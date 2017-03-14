# -*- coding: utf-8 -*-
#
# Copyright 2012-2014 Scalient LLC
# All rights reserved.

class << self
  include Percolate
  include Scalient::Util
end

recipe = self
hostname = node.name
domain_name = hostname.split(".", -1)[1...3].join(".")

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

key_info = percolator.find("keys-aws", :hostname, hostname)["aws"]
route53_info = percolator.find("dns-aws", :hostname, hostname)["aws-route53"]

alternate_domain_names = route53_info[domain_name]["alternates"] || []

access_key = key_info["access_key"]
secret_key = key_info["secret_key"]

zones = Fog::DNS.new({provider: "aws",
                      aws_access_key_id: access_key,
                      aws_secret_access_key: secret_key}).zones

([domain_name] + alternate_domain_names).each do |domain_name|
  zone_id = route53_info[domain_name]["zone_id"]
  domain = zones.get(zone_id).domain.gsub(Regexp.new("\\.$"), "")
  domain_name = hostname.split(".", -1)[0] + "." + domain_name

  route53_record "register CNAME record #{domain_name}" do
    name domain_name
    type "CNAME"
    value node["ec2"]["public_hostname"]
    ttl 300

    zone_id zone_id
    aws_access_key_id access_key
    aws_secret_access_key secret_key

    action :create
  end

  if hostname.split(".", -1)[0] == "www"
    # Enable the wwwizer.com "naked domain" redirect service.
    route53_record "register WWWizer naked domain redirect A record #{domain_name}" do
      name domain
      type "A"
      value "174.129.25.170"
      ttl 604800

      zone_id zone_id
      aws_access_key_id access_key
      aws_secret_access_key secret_key

      action :create
    end
  end
end
