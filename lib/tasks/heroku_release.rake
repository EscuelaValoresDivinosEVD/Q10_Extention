# frozen_string_literal: true

namespace :heroku do
  desc "Release phase: migrate primary and load Solid schemas when missing (single Heroku Postgres)"
  task release: :environment do
    Rake::Task["db:prepare"].invoke

    {
      queue: "solid_queue_jobs",
      cache: "solid_cache_entries",
      cable: "solid_cable_messages"
    }.each do |role, marker_table|
      config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: role.to_s)
      next unless config

      ActiveRecord::Base.establish_connection(config)
      next if ActiveRecord::Base.connection.table_exists?(marker_table)

      schema_file = Rails.root.join("db/#{role}_schema.rb")
      puts "Loading #{schema_file}..."
      load schema_file
    end
  ensure
    ActiveRecord::Base.establish_connection(:primary) if ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "primary")
  end
end
