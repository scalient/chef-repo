# -*- coding: utf-8 -*-
#
# Copyright 2012-2021 Scalient LLC
# All rights reserved.

class << self
  include Percolate
  include Scalient::Util
end

hostname = node.name

apt_repository "elastic" do
  uri "https://artifacts.elastic.co/packages/7.x/apt"
  components ["main"]
  distribution "stable"
  key "D88E42B4"
  action :add
end

package "metricbeat" do
  action :install
end

service "metricbeat" do
  action :enable
end

if elasticsearch_info = percolator.find("elasticsearch", :hostname, hostname)&.[]("elasticsearch")
  template "/etc/metricbeat/metricbeat.yml" do
    source "metricbeat-metricbeat.yml.erb"
    owner "root"
    group "root"
    mode 0600
    variables(
        cloud_id: elasticsearch_info["cloud_id"],
        user: elasticsearch_info["user"],
        password: elasticsearch_info["password"]
    )
    action :create
    notifies :restart, "service[metricbeat]", :immediately
  end
end


if aws_info = percolator.find("keys-aws", :hostname, hostname)&.[]("aws")
  template "/etc/metricbeat/modules.d/aws.yml" do
    source "metricbeat-aws.yml.erb"
    owner "root"
    group "root"
    mode 0600
    variables(
        access_key: aws_info["access_key"],
        secret_key: aws_info["secret_key"]
    )
    action :create
    notifies :restart, "service[metricbeat]", :immediately
  end
end
