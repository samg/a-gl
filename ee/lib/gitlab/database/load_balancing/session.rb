# frozen_string_literal: true

module Gitlab
  module Database
    module LoadBalancing
      # Tracking of load balancing state per user session.
      #
      # A session starts at the beginning of a request and ends once the request
      # has been completed. Sessions can be used to keep track of what hosts
      # should be used for queries.
      class Session
        CACHE_KEY = :gitlab_load_balancer_session

        def self.current
          RequestStore[CACHE_KEY] ||= new
        end

        def self.clear_session
          RequestStore.delete(CACHE_KEY)
        end

        def self.without_sticky_writes(&block)
          current.ignore_writes(&block)
        end

        def initialize
          @use_primary = false
          @performed_write = false
          @ignore_writes = false
        end

        def use_primary?
          @use_primary
        end

        alias_method :using_primary?, :use_primary?

        def use_primary!
          @use_primary = true
        end

        def use_primary(&blk)
          used_primary = @use_primary
          @use_primary = true
          yield
        ensure
          @use_primary = used_primary || @performed_write
        end

        def ignore_writes(&block)
          @ignore_writes = true

          yield
        ensure
          @ignore_writes = false
        end

        def write!
          @performed_write = true

          return if @ignore_writes

          use_primary!
        end

        def performed_write?
          @performed_write
        end
      end
    end
  end
end
