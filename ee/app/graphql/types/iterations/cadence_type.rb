# frozen_string_literal: true

module Types
  module Iterations
    class CadenceType < BaseObject
      graphql_name 'IterationCadence'
      description 'Represents an iteration cadence'

      authorize :read_iteration_cadence

      field :id, ::Types::GlobalIDType[::Iterations::Cadence], null: false,
        description: 'Global ID of the iteration cadence.'

      field :title, GraphQL::STRING_TYPE, null: false,
        description: 'Title of the iteration cadence.'

      field :duration_in_weeks, GraphQL::INT_TYPE, null: true,
        description: 'Duration in weeks of the iterations within this cadence.'

      field :iterations_in_advance, GraphQL::INT_TYPE, null: true,
        description: 'Future iterations to be created when iteration cadence is set to automatic.'

      field :start_date, Types::TimeType, null: true,
        description: 'Timestamp of the iteration cadence start date.'

      field :automatic, GraphQL::BOOLEAN_TYPE, null: true,
        description: 'Whether the iteration cadence should automatically generate future iterations.'

      field :active, GraphQL::BOOLEAN_TYPE, null: true,
        description: 'Whether the iteration cadence is active.'
    end
  end
end
