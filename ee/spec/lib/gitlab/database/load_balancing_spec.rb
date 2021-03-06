# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Database::LoadBalancing do
  describe '.proxy' do
    context 'when configured' do
      before do
        allow(ActiveRecord::Base.singleton_class).to receive(:prepend)
        subject.configure_proxy
      end

      after do
        subject.clear_configuration
      end

      it 'returns the connection proxy' do
        expect(subject.proxy).to be_an_instance_of(subject::ConnectionProxy)
      end
    end

    context 'when not configured' do
      it 'returns nil' do
        expect(subject.proxy).to be_nil
      end

      it 'tracks an error to sentry' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
          an_instance_of(subject::ProxyNotConfiguredError)
        )

        subject.proxy
      end
    end
  end

  describe '.configuration' do
    it 'returns a Hash' do
      config = { 'hosts' => %w(foo) }

      allow(ActiveRecord::Base.configurations[Rails.env])
        .to receive(:[])
        .with('load_balancing')
        .and_return(config)

      expect(described_class.configuration).to eq(config)
    end
  end

  describe '.max_replication_difference' do
    context 'without an explicitly configured value' do
      it 'returns the default value' do
        allow(described_class)
          .to receive(:configuration)
          .and_return({})

        expect(described_class.max_replication_difference).to eq(8.megabytes)
      end
    end

    context 'with an explicitly configured value' do
      it 'returns the configured value' do
        allow(described_class)
          .to receive(:configuration)
          .and_return({ 'max_replication_difference' => 4 })

        expect(described_class.max_replication_difference).to eq(4)
      end
    end
  end

  describe '.max_replication_lag_time' do
    context 'without an explicitly configured value' do
      it 'returns the default value' do
        allow(described_class)
          .to receive(:configuration)
          .and_return({})

        expect(described_class.max_replication_lag_time).to eq(60)
      end
    end

    context 'with an explicitly configured value' do
      it 'returns the configured value' do
        allow(described_class)
          .to receive(:configuration)
          .and_return({ 'max_replication_lag_time' => 4 })

        expect(described_class.max_replication_lag_time).to eq(4)
      end
    end
  end

  describe '.replica_check_interval' do
    context 'without an explicitly configured value' do
      it 'returns the default value' do
        allow(described_class)
          .to receive(:configuration)
          .and_return({})

        expect(described_class.replica_check_interval).to eq(60)
      end
    end

    context 'with an explicitly configured value' do
      it 'returns the configured value' do
        allow(described_class)
          .to receive(:configuration)
          .and_return({ 'replica_check_interval' => 4 })

        expect(described_class.replica_check_interval).to eq(4)
      end
    end
  end

  describe '.hosts' do
    it 'returns a list of hosts' do
      allow(described_class)
        .to receive(:configuration)
        .and_return({ 'hosts' => %w(foo bar baz) })

      expect(described_class.hosts).to eq(%w(foo bar baz))
    end
  end

  describe '.pool_size' do
    it 'returns a Fixnum' do
      expect(described_class.pool_size).to be_a_kind_of(Integer)
    end
  end

  describe '.enable?' do
    let!(:license) { create(:license, plan: ::License::PREMIUM_PLAN) }

    before do
      subject.clear_configuration
    end

    it 'returns false when no hosts are specified' do
      allow(described_class).to receive(:hosts).and_return([])

      expect(described_class.enable?).to eq(false)
    end

    it 'returns false when Sidekiq is being used' do
      allow(described_class).to receive(:hosts).and_return(%w(foo))
      allow(Gitlab::Runtime).to receive(:sidekiq?).and_return(true)

      expect(described_class.enable?).to eq(false)
    end

    it 'returns false when running inside a Rake task' do
      allow(Gitlab::Runtime).to receive(:rake?).and_return(true)

      expect(described_class.enable?).to eq(false)
    end

    it 'returns true when load balancing should be enabled' do
      allow(described_class).to receive(:hosts).and_return(%w(foo))
      allow(Gitlab::Runtime).to receive(:sidekiq?).and_return(false)

      expect(described_class.enable?).to eq(true)
    end

    it 'returns true when service discovery is enabled' do
      allow(described_class).to receive(:hosts).and_return([])
      allow(Gitlab::Runtime).to receive(:sidekiq?).and_return(false)

      allow(described_class)
        .to receive(:service_discovery_enabled?)
        .and_return(true)

      expect(described_class.enable?).to eq(true)
    end

    context 'without a license' do
      before do
        License.destroy_all # rubocop: disable Cop/DestroyAll
      end

      it 'is disabled' do
        expect(described_class.enable?).to eq(false)
      end
    end

    context 'with an EES license' do
      let!(:license) { create(:license, plan: ::License::STARTER_PLAN) }

      it 'is disabled' do
        expect(described_class.enable?).to eq(false)
      end
    end

    context 'with an EEP license' do
      let!(:license) { create(:license, plan: ::License::PREMIUM_PLAN) }

      it 'is enabled' do
        allow(described_class).to receive(:hosts).and_return(%w(foo))
        allow(Gitlab::Runtime).to receive(:sidekiq?).and_return(false)

        expect(described_class.enable?).to eq(true)
      end
    end
  end

  describe '.configured?' do
    let!(:license) { create(:license, plan: ::License::PREMIUM_PLAN) }

    it 'returns true when Sidekiq is being used' do
      allow(described_class).to receive(:hosts).and_return(%w(foo))
      allow(Gitlab::Runtime).to receive(:sidekiq?).and_return(true)

      expect(described_class.configured?).to eq(true)
    end

    it 'returns true when service discovery is enabled in Sidekiq' do
      allow(described_class).to receive(:hosts).and_return([])
      allow(Gitlab::Runtime).to receive(:sidekiq?).and_return(true)

      allow(described_class)
        .to receive(:service_discovery_enabled?)
        .and_return(true)

      expect(described_class.configured?).to eq(true)
    end

    it 'returns false when neither service discovery nor hosts are configured' do
      allow(described_class).to receive(:hosts).and_return([])

      allow(described_class)
        .to receive(:service_discovery_enabled?)
        .and_return(false)

      expect(described_class.configured?).to eq(false)
    end

    context 'without a license' do
      before do
        License.destroy_all # rubocop: disable Cop/DestroyAll
      end

      it 'is not configured' do
        expect(described_class.configured?).to eq(false)
      end
    end
  end

  describe '.configure_proxy' do
    after do
      described_class.clear_configuration
    end

    it 'configures the connection proxy' do
      allow(ActiveRecord::Base.singleton_class).to receive(:prepend)

      described_class.configure_proxy

      expect(ActiveRecord::Base.singleton_class).to have_received(:prepend)
        .with(Gitlab::Database::LoadBalancing::ActiveRecordProxy)
    end
  end

  describe '.active_record_models' do
    it 'returns an Array' do
      expect(described_class.active_record_models).to be_an_instance_of(Array)
    end
  end

  describe '.service_discovery_enabled?' do
    it 'returns true if service discovery is enabled' do
      allow(described_class)
        .to receive(:configuration)
        .and_return('discover' => { 'record' => 'foo' })

      expect(described_class.service_discovery_enabled?).to eq(true)
    end

    it 'returns false if service discovery is disabled' do
      expect(described_class.service_discovery_enabled?).to eq(false)
    end
  end

  describe '.service_discovery_configuration' do
    context 'when no configuration is provided' do
      it 'returns a default configuration Hash' do
        expect(described_class.service_discovery_configuration).to eq(
          nameserver: 'localhost',
          port: 8600,
          record: nil,
          record_type: 'A',
          interval: 60,
          disconnect_timeout: 120,
          use_tcp: false
        )
      end
    end

    context 'when configuration is provided' do
      it 'returns a Hash including the custom configuration' do
        allow(described_class)
          .to receive(:configuration)
          .and_return('discover' => { 'record' => 'foo', 'record_type' => 'SRV' })

        expect(described_class.service_discovery_configuration).to eq(
          nameserver: 'localhost',
          port: 8600,
          record: 'foo',
          record_type: 'SRV',
          interval: 60,
          disconnect_timeout: 120,
          use_tcp: false
        )
      end
    end
  end

  describe '.start_service_discovery' do
    it 'does not start if service discovery is disabled' do
      expect(Gitlab::Database::LoadBalancing::ServiceDiscovery)
        .not_to receive(:new)

      described_class.start_service_discovery
    end

    it 'starts service discovery if enabled' do
      allow(described_class)
        .to receive(:service_discovery_enabled?)
        .and_return(true)

      instance = double(:instance)

      expect(Gitlab::Database::LoadBalancing::ServiceDiscovery)
        .to receive(:new)
        .with(an_instance_of(Hash))
        .and_return(instance)

      expect(instance)
        .to receive(:start)

      described_class.start_service_discovery
    end
  end

  describe '.db_role_for_connection' do
    let(:connection) { double(:conneciton) }

    context 'when the load balancing is not configured' do
      before do
        allow(described_class).to receive(:enable?).and_return(false)
      end

      it 'returns primary' do
        expect(described_class.db_role_for_connection(connection)).to be(:primary)
      end
    end

    context 'when the load balancing is configured' do
      let(:proxy) { described_class::ConnectionProxy.new(%w(foo)) }
      let(:load_balancer) { described_class::LoadBalancer.new(%w(foo)) }

      before do
        allow(ActiveRecord::Base.singleton_class).to receive(:prepend)

        allow(described_class).to receive(:enable?).and_return(true)
        allow(described_class).to receive(:proxy).and_return(proxy)
        allow(proxy).to receive(:load_balancer).and_return(load_balancer)

        subject.configure_proxy(proxy)
      end

      after do
        subject.clear_configuration
      end

      context 'when the load balancer returns :replica' do
        it 'returns :replica' do
          allow(load_balancer).to receive(:db_role_for_connection).and_return(:replica)

          expect(described_class.db_role_for_connection(connection)).to be(:replica)

          expect(load_balancer).to have_received(:db_role_for_connection).with(connection)
        end
      end

      context 'when the load balancer returns :primary' do
        it 'returns :primary' do
          allow(load_balancer).to receive(:db_role_for_connection).and_return(:primary)

          expect(described_class.db_role_for_connection(connection)).to be(:primary)

          expect(load_balancer).to have_received(:db_role_for_connection).with(connection)
        end
      end

      context 'when the load balancer returns nil' do
        it 'returns :primary' do
          allow(load_balancer).to receive(:db_role_for_connection).and_return(nil)

          expect(described_class.db_role_for_connection(connection)).to be(:primary)

          expect(load_balancer).to have_received(:db_role_for_connection).with(connection)
        end
      end
    end
  end
end
