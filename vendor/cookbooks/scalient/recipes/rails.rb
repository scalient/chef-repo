# -*- coding: utf-8 -*-
#
# Copyright 2012-2014 Scalient LLC
# All rights reserved.

require "pathname"

class << self
  include Percolate
  include Scalient::Util
end

recipe = self
user_home = Dir.home(recipe.original_user)
hostname = node.name
domain_name = hostname.split(".", -1)[1...3].join(".")
app_dir = Pathname.new("apps").join(hostname.split(".", -1)[1]).expand_path(user_home)

chef_gem "install `percolate` for #{recipe_name}" do
  package_name "percolate"
  action :nothing
end.action(:install)

chef_gem "install `bundler` for #{recipe_name}" do
  package_name "bundler"
  action :nothing
end.action(:install)

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
end.action(:install)

link "/usr/bin/node" do
  to "/usr/bin/nodejs"
  owner "root"
  group "root"
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
  variables(rbenv_version: Pathname.new("../..").expand_path(recipe.ruby_interpreter_path).basename.to_s,
            app_root: app_dir.join("current").to_s,
            original_user: recipe.original_user)
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

ruby_block "find Percolate info for #{recipe_name}" do
  block do
    key_info = recipe.percolator.find("keys-aws", :hostname, hostname)["aws"]
    access_key = key_info["access_key"]
    secret_key = key_info["secret_key"]

    ssl_info = recipe.percolator.find("certificates", :hostname, hostname)
    ssl_info &&= ssl_info["ssl"] && ssl_info["ssl"][domain_name]
    ssl_dir = Pathname.new("/etc/ssl/private")

    # Is there SSL information for this hostname? If so, we need to do more work.
    if !ssl_info.nil?
      recipe.file ssl_dir.join("chef-#{domain_name}.crt").to_s do
        owner "root"
        group "root"
        mode 0640
        content (ssl_info["certificate"] + ssl_info["ca_certificate"]).join("\n") + "\n"
        action :nothing
      end.action(:create)

      recipe.file ssl_dir.join("chef-#{domain_name}.key").to_s do
        owner "root"
        group "root"
        mode 0640
        content ssl_info["key"].join("\n") + "\n"
        action :nothing
      end.action(:create)
    end

    recipe.template "/etc/nginx/sites-available/default" do
      source "default.erb"
      owner "root"
      group "root"
      mode 0644
      variables(app_root: app_dir.join("current", "public").to_s,
                use_ssl: !ssl_info.nil?,
                ssl_dir: ssl_dir.to_s,
                domain_name: domain_name)
      notifies :restart, "service[nginx]", :immediately
      action :nothing
    end.action(:create)

    recipe.template app_dir.join("shared", "config", "action_mailer.yml").to_s do
      source "action_mailer.yml.erb"
      owner recipe.original_user
      group recipe.original_group
      mode 0644
      variables(hostname: node.name)
      action :nothing
    end.action(:create)

    recipe.template app_dir.join("shared", "config", "airbrake.yml").to_s do
      source "airbrake.yml.erb"
      owner recipe.original_user
      group recipe.original_group
      mode 0644
      variables(api_key: recipe.percolator.find("monitoring-airbrake", :hostname, hostname)["airbrake_api_key"])
      action :nothing
    end.action(:create)

    recipe.template app_dir.join("shared", "config", "aws.yml").to_s do
      source "aws.yml.erb"
      owner recipe.original_user
      group recipe.original_group
      mode 0644
      variables(access_key: access_key,
                secret_key: secret_key)
      action :nothing
    end.action(:create)

    recipe.template app_dir.join("shared", "config", "google_analytics.yml").to_s do
      source "google_analytics.yml.erb"
      owner recipe.original_user
      group recipe.original_group
      mode 0644
      variables(id: recipe.percolator.find("analytics-google", :hostname, hostname)["google_analytics_id"])
      action :nothing
    end.action(:create)

    recipe.template app_dir.join("shared", "config", "secrets.yml").to_s do
      source "secrets.yml.erb"
      owner recipe.original_user
      group recipe.original_group
      mode 0644
      variables(rails_secret_key: recipe.percolator.find("rails-secret_key", :hostname, hostname)["rails_secret_key"])
      action :nothing
    end.action(:create)
  end

  action :nothing
end.action(:run)
