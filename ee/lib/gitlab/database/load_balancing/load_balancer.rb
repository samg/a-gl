# frozen_string_literal: true

module Gitlab
  module Database
    module LoadBalancing
      # Load balancing for ActiveRecord connections.
      #
      # Each host in the load balancer uses the same credentials as the primary
      # database.
      #
      # This class *requires* that `ActiveRecord::Base.retrieve_connection`
      # always returns a connection to the primary.
      class LoadBalancer
        CACHE_KEY = :gitlab_load_balancer_host

        attr_reader :host_list

        # hosts - The hostnames/addresses of the additional databases.
        def initialize(hosts = [])
          @host_list = HostList.new(hosts.map { |addr| Host.new(addr, self) })
          @connection_db_roles = {}.compare_by_identity
        end

        # Yields a connection that can be used for reads.
        #
        # If no secondaries were available this method will use the primary
        # instead.
        def read(&block)
          connection = nil
          conflict_retried = 0

          while host
            ensure_caching!

            begin
              connection = host.connection
              @connection_db_roles[connection] = ROLE_REPLICA

              return yield connection
            rescue => error
              @connection_db_roles.delete(connection) if connection.present?

              if serialization_failure?(error)
                # This error can occur when a query conflicts. See
                # https://www.postgresql.org/docs/current/static/hot-standby.html#HOT-STANDBY-CONFLICT
                # for more information.
                #
                # In this event we'll cycle through the secondaries at most 3
                # times before using the primary instead.
                will_retry = conflict_retried < @host_list.length * 3

                LoadBalancing::Logger.warn(
                  event: :host_query_conflict,
                  message: 'Query conflict on host',
                  conflict_retried: conflict_retried,
                  will_retry: will_retry,
                  db_host: host.host,
                  db_port: host.port,
                  host_list_length: @host_list.length
                )

                if will_retry
                  conflict_retried += 1
                  release_host
                else
                  break
                end
              elsif connection_error?(error)
                host.offline!
                release_host
              else
                raise error
              end
            end
          end

          LoadBalancing::Logger.warn(
            event: :no_secondaries_available,
            message: 'No secondaries were available, using primary instead',
            conflict_retried: conflict_retried,
            host_list_length: @host_list.length
          )

          read_write(&block)
        ensure
          @connection_db_roles.delete(connection) if connection.present?
        end

        # Yields a connection that can be used for both reads and writes.
        def read_write
          connection = nil
          # In the event of a failover the primary may be briefly unavailable.
          # Instead of immediately grinding to a halt we'll retry the operation
          # a few times.
          retry_with_backoff do
            connection = ActiveRecord::Base.retrieve_connection
            @connection_db_roles[connection] = ROLE_PRIMARY

            yield connection
          end
        ensure
          @connection_db_roles.delete(connection) if connection.present?
        end

        # Recognize the role (primary/replica) of the database this connection
        # is connecting to. If the connection is not issued by this load
        # balancer, return nil
        def db_role_for_connection(connection)
          @connection_db_roles[connection]
        end

        # Returns a host to use for queries.
        #
        # Hosts are scoped per thread so that multiple threads don't
        # accidentally re-use the same host + connection.
        def host
          RequestStore[CACHE_KEY] ||= @host_list.next
        end

        # Releases the host and connection for the current thread.
        def release_host
          if host = RequestStore[CACHE_KEY]
            host.disable_query_cache!
            host.release_connection
          end

          RequestStore.delete(CACHE_KEY)
        end

        def release_primary_connection
          ActiveRecord::Base.connection_pool.release_connection
        end

        # Returns the transaction write location of the primary.
        def primary_write_location
          location = read_write do |connection|
            ::Gitlab::Database.get_write_location(connection)
          end

          return location if location

          raise 'Failed to determine the write location of the primary database'
        end

        # Returns true if all hosts have caught up to the given transaction
        # write location.
        def all_caught_up?(location)
          @host_list.hosts.all? { |host| host.caught_up?(location) }
        end

        # Yields a block, retrying it upon error using an exponential backoff.
        def retry_with_backoff(retries = 3, time = 2)
          retried = 0
          last_error = nil

          while retried < retries
            begin
              return yield
            rescue => error
              raise error unless connection_error?(error)

              # We need to release the primary connection as otherwise Rails
              # will keep raising errors when using the connection.
              release_primary_connection

              last_error = error
              sleep(time)
              retried += 1
              time **= 2
            end
          end

          raise last_error
        end

        def connection_error?(error)
          case error
          when ActiveRecord::StatementInvalid, ActionView::Template::Error
            # After connecting to the DB Rails will wrap query errors using this
            # class.
            connection_error?(error.cause)
          when *CONNECTION_ERRORS
            true
          else
            # When PG tries to set the client encoding but fails due to a
            # connection error it will raise a PG::Error instance. Catching that
            # would catch all errors (even those we don't want), so instead we
            # check for the message of the error.
            error.message.start_with?('invalid encoding name:')
          end
        end

        def serialization_failure?(error)
          if error.cause
            serialization_failure?(error.cause)
          else
            error.is_a?(PG::TRSerializationFailure)
          end
        end

        private

        def ensure_caching!
          host.enable_query_cache! unless host.query_cache_enabled
        end
      end
    end
  end
end
