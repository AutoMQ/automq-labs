#!/bin/bash

# Debezium MySQL CDC 测试脚本
# 该脚本用于连接到 MySQL 数据库并执行测试 SQL

# 从 terraform 输出获取连接信息
DB_HOST=$(terraform output -raw database_endpoint)
DB_PORT=$(terraform output -raw database_port)
DB_USER=$(terraform output -raw database_username)
DB_PASSWORD=$(terraform output -raw database_password)
DB_NAME="testdb"

# 添加 MySQL 客户端到 PATH
export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"

# MySQL 连接命令 - 使用环境变量传递密码避免特殊字符问题
export MYSQL_PWD="$DB_PASSWORD"
MYSQL_CMD="mysql -h $DB_HOST -P $DB_PORT -u $DB_USER $DB_NAME"

echo "🔗 连接到 MySQL 数据库..."
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
        $MYSQL_CMD < "$sql_file"
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
    echo "$sql_command" | $MYSQL_CMD
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
    echo "🎯 Debezium MySQL CDC 测试菜单"
    echo "================================="
    echo "1. 初始化测试数据（创建表和初始数据）"
    echo "2. 运行 CDC 测试场景（INSERT/UPDATE/DELETE）"
    echo "3. 加载持续数据生成器"
    echo "4. 生成混合测试数据"
    echo "5. 生成用户活动数据"
    echo "6. 清理旧测试数据"
    echo "7. 查看数据统计"
    echo "8. 连接到数据库（交互模式）"
    echo "9. 检查 Debezium 相关配置"
    echo "10. 启动持续数据生成（后台运行）"
    echo "0. 退出"
    echo ""
    read -p "请选择操作 (0-10): " choice
}

# 检查 Debezium 配置
check_debezium_config() {
    echo "🔍 检查 Debezium 相关配置..."
    
    execute_sql_command "
    SHOW VARIABLES LIKE 'binlog_format';
    SHOW VARIABLES LIKE 'binlog_row_image';
    SHOW VARIABLES LIKE 'log_bin';
    SHOW VARIABLES LIKE 'server_id';
    SHOW VARIABLES LIKE 'gtid_mode';
    " "检查 MySQL Binlog 配置"
    
    execute_sql_command "
    SHOW MASTER STATUS;
    " "检查 Master 状态"
    
    execute_sql_command "
    SELECT table_schema, table_name, table_type 
    FROM information_schema.tables 
    WHERE table_schema = 'debezium_test'
    ORDER BY table_name;
    " "检查测试表"
}

# 查看数据统计
show_data_statistics() {
    echo "📊 查看数据统计..."
    
    execute_sql_command "
    USE debezium_test;
    SELECT 
        'Table Statistics' as info_type,
        '' as table_name,
        '' as record_count,
        '' as latest_record
    UNION ALL
    SELECT 
        '',
        'users' as table_name,
        COUNT(*) as record_count,
        COALESCE(MAX(updated_at), 'N/A') as latest_record
    FROM users
    UNION ALL
    SELECT 
        '',
        'orders' as table_name,
        COUNT(*) as record_count,
        COALESCE(MAX(updated_at), 'N/A') as latest_record
    FROM orders
    UNION ALL
    SELECT 
        '',
        'products' as table_name,
        COUNT(*) as record_count,
        COALESCE(MAX(updated_at), 'N/A') as latest_record
    FROM products
    UNION ALL
    SELECT 
        '',
        'order_items' as table_name,
        COUNT(*) as record_count,
        COALESCE(MAX(created_at), 'N/A') as latest_record
    FROM order_items
    UNION ALL
    SELECT 
        '',
        'user_activity_logs' as table_name,
        COUNT(*) as record_count,
        COALESCE(MAX(created_at), 'N/A') as latest_record
    FROM user_activity_logs;
    " "数据统计"
    
    execute_sql_command "
    USE debezium_test;
    SELECT 'Recent Activity (Last 10 minutes)' as activity_summary;
    SELECT 
        'New Users' as activity_type, 
        COUNT(*) as count 
    FROM users 
    WHERE created_at >= DATE_SUB(NOW(), INTERVAL 10 MINUTE)
    UNION ALL
    SELECT 
        'New Orders' as activity_type, 
        COUNT(*) as count 
    FROM orders 
    WHERE order_date >= DATE_SUB(NOW(), INTERVAL 10 MINUTE)
    UNION ALL
    SELECT 
        'New Activities' as activity_type, 
        COUNT(*) as count 
    FROM user_activity_logs 
    WHERE created_at >= DATE_SUB(NOW(), INTERVAL 10 MINUTE);
    " "最近活动统计"
}

