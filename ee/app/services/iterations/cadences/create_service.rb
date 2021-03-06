# frozen_string_literal: true

module Iterations
  module Cadences
    class CreateService
      include Gitlab::Allowable

      attr_accessor :group, :current_user, :params

      def initialize(group, user, params = {})
        @group, @current_user, @params = group, user, params.dup
      end

      def execute
        return ::ServiceResponse.error(message: _('Operation not allowed'), http_status: 403) unless can_create_iteration_cadence?

        iteration_cadence = group.iterations_cadences.new(params)

        if iteration_cadence.save
          ::ServiceResponse.success(payload: { iteration_cadence: iteration_cadence })
        else
          ::ServiceResponse.error(message: iteration_cadence.errors.full_messages, http_status: 422)
        end
      end

      private

      def can_create_iteration_cadence?
        group.iteration_cadences_feature_flag_enabled? &&
          can?(current_user, :create_iteration_cadence, group) &&
          can_create_single_or_multiple_iteration_cadences?
      end

      def can_create_single_or_multiple_iteration_cadences?
        group.feature_available?(:iterations) && (group.iterations_cadences.empty? || group.multiple_iteration_cadences_available?)
      end
    end
  end
end
