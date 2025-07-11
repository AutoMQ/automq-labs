# AutoMQ Auto-Balancing Demos

This section provides a collection of demonstrations showcasing AutoMQ's powerful auto-balancing capabilities. These demos illustrate how the cluster can automatically rebalance workloads under various conditions to optimize performance and ensure stability.

## General Workflow

The demos in this section are designed to run against a pre-existing AutoMQ cluster. They do not include cluster setup instructions themselves. The general workflow is as follows:

1.  **Deploy an AutoMQ Cluster**: First, deploy a multi-node AutoMQ cluster using one of the methods provided in the **[Open Source Setup](../opensource-setup/)** directory (e.g., using the Docker Compose or Kubernetes guides). A three-node cluster is recommended to best observe balancing behavior.

2.  **Navigate to a Demo**: Change into the directory of the specific scenario you want to test (e.g., `cd traffic-based`).

3.  **Run the Demo Workload**: Follow the instructions in the `README.md` of the specific demo. This will typically involve running a script or a `docker-compose.yml` file that generates a specific type of load to create an imbalance.

4.  **Observe and Verify**: The demo's README will guide you on what metrics to observe (e.g., `BytesInPerSec`, partition distribution) to see the "before" and "after" state, confirming that the auto-balancer has taken action as expected.

## Scenarios

> **Note on Feature Availability**:
> *   **AutoMQ Open Source** supports Traffic-Based Balancing and balancing during Scale-Up/Scale-Down events.
> *   **AutoMQ Cloud** supports all scenarios, including the advanced QPS-Based Balancing and Slow Node Isolation features. To test these, please set up an [AutoMQ Cloud cluster](https://www.automq.com/docs/automq-cloud/getting-started/install-byoc-environment/aws/install-env-from-marketplace).

1.  **[Traffic-Based Balancing](./traffic-based/)**: Demonstrates how AutoMQ rebalances partitions when one broker receives a disproportionately high amount of traffic (bytes/sec).
2.  **[QPS-Based Balancing](./qps-based/)**: Shows how the cluster rebalances based on request rate (queries per second), even if the traffic volume is similar.
3.  **[Slow Node Isolation](./slow-node-isolation/)**: Simulates a "slow node" with high latency and demonstrates how AutoMQ automatically isolates it by migrating its partitions to healthier nodes.
4.  **[Scale-Up Balancing](./scale-up/)**: Illustrates how, after adding a new broker to the cluster, AutoMQ automatically migrates some of the load to the new node to utilize its resources.
5.  **[Scale-Down Balancing](./scale-down/)**: Shows how, when a broker is decommissioned or fails, its workload is safely and automatically distributed among the remaining active nodes.