import { mount, createLocalVue } from '@vue/test-utils';
import { escape } from 'lodash';
import waitForPromises from 'helpers/wait_for_promises';
import NoteActions from '~/notes/components/note_actions.vue';
import NoteBody from '~/notes/components/note_body.vue';
import NoteHeader from '~/notes/components/note_header.vue';
import issueNote from '~/notes/components/noteable_note.vue';
import createStore from '~/notes/stores';
import UserAvatarLink from '~/vue_shared/components/user_avatar/user_avatar_link.vue';
import { noteableDataMock, notesDataMock, note } from '../mock_data';

describe('issue_note', () => {
  let store;
  let wrapper;
  const findMultilineComment = () => wrapper.find('[data-testid="multiline-comment"]');

  const createWrapper = (props = {}) => {
    store = createStore();
    store.dispatch('setNoteableData', noteableDataMock);
    store.dispatch('setNotesData', notesDataMock);

    const localVue = createLocalVue();
    wrapper = mount(localVue.extend(issueNote), {
      store,
      propsData: {
        note,
        ...props,
      },
      localVue,
      stubs: [
        'note-header',
        'user-avatar-link',
        'note-actions',
        'note-body',
        'multiline-comment-form',
      ],
    });
  };

  afterEach(() => {
    wrapper.destroy();
  });

  describe('mutiline comments', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('should render if has multiline comment', async () => {
      const position = {
        line_range: {
          start: {
            line_code: 'abc_1_1',
            type: null,
            old_line: '1',
            new_line: '1',
          },
          end: {
            line_code: 'abc_2_2',
            type: null,
            old_line: '2',
            new_line: '2',
          },
        },
      };
      const line = {
        line_code: 'abc_1_1',
        type: null,
        old_line: '1',
        new_line: '1',
      };
      wrapper.setProps({
        note: { ...note, position },
        discussionRoot: true,
        line,
      });

      await wrapper.vm.$nextTick();
      expect(findMultilineComment().text()).toBe('Comment on lines 1 to 2');
    });

    it('should only render if it has everything it needs', () => {
      const position = {
        line_range: {
          start: {
            line_code: 'abc_1_1',
            type: null,
            old_line: '',
            new_line: '',
          },
          end: {
            line_code: 'abc_2_2',
            type: null,
            old_line: '2',
            new_line: '2',
          },
        },
      };
      const line = {
        line_code: 'abc_1_1',
        type: null,
        old_line: '1',
        new_line: '1',
      };
      wrapper.setProps({
        note: { ...note, position },
        discussionRoot: true,
        line,
      });

      return wrapper.vm.$nextTick().then(() => {
        expect(findMultilineComment().exists()).toBe(false);
      });
    });

    it('should not render if has single line comment', () => {
      const position = {
        line_range: {
          start: {
            line_code: 'abc_1_1',
            type: null,
            old_line: '1',
            new_line: '1',
          },
          end: {
            line_code: 'abc_1_1',
            type: null,
            old_line: '1',
            new_line: '1',
          },
        },
      };
      const line = {
        line_code: 'abc_1_1',
        type: null,
        old_line: '1',
        new_line: '1',
      };
      wrapper.setProps({
        note: { ...note, position },
        discussionRoot: true,
        line,
      });

      return wrapper.vm.$nextTick().then(() => {
        expect(findMultilineComment().exists()).toBe(false);
      });
    });

    it('should not render if `line_range` is unavailable', () => {
      expect(findMultilineComment().exists()).toBe(false);
    });
  });

  describe('rendering', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('should render user information', () => {
      const { author } = note;
      const avatar = wrapper.findComponent(UserAvatarLink);
      const avatarProps = avatar.props();

      expect(avatarProps.linkHref).toBe(author.path);
      expect(avatarProps.imgSrc).toBe(author.avatar_url);
      expect(avatarProps.imgAlt).toBe(author.name);
      expect(avatarProps.imgSize).toBe(40);
    });

    it('should render note header content', () => {
      const noteHeader = wrapper.findComponent(NoteHeader);
      const noteHeaderProps = noteHeader.props();

      expect(noteHeaderProps.author).toBe(note.author);
      expect(noteHeaderProps.createdAt).toBe(note.created_at);
      expect(noteHeaderProps.noteId).toBe(note.id);
    });

    it('should render note actions', () => {
      const { author } = note;
      const noteActions = wrapper.findComponent(NoteActions);
      const noteActionsProps = noteActions.props();

      expect(noteActionsProps.authorId).toBe(author.id);
      expect(noteActionsProps.noteId).toBe(note.id);
      expect(noteActionsProps.noteUrl).toBe(note.noteable_note_url);
      expect(noteActionsProps.accessLevel).toBe(note.human_access);
      expect(noteActionsProps.canEdit).toBe(note.current_user.can_edit);
      expect(noteActionsProps.canAwardEmoji).toBe(note.current_user.can_award_emoji);
      expect(noteActionsProps.canDelete).toBe(note.current_user.can_edit);
      expect(noteActionsProps.canReportAsAbuse).toBe(true);
      expect(noteActionsProps.canResolve).toBe(false);
      expect(noteActionsProps.reportAbusePath).toBe(note.report_abuse_path);
      expect(noteActionsProps.resolvable).toBe(false);
      expect(noteActionsProps.isResolved).toBe(false);
      expect(noteActionsProps.isResolving).toBe(false);
      expect(noteActionsProps.resolvedBy).toEqual({});
    });

    it('should render issue body', () => {
      const noteBody = wrapper.findComponent(NoteBody);
      const noteBodyProps = noteBody.props();

      expect(noteBodyProps.note).toBe(note);
      expect(noteBodyProps.line).toBe(null);
      expect(noteBodyProps.canEdit).toBe(note.current_user.can_edit);
      expect(noteBodyProps.isEditing).toBe(false);
      expect(noteBodyProps.helpPagePath).toBe('');
    });

    it('prevents note preview xss', async () => {
      const noteBody =
        '<img src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7" onload="alert(1)" />';
      const alertSpy = jest.spyOn(window, 'alert').mockImplementation(() => {});
      const noteBodyComponent = wrapper.findComponent(NoteBody);

      store.hotUpdate({
        actions: {
          updateNote() {},
          setSelectedCommentPositionHover() {},
        },
      });

      noteBodyComponent.vm.$emit('handleFormUpdate', noteBody, null, () => {});

      await waitForPromises();
      expect(alertSpy).not.toHaveBeenCalled();
      expect(wrapper.vm.note.note_html).toBe(escape(noteBody));
    });
  });

  describe('cancel edit', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('restores content of updated note', async () => {
      const updatedText = 'updated note text';
      store.hotUpdate({
        actions: {
          updateNote() {},
        },
      });
      const noteBody = wrapper.findComponent(NoteBody);
      noteBody.vm.resetAutoSave = () => {};

      noteBody.vm.$emit('handleFormUpdate', updatedText, null, () => {});

      await wrapper.vm.$nextTick();
      let noteBodyProps = noteBody.props();

      expect(noteBodyProps.note.note_html).toBe(updatedText);

      noteBody.vm.$emit('cancelForm');
      await wrapper.vm.$nextTick();

      noteBodyProps = noteBody.props();

      expect(noteBodyProps.note.note_html).toBe(note.note_html);
    });
  });

  describe('formUpdateHandler', () => {
    const updateNote = jest.fn();
    const params = ['', null, jest.fn(), ''];

    const updateActions = () => {
      store.hotUpdate({
        actions: {
          updateNote,
          setSelectedCommentPositionHover() {},
        },
      });
    };

    afterEach(() => updateNote.mockReset());

    it('responds to handleFormUpdate', () => {
      createWrapper();
      updateActions();
      wrapper.findComponent(NoteBody).vm.$emit('handleFormUpdate', ...params);
      expect(wrapper.emitted('handleUpdateNote')).toBeTruthy();
    });

    it('does not stringify empty position', () => {
      createWrapper();
      updateActions();
      wrapper.findComponent(NoteBody).vm.$emit('handleFormUpdate', ...params);
      expect(updateNote.mock.calls[0][1].note.note.position).toBeUndefined();
    });

    it('stringifies populated position', () => {
      const position = { test: true };
      const expectation = JSON.stringify(position);
      createWrapper({ note: { ...note, position } });
      updateActions();
      wrapper.findComponent(NoteBody).vm.$emit('handleFormUpdate', ...params);
      expect(updateNote.mock.calls[0][1].note.note.position).toBe(expectation);
    });
  });
});
