# -*- coding: utf-8 -*-
#
# Copyright 2012-2014 Scalient LLC
# All rights reserved.

require "pathname"

class << self
  include Scalient::Util
end

recipe = self
user_home = Dir.home(recipe.original_user)
hostname = node.name
app_dir = Pathname.new("apps").join(hostname.split(".", -1)[1]).expand_path(user_home)

chef_gem "install `bundler` for #{recipe_name}" do
  package_name "bundler"
  action :nothing
end.action(:install)

template "/etc/init/sidekiq.conf" do
  source "sidekiq.conf.erb"
  owner "root"
  group "root"
  mode 0644
  variables(rbenv_version: Pathname.new("../..").expand_path(recipe.ruby_interpreter_path).basename.to_s,
            app_root: app_dir.join("current"),
            original_user: recipe.original_user)
  notifies :create, "link[/etc/init.d/sidekiq]", :immediately
  action :nothing
end.action(:create)

link "/etc/init.d/sidekiq" do
  to "/lib/init/upstart-job"
  owner "root"
  group "root"
  action :nothing
end

# Redis is used by Sidekiq.
package "redis-server" do
  action :nothing
end.action(:install)
