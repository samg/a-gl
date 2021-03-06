---
stage: Enablement
group: Geo
info: To determine the technical writer assigned to the Stage/Group associated with this page, see https://about.gitlab.com/handbook/engineering/ux/technical-writing/#assignments
type: howto
---

# Removing secondary Geo nodes **(PREMIUM SELF)**

**Secondary** nodes can be removed from the Geo cluster using the Geo administration page of the **primary** node. To remove a **secondary** node:

1. Go to **Admin Area > Geo** (`/admin/geo/nodes`).
1. Click the **Remove** button for the **secondary** node you want to remove.
1. Confirm by clicking **Remove** when the prompt appears.

Once removed from the Geo administration page, you must stop and uninstall the **secondary** node:

1. On the **secondary** node, stop GitLab:

   ```shell
   sudo gitlab-ctl stop
   ```

1. On the **secondary** node, uninstall GitLab:

   ```shell
   # Stop gitlab and remove its supervision process
   sudo gitlab-ctl uninstall

   # Debian/Ubuntu
   sudo dpkg --remove gitlab-ee

   # Redhat/Centos
   sudo rpm --erase gitlab-ee
   ```

Once GitLab has been uninstalled from the **secondary** node, the replication slot must be dropped from the **primary** node's database as follows:

1. On the **primary** node, start a PostgreSQL console session:

   ```shell
   sudo gitlab-psql
   ```

   NOTE:
   Using `gitlab-rails dbconsole` will not work, because managing replication slots requires superuser permissions.

1. Find the name of the relevant replication slot. This is the slot that is specified with `--slot-name` when running the replicate command: `gitlab-ctl replicate-geo-database`.

   ```sql
   SELECT * FROM pg_replication_slots;
   ```

1. Remove the replication slot for the **secondary** node:

   ```sql
   SELECT pg_drop_replication_slot('<name_of_slot>');
   ```
