# -*- coding: utf-8 -*-
#
# Copyright 2012 Scalient LLC

class << self
  include Scalient::Utils
end

require "pathname"

recipe = self
user_home = Dir.home(recipe.original_user)
app_dir = Pathname.new("apps").join(node.name.split(".", -1)[1]).expand_path(user_home)

apt_repository "passenger-nginx" do
  uri "http://ppa.launchpad.net/brightbox/passenger-nginx/ubuntu"
  distribution node["lsb"]["codename"]
  components ["main"]
  keyserver "keyserver.ubuntu.com"
  key "C3173AA6"
  cache_rebuild true
  action :nothing
end.action(:add)

package "nginx-full" do
  action :nothing
end.action(:install)

package "libpq-dev" do
  action :nothing
end.action(:install)

package "libsqlite3-dev" do
  action :nothing
end.action(:install)

gem_package "passenger" do
  gem_binary "gem"
  action :nothing
end.action(:install)

# UGLY HACK: We need to install two versions each of rack and rake to induce lazy activation by RubyGems. Otherwise,
# version conflicts with Bundler's Gemfile.lock may result.

gem_package "rack" do
  gem_binary "gem"
  action :nothing
end.action(:install)

gem_package "rack-redundant" do
  package_name "rack"
  gem_binary "gem"
  version "1.4.4"
  action :nothing
end.action(:install)

gem_package "rake" do
  gem_binary "gem"
  action :nothing
end.action(:install)

gem_package "rake-redundant" do
  package_name "rake"
  gem_binary "gem"
  version "10.0.2"
  action :nothing
end.action(:install)

template "/etc/nginx/sites-available/default" do
  source "default.erb"
  owner "root"
  group "root"
  mode 0644
  variables(:app_root => app_dir.join("current", "public").to_s,
            :passenger_ruby => recipe.ruby_interpreter_path)
  notifies :restart, "service[nginx]", :immediately
  action :nothing
end.action(:create)

service "nginx" do
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
  variables(:api_key => data_bag_item("monitoring", "airbrake")[node.name])
  action :nothing
end.action(:create)

template app_dir.join("shared", "config", "aws.yml").to_s do
  source "aws.yml.erb"
  owner recipe.original_user
  group recipe.original_group
  mode 0644
  variables(:access_key => data_bag_item("keys", "aws")["access_key"],
            :secret_key => data_bag_item("keys", "aws")["secret_key"])
  action :nothing
end.action(:create)

template app_dir.join("shared", "config", "google_analytics.yml").to_s do
  source "google_analytics.yml.erb"
  owner recipe.original_user
  group recipe.original_group
  mode 0644
  variables(:id => data_bag_item("analytics", "google")[node.name])
  action :nothing
end.action(:create)
