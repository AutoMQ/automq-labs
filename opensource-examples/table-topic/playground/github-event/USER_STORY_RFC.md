# 用户故事：AutoMQ Table Topic 功能调研与 RFC 准备

## 概述

作为一名**负责 AutoMQ 产品调研的 Kafka SRE**，我已经通过会议和邮件对 AutoMQ 的技术架构和价格有了一定了解，现在需要准备 **RFC（Request for Comments）** 向老板和同事汇报。如果方案得到认可，我们才能正式向 DevOps 团队申请云资源进行测试。在正式测试之前，我希望通过这个 GitHub 事件分析场景**亲自验证 AutoMQ 的 Table Topic 功能**，特别是验证它是否能与我们现有的 **AWS Athena** 和 **Stream Processing** 架构相结合，以便在 RFC 评审时能够基于实际体验提出更有价值的问题，并更准确地评估 AutoMQ 的能力。

## 背景与挑战

作为 Kafka SRE，我负责评估 AutoMQ 作为我们现有 Kafka 基础设施的潜在替代方案。虽然我已经通过多次会议和邮件沟通了解了 AutoMQ 的技术架构、定价模式和核心能力，但我还没有机会亲自测试和验证这些能力。在正式测试之前，我需要：

1. **验证 Table Topic 功能**：AutoMQ 声称 Table Topic 可以自动将 Kafka 流数据转换为 Iceberg 表并存储到 S3，但我需要确认这个功能是否真的如他们所说那样简单易用
2. **评估与现有架构的兼容性**：我们当前使用 AWS Athena 进行数据分析，使用 Spark 进行流处理。我需要确认 Table Topic 生成的 Iceberg 表是否能够无缝集成到我们的现有工作流中
3. **了解实际效果**：通过一个真实的场景（GitHub 事件分析）来体验 Table Topic 的实际效果，包括数据转换的延迟、查询性能、以及整体架构的简洁性
4. **为 RFC 准备素材**：通过亲自上手体验，我能够提出更有针对性的问题，并在内部评审时为方案提供更有说服力的支持

## 业务价值

本场景旨在通过一个实际的 GitHub 事件分析用例，深入验证 AutoMQ 的 Table Topic 功能在实际生产场景中的表现。通过构建这个实时分析管道，我将能够：

- **验证流批一体化能力**：确认 Table Topic 是否真的能够实现流式数据与批处理分析的完美融合，无需构建复杂的 ETL 管道
- **评估与 AWS Athena 的集成**：测试使用 AWS Athena 直接查询 Table Topic 生成的 Iceberg 表，验证查询性能和易用性
- **验证与 Stream Processing 的结合**：探索 Table Topic 如何与我们的 Spark 流处理工作流相结合，评估是否能够简化现有架构
- **收集实际体验数据**：通过亲自操作，收集关于部署复杂度、配置难度、性能表现等方面的第一手数据，为 RFC 评审提供客观依据

如果 AutoMQ 的 Table Topic 确实如宣传的那样优秀，我将能够在内部评审时为该方案提供更有力的支持，推动团队进行正式测试。

## 架构设计

```
GH Archive → Producer → AutoMQ BYOC (Kafka) → Table Topic → Iceberg Table (S3) → AWS Athena/Spark
                                                                     ↓
                                                          S3 Table (元数据存储在 S3)
```

### 核心验证点

1. **AutoMQ BYOC 部署**（Terraform）
   - 验证 Terraform 模块的完整性和易用性
   - 确认部署流程是否顺畅，配置是否清晰
   - 评估部署时间和资源消耗

2. **Table Topic 配置与使用**
   - 验证 Table Topic 的配置是否简单直观
   - 确认自动转换功能是否按预期工作
   - 评估数据转换的实时性和准确性

3. **S3 Table 存储**
   - 验证 Iceberg 表是否正确存储在 S3
   - 确认元数据管理是否可靠
   - 评估存储成本和数据组织方式

4. **AWS Athena 集成**
   - 验证是否能够直接从 S3 发现和查询 Iceberg 表
   - 测试查询性能和响应时间
   - 评估 SQL 兼容性和功能完整性

5. **Spark 流处理集成**
   - 验证 Spark 是否能够读取 Table Topic 生成的 Iceberg 表
   - 测试流批一体化的实际效果
   - 评估与现有 Spark 工作流的兼容性

## 验证场景：GitHub 事件实时分析

### 场景描述

使用 GH Archive 提供的公开 GitHub 事件数据，构建一个实时分析管道：
- 持续从 GH Archive 获取 GitHub 事件（WatchEvent、PushEvent 等）
- 通过 Producer 发送到 AutoMQ Kafka 主题
- Table Topic 自动将数据转换为 Iceberg 表并存储到 S3
- 使用 AWS Athena 和 Spark 查询和分析数据

### 验证目标

1. **功能验证**
   - ✅ Table Topic 能够自动创建 Iceberg 表
   - ✅ 数据能够正确写入 S3
   - ✅ 表结构符合预期（基于 Schema Registry 的模式）

