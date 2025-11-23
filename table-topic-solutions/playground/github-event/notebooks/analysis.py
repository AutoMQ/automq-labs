import marimo

__generated_with = "0.18.0"
app = marimo.App(width="medium", app_title="GitHub Real-Time Analytics")


@app.cell(hide_code=True)
def _():
    # Import required libraries
    import marimo as mo
    import os

    # 简化包配置，使用 tabulario/spark-iceberg 镜像预装的包
    # 不需要额外下载包，直接使用镜像中已有的配置
    print("✓ Using pre-configured Spark packages from tabulario/spark-iceberg image")

    # Now import pyspark after setting environment variable
    try:
        print("Importing PySpark...")
        from pyspark.sql import SparkSession
        print("✓ PySpark imported successfully")

        # Initialize SparkSession using pre-configured environment
        print("Initializing SparkSession using pre-configured environment...")
        spark = SparkSession.builder \
            .appName("GitHub Events Analytics") \
            .getOrCreate()
        print("✓ SparkSession created successfully")
        print(f"✓ Spark version: {spark.version}")
        # Uncomment the line below to test query on startup
    except Exception as e:
        error_msg = f"""❌ Error initializing SparkSession:{str(e)}"""
        print(error_msg)
        raise RuntimeError(error_msg) from e

    return mo, spark, SparkSession


@app.cell(hide_code=True)
def _(mo):
    import time
    import threading
    import schedule
    
    # 状态管理
    get_events, set_events = mo.state(value=[])
    get_spark_session, set_spark_session = mo.state(value=None)
    get_restart_count, set_restart_count = mo.state(value=0)
    get_scheduler_started, set_scheduler_started = mo.state(value=False)
    get_last_update, set_last_update = mo.state(value="Never")
    
    return (get_events, set_events, get_spark_session, set_spark_session, 
            get_restart_count, set_restart_count, get_scheduler_started, 
            set_scheduler_started, get_last_update, set_last_update, time, threading, schedule)


@app.cell
def _(mo):
    mo.md(r"""
    # 🚀 GitHub Events Real-Time Analytics
    This demo showcases **[AutoMQ](https://github.com/AutoMQ/automq) Table Topic** - automatically converting Kafka topics into Apache Iceberg tables for real-time analytics.

    **Data Source**: [GH Archive](https://www.gharchive.org/) - Public GitHub timeline events  
    **Technology**: AutoMQ Table Topic (Zero ETL, Real-time Ingestion)
    ---
    """)
    return


@app.cell(hide_code=True)
def _(get_spark_session, set_spark_session, get_restart_count, set_restart_count, 
      get_scheduler_started, set_scheduler_started, get_events, set_events, get_last_update, 
      set_last_update, threading, schedule, time, SparkSession, spark):
    
    def refresh_data():
        print('refresh event data')
        """刷新数据的函数"""
        try:
            # 使用当前可用的 Spark 会话
            current_spark = get_spark_session() if get_spark_session() is not None else spark
            
            # Query the latest data
            df = current_spark.sql("SELECT * FROM default.github_events_iceberg ORDER BY created_at DESC LIMIT 20")
            pandas_df = df.toPandas()
            
            # Update state
            set_events(pandas_df)
            
            # Update last refresh time
            current_time = time.strftime("%H:%M:%S")
            set_last_update(current_time)
            
            print(f"🔄 [Auto-refresh] Data updated at {current_time} - Found {len(pandas_df)} records")
            
        except Exception as e:
            print(f"❌ [Auto-refresh] Error refreshing data: {e}")
    
    def restart_spark():
        """重启 Spark 会话的函数"""
        print(f"🔄 [Background] Auto-restarting Spark (restart #{get_restart_count() + 1})...")
        try:
            # 停止当前 Spark 会话
            current_spark = get_spark_session()
            
            # 等待一下
            time.sleep(3)
            
            # 创建新的 Spark 会话
            new_spark = SparkSession.builder \
                .appName(f"GitHub Events Analytics - Auto Restart {get_restart_count() + 1}") \
                .getOrCreate()

            if current_spark is not None:
                current_spark.stop()
                print("✓ [Background] Previous Spark session stopped")
            
            # 更新状态
            set_restart_count(get_restart_count() + 1)
            set_spark_session(new_spark)
            
            print(f"✓ [Background] New Spark session created")
            print(f"✓ [Background] Spark version: {new_spark.version}")
            
        except Exception as e:
            print(f"❌ [Background] Error restarting Spark: {e}")
    
    def run_scheduler():
        """运行调度器的后台线程函数"""
        while True:
            schedule.run_pending()
            time.sleep(1)
    
    # 启动后台调度器（只启动一次）
    if not get_scheduler_started():
        print("🚀 Starting background schedulers...")
        
        # 设置每10秒刷新数据
        schedule.every(10).seconds.do(refresh_data)
        
        # 设置每10分钟重启Spark
        schedule.every(30).minutes.do(restart_spark)
        
        # 启动后台线程
        scheduler_thread = threading.Thread(target=run_scheduler, daemon=True)
        scheduler_thread.start()
        
        # 标记调度器已启动
        set_scheduler_started(True)
        
        print("✓ Background schedulers started:")
        print("  • Data refresh: every 10 seconds")
        print("  • Spark restart: every 10 minutes")
        
        # 立即执行一次数据刷新
        refresh_data()
    else:
        print("✓ Background schedulers already running")


@app.cell
def _(mo, get_last_update):
    mo.vstack([
        mo.md("## 📊 Live GitHub Events Data"),
        mo.md(f"*Last updated: {get_last_update()} • Auto-refresh every 10 seconds*")
    ])


@app.cell(hide_code=True)
def _(get_events, set_events, spark, get_spark_session, set_last_update, time):
    # 初始数据加载（只在首次启动时执行）
    if len(get_events()) == 0:
        print("🔍 Initial data loading...")
        try:
            # 使用当前可用的 Spark 会话
            current_spark = get_spark_session() if get_spark_session() is not None else spark
            
            # Query the data
            df = current_spark.sql("SELECT * FROM default.github_events_iceberg ORDER BY created_at DESC LIMIT 20")
            pandas_df = df.toPandas()
            
            # Store the data in state
            set_events(pandas_df)
            set_last_update(time.strftime("%H:%M:%S"))
            
            print(f"✓ Initial data loaded - Found {len(pandas_df)} records")
            
        except Exception as e:
            print(f"❌ Error loading initial data: {e}")
            print("💡 Background scheduler will handle data refresh automatically")
            set_events([])
    else:
        print("✓ Data already loaded, background refresh is active")


@app.cell
def _(get_events, mo):
    events_data = get_events()
    # Select only specific columns to display (modify this list as needed)
    display_columns = ['id', 'type', 'actor_login', 'repo_name', 'created_at']


    # Filter the DataFrame to show only selected columns
    if len(events_data) > 0:
        # Check which columns actually exist in the data
        available_columns = [col for col in display_columns if col in events_data.columns]
        filtered_data = events_data[available_columns]
    
        print(f"✓ Displaying {len(available_columns)} columns: {', '.join(available_columns)}")
    else:
        filtered_data = events_data

    # Create interactive table with filtered data
    table = mo.ui.table(
        filtered_data,
        selection=None,
        show_column_summaries=False
    )

    # Return the vstack as the final expression to display
    mo.vstack([
        mo.md("### Recent GitHub Events"),
        table
    ])
    return


if __name__ == "__main__":
    app.run()
