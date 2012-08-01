# -*- coding: utf-8 -*-
#
# Copyright 2012 Scalient LLC

require "etc"

module Scalient
  module Utils
    module InstanceMethods
      def original_user
        original_uid = Process.uid
        original_uid = ENV["SUDO_UID"].to_i if original_uid == 0 && ENV.include?("SUDO_UID")
        Etc.getpwuid(original_uid).name
      end

      def original_group
        original_gid = Process.gid
        original_gid = ENV["SUDO_GID"].to_i if original_gid == 0 && ENV.include?("SUDO_GID")
        Etc.getgrgid(original_gid).name
      end
    end

    def self.included(clazz)
      clazz.send(:include, InstanceMethods)
    end
  end
end
