import { createLocalVue, shallowMount } from '@vue/test-utils';
import Vuex from 'vuex';
import EpicFilteredSearch from 'ee_component/boards/components/epic_filtered_search.vue';
import { createStore } from '~/boards/stores';
import * as commonUtils from '~/lib/utils/common_utils';
import FilteredSearchBarRoot from '~/vue_shared/components/filtered_search_bar/filtered_search_bar_root.vue';

const localVue = createLocalVue();
localVue.use(Vuex);

describe('EpicFilteredSearch', () => {
  let wrapper;
  let store;

  const createComponent = () => {
    wrapper = shallowMount(EpicFilteredSearch, {
      localVue,
      provide: { search: '' },
      store,
    });
  };

  const findFilteredSearch = () => wrapper.findComponent(FilteredSearchBarRoot);

  beforeEach(() => {
    // this needed for actions call for performSearch
    window.gon = { features: {} };
  });

  afterEach(() => {
    wrapper.destroy();
  });

  describe('default', () => {
    beforeEach(() => {
      store = createStore();

      jest.spyOn(store, 'dispatch');

      createComponent();
    });

    it('renders FilteredSearch', () => {
      expect(findFilteredSearch().exists()).toBe(true);
    });

    describe('when onFilter is emitted', () => {
      it('calls performSearch', () => {
        findFilteredSearch().vm.$emit('onFilter', [{ value: { data: '' } }]);

        expect(store.dispatch).toHaveBeenCalledWith('performSearch');
      });

      it('calls historyPushState', () => {
        jest.spyOn(commonUtils, 'historyPushState');
        findFilteredSearch().vm.$emit('onFilter', [{ value: { data: 'searchQuery' } }]);

        expect(commonUtils.historyPushState).toHaveBeenCalledWith(
          'http://test.host/?search=searchQuery',
        );
      });
    });
  });
});
