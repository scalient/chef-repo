# -*- coding: utf-8 -*-
#
# Copyright 2012-2014 Scalient LLC
# All rights reserved.

require "pathname"

class << self
  include Percolate
  include Scalient::Util
end

chef_gem "install `fog-aws` for #{recipe_name}" do
  package_name "fog-aws"
  compile_time true
  action :install
end

chef_gem "install `percolate` for #{recipe_name}" do
  package_name "percolate"
  compile_time true
  action :install
end

require "fog/aws"

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

apt_repository "nodesource" do
  uri "https://deb.nodesource.com/node_13.x"
  components ["main"]
  key "68576280"
  action :add
end

package "nodejs" do
  action :install
end

package "chromium-browser" do
  action :install
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

template "/lib/systemd/system/chromium-browser.service" do
  source "chromium-browser.service.erb"
  owner "root"
  group "root"
  mode 0644
  variables(
      app_root: app_dir.join("current").to_s,
      original_user: recipe.original_user
  )
  notifies :create, "link[/etc/systemd/system/multi-user.target.wants/chromium-browser.service]", :immediately
  action :create
end

link "/etc/systemd/system/multi-user.target.wants/chromium-browser.service" do
  to "/lib/systemd/system/chromium-browser.service"
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
    app_dir.join("shared", "system"),
    app_dir.join("shared", "public"),
    app_dir.join("shared", "public", "assets")
].each do |dir|
  directory dir.to_s do
    owner recipe.original_user
    group recipe.original_group
    mode 0755
    action :create
  end
end

npm_package "bower" do
  action :install
end

npm_package "yarn" do
  action :install
end

key_info = percolator.find("keys-aws", :hostname, hostname)["aws"]
access_key = key_info["access_key"]
secret_key = key_info["secret_key"]
region = key_info["region"]

deploy_scope = percolator.find("rails-deploy", :hostname, hostname)["deploy_scope"]

elb_client = Fog::AWS::ELB.new(
    aws_access_key_id: access_key, aws_secret_access_key: secret_key,
    # Important: This queries against ELBv2, aka our ALBs.
    version: "2015-12-01"
)

begin
  arn = elb_client.describe_load_balancers(Fog::AWS.indexed_param("Names.member", [deploy_scope])).
      body["DescribeLoadBalancersResult"]["LoadBalancerDescriptions"][0]["LoadBalancerArn"]

  # The load balancer tags serve as meta information that inform application servers.
  # TODO: Ugh, use fog-aws' private API because ELBv2 isn't well-supported.
  load_balancer_meta = elb_client.send(:request, {
      "Action" => "DescribeTags",
      parser: Fog::Parsers::AWS::ELB::TagListParser.new
  }.
      merge(Fog::AWS.indexed_param("ResourceArns.member", [arn]))).
      body["DescribeTagsResult"]["LoadBalancers"][0]["Tags"]
rescue Fog::AWS::ELB::NotFound
  load_balancer_meta = {}
end

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

if elasticsearch_info = percolator.find("elasticsearch", :hostname, hostname)["elasticsearch"]
  template app_dir.join("shared/config/elasticsearch.yml").to_s do
    source "elasticsearch.yml.erb"
    owner recipe.original_user
    group recipe.original_group
    mode 0644
    variables(
        url: elasticsearch_info["url"],
        cloud_id: elasticsearch_info["cloud_id"],
        user: elasticsearch_info["user"],
        password: elasticsearch_info["password"]
    )
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
      scope: deploy_scope || "default",
      load_balancer_meta: load_balancer_meta
  )
  action :create
end

# Since we no longer compile assets to `public/assets`, touch this magical file to help ensure that the Capistrano
# deployment goes through.
file app_dir.join("shared", "public", "assets", ".sprockets-manifest.json").to_s do
  owner recipe.original_user
  group recipe.original_group
  mode 0644
  action :create_if_missing
end
