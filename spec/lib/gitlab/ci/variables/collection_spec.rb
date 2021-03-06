# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ci::Variables::Collection do
  describe '.new' do
    it 'can be initialized with an array' do
      variable = { key: 'VAR', value: 'value', public: true, masked: false }

      collection = described_class.new([variable])

      expect(collection.first.to_runner_variable).to eq variable
    end

    it 'can be initialized without an argument' do
      is_expected.to be_none
    end
  end

  describe '#append' do
    it 'appends a hash' do
      subject.append(key: 'VARIABLE', value: 'something')

      is_expected.to be_one
    end

    it 'appends a Ci::Variable' do
      subject.append(build(:ci_variable))

      is_expected.to be_one
    end

    it 'appends an internal resource' do
      collection = described_class.new([{ key: 'TEST', value: '1' }])

      subject.append(collection.first)

      is_expected.to be_one
    end

    it 'returns self' do
      expect(subject.append(key: 'VAR', value: 'test'))
        .to eq subject
    end
  end

  describe '#concat' do
    it 'appends all elements from an array' do
      collection = described_class.new([{ key: 'VAR_1', value: '1' }])
      variables = [{ key: 'VAR_2', value: '2' }, { key: 'VAR_3', value: '3' }]

      collection.concat(variables)

      expect(collection).to include(key: 'VAR_1', value: '1', public: true)
      expect(collection).to include(key: 'VAR_2', value: '2', public: true)
      expect(collection).to include(key: 'VAR_3', value: '3', public: true)
    end

    it 'appends all elements from other collection' do
      collection = described_class.new([{ key: 'VAR_1', value: '1' }])
      additional = described_class.new([{ key: 'VAR_2', value: '2' },
                                        { key: 'VAR_3', value: '3' }])

      collection.concat(additional)

      expect(collection).to include(key: 'VAR_1', value: '1', public: true)
      expect(collection).to include(key: 'VAR_2', value: '2', public: true)
      expect(collection).to include(key: 'VAR_3', value: '3', public: true)
    end

    it 'does not concatenate resource if it undefined' do
      collection = described_class.new([{ key: 'VAR_1', value: '1' }])

      collection.concat(nil)

      expect(collection).to be_one
    end

    it 'returns self' do
      expect(subject.concat([key: 'VAR', value: 'test']))
        .to eq subject
    end
  end

  describe '#+' do
    it 'makes it possible to combine with an array' do
      collection = described_class.new([{ key: 'TEST', value: '1' }])
      variables = [{ key: 'TEST', value: 'something' }]

      expect((collection + variables).count).to eq 2
    end

    it 'makes it possible to combine with another collection' do
      collection = described_class.new([{ key: 'TEST', value: '1' }])
      other = described_class.new([{ key: 'TEST', value: '2' }])

      expect((collection + other).count).to eq 2
    end
  end

  describe '#[]' do
    variable = { key: 'VAR', value: 'value', public: true, masked: false }

    collection = described_class.new([variable])

    it 'returns nil for a non-existent variable name' do
      expect(collection['UNKNOWN_VAR']).to be_nil
    end

    it 'returns Item for an existent variable name' do
      expect(collection['VAR']).to be_an_instance_of(Gitlab::Ci::Variables::Collection::Item)
      expect(collection['VAR'].to_runner_variable).to eq(variable)
    end
  end

  describe '#size' do
    it 'returns zero for empty collection' do
      collection = described_class.new([])

      expect(collection.size).to eq(0)
    end

    it 'returns 2 for collection with 2 variables' do
      collection = described_class.new(
        [
          { key: 'VAR1', value: 'value', public: true, masked: false },
          { key: 'VAR2', value: 'value', public: true, masked: false }
        ])

      expect(collection.size).to eq(2)
    end

    it 'returns 3 for collection with 2 duplicate variables' do
      collection = described_class.new(
        [
          { key: 'VAR1', value: 'value', public: true, masked: false },
          { key: 'VAR2', value: 'value', public: true, masked: false },
          { key: 'VAR1', value: 'value', public: true, masked: false }
        ])

      expect(collection.size).to eq(3)
    end
  end

  describe '#to_runner_variables' do
    it 'creates an array of hashes in a runner-compatible format' do
      collection = described_class.new([{ key: 'TEST', value: '1' }])

      expect(collection.to_runner_variables)
        .to eq [{ key: 'TEST', value: '1', public: true, masked: false }]
    end
  end

  describe '#to_hash' do
    it 'returns regular hash in valid order without duplicates' do
      collection = described_class.new
        .append(key: 'TEST1', value: 'test-1')
        .append(key: 'TEST2', value: 'test-2')
        .append(key: 'TEST1', value: 'test-3')

      expect(collection.to_hash).to eq('TEST1' => 'test-3',
                                       'TEST2' => 'test-2')

      expect(collection.to_hash).to include(TEST1: 'test-3')
      expect(collection.to_hash).not_to include(TEST1: 'test-1')
    end
  end

  describe '#reject' do
    let(:collection) do
      described_class.new
        .append(key: 'CI_JOB_NAME', value: 'test-1')
        .append(key: 'CI_BUILD_ID', value: '1')
        .append(key: 'TEST1', value: 'test-3')
    end

    subject { collection.reject { |var| var[:key] =~ /\ACI_(JOB|BUILD)/ } }

    it 'returns a Collection instance' do
      is_expected.to be_an_instance_of(described_class)
    end

    it 'returns correctly filtered Collection' do
      comp = collection.to_runner_variables.reject { |var| var[:key] =~ /\ACI_(JOB|BUILD)/ }
      expect(subject.to_runner_variables).to eq(comp)
    end
  end

  describe '#expand_value' do
    let(:collection) do
      Gitlab::Ci::Variables::Collection.new
                     .append(key: 'CI_JOB_NAME', value: 'test-1')
                     .append(key: 'CI_BUILD_ID', value: '1')
                     .append(key: 'RAW_VAR', value: '$TEST1', raw: true)
                     .append(key: 'TEST1', value: 'test-3')
    end

    context 'table tests' do
      using RSpec::Parameterized::TableSyntax

      where do
        {
          "empty value": {
            value: '',
            result: '',
            keep_undefined: false
          },
          "simple expansions": {
            value: 'key$TEST1-$CI_BUILD_ID',
            result: 'keytest-3-1',
            keep_undefined: false
          },
          "complex expansion": {
            value: 'key${TEST1}-${CI_JOB_NAME}',
            result: 'keytest-3-test-1',
            keep_undefined: false
          },
          "complex expansions with raw variable": {
            value: 'key${RAW_VAR}-${CI_JOB_NAME}',
            result: 'key$TEST1-test-1',
            keep_undefined: false
          },
          "missing variable not keeping original": {
            value: 'key${MISSING_VAR}-${CI_JOB_NAME}',
            result: 'key-test-1',
            keep_undefined: false
          },
          "missing variable keeping original": {
            value: 'key${MISSING_VAR}-${CI_JOB_NAME}',
            result: 'key${MISSING_VAR}-test-1',
            keep_undefined: true
          }
        }
      end

      with_them do
        subject { collection.expand_value(value, keep_undefined: keep_undefined) }

        it 'matches expected expansion' do
          is_expected.to eq(result)
        end
      end
    end
  end

  describe '#sort_and_expand_all' do
    context 'when FF :variable_inside_variable is disabled' do
      let_it_be(:project_with_flag_disabled) { create(:project) }
      let_it_be(:project_with_flag_enabled) { create(:project) }

      before do
        stub_feature_flags(variable_inside_variable: [project_with_flag_enabled])
      end

      context 'table tests' do
        using RSpec::Parameterized::TableSyntax

        where do
          {
            "empty array": {
              variables: [],
              keep_undefined: false
            },
            "simple expansions": {
              variables: [
                { key: 'variable', value: 'value' },
                { key: 'variable2', value: 'result' },
                { key: 'variable3', value: 'key$variable$variable2' }
              ],
              keep_undefined: false
            },
            "complex expansion": {
              variables: [
                { key: 'variable', value: 'value' },
                { key: 'variable2', value: 'key${variable}' }
              ],
              keep_undefined: false
            },
            "out-of-order variable reference": {
              variables: [
                { key: 'variable2', value: 'key${variable}' },
                { key: 'variable', value: 'value' }
              ],
              keep_undefined: false
            },
            "complex expansions with raw variable": {
              variables: [
                { key: 'variable3', value: 'key_${variable}_${variable2}' },
                { key: 'variable', value: '$variable2', raw: true },
                { key: 'variable2', value: 'value2' }
              ],
              keep_undefined: false
            },
            "array with cyclic dependency": {
              variables: [
                { key: 'variable', value: '$variable2' },
                { key: 'variable2', value: '$variable3' },
                { key: 'variable3', value: 'key$variable$variable2' }
              ],
              keep_undefined: true
            }
          }
        end

        with_them do
          let(:collection) { Gitlab::Ci::Variables::Collection.new(variables, keep_undefined: keep_undefined) }

          subject { collection.sort_and_expand_all(project_with_flag_disabled) }

          it 'returns Collection' do
            is_expected.to be_an_instance_of(Gitlab::Ci::Variables::Collection)
          end

          it 'does not expand variables' do
            var_hash = variables.pluck(:key, :value).to_h
            expect(subject.to_hash).to eq(var_hash)
          end
        end
      end
    end

    context 'when FF :variable_inside_variable is enabled' do
      let_it_be(:project_with_flag_disabled) { create(:project) }
      let_it_be(:project_with_flag_enabled) { create(:project) }

      before do
        stub_feature_flags(variable_inside_variable: [project_with_flag_enabled])
      end

      context 'table tests' do
        using RSpec::Parameterized::TableSyntax

        where do
          {
            "empty array": {
              variables: [],
              keep_undefined: false,
              result: []
            },
            "simple expansions": {
              variables: [
                { key: 'variable', value: 'value' },
                { key: 'variable2', value: 'result' },
                { key: 'variable3', value: 'key$variable$variable2' },
                { key: 'variable4', value: 'key$variable$variable3' }
              ],
              keep_undefined: false,
              result: [
                { key: 'variable', value: 'value' },
                { key: 'variable2', value: 'result' },
                { key: 'variable3', value: 'keyvalueresult' },
                { key: 'variable4', value: 'keyvaluekeyvalueresult' }
              ]
            },
            "complex expansion": {
              variables: [
                { key: 'variable', value: 'value' },
                { key: 'variable2', value: 'key${variable}' }
              ],
              keep_undefined: false,
              result: [
                { key: 'variable', value: 'value' },
                { key: 'variable2', value: 'keyvalue' }
              ]
            },
            "unused variables": {
              variables: [
                { key: 'variable', value: 'value' },
                { key: 'variable2', value: 'result2' },
                { key: 'variable3', value: 'result3' },
                { key: 'variable4', value: 'key$variable$variable3' }
              ],
              keep_undefined: false,
              result: [
                { key: 'variable', value: 'value' },
                { key: 'variable2', value: 'result2' },
                { key: 'variable3', value: 'result3' },
                { key: 'variable4', value: 'keyvalueresult3' }
              ]
            },
            "complex expansions": {
              variables: [
                { key: 'variable', value: 'value' },
                { key: 'variable2', value: 'result' },
                { key: 'variable3', value: 'key${variable}${variable2}' }
              ],
              keep_undefined: false,
              result: [
                { key: 'variable', value: 'value' },
                { key: 'variable2', value: 'result' },
                { key: 'variable3', value: 'keyvalueresult' }
              ]
            },
            "out-of-order expansion": {
              variables: [
                { key: 'variable3', value: 'key$variable2$variable' },
                { key: 'variable', value: 'value' },
                { key: 'variable2', value: 'result' }
              ],
              keep_undefined: false,
              result: [
                { key: 'variable2', value: 'result' },
                { key: 'variable', value: 'value' },
                { key: 'variable3', value: 'keyresultvalue' }
              ]
            },
            "out-of-order complex expansion": {
              variables: [
                { key: 'variable', value: 'value' },
                { key: 'variable2', value: 'result' },
                { key: 'variable3', value: 'key${variable2}${variable}' }
              ],
              keep_undefined: false,
              result: [
                { key: 'variable', value: 'value' },
                { key: 'variable2', value: 'result' },
                { key: 'variable3', value: 'keyresultvalue' }
              ]
            },
            "missing variable": {
              variables: [
                { key: 'variable2', value: 'key$variable' }
              ],
              keep_undefined: false,
              result: [
                { key: 'variable2', value: 'key' }
              ]
            },
            "missing variable keeping original": {
              variables: [
                { key: 'variable2', value: 'key$variable' }
              ],
              keep_undefined: true,
              result: [
                { key: 'variable2', value: 'key$variable' }
              ]
            },
            "complex expansions with missing variable keeping original": {
              variables: [
                { key: 'variable4', value: 'key${variable}${variable2}${variable3}' },
                { key: 'variable', value: 'value' },
                { key: 'variable3', value: 'value3' }
              ],
              keep_undefined: true,
              result: [
                { key: 'variable', value: 'value' },
                { key: 'variable3', value: 'value3' },
                { key: 'variable4', value: 'keyvalue${variable2}value3' }
              ]
            },
            "complex expansions with raw variable": {
              variables: [
                { key: 'variable3', value: 'key_${variable}_${variable2}' },
                { key: 'variable', value: '$variable2', raw: true },
                { key: 'variable2', value: 'value2' }
              ],
              keep_undefined: false,
              result: [
                { key: 'variable', value: '$variable2', raw: true },
                { key: 'variable2', value: 'value2' },
                { key: 'variable3', value: 'key_$variable2_value2' }
              ]
            },
            "cyclic dependency causes original array to be returned": {
              variables: [
                { key: 'variable', value: '$variable2' },
                { key: 'variable2', value: '$variable3' },
                { key: 'variable3', value: 'key$variable$variable2' }
              ],
              keep_undefined: false,
              result: [
                { key: 'variable', value: '$variable2' },
                { key: 'variable2', value: '$variable3' },
                { key: 'variable3', value: 'key$variable$variable2' }
              ]
            }
          }
        end

        with_them do
          let(:collection) { Gitlab::Ci::Variables::Collection.new(variables) }

          subject { collection.sort_and_expand_all(project_with_flag_enabled, keep_undefined: keep_undefined) }

          it 'returns Collection' do
            is_expected.to be_an_instance_of(Gitlab::Ci::Variables::Collection)
          end

          it 'expands variables' do
            var_hash = result.to_h { |env| [env.fetch(:key), env.fetch(:value)] }
              .with_indifferent_access
            expect(subject.to_hash).to eq(var_hash)
          end

          it 'preserves raw attribute' do
            expect(subject.pluck(:key, :raw).to_h).to eq(collection.pluck(:key, :raw).to_h)
          end
        end
      end
    end
  end
end
