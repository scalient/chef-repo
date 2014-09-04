# -*- coding: utf-8 -*-
#
# Copyright 2012-2014 Scalient LLC
# All rights reserved.

require "pathname"
require "shellwords"

class << self
  include Scalient::Util
end

recipe = self
cluster = node.name.split(".", -1)[1]
postgresql_conf_dir = Pathname.new("/etc/postgresql").join(Scalient::PostgreSQL::VERSION, cluster)
postgresql_data_dir = Pathname.new("/var/lib/postgresql").join(Scalient::PostgreSQL::VERSION, cluster)
postgresql_bin_dir = Pathname.new("/usr/lib/postgresql").join(Scalient::PostgreSQL::VERSION, "bin")

template "/etc/sysctl.conf" do
  source "sysctl.conf.erb"
  owner "root"
  group "root"
  mode 0644
  variables(kernel_shmmax: Scalient::PostgreSQL::CACHE_SIZE * 1024 * 1024)
  notifies :run, "bash[sysctl]", :immediately
  action :nothing
end.action(:create)

bash "sysctl" do
  user "root"
  group "root"
  code <<EOF
exec -- sysctl -p
EOF
  action :nothing
end

package "postgresql-" + Scalient::PostgreSQL::VERSION do
  notifies :stop, "service[postgresql]", :immediately
  action :nothing
end.action(:install)

directory postgresql_conf_dir.parent.join("main").to_s do
  recursive true
  action :nothing
end.action(:delete)

directory postgresql_data_dir.parent.join("main").to_s do
  recursive true
  action :nothing
end.action(:delete)

directory postgresql_conf_dir.to_s do
  owner "postgres"
  group "postgres"
  mode 0755
  action :nothing
end.action(:create)

directory postgresql_data_dir.to_s do
  owner "postgres"
  group "postgres"
  mode 0700
  action :nothing
end.action(:create)

template postgresql_conf_dir.join("postgresql.conf").to_s do
  source "postgresql.conf.erb"
  owner "postgres"
  group "postgres"
  mode 0644
  variables(cluster: cluster,
            prefix: Scalient::PREFIX,
            version: Scalient::PostgreSQL::VERSION,
            cache_size: Scalient::PostgreSQL::CACHE_SIZE)
  notifies :restart, "service[postgresql]", :immediately
  action :nothing
end.action(:create)

cookbook_file postgresql_conf_dir.join("pg_hba.conf").to_s do
  source "pg_hba.conf"
  owner "postgres"
  group "postgres"
  mode 0640
  notifies :restart, "service[postgresql]", :immediately
  action :nothing
end.action(:create)

cookbook_file postgresql_conf_dir.join("pg_ident.conf").to_s do
  source "pg_ident.conf"
  owner "postgres"
  group "postgres"
  mode 0640
  notifies :restart, "service[postgresql]", :immediately
  action :nothing
end.action(:create)

bash "initdb" do
  user "postgres"
  group "postgres"
  code <<EOF
exec -- #{postgresql_bin_dir.join("initdb").to_s.shellescape} -D #{postgresql_data_dir.to_s.shellescape} -E UTF8
EOF
  only_if { (postgresql_data_dir.entries - [".", ".."].map { |s| Pathname.new (s) }).empty? }
  notifies :create, "link[#{postgresql_data_dir.join("server.crt")}]", :immediately
  notifies :create, "link[#{postgresql_data_dir.join("server.key")}]", :immediately
  notifies :restart, "service[postgresql]", :immediately
  notifies :run, "bash[createuser]", :immediately
  notifies :run, "bash[createdb]", :immediately
  action :nothing
end.action(:run)

link postgresql_data_dir.join("server.crt").to_s do
  to "/etc/ssl/certs/ssl-cert-snakeoil.pem"
  owner "postgres"
  group "postgres"
  action :nothing
end

link postgresql_data_dir.join("server.key").to_s do
  to "/etc/ssl/private/ssl-cert-snakeoil.key"
  owner "postgres"
  group "postgres"
  action :nothing
end

service "postgresql" do
  only_if do
    !postgresql_conf_dir.exist? \
      || (postgresql_conf_dir.join("postgresql.conf").exist? \
      && postgresql_conf_dir.join("pg_hba.conf").exist? \
      && postgresql_conf_dir.join("pg_ident.conf").exist? \
      && postgresql_data_dir.join("PG_VERSION").exist?)
  end

  action :nothing
end

bash "createuser" do
  user "postgres"
  group "postgres"
  code <<EOF
exec -- createuser --superuser -- #{recipe.original_user.shellescape}
EOF
  action :nothing
end

bash "createdb" do
  user "postgres"
  group "postgres"
  code <<EOF
exec -- createdb -- #{recipe.original_user.shellescape}
EOF
  action :nothing
end
