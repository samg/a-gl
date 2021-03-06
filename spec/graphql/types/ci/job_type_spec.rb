# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ci::JobType do
  specify { expect(described_class.graphql_name).to eq('CiJob') }
  specify { expect(described_class).to require_graphql_authorizations(:read_commit_status) }

  it 'exposes the expected fields' do
    expected_fields = %i[
      id
      shortSha
      pipeline
      name
      needs
      detailedStatus
      scheduledAt
      artifacts
      finished_at
      duration
    ]

    expect(described_class).to have_graphql_fields(*expected_fields)
  end
end
