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
[![](https://badgen.net/badge/Slack/Join%20AutoMQ/0abd59?icon=slack)](https://go.automq.com/slack)


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

## Repository Structure

This repository is organized into three main directories:

### 📦 [opensource-examples](opensource-examples/)

Examples and demos for the **AutoMQ Open Source** version. This directory contains:

*   **[Setup](opensource-examples/setup/)**: Deploy AutoMQ open-source version using Docker Compose and Kubernetes (Bitnami/Strimzi Helm charts).
*   **[Clients](opensource-examples/clients/)**: Build and run demos for various language clients, including Java, C++, Go, Python, and JavaScript.
*   **[Table Topic](opensource-examples/table-topic/)**: Explore AutoMQ's Table Topic feature that automatically streams Kafka messages into Apache Iceberg tables.
*   **[UI Tools](opensource-examples/ui/)**: Set up web-based management UIs for AutoMQ, including Kafka UI, Kafdrop, and Redpanda Console.

### ☁️ [byoc-examples](byoc-examples/)

Examples for deploying **AutoMQ Cloud Service (BYOC - Bring Your Own Cloud)**. This directory contains:

*   **[Setup](byoc-examples/setup/)**: Deploy AutoMQ cloud service on AWS (EC2 and EKS) and Azure using Terraform.
*   **[Kubernetes Infrastructure](byoc-examples/setup/kubernetes/)**: Provides Terraform scripts for provisioning Kubernetes clusters on AWS, Azure, and GCP.

### 🚀 [software-examples](software-examples/)

Kubernetes deployment examples for AutoMQ software with different configurations:

*   **[Kubernetes](software-examples/kubernetes/)**: Deployment examples with role-based, static, and TLS configurations.

## Getting Started

Each section contains a detailed `README.md` file with instructions on how to run the samples. Please refer to the specific section for more information.

## Important Note on Production Use

> **Disclaimer**: The samples and demonstrations provided in this repository are intended for Proof of Concept (PoC) and testing purposes only. They are not recommended for direct use in a production environment.
>
> For production deployments, we strongly recommend discussing your architecture and best practices with our engineering team to ensure optimal performance, reliability, and cost-efficiency.
>
> Please **[contact us](https://www.automq.com/contact)** to get in touch.