import { GlIcon } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import TimeAgo from '~/pipelines/components/pipelines_list/time_ago.vue';

describe('Timeago component', () => {
  let wrapper;

  const mutlipleStages = {
    manual_actions: [
      {
        name: 'deploy_job',
        path: '/root/one-stage-manual/-/jobs/1930/play',
        playable: true,
        scheduled: false,
      },
    ],
    stages: [
      {
        name: 'deploy',
      },
      {
        name: 'qa',
      },
    ],
  };

  const singleStageManual = {
    manual_actions: [
      {
        name: 'deploy_job',
        path: '/root/one-stage-manual/-/jobs/1930/play',
        playable: true,
        scheduled: false,
      },
    ],
    stages: [
      {
        name: 'deploy',
      },
    ],
  };

  const createComponent = (props = {}) => {
    wrapper = shallowMount(TimeAgo, {
      propsData: {
        pipeline: {
          details: {
            ...props,
          },
        },
      },
      data() {
        return {
          iconTimerSvg: `<svg></svg>`,
        };
      },
    });
  };

  afterEach(() => {
    wrapper.destroy();
    wrapper = null;
  });

  const duration = () => wrapper.find('.duration');
  const finishedAt = () => wrapper.find('.finished-at');
  const findInProgress = () => wrapper.find('[data-testid="pipeline-in-progress"]');
  const findSkipped = () => wrapper.find('[data-testid="pipeline-skipped"]');

  describe('with duration', () => {
    beforeEach(() => {
      createComponent({ duration: 10, finished_at: '' });
    });

    it('should render duration and timer svg', () => {
      const icon = duration().find(GlIcon);

      expect(duration().exists()).toBe(true);
      expect(icon.props('name')).toBe('timer');
    });
  });

  describe('without duration', () => {
    beforeEach(() => {
      createComponent({ ...singleStageManual, duration: 0, finished_at: '' });
    });

    it('should not render duration and timer svg', () => {
      expect(duration().exists()).toBe(false);
    });
  });

  describe('with finishedTime', () => {
    beforeEach(() => {
      createComponent({ duration: 0, finished_at: '2017-04-26T12:40:23.277Z' });
    });

    it('should render time and calendar icon', () => {
      const icon = finishedAt().find(GlIcon);
      const time = finishedAt().find('time');

      expect(finishedAt().exists()).toBe(true);
      expect(icon.props('name')).toBe('calendar');
      expect(time.exists()).toBe(true);
    });
  });

  describe('without finishedTime', () => {
    beforeEach(() => {
      createComponent({ ...singleStageManual, duration: 0, finished_at: '' });
    });

    it('should not render time and calendar icon', () => {
      expect(finishedAt().exists()).toBe(false);
    });
  });

  describe('in progress', () => {
    it.each`
      durationTime | finishedAtTime                | shouldShow
      ${10}        | ${'2017-04-26T12:40:23.277Z'} | ${false}
      ${10}        | ${''}                         | ${false}
      ${0}         | ${'2017-04-26T12:40:23.277Z'} | ${false}
      ${0}         | ${''}                         | ${true}
    `(
      'progress state shown: $shouldShow when pipeline duration is $durationTime and finished_at is $finishedAtTime',
      ({ durationTime, finishedAtTime, shouldShow }) => {
        createComponent({
          ...mutlipleStages,
          duration: durationTime,
          finished_at: finishedAtTime,
        });

        expect(findInProgress().exists()).toBe(shouldShow);
        expect(findSkipped().exists()).toBe(false);
      },
    );
  });

  describe('skipped', () => {
    it.each`
      durationTime | finishedAtTime                | shouldShow
      ${10}        | ${'2017-04-26T12:40:23.277Z'} | ${false}
      ${10}        | ${''}                         | ${false}
      ${0}         | ${'2017-04-26T12:40:23.277Z'} | ${false}
      ${0}         | ${''}                         | ${true}
    `(
      'progress state shown: $shouldShow when pipeline duration is $durationTime and finished_at is $finishedAtTime',
      ({ durationTime, finishedAtTime, shouldShow }) => {
        createComponent({
          ...singleStageManual,
          duration: durationTime,
          finished_at: finishedAtTime,
        });

        expect(findSkipped().exists()).toBe(shouldShow);
        expect(findInProgress().exists()).toBe(false);
      },
    );
  });
});
