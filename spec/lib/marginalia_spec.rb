# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Marginalia spec' do
  class MarginaliaTestController < ApplicationController
    skip_before_action :authenticate_user!, :check_two_factor_requirement

    def first_user
      User.first
      render body: nil
    end

    private

    [:auth_user, :current_user, :set_experimentation_subject_id_cookie, :signed_in?].each do |method|
      define_method(method) { }
    end
  end

  class MarginaliaTestJob
    include Sidekiq::Worker

    def perform
      Gitlab::ApplicationContext.with_context(caller_id: self.class.name) do
        User.first
      end
    end
  end

  class MarginaliaTestMailer < ApplicationMailer
    def first_user
      User.first
    end
  end

  describe 'For rails web requests' do
    let(:correlation_id) { SecureRandom.uuid }
    let(:recorded) { ActiveRecord::QueryRecorder.new { make_request(correlation_id) } }

    let(:component_map) do
      {
        "application"    => "test",
        "endpoint_id"    => "MarginaliaTestController#first_user",
        "correlation_id" => correlation_id
      }
    end

    it 'generates a query that includes the component and value' do
      component_map.each do |component, value|
        expect(recorded.log.last).to include("#{component}:#{value}")
      end
    end
  end

  describe 'for Sidekiq worker jobs' do
    around do |example|
      with_sidekiq_server_middleware do |chain|
        chain.add Labkit::Middleware::Sidekiq::Context::Server
        chain.add Marginalia::SidekiqInstrumentation::Middleware
        Marginalia.application_name = "sidekiq"
        example.run
      end
    end

    after(:all) do
      MarginaliaTestJob.clear
    end

    before do
      MarginaliaTestJob.perform_async
    end

    let(:sidekiq_job) { MarginaliaTestJob.jobs.first }
    let(:recorded) { ActiveRecord::QueryRecorder.new { MarginaliaTestJob.drain } }

    let(:component_map) do
      {
        "application"    => "sidekiq",
        "endpoint_id"    => "MarginaliaTestJob",
        "correlation_id" => sidekiq_job['correlation_id'],
        "jid"            => sidekiq_job['jid']
      }
    end

    it 'generates a query that includes the component and value' do
      component_map.each do |component, value|
        expect(recorded.log.last).to include("#{component}:#{value}")
      end
    end

    describe 'for ActionMailer delivery jobs' do
      # We need to ensure that this runs through Sidekiq to take
      # advantage of the middleware. There is a Rails bug that means we
      # have to do some extra steps to make this happen:
      # https://github.com/rails/rails/issues/37270#issuecomment-553927324
      around do |example|
        original_queue_adapter = ActiveJob::Base.queue_adapter
        descendants = ActiveJob::Base.descendants + [ActiveJob::Base]

        ActiveJob::Base.queue_adapter = :sidekiq
        descendants.each(&:disable_test_adapter)
        example.run
        descendants.each { |a| a.enable_test_adapter(ActiveJob::QueueAdapters::TestAdapter.new) }
        ActiveJob::Base.queue_adapter = original_queue_adapter
      end

      let(:delivery_job) { MarginaliaTestMailer.first_user.deliver_later }

      let(:recorded) do
        ActiveRecord::QueryRecorder.new do
          Sidekiq::Worker.drain_all
        end
      end

      let(:component_map) do
        {
          "application" => "sidekiq",
          "endpoint_id" => "ActionMailer::MailDeliveryJob",
          "jid"         => delivery_job.job_id
        }
      end

      it 'generates a query that includes the component and value' do
        component_map.each do |component, value|
          expect(recorded.log.last).to include("#{component}:#{value}")
        end
      end
    end
  end

  def make_request(correlation_id)
    request_env = Rack::MockRequest.env_for('/')

    ::Labkit::Correlation::CorrelationId.use_id(correlation_id) do
      MarginaliaTestController.action(:first_user).call(request_env)
    end
  end
end
