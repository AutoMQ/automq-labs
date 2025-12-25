#!/bin/bash

# Debezium PostgreSQL CDC 测试脚本
# 该脚本用于连接到 PostgreSQL 数据库并执行测试 SQL

# 设置 PostgreSQL 客户端工具路径
export PATH="/opt/homebrew/Cellar/postgresql@15/15.14/bin:$PATH"

# 检查 psql 是否可用
if ! command -v psql &> /dev/null; then
    echo "❌ psql 命令未找到。请确保已安装 PostgreSQL 客户端工具。"
    echo "在 macOS 上可以使用：brew install postgresql@15"
    exit 1
fi

# 从 terraform 输出获取连接信息
DB_HOST=$(terraform output -raw database_endpoint)
DB_PORT=$(terraform output -raw database_port)
DB_USER=$(terraform output -raw database_username)
DB_PASSWORD=$(terraform output -raw database_password)
DB_NAME="testdb"

# 构建连接字符串
export PGPASSWORD="$DB_PASSWORD"
PSQL_CMD="psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME"

echo "🔗 连接到 PostgreSQL 数据库..."
echo "主机: $DB_HOST"
echo "端口: $DB_PORT"
echo "用户: $DB_USER"
echo "数据库: $DB_NAME"
echo ""

# 函数：执行 SQL 文件
execute_sql_file() {
    local sql_file=$1
    local description=$2
    
    echo "📝 执行 $description..."
    if [[ -f "$sql_file" ]]; then
        $PSQL_CMD -f "$sql_file"
        if [[ $? -eq 0 ]]; then
            echo "✅ $description 执行成功"
        else
            echo "❌ $description 执行失败"
            return 1
        fi
    else
        echo "❌ 文件 $sql_file 不存在"
        return 1
    fi
    echo ""
}

# 函数：执行单个 SQL 命令
execute_sql_command() {
    local sql_command=$1
    local description=$2
    
    echo "🔄 执行 $description..."
    echo "$sql_command" | $PSQL_CMD
    if [[ $? -eq 0 ]]; then
        echo "✅ $description 执行成功"
    else
        echo "❌ $description 执行失败"
        return 1
    fi
    echo ""
}

# 主菜单
show_menu() {
    echo "🎯 Debezium PostgreSQL CDC 测试菜单"
    echo "=================================="
    echo "1. 初始化测试数据（创建表和初始数据）"
    echo "2. 运行 CDC 测试场景（INSERT/UPDATE/DELETE）"
    echo "3. 生成持续测试数据（批量数据生成）"
    echo "4. 清理旧测试数据"
    echo "5. 查看当前数据状态"
    echo "6. 连接到数据库（交互模式）"
    echo "7. 检查 Debezium 相关配置"
    echo "0. 退出"
    echo ""
    read -p "请选择操作 (0-7): " choice
}

# 检查 Debezium 配置
check_debezium_config() {
    echo "🔍 检查 Debezium 相关配置..."
    
    execute_sql_command "
    SELECT name, setting, unit, context 
    FROM pg_settings 
    WHERE name IN (
        'wal_level', 
        'max_replication_slots', 
        'max_wal_senders', 
        'shared_preload_libraries'
    ) 
    ORDER BY name;" "检查 WAL 和复制相关配置"
    
    execute_sql_command "
    SELECT slot_name, plugin, slot_type, database, active 
    FROM pg_replication_slots;" "检查复制槽状态"
    
    execute_sql_command "
    SELECT schemaname, tablename, hasindexes, hasrules, hastriggers 
    FROM pg_tables 
    WHERE schemaname = 'debezium_test';" "检查测试表状态"
}

# 查看数据状态
show_data_status() {
    echo "📊 查看当前数据状态..."
    
    execute_sql_command "
    SELECT 
        'users' as table_name, 
        COUNT(*) as record_count,
        MIN(created_at) as earliest_record,
        MAX(updated_at) as latest_update
    FROM debezium_test.users
    UNION ALL
    SELECT 
        'orders' as table_name, 
        COUNT(*) as record_count,
        MIN(order_date) as earliest_record,
        MAX(updated_at) as latest_update
    FROM debezium_test.orders
    UNION ALL
    SELECT 
        'products' as table_name, 
        COUNT(*) as record_count,
        MIN(created_at) as earliest_record,
        MAX(created_at) as latest_update
    FROM debezium_test.products;" "数据统计"
}

# 生成测试数据
generate_test_data() {
    read -p "请输入要生成的批次大小 (默认 10): " batch_size
    batch_size=${batch_size:-10}
    
    execute_sql_command "SELECT debezium_test.generate_continuous_data($batch_size);" "生成测试数据"
}

# 清理数据
cleanup_data() {
    read -p "请输入要清理多少天前的数据 (默认 1): " days_old
    days_old=${days_old:-1}
    
    execute_sql_command "SELECT debezium_test.cleanup_old_data($days_old);" "清理旧数据"
}

# 主循环
while true; do
    show_menu
    
    case $choice in
        1)
            execute_sql_file "debezium_test_data.sql" "初始化测试数据"
            ;;
        2)
            execute_sql_file "cdc_test_scenarios.sql" "CDC 测试场景"
            ;;
        3)
            execute_sql_file "continuous_data_generator.sql" "加载数据生成函数"
            if [[ $? -eq 0 ]]; then
                generate_test_data
            fi
            ;;
        4)
            cleanup_data
            ;;
        5)
            show_data_status
            ;;
        6)
            echo "🔗 启动交互式连接..."
            echo "使用 \\q 退出 psql"
            $PSQL_CMD
            ;;
        7)
            check_debezium_config
            ;;
        0)
            echo "👋 退出测试脚本"
            break
            ;;
        *)
            echo "❌ 无效选择，请重新输入"
            ;;
    esac
    
    echo ""
    read -p "按 Enter 键继续..."
    clear
done
