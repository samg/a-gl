# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Project.cluster_agents' do
  include GraphqlHelpers

  let_it_be(:project) { create(:project, :public) }
  let_it_be(:current_user) { create(:user, maintainer_projects: [project]) }
  let_it_be(:agents) { create_list(:cluster_agent, 5, project: project) }

  let(:first) { var('Int') }
  let(:cluster_agents_fields) { nil }
  let(:project_fields) do
    query_nodes(:cluster_agents, cluster_agents_fields, args: { first: first }, max_depth: 3)
  end

  let(:query) do
    args = { full_path: project.full_path }

    with_signature([first], graphql_query_for(:project, args, project_fields))
  end

  before do
    stub_licensed_features(cluster_agents: true)
  end

  it 'can retrieve cluster agents' do
    post_graphql(query, current_user: current_user)

    expect(graphql_data_at(:project, :cluster_agents, :nodes)).to match_array(
      agents.map { |agent| a_hash_including('id' => global_id_of(agent)) }
    )
  end

  context 'selecting page info' do
    let(:project_fields) do
      query_nodes(:cluster_agents, args: { first: first }, include_pagination_info: true)
    end

    it 'can paginate cluster agents' do
      post_graphql(query, current_user: current_user, variables: first.with(2))

      expect(graphql_data_at(:project, :cluster_agents, :page_info)).to include(
        'hasNextPage' => be_truthy,
        'hasPreviousPage' => be_falsey
      )
      expect(graphql_data_at(:project, :cluster_agents, :nodes)).to have_attributes(size: 2)
    end
  end

  context 'selecting tokens' do
    let(:cluster_agents_fields) { [:id, query_nodes(:tokens, of: 'ClusterAgentToken')] }

    before do
      create(:cluster_agent_token, agent: agents.first)
      create(:cluster_agent_token, agent: agents.second)
    end

    it 'can select tokens' do
      post_graphql(query, current_user: current_user)

      tokens = graphql_data_at(:project, :cluster_agents, :nodes, :tokens, :nodes)

      expect(tokens).to contain_exactly(
        a_hash_including('id' => be_present),
        a_hash_including('id' => be_present)
      )
    end

    it 'does not suffer from N+1 performance issues' do
      expect do
        post_graphql(query, current_user: current_user)
      end.to issue_same_number_of_queries_as { post_graphql(query, current_user: current_user, variables: [first.with(1)]) }
    end
  end
end
