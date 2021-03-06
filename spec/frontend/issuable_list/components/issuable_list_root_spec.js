import { GlSkeletonLoading, GlPagination } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import VueDraggable from 'vuedraggable';

import { TEST_HOST } from 'helpers/test_constants';

import IssuableItem from '~/issuable_list/components/issuable_item.vue';
import IssuableListRoot from '~/issuable_list/components/issuable_list_root.vue';
import IssuableTabs from '~/issuable_list/components/issuable_tabs.vue';
import FilteredSearchBar from '~/vue_shared/components/filtered_search_bar/filtered_search_bar_root.vue';

import { mockIssuableListProps, mockIssuables } from '../mock_data';

const createComponent = ({ props = mockIssuableListProps, data = {} } = {}) =>
  shallowMount(IssuableListRoot, {
    propsData: props,
    data() {
      return data;
    },
    slots: {
      'nav-actions': `
      <button class="js-new-issuable">New issuable</button>
    `,
      'empty-state': `
      <p class="js-issuable-empty-state">Issuable empty state</p>
    `,
    },
    stubs: {
      IssuableTabs,
    },
  });

describe('IssuableListRoot', () => {
  let wrapper;

  const findFilteredSearchBar = () => wrapper.findComponent(FilteredSearchBar);
  const findGlPagination = () => wrapper.findComponent(GlPagination);
  const findIssuableTabs = () => wrapper.findComponent(IssuableTabs);
  const findVueDraggable = () => wrapper.findComponent(VueDraggable);

  afterEach(() => {
    wrapper.destroy();
  });

  describe('computed', () => {
    beforeEach(() => {
      wrapper = createComponent();
    });

    const mockCheckedIssuables = {
      [mockIssuables[0].iid]: { checked: true, issuable: mockIssuables[0] },
      [mockIssuables[1].iid]: { checked: true, issuable: mockIssuables[1] },
      [mockIssuables[2].iid]: { checked: true, issuable: mockIssuables[2] },
    };

    const mIssuables = [mockIssuables[0], mockIssuables[1], mockIssuables[2]];

    describe('skeletonItemCount', () => {
      it.each`
        totalItems | defaultPageSize | currentPage | returnValue
        ${100}     | ${20}           | ${1}        | ${20}
        ${105}     | ${20}           | ${6}        | ${5}
        ${7}       | ${20}           | ${1}        | ${7}
        ${0}       | ${20}           | ${1}        | ${5}
      `(
        'returns $returnValue when totalItems is $totalItems, defaultPageSize is $defaultPageSize and currentPage is $currentPage',
        async ({ totalItems, defaultPageSize, currentPage, returnValue }) => {
          wrapper.setProps({
            totalItems,
            defaultPageSize,
            currentPage,
          });

          await wrapper.vm.$nextTick();

          expect(wrapper.vm.skeletonItemCount).toBe(returnValue);
        },
      );
    });

    describe('allIssuablesChecked', () => {
      it.each`
        checkedIssuables        | issuables     | specTitle        | returnValue
        ${mockCheckedIssuables} | ${mIssuables} | ${'same as'}     | ${true}
        ${{}}                   | ${mIssuables} | ${'not same as'} | ${false}
      `(
        'returns $returnValue when bulkEditIssuables count is $specTitle issuables count',
        async ({ checkedIssuables, issuables, returnValue }) => {
          wrapper.setProps({
            issuables,
          });

          await wrapper.vm.$nextTick();

          wrapper.setData({
            checkedIssuables,
          });

          await wrapper.vm.$nextTick();

          expect(wrapper.vm.allIssuablesChecked).toBe(returnValue);
        },
      );
    });

    describe('bulkEditIssuables', () => {
      it('returns array of issuables which have `checked` set to true within checkedIssuables map', async () => {
        wrapper.setData({
          checkedIssuables: mockCheckedIssuables,
        });

        await wrapper.vm.$nextTick();

        expect(wrapper.vm.bulkEditIssuables).toHaveLength(mIssuables.length);
      });
    });
  });

  describe('watch', () => {
    beforeEach(() => {
      wrapper = createComponent();
    });

    describe('issuables', () => {
      it('populates `checkedIssuables` prop with all issuables', async () => {
        wrapper.setProps({
          issuables: [mockIssuables[0]],
        });

        await wrapper.vm.$nextTick();

        expect(Object.keys(wrapper.vm.checkedIssuables)).toHaveLength(1);
        expect(wrapper.vm.checkedIssuables[mockIssuables[0].iid]).toEqual({
          checked: false,
          issuable: mockIssuables[0],
        });
      });
    });

    describe('urlParams', () => {
      it('updates window URL reflecting props within `urlParams`', async () => {
        const urlParams = {
          state: 'closed',
          sort: 'updated_asc',
          page: 1,
          search: 'foo',
        };

        wrapper.setProps({
          urlParams,
        });

        await wrapper.vm.$nextTick();

        expect(global.window.location.href).toBe(
          `${TEST_HOST}/?state=${urlParams.state}&sort=${urlParams.sort}&page=${urlParams.page}&search=${urlParams.search}`,
        );
      });
    });
  });

  describe('methods', () => {
    beforeEach(() => {
      wrapper = createComponent();
    });

    describe('issuableId', () => {
      it('returns id value from provided issuable object', () => {
        expect(wrapper.vm.issuableId({ id: 1 })).toBe(1);
        expect(wrapper.vm.issuableId({ iid: 1 })).toBe(1);
        expect(wrapper.vm.issuableId({})).toBeDefined();
      });
    });

    describe('issuableChecked', () => {
      it('returns boolean value representing checked status of issuable item', async () => {
        wrapper.setData({
          checkedIssuables: {
            [mockIssuables[0].iid]: { checked: true, issuable: mockIssuables[0] },
          },
        });

        await wrapper.vm.$nextTick();

        expect(wrapper.vm.issuableChecked(mockIssuables[0])).toBe(true);
      });
    });
  });

  describe('template', () => {
    beforeEach(() => {
      wrapper = createComponent();
    });

    it('renders component container element with class "issuable-list-container"', () => {
      expect(wrapper.classes()).toContain('issuable-list-container');
    });

    it('renders issuable-tabs component', () => {
      const tabsEl = findIssuableTabs();

      expect(tabsEl.exists()).toBe(true);
      expect(tabsEl.props()).toMatchObject({
        tabs: wrapper.vm.tabs,
        tabCounts: wrapper.vm.tabCounts,
        currentTab: wrapper.vm.currentTab,
      });
    });

    it('renders contents for slot "nav-actions" within issuable-tab component', () => {
      const buttonEl = findIssuableTabs().find('button.js-new-issuable');

      expect(buttonEl.exists()).toBe(true);
      expect(buttonEl.text()).toBe('New issuable');
    });

    it('renders filtered-search-bar component', () => {
      const searchEl = findFilteredSearchBar();
      const {
        namespace,
        recentSearchesStorageKey,
        searchInputPlaceholder,
        searchTokens,
        sortOptions,
        initialFilterValue,
        initialSortBy,
      } = wrapper.vm;

      expect(searchEl.exists()).toBe(true);
      expect(searchEl.props()).toMatchObject({
        namespace,
        recentSearchesStorageKey,
        searchInputPlaceholder,
        tokens: searchTokens,
        sortOptions,
        initialFilterValue,
        initialSortBy,
      });
    });

    it('renders gl-loading-icon when `issuablesLoading` prop is true', async () => {
      wrapper.setProps({
        issuablesLoading: true,
      });

      await wrapper.vm.$nextTick();

      expect(wrapper.findAllComponents(GlSkeletonLoading)).toHaveLength(
        wrapper.vm.skeletonItemCount,
      );
    });

    it('renders issuable-item component for each item within `issuables` array', () => {
      const itemsEl = wrapper.findAllComponents(IssuableItem);
      const mockIssuable = mockIssuableListProps.issuables[0];

      expect(itemsEl).toHaveLength(mockIssuableListProps.issuables.length);
      expect(itemsEl.at(0).props()).toMatchObject({
        issuableSymbol: wrapper.vm.issuableSymbol,
        issuable: mockIssuable,
      });
    });

    it('renders contents for slot "empty-state" when `issuablesLoading` is false and `issuables` is empty', async () => {
      wrapper.setProps({
        issuables: [],
      });

      await wrapper.vm.$nextTick();

      expect(wrapper.find('p.js-issuable-empty-state').exists()).toBe(true);
      expect(wrapper.find('p.js-issuable-empty-state').text()).toBe('Issuable empty state');
    });

    it('renders gl-pagination when `showPaginationControls` prop is true', async () => {
      wrapper.setProps({
        showPaginationControls: true,
        totalItems: 10,
      });

      await wrapper.vm.$nextTick();

      const paginationEl = findGlPagination();
      expect(paginationEl.exists()).toBe(true);
      expect(paginationEl.props()).toMatchObject({
        perPage: 20,
        value: 1,
        prevPage: 0,
        nextPage: 2,
        totalItems: 10,
        align: 'center',
      });
    });
  });

  describe('events', () => {
    beforeEach(() => {
      wrapper = createComponent({
        data: {
          checkedIssuables: {
            [mockIssuables[0].iid]: { checked: true, issuable: mockIssuables[0] },
          },
        },
      });
    });

    it('issuable-tabs component emits `click-tab` event on `click-tab` event', () => {
      findIssuableTabs().vm.$emit('click');

      expect(wrapper.emitted('click-tab')).toBeTruthy();
    });

    it('sets all issuables as checked when filtered-search-bar component emits `checked-input` event', async () => {
      const searchEl = findFilteredSearchBar();

      searchEl.vm.$emit('checked-input', true);

      await wrapper.vm.$nextTick();

      expect(searchEl.emitted('checked-input')).toBeTruthy();
      expect(searchEl.emitted('checked-input').length).toBe(1);

      expect(wrapper.vm.checkedIssuables[mockIssuables[0].iid]).toEqual({
        checked: true,
        issuable: mockIssuables[0],
      });
    });

    it('filtered-search-bar component emits `filter` event on `onFilter` & `sort` event on `onSort` events', () => {
      const searchEl = findFilteredSearchBar();

      searchEl.vm.$emit('onFilter');
      expect(wrapper.emitted('filter')).toBeTruthy();
      searchEl.vm.$emit('onSort');
      expect(wrapper.emitted('sort')).toBeTruthy();
    });

    it('sets an issuable as checked when issuable-item component emits `checked-input` event', async () => {
      const issuableItem = wrapper.findAllComponents(IssuableItem).at(0);

      issuableItem.vm.$emit('checked-input', true);

      await wrapper.vm.$nextTick();

      expect(issuableItem.emitted('checked-input')).toBeTruthy();
      expect(issuableItem.emitted('checked-input').length).toBe(1);

      expect(wrapper.vm.checkedIssuables[mockIssuables[0].iid]).toEqual({
        checked: true,
        issuable: mockIssuables[0],
      });
    });

    it('gl-pagination component emits `page-change` event on `input` event', async () => {
      wrapper.setProps({
        showPaginationControls: true,
      });

      await wrapper.vm.$nextTick();

      findGlPagination().vm.$emit('input');
      expect(wrapper.emitted('page-change')).toBeTruthy();
    });
  });

  describe('manual sorting', () => {
    describe('when enabled', () => {
      beforeEach(() => {
        wrapper = createComponent({
          props: {
            ...mockIssuableListProps,
            isManualOrdering: true,
          },
        });
      });

      it('renders VueDraggable component', () => {
        expect(findVueDraggable().exists()).toBe(true);
      });

      it('IssuableItem has grab cursor', () => {
        expect(wrapper.findComponent(IssuableItem).classes()).toContain('gl-cursor-grab');
      });

      it('emits a "reorder" event when user updates the issue order', () => {
        const oldIndex = 4;
        const newIndex = 6;

        findVueDraggable().vm.$emit('update', { oldIndex, newIndex });

        expect(wrapper.emitted('reorder')).toEqual([[{ oldIndex, newIndex }]]);
      });
    });

    describe('when disabled', () => {
      beforeEach(() => {
        wrapper = createComponent();
      });

      it('does not render VueDraggable component', () => {
        expect(findVueDraggable().exists()).toBe(false);
      });
    });
  });
});
