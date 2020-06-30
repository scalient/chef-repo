# -*- coding: utf-8 -*-
#
# Copyright 2012-2017 Scalient LLC
# All rights reserved.

require "pathname"

class << self
  include Percolate
  include Scalient::Util
end

recipe = self
user_home = Dir.home(recipe.original_user)

def generate_config_templates(data_bag_name, work_dir)
  (percolator.find_facet(data_bag_name, :project_directory)&.fixtures || {}).each_key do |dir_name|
    config_dir = work_dir.join(dir_name, "config")
    yield percolator.find(data_bag_name, :project_directory, dir_name), config_dir if config_dir.directory?
  end
end

chef_gem "install `percolate` for #{recipe_name}" do
  package_name "percolate"
  compile_time true
  action :install
end

workstation_info = data_bag_item("workstations", "default")[node.name]

if !workstation_info.nil?
  work_dir = Pathname.new(workstation_info["work_dir"]).expand_path(user_home)

  generate_config_templates("rails-action_mailer", work_dir) do |entity, config_dir|
    template config_dir.join("action_mailer.yml").to_s do
      source "action_mailer.yml.erb"
      owner recipe.original_user
      group recipe.original_group
      mode 0644
      variables(hostname: "localhost", port: 3000)
      action :create
    end
  end

  generate_config_templates("rails-secret_key", work_dir) do |entity, config_dir|
    template config_dir.join("secrets.yml").to_s do
      source "secrets.yml.erb"
      owner recipe.original_user
      group recipe.original_group
      mode 0644
      variables(rails_secret_key: entity["rails_secret_key"])
      action :create
    end
  end

  generate_config_templates("monitoring-airbrake", work_dir) do |entity, config_dir|
    if airbrake_info = entity["airbrake"]
      template config_dir.join("airbrake.yml").to_s do
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
  end

  generate_config_templates("analytics-google", work_dir) do |entity, config_dir|
    if google_analytics_id = entity["google_analytics_id"]
      template config_dir.join("google_analytics.yml").to_s do
        source "google_analytics.yml.erb"
        owner recipe.original_user
        group recipe.original_group
        mode 0644
        variables(id: google_analytics_id)
        action :create
      end
    end
  end

  generate_config_templates("elasticsearch", work_dir) do |entity, config_dir|
    if elasticsearch_info = entity["elasticsearch"]
      template config_dir.join("elasticsearch.yml").to_s do
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
  end

  generate_config_templates("keys-aws", work_dir) do |entity, config_dir|
    template config_dir.join("aws.yml").to_s do
      source "aws.yml.erb"
      owner recipe.original_user
      group recipe.original_group
      mode 0644
      variables(
          access_key: entity["aws"]["access_key"],
          secret_key: entity["aws"]["secret_key"],
          region: entity["aws"]["region"]
      )
      action :create
    end
  end

  generate_config_templates("communication-twilio", work_dir) do |entity, config_dir|
    if twilio_info = entity["twilio"]
      template config_dir.join("twilio.yml").to_s do
        source "twilio.yml.erb"
        owner recipe.original_user
        group recipe.original_group
        mode 0644
        variables(
            account_sid: twilio_info["account_sid"],
            auth_token: twilio_info["auth_token"],
            messaging_service_sid: twilio_info["messaging_service_sid"]
        )
        action :create
      end
    end
  end

  generate_config_templates("rails-deploy", work_dir) do |entity, config_dir|
    deploy_scope = entity["deploy_scope"]

    template config_dir.join("deploy.yml").to_s do
      source "deploy.yml.erb"
      owner recipe.original_user
      group recipe.original_group
      mode 0644
      variables(
          scope: deploy_scope || "default"
      )
      action :create
    end
  end
end
