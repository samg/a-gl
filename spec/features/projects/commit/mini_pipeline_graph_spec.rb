# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Mini Pipeline Graph in Commit View', :js do
  let(:project) { create(:project, :public, :repository) }

  context 'when commit has pipelines' do
    let(:pipeline) do
      create(:ci_pipeline,
              status: :running,
              project: project,
              ref: project.default_branch,
              sha: project.commit.sha)
    end

    let(:build) { create(:ci_build, pipeline: pipeline, status: :running) }

    shared_examples 'shows ci icon and mini pipeline' do
      before do
        build.run
        visit project_commit_path(project, project.commit.id)
      end

      it 'display icon with status' do
        expect(page).to have_selector('.ci-status-icon-running')
      end

      it 'displays a mini pipeline graph' do
        expect(page).to have_selector('.mr-widget-pipeline-graph')

        first('.mini-pipeline-graph-dropdown-toggle').click

        wait_for_requests

        page.within '.js-builds-dropdown-list' do
          expect(page).to have_selector('.ci-status-icon-running')
          expect(page).to have_content(build.stage)
        end

        build.drop
      end
    end

    context 'when ci_commit_pipeline_mini_graph_vue is disabled' do
      before do
        stub_feature_flags(ci_commit_pipeline_mini_graph_vue: false)
      end

      it_behaves_like 'shows ci icon and mini pipeline'
    end

    context 'when ci_commit_pipeline_mini_graph_vue is enabled' do
      before do
        stub_feature_flags(ci_commit_pipeline_mini_graph_vue: true)
      end

      it_behaves_like 'shows ci icon and mini pipeline'
    end
  end

  context 'when commit does not have pipelines' do
    before do
      visit project_commit_path(project, project.commit.id)
    end

    it 'does not display a mini pipeline graph' do
      expect(page).not_to have_selector('.mr-widget-pipeline-graph')
    end
  end
end
