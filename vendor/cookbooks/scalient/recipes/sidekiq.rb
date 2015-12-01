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
  compile_time true
  action :install
end

template "/lib/systemd/system/sidekiq.service" do
  source "sidekiq.service.erb"
  owner "root"
  group "root"
  mode 0644
  variables(rbenv_version: Pathname.new("../..").expand_path(recipe.ruby_interpreter_path).basename.to_s,
            app_root: app_dir.join("current"),
            original_user: recipe.original_user)
  notifies :create, "link[/etc/systemd/system/multi-user.target.wants/sidekiq.service]", :immediately
  action :create
end

link "/etc/systemd/system/multi-user.target.wants/sidekiq.service" do
  to "/lib/systemd/system/sidekiq.service"
  owner "root"
  group "root"
  action :nothing
end

# Redis is used by Sidekiq.
package "redis-server" do
  action :install
end
