# Debezium MySQL Connector 配置指南

## 数据库连接信息

根据当前部署的 MySQL RDS 实例，以下是连接信息：

- **主机**: `debezium-mysql-34d72e84.c2bcmays6km5.us-east-1.rds.amazonaws.com`
- **端口**: `3306`
- **用户名**: `admin`
- **密码**: `*-9&g?*56JmcO|h-wT#F%`
- **数据库**: `testdb`

## Debezium MySQL Connector 配置

### 基本连接器配置 (JSON)

```json
{
    "name": "debezium-mysql-connector",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "database.hostname": "debezium-mysql-34d72e84.c2bcmays6km5.us-east-1.rds.amazonaws.com",
        "database.port": "3306",
        "database.user": "admin",
        "database.password": "*-9&g?*56JmcO|h-wT#F%",
        "database.server.id": "184054",
        "database.server.name": "debezium-mysql-server",
        "database.include.list": "debezium_test",
        "table.include.list": "debezium_test.users,debezium_test.orders,debezium_test.products,debezium_test.order_items,debezium_test.user_activity_logs",
        "database.history.kafka.bootstrap.servers": "localhost:9092",
        "database.history.kafka.topic": "debezium.mysql.history",
        "include.schema.changes": "true",
        "transforms": "route",
        "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
        "transforms.route.regex": "([^.]+)\\.([^.]+)\\.([^.]+)",
        "transforms.route.replacement": "$3"
    }
}
```

### 高级配置选项

```json
{
    "name": "debezium-mysql-connector-advanced",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "database.hostname": "debezium-mysql-34d72e84.c2bcmays6km5.us-east-1.rds.amazonaws.com",
        "database.port": "3306",
        "database.user": "admin",
        "database.password": "*-9&g?*56JmcO|h-wT#F%",
        "database.server.id": "184054",
        "database.server.name": "debezium-mysql-server",
        
        // 数据库和表配置
        "database.include.list": "debezium_test",
        "table.include.list": "debezium_test.users,debezium_test.orders,debezium_test.products,debezium_test.order_items,debezium_test.user_activity_logs",
        
        // 历史记录配置
        "database.history.kafka.bootstrap.servers": "localhost:9092",
        "database.history.kafka.topic": "debezium.mysql.history",
        
        // 快照配置
        "snapshot.mode": "initial",
        "snapshot.locking.mode": "minimal",
        "snapshot.new.tables": "parallel",
        
        // Binlog 配置
        "binlog.buffer.size": "32768",
        "max.batch.size": "2048",
        "max.queue.size": "8192",
        
        // 容错配置
        "errors.tolerance": "none",
        "errors.log.enable": "true",
        "errors.log.include.messages": "true",
        
        // 数据转换
        "include.schema.changes": "true",
        "include.query": "false",
        "tombstones.on.delete": "true",
        
        // 消息路由
        "transforms": "route",
        "transforms.route.type": "org.apache.kafka.connect.transforms.RegexRouter",
        "transforms.route.regex": "([^.]+)\\.([^.]+)\\.([^.]+)",
        "transforms.route.replacement": "$3",
        
        // 性能优化
        "heartbeat.interval.ms": "10000",
        "heartbeat.topics.prefix": "debezium-heartbeat",
        
        // 消息格式
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",
        "key.converter.schemas.enable": "false",
        "value.converter.schemas.enable": "false"
    }
}
```

## 关键配置参数说明

### 必需参数

| 参数 | 值 | 说明 |
|------|----|----- |
| `connector.class` | `io.debezium.connector.mysql.MySqlConnector` | MySQL 连接器类 |
| `database.hostname` | RDS 端点 | MySQL 服务器地址 |
| `database.port` | `3306` | MySQL 端口 |
| `database.user` | `admin` | 数据库用户名 |
| `database.password` | 数据库密码 | 数据库密码 |
| `database.server.id` | `184054` | 唯一的服务器 ID |
| `database.server.name` | 逻辑服务器名 | Kafka 主题前缀 |

