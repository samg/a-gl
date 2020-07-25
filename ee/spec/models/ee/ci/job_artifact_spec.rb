# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::JobArtifact do
  using RSpec::Parameterized::TableSyntax
  include EE::GeoHelpers

  describe '#destroy' do
    let_it_be(:primary) { create(:geo_node, :primary) }
    let_it_be(:secondary) { create(:geo_node) }

    it 'creates a JobArtifactDeletedEvent' do
      stub_current_geo_node(primary)

      job_artifact = create(:ee_ci_job_artifact, :archive)

      expect do
        job_artifact.destroy
      end.to change { Geo::JobArtifactDeletedEvent.count }.by(1)
    end
  end

  describe '.license_scanning_reports' do
    subject { Ci::JobArtifact.license_scanning_reports }

    context 'when there is a license management report' do
      let!(:artifact) { create(:ee_ci_job_artifact, :license_management) }

      it { is_expected.to eq([artifact]) }
    end

    context 'when there is a license scanning report' do
      let!(:artifact) { create(:ee_ci_job_artifact, :license_scanning) }

      it { is_expected.to eq([artifact]) }
    end
  end

  describe '.metrics_reports' do
    subject { Ci::JobArtifact.metrics_reports }

    context 'when there is a metrics report' do
      let!(:artifact) { create(:ee_ci_job_artifact, :metrics) }

      it { is_expected.to eq([artifact]) }
    end

    context 'when there is no metrics reports' do
      let!(:artifact) { create(:ee_ci_job_artifact, :trace) }

      it { is_expected.to be_empty }
    end
  end

  describe '.security_reports' do
    subject { Ci::JobArtifact.security_reports }

    context 'when there is a security report' do
      let!(:sast_artifact) { create(:ee_ci_job_artifact, :sast) }
      let!(:secret_detection_artifact) { create(:ee_ci_job_artifact, :secret_detection) }

      it { is_expected.to eq([sast_artifact, secret_detection_artifact]) }
    end

    context 'when there are no security reports' do
      let!(:artifact) { create(:ci_job_artifact, :archive) }

      it { is_expected.to be_empty }
    end
  end

  describe '.coverage_fuzzing_reports' do
    subject { Ci::JobArtifact.coverage_fuzzing }

    context 'when there is a metrics report' do
      let!(:artifact) { create(:ee_ci_job_artifact, :coverage_fuzzing) }

      it { is_expected.to eq([artifact]) }
    end

    context 'when there is no coverage fuzzing reports' do
      let!(:artifact) { create(:ee_ci_job_artifact, :trace) }

      it { is_expected.to be_empty }
    end
  end

  describe '.associated_file_types_for' do
    using RSpec::Parameterized::TableSyntax

    subject { Ci::JobArtifact.associated_file_types_for(file_type) }

    where(:file_type, :result) do
      'license_scanning'    | %w(license_management license_scanning)
      'codequality'         | %w(codequality)
      'browser_performance' | %w(browser_performance performance)
      'load_performance'    | %w(load_performance)
      'quality'             | nil
    end

    with_them do
      it { is_expected.to eq result }
    end
  end

  describe '#replicables_for_geo_node' do
    # Selective sync is configured relative to the job artifact's project.
    #
    # Permutations of sync_object_storage combined with object-stored-artifacts
    # are tested in code, because the logic is simple, and to do it in the table
    # would quadruple its size and have too much duplication.
    where(:selective_sync_namespaces, :selective_sync_shards, :project_factory, :include_expectation) do
      nil                  | nil    | [:project]               | true
      # selective sync by shard
      nil                  | :model | [:project]               | true
      nil                  | :other | [:project]               | false
      # selective sync by namespace
      :model_parent        | nil    | [:project]               | true
      :model_parent_parent | nil    | [:project, :in_subgroup] | true
      :other               | nil    | [:project]               | false
      :other               | nil    | [:project, :in_subgroup] | false
    end

    with_them do
      subject(:job_artifact_included) { described_class.replicables_for_geo_node.include?(ci_job_artifact) }

      let(:factory) { [:ci_job_artifact]}
      let(:project) { create(*project_factory) }
      let(:ci_build) { create(:ci_build, project: project) }
      let(:node) do
        create_geo_node_to_test_replicables_for_geo_node(
          project,
          selective_sync_namespaces: selective_sync_namespaces,
          selective_sync_shards: selective_sync_shards,
          sync_object_storage: sync_object_storage)
      end

      before do
        stub_artifacts_object_storage
        stub_current_geo_node(node)
      end

      context 'when sync object storage is enabled' do
        let(:sync_object_storage) { true }

        context 'when the job artifact is locally stored' do
          let(:ci_job_artifact) { create(*factory, job: ci_build) }

          it { is_expected.to eq(include_expectation) }
        end

        context 'when the job artifact is object stored' do
          let(:ci_job_artifact) { create(*factory, :remote_store, job: ci_build) }

          it { is_expected.to eq(include_expectation) }
        end
      end

      context 'when sync object storage is disabled' do
        let(:sync_object_storage) { false }

        context 'when the job artifact is locally stored' do
          let(:ci_job_artifact) { create(*factory, job: ci_build) }

          it { is_expected.to eq(include_expectation) }
        end

        context 'when the job artifact is object stored' do
          let(:ci_job_artifact) { create(*factory, :remote_store, job: ci_build) }

          it { is_expected.to be_falsey }
        end
      end
    end
  end
end
