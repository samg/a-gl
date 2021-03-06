# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dashboard Active Tab', :js do
  before do
    stub_feature_flags(combined_menu: false)

    sign_in(create(:user))
  end

  shared_examples 'page has active tab' do |title|
    it "#{title} tab" do
      subject

      expect(page).to have_selector('.navbar-sub-nav li.active', count: 1)
      expect(find('.navbar-sub-nav li.active')).to have_content(title)
    end
  end

  context 'on dashboard projects' do
    it_behaves_like 'page has active tab', 'Projects' do
      subject { visit dashboard_projects_path }
    end
  end

  context 'on dashboard groups' do
    it_behaves_like 'page has active tab', 'Groups' do
      subject { visit dashboard_groups_path }
    end
  end
end
