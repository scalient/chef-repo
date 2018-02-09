# -*- coding: utf-8 -*-
#
# Copyright 2012-2018 Scalient LLC
# All rights reserved.

require "etc"
require "fileutils"
require "pathname"
require "shellwords"

class << self
  include Percolate
  include Scalient::Util
end

recipe = self
prefix_dir = Pathname.new("/usr/local")
hostname = node.name

chef_gem "install `fog-aws` for #{recipe_name}" do
  package_name "fog-aws"
  compile_time true
  action :install
end

chef_gem "install `percolate` for #{recipe_name}" do
  package_name "percolate"
  compile_time true
  action :install
end

template "/etc/hosts" do
  source "hosts.erb"
  owner "root"
  group "root"
  mode 0644
  variables(fqdn: hostname,
            hostname: hostname.split(".", -1)[0])
  action :create
end

template "/etc/hostname" do
  source "hostname.erb"
  owner "root"
  group "root"
  mode 0644
  variables(hostname: hostname.split(".", -1)[0])
  notifies :run, "bash[hostname]", :immediately
  action :create
end

bash "hostname" do
  user "root"
  group "root"
  code <<EOF
exec -- hostname -F /etc/hostname
EOF
  action :nothing
end

cookbook_file "/etc/ssh/ssh_known_hosts" do
  source "ssh_known_hosts"
  owner "root"
  group "root"
  mode 0644
  action :create
end

require "fog/aws"

key_info = percolator.find("keys-aws", :hostname, hostname)["aws"]
access_key = key_info["access_key"]
secret_key = key_info["secret_key"]

compute = Fog::Compute.new({provider: "aws",
                            aws_access_key_id: access_key,
                            aws_secret_access_key: secret_key})
compute.create_tags([node["ec2"]["instance_id"]], "Name" => hostname)

template "/lib/systemd/system/chef-client.service" do
  source "chef-client.service.erb"
  owner "root"
  group "root"
  mode 0644
  variables(rbenv_version: Pathname.new("../..").expand_path(recipe.ruby_interpreter_path).basename.to_s,
            prefix: prefix_dir.to_s)
  notifies :create, "link[/etc/systemd/system/multi-user.target.wants/chef-client.service]", :immediately
  action :create
end

link "/etc/systemd/system/multi-user.target.wants/chef-client.service" do
  to "/lib/systemd/system/chef-client.service"
  owner "root"
  group "root"
  action :nothing
end

# The `ntpd` service prevents server clock skew.
package "ntp" do
  action :install
end

# Remove potentially root-owned `~/.bundle` directories resulting from the `chef_gem` resource, which uses Bundler under
# the hood.
ruby_block "remove root-owned ~/.bundle directory" do
  block do
    original_user_entity = Etc.getpwnam(recipe.original_user)

    begin
      dir = recipe.original_user_home + ".bundle"
      dir_stat = dir.stat

      FileUtils.rm_rf(dir) \
        if dir_stat.uid != original_user_entity.uid || dir_stat.gid != original_user_entity.gid
    rescue Errno::ENOENT
      # Don't do anything if the directory wasn't found.
    end
  end

  action :run
end
