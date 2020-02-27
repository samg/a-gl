# frozen_string_literal: true

module EE
  module API
    module Entities
      class Dependency < Grape::Entity
        class Vulnerability < Grape::Entity
          expose :name, :severity
        end

        expose :name, :version, :package_manager, :dependency_file_path
        expose :dependency_file_path do |dependency|
          dependency[:location][:path]
        end
        expose :vulnerabilities, using: Vulnerability, if: ->(_, opts) { can_read_vulnerabilities?(opts[:user], opts[:project]) }

        private

        def can_read_vulnerabilities?(user, project)
          Ability.allowed?(user, :read_vulnerability, project)
        end
      end
    end
  end
end
