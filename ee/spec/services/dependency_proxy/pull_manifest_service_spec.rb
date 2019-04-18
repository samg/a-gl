# frozen_string_literal: true
require 'spec_helper'

describe DependencyProxy::PullManifestService do
  include EE::DependencyProxyHelpers

  let(:image) { 'alpine' }
  let(:tag) { '3.9' }
  let(:token) { Digest::SHA256.hexdigest('123') }
  let(:manifest) { { foo: 'bar' }.to_json }

  subject { described_class.new(image, tag, token).execute }

  context 'remote request is successful' do
    before do
      stub_manifest_download(image, tag)
    end

    it { expect(subject[:code]).to eq(200) }
    it { expect(subject[:body]).to eq(manifest) }
  end

  context 'remote request is not found' do
    before do
      stub_manifest_download(image, tag, 404, 'Not found')
    end

    it { expect(subject[:code]).to eq(404) }
    it { expect(subject[:body]).to eq('Not found') }
  end

  context 'net timeout exception' do
    before do
      manifest_link = DependencyProxy::Registry.manifest_url(image, tag)

      stub_request(:get, manifest_link).to_timeout
    end

    it { expect(subject[:code]).to eq(599) }
    it { expect(subject[:body]).to eq('execution expired') }
  end
end
