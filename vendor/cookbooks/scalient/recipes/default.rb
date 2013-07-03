# -*- coding: utf-8 -*-
#
# Copyright 2012 Scalient LLC

class << self
  include Scalient::Utils
end

require "pathname"
require "shellwords"

recipe = self
prefix_dir = Pathname.new("/usr/local")
gemfile = Pathname.new("client/Gemfile.d/Gemfile-scalient").expand_path(Dir.home("chef"))
has_rabbitmq_server = Pathname.new("/usr/sbin/rabbitmqctl").executable?
org_name = node.name.split(".", -1)[1]

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
                                :aws_access_key_id => data_bag_item("keys", "aws")[org_name]["access_key"],
                                :aws_secret_access_key => data_bag_item("keys", "aws")[org_name]["secret_key"]})
    compute.create_tags([node["ec2"]["instance_id"]], "Name" => node.name)
  end

  action :nothing
end.action(:create)

[prefix_dir.join("etc", "chef-solo"),
 prefix_dir.join("var", "chef-solo"),
 prefix_dir.join("var", "chef-solo", "data_bags"),
 prefix_dir.join("var", "chef-solo", "roles"),
 prefix_dir.join("var", "log", "chef-solo")].each do |dir|
  directory dir.to_s do
    owner "chef"
    group "chef"
    mode 0755
    action :nothing
  end.action(:create)
end

template prefix_dir.join("etc", "chef-solo", "solo.rb").to_s do
  source "solo.rb.erb"
  owner "chef"
  group "chef"
  mode 0644
  variables(:prefix => prefix_dir.to_s)
  action :nothing
end.action(:create)

cookbook_file prefix_dir.join("etc", "chef-solo", "node.json").to_s do
  source "node.json"
  owner "chef"
  group "chef"
  mode 0644
  action :nothing
end.action(:create)

cookbook_file prefix_dir.join("var", "chef-solo", "roles", "init.json").to_s do
  source "init.json"
  owner "chef"
  group "chef"
  mode 0644
  action :nothing
end.action(:create)

[["dns", "aws"],
 ["keys", "aws"]].each do |tuple|
  directory prefix_dir.join("var", "chef-solo", "data_bags", tuple[0]).to_s do
    owner "chef"
    group "chef"
    mode 0755
    action :nothing
  end.action(:create)

  file prefix_dir.join("var", "chef-solo", "data_bags", tuple[0], "#{tuple[1]}.json").to_s do
    content JSON.pretty_generate(data_bag_item(tuple[0], tuple[1]).raw_data)
    owner "chef"
    group "chef"
    mode 0600
    action :nothing
  end.action(:create)
end

template "/etc/init/chef-solo.conf" do
  source "chef-solo.conf.erb"
  owner "root"
  group "root"
  mode 0644
  variables(:rbenv_version => Pathname.new("../..").expand_path(recipe.ruby_interpreter_path).basename.to_s,
            :prefix => prefix_dir.to_s)
  notifies :create, "link[/etc/init.d/chef-solo]", :immediately
  action :nothing
end.action(:create)

link "/etc/init.d/chef-solo" do
  to "/lib/init/upstart-job"
  owner "root"
  group "root"
  action :nothing
end
