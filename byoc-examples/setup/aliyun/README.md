# AutoMQ on Alibaba Cloud

This directory contains examples for managing AutoMQ resources in an existing
Alibaba Cloud BYOC environment.

## Examples

### [AutoMQ Elastic Pool](./automq-cluster/)

Create a three-AZ VMIS AutoMQ Instance with the AutoMQ Terraform Provider. The
example uses Alibaba Cloud Regional ESSD-backed WAL and references existing
VSwitches, a security group, an OSS data bucket, a PrivateZone, and a RAM role.
