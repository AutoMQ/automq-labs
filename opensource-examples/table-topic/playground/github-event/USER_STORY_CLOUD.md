# 用户故事：基于 AutoMQ BYOC 的实时 GitHub 事件分析系统（AWS 云上部署）

## 概述

作为一名**数据工程师**，我希望在 AWS 上使用 AutoMQ BYOC 构建一个**实时分析管道**来处理 GitHub 事件，以便能够使用 AWS Athena 等标准 SQL 工具**直接从 S3 查询 GitHub 事件数据**，而无需管理复杂的 ETL 管道。

## 业务价值

本场景旨在深入了解 AutoMQ 的 Table Topic 功能，探索其在流处理场景下的强大能力。通过构建实时 GitHub 事件分析系统，我们将展示 Table Topic 如何自动将 Kafka 流数据转换为 Apache Iceberg 表格式并存储到 S3，从而实现流式数据与批处理分析的完美融合。更重要的是，我们将验证 Table Topic 与 Spark 和 AWS Athena 的集成能力，展示如何在不构建复杂 ETL 管道的情况下，直接使用标准 SQL 工具对实时流数据进行查询和分析，为现代数据架构提供一种更简洁、更高效的流批一体化解决方案。

## 架构设计

```
GH Archive → Lambda/ECS Producer → AutoMQ BYOC (Kafka) → Table Topic → Iceberg Table (S3) → AWS Athena/EMR
                                                                         ↓
                                                              S3 Table (元数据存储在 S3)
```

### 核心组件

1. **AutoMQ BYOC 集群**（Terraform 部署）
   - 部署在 AWS EKS 或 EC2 上
   - 配置 S3 作为存储后端
   - 启用 Table Topic 功能以实现自动 Iceberg 转换

2. **数据生产者**（AWS Lambda 或 ECS Fargate）
   - 持续从 GH Archive 获取 GitHub 事件
   - 将事件发送到 AutoMQ Kafka 主题
   - 处理重试和错误恢复

3. **AutoMQ Table Topic**
   - 自动将 Kafka 主题转换为 Iceberg 表格式
   - 将数据存储在 S3 存储桶中
   - 通过 Schema Registry 管理数据模式

4. **S3 Table**
   - Iceberg 表直接存储在 S3 中，元数据也存储在 S3
   - 使查询引擎能够直接从 S3 发现和查询表

5. **查询层**
   - **AWS Athena**：在 S3 上进行无服务器 SQL 查询
   - **AWS EMR**：基于 Spark 的复杂工作负载分析
   - **Amazon QuickSight**：商业智能仪表板

## 实施细节

### 1. 基础设施搭建（Terraform）

```hcl
# 在 AWS 上部署 AutoMQ BYOC 集群
module "automq_byoc" {
  source = "automq/automq-byoc/aws"
  
  cluster_name = "github-events-analytics"
  s3_bucket     = aws_s3_bucket.iceberg_warehouse.bucket
  vpc_id        = aws_vpc.main.id
  
  # 启用 Table Topic 功能
  enable_table_topic = true
  table_topic_catalog_type = "s3"  # 使用 S3 Table
  table_topic_warehouse    = "s3://${aws_s3_bucket.iceberg_warehouse.bucket}/warehouse/"
}
```

**与本地 Docker 部署的主要区别：**
- 使用真实的 AWS S3 而不是 MinIO
- 部署在 EKS/EC2 上而不是本地 Docker
- 使用 S3 Table 存储 Iceberg 表（元数据直接存储在 S3，无需额外的目录服务）
- 基于流量自动扩缩容
- 集成 AWS IAM 实现安全控制

### 2. 生产者部署

**方案 A：AWS Lambda（事件驱动）**
- 定时 Lambda 函数（每 5 分钟执行一次）
- 获取每小时的 GitHub 事件归档
- 发送到 AutoMQ Kafka 主题
- 适合周期性数据摄取，成本效益高

**方案 B：ECS Fargate（持续运行）**
- 长期运行的容器服务
- 持续从 GH Archive 拉取数据
- 更适合高吞吐量场景
- 基于队列深度自动扩缩容

### 3. Table Topic 配置

创建启用 Table Topic 的 Kafka 主题：

