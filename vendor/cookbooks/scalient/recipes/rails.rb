# -*- coding: utf-8 -*-
#
# Copyright 2012-2014 Scalient LLC

class << self
  include Scalient::Util
end

include_recipe "scalient::initialize"
include_recipe "percolate"

require "pathname"

recipe = self
user_home = Dir.home(recipe.original_user)
hostname = node.name
app_dir = Pathname.new("apps").join(hostname.split(".", -1)[1]).expand_path(user_home)

key_info = percolator.find("keys-aws", :hostname, hostname)["aws"]
access_key = key_info["access_key"]
secret_key = key_info["secret_key"]

package "nginx" do
  action :nothing
end.action(:install)

package "libpq-dev" do
  action :nothing
end.action(:install)

package "libsqlite3-dev" do
  action :nothing
end.action(:install)

package "nodejs" do
  action :nothing
  notifies :create, "link[/usr/bin/node]", :immediately
end.action(:install)

link "/usr/bin/node" do
  to "nodejs"
  owner "root"
  group "root"
  action :nothing
end

template "/etc/nginx/sites-available/default" do
  source "default.erb"
  owner "root"
  group "root"
  mode 0644
  variables(:app_root => app_dir.join("current", "public").to_s)
  notifies :restart, "service[nginx]", :immediately
  action :nothing
end.action(:create)

service "nginx" do
  action :nothing
end

template "/etc/init/unicorn.conf" do
  source "unicorn.conf.erb"
  owner "root"
  group "root"
  mode 0644
  variables(:rbenv_version => Pathname.new("../..").expand_path(recipe.ruby_interpreter_path).basename.to_s,
            :app_root => app_dir.join("current").to_s,
            :original_user => recipe.original_user)
  notifies :create, "link[/etc/init.d/unicorn]", :immediately
  action :nothing
end.action(:create)

link "/etc/init.d/unicorn" do
  to "/lib/init/upstart-job"
  owner "root"
  group "root"
  action :nothing
end

[app_dir.parent,
 app_dir,
 app_dir.join("releases"),
 app_dir.join("shared"),
 app_dir.join("shared", "config"),
 app_dir.join("shared", "log"),
 app_dir.join("shared", "pids"),
 app_dir.join("shared", "system")].each do |dir|
  directory dir.to_s do
    owner recipe.original_user
    group recipe.original_group
    mode 0755
    action :nothing
  end.action(:create)
end

template app_dir.join("shared", "config", "airbrake.yml").to_s do
  source "airbrake.yml.erb"
  owner recipe.original_user
  group recipe.original_group
  mode 0644
  variables(:api_key => recipe.percolator.find("monitoring-airbrake", :hostname, hostname)["airbrake_api_key"])
  action :nothing
end.action(:create)

template app_dir.join("shared", "config", "aws.yml").to_s do
  source "aws.yml.erb"
  owner recipe.original_user
  group recipe.original_group
  mode 0644
  variables(:access_key => access_key,
            :secret_key => secret_key)
  action :nothing
end.action(:create)

template app_dir.join("shared", "config", "google_analytics.yml").to_s do
  source "google_analytics.yml.erb"
  owner recipe.original_user
  group recipe.original_group
  mode 0644
  variables(:id => recipe.percolator.find("analytics-google", :hostname, hostname)["google_analytics_id"])
  action :nothing
end.action(:create)
