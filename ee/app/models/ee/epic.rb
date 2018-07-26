module EE
  module Epic
    extend ActiveSupport::Concern

    prepended do
      include AtomicInternalId
      include IidRoutes
      include ::Issuable
      include Noteable
      include Referable
      include Awardable
      include LabelEventable

      belongs_to :assignee, class_name: "User"
      belongs_to :group

      has_internal_id :iid, scope: :group, init: ->(s) { s&.group&.epics&.maximum(:iid) }

      has_many :epic_issues
      has_many :issues, through: :epic_issues

      validates :group, presence: true

      scope :order_start_or_end_date_asc, -> do
        # mysql returns null values first in opposite to postgres which
        # returns them last by default
        nulls_first = ::Gitlab::Database.postgresql? ? 'NULLS FIRST' : ''
        reorder("COALESCE(start_date, end_date) ASC #{nulls_first}")
      end
    end

    module ClassMethods
      # We support internal references (&epic_id) and cross-references (group.full_path&epic_id)
      #
      # Escaped versions with `&amp;` will be extracted too
      #
      # The parent of epic is group instead of project and therefore we have to define new patterns
      def reference_pattern
        @reference_pattern ||= begin
          combined_prefix = Regexp.union(Regexp.escape(reference_prefix), Regexp.escape(reference_prefix_escaped))
          group_regexp = %r{
            (?<!\w)
            (?<group>#{::Gitlab::PathRegex::FULL_NAMESPACE_FORMAT_REGEX})
          }x
          %r{
            (#{group_regexp})?
            (?:#{combined_prefix})(?<epic>\d+)
          }x
        end
      end

      def link_reference_pattern
        %r{
          (?<url>
            #{Regexp.escape(::Gitlab.config.gitlab.url)}
            \/groups\/(?<group>#{::Gitlab::PathRegex::FULL_NAMESPACE_FORMAT_REGEX})
            \/-\/epics
            \/(?<epic>\d+)
            (?<path>
              (\/[a-z0-9_=-]+)*
            )?
            (?<query>
              \?[a-z0-9_=-]+
              (&[a-z0-9_=-]+)*
            )?
            (?<anchor>\#[a-z0-9_-]+)?
          )
        }x
      end

      def order_by(method)
        if method.to_s == 'start_or_end_date'
          order_start_or_end_date_asc
        else
          super
        end
      end

      def parent_class
        ::Group
      end
    end

    def assignees
      Array(assignee)
    end

    def project
      nil
    end

    def supports_weight?
      false
    end

    def upcoming?
      start_date&.future?
    end

    def expired?
      end_date&.past?
    end

    def elapsed_days
      return 0 if start_date.nil? || start_date.future?

      (Date.today - start_date).to_i
    end

    # Needed to use EntityDateHelper#remaining_days_in_words
    alias_attribute(:due_date, :end_date)

    def update_dates
      milestone_data = fetch_milestone_date_data

      self.start_date = start_date_is_fixed? ? start_date_fixed : milestone_data[:start_date]
      self.start_date_sourcing_milestone_id = milestone_data[:start_date_sourcing_milestone_id]
      self.due_date = due_date_is_fixed? ? due_date_fixed : milestone_data[:due_date]
      self.due_date_sourcing_milestone_id = milestone_data[:due_date_sourcing_milestone_id]

      save if changed?
    end

    # Earliest start date from issues' milestones
    def start_date_from_milestones
      start_date_is_fixed? ? epic_issues.joins(issue: :milestone).minimum('milestones.start_date') : start_date
    end

    # Latest end date from issues' milestones
    def due_date_from_milestones
      due_date_is_fixed? ? epic_issues.joins(issue: :milestone).maximum('milestones.due_date') : due_date
    end

    def to_reference(from = nil, full: false)
      reference = "#{self.class.reference_prefix}#{iid}"

      return reference unless cross_reference?(from) || full

      "#{group.full_path}#{reference}"
    end

    def cross_reference?(from)
      from && from != group
    end

    # we don't support project epics for epics yet, planned in the future #4019
    def update_project_counter_caches
    end

    def issues_readable_by(current_user)
      related_issues = ::Issue.select('issues.*, epic_issues.id as epic_issue_id, epic_issues.relative_position')
        .joins(:epic_issue)
        .where("epic_issues.epic_id = #{id}")
        .order('epic_issues.relative_position, epic_issues.id')

      Ability.issues_readable_by_user(related_issues, current_user)
    end

    def mentionable_params
      { group: group, label_url_method: :group_epics_url }
    end

    def discussions_rendered_on_frontend?
      true
    end

    def banzai_render_context(field)
      super.merge(label_url_method: :group_epics_url)
    end

    private

    def fetch_milestone_date_data
      sql = <<~SQL
        SELECT milestones.id, milestones.start_date, milestones.due_date FROM milestones 
        INNER JOIN issues ON issues.milestone_id = milestones.id
        INNER JOIN epic_issues ON epic_issues.issue_id = issues.id
        INNER JOIN (
          SELECT MIN(milestones.start_date) AS start_date, MAX(milestones.due_date) AS due_date
          FROM milestones 
          INNER JOIN issues ON issues.milestone_id = milestones.id
          INNER JOIN epic_issues ON epic_issues.issue_id = issues.id
          WHERE epic_issues.epic_id = #{id}
        ) inner_results ON (inner_results.start_date = milestones.start_date OR inner_results.due_date = milestones.due_date)
        WHERE epic_issues.epic_id = #{id}
        ORDER BY milestones.start_date, milestones.due_date;
      SQL

      db_results = ActiveRecord::Base.connection.select_all(sql).to_a

      results = {}
      db_results.find { |row| row['start_date'] }&.tap do |row|
        results[:start_date] = row['start_date']
        results[:start_date_sourcing_milestone_id] = row['id']
      end
      db_results.reverse.find { |row| row['due_date'] }&.tap do |row|
        results[:due_date] = row['due_date']
        results[:due_date_sourcing_milestone_id] = row['id']
      end
      results
    end
  end
end
