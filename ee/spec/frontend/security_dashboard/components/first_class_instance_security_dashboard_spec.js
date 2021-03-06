import { shallowMount } from '@vue/test-utils';
import CsvExportButton from 'ee/security_dashboard/components/csv_export_button.vue';
import DashboardNotConfigured from 'ee/security_dashboard/components/empty_states/instance_dashboard_not_configured.vue';
import FirstClassInstanceDashboard from 'ee/security_dashboard/components/first_class_instance_security_dashboard.vue';
import FirstClassInstanceVulnerabilities from 'ee/security_dashboard/components/first_class_instance_security_dashboard_vulnerabilities.vue';
import Filters from 'ee/security_dashboard/components/first_class_vulnerability_filters.vue';
import SecurityDashboardLayout from 'ee/security_dashboard/components/security_dashboard_layout.vue';
import VulnerabilitiesCountList from 'ee/security_dashboard/components/vulnerability_count_list.vue';

describe('First Class Instance Dashboard Component', () => {
  let wrapper;

  const defaultMocks = ({ loading = false } = {}) => ({
    $apollo: { queries: { projects: { loading } } },
  });

  const vulnerabilitiesExportEndpoint = '/vulnerabilities/exports';

  const findInstanceVulnerabilities = () => wrapper.find(FirstClassInstanceVulnerabilities);
  const findCsvExportButton = () => wrapper.find(CsvExportButton);
  const findEmptyState = () => wrapper.find(DashboardNotConfigured);
  const findFilters = () => wrapper.find(Filters);
  const findVulnerabilitiesCountList = () => wrapper.find(VulnerabilitiesCountList);
  const findHeader = () => wrapper.find('[data-testid="header"]');

  const createWrapper = ({ data = {}, stubs, mocks = defaultMocks() }) => {
    return shallowMount(FirstClassInstanceDashboard, {
      data() {
        return { ...data };
      },
      mocks,
      propsData: {
        vulnerabilitiesExportEndpoint,
      },
      stubs: {
        ...stubs,
        SecurityDashboardLayout,
      },
    });
  };

  afterEach(() => {
    wrapper.destroy();
    wrapper = null;
  });

  describe('when initialized', () => {
    beforeEach(() => {
      wrapper = createWrapper({
        data: {
          projects: [{ id: 1 }, { id: 2 }],
        },
      });
    });

    it('should show the header', () => {
      expect(findHeader().exists()).toBe(true);
    });

    it('should render the vulnerabilities', () => {
      expect(findInstanceVulnerabilities().props()).toEqual({
        filters: {},
      });
    });

    it('has filters', () => {
      expect(findFilters().exists()).toBe(true);
    });

    it('responds to the filterChange event', () => {
      const filters = { severity: 'critical' };
      findFilters().vm.$listeners.filterChange(filters);
      return wrapper.vm.$nextTick(() => {
        expect(wrapper.vm.filters).toEqual(filters);
        expect(findInstanceVulnerabilities().props('filters')).toEqual(filters);
      });
    });

    it('displays the csv export button', () => {
      expect(findCsvExportButton().props('vulnerabilitiesExportEndpoint')).toBe(
        vulnerabilitiesExportEndpoint,
      );
    });

    it('displays the vulnerability count list with the correct data', () => {
      expect(findVulnerabilitiesCountList().props()).toMatchObject({
        scope: 'instance',
        filters: wrapper.vm.filters,
      });
    });
  });

  describe('when loading projects', () => {
    beforeEach(() => {
      wrapper = createWrapper({
        mocks: defaultMocks({ loading: true }),
        data: {
          projects: [{ id: 1 }],
        },
      });
    });

    it('does not render the export button, vulnerabilities count list, or header', () => {
      expect(findCsvExportButton().exists()).toBe(false);
      expect(findVulnerabilitiesCountList().exists()).toBe(false);
      expect(findHeader().exists()).toBe(false);
    });
  });

  describe('when uninitialized', () => {
    beforeEach(() => {
      wrapper = createWrapper({
        data: {
          isManipulatingProjects: false,
        },
      });
    });

    it('only renders the empty state', () => {
      expect(findEmptyState().exists()).toBe(true);
      expect(findCsvExportButton().exists()).toBe(false);
      expect(findInstanceVulnerabilities().exists()).toBe(false);
      expect(findFilters().exists()).toBe(false);
      expect(findVulnerabilitiesCountList().exists()).toBe(false);
      expect(findHeader().exists()).toBe(false);
    });
  });
});
