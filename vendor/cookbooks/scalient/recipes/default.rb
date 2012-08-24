# -*- coding: utf-8 -*-
#
# Copyright 2012 Scalient LLC

require "pathname"

gemfile = Pathname.new("client/Gemfile.d/Gemfile-scalient").expand_path(Dir.home("chef"))
has_rabbitmq_server = Pathname.new("/usr/sbin/rabbitmqctl").executable?

cap_ops_gemfile_fragment gemfile.to_s do
  source gemfile.basename.to_s
  action :nothing
end.action(:create)

cap_ops_recreate_rabbit_queue "reload-hostname" do
  action :nothing
end

template "/etc/hosts" do
  source "hosts.erb"
  owner "root"
  group "root"
  mode 0644
  variables(:fqdn => node.name,
            :hostname => node.name.split(".", -1)[0])
  action :nothing
end.action(:create)

template "/etc/hostname" do
  source "hostname.erb"
  owner "root"
  group "root"
  mode 0644
  variables(:hostname => node.name.split(".", -1)[0])
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
                                :aws_access_key_id => data_bag_item("keys", "aws")["access_key"],
                                :aws_secret_access_key => data_bag_item("keys", "aws")["secret_key"]})
    compute.create_tags([node["ec2"]["instance_id"]], "Name" => node.name)
  end

  action :nothing
end.action(:create)
