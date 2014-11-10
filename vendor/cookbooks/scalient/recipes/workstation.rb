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

def generate_config_templates(data_bag_name, work_dir)
  percolator.find_facet(data_bag_name, :project_directory).fixtures.each_key do |dir_name|
    config_dir = work_dir.join(dir_name, "config")
    yield percolator.find(data_bag_name, :project_directory, dir_name), config_dir if config_dir.directory?
  end
end

chef_gem "install `percolate` for #{recipe_name}" do
  package_name "percolate"
  action :nothing
end.action(:install)

workstation_info = data_bag_item("init-workstation", "default")[node.name]

if !workstation_info.nil?
  work_dir = Pathname.new(workstation_info["work_dir"]).expand_path(user_home)

  ruby_block "find Percolate info for #{recipe_name}" do
    block do
      recipe.generate_config_templates("rails-action_mailer", work_dir) do |entity, config_dir|
        recipe.template config_dir.join("action_mailer.yml").to_s do
          source "action_mailer.yml.erb"
          owner recipe.original_user
          group recipe.original_group
          mode 0644
          variables(hostname: "localhost")
          action :nothing
        end.action(:create)
      end

      recipe.generate_config_templates("rails-secret_key", work_dir) do |entity, config_dir|
        recipe.template config_dir.join("secrets.yml").to_s do
          source "secrets.yml.erb"
          owner recipe.original_user
          group recipe.original_group
          mode 0644
          variables(rails_secret_key: entity["rails_secret_key"])
          action :nothing
        end.action(:create)
      end

      recipe.generate_config_templates("monitoring-airbrake", work_dir) do |entity, config_dir|
        recipe.template config_dir.join("airbrake.yml").to_s do
          source "airbrake.yml.erb"
          owner recipe.original_user
          group recipe.original_group
          mode 0644
          variables(api_key: entity["airbrake_api_key"])
          action :nothing
        end.action(:create)
      end

      recipe.generate_config_templates("analytics-google", work_dir) do |entity, config_dir|
        recipe.template config_dir.join("google_analytics.yml").to_s do
          source "google_analytics.yml.erb"
          owner recipe.original_user
          group recipe.original_group
          mode 0644
          variables(id: entity["google_analytics_id"])
          action :nothing
        end.action(:create)
      end

      recipe.generate_config_templates("keys-aws", work_dir) do |entity, config_dir|
        recipe.template config_dir.join("aws.yml").to_s do
          source "aws.yml.erb"
          owner recipe.original_user
          group recipe.original_group
          mode 0644
          variables(access_key: entity["aws"]["access_key"],
                    secret_key: entity["aws"]["secret_key"])
          action :nothing
        end.action(:create)
      end
    end

    action :nothing
  end.action(:run)
end
