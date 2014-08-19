# -*- coding: utf-8 -*-
#
# Copyright 2012-2014 Scalient LLC
# All rights reserved.

include_recipe "scalient::initialize"
include_recipe "percolate"

hostname = node.name
domain_name = hostname.split(".", -1)[1...3].join(".")

key_info = percolator.find("keys-aws", :hostname, hostname)["aws"]
route53_info = percolator.find("dns-aws", :hostname, hostname)["aws-route53"]

alternate_domain_names = route53_info[domain_name]["alternates"] || []

access_key = key_info["access_key"]
secret_key = key_info["secret_key"]

require "fog"

zones = Fog::DNS.new({:provider => "aws",
                      :aws_access_key_id => access_key,
                      :aws_secret_access_key => secret_key}).zones

([domain_name] + alternate_domain_names).each do |domain_name|
  zone_id = route53_info[domain_name]["zone_id"]
  domain = zones.get(zone_id).domain.gsub(Regexp.new("\\.$"), "")
  domain_name = hostname.split(".", -1)[0] + "." + domain_name

  route53_record "register-cname-#{domain_name}" do
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
    route53_record "register-a-wwwizer-#{domain_name}" do
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
