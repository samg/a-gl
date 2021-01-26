# frozen_string_literal: true

module Gitlab
  module Database
    ##
    # This class is used to make it possible to ensure read consistency in
    # GitLab EE without the need of overriding a lot of methods / classes /
    # modules.
    #
    # This is a CE class that does nothing in CE, because database load
    # balancing is EE-only feature, but you can still use it in CE. It will
    # start ensuring read consistency once it is overridden in EE.
    #
    # Using this class in CE helps to avoid creeping discrepancy between CE /
    # EE only to force usage of the primary database in EE.
    #
    class Consistency
      def self.with_read_consistency(&block)
        self.new.use_primary(&block)
      end

      ##
      # In CE there is no database load balancing, so all reads are expected to
      # be consistent by the ACID guarantees of a single PostgreSQL instance.
      #
      # This method is overridden in EE.
      #
      def use_primary(&block)
        yield
      end
    end
  end
end

::Gitlab::Database::Consistency.prepend_if_ee('EE::Gitlab::Database::Consistency')
