# Debezium PostgreSQL CDC 测试指南

该目录包含了用于测试 Debezium PostgreSQL CDC 功能的完整脚本和数据。

## 文件说明

- `debezium_test_data.sql` - 初始化测试数据（创建表、触发器、初始数据）
- `cdc_test_scenarios.sql` - CDC 测试场景（INSERT/UPDATE/DELETE 操作）
- `continuous_data_generator.sql` - 持续数据生成函数
- `run_cdc_tests.sh` - 自动化测试脚本（推荐使用）

## 使用方法

### 方法 1: 使用自动化脚本（推荐）

```bash
# 确保你在 terraform 目录下
cd terraform

# 运行自动化测试脚本
./run_cdc_tests.sh
```

脚本提供以下功能：
1. **初始化测试数据** - 创建 `debezium_test` schema 和相关表
2. **运行 CDC 测试场景** - 执行各种数据变更操作
3. **生成持续测试数据** - 批量生成测试数据
4. **清理旧测试数据** - 删除过期的测试数据
5. **查看数据状态** - 显示当前表的统计信息
6. **交互式连接** - 直接连接到数据库
7. **检查 Debezium 配置** - 验证数据库配置是否正确

### 方法 2: 手动执行 SQL 文件

```bash
# 获取连接信息
DB_HOST=$(terraform output -raw database_endpoint)
DB_PORT=$(terraform output -raw database_port)
DB_USER=$(terraform output -raw database_username)
DB_PASSWORD=$(terraform output -raw database_password)

# 设置密码环境变量
export PGPASSWORD="$DB_PASSWORD"

# 1. 初始化测试数据
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d testdb -f debezium_test_data.sql

# 2. 运行 CDC 测试场景
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d testdb -f cdc_test_scenarios.sql

# 3. 加载持续数据生成器
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d testdb -f continuous_data_generator.sql
```

## 测试数据结构

### 测试表结构

1. **users 表** - 用户信息
   - `id` (SERIAL PRIMARY KEY)
   - `username` (VARCHAR, UNIQUE)
   - `email` (VARCHAR)
   - `full_name` (VARCHAR)
   - `age` (INTEGER)
   - `status` (VARCHAR)
   - `created_at`, `updated_at` (TIMESTAMP)

2. **orders 表** - 订单信息
   - `id` (SERIAL PRIMARY KEY)
   - `user_id` (INTEGER, 外键)
   - `order_number` (VARCHAR, UNIQUE)
   - `total_amount` (DECIMAL)
   - `status` (VARCHAR)
   - `order_date`, `updated_at` (TIMESTAMP)

3. **products 表** - 产品信息
   - `id` (SERIAL PRIMARY KEY)
   - `name` (VARCHAR)
   - `description` (TEXT)
   - `price` (DECIMAL)
   - `category` (VARCHAR)
   - `stock_quantity` (INTEGER)
   - `is_active` (BOOLEAN)
   - `created_at` (TIMESTAMP)

### CDC 测试场景

脚本包含以下 CDC 测试场景：

1. **INSERT 操作**
   - 新用户注册
   - 创建订单
   - 添加产品

2. **UPDATE 操作**
   - 更新用户信息
   - 修改订单状态
   - 批量更新产品价格

3. **DELETE 操作**
   - 删除订单
   - 删除用户

4. **事务操作**
   - 复杂的多表事务操作

## 持续数据生成

使用 `generate_continuous_data()` 函数可以持续生成测试数据：

```sql
-- 生成 20 条记录的批次
SELECT debezium_test.generate_continuous_data(20);

-- 清理 1 天前的测试数据
SELECT debezium_test.cleanup_old_data(1);
```

## 观察 CDC 事件

在运行测试脚本的同时，你可以通过以下方式观察 CDC 事件：

1. **Kafka 主题监控** - 如果使用 Kafka Connect，查看相关主题
2. **Debezium 连接器日志** - 检查连接器的日志输出
3. **复制槽监控** - 查看 PostgreSQL 复制槽状态

```sql
-- 查看复制槽状态
SELECT slot_name, plugin, slot_type, database, active, 
       restart_lsn, confirmed_flush_lsn 
FROM pg_replication_slots;

-- 查看 WAL 相关统计
SELECT * FROM pg_stat_replication;
```

## 故障排除

### 常见问题

1. **连接失败**
   ```bash
   # 检查数据库是否可访问
   nc -zv $DB_HOST $DB_PORT
   ```

2. **权限错误**
   ```sql
   -- 检查用户权限
   SELECT rolname, rolsuper, rolreplication, rolcreaterole 
   FROM pg_roles WHERE rolname = 'dbadmin';
   ```

3. **Debezium 配置检查**
   ```sql
   -- 检查关键配置参数
   SELECT name, setting FROM pg_settings 
   WHERE name IN ('wal_level', 'max_replication_slots', 'max_wal_senders');
   ```

### 清理环境

如果需要完全清理测试环境：

```sql
-- 删除测试 schema 和所有数据
DROP SCHEMA IF EXISTS debezium_test CASCADE;
```

## 性能考虑

- 持续数据生成器会产生大量数据，建议在测试环境中使用
- 定期运行清理函数以避免数据库空间不足
- 监控 WAL 日志大小，确保不会影响数据库性能
