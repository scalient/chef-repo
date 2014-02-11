# -*- coding: utf-8 -*-
#
# Copyright 2012-2014 Scalient LLC

class << self
  include Scalient::Util
end

include_recipe "scalient::initialize"

require "pathname"

recipe = self
user_home = Dir.home(recipe.original_user)
hostname = node.name
app_dir = Pathname.new("apps").join(hostname.split(".", -1)[1]).expand_path(user_home)

template "/etc/init/sidekiq.conf" do
  source "sidekiq.conf.erb"
  owner "root"
  group "root"
  mode 0644
  variables(:rbenv_version => Pathname.new("../..").expand_path(recipe.ruby_interpreter_path).basename.to_s,
            :app_root => app_dir.join("current"),
            :original_user => recipe.original_user)
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
