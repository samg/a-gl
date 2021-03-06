---
stage: Create
group: Gitaly
info: To determine the technical writer assigned to the Stage/Group associated with this page, see https://about.gitlab.com/handbook/engineering/ux/technical-writing/#assignments
type: reference
---

# Gitaly Cluster **(FREE SELF)**

[Gitaly](index.md), the service that provides storage for Git repositories, can
be run in a clustered configuration to scale the Gitaly service and increase
fault tolerance. In this configuration, every Git repository is stored on every
Gitaly node in the cluster.

Using a Gitaly Cluster increases fault tolerance by:

- Replicating write operations to warm standby Gitaly nodes.
- Detecting Gitaly node failures.
- Automatically routing Git requests to an available Gitaly node.

NOTE:
Technical support for Gitaly clusters is limited to GitLab Premium and Ultimate
customers.

The availability objectives for Gitaly clusters are:

- **Recovery Point Objective (RPO):** Less than 1 minute.

  Writes are replicated asynchronously. Any writes that have not been replicated
  to the newly promoted primary are lost.

  [Strong consistency](#strong-consistency) can be used to avoid loss in some
  circumstances.

- **Recovery Time Objective (RTO):** Less than 10 seconds.

  Outages are detected by a health checks run by each Praefect node every
  second. Failover requires ten consecutive failed health checks on each
  Praefect node.

  [Faster outage detection](https://gitlab.com/gitlab-org/gitaly/-/issues/2608)
  is planned to improve this to less than 1 second.

Gitaly Cluster supports:

- [Strong consistency](#strong-consistency) of the secondary replicas.
- [Automatic failover](#automatic-failover-and-leader-election) from the primary to the secondary.
- Reporting of possible data loss if replication queue is non-empty.
- Marking repositories as [read only](#read-only-mode) if data loss is detected to prevent data inconsistencies.

Follow the [Gitaly Cluster epic](https://gitlab.com/groups/gitlab-org/-/epics/1489)
for improvements including
[horizontally distributing reads](https://gitlab.com/groups/gitlab-org/-/epics/2013).

## Overview

Git storage is provided through the Gitaly service in GitLab, and is essential
to correct proper operation of the GitLab application. When the number of
users, repositories, and activity grows, it is important to scale Gitaly
appropriately by:

- Increasing the available CPU and memory resources available to Git before
  resource exhaustion degrades Git, Gitaly, and GitLab application performance.
- Increase available storage before storage limits are reached causing write
  operations to fail.
- Improve fault tolerance by removing single points of failure. Git should be
  considered mission critical if a service degradation would prevent you from
  deploying changes to production.

### Moving beyond NFS

WARNING:
From GitLab 13.0, using NFS for Git repositories is deprecated. In GitLab 14.0,
support for NFS for Git repositories is scheduled to be removed. Upgrade to
Gitaly Cluster as soon as possible.

[Network File System (NFS)](https://en.wikipedia.org/wiki/Network_File_System)
is not well suited to Git workloads which are CPU and IOPS sensitive.
Specifically:

- Git is sensitive to file system latency. Even simple operations require many
  read operations. Operations that are fast on block storage can become an order of
  magnitude slower. This significantly impacts GitLab application performance.
- NFS performance optimizations that prevent the performance gap between
  block storage and NFS being even wider are vulnerable to race conditions. We have observed
  [data inconsistencies](https://gitlab.com/gitlab-org/gitaly/-/issues/2589)
  in production environments caused by simultaneous writes to different NFS
  clients. Data corruption is not an acceptable risk.

Gitaly Cluster is purpose built to provide reliable, high performance, fault
tolerant Git storage.

Further reading:

- Blog post: [The road to Gitaly v1.0 (aka, why GitLab doesn't require NFS for storing Git data anymore)](https://about.gitlab.com/blog/2018/09/12/the-road-to-gitaly-1-0/)
- Blog post: [How we spent two weeks hunting an NFS bug in the Linux kernel](https://about.gitlab.com/blog/2018/11/14/how-we-spent-two-weeks-hunting-an-nfs-bug/)

## Where Gitaly Cluster fits

GitLab accesses [repositories](../../user/project/repository/index.md) through the configured
[repository storages](../repository_storage_paths.md). Each new repository is stored on one of the
repository storages based on their configured weights. Each repository storage is either:

- A Gitaly storage served directly by Gitaly. These map to a directory on the file system of a
  Gitaly node.
- A [virtual storage](#virtual-storage-or-direct-gitaly-storage) served by Praefect. A virtual
  storage is a cluster of Gitaly storages that appear as a single repository storage.

Virtual storages are a feature of Gitaly Cluster. They support replicating the repositories to
multiple storages for fault tolerance. Virtual storages can improve performance by distributing
requests across Gitaly nodes. Their distributed nature makes it viable to have a single repository
storage in GitLab to simplify repository management.

## Components of Gitaly Cluster

Gitaly Cluster consists of multiple components:

- [Load balancer](#load-balancer) for distributing requests and providing fault-tolerant access to
  Praefect nodes.
- [Praefect](#praefect) nodes for managing the cluster and routing requests to Gitaly nodes.
- [PostgreSQL database](#postgresql) for persisting cluster metadata and [PgBouncer](#pgbouncer),
  recommended for pooling Praefect's database connections.
- [Gitaly](index.md) nodes to provide repository storage and Git access.

![Cluster example](img/cluster_example_v13_3.png)

In this example:

- Repositories are stored on a virtual storage called `storage-1`.
- Three Gitaly nodes provide `storage-1` access: `gitaly-1`, `gitaly-2`, and `gitaly-3`.
- The three Gitaly nodes store data on their file systems.

### Virtual storage or direct Gitaly storage

Gitaly supports multiple models of scaling:

- Clustering using Gitaly Cluster, where each repository is stored on multiple Gitaly nodes in the
  cluster. Read requests are distributed between repository replicas and write requests are
  broadcast to repository replicas. GitLab accesses virtual storage.
- Direct access to Gitaly storage using [repository storage paths](../repository_storage_paths.md),
  where each repository is stored on the assigned Gitaly node. All requests are routed to this node.

The following is Gitaly set up to use direct access to Gitaly instead of Gitaly Cluster:

![Shard example](img/shard_example_v13_3.png)

In this example:

- Each repository is stored on one of three Gitaly storages: `storage-1`, `storage-2`,
  or `storage-3`.
- Each storage is serviced by a Gitaly node.
- The three Gitaly nodes store data in three separate hashed storage locations.

Generally, virtual storage with Gitaly Cluster can replace direct Gitaly storage configurations, at
the expense of additional storage needed to store each repository on multiple Gitaly nodes. The
benefit of using Gitaly Cluster over direct Gitaly storage is:

- Improved fault tolerance, because each Gitaly node has a copy of every repository.
- Improved resource utilization, reducing the need for over-provisioning for shard-specific peak
  loads, because read loads are distributed across replicas.
- Manual rebalancing for performance is not required, because read loads are distributed across
  replicas.
- Simpler management, because all Gitaly nodes are identical.

Under some workloads, CPU and memory requirements may require a large fleet of Gitaly nodes. It
can be uneconomical to have one to one replication factor.

A hybrid approach can be used in these instances, where each shard is configured as a smaller
cluster. [Variable replication factor](https://gitlab.com/groups/gitlab-org/-/epics/3372) is planned
to provide greater flexibility for extremely large GitLab instances.

### Gitaly Cluster compared to Geo

Gitaly Cluster and [Geo](../geo/index.md) both provide redundancy. However the redundancy of:

- Gitaly Cluster provides fault tolerance for data storage and is invisible to the user. Users are
  not aware when Gitaly Cluster is used.
- Geo provides [replication](../geo/index.md) and [disaster recovery](../geo/disaster_recovery/index.md) for
  an entire instance of GitLab. Users know when they are using Geo for
  [replication](../geo/index.md). Geo [replicates multiple datatypes](../geo/replication/datatypes.md#limitations-on-replicationverification),
  including Git data.

The following table outlines the major differences between Gitaly Cluster and Geo:

| Tool           | Nodes    | Locations | Latency tolerance  | Failover                                             | Consistency                   | Provides redundancy for |
|:---------------|:---------|:----------|:-------------------|:-----------------------------------------------------|:------------------------------|:------------------------|
| Gitaly Cluster | Multiple | Single    | Approximately 1 ms | [Automatic](#automatic-failover-and-leader-election) | [Strong](#strong-consistency) | Data storage in Git     |
| Geo            | Multiple | Multiple  | Up to one minute   | [Manual](../geo/disaster_recovery/index.md)          | Eventual                      | Entire GitLab instance  |

For more information, see:

- [Gitaly architecture](index.md#architecture).
- Geo [use cases](../geo/index.md#use-cases) and [architecture](../geo/index.md#architecture).

## Architecture

Praefect is a router and transaction manager for Gitaly, and a required
component for running a Gitaly Cluster.

![Architecture diagram](img/praefect_architecture_v12_10.png)

For more information, see [Gitaly HA Design](https://gitlab.com/gitlab-org/gitaly/-/blob/master/doc/design_ha.md)

## Requirements for configuring a Gitaly Cluster

The minimum recommended configuration for a Gitaly Cluster requires:

- 1 load balancer
- 1 PostgreSQL server (PostgreSQL 11 or newer)
- 3 Praefect nodes
- 3 Gitaly nodes (1 primary, 2 secondary)

See the [design
document](https://gitlab.com/gitlab-org/gitaly/-/blob/master/doc/design_ha.md)
for implementation details.

## Setup Instructions

If you [installed](https://about.gitlab.com/install/) GitLab using the Omnibus
package (highly recommended), follow the steps below:

1. [Preparation](#preparation)
1. [Configuring the Praefect database](#postgresql)
1. [Configuring the Praefect proxy/router](#praefect)
1. [Configuring each Gitaly node](#gitaly) (once for each Gitaly node)
1. [Configure the load balancer](#load-balancer)
1. [Updating the GitLab server configuration](#gitlab)
1. [Configure Grafana](#grafana)

### Preparation

Before beginning, you should already have a working GitLab instance. [Learn how
to install GitLab](https://about.gitlab.com/install/).

Provision a PostgreSQL server (PostgreSQL 11 or newer).

Prepare all your new nodes by [installing
GitLab](https://about.gitlab.com/install/).

- At least 1 Praefect node (minimal storage required)
- 3 Gitaly nodes (high CPU, high memory, fast storage)
- 1 GitLab server

You need the IP/host address for each node.

1. `LOAD_BALANCER_SERVER_ADDRESS`: the IP/host address of the load balancer
1. `POSTGRESQL_SERVER_ADDRESS`: the IP/host address of the PostgreSQL server
1. `PRAEFECT_HOST`: the IP/host address of the Praefect server
1. `GITALY_HOST_*`: the IP or host address of each Gitaly server
1. `GITLAB_HOST`: the IP/host address of the GitLab server

If you are using a cloud provider, you can look up the addresses for each server through your cloud provider's management console.

If you are using Google Cloud Platform, SoftLayer, or any other vendor that provides a virtual private cloud (VPC) you can use the private addresses for each cloud instance (corresponds to "internal address" for Google Cloud Platform) for `PRAEFECT_HOST`, `GITALY_HOST_*`, and `GITLAB_HOST`.

#### Secrets

The communication between components is secured with different secrets, which
are described below. Before you begin, generate a unique secret for each, and
make note of it. This enables you to replace these placeholder tokens
with secure tokens as you complete the setup process.

1. `GITLAB_SHELL_SECRET_TOKEN`: this is used by Git hooks to make callback HTTP
   API requests to GitLab when accepting a Git push. This secret is shared with
   GitLab Shell for legacy reasons.
1. `PRAEFECT_EXTERNAL_TOKEN`: repositories hosted on your Praefect cluster can
   only be accessed by Gitaly clients that carry this token.
1. `PRAEFECT_INTERNAL_TOKEN`: this token is used for replication traffic inside
   your Praefect cluster. This is distinct from `PRAEFECT_EXTERNAL_TOKEN`
   because Gitaly clients must not be able to access internal nodes of the
   Praefect cluster directly; that could lead to data loss.
1. `PRAEFECT_SQL_PASSWORD`: this password is used by Praefect to connect to
   PostgreSQL.

We note in the instructions below where these secrets are required.

NOTE:
Omnibus GitLab installations can use `gitlab-secrets.json`.

### PostgreSQL

NOTE:
Do not store the GitLab application database and the Praefect
database on the same PostgreSQL server if using
[Geo](../geo/index.md). The replication state is internal to each instance
of GitLab and should not be replicated.

These instructions help set up a single PostgreSQL database, which creates a single point of
failure. The following options are available:

- For non-Geo installations, either:
  - Use one of the documented [PostgreSQL setups](../postgresql/index.md).
  - Use your own third-party database setup, if fault tolerance is required.
- For Geo instances, either:
  - Set up a separate [PostgreSQL instance](https://www.postgresql.org/docs/11/high-availability.html).
  - Use a cloud-managed PostgreSQL service. AWS
     [Relational Database Service](https://aws.amazon.com/rds/) is recommended.

To complete this section you need:

- 1 Praefect node
- 1 PostgreSQL server (PostgreSQL 11 or newer)
  - An SQL user with permissions to create databases

During this section, we configure the PostgreSQL server, from the Praefect
node, using `psql` which is installed by Omnibus GitLab.

1. SSH into the **Praefect** node and login as root:

   ```shell
   sudo -i
   ```

1. Connect to the PostgreSQL server with administrative access. This is likely
   the `postgres` user. The database `template1` is used because it is created
   by default on all PostgreSQL servers.

   ```shell
   /opt/gitlab/embedded/bin/psql -U postgres -d template1 -h POSTGRESQL_SERVER_ADDRESS
   ```

   Create a new user `praefect` to be used by Praefect. Replace
   `PRAEFECT_SQL_PASSWORD` with the strong password you generated in the
   preparation step.

   ```sql
   CREATE ROLE praefect WITH LOGIN CREATEDB PASSWORD 'PRAEFECT_SQL_PASSWORD';
   ```

1. Reconnect to the PostgreSQL server, this time as the `praefect` user:

   ```shell
   /opt/gitlab/embedded/bin/psql -U praefect -d template1 -h POSTGRESQL_SERVER_ADDRESS
   ```

   Create a new database `praefect_production`. By creating the database while
   connected as the `praefect` user, we are confident they have access.

   ```sql
   CREATE DATABASE praefect_production WITH ENCODING=UTF8;
   ```

The database used by Praefect is now configured.

#### PgBouncer

To reduce PostgreSQL resource consumption, we recommend setting up and configuring
[PgBouncer](https://www.pgbouncer.org/) in front of the PostgreSQL instance. To do
this, set the corresponding IP or host address of the PgBouncer instance in
`/etc/gitlab/gitlab.rb` by changing the following settings:

- `praefect['database_host']`, for the address.
- `praefect['database_port']`, for the port.

Because PgBouncer manages resources more efficiently, Praefect still requires a
direct connection to the PostgreSQL database. It uses the
[LISTEN](https://www.postgresql.org/docs/11/sql-listen.html)
feature that is [not supported](https://www.pgbouncer.org/features.html) by
PgBouncer with `pool_mode = transaction`.
Set `praefect['database_host_no_proxy']` and `praefect['database_port_no_proxy']`
to a direct connection, and not a PgBouncer connection.

Save the changes to `/etc/gitlab/gitlab.rb` and
[reconfigure Praefect](../restart_gitlab.md#omnibus-gitlab-reconfigure).

This documentation doesn't provide PgBouncer installation instructions,
but you can:

- Find instructions on the [official website](https://www.pgbouncer.org/install.html).
- Use a [Docker image](https://hub.docker.com/r/edoburu/pgbouncer/).

In addition to the base PgBouncer configuration options, set the following values in
your `pgbouncer.ini` file:

- The [Praefect PostgreSQL database](#postgresql) in the `[databases]` section:

   ```ini
   [databases]
   * = host=POSTGRESQL_SERVER_ADDRESS port=5432 auth_user=praefect
   ```

- [`pool_mode`](https://www.pgbouncer.org/config.html#pool_mode)
  and [`ignore_startup_parameters`](https://www.pgbouncer.org/config.html#ignore_startup_parameters)
  in the `[pgbouncer]` section:

   ```ini
   [pgbouncer]
   pool_mode = transaction
   ignore_startup_parameters = extra_float_digits
   ```

The `praefect` user and its password should be included in the file (default is
`userlist.txt`) used by PgBouncer if the [`auth_file`](https://www.pgbouncer.org/config.html#auth_file)
configuration option is set.

NOTE:
By default PgBouncer uses port `6432` to accept incoming
connections. You can change it by setting the [`listen_port`](https://www.pgbouncer.org/config.html#listen_port)
configuration option. We recommend setting it to the default port value (`5432`) used by
PostgreSQL instances. Otherwise you should change the configuration parameter
`praefect['database_port']` for each Praefect instance to the correct value.

### Praefect

> [Introduced](https://gitlab.com/gitlab-org/gitaly/-/issues/2634) in GitLab 13.4, Praefect nodes can no longer be designated as `primary`.

NOTE:
If there are multiple Praefect nodes, complete these steps for **each** node.

To complete this section you need a [configured PostgreSQL server](#postgresql), including:

- IP/host address (`POSTGRESQL_SERVER_ADDRESS`)
- Password (`PRAEFECT_SQL_PASSWORD`)

Praefect should be run on a dedicated node. Do not run Praefect on the
application server, or a Gitaly node.

1. SSH into the **Praefect** node and login as root:

   ```shell
   sudo -i
   ```

1. Disable all other services by editing `/etc/gitlab/gitlab.rb`:

   ```ruby
   # Disable all other services on the Praefect node
   postgresql['enable'] = false
   redis['enable'] = false
   nginx['enable'] = false
   alertmanager['enable'] = false
   prometheus['enable'] = false
   grafana['enable'] = false
   puma['enable'] = false
   sidekiq['enable'] = false
   gitlab_workhorse['enable'] = false
   gitaly['enable'] = false

   # Enable only the Praefect service
   praefect['enable'] = true

   # Prevent database connections during 'gitlab-ctl reconfigure'
   gitlab_rails['rake_cache_clear'] = false
   gitlab_rails['auto_migrate'] = false
   ```

1. Configure **Praefect** to listen on network interfaces by editing
   `/etc/gitlab/gitlab.rb`:

   ```ruby
   praefect['listen_addr'] = '0.0.0.0:2305'

   # Enable Prometheus metrics access to Praefect. You must use firewalls
   # to restrict access to this address/port.
   praefect['prometheus_listen_addr'] = '0.0.0.0:9652'
   ```

1. Configure a strong `auth_token` for **Praefect** by editing
   `/etc/gitlab/gitlab.rb`. This is needed by clients outside the cluster
   (like GitLab Shell) to communicate with the Praefect cluster:

   ```ruby
   praefect['auth_token'] = 'PRAEFECT_EXTERNAL_TOKEN'
   ```

1. Configure **Praefect** to connect to the PostgreSQL database by editing
   `/etc/gitlab/gitlab.rb`.

   You need to replace `POSTGRESQL_SERVER_ADDRESS` with the IP/host address
   of the database, and `PRAEFECT_SQL_PASSWORD` with the strong password set
   above.

   ```ruby
   praefect['database_host'] = 'POSTGRESQL_SERVER_ADDRESS'
   praefect['database_port'] = 5432
   praefect['database_user'] = 'praefect'
   praefect['database_password'] = 'PRAEFECT_SQL_PASSWORD'
   praefect['database_dbname'] = 'praefect_production'
   praefect['database_host_no_proxy'] = 'POSTGRESQL_SERVER_ADDRESS'
   praefect['database_port_no_proxy'] = 5432
   ```

   If you want to use a TLS client certificate, the options below can be used:

   ```ruby
   # Connect to PostgreSQL using a TLS client certificate
   # praefect['database_sslcert'] = '/path/to/client-cert'
   # praefect['database_sslkey'] = '/path/to/client-key'

   # Trust a custom certificate authority
   # praefect['database_sslrootcert'] = '/path/to/rootcert'
   ```

   By default, Praefect refuses to make an unencrypted connection to
   PostgreSQL. You can override this by uncommenting the following line:

   ```ruby
   # praefect['database_sslmode'] = 'disable'
   ```

1. Configure the **Praefect** cluster to connect to each Gitaly node in the
   cluster by editing `/etc/gitlab/gitlab.rb`.

   The virtual storage's name must match the configured storage name in GitLab
   configuration. In a later step, we configure the storage name as `default`
   so we use `default` here as well. This cluster has three Gitaly nodes `gitaly-1`,
   `gitaly-2`, and `gitaly-3`, which are intended to be replicas of each other.

   WARNING:
   If you have data on an already existing storage called
   `default`, you should configure the virtual storage with another name and
   [migrate the data to the Gitaly Cluster storage](#migrate-existing-repositories-to-gitaly-cluster)
   afterwards.

   Replace `PRAEFECT_INTERNAL_TOKEN` with a strong secret, which is used by
   Praefect when communicating with Gitaly nodes in the cluster. This token is
   distinct from the `PRAEFECT_EXTERNAL_TOKEN`.

   Replace `GITALY_HOST_*` with the IP or host address of the each Gitaly node.

   More Gitaly nodes can be added to the cluster to increase the number of
   replicas. More clusters can also be added for very large GitLab instances.

   NOTE:
   When adding additional Gitaly nodes to a virtual storage, all storage names
   within that virtual storage must be unique. Additionally, all Gitaly node
   addresses referenced in the Praefect configuration must be unique.

   ```ruby
   # Name of storage hash must match storage name in git_data_dirs on GitLab
   # server ('default') and in git_data_dirs on Gitaly nodes ('gitaly-1')
   praefect['virtual_storages'] = {
     'default' => {
       'nodes' => {
         'gitaly-1' => {
           'address' => 'tcp://GITALY_HOST_1:8075',
           'token'   => 'PRAEFECT_INTERNAL_TOKEN',
         },
         'gitaly-2' => {
           'address' => 'tcp://GITALY_HOST_2:8075',
           'token'   => 'PRAEFECT_INTERNAL_TOKEN'
         },
         'gitaly-3' => {
           'address' => 'tcp://GITALY_HOST_3:8075',
           'token'   => 'PRAEFECT_INTERNAL_TOKEN'
         }
       }
     }
   }
   ```

   NOTE:
   In [GitLab 13.8 and earlier](https://gitlab.com/gitlab-org/omnibus-gitlab/-/merge_requests/4988),
   Gitaly nodes were configured directly under the virtual storage, and not under the `nodes` key.

1. [Introduced](https://gitlab.com/groups/gitlab-org/-/epics/2013) in GitLab 13.1 and later, enable [distribution of reads](#distributed-reads).

1. Save the changes to `/etc/gitlab/gitlab.rb` and [reconfigure
   Praefect](../restart_gitlab.md#omnibus-gitlab-reconfigure):

   ```shell
   gitlab-ctl reconfigure
   ```

1. To ensure that Praefect [has updated its Prometheus listen
   address](https://gitlab.com/gitlab-org/gitaly/-/issues/2734), [restart
   Praefect](../restart_gitlab.md#omnibus-gitlab-restart):

   ```shell
   gitlab-ctl restart praefect
   ```

1. Verify that Praefect can reach PostgreSQL:

   ```shell
   sudo -u git /opt/gitlab/embedded/bin/praefect -config /var/opt/gitlab/praefect/config.toml sql-ping
   ```

   If the check fails, make sure you have followed the steps correctly. If you
   edit `/etc/gitlab/gitlab.rb`, remember to run `sudo gitlab-ctl reconfigure`
   again before trying the `sql-ping` command.

**The steps above must be completed for each Praefect node!**

#### Enabling TLS support

> [Introduced](https://gitlab.com/gitlab-org/gitaly/-/issues/1698) in GitLab 13.2.

Praefect supports TLS encryption. To communicate with a Praefect instance that listens
for secure connections, you must:

- Use a `tls://` URL scheme in the `gitaly_address` of the corresponding storage entry
  in the GitLab configuration.
- Bring your own certificates because this isn't provided automatically. The certificate
  corresponding to each Praefect server must be installed on that Praefect server.

Additionally the certificate, or its certificate authority, must be installed on all Gitaly servers
and on all Praefect clients that communicate with it following the procedure described in
[GitLab custom certificate configuration](https://docs.gitlab.com/omnibus/settings/ssl.html#install-custom-public-certificates) (and repeated below).

Note the following:

- The certificate must specify the address you use to access the Praefect server. If
  addressing the Praefect server by:

  - Hostname, you can either use the Common Name field for this, or add it as a Subject
    Alternative Name.
  - IP address, you must add it as a Subject Alternative Name to the certificate.

- You can configure Praefect servers with both an unencrypted listening address
  `listen_addr` and an encrypted listening address `tls_listen_addr` at the same time.
  This allows you to do a gradual transition from unencrypted to encrypted traffic, if
  necessary.

To configure Praefect with TLS:

**For Omnibus GitLab**

1. Create certificates for Praefect servers.

1. On the Praefect servers, create the `/etc/gitlab/ssl` directory and copy your key
   and certificate there:

   ```shell
   sudo mkdir -p /etc/gitlab/ssl
   sudo chmod 755 /etc/gitlab/ssl
   sudo cp key.pem cert.pem /etc/gitlab/ssl/
   sudo chmod 644 key.pem cert.pem
   ```

1. Edit `/etc/gitlab/gitlab.rb` and add:

   ```ruby
   praefect['tls_listen_addr'] = "0.0.0.0:3305"
   praefect['certificate_path'] = "/etc/gitlab/ssl/cert.pem"
   praefect['key_path'] = "/etc/gitlab/ssl/key.pem"
   ```

1. Save the file and [reconfigure](../restart_gitlab.md#omnibus-gitlab-reconfigure).

1. On the Praefect clients (including each Gitaly server), copy the certificates,
   or their certificate authority, into `/etc/gitlab/trusted-certs`:

   ```shell
   sudo cp cert.pem /etc/gitlab/trusted-certs/
   ```

1. On the Praefect clients (except Gitaly servers), edit `git_data_dirs` in
   `/etc/gitlab/gitlab.rb` as follows:

   ```ruby
   git_data_dirs({
     "default" => {
       "gitaly_address" => 'tls://LOAD_BALANCER_SERVER_ADDRESS:2305',
       "gitaly_token" => 'PRAEFECT_EXTERNAL_TOKEN'
     }
   })
   ```

1. Save the file and [reconfigure GitLab](../restart_gitlab.md#omnibus-gitlab-reconfigure).

**For installations from source**

1. Create certificates for Praefect servers.
1. On the Praefect servers, create the `/etc/gitlab/ssl` directory and copy your key and certificate
   there:

   ```shell
   sudo mkdir -p /etc/gitlab/ssl
   sudo chmod 755 /etc/gitlab/ssl
   sudo cp key.pem cert.pem /etc/gitlab/ssl/
   sudo chmod 644 key.pem cert.pem
   ```

1. On the Praefect clients (including each Gitaly server), copy the certificates,
   or their certificate authority, into the system trusted certificates:

   ```shell
   sudo cp cert.pem /usr/local/share/ca-certificates/praefect.crt
   sudo update-ca-certificates
   ```

1. On the Praefect clients (except Gitaly servers), edit `storages` in
   `/home/git/gitlab/config/gitlab.yml` as follows:

   ```yaml
   gitlab:
     repositories:
       storages:
         default:
           gitaly_address: tls://LOAD_BALANCER_SERVER_ADDRESS:3305
           path: /some/local/path
   ```

   NOTE:
   `/some/local/path` should be set to a local folder that exists, however no
   data is stored in this folder. This requirement is scheduled to be removed when
   [this issue](https://gitlab.com/gitlab-org/gitaly/-/issues/1282) is resolved.

1. Save the file and [restart GitLab](../restart_gitlab.md#installations-from-source).
1. Copy all Praefect server certificates, or their certificate authority, to the system
   trusted certificates on each Gitaly server so the Praefect server trusts the
   certificate when called by Gitaly servers:

   ```shell
   sudo cp cert.pem /usr/local/share/ca-certificates/praefect.crt
   sudo update-ca-certificates
   ```

1. Edit `/home/git/praefect/config.toml` and add:

   ```toml
   tls_listen_addr = '0.0.0.0:3305'

   [tls]
   certificate_path = '/etc/gitlab/ssl/cert.pem'
   key_path = '/etc/gitlab/ssl/key.pem'
   ```

1. Save the file and [restart GitLab](../restart_gitlab.md#installations-from-source).

### Gitaly

NOTE:
Complete these steps for **each** Gitaly node.

To complete this section you need:

- [Configured Praefect node](#praefect)
- 3 (or more) servers, with GitLab installed, to be configured as Gitaly nodes.
  These should be dedicated nodes, do not run other services on these nodes.

Every Gitaly server assigned to the Praefect cluster needs to be configured. The
configuration is the same as a normal [standalone Gitaly server](index.md),
except:

- The storage names are exposed to Praefect, not GitLab
- The secret token is shared with Praefect, not GitLab

The configuration of all Gitaly nodes in the Praefect cluster can be identical,
because we rely on Praefect to route operations correctly.

Particular attention should be shown to:

- The `gitaly['auth_token']` configured in this section must match the `token`
  value under `praefect['virtual_storages']['nodes']` on the Praefect node. This was set
  in the [previous section](#praefect). This document uses the placeholder
  `PRAEFECT_INTERNAL_TOKEN` throughout.
- The storage names in `git_data_dirs` configured in this section must match the
  storage names under `praefect['virtual_storages']` on the Praefect node. This
  was set in the [previous section](#praefect). This document uses `gitaly-1`,
  `gitaly-2`, and `gitaly-3` as Gitaly storage names.

For more information on Gitaly server configuration, see our [Gitaly
documentation](configure_gitaly.md#configure-gitaly-servers).

1. SSH into the **Gitaly** node and login as root:

   ```shell
   sudo -i
   ```

1. Disable all other services by editing `/etc/gitlab/gitlab.rb`:

   ```ruby
   # Disable all other services on the Praefect node
   postgresql['enable'] = false
   redis['enable'] = false
   nginx['enable'] = false
   grafana['enable'] = false
   puma['enable'] = false
   sidekiq['enable'] = false
   gitlab_workhorse['enable'] = false
   prometheus_monitoring['enable'] = false

   # Enable only the Gitaly service
   gitaly['enable'] = true

   # Enable Prometheus if needed
   prometheus['enable'] = true

   # Prevent database connections during 'gitlab-ctl reconfigure'
   gitlab_rails['rake_cache_clear'] = false
   gitlab_rails['auto_migrate'] = false
   ```

1. Configure **Gitaly** to listen on network interfaces by editing
   `/etc/gitlab/gitlab.rb`:

   ```ruby
   # Make Gitaly accept connections on all network interfaces.
   # Use firewalls to restrict access to this address/port.
   gitaly['listen_addr'] = '0.0.0.0:8075'

   # Enable Prometheus metrics access to Gitaly. You must use firewalls
   # to restrict access to this address/port.
   gitaly['prometheus_listen_addr'] = '0.0.0.0:9236'
   ```

1. Configure a strong `auth_token` for **Gitaly** by editing
   `/etc/gitlab/gitlab.rb`. This is needed by clients to communicate with
   this Gitaly nodes. Typically, this token is the same for all Gitaly
   nodes.

   ```ruby
   gitaly['auth_token'] = 'PRAEFECT_INTERNAL_TOKEN'
   ```

1. Configure the GitLab Shell secret token, which is needed for `git push` operations. Either:

   - Method 1:

     1. Copy `/etc/gitlab/gitlab-secrets.json` from the Gitaly client to same path on the Gitaly
        servers and any other Gitaly clients.
     1. [Reconfigure GitLab](../restart_gitlab.md#omnibus-gitlab-reconfigure) on Gitaly servers.

   - Method 2:

     1. Edit `/etc/gitlab/gitlab.rb`.
     1. Replace `GITLAB_SHELL_SECRET_TOKEN` with the real secret.

        ```ruby
        gitlab_shell['secret_token'] = 'GITLAB_SHELL_SECRET_TOKEN'
        ```

1. Configure and `internal_api_url`, which is also needed for `git push` operations:

   ```ruby
   # Configure the gitlab-shell API callback URL. Without this, `git push` will
   # fail. This can be your front door GitLab URL or an internal load balancer.
   # Examples: 'https://gitlab.example.com', 'http://1.2.3.4'
   gitlab_rails['internal_api_url'] = 'http://GITLAB_HOST'
   ```

1. Configure the storage location for Git data by setting `git_data_dirs` in
   `/etc/gitlab/gitlab.rb`. Each Gitaly node should have a unique storage name
   (such as `gitaly-1`).

   Instead of configuring `git_data_dirs` uniquely for each Gitaly node, it is
   often easier to have include the configuration for all Gitaly nodes on every
   Gitaly node. This is supported because the Praefect `virtual_storages`
   configuration maps each storage name (such as `gitaly-1`) to a specific node, and
   requests are routed accordingly. This means every Gitaly node in your fleet
   can share the same configuration.

   ```ruby
   # You can include the data dirs for all nodes in the same config, because
   # Praefect will only route requests according to the addresses provided in the
   # prior step.
   git_data_dirs({
     "gitaly-1" => {
       "path" => "/var/opt/gitlab/git-data"
     },
     "gitaly-2" => {
       "path" => "/var/opt/gitlab/git-data"
     },
     "gitaly-3" => {
       "path" => "/var/opt/gitlab/git-data"
     }
   })
   ```

1. Save the changes to `/etc/gitlab/gitlab.rb` and [reconfigure
   Gitaly](../restart_gitlab.md#omnibus-gitlab-reconfigure):

   ```shell
   gitlab-ctl reconfigure
   ```

1. To ensure that Gitaly [has updated its Prometheus listen
   address](https://gitlab.com/gitlab-org/gitaly/-/issues/2734), [restart
   Gitaly](../restart_gitlab.md#omnibus-gitlab-restart):

   ```shell
   gitlab-ctl restart gitaly
   ```

**The steps above must be completed for each Gitaly node!**

After all Gitaly nodes are configured, you can run the Praefect connection
checker to verify Praefect can connect to all Gitaly servers in the Praefect
configuration.

1. SSH into each **Praefect** node and run the Praefect connection checker:

   ```shell
   sudo /opt/gitlab/embedded/bin/praefect -config /var/opt/gitlab/praefect/config.toml dial-nodes
   ```

### Load Balancer

In a fault-tolerant Gitaly configuration, a load balancer is needed to route
internal traffic from the GitLab application to the Praefect nodes. The
specifics on which load balancer to use or the exact configuration is beyond the
scope of the GitLab documentation.

NOTE:
The load balancer must be configured to accept traffic from the Gitaly nodes in
addition to the GitLab nodes. Some requests handled by
[`gitaly-ruby`](configure_gitaly.md#gitaly-ruby) sidecar processes call into the main Gitaly
process. `gitaly-ruby` uses the Gitaly address set in the GitLab server's
`git_data_dirs` setting to make this connection.

We hope that if you're managing fault-tolerant systems like GitLab, you have a load balancer
of choice already. Some examples include [HAProxy](https://www.haproxy.org/)
(open-source), [Google Internal Load Balancer](https://cloud.google.com/load-balancing/docs/internal/),
[AWS Elastic Load Balancer](https://aws.amazon.com/elasticloadbalancing/), F5
Big-IP LTM, and Citrix Net Scaler. This documentation outlines what ports
and protocols you need configure.

| LB Port | Backend Port | Protocol |
|:--------|:-------------|:---------|
| 2305    | 2305         | TCP      |

### GitLab

To complete this section you need:

- [Configured Praefect node](#praefect)
- [Configured Gitaly nodes](#gitaly)

The Praefect cluster needs to be exposed as a storage location to the GitLab
application. This is done by updating the `git_data_dirs`.

Particular attention should be shown to:

- the storage name added to `git_data_dirs` in this section must match the
  storage name under `praefect['virtual_storages']` on the Praefect node(s). This
  was set in the [Praefect](#praefect) section of this guide. This document uses
  `default` as the Praefect storage name.

1. SSH into the **GitLab** node and login as root:

   ```shell
   sudo -i
   ```

1. Configure the `external_url` so that files could be served by GitLab
   by proper endpoint access by editing `/etc/gitlab/gitlab.rb`:

   You need to replace `GITLAB_SERVER_URL` with the real external facing
   URL on which current GitLab instance is serving:

   ```ruby
   external_url 'GITLAB_SERVER_URL'
   ```

1. Disable the default Gitaly service running on the GitLab host. It isn't needed
   because GitLab connects to the configured cluster.

   WARNING:
   If you have existing data stored on the default Gitaly storage,
   you should [migrate the data your Gitaly Cluster storage](#migrate-existing-repositories-to-gitaly-cluster)
   first.

   ```ruby
   gitaly['enable'] = false
   ```

1. Add the Praefect cluster as a storage location by editing
   `/etc/gitlab/gitlab.rb`.

   You need to replace:

   - `LOAD_BALANCER_SERVER_ADDRESS` with the IP address or hostname of the load
     balancer.
   - `PRAEFECT_EXTERNAL_TOKEN` with the real secret

   If you are using TLS, the `gitaly_address` should begin with `tls://`.

   ```ruby
   git_data_dirs({
     "default" => {
       "gitaly_address" => "tcp://LOAD_BALANCER_SERVER_ADDRESS:2305",
       "gitaly_token" => 'PRAEFECT_EXTERNAL_TOKEN'
     }
   })
   ```

1. Configure the GitLab Shell secret token so that callbacks from Gitaly nodes during a `git push`
   are properly authenticated. Either:

   - Method 1:

     1. Copy `/etc/gitlab/gitlab-secrets.json` from the Gitaly client to same path on the Gitaly
        servers and any other Gitaly clients.
     1. [Reconfigure GitLab](../restart_gitlab.md#omnibus-gitlab-reconfigure) on Gitaly servers.

   - Method 2:

     1. Edit `/etc/gitlab/gitlab.rb`.
     1. Replace `GITLAB_SHELL_SECRET_TOKEN` with the real secret.

        ```ruby
        gitlab_shell['secret_token'] = 'GITLAB_SHELL_SECRET_TOKEN'
        ```

1. Add Prometheus monitoring settings by editing `/etc/gitlab/gitlab.rb`. If Prometheus
   is enabled on a different node, make edits on that node instead.

   You need to replace:

   - `PRAEFECT_HOST` with the IP address or hostname of the Praefect node
   - `GITALY_HOST_*` with the IP address or hostname of each Gitaly node

   ```ruby
   prometheus['scrape_configs'] = [
     {
       'job_name' => 'praefect',
       'static_configs' => [
         'targets' => [
           'PRAEFECT_HOST:9652', # praefect-1
           'PRAEFECT_HOST:9652', # praefect-2
           'PRAEFECT_HOST:9652', # praefect-3
         ]
       ]
     },
     {
       'job_name' => 'praefect-gitaly',
       'static_configs' => [
         'targets' => [
           'GITALY_HOST_1:9236', # gitaly-1
           'GITALY_HOST_2:9236', # gitaly-2
           'GITALY_HOST_3:9236', # gitaly-3
         ]
       ]
     }
   ]
   ```

1. Save the changes to `/etc/gitlab/gitlab.rb` and [reconfigure GitLab](../restart_gitlab.md#omnibus-gitlab-reconfigure):

   ```shell
   gitlab-ctl reconfigure
   ```

1. Verify on each Gitaly node the Git Hooks can reach GitLab. On each Gitaly node run:

   ```shell
   /opt/gitlab/embedded/bin/gitaly-hooks check /var/opt/gitlab/gitaly/config.toml
   ```

1. Verify that GitLab can reach Praefect:

   ```shell
   gitlab-rake gitlab:gitaly:check
   ```

1. Check in **Admin Area > Settings > Repository > Repository storage** that the Praefect storage
   is configured to store new repositories. Following this guide, the `default` storage should have
   weight 100 to store all new repositories.

1. Verify everything is working by creating a new project. Check the
   "Initialize repository with a README" box so that there is content in the
   repository that viewed. If the project is created, and you can see the
   README file, it works!

### Grafana

Grafana is included with GitLab, and can be used to monitor your Praefect
cluster. See [Grafana Dashboard
Service](https://docs.gitlab.com/omnibus/settings/grafana.html)
for detailed documentation.

To get started quickly:

1. SSH into the **GitLab** node (or whichever node has Grafana enabled) and login as root:

   ```shell
   sudo -i
   ```

1. Enable the Grafana login form by editing `/etc/gitlab/gitlab.rb`.

   ```ruby
   grafana['disable_login_form'] = false
   ```

1. Save the changes to `/etc/gitlab/gitlab.rb` and [reconfigure
   GitLab](../restart_gitlab.md#omnibus-gitlab-reconfigure):

   ```shell
   gitlab-ctl reconfigure
   ```

1. Set the Grafana administrator password. This command prompts you to enter a new
   password:

   ```shell
   gitlab-ctl set-grafana-password
   ```

1. In your web browser, open `/-/grafana` (such as
   `https://gitlab.example.com/-/grafana`) on your GitLab server.

   Login using the password you set, and the username `admin`.

1. Go to **Explore** and query `gitlab_build_info` to verify that you are
   getting metrics from all your machines.

Congratulations! You've configured an observable fault-tolerant Praefect
cluster.

## Distributed reads

> - Introduced in GitLab 13.1 in [beta](https://about.gitlab.com/handbook/product/gitlab-the-product/#alpha-beta-ga) with feature flag `gitaly_distributed_reads` set to disabled.
> - [Made generally available and enabled by default](https://gitlab.com/gitlab-org/gitaly/-/issues/2951) in GitLab 13.3.
> - [Disabled by default](https://gitlab.com/gitlab-org/gitaly/-/issues/3178) in GitLab 13.5.
> - [Enabled by default](https://gitlab.com/gitlab-org/gitaly/-/issues/3334) in GitLab 13.8.

Praefect supports distribution of read operations across Gitaly nodes that are
configured for the virtual node.

All RPCs marked with `ACCESSOR` option like
[GetBlob](https://gitlab.com/gitlab-org/gitaly/-/blob/v12.10.6/proto/blob.proto#L16)
are redirected to an up to date and healthy Gitaly node.

_Up to date_ in this context means that:

- There is no replication operations scheduled for this node.
- The last replication operation is in _completed_ state.

If there is no such nodes, or any other error occurs during node selection, the primary
node is chosen to serve the request.

To track distribution of read operations, you can use the `gitaly_praefect_read_distribution`
Prometheus counter metric. It has two labels:

- `virtual_storage`.
- `storage`.

They reflect configuration defined for this instance of Praefect.

## Strong consistency

> - Introduced in GitLab 13.1 in [alpha](https://about.gitlab.com/handbook/product/gitlab-the-product/#alpha-beta-ga), disabled by default.
> - Entered [beta](https://about.gitlab.com/handbook/product/gitlab-the-product/#alpha-beta-ga) in GitLab 13.2, disabled by default.
> - From GitLab 13.3, disabled unless primary-wins reference transactions strategy is disabled.
> - From GitLab 13.4, enabled by default.

Praefect guarantees eventual consistency by replicating all writes to secondary nodes
after the write to the primary Gitaly node has happened.

Praefect can instead provide strong consistency by creating a transaction and writing
changes to all Gitaly nodes at once.
If enabled, transactions are only available for a subset of RPCs. For more
information, see the [strong consistency epic](https://gitlab.com/groups/gitlab-org/-/epics/1189).

To enable strong consistency:

- In GitLab 13.5, you must use Git v2.28.0 or higher on Gitaly nodes to enable
  strong consistency.
- In GitLab 13.4 and later, the strong consistency voting strategy has been
  improved. Instead of requiring all nodes to agree, only the primary and half
  of the secondaries need to agree. This strategy is enabled by default. To
  disable it and continue using the primary-wins strategy, enable the
  `:gitaly_reference_transactions_primary_wins` feature flag.
- In GitLab 13.3, reference transactions are enabled by default with a
  primary-wins strategy. This strategy causes all transactions to succeed for
  the primary and thus does not ensure strong consistency. To enable strong
  consistency, disable the `:gitaly_reference_transactions_primary_wins`
  feature flag.
- In GitLab 13.2, enable the `:gitaly_reference_transactions` feature flag.
- In GitLab 13.1, enable the `:gitaly_reference_transactions` and `:gitaly_hooks_rpc`
  feature flags.

Changing feature flags requires [access to the Rails console](../feature_flags.md#start-the-gitlab-rails-console).
In the Rails console, enable or disable the flags as required. For example:

```ruby
Feature.enable(:gitaly_reference_transactions)
Feature.disable(:gitaly_reference_transactions_primary_wins)
```

To monitor strong consistency, you can use the following Prometheus metrics:

- `gitaly_praefect_transactions_total`: Number of transactions created and
  voted on.
- `gitaly_praefect_subtransactions_per_transaction_total`: Number of times
  nodes cast a vote for a single transaction. This can happen multiple times if
  multiple references are getting updated in a single transaction.
- `gitaly_praefect_voters_per_transaction_total`: Number of Gitaly nodes taking
  part in a transaction.
- `gitaly_praefect_transactions_delay_seconds`: Server-side delay introduced by
  waiting for the transaction to be committed.
- `gitaly_hook_transaction_voting_delay_seconds`: Client-side delay introduced
  by waiting for the transaction to be committed.

## Replication factor

Replication factor is the number of copies Praefect maintains of a given repository. A higher
replication factor offers better redundancy and distribution of read workload, but also results
in a higher storage cost. By default, Praefect replicates repositories to every storage in a
virtual storage.

### Configure replication factors

WARNING:
The feature is not production ready yet. After you set a replication factor, you can't unset it
without manually modifying database state. Variable replication factor requires you to enable
repository-specific primaries by configuring the `per_repository` primary election strategy. The election
strategy is not production ready yet.

Praefect supports configuring a replication factor on a per-repository basis, by assigning
specific storage nodes to host a repository.

Praefect does not store the actual replication factor, but assigns enough storages to host the repository
so the desired replication factor is met. If a storage node is later removed from the virtual storage,
the replication factor of repositories assigned to the storage is decreased accordingly.

You can configure:

- A default replication factor for each virtual storage that is applied to newly-created repositories.
  The configuration is added to the `/etc/gitlab/gitlab.rb` file:

  ```ruby
  praefect['virtual_storages'] = {
    'default' => {
      'default_replication_factor' => 1,
      # ...
    }
  }
  ```

- A replication factor for an existing repository using the `set-replication-factor` sub-command.
  `set-replication-factor` automatically assigns or unassigns random storage nodes as
  necessary to reach the desired replication factor. The repository's primary node is
  always assigned first and is never unassigned.

  ```shell
  sudo /opt/gitlab/embedded/bin/praefect -config /var/opt/gitlab/praefect/config.toml set-replication-factor -virtual-storage <virtual-storage> -repository <relative-path> -replication-factor <replication-factor>
  ```

  - `-virtual-storage` is the virtual storage the repository is located in.
  - `-repository` is the repository's relative path in the storage.
  - `-replication-factor` is the desired replication factor of the repository. The minimum value is
    `1`, as the primary needs a copy of the repository. The maximum replication factor is the number of
    storages in the virtual storage.

  On success, the assigned host storages are printed. For example:

  ```shell
  $ sudo /opt/gitlab/embedded/bin/praefect -config /var/opt/gitlab/praefect/config.toml set-replication-factor -virtual-storage default -repository @hashed/3f/db/3fdba35f04dc8c462986c992bcf875546257113072a909c162f7e470e581e278.git -replication-factor 2

  current assignments: gitaly-1, gitaly-2
  ```

## Automatic failover and leader election

Praefect regularly checks the health of each backend Gitaly node. This
information can be used to automatically failover to a new primary node if the
current primary node is found to be unhealthy.

- **PostgreSQL (recommended):** Enabled by default, and equivalent to:
  `praefect['failover_election_strategy'] = sql`. This configuration
  option allows multiple Praefect nodes to coordinate via the
  PostgreSQL database to elect a primary Gitaly node. This configuration
  causes Praefect nodes to elect a new primary, monitor its health,
  and elect a new primary if the current one has not been reachable in
  10 seconds by a majority of the Praefect nodes.
- **Memory:** Enabled by setting `praefect['failover_election_strategy'] = 'local'`
  in `/etc/gitlab/gitlab.rb` on the Praefect node. If a sufficient number of health
  checks fail for the current primary backend Gitaly node, and new primary will
  be elected. **Do not use with multiple Praefect nodes!** Using with multiple
  Praefect nodes is likely to result in a split brain.

We are likely to implement support for Consul, and a cloud native, strategy in the future.

## Primary Node Failure

Gitaly Cluster recovers from a failing primary Gitaly node by promoting a healthy secondary as the
new primary.

To minimize data loss, Gitaly Cluster:

- Switches repositories that are outdated on the new primary to [read-only mode](#read-only-mode).
- Elects the secondary with the least unreplicated writes from the primary to be the new primary.
  Because there can still be some unreplicated writes, [data loss can occur](#check-for-data-loss).

### Read-only mode

> - Introduced in GitLab 13.0 as [generally available](https://about.gitlab.com/handbook/product/gitlab-the-product/#generally-available-ga).
> - Between GitLab 13.0 and GitLab 13.2, read-only mode applied to the whole virtual storage and occurred whenever failover occurred.
> - [In GitLab 13.3 and later](https://gitlab.com/gitlab-org/gitaly/-/issues/2862), read-only mode applies on a per-repository basis and only occurs if a new primary is out of date.

When Gitaly Cluster switches to a new primary, repositories enter read-only mode if they are out of
date. This can happen after failing over to an outdated secondary. Read-only mode eases data
recovery efforts by preventing writes that may conflict with the unreplicated writes on other nodes.

To enable writes again, an administrator can:

1. [Check](#check-for-data-loss) for data loss.
1. Attempt to [recover](#data-recovery) missing data.
1. Either [enable writes](#enable-writes-or-accept-data-loss) in the virtual storage or
   [accept data loss](#enable-writes-or-accept-data-loss) if necessary, depending on the version of
   GitLab.

### Check for data loss

The Praefect `dataloss` sub-command identifies replicas that are likely to be outdated. This can help
identify potential data loss after a failover. The following parameters are
available:

- `-virtual-storage` that specifies which virtual storage to check. The default behavior is to
  display outdated replicas of read-only repositories as they might require administrator action.
- In GitLab 13.3 and later, `-partially-replicated` that specifies whether to display a list of
  [outdated replicas of writable repositories](#outdated-replicas-of-writable-repositories).

NOTE:
`dataloss` is still in beta and the output format is subject to change.

To check for repositories with outdated primaries, run:

```shell
sudo /opt/gitlab/embedded/bin/praefect -config /var/opt/gitlab/praefect/config.toml dataloss [-virtual-storage <virtual-storage>]
```

Every configured virtual storage is checked if none is specified:

```shell
sudo /opt/gitlab/embedded/bin/praefect -config /var/opt/gitlab/praefect/config.toml dataloss
```

Repositories which have assigned storage nodes that contain an outdated copy of the repository are listed
in the output. This information is printed for each repository:

- A repository's relative path to the storage directory identifies each repository and groups the related
  information.
- The repository's current status is printed in parentheses next to the disk path. If the repository's primary
  is outdated, the repository is in `read-only` mode and can't accept writes. Otherwise, the mode is `writable`.
- The primary field lists the repository's current primary. If the repository has no primary, the field shows
  `No Primary`.
- The In-Sync Storages lists replicas which have replicated the latest successful write and all writes
  preceding it.
- The Outdated Storages lists replicas which contain an outdated copy of the repository. Replicas which have no copy
  of the repository but should contain it are also listed here. The maximum number of changes the replica is missing
  is listed next to replica. It's important to notice that the outdated replicas may be fully up to date or contain
  later changes but Praefect can't guarantee it.

Whether a replica is assigned to host the repository is listed with each replica's status. `assigned host` is printed
next to replicas which are assigned to store the repository. The text is omitted if the replica contains a copy of
the repository but is not assigned to store the repository. Such replicas aren't kept in-sync by Praefect, but may
act as replication sources to bring assigned replicas up to date.

Example output:

```shell
Virtual storage: default
  Outdated repositories:
    @hashed/3f/db/3fdba35f04dc8c462986c992bcf875546257113072a909c162f7e470e581e278.git (read-only):
      Primary: gitaly-1
      In-Sync Storages:
        gitaly-2, assigned host
      Outdated Storages:
        gitaly-1 is behind by 3 changes or less, assigned host
        gitaly-3 is behind by 3 changes or less
```

A confirmation is printed out when every repository is writable. For example:

```shell
Virtual storage: default
  All repositories are writable!
```

#### Outdated replicas of writable repositories

> [Introduced](https://gitlab.com/gitlab-org/gitaly/-/issues/3019) in GitLab 13.3.

To also list information of repositories whose primary is up to date but one or more assigned
replicas are outdated, use the `-partially-replicated` flag.

A repository is writable if the primary has the latest changes. Secondaries might be temporarily
outdated while they are waiting to replicate the latest changes.

```shell
sudo /opt/gitlab/embedded/bin/praefect -config /var/opt/gitlab/praefect/config.toml dataloss [-virtual-storage <virtual-storage>] [-partially-replicated]
```

Example output:

```shell
Virtual storage: default
  Outdated repositories:
    @hashed/3f/db/3fdba35f04dc8c462986c992bcf875546257113072a909c162f7e470e581e278.git (writable):
      Primary: gitaly-1
      In-Sync Storages:
        gitaly-1, assigned host
      Outdated Storages:
        gitaly-2 is behind by 3 changes or less, assigned host
        gitaly-3 is behind by 3 changes or less
```

With the `-partially-replicated` flag set, a confirmation is printed out if every assigned replica is fully up to
date.

For example:

```shell
Virtual storage: default
  All repositories are up to date!
```

### Check repository checksums

To check a project's repository checksums across on all Gitaly nodes, run the
[replicas Rake task](../raketasks/praefect.md#replica-checksums) on the main GitLab node.

### Enable writes or accept data loss

Praefect provides the following sub-commands to re-enable writes:

- In GitLab 13.2 and earlier, `enable-writes` to re-enable virtual storage for writes after data
  recovery attempts.

   ```shell
   sudo /opt/gitlab/embedded/bin/praefect -config /var/opt/gitlab/praefect/config.toml enable-writes -virtual-storage <virtual-storage>
   ```

- [In GitLab 13.3](https://gitlab.com/gitlab-org/gitaly/-/merge_requests/2415) and later,
  `accept-dataloss` to accept data loss and re-enable writes for repositories after data recovery
  attempts have failed. Accepting data loss causes current version of the repository on the
  authoritative storage to be considered latest. Other storages are brought up to date with the
  authoritative storage by scheduling replication jobs.

  ```shell
  sudo /opt/gitlab/embedded/bin/praefect -config /var/opt/gitlab/praefect/config.toml accept-dataloss -virtual-storage <virtual-storage> -repository <relative-path> -authoritative-storage <storage-name>
  ```

WARNING:
`accept-dataloss` causes permanent data loss by overwriting other versions of the repository. Data
[recovery efforts](#data-recovery) must be performed before using it.

## Data recovery

If a Gitaly node fails replication jobs for any reason, it ends up hosting outdated versions of the
affected repositories. Praefect provides tools for:

- [Automatic](#automatic-reconciliation) reconciliation, for GitLab 13.4 and later.
- [Manual](#manual-reconciliation) reconciliation, for:
  - GitLab 13.3 and earlier.
  - Repositories upgraded to GitLab 13.4 and later without entries in the `repositories` table.
    A migration tool [is planned](https://gitlab.com/gitlab-org/gitaly/-/issues/3033).

These tools reconcile the outdated repositories to bring them fully up to date again.

### Automatic reconciliation

> [Introduced](https://gitlab.com/gitlab-org/gitaly/-/issues/2717) in GitLab 13.4.

Praefect automatically reconciles repositories that are not up to date. By default, this is done every
five minutes. For each outdated repository on a healthy Gitaly node, the Praefect picks a
random, fully up-to-date replica of the repository on another healthy Gitaly node to replicate from. A
replication job is scheduled only if there are no other replication jobs pending for the target
repository.

The reconciliation frequency can be changed via the configuration. The value can be any valid
[Go duration value](https://golang.org/pkg/time/#ParseDuration). Values below 0 disable the feature.

Examples:

```ruby
praefect['reconciliation_scheduling_interval'] = '5m' # the default value
```

```ruby
praefect['reconciliation_scheduling_interval'] = '30s' # reconcile every 30 seconds
```

```ruby
praefect['reconciliation_scheduling_interval'] = '0' # disable the feature
```

### Manual reconciliation

The Praefect `reconcile` sub-command allows for the manual reconciliation between two Gitaly nodes. The
command replicates every repository on a later version on the reference storage to the target storage.

```shell
sudo /opt/gitlab/embedded/bin/praefect -config /var/opt/gitlab/praefect/config.toml reconcile -virtual <virtual-storage> -reference <up-to-date-storage> -target <outdated-storage> -f
```

- Replace the placeholder `<virtual-storage>` with the virtual storage containing the Gitaly node storage to be checked.
- Replace the placeholder `<up-to-date-storage>` with the Gitaly storage name containing up to date repositories.
- Replace the placeholder `<outdated-storage>` with the Gitaly storage name containing outdated repositories.

## Migrate existing repositories to Gitaly Cluster

If your GitLab instance already has repositories on single Gitaly nodes, these aren't migrated to
Gitaly Cluster automatically.

Project repositories may be moved from one storage location using the [Project repository storage moves API](../../api/project_repository_storage_moves.md). Note that this API cannot move all repository types. For moving other repositories types, see:

- [Snippet repository storage moves API](../../api/snippet_repository_storage_moves.md).
- [Group repository storage moves API](../../api/group_repository_storage_moves.md).

To move repositories to Gitaly Cluster:

1. [Schedule repository storage moves for all projects on a storage shard](../../api/project_repository_storage_moves.md#schedule-repository-storage-moves-for-all-projects-on-a-storage-shard) using the API. For example:

   ```shell
   curl --request POST --header "Private-Token: <your_access_token>" --header "Content-Type: application/json" \
   --data '{"source_storage_name":"gitaly","destination_storage_name":"praefect"}' "https://gitlab.example.com/api/v4/project_repository_storage_moves"
   ```

1. [Query the most recent repository moves](../../api/project_repository_storage_moves.md#retrieve-all-project-repository-storage-moves)
   using the API. The query indicates either:
   - The moves have completed successfully. The `state` field is `finished`.
   - The moves are in progress. Re-query the repository move until it completes successfully.
   - The moves have failed. Most failures are temporary and are solved by rescheduling the move.

1. After the moves are complete, [query projects](../../api/projects.md#list-all-projects)
   using the API to confirm that all projects have moved. No projects should be returned
   with `repository_storage` field set to the old storage.

In a similar way, you can move other repository types by using the
[Snippet repository storage moves API](../../api/snippet_repository_storage_moves.md) **(FREE SELF)**
or the [Groups repository storage moves API](../../api/group_repository_storage_moves.md) **(PREMIUM SELF)**.

## Debugging Praefect

If you receive an error, check `/var/log/gitlab/gitlab-rails/production.log`.

Here are common errors and potential causes:

- 500 response code
  - **ActionView::Template::Error (7:permission denied)**
    - `praefect['auth_token']` and `gitlab_rails['gitaly_token']` do not match on the GitLab server.
  - **Unable to save project. Error: 7:permission denied**
    - Secret token in `praefect['storage_nodes']` on GitLab server does not match the
      value in `gitaly['auth_token']` on one or more Gitaly servers.
- 503 response code
  - **GRPC::Unavailable (14:failed to connect to all addresses)**
    - GitLab was unable to reach Praefect.
  - **GRPC::Unavailable (14:all SubCons are in TransientFailure...)**
    - Praefect cannot reach one or more of its child Gitaly nodes. Try running
      the Praefect connection checker to diagnose.
