# -*- coding: utf-8 -*-
#
# Copyright 2012 Scalient LLC

require "etc"
require "pathname"
require "rbconfig"

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

      def ruby_interpreter_path
        Pathname.new(RbConfig::CONFIG["RUBY_INSTALL_NAME"] + RbConfig::CONFIG["EXEEXT"]) \
          .expand_path(RbConfig::CONFIG["bindir"]).to_s
      end
    end

    def self.included(clazz)
      clazz.send(:include, InstanceMethods)
    end

    class HashMatchGroup
      attr_reader :name
      attr_reader :subgroups

      def initialize(name = nil, &block)
        @name = name
        @subgroups = []

        instance_eval(&block) if !block.nil?
      end

      # Resolves subgroups in reverse order of declaration, from most specific to least specific.
      def match(name, hash)
        if subgroups.empty?
          hash.each_pair do |k, v|
            return v if match_key?(name, k)
          end
        else
          @subgroups.each do |subgroup|
            subhash = hash[subgroup.name]
            next if subhash.nil?

            m = subgroup.match(name, subhash)
            return m if !m.nil?
          end
        end

        nil
      end

      def subgroup(match_group)
        @subgroups.unshift(match_group)
      end

      def match_key?(name, key)
        false
      end
    end

    class OrganizationMatchGroup < HashMatchGroup
      # Treats the name as a hostname and parses out the middle portion as the organization.
      def match_key?(name, key)
        name.split(".", -1)[1] == key
      end
    end

    class HostnameMatchGroup < HashMatchGroup
      # Treats the name as a hostname.
      def match_key?(name, key)
        name == key
      end
    end
  end
end
