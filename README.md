<div align="center">
<p align="center">
  📑&nbsp <a
    href="https://www.automq.com/docs/automq/what-is-automq/overview?utm_source=github_automq"
    target="_blank"
  ><b>Documentation</b></a>&nbsp&nbsp&nbsp
  🔥&nbsp <a
    href="https://www.automq.com/docs/automq-cloud/getting-started/install-byoc-environment/aws/install-env-from-marketplace?utm_source=github_automq"
    target="_blank"
  ><b>Free trial of AutoMQ on AWS</b></a>&nbsp&nbsp&nbsp
</p>
</div>

[![Linkedin Badge](https://img.shields.io/badge/-LinkedIn-blue?style=flat-square&logo=Linkedin&logoColor=white&link=https://www.linkedin.com/company/automq)](https://www.linkedin.com/company/automq)
[![](https://badgen.net/badge/Slack/Join%20AutoMQ/0abd59?icon=slack)](https://join.slack.com/t/automq/shared_invite/zt-29h17vye9-thf31ebIVL9oXuRdACnOIA)


# AutoMQ Labs

This repository provides a collection of samples to help you get started with [AutoMQ](https://www.automq.com), the next-generation cloud-native streaming platform, covering both open-source and cloud service setups.

## AutoMQ Open Source vs. AutoMQ Cloud

*   **AutoMQ Open Source**: A stateless Kafka® on S3, offering 10x cost savings and scaling in seconds under the Apache License 2.0. Due to the nature of object storage, latency can be in the hundreds of milliseconds.
*   **AutoMQ Cloud Service**: Builds upon the open-source version with more shared storage options. It guarantees low latency consistent with Apache Kafka and includes commercial features like Kafka Linking for seamless migration.

## A Note on Software Versions

> The software versions used in the demos within this repository may be outdated. For any real-world use case, please use the latest official releases.
>
> -   **Open Source Docker Images**: Find the latest tags on [Docker Hub](https://hub.docker.com/r/automqinc/automq/tags).
> -   **Open Source Binaries**: Download the latest release from [GitHub Releases](https://github.com/AutoMQ/automq/releases).
> -   **AutoMQ Cloud**: View the latest version details in the [Cloud Release Notes](https://www.automq.com/docs/automq-cloud/release-notes).

## Overview

This repository is organized into the following sections:

*   **[Open Source Setup](./opensource-setup/)**: Deploy AutoMQ open-source version using Docker Compose, Kubernetes, and Ansible.
*   **[Client Examples](./client-examples/)**: Build and run demos for various language clients, including Java, C++, Go, and Python.
*   **[Table Topic Solutions](./table-topic-solutions/)**: Explore solutions for append and CDC scenarios with Table Topic, and integrations with Iceberg REST Catalog, AWS Glue, and Hive Metastore.
*   **[Cloud Service Setup](./cloudservice-setup/)**: Deploy AutoMQ cloud service on AWS (EC2 and EKS), GCP (Kubernetes), and Azure (Kubernetes) using Terraform.
*   **[Observability](./observability/)**: Set up a monitoring stack with Mimir and Grafana for AutoMQ using Docker Compose.
*   **[Kubernetes](./kubernetes/)**: Provides Terraform scripts for provisioning Kubernetes clusters on AWS, Azure, and GCP.
*   **[Kafka Linking Demos](./kafka-linking-demos/)**: Learn how to migrate from any Kafka cluster to AutoMQ with demos for standard clients and Flink applications.
*   **[Auto-Balancing Demos](./auto-balancing-demos/)**: See how AutoMQ automatically balances workloads based on traffic, QPS, and node health.

## Getting Started

Each section contains a detailed `README.md` file with instructions on how to run the samples. Please refer to the specific section for more information.

## Important Note on Production Use

> **Disclaimer**: The samples and demonstrations provided in this repository are intended for Proof of Concept (PoC) and testing purposes only. They are not recommended for direct use in a production environment.
>
> For production deployments, we strongly recommend discussing your architecture and best practices with our engineering team to ensure optimal performance, reliability, and cost-efficiency.
>
> Please **[contact us](https://www.automq.com/contact)** to get in touch.

## Contributing

We welcome contributions! Please see our [contributing guidelines](./CONTRIBUTING.md) for more information.

## License

This project is licensed under the [Apache License 2.0](./LICENSE).
