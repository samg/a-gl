# frozen_string_literal: true

module Groups
  # Service class for counting and caching the number of open issues of a group.
  # class OpenIssuesCountService < IssuablesCountService
  class OpenIssuesCountService < BaseCountService
    include Gitlab::Utils::StrongMemoize

    VERSION = 1
    PUBLIC_COUNT_KEY = 'group_public_open_issues_count'
    TOTAL_COUNT_KEY = 'group_total_open_issues_count'
    CACHED_COUNT_THRESHOLD = 1000
    EXPIRATION_TIME = 24.hours

    def initialize(group, user = nil)
      @group = group
      @user = user
    end

    def count
      cached_count = Rails.cache.read(cache_key)

      if cached_count && cached_count >= CACHED_COUNT_THRESHOLD
        cached_count
      else
        new_count = uncached_count
        update_cache_for_key(cache_key) { new_count }
        new_count
      end
    end

    def cache_options
      super.merge({ expires_in: EXPIRATION_TIME })
    end

    def cache_key(key = nil)
      ['groups', 'open_issues_count_service', VERSION, @group.id, cache_key_name]
    end

    def cache_key_name
      public_only? ? PUBLIC_COUNT_KEY : TOTAL_COUNT_KEY
    end

    def public_only?
      !user_is_at_least_reporter?
    end

    def user_is_at_least_reporter?
      strong_memoize(:user_is_at_least_reporter) do
        @user && @group.member?(@user, Gitlab::Access::REPORTER)
      end
    end

    def relation_for_count
      self.class.query(@group, user: @user, public_only: public_only?)
    end

    def self.query(group, user: nil, public_only: true)
      IssuesFinder.new(user, group_id: group.id, state: 'opened', non_archived: true, include_subgroups: true, public_only: public_only).execute
    end
  end
end
