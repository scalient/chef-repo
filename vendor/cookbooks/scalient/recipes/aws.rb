# -*- coding: utf-8 -*-
#
# Copyright 2012 Scalient LLC

route53_record "register-cname" do
  name node.name
  type "CNAME"
  value node["ec2"]["public_hostname"]
  ttl 300

  zone_id data_bag_item("dns", "aws")["route53_zone_id"]
  aws_access_key_id data_bag_item("keys", "aws")["access_key"]
  aws_secret_access_key data_bag_item("keys", "aws")["secret_key"]

  action :nothing
end.action(:create)
