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
