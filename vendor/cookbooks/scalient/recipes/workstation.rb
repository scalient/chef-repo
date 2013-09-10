# -*- coding: utf-8 -*-
#
# Copyright 2012 Scalient LLC

class << self
  include Scalient::Utils
end

require "pathname"

recipe = self
user_home = Dir.home(recipe.original_user)

class DirectoryHostnameMatchGroup < HashMatchGroup
  def match_key?(name, key)
    name.split(".", -1)[0..1] == key.split(".", -1)[0..1]
  end
end

# Attempts to match hostnames of the form `$!{role}.$!{domain}.*` to user work directories of the form
# `$!{work_dir}/$!{role}-$!{domain}`. Takes action on the matched directories.
#
# @param [Hash] hostname_hash the `Hash` from hostnames to information on them.
# @param [Pathname] work_dir the user work directory.
# @yield [hostname_info, config_dir] Performs the given action on a matched directory.
# @yieldparam [Object] hostname_info the hostname information.
# @yieldparam [Pathname] config_dir the configuration directory.
def generate_config_templates(hash, work_dir)
  match_group = HashMatchGroup.new do
    subgroup OrganizationMatchGroup.new("organizations")
    subgroup DirectoryHostnameMatchGroup.new("hostnames")
  end

  work_dir.children.select do |subdir|
    name = subdir.basename.to_s.split("-", -1)
    next if name.size != 2
    name = name.join(".")

    info = match_group.match(name, hash)
    config_dir = subdir.join("config")

    yield info, config_dir if config_dir.directory? && !info.nil?
  end
end

values = data_bag_item("init", "workstation").select do |node_name, _|
  node_name == node.name
end.values

if !values.empty?
  workstation_info = values[0]
  work_dir = Pathname.new(workstation_info["work_dir"]).expand_path(user_home)

  generate_config_templates(data_bag_item("monitoring", "airbrake"), work_dir) do |info, config_dir|
    template Pathname.new("airbrake.yml").expand_path(config_dir).to_s do
      source "airbrake.yml.erb"
      owner recipe.original_user
      group recipe.original_group
      mode 0644
      variables(:api_key => info)
      action :nothing
    end.action(:create)
  end

  generate_config_templates(data_bag_item("analytics", "google"), work_dir) do |info, config_dir|
    template Pathname.new("google_analytics.yml").expand_path(config_dir).to_s do
      source "google_analytics.yml.erb"
      owner recipe.original_user
      group recipe.original_group
      mode 0644
      variables(:id => info)
      action :nothing
    end.action(:create)
  end

  generate_config_templates(data_bag_item("keys", "aws"), work_dir) do |info, config_dir|
    template Pathname.new("aws.yml").expand_path(config_dir).to_s do
      source "aws.yml.erb"
      owner recipe.original_user
      group recipe.original_group
      mode 0644
      variables(:access_key => info["access_key"],
                :secret_key => info["secret_key"])
      action :nothing
    end.action(:create)
  end
end
