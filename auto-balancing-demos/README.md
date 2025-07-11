# AutoMQ Auto-Balancing Demos

This section provides a collection of demonstrations showcasing AutoMQ's powerful auto-balancing capabilities. These demos illustrate how the cluster can automatically rebalance workloads under various conditions to optimize performance and ensure stability.

Each subdirectory contains a specific scenario with a `docker-compose.yml` setup and detailed instructions.

### Scenarios

1.  **[Traffic-Based Balancing](./traffic-based/)**: Demonstrates how AutoMQ rebalances partitions when one broker receives a disproportionately high amount of traffic (bytes/sec).
2.  **[QPS-Based Balancing](./qps-based/)**: Shows how the cluster rebalances based on request rate (queries per second), even if the traffic volume is similar.
3.  **[Slow Node Isolation](./slow-node-isolation/)**: Simulates a "slow node" with high latency and demonstrates how AutoMQ automatically isolates it by migrating its partitions to healthier nodes.
4.  **[Scale-Up Balancing](./scale-up/)**: Illustrates how, after adding a new broker to the cluster, AutoMQ automatically migrates some of the load to the new node to utilize its resources.
5.  **[Scale-Down Balancing](./scale-down/)**: Shows how, when a broker is decommissioned or fails, its workload is safely and automatically distributed among the remaining active nodes.
