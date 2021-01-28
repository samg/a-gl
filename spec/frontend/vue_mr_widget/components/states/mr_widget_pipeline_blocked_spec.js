import { shallowMount, mount } from '@vue/test-utils';
import PipelineBlockedComponent from '~/vue_merge_request_widget/components/states/mr_widget_pipeline_blocked.vue';

describe('MRWidgetPipelineBlocked', () => {
  let wrapper;

  const createWrapper = (mountFn = shallowMount) => {
    wrapper = mountFn(PipelineBlockedComponent);
  };

  afterEach(() => {
    wrapper.destroy();
  });

  it('renders warning icon', () => {
    createWrapper(mount);

    expect(wrapper.find('.ci-status-icon-warning').exists()).toBe(true);
  });

  it('renders information text', () => {
    createWrapper();

    expect(wrapper.text()).toBe(
      'Pipeline blocked. The pipeline for this merge request requires a manual action to proceed',
    );
  });
});
