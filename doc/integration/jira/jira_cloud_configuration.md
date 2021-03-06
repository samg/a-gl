---
stage: Create
group: Ecosystem
info: To determine the technical writer assigned to the Stage/Group associated with this page, see https://about.gitlab.com/handbook/engineering/ux/technical-writing/#assignments
---

# Create an API token in Jira on Atlassian cloud **(FREE)**

For [integrations with Jira](../../user/project/integrations/jira.md), an API token is needed when integrating with Jira
on Atlassian cloud. To create an API token:

1. Log in to [`id.atlassian.com`](https://id.atlassian.com/manage-profile/security/api-tokens) with your email address.

   NOTE:
   It is important that the user associated with this email address has *write* access
   to projects in Jira.

1. Click **Create API token**.

   ![Jira API token](../../user/project/integrations/img/jira_api_token_menu.png)

1. Click **Copy**, or click **View** and write down the new API token. It is required when [configuring GitLab](../../user/project/integrations/jira.md#configure-gitlab).

   ![Jira API token](../../user/project/integrations/img/jira_api_token.png)

The Jira configuration is complete. You need the newly created token, and the associated email
address, when [configuring GitLab](../../user/project/integrations/jira.md#configure-gitlab).
