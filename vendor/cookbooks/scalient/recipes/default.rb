# -*- coding: utf-8 -*-
#
# Copyright 2012-2014 Scalient LLC
# All rights reserved.

require "pathname"
require "shellwords"

class << self
  include Percolate
  include Scalient::Util
end

recipe = self
prefix_dir = Pathname.new("/usr/local")
hostname = node.name

chef_gem "install `fog` for #{recipe_name}" do
  package_name "fog"
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

require "fog"

key_info = percolator.find("keys-aws", :hostname, hostname)["aws"]
access_key = key_info["access_key"]
secret_key = key_info["secret_key"]

compute = Fog::Compute.new({provider: "aws",
                            aws_access_key_id: access_key,
                            aws_secret_access_key: secret_key})
compute.create_tags([node["ec2"]["instance_id"]], "Name" => hostname)

template "/etc/init/chef-client.conf" do
  source "chef-client.conf.erb"
  owner "root"
  group "root"
  mode 0644
  variables(rbenv_version: Pathname.new("../..").expand_path(recipe.ruby_interpreter_path).basename.to_s,
            prefix: prefix_dir.to_s)
  notifies :create, "link[/etc/init.d/chef-client]", :immediately
  action :create
end

link "/etc/init.d/chef-client" do
  to "/lib/init/upstart-job"
  owner "root"
  group "root"
  action :nothing
end