# 生成混合测试数据
generate_mixed_data() {
    echo "请输入要生成的数据量："
    read -p "用户数量 (默认 5): " users
    read -p "产品数量 (默认 3): " products  
    read -p "订单数量 (默认 8): " orders
    read -p "活动数量 (默认 20): " activities
    read -p "更新用户数量 (默认 5): " updates
    
    users=${users:-5}
    products=${products:-3}
    orders=${orders:-8}
    activities=${activities:-20}
    updates=${updates:-5}
    
    execute_sql_command "
    USE debezium_test;
    CALL GenerateMixedTestData($users, $products, $orders, $activities, $updates);
    " "生成混合测试数据"
}

# 生成用户活动
generate_user_activity() {
    read -p "请输入要生成的活动数量 (默认 50): " activity_count
    activity_count=${activity_count:-50}
    
    execute_sql_command "
    USE debezium_test;
    CALL GenerateUserActivity($activity_count);
    " "生成用户活动数据"
}

# 清理数据
cleanup_data() {
    read -p "请输入要清理多少天前的数据 (默认 1): " days_old
    days_old=${days_old:-1}
    
    execute_sql_command "
    USE debezium_test;
    CALL CleanupOldTestData($days_old);
    " "清理旧数据"
}

# 启动持续数据生成
start_continuous_generation() {
    echo "🔄 启动持续数据生成..."
    read -p "请输入生成间隔秒数 (默认 30): " interval
    read -p "请输入运行时长分钟数 (默认 60): " duration_minutes
    
    interval=${interval:-30}
    duration_minutes=${duration_minutes:-60}
    
    echo "将每 $interval 秒生成一批数据，持续 $duration_minutes 分钟..."
    echo "按 Ctrl+C 停止生成"
    
    # 创建临时脚本 (修复 macOS date 命令)
    cat > /tmp/continuous_mysql_cdc.sh << EOF
#!/bin/bash
# 计算结束时间 (macOS 兼容)
if [[ "\$(uname)" == "Darwin" ]]; then
    # macOS 使用 -v 选项
    end_time=\$(date -v+${duration_minutes}M +%s)
else
    # Linux 使用 -d 选项
    end_time=\$(date -d "$duration_minutes minutes" +%s)
fi

current_time=\$(date +%s)
while [[ \$current_time -lt \$end_time ]]; do
    echo "\$(date): Generating batch data..."
    echo "USE debezium_test; CALL GenerateMixedTestData(2, 1, 3, 10, 2);" | $MYSQL_CMD
    if [[ \$? -eq 0 ]]; then
        echo "\$(date): Batch generated successfully"
    else
        echo "\$(date): Error generating batch data"
    fi
    sleep $interval
    current_time=\$(date +%s)
done
echo "Continuous generation completed after $duration_minutes minutes."
EOF
    
    chmod +x /tmp/continuous_mysql_cdc.sh
    
    # 在后台运行
    nohup /tmp/continuous_mysql_cdc.sh > /tmp/mysql_cdc_generation.log 2>&1 &
    echo "✅ 持续数据生成已启动 (PID: $!)"
    echo "📋 日志文件: /tmp/mysql_cdc_generation.log"
    echo "🛑 要停止生成，运行: pkill -f continuous_mysql_cdc.sh"
}

# 主循环
while true; do
    show_menu
    
    case $choice in
        1)
            execute_sql_file "mysql_test_data.sql" "初始化 MySQL 测试数据"
            ;;
        2)
            execute_sql_file "mysql_cdc_scenarios.sql" "MySQL CDC 测试场景"
            ;;
        3)
            execute_sql_file "mysql_continuous_generator.sql" "加载持续数据生成器"
            ;;
        4)
            generate_mixed_data
            ;;
        5)
            generate_user_activity
            ;;
        6)
            cleanup_data
            ;;
        7)
            show_data_statistics
            ;;
        8)
            echo "🔗 启动交互式 MySQL 连接..."
            echo "使用 'exit' 或 'quit' 退出 MySQL"
            $MYSQL_CMD
            ;;
        9)
            check_debezium_config
            ;;
        10)
            start_continuous_generation
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
