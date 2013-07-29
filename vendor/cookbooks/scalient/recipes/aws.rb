# -*- coding: utf-8 -*-
#
# Copyright 2012 Scalient LLC

recipe = self
hostname = node.name.split(".", -1)[0]
main_org_name = node.name.split(".", -1)[1]
alternate_org_names = data_bag_item("dns", "aws")[main_org_name]["alternates"] || []
access_key = data_bag_item("keys", "aws")[main_org_name]["access_key"]
secret_key = data_bag_item("keys", "aws")[main_org_name]["secret_key"]

ruby_block "register-cnames" do
  block do
    require "fog"

    zones = Fog::DNS.new({:provider => "aws",
                          :aws_access_key_id => access_key,
                          :aws_secret_access_key => secret_key}).zones

    ([main_org_name] + alternate_org_names).each do |org_name|
      zone_id = data_bag_item("dns", "aws")[org_name]["route53_zone_id"]
      domain = zones.get(zone_id).domain.gsub(Regexp.new("\\.$"), "")
      domain_name = hostname + "." + domain

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

      if hostname == "www"
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
