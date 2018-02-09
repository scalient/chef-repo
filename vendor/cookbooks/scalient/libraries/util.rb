# -*- coding: utf-8 -*-
#
# Copyright 2012-2014 Scalient LLC
# All rights reserved.

require "etc"
require "pathname"
require "rbconfig"

module Scalient
  module Util
    module InstanceMethods
      def original_user
        @original_user ||= ENV["SUDO_USER"] || Etc.getpwuid.name
      end

      def original_group
        @original_group ||= Etc.getgrgid(Etc.getpwnam(original_user).gid).name
      end

      def original_user_home
        @original_user_home ||= Pathname.new(Etc.getpwnam(original_user).dir)
      end

      def ruby_interpreter_path
        Pathname.new(RbConfig::CONFIG["RUBY_INSTALL_NAME"] + RbConfig::CONFIG["EXEEXT"]) \
          .expand_path(RbConfig::CONFIG["bindir"]).to_s
      end
    end

    def self.included(clazz)
      clazz.send(:include, InstanceMethods)
    end
  end
end
