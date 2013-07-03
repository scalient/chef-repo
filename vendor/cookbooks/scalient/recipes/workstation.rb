# -*- coding: utf-8 -*-
#
# Copyright 2012 Scalient LLC

class << self
  include Scalient::Utils
end

require "pathname"

recipe = self
user_home = Dir.home(recipe.original_user)

# Attempts to match hostnames of the form `$!{role}.$!{domain}.*` to user work directories of the form
# `$!{work_dir}/$!{role}-$!{domain}`. Takes action on the matched directories.
#
# @param [Hash] hostname_hash the `Hash` from hostnames to information on them.
# @param [Pathname] work_dir the user work directory.
# @yield [hostname_info, config_dir] Performs the given action on a matched directory.
# @yieldparam [Object] hostname_info the hostname information.
# @yieldparam [Pathname] config_dir the configuration directory.
def generate_config_templates(hostname_hash, work_dir)
  hostname_hash.each_pair do |hostname, hostname_info|
    next if hostname == "id"

    config_dir = Pathname.new(hostname.split(".", -1)[0..1].join(".").gsub(".", "-")) \
      .join("config") \
      .expand_path(work_dir)

    yield hostname_info, config_dir if config_dir.directory?
  end
end

values = data_bag_item("init", "workstation").select do |node_name, _|
  node_name == node.name
end.values

if !values.empty?
  workstation_info = values[0]
  work_dir = Pathname.new(workstation_info["work_dir"]).expand_path(user_home)

  generate_config_templates(data_bag_item("monitoring", "airbrake"), work_dir) do |hostname_info, config_dir|
    template Pathname.new("airbrake.yml").expand_path(config_dir).to_s do
      source "airbrake.yml.erb"
      owner recipe.original_user
      group recipe.original_group
      mode 0644
      variables(:api_key => hostname_info)
      action :nothing
    end.action(:create)
  end

  generate_config_templates(data_bag_item("analytics", "google"), work_dir) do |hostname_info, config_dir|
    template Pathname.new("google_analytics.yml").expand_path(config_dir).to_s do
      source "google_analytics.yml.erb"
      owner recipe.original_user
      group recipe.original_group
      mode 0644
      variables(:id => hostname_info)
      action :nothing
    end.action(:create)
  end

  hostnames = (data_bag_item("monitoring", "airbrake").keys + data_bag_item("analytics", "google").keys).uniq
  hostname_hash = Hash[hostnames.zip([data_bag_item("keys", "aws")[workstation_info["organization"]]] * hostnames.size)]

  generate_config_templates(hostname_hash, work_dir) do |hostname_info, config_dir|
    template Pathname.new("aws.yml").expand_path(config_dir).to_s do
      source "aws.yml.erb"
      owner recipe.original_user
      group recipe.original_group
      mode 0644
      variables(:access_key => hostname_info["access_key"],
                :secret_key => hostname_info["secret_key"])
      action :nothing
    end.action(:create)
  end
end
