import { shallowMount } from '@vue/test-utils';
import Main from 'ee/vulnerabilities/components/main.vue';
import Header from 'ee/vulnerabilities/components/header.vue';
import Details from 'ee/vulnerabilities/components/details.vue';
import Footer from 'ee/vulnerabilities/components/footer.vue';
import AxiosMockAdapter from 'axios-mock-adapter';

const mockAxios = new AxiosMockAdapter();

describe('Vulnerability', () => {
  let wrapper;

  const vulnerability = {
    id: 1,
    created_at: new Date().toISOString(),
    report_type: 'sast',
    state: 'detected',
    create_mr_url: '/create_mr_url',
    create_issue_url: '/create_issue_url',
    project_fingerprint: 'abc123',
    pipeline: {
      id: 2,
      created_at: new Date().toISOString(),
      url: 'pipeline_url',
      sourceBranch: 'master',
    },
    description: 'description',
    identifiers: 'identifiers',
    links: 'links',
    location: 'location',
    name: 'name',
    project: {
      full_path: '/project_full_path',
      full_name: 'Test Project',
    },
    discussions_url: '/discussion_url',
    notes_url: '/notes_url',
    can_modify_related_issues: false,
    related_issues_help_path: '/help_path',
    merge_request_feedback: null,
    issue_feedback: null,
    remediation: null,
  };

  const createWrapper = () => {
    wrapper = shallowMount(Main, {
      propsData: {
        vulnerability,
      },
    });
  };

  afterEach(() => {
    wrapper.destroy();
    wrapper = null;
    mockAxios.reset();
  });

  beforeEach(createWrapper);

  const findHeader = () => wrapper.find(Header);
  const findDetails = () => wrapper.find(Details);
  const findFooter = () => wrapper.find(Footer);

  describe('default behavior', () => {
    it('consits of header, details and footer', () => {
      expect(findHeader().exists()).toBe(true);
      expect(findDetails().exists()).toBe(true);
      expect(findFooter().exists()).toBe(true);
    });

    it('passes the correct properties to the children', () => {
      expect(findHeader().props()).toMatchObject({
        initialVulnerability: vulnerability,
      });
      expect(findDetails().props()).toMatchObject({ vulnerability });
      expect(findFooter().props()).toMatchObject({
        vulnerabilityId: vulnerability.id,
        discussionsUrl: vulnerability.discussions_url,
        notesUrl: vulnerability.notes_url,
        solutionInfo: {
          solution: vulnerability.solution,
          remediation: vulnerability.remediation,
          hasDownload: Boolean(vulnerability.has_download),
          hasMr: vulnerability.has_mr,
          hasRemediation: Boolean(vulnerability.has_remediation),
          vulnerabilityFeedbackHelpPath: vulnerability.vulnerability_feedback_help_path,
          isStandaloneVulnerability: true,
        },
        issueFeedback: vulnerability.issue_feedback,
        mergeRequestFeedback: vulnerability.merge_request_feedback,
        canModifyRelatedIssues: vulnerability.can_modify_related_issues,
        project: {
          url: vulnerability.project.full_path,
          value: vulnerability.project.full_name,
        },
        relatedIssuesHelpPath: vulnerability.related_issues_help_path,
      });
    });
  });

  describe('vulnerability state change event', () => {
    let fetchDiscussions;
    let refreshVulnerability;

    beforeEach(() => {
      fetchDiscussions = jest.fn();
      refreshVulnerability = jest.fn();

      findHeader().vm.refreshVulnerability = refreshVulnerability;
      findFooter().vm.fetchDiscussions = fetchDiscussions;
    });

    it('updates the footer notes when the vulnerbility was changed', () => {
      const newState = 'dismissed';

      findHeader().vm.$emit('vulnerability-state-change', newState);

      expect(fetchDiscussions).toHaveBeenCalledTimes(1);
      expect(refreshVulnerability).not.toHaveBeenCalled();
    });

    it('updates the header when the footer received a state-change note', () => {
      findHeader().vm.$emit('vulnerability-state-change', undefined);

      expect(fetchDiscussions).not.toHaveBeenCalled();
      expect(refreshVulnerability).toHaveBeenCalledTimes(1);
    });
  });
});
