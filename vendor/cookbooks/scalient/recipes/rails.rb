# -*- coding: utf-8 -*-
#
# Copyright 2012 Scalient LLC

class << self
  include Scalient::Utils
end

require "pathname"

recipe = self

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
  variables(:app_root => Pathname.new("apps/scalient/current/public").expand_path(Dir.home(recipe.original_user)).to_s,
            :passenger_ruby => recipe.ruby_interpreter_path)
  notifies :restart, "service[nginx]", :immediately
  action :nothing
end.action(:create)

service "nginx" do
  action :nothing
end