### 数据库配置

| 参数 | 建议值 | 说明 |
|------|--------|------|
| `database.include.list` | `debezium_test` | 要监控的数据库 |
| `table.include.list` | 具体表名列表 | 要监控的表 |
| `column.exclude.list` | 敏感列名 | 要排除的列 |

### 快照配置

| 参数 | 选项 | 说明 |
|------|------|------|
| `snapshot.mode` | `initial`/`when_needed`/`never` | 快照模式 |
| `snapshot.locking.mode` | `minimal`/`extended` | 快照锁定模式 |
| `snapshot.new.tables` | `parallel`/`off` | 新表快照方式 |

### 性能配置

| 参数 | 建议值 | 说明 |
|------|--------|------|
| `max.batch.size` | `2048` | 最大批处理大小 |
| `max.queue.size` | `8192` | 最大队列大小 |
| `heartbeat.interval.ms` | `10000` | 心跳间隔 |

## 使用 Kafka Connect REST API 部署

### 1. 创建连接器

```bash
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @mysql-connector-config.json
```

### 2. 检查连接器状态

```bash
curl http://localhost:8083/connectors/debezium-mysql-connector/status
```

### 3. 暂停连接器

```bash
curl -X PUT http://localhost:8083/connectors/debezium-mysql-connector/pause
```

### 4. 恢复连接器

```bash
curl -X PUT http://localhost:8083/connectors/debezium-mysql-connector/resume
```

### 5. 删除连接器

```bash
curl -X DELETE http://localhost:8083/connectors/debezium-mysql-connector
```

## Kafka 主题结构

连接器会为每个表创建相应的 Kafka 主题：

- `users` - 用户表变更事件
- `orders` - 订单表变更事件  
- `products` - 产品表变更事件
- `order_items` - 订单项变更事件
- `user_activity_logs` - 用户活动日志变更事件

## 监控和调试

### 查看连接器日志

```bash
# 如果使用 Docker
docker logs kafka-connect

# 如果使用独立进程
tail -f logs/connect.log
```

### 监控 Kafka 主题

```bash
# 列出主题
kafka-topics.sh --bootstrap-server localhost:9092 --list

# 消费某个主题的消息
kafka-console-consumer.sh --bootstrap-server localhost:9092 \
  --topic users --from-beginning --property print.key=true
```

### 检查 MySQL Binlog

```sql
-- 检查 binlog 状态
SHOW MASTER STATUS;

-- 查看 binlog 事件
SHOW BINLOG EVENTS IN 'mysql-bin-changelog.000001';

-- 检查 binlog 格式
SHOW VARIABLES LIKE 'binlog_format';
```

## 故障排除

### 常见问题

1. **连接器无法启动**
   - 检查数据库连接参数
   - 验证用户权限
   - 确认 binlog 已启用

2. **缺少变更事件**
   - 检查表是否在 include.list 中
   - 验证 binlog 格式为 ROW
   - 确认操作在监控的数据库中

3. **性能问题**
   - 调整 `max.batch.size`
   - 增加 `max.queue.size`
   - 优化 `heartbeat.interval.ms`

### 数据库权限要求

确保数据库用户具有以下权限：

```sql
-- 创建专用 Debezium 用户 (可选)
CREATE USER 'debezium'@'%' IDENTIFIED BY 'debezium_password';

-- 授予必要权限
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'debezium'@'%';
GRANT ALL PRIVILEGES ON debezium_test.* TO 'debezium'@'%';

FLUSH PRIVILEGES;
```

## 测试验证

使用提供的测试脚本验证 CDC 功能：

```bash
# 运行 MySQL CDC 测试
./run_mysql_cdc_tests.sh

# 1. 初始化测试数据
# 2. 运行 CDC 测试场景  
# 3. 生成持续测试数据
# 10. 启动持续数据生成（后台运行）
```

观察 Kafka 主题中的变更事件，验证 CDC 功能正常工作。
