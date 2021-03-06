import types from './mutation_types';

export default {
  [types.SET_ACTIVE_TAB](state, tab) {
    Object.assign(state, { activeTab: tab });
  },
  [types.SET_ENDPOINTS](state, endpoints) {
    Object.assign(state, { endpoints });
  },
};
