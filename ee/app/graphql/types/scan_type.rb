# frozen_string_literal: true

module Types
  # rubocop: disable Graphql/AuthorizeTypes
  class ScanType < BaseObject
    graphql_name 'Scan'
    description 'Represents the security scan information'

    authorize :read_scan

    field :name, GraphQL::STRING_TYPE, null: false, description: 'Name of the scan.'
    field :errors, [GraphQL::STRING_TYPE], null: false, description: 'List of errors.'

    def errors
      object.info['errors'].to_a
    end
  end
end
