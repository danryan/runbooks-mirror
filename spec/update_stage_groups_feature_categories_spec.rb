# frozen_string_literal: true

require 'spec_helper'

require_relative '../scripts/update_stage_groups_feature_categories'

describe UpdateStageGroupsFeatureCategories do
  subject { described_class.new(stage_url, mapping_path, logger) }

  let(:tmp_dir) { Dir.mktmpdir }
  let(:stage_url) { 'http://example.local/stages.yml' }
  let(:mapping_path) { "#{tmp_dir}/stage-group-mapping.jsonnet" }
  let(:stages_yml) do
    <<~YAML
      stages:
        manage:
          pm: Jeremy Watson
          groups:
            access:
              name: Access
              pm: Melissa Ushakov
              focus: Manage Access Paid GMAU
              categories:
                - authentication_and_authorization
                - subgroups
                - users
            ML/AI:
              name: Machine Learning
              categories:
                - mlops
                - insider_threat
            compliance:
              name: Compliance
              pm: Matt Gonzales
              focus: Manage Compliance Paid GMAU
              categories:
                - audit_events
                - audit_reports
                - compliance_management

        plan:
          pm: Jeremy Watson
          groups:
            project_management:
              name: Project Management
              pm: Gabe Weaver
              categories:
                - issue_tracking
                - boards
                - time_tracking
                - jira_importer
                - projects

            product_planning:
              name: Product Planning
              pm: Christen Dybenko
              categories:
                - epics
                - roadmaps
                - design_management
    YAML
  end

  let(:stages_jsonnet) do
    <<~JSONNET
        // This file is autogenerated using scripts/update_stage_groups_feature_categories.rb
        // Please don't update manually
        {
          access: {
            name: 'Access',
            stage: 'manage',
            feature_categories: [
              'authentication_and_authorization',
              'subgroups',
              'users',
            ],
          },
          'ml-ai': {
            name: 'Machine Learning',
            stage: 'manage',
            feature_categories: [
              'mlops',
              'insider_threat',
            ],
          },
          compliance: {
            name: 'Compliance',
            stage: 'manage',
            feature_categories: [
              'audit_events',
              'audit_reports',
              'compliance_management',
            ],
          },
          project_management: {
            name: 'Project Management',
            stage: 'plan',
            feature_categories: [
              'issue_tracking',
              'boards',
              'time_tracking',
              'jira_importer',
              'projects',
            ],
          },
          product_planning: {
            name: 'Product Planning',
            stage: 'plan',
            feature_categories: [
              'epics',
              'roadmaps',
              'design_management',
            ],
          },
        }
    JSONNET
  end

  let(:logger) { Logger.new(StringIO.new) }

  before do
    stub_request(:get, "http://example.local/stages.yml").to_return(body: stages_yml)
  end

  after do
    FileUtils.remove_entry tmp_dir
  end

  context 'when mapping file does not exist' do
    it 'generates a new group info file' do
      expect(File.exist?(mapping_path)).to eq(false)

      subject.call

      expect(File.exist?(mapping_path)).to eq(true)
      expect(File.read(mapping_path)).to eq(stages_jsonnet)
    end
  end

  context 'when mapping file already exists' do
    before do
      File.write(
        mapping_path, <<~JSONNET
        {
          access: {
            name: 'Access',
            stage: 'manage',
            feature_categories: [
              'authentication_and_authorization',
              'subgroups',
              'users',
            ],
          },
          compliance: {
            name: 'Compliance',
            stage: 'manage',
            feature_categories: [
              'audit_events',
              'audit_reports',
              'compliance_management',
            ],
          }
        }
        JSONNET
      )
    end

    it 'overrides with new group info' do
      expect(File.exist?(mapping_path)).to eq(true)

      subject.call

      expect(File.read(mapping_path)).to eq(stages_jsonnet)
    end
  end

  context 'when the mapping contains a category multiple times' do
    let(:stages_yml) do
      <<~YAML
        stages:
          growth:
            groups:
              activation:
                name: Activation
                categories:
                  - experimentation
                  - onboarding
              conversion:
                name: Conversion
                categories:
                  - onboarding
                  - experimentation
              expansion:
                name: Expansion
                categories:
                  - experimentation
                  - expansion
      YAML
    end

    let(:stages_jsonnet) do
      <<~JSONNET
      // This file is autogenerated using scripts/update_stage_groups_feature_categories.rb
      // Please don't update manually
      {
        activation: {
          name: 'Activation',
          stage: 'growth',
          feature_categories: [
            'experimentation',
            'onboarding',
          ],
        },
        conversion: {
          name: 'Conversion',
          stage: 'growth',
          feature_categories: [

          ],
        },
        expansion: {
          name: 'Expansion',
          stage: 'growth',
          feature_categories: [
            'expansion',
          ],
        },
      }
      JSONNET
    end

    it "only writes the feature category to the first group and logs warnigns for the others" do
      expect(logger).to receive(:warn).with(/experimentation was already in activation not adding to conversion/)
      expect(logger).to receive(:warn).with(/experimentation was already in activation not adding to expansion/)

      subject.call

      expect(File.read(mapping_path)).to eq(stages_jsonnet)
    end
  end
end
