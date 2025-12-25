#!/bin/bash

# MySQL CDC 持续数据生成脚本 (macOS 优化版)
# 该脚本持续生成测试数据来观察 CDC 事件

# 从 terraform 输出获取连接信息
DB_HOST=$(terraform output -raw database_endpoint)
DB_PORT=$(terraform output -raw database_port)
DB_USER=$(terraform output -raw database_username)
DB_PASSWORD=$(terraform output -raw database_password)
DB_NAME="testdb"

# 添加 MySQL 客户端到 PATH
export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"
export MYSQL_PWD="$DB_PASSWORD"
MYSQL_CMD="mysql -h $DB_HOST -P $DB_PORT -u $DB_USER $DB_NAME"

# 默认参数
DEFAULT_INTERVAL=30
DEFAULT_DURATION=60
DEFAULT_BATCH_SIZE=5

# 显示使用方法
show_usage() {
    echo "📊 MySQL CDC 持续数据生成器"
    echo "==============================="
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -i, --interval <秒>     生成间隔 (默认: $DEFAULT_INTERVAL 秒)"
    echo "  -d, --duration <分钟>   运行时长 (默认: $DEFAULT_DURATION 分钟)"
    echo "  -b, --batch-size <数量> 每批数据量 (默认: $DEFAULT_BATCH_SIZE)"
    echo "  -c, --continuous        持续运行 (忽略时长限制)"
    echo "  -h, --help             显示帮助"
    echo ""
    echo "示例:"
    echo "  $0 -i 20 -d 30 -b 10    # 每20秒生成10条数据，运行30分钟"
    echo "  $0 -c -i 10             # 持续运行，每10秒生成数据"
    echo "  $0                      # 使用默认参数运行"
}

# 解析命令行参数
parse_args() {
    interval=$DEFAULT_INTERVAL
    duration=$DEFAULT_DURATION
    batch_size=$DEFAULT_BATCH_SIZE
    continuous=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--interval)
                interval="$2"
                shift 2
                ;;
            -d|--duration)
                duration="$2"
                shift 2
                ;;
            -b|--batch-size)
                batch_size="$2"
                shift 2
                ;;
            -c|--continuous)
                continuous=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "❌ 未知参数: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# 测试数据库连接
test_connection() {
    echo "🔗 测试数据库连接..."
    if echo "SELECT 1;" | $MYSQL_CMD > /dev/null 2>&1; then
        echo "✅ 数据库连接成功"
    else
        echo "❌ 数据库连接失败，请检查配置"
        exit 1
    fi
}

# 确保存储过程存在
ensure_procedures() {
    echo "🔧 检查存储过程..."
    procedure_check=$(echo "
    SELECT COUNT(*) 
    FROM information_schema.routines 
    WHERE routine_schema = 'debezium_test' 
      AND routine_name = 'GenerateMixedTestData';
    " | $MYSQL_CMD -N)
    
    if [[ "$procedure_check" -eq 0 ]]; then
        echo "⚠️  存储过程不存在，请先运行初始化脚本"
        echo "   执行: ./run_mysql_cdc_tests.sh"
        echo "   选择选项 3: 加载持续数据生成器"
        exit 1
    else
        echo "✅ 存储过程已准备就绪"
    fi
}

# 生成一批数据
generate_batch() {
    local batch_num=$1
    echo "📝 [$(date '+%Y-%m-%d %H:%M:%S')] 生成第 $batch_num 批数据..."
    
    sql="USE debezium_test; CALL GenerateMixedTestData($batch_size, $((batch_size/2)), $((batch_size*2)), $((batch_size*5)), $((batch_size/2)));"
    
    if echo "$sql" | $MYSQL_CMD > /dev/null 2>&1; then
        echo "✅ [$(date '+%Y-%m-%d %H:%M:%S')] 第 $batch_num 批数据生成成功"
    else
        echo "❌ [$(date '+%Y-%m-%d %H:%M:%S')] 第 $batch_num 批数据生成失败"
    fi
}

# 显示统计信息
show_stats() {
    echo "📊 [$(date '+%Y-%m-%d %H:%M:%S')] 当前数据统计:"
    echo "
    SELECT 
        'users' as table_name, COUNT(*) as count
    FROM debezium_test.users
    UNION ALL
    SELECT 
        'orders' as table_name, COUNT(*) as count  
    FROM debezium_test.orders
    UNION ALL
    SELECT 
        'products' as table_name, COUNT(*) as count
    FROM debezium_test.products
    UNION ALL
    SELECT 
        'activities' as table_name, COUNT(*) as count
    FROM debezium_test.user_activity_logs;
    " | $MYSQL_CMD
}

# 信号处理函数
cleanup() {
    echo ""
    echo "🛑 [$(date '+%Y-%m-%d %H:%M:%S')] 收到停止信号，正在清理..."
    show_stats
    echo "👋 [$(date '+%Y-%m-%d %H:%M:%S')] 数据生成已停止"
    exit 0
}

# 主函数
main() {
    # 解析参数
    parse_args "$@"
    
    # 显示配置
    echo "🚀 MySQL CDC 持续数据生成器启动"
    echo "=================================="
    echo "数据库: $DB_HOST:$DB_PORT"
    echo "生成间隔: $interval 秒"
    echo "每批数据量: $batch_size"
    if [[ "$continuous" == "true" ]]; then
        echo "运行模式: 持续运行"
    else
        echo "运行时长: $duration 分钟"
    fi
    echo ""
    
    # 测试连接
    test_connection
    
    # 检查存储过程
    ensure_procedures
    
    # 设置信号处理
    trap cleanup SIGINT SIGTERM
    
    # 计算结束时间
    if [[ "$continuous" == "false" ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS
            end_time=$(date -v+${duration}M +%s)
        else
            # Linux
            end_time=$(date -d "$duration minutes" +%s)
        fi
    fi
    
    # 开始生成数据
    echo "🎯 [$(date '+%Y-%m-%d %H:%M:%S')] 开始生成数据..."
    echo "   按 Ctrl+C 停止生成"
    echo ""
    
    batch_num=1
    
    while true; do
        current_time=$(date +%s)
        
        # 检查是否超时
        if [[ "$continuous" == "false" && $current_time -gt $end_time ]]; then
            echo "⏰ [$(date '+%Y-%m-%d %H:%M:%S')] 运行时间到达，停止生成"
            break
        fi
        
        # 生成数据
        generate_batch $batch_num
        
        # 每10批显示一次统计
        if [[ $((batch_num % 10)) -eq 0 ]]; then
            show_stats
        fi
        
        # 等待下次生成
        sleep $interval
        batch_num=$((batch_num + 1))
    done
    
    # 显示最终统计
    echo ""
    echo "📈 [$(date '+%Y-%m-%d %H:%M:%S')] 最终数据统计:"
    show_stats
    echo "🎉 [$(date '+%Y-%m-%d %H:%M:%S')] 数据生成完成，共生成 $((batch_num-1)) 批数据"
}

# 运行主函数
main "$@"
