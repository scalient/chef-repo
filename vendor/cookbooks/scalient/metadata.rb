# -*- coding: utf-8 -*-
#
# Copyright 2012-2014 Scalient LLC
# All rights reserved.

require "pathname"

maintainer "Roy Liu"
maintainer_email "roy@scalient.net"
license "All rights reserved"
description "The Chef cookbook for Scalient LLC"
long_description Pathname.new("../README.md").expand_path(__FILE__).open { |f| f.read }
version "0.9.0"

depends "apt"
depends "percolate"
depends "route53"
