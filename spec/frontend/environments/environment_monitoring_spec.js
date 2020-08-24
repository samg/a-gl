import { shallowMount } from '@vue/test-utils';
import { GlIcon } from '@gitlab/ui';
import MonitoringComponent from '~/environments/components/environment_monitoring.vue';

describe('Monitoring Component', () => {
  let wrapper;

  const monitoringUrl = 'https://gitlab.com';

  const createWrapper = () => {
    wrapper = shallowMount(MonitoringComponent, {
      propsData: {
        monitoringUrl,
      },
    });
  };

  const findIcons = () => wrapper.findAll(GlIcon);
  const findIconsByName = name => findIcons().filter(icon => icon.props('name') === name);

  beforeEach(() => {
    createWrapper();
  });

  describe('computed', () => {
    it('title', () => {
      expect(wrapper.vm.title).toBe('Monitoring');
    });
  });

  it('should render a link to environment monitoring page', () => {
    expect(wrapper.attributes('href')).toEqual(monitoringUrl);
    expect(findIconsByName('chart').length).toBe(1);
    expect(wrapper.attributes('title')).toBe('Monitoring');
    expect(wrapper.attributes('aria-label')).toBe('Monitoring');
  });
});
