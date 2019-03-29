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
hostname_components = hostname.split(".", -1)
machine_name = hostname_components[0]
domain_name = hostname_components[1...3].join(".")
app_dir = Pathname.new("apps").join(hostname.split(".", -1)[1]).expand_path(user_home)

route53_info = percolator.find("dns-aws", :hostname, hostname)["aws-route53"]

hostname_domain_names = ([domain_name] + (route53_info[domain_name]["alternates"] || [])).map do |domain_name|
  ["#{machine_name}.#{domain_name}", domain_name]
end

chef_gem "install `percolate` for #{recipe_name}" do
  package_name "percolate"
  compile_time true
  action :install
end

chef_gem "install `bundler` for #{recipe_name}" do
  package_name "bundler"
  compile_time true
  action :install
end

package "nginx" do
  action :install
end

package "libpq-dev" do
  action :install
end

package "libsqlite3-dev" do
  action :install
end

package "libssl-dev" do
  action :install
end

service "nginx" do
  action :nothing
end

template "/lib/systemd/system/unicorn.service" do
  source "unicorn.service.erb"
  owner "root"
  group "root"
  mode 0644
  variables(
      rbenv_version: Pathname.new("../..").expand_path(recipe.ruby_interpreter_path).basename.to_s,
      app_root: app_dir.join("current").to_s,
      original_user: recipe.original_user
  )
  notifies :create, "link[/etc/systemd/system/multi-user.target.wants/unicorn.service]", :immediately
  action :create
end

link "/etc/systemd/system/multi-user.target.wants/unicorn.service" do
  to "/lib/systemd/system/unicorn.service"
  owner "root"
  group "root"
  action :nothing
end

[
    app_dir.parent,
    app_dir,
    app_dir.join("releases"),
    app_dir.join("shared"),
    app_dir.join("shared", "config"),
    app_dir.join("shared", "log"),
    app_dir.join("shared", "pids"),
    app_dir.join("shared", "system")
].each do |dir|
  directory dir.to_s do
    owner recipe.original_user
    group recipe.original_group
    mode 0755
    action :create
  end
end

nodejs_npm "bower" do
  action :install
end

nodejs_npm "yarn" do
  action :install
end

key_info = percolator.find("keys-aws", :hostname, hostname)["aws"]
access_key = key_info["access_key"]
secret_key = key_info["secret_key"]
region = key_info["region"]

deploy_scope = percolator.find("rails-deploy", :hostname, hostname)["deploy_scope"]

domain_name_ssl_infos = percolator.find("certificates", :hostname, hostname)&.dig("ssl") || {}
ssl_dir = Pathname.new("/etc/ssl/private")

# Is there SSL information for this hostname? If so, we need to do more work.
domain_name_ssl_infos.each do |domain_name, ssl_info|
  file ssl_dir.join("chef-#{domain_name}.crt").to_s do
    owner "root"
    group "root"
    mode 0640
    content (ssl_info["certificate"] + ssl_info["ca_certificate"]).join("\n") + "\n"
    sensitive true
    action :create
  end

  file ssl_dir.join("chef-#{domain_name}.key").to_s do
    owner "root"
    group "root"
    mode 0640
    content ssl_info["key"].join("\n") + "\n"
    sensitive true
    action :create
  end
end

template "/etc/nginx/sites-available/default" do
  source "rails-default.erb"
  owner "root"
  group "root"
  mode 0644
  variables(
      app_root: app_dir.join("current", "public").to_s,
      ssl_dir: ssl_dir.to_s,
      domain_ssl_infos: domain_name_ssl_infos,
      hostname_domain_names: hostname_domain_names
  )
  notifies :restart, "service[nginx]", :immediately
  action :create
end

template app_dir.join("shared", "config", "action_mailer.yml").to_s do
  source "action_mailer.yml.erb"
  owner recipe.original_user
  group recipe.original_group
  mode 0644
  variables(hostname: node.name)
  action :create
end

if airbrake_info = percolator.find("monitoring-airbrake", :hostname, hostname)&.dig("airbrake")
  template app_dir.join("shared", "config", "airbrake.yml").to_s do
    source "airbrake.yml.erb"
    owner recipe.original_user
    group recipe.original_group
    mode 0644
    variables(
        project_id: airbrake_info["project_id"],
        project_key: airbrake_info["project_key"]
    )
    action :create
  end
end

template app_dir.join("shared", "config", "aws.yml").to_s do
  source "aws.yml.erb"
  owner recipe.original_user
  group recipe.original_group
  mode 0644
  variables(
      access_key: access_key,
      secret_key: secret_key,
      region: region
  )
  action :create
end

if google_analytics_id = percolator.find("analytics-google", :hostname, hostname)&.dig("google_analytics_id")
  template app_dir.join("shared", "config", "google_analytics.yml").to_s do
    source "google_analytics.yml.erb"
    owner recipe.original_user
    group recipe.original_group
    mode 0644
    variables(id: google_analytics_id)
    action :create
  end
end

template app_dir.join("shared", "config", "secrets.yml").to_s do
  source "secrets.yml.erb"
  owner recipe.original_user
  group recipe.original_group
  mode 0644
  variables(rails_secret_key: recipe.percolator.find("rails-secret_key", :hostname, hostname)["rails_secret_key"])
  action :create
end

template app_dir.join("shared", "config", "deploy.yml").to_s do
  source "deploy.yml.erb"
  owner recipe.original_user
  group recipe.original_group
  mode 0644
  variables(
      scope: deploy_scope || "default"
  )
  action :create
end

template app_dir.join("shared", "config", "webpacker.yml").to_s do
  source "webpacker.yml.erb"
  owner recipe.original_user
  group recipe.original_group
  mode 0644
  variables(
      public_output_path: (deploy_scope && (Pathname.new("assets") + deploy_scope + "packs")).to_s || "packs"
  )
  action :create
end
