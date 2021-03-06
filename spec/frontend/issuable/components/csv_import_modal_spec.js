import { GlModal } from '@gitlab/ui';
import { getByRole, getByLabelText } from '@testing-library/dom';
import { mount } from '@vue/test-utils';
import { stubComponent } from 'helpers/stub_component';
import { extendedWrapper } from 'helpers/vue_test_utils_helper';
import CsvImportModal from '~/issuable/components/csv_import_modal.vue';

jest.mock('~/lib/utils/csrf', () => ({ token: 'mock-csrf-token' }));

describe('CsvImportModal', () => {
  let wrapper;
  let formSubmitSpy;

  function createComponent(options = {}) {
    const { injectedProperties = {}, props = {} } = options;
    return extendedWrapper(
      mount(CsvImportModal, {
        propsData: {
          modalId: 'csv-import-modal',
          ...props,
        },
        provide: {
          issuableType: 'issues',
          ...injectedProperties,
        },
        stubs: {
          GlModal: stubComponent(GlModal, {
            template: '<div><slot></slot><slot name="modal-footer"></slot></div>',
          }),
        },
      }),
    );
  }

  beforeEach(() => {
    formSubmitSpy = jest.spyOn(HTMLFormElement.prototype, 'submit').mockImplementation();
  });

  afterEach(() => {
    wrapper.destroy();
  });

  const findModal = () => wrapper.findComponent(GlModal);
  const findPrimaryButton = () => getByRole(wrapper.element, 'button', { name: 'Import issues' });
  const findForm = () => wrapper.findByTestId('import-csv-form');
  const findFileInput = () => getByLabelText(wrapper.element, 'Upload CSV file');
  const findAuthenticityToken = () => new FormData(findForm().element).get('authenticity_token');

  describe('template', () => {
    it('displays modal title', () => {
      wrapper = createComponent();
      expect(findModal().text()).toContain('Import issues');
    });

    it('displays a note about the maximum allowed file size', () => {
      const maxAttachmentSize = 500;
      wrapper = createComponent({ injectedProperties: { maxAttachmentSize } });
      expect(findModal().text()).toContain(`The maximum file size allowed is ${maxAttachmentSize}`);
    });

    describe('form', () => {
      const importCsvIssuesPath = 'gitlab-org/gitlab-test/-/issues/import_csv';

      beforeEach(() => {
        wrapper = createComponent({ injectedProperties: { importCsvIssuesPath } });
      });

      it('displays the form with the correct action and inputs', () => {
        expect(findForm().exists()).toBe(true);
        expect(findForm().attributes('action')).toBe(importCsvIssuesPath);
        expect(findAuthenticityToken()).toBe('mock-csrf-token');
        expect(findFileInput()).toExist();
      });

      it('displays the correct primary button action text', () => {
        expect(findPrimaryButton()).toExist();
      });

      it('submits the form when the primary action is clicked', async () => {
        findPrimaryButton().click();

        expect(formSubmitSpy).toHaveBeenCalled();
      });
    });
  });
});
