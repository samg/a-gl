# frozen_string_literal: true

module Types
  module Boards
    # Common arguments that we can be used to filter boards epics and issues
    class BoardIssuableInputBaseType < BaseInputObject
      argument :label_name, GraphQL::STRING_TYPE.to_list_type,
               required: false,
               description: 'Filter by label name.'

      argument :author_username, GraphQL::STRING_TYPE,
               required: false,
               description: 'Filter by author username.'

      argument :my_reaction_emoji, GraphQL::STRING_TYPE,
               required: false,
               description: 'Filter by reaction emoji applied by the current user.'
    end
  end
end
