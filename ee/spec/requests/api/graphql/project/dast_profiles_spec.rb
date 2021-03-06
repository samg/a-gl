# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.project(fullPath).dastProfiles' do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:current_user) { create(:user) }
  let_it_be(:dast_profile1) { create(:dast_profile, project: project) }
  let_it_be(:dast_profile2) { create(:dast_profile, project: project) }
  let_it_be(:dast_profile3) { create(:dast_profile, project: project) }
  let_it_be(:dast_profile4) { create(:dast_profile, project: project) }

  subject do
    fields = all_graphql_fields_for('DastProfile')

    query = graphql_query_for(
      :project,
      { full_path: project.full_path },
      query_nodes(:dast_profiles, fields)
    )

    post_graphql(
      query,
      current_user: current_user,
      variables: {
        fullPath: project.full_path
      }
    )
  end

  before do
    stub_licensed_features(security_on_demand_scans: true)
  end

  context 'when a user does not have access to the project' do
    it 'returns a null project' do
      subject

      expect(graphql_data_at(:project)).to be_nil
    end
  end

  context 'when a user does not have access to dast_profiles' do
    it 'returns an empty nodes array' do
      project.add_guest(current_user)

      subject

      expect(graphql_data_at(:project, :dast_profiles, :nodes)).to be_empty
    end
  end

  context 'when a user has access to dast_profiles' do
    before do
      project.add_developer(current_user)
    end

    let(:data_path) { [:project, :dast_profiles] }

    def pagination_results_data(dast_profiles)
      dast_profiles.map { |dast_profile| dast_profile['id'] }
    end

    it_behaves_like 'sorted paginated query' do
      let(:sort_param) { nil }
      let(:first_param) { 3 }

      let(:expected_results) do
        [dast_profile4, dast_profile3, dast_profile2, dast_profile1].map { |validation| global_id_of(validation)}
      end
    end

    it 'includes branch information' do
      subject

      expect(graphql_data_at(:project, :dast_profiles, :nodes, 0, 'branch')).to eq('name' => 'master', 'exists' => true)
    end
  end

  def pagination_query(arguments)
    graphql_query_for(
      :project,
      { full_path: project.full_path },
      query_nodes(:dast_profiles, 'id', include_pagination_info: true, args: arguments)
    )
  end
end