```bash
# 通过 AutoMQ CLI 或 Terraform
kafka-topics.sh --create \
  --topic github_events_iceberg \
  --partitions 16 \
  --config automq.table.topic.enable=true \
  --config automq.table.topic.catalog.type=s3 \
  --config automq.table.topic.catalog.warehouse=s3://github-events-warehouse/warehouse/ \
  --config automq.table.topic.schema.registry.url=http://schema-registry:8081
```

### 4. 从 S3 查询数据

**使用 AWS Athena：**

```sql
-- 查询最近的 GitHub 事件
SELECT 
  type,
  repo_name,
  actor_login,
  created_at,
  COUNT(*) as event_count
FROM github_events_iceberg
WHERE created_at >= current_timestamp - interval '3' day
GROUP BY type, repo_name, actor_login, created_at
ORDER BY created_at DESC
LIMIT 100;

-- 按星标数排序的热门仓库（WatchEvents）
SELECT 
  repo_name,
  COUNT(*) as star_count
FROM github_events_iceberg
WHERE type = 'WatchEvent'
  AND created_at >= current_timestamp - interval '3' day
GROUP BY repo_name
ORDER BY star_count DESC
LIMIT 10;
```

**使用 AWS EMR（Spark）：**

```python
from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("GitHubEventsAnalytics") \
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
    .config("spark.sql.catalog.s3", "org.apache.iceberg.spark.SparkCatalog") \
    .config("spark.sql.catalog.s3.type", "hadoop") \
    .config("spark.sql.catalog.s3.warehouse", "s3://github-events-warehouse/warehouse/") \
    .getOrCreate()

# 查询 Iceberg 表（直接从 S3 读取）
df = spark.sql("""
    SELECT * 
    FROM s3.default.github_events_iceberg 
    WHERE created_at >= current_timestamp() - interval 3 days
    ORDER BY created_at DESC
    LIMIT 100
""")
df.show()
```

## 成功标准

1. ✅ **基础设施**：通过 Terraform 在 AWS 上部署 AutoMQ BYOC 集群
2. ✅ **数据摄取**：持续从 GH Archive 摄取 GitHub 事件
3. ✅ **表创建**：通过 Table Topic 在 S3 中自动创建 Iceberg 表
4. ✅ **查询能力**：可通过 AWS Athena 和 EMR 查询数据
5. ✅ **实时分析**：查询在数据摄取后几分钟内返回结果
6. ✅ **成本优化**：每天处理 1000 万事件的总体基础设施成本 < $500/月

## 监控与可观测性

- **CloudWatch 指标**：监控 AutoMQ 集群健康状态、吞吐量、延迟
- **CloudWatch 日志**：生产者日志、Kafka broker 日志
- **Athena 查询历史**：跟踪查询性能和成本
- **S3 存储指标**：监控 Iceberg 表增长

## 安全考虑

- **IAM 角色**：生产者和查询服务使用 IAM 角色（无硬编码凭证）
- **VPC**：AutoMQ 集群部署在私有子网中
- **S3 加密**：Iceberg 数据静态加密
- **Schema Registry**：启用身份验证进行模式管理

## 成本估算

- **AutoMQ BYOC**：约 $200-300/月（3 节点集群）
- **S3 存储**：约 $50/月（100GB 数据，标准层）
- **Athena 查询**：约 $5/TB 扫描（按查询付费）
- **Lambda/ECS**：约 $20/月（生产者）
- **总计**：约 $275-375/月

## 后续步骤

1. 使用 Terraform 部署 AutoMQ BYOC 集群
2. 设置生产者服务（Lambda 或 ECS）
3. 创建 Table Topic 并验证 Iceberg 表创建（使用 S3 Table）
4. 配置查询引擎以直接从 S3 读取 Iceberg 表
5. 通过 AWS Athena 测试查询
6. 在 Amazon QuickSight 中构建仪表板

## 参考资料

- [AutoMQ BYOC 文档](https://www.automq.com/docs/automq-cloud)
- [AWS Athena Iceberg 集成](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg.html)
- [GH Archive](https://www.gharchive.org/)
- [Apache Iceberg](https://iceberg.apache.org/)
