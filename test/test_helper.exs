:ok = TestCluster.setup_node_for_cluster_once()

:pg.start_link(ClusterLoadBalancer)

ExUnit.start()
