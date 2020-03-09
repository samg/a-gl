export default [
  {
    name: 'My Cluster 1',
    environmentScope: '*',
    size: '3',
    clusterType: 'group_type',
    status: 'disabled',
    memory: '22.50 (30% free)',
  },
  {
    name: 'My Cluster 2',
    environmentScope: 'development',
    size: '12',
    clusterType: 'project_type',
    status: 'unreachable',
    memory: '11 (60% free)',
  },
  {
    name: 'My Cluster 3',
    environmentScope: 'development',
    size: '12',
    clusterType: 'project_type',
    status: 'authentication_failure',
    memory: '22 (33% free)',
  },
  {
    name: 'My Cluster 4',
    environmentScope: 'production',
    size: '12',
    clusterType: 'project_type',
    status: 'deleting',
    memory: '45 (15% free)',
  },
  {
    name: 'My Cluster 5',
    environmentScope: 'development',
    size: '12',
    clusterType: 'project_type',
    status: 'connected',
    memory: '20.12 (35% free)',
  },
];
