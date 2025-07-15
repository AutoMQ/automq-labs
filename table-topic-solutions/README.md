# Table Topic Solutions

`Table Topic` is a core feature of AutoMQ that redefines how data is streamed into table formats like Apache Iceberg. It enables **seamless, real-time data streaming directly into Iceberg tables**, eliminating the need for periodic ETL jobs. This "Zero-ETL" approach simplifies data pipelines and provides a powerful foundation for building **unified stream-batch** data lakehouses. By merging the real-time append capabilities of a stream with the cost-effective, high-throughput nature of object storage, Table Topic unlocks true stream-batch unification.

## Open-Source and Cloud Availability

The Table Topic feature is available in both the **open-source version** of AutoMQ and the **AutoMQ Cloud** service. You can choose the deployment method that best suits your business needs.

## Solutions

This directory contains practical application scenarios and solutions based on Table Topic to help users better understand and utilize its capabilities.

### Available Solutions

*   [**Iceberg Spark Streaming Integration**](./iceberg-spark-streaming/README.md)
    This example demonstrates how to write data in real-time into an Iceberg table managed by a Table Topic using a Spark Streaming job. It's a typical streaming ETL scenario that showcases the unified stream-batch power of Table Topic.

### Work in Progress

We are actively working on more solutions to cover a wider range of use cases. Stay tuned for upcoming examples!