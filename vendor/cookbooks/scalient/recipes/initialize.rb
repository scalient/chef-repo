# -*- coding: utf-8 -*-
#
# Copyright 2014 Scalient LLC

gemfile = Pathname.new("client/Gemfile.d/Gemfile-scalient").expand_path(Dir.home("chef"))

# Run this resource now to ensure that all the dependencies are installed.
cap_ops_gemfile_fragment gemfile.to_s do
  source gemfile.basename.to_s
  action :nothing
end.run_action(:create)
