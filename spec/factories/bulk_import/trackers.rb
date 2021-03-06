# frozen_string_literal: true

FactoryBot.define do
  factory :bulk_import_tracker, class: 'BulkImports::Tracker' do
    association :entity, factory: :bulk_import_entity

    stage { 0 }
    relation { :relation }
    has_next_page { false }
  end
end
