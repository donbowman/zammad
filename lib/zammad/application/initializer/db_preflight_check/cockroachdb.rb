# NOTE: Why use Cockroachdb::Connection over ActiveRecord::Base.connection?
#
# As of Rails 5.2, db:create now runs initializers prior to creating the DB.
# That means if an initializer tries to establish an ActiveRecord::Base.connection,
# it will raise an ActiveRecord::NoDatabaseError
# (see https://github.com/rails/rails/issues/32870 for more details).
#
# The workaround is to use the bare RDBMS library
# and connect to a standard system database instead.

module Zammad
  class Application
    class Initializer
      module DBPreflightCheck
        module Cockroachdb
          extend Base

          def self.perform
            check_version_compatibility
          ensure
            connection.try(:finish)
          end

          def self.check_version_compatibility
            return if connection.nil?  # Edge case: if Cockroachdb can't find a DB to connect to

            super
          end

          def self.connection
            alternate_dbs = %w[postgres]

            @connection ||= begin
                              PG.connect(db_config)
                            rescue PG::ConnectionBad
                              db_config[:dbname] = alternate_dbs.pop
                              retry if db_config[:dbname].present?
                            end
          end

          # Adapted from ActiveRecord::ConnectionHandling#postgresql_connection
          def self.db_config
            @db_config ||= ActiveRecord::Base.connection_config.dup.tap do |config|
              config.symbolize_keys!
              config[:user] = config.delete(:username)
              config[:dbname] = config.delete(:database)
              config.slice!(*PG::Connection.conndefaults_hash.keys, :requiressl)
              config.compact!
            end
          end

          #crdb_version| CockroachDB OSS v19.1.1 (x86_64-unknown-linux-gnu ...
          def self.current_version
            ver = crdb_variable('crdb_version').split.third
            ver[0] = ''
            @current_version ||= ver
          end

          def self.min_version
            @min_version ||= '19.1.1'
          end

          def self.vendor
            @vendor ||= 'Cockroachdb'
          end

          def self.crdb_variable(name)
            connection.exec("SHOW #{name};").first[name]
          end
        end
      end
    end
  end
end