2. **集成验证**
   - ✅ AWS Athena 能够发现并查询 S3 中的 Iceberg 表
   - ✅ Spark 能够读取 Iceberg 表进行流处理
   - ✅ 查询性能满足预期

3. **易用性验证**
   - ✅ Terraform 配置简单明了
   - ✅ Table Topic 配置直观
   - ✅ 整体部署流程顺畅

4. **效果评估**
   - ✅ 数据延迟在可接受范围内
   - ✅ 查询响应时间合理
   - ✅ 架构简化程度符合预期

## 实施步骤

### 阶段 1：本地验证（当前阶段）

在正式申请云资源之前，使用本地 Docker 环境进行初步验证：

1. **部署本地环境**
   ```bash
   # 使用 playground 的 docker-compose 环境
   just -f github-event/justfile up
   ```

2. **验证 Table Topic 功能**
   - 创建 Table Topic
   - 启动 Producer 发送数据
   - 验证 Iceberg 表创建和数据写入

3. **测试查询能力**
   - 使用 Spark SQL 查询表
   - 验证数据正确性
   - 评估查询性能

### 阶段 2：云上验证（正式测试阶段）

获得审批后，在 AWS 上进行完整验证：

1. **使用 Terraform 部署 AutoMQ BYOC**
   ```hcl
   module "automq_byoc" {
     source = "automq/automq-byoc/aws"
     
     cluster_name = "table-topic-validation"
     s3_bucket     = aws_s3_bucket.iceberg_warehouse.bucket
     
     enable_table_topic = true
     table_topic_catalog_type = "s3"
     table_topic_warehouse    = "s3://${aws_s3_bucket.iceberg_warehouse.bucket}/warehouse/"
   }
   ```

2. **部署 Producer 服务**
   - 使用 ECS Fargate 或 Lambda
   - 持续从 GH Archive 获取数据
   - 发送到 AutoMQ Kafka 主题

3. **验证 AWS Athena 集成**
   ```sql
   -- 测试查询
   SELECT 
     type,
     repo_name,
     COUNT(*) as event_count
   FROM github_events_iceberg
   WHERE created_at >= current_timestamp - interval '3' day
   GROUP BY type, repo_name
   ORDER BY event_count DESC
   LIMIT 10;
   ```

4. **验证 Spark 集成**
   - 配置 Spark 读取 S3 中的 Iceberg 表
   - 执行流处理任务
   - 验证结果正确性

## 关键验证问题

通过这个场景，我将重点验证以下问题：

1. **Table Topic 的实际效果如何？**
   - 数据转换是否真的自动化？
   - 转换延迟是多少？
   - 数据准确性如何？

2. **与 AWS Athena 的集成是否顺畅？**
   - 是否能够自动发现表？
   - 查询性能如何？
   - SQL 兼容性如何？

3. **与 Stream Processing 的结合是否可行？**
   - Spark 能否无缝读取？
   - 流批一体化效果如何？
   - 是否能够简化现有架构？

4. **部署和运维复杂度如何？**
   - Terraform 支持是否完整？
   - 配置是否简单？
   - 监控和运维是否方便？

## 成功标准

验证完成后，我将能够回答以下问题，为 RFC 提供有力支持：

1. ✅ **功能验证**：Table Topic 功能确实如宣传的那样工作
2. ✅ **集成验证**：与 AWS Athena 和 Spark 的集成顺畅可用
3. ✅ **效果评估**：数据延迟、查询性能等指标符合预期
4. ✅ **易用性评估**：部署和配置流程简单直观
5. ✅ **价值确认**：确实能够简化现有架构，减少 ETL 复杂度

## 为 RFC 准备的输出

完成验证后，我将整理以下材料用于 RFC：

1. **验证报告**：详细记录验证过程、结果和发现的问题
2. **性能数据**：数据延迟、查询性能等关键指标
3. **架构对比**：使用 Table Topic 前后的架构对比
4. **风险评估**：潜在风险和应对方案
5. **推荐建议**：基于验证结果给出是否推进正式测试的建议

## 预期成果

如果验证结果积极，我将能够在 RFC 评审中：

- **提供第一手验证数据**：基于实际体验而非理论分析
- **提出更有针对性的问题**：基于实际操作中发现的问题
- **为方案提供有力支持**：如果确实优秀，不介意在评审时多发声支持
- **推动正式测试**：为获得审批和资源申请提供依据

如果验证结果不理想，我也能够：

- **提出具体问题**：指出哪些方面需要改进
- **给出客观评估**：帮助团队做出正确决策
- **避免资源浪费**：在正式测试前发现问题

## 参考资料

- [AutoMQ Table Topic 文档](https://www.automq.com/docs/automq-cloud/table-topic)
- [AWS Athena Iceberg 集成](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg.html)
- [Apache Iceberg](https://iceberg.apache.org/)
- [GH Archive](https://www.gharchive.org/)

