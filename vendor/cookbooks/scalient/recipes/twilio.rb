# -*- coding: utf-8 -*-
#
# Copyright 2017 Scalient LLC
# All rights reserved.

class << self
  include Percolate
  include Scalient::Util
end

recipe = self
user_home = Dir.home(recipe.original_user)
hostname = node.name
app_dir = Pathname.new("apps").join(hostname.split(".", -1)[1]).expand_path(user_home)

if twilio_info = recipe.percolator.find("communication-twilio", :hostname, hostname)&.[]("twilio")
  template app_dir.join("shared", "config", "twilio.yml").to_s do
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
