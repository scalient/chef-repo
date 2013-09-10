# -*- coding: utf-8 -*-
#
# Copyright 2012 Scalient LLC

class << self
  include Scalient::Utils
end

recipe = self
hostname = node.name
domain_name = node.name.split(".", -1)[1..2].join(".")

match_group = HashMatchGroup.new do
  subgroup OrganizationMatchGroup.new("organizations")
  subgroup HostnameMatchGroup.new("hostnames")
end

alternate_domain_names = data_bag_item("dns", "aws")[domain_name]["alternates"] || []

key_info = match_group.match(hostname, data_bag_item("keys", "aws"))
access_key = key_info["access_key"]
secret_key = key_info["secret_key"]

ruby_block "register-cnames" do
  block do
    require "fog"

    zones = Fog::DNS.new({:provider => "aws",
                          :aws_access_key_id => access_key,
                          :aws_secret_access_key => secret_key}).zones

    ([domain_name] + alternate_domain_names).each do |domain_name|
      zone_id = data_bag_item("dns", "aws")[domain_name]["route53_zone_id"]
      domain = zones.get(zone_id).domain.gsub(Regexp.new("\\.$"), "")
      domain_name = hostname.split(".", -1)[0] + "." + domain_name

      recipe.route53_record "register-cname-#{domain_name}" do
        name domain_name
        type "CNAME"
        value node["ec2"]["public_hostname"]
        ttl 300

        zone_id zone_id
        aws_access_key_id access_key
        aws_secret_access_key secret_key

        action :nothing
      end.action(:create)

      if hostname.split(".", -1)[0] == "www"
        # Enable the wwwizer.com "naked domain" redirect service.
        recipe.route53_record "register-a-wwwizer-#{domain_name}" do
          name domain
          type "A"
          value "174.129.25.170"
          ttl 604800

          zone_id zone_id
          aws_access_key_id access_key
          aws_secret_access_key secret_key

          action :nothing
        end.action(:create)
      end
    end
  end

  action :nothing
end.action(:create)
