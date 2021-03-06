# -*- coding: utf-8 -*-
#
# Copyright 2012-2014 Scalient LLC
# All rights reserved.

require "pathname"
require "shellwords"

class << self
  include Percolate
  include Scalient::Util
end

recipe = self
cluster = node.name.split(".", -1)[1]
hostname = node.name
domain_name = hostname.split(".", -1)[1...3].join(".")

postgresql_conf_dir = Pathname.new("/etc/postgresql").join(Scalient::PostgreSQL::VERSION, cluster)
postgresql_data_dir = Pathname.new("/var/lib/postgresql").join(Scalient::PostgreSQL::VERSION, cluster)
postgresql_bin_dir = Pathname.new("/usr/lib/postgresql").join(Scalient::PostgreSQL::VERSION, "bin")
postgresql_info = percolator.find("database-postgresql", :hostname, hostname)["postgresql"]

template "/etc/sysctl.conf" do
  source "sysctl.conf.erb"
  owner "root"
  group "root"
  mode 0644
  variables(kernel_shmmax: Scalient::PostgreSQL::CACHE_SIZE * 1024 * 1024)
  notifies :run, "bash[sysctl -p]", :immediately
  action :create
end

bash "sysctl -p" do
  user "root"
  group "root"
  code <<EOF
exec -- sysctl -p
EOF
  action :nothing
end

package "postgresql-#{Scalient::PostgreSQL::VERSION}" do
  action :install
end

# Remove the `main` cluster so that it doesn't interfere with our cluster.
bash "pg_dropcluster --stop -- #{Scalient::PostgreSQL::VERSION} main" do
  user "root"
  group "root"
  code <<EOF
exec -- pg_dropcluster --stop -- #{Scalient::PostgreSQL::VERSION} main
EOF
  returns [0, 1]
  # Any changes to the clustering setup should be met with a systemd service definition reload.
  notifies :run, "bash[systemctl -- daemon-reload]", :immediately
  notifies :restart, "service[postgresql]", :immediately
  action :run
end

[postgresql_conf_dir.parent, postgresql_conf_dir, postgresql_data_dir.parent].each do |dir|
  directory dir.to_s do
    owner "postgres"
    group "postgres"
    mode 0755
    action :create
  end
end

directory postgresql_data_dir.to_s do
  owner "postgres"
  group "postgres"
  mode 0700
  action :create
end

template postgresql_conf_dir.join("postgresql.conf").to_s do
  source "postgresql.conf.erb"
  owner "postgres"
  group "postgres"
  mode 0644
  variables(
      cluster: cluster,
      prefix: Scalient::PREFIX,
      version: Scalient::PostgreSQL::VERSION,
      cache_size: Scalient::PostgreSQL::CACHE_SIZE
  )
  notifies :restart, "service[postgresql]", :immediately
  action :create
end

template postgresql_conf_dir.join("pg_hba.conf").to_s do
  source "pg_hba.conf.erb"
  owner "postgres"
  group "postgres"
  mode 0640
  notifies :restart, "service[postgresql]", :immediately
  variables(users: (postgresql_info || {})["users"] || [])
  action :create
end

cookbook_file postgresql_conf_dir.join("pg_ident.conf").to_s do
  source "pg_ident.conf"
  owner "postgres"
  group "postgres"
  mode 0640
  notifies :restart, "service[postgresql]", :immediately
  action :create
end

bash "#{postgresql_bin_dir.join("initdb").to_s.shellescape} -D #{postgresql_data_dir.to_s.shellescape} -E UTF8" do
  user "postgres"
  group "postgres"
  code <<EOF
exec -- #{postgresql_bin_dir.join("initdb").to_s.shellescape} -D #{postgresql_data_dir.to_s.shellescape} -E UTF8
EOF
  only_if { (postgresql_data_dir.entries - [".", ".."].map { |s| Pathname.new (s) }).empty? }
  action :run
end

# At this point a cluster should've been created, or an existing one has been detected.
bash "systemctl -- daemon-reload" do
  user "root"
  group "root"
  code <<EOF
exec -- systemctl -- daemon-reload
EOF
  action :run
end

# Configuration should be complete at this point; restart the Postgres service.
service "postgresql" do
  action :restart
end

# Authorize the current user to prevent the "Fatal: role ${USER} does not exist" error.
bash "createuser --superuser -- #{recipe.original_user.shellescape}" do
  user "postgres"
  group "postgres"
  code <<EOF
exec -- createuser --superuser -- #{recipe.original_user.shellescape}
EOF
  returns [0, 1]
  action :run
end

# Create the database.
bash "createdb -- #{recipe.original_user.shellescape}" do
  user "postgres"
  group "postgres"
  code <<EOF
exec -- createdb -- #{recipe.original_user.shellescape}
EOF
  returns [0, 1]
  action :run
end

# Is there SSL information for this hostname? If so, we need to do more work.
if ssl_info = percolator.find("certificates", :hostname, hostname)&.dig("ssl", domain_name)
  file postgresql_data_dir.join("server.crt").to_s do
    owner "postgres"
    group "postgres"
    mode 0600
    content (ssl_info["certificate"] + ssl_info["ca_certificate"]).join("\n") + "\n"
    sensitive true
    notifies :restart, "service[postgresql]", :immediately
    action :create
  end

  file postgresql_data_dir.join("server.key").to_s do
    owner "postgres"
    group "postgres"
    mode 0600
    content ssl_info["key"].join("\n") + "\n"
    sensitive true
    notifies :restart, "service[postgresql]", :immediately
    action :create
  end
else
  link postgresql_data_dir.join("server.crt").to_s do
    to "/etc/ssl/certs/ssl-cert-snakeoil.pem"
    owner "postgres"
    group "postgres"
    notifies :restart, "service[postgresql]", :immediately
    action :create
  end

  link postgresql_data_dir.join("server.key").to_s do
    to "/etc/ssl/private/ssl-cert-snakeoil.key"
    owner "postgres"
    group "postgres"
    notifies :restart, "service[postgresql]", :immediately
    action :create
  end
end
