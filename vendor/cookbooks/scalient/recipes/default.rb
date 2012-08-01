# -*- coding: utf-8 -*-
#
# Copyright 2012 Scalient LLC

require "pathname"

gemfile = Pathname.new("client/Gemfile.d/Gemfile-scalient").expand_path(Dir.home("chef"))

cap_ops_gemfile_fragment gemfile.to_s do
  source gemfile.basename.to_s
  action :nothing
end.action(:create)
