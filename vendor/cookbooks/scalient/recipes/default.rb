# -*- coding: utf-8 -*-
#
# Copyright 2012-2014 Scalient LLC

class << self
  include Scalient::Util
end

include_recipe "scalient::initialize"
include_recipe "percolate"

require "pathname"
require "shellwords"

recipe = self
prefix_dir = Pathname.new("/usr/local")
has_rabbitmq_server = Pathname.new("/usr/sbin/rabbitmqctl").executable?
hostname = node.name

key_info = percolator.find("keys-aws", :hostname, hostname)["aws"]
access_key = key_info["access_key"]
secret_key = key_info["secret_key"]

cap_ops_recreate_rabbit_queue "reload-hostname" do
  action :nothing
end

template "/etc/hosts" do
  source "hosts.erb"
  owner "root"
  group "root"
  mode 0644
  variables(:fqdn => hostname,
            :hostname => hostname.split(".", -1)[0])
  action :nothing
end.action(:create)

template "/etc/hostname" do
  source "hostname.erb"
  owner "root"
  group "root"
  mode 0644
  variables(:hostname => hostname.split(".", -1)[0])
  notifies :run, "cap_ops_recreate_rabbit_queue[reload-hostname]", :immediately if has_rabbitmq_server
  notifies :run, "bash[hostname]", :immediately if !has_rabbitmq_server
  action :nothing
end.action(:create)

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
  action :nothing
end.action(:create)

ruby_block "set-ec2-instance-name" do
  block do
    require "fog"

    compute = Fog::Compute.new({:provider => "aws",
                                :aws_access_key_id => access_key,
                                :aws_secret_access_key => secret_key})
    compute.create_tags([node["ec2"]["instance_id"]], "Name" => hostname)
  end
end

template "/etc/init/chef-client.conf" do
  source "chef-client.conf.erb"
  owner "root"
  group "root"
  mode 0644
  variables(:rbenv_version => Pathname.new("../..").expand_path(recipe.ruby_interpreter_path).basename.to_s,
            :prefix => prefix_dir.to_s)
  notifies :create, "link[/etc/init.d/chef-client]", :immediately
  action :nothing
end.action(:create)

link "/etc/init.d/chef-client" do
  to "/lib/init/upstart-job"
  owner "root"
  group "root"
  action :nothing
end
