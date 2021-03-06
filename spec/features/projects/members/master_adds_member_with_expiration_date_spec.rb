# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Projects > Members > Maintainer adds member with expiration date', :js do
  include Select2Helper
  include ActiveSupport::Testing::TimeHelpers
  include Spec::Support::Helpers::Features::MembersHelpers

  let_it_be(:maintainer) { create(:user) }
  let_it_be(:project) { create(:project) }
  let(:new_member) { create(:user) }

  before do
    travel_to Time.now.utc.beginning_of_day

    project.add_maintainer(maintainer)
    sign_in(maintainer)
  end

  it 'expiration date is displayed in the members list' do
    stub_feature_flags(invite_members_group_modal: false)

    visit project_project_members_path(project)

    page.within '.invite-users-form' do
      select2(new_member.id, from: '#user_ids', multiple: true)

      fill_in 'expires_at', with: 5.days.from_now.to_date
      find_field('expires_at').native.send_keys :enter

      click_on 'Invite'
    end

    page.within find_member_row(new_member) do
      expect(page).to have_content(/in \d days/)
    end
  end

  it 'changes expiration date' do
    project.team.add_users([new_member.id], :developer, expires_at: 3.days.from_now.to_date)
    visit project_project_members_path(project)

    page.within find_member_row(new_member) do
      fill_in 'Expiration date', with: 5.days.from_now.to_date
      find_field('Expiration date').native.send_keys :enter

      wait_for_requests

      expect(page).to have_content(/in \d days/)
    end
  end

  it 'clears expiration date' do
    project.team.add_users([new_member.id], :developer, expires_at: 5.days.from_now.to_date)
    visit project_project_members_path(project)

    page.within find_member_row(new_member) do
      expect(page).to have_content(/in \d days/)

      find('[data-testid="clear-button"]').click

      wait_for_requests

      expect(page).to have_content('No expiration set')
    end
  end

  def project_member_id
    project.members.find_by(user_id: new_member).id
  end
end
