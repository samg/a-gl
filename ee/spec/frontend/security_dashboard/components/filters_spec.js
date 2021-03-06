import { GlToggle } from '@gitlab/ui';
import { shallowMount, createLocalVue } from '@vue/test-utils';
import Vuex from 'vuex';
import Filters from 'ee/security_dashboard/components/filters.vue';
import createStore from 'ee/security_dashboard/store';

const localVue = createLocalVue();
localVue.use(Vuex);

describe('Filter component', () => {
  let wrapper;
  let store;

  const createWrapper = (props = {}) => {
    wrapper = shallowMount(Filters, {
      localVue,
      store,
      propsData: {
        ...props,
      },
      slots: {
        buttons: '<div class="button-slot"></div>',
      },
    });
  };

  beforeEach(() => {
    store = createStore();
  });

  afterEach(() => {
    wrapper.destroy();
    wrapper = null;
  });

  describe('severity', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('should display all filters', () => {
      expect(wrapper.findAll('.js-filter')).toHaveLength(2);
    });

    it('should display "Hide dismissed vulnerabilities" toggle', () => {
      expect(wrapper.findComponent(GlToggle).props('label')).toBe(Filters.i18n.toggleLabel);
    });
  });

  describe('buttons slot', () => {
    it('should exist', () => {
      createWrapper();
      expect(wrapper.find('.button-slot').exists()).toBe(true);
    });
  });
});
