---
stage: Create
group: Ecosystem
info: To determine the technical writer assigned to the Stage/Group associated with this page, see https://about.gitlab.com/handbook/engineering/ux/technical-writing/#assignments
---

# Mattermost Notifications Service **(FREE)**

The Mattermost Notifications Service allows your GitLab project to send events (e.g., `issue created`) to your existing Mattermost team as notifications. This requires configurations in both Mattermost and GitLab.

You can also use Mattermost slash commands to control GitLab inside Mattermost. This is the separately configured [Mattermost slash commands](mattermost_slash_commands.md).

## On Mattermost

To enable Mattermost integration you must create an incoming webhook integration:

1. Sign in to your Mattermost instance.
1. Visit incoming webhooks, that is something like: `https://mattermost.example.com/your_team_name/integrations/incoming_webhooks/add`.
1. Choose a display name, description and channel, those can be overridden on GitLab.
1. Save it and copy the **Webhook URL** because we need this later for GitLab.

Incoming Webhooks might be blocked on your Mattermost instance. Ask your Mattermost administrator
to enable it on:

- **Mattermost System Console > Integrations > Integration Management** in Mattermost
  versions 5.12 and later.
- **Mattermost System Console > Integrations > Custom Integrations** in Mattermost
  versions 5.11 and earlier.

Display name override is not enabled by default, you need to ask your administrator to enable it on that same section.

## On GitLab

After you set up Mattermost, it's time to set up GitLab.

Navigate to the [Integrations page](overview.md#accessing-integrations)
and select the **Mattermost notifications** service to configure it.
There, you see a checkbox with the following events that can be triggered:

- Push
- Issue
- Confidential issue
- Merge request
- Note
- Confidential note
- Tag push
- Pipeline
- Wiki page
- Deployment

Below each of these event checkboxes, you have an input field to enter
which Mattermost channel you want to send that event message. Enter your preferred channel handle (the hash sign `#` is optional).

At the end, fill in your Mattermost details:

| Field | Description |
| ----- | ----------- |
| **Webhook**  | The incoming webhook URL which you have to set up on Mattermost, similar to: `http://mattermost.example/hooks/5xo???` |
| **Username** | Optional username which can be on messages sent to Mattermost. Fill this in if you want to change the username of the bot. |
| **Notify only broken pipelines** | If you choose to enable the **Pipeline** event and you want to be only notified about failed pipelines. |
| **Branches to be notified** | Select which types of branches to send notifications for. |
| **Labels to be notified** | Optional labels that the issue or merge request must have in order to trigger a notification. Leave blank to get all notifications. |

![Mattermost configuration](img/mattermost_configuration_v2.png)
