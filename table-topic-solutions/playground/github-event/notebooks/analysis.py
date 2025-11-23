import marimo

__generated_with = "0.18.0"
app = marimo.App(width="medium", app_title="GitHub Real-Time Analytics")


@app.cell(hide_code=True)
def _():
    # Import required libraries
    import marimo as mo
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
    
    # 状态管理
    get_events, set_events = mo.state(value=[])
    get_last_update, set_last_update = mo.state(value="Never")
    
    return (get_events, set_events, get_last_update, set_last_update, time)


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

@app.cell
def _(mo):
    # 创建自动刷新组件，每30秒刷新一次
    dataRefresh = mo.ui.refresh(options=["30s"], default_interval="30s")
    return (dataRefresh,)


@app.cell(hide_code=True)
def _(dataRefresh, get_events, set_events, get_last_update, set_last_update, spark, time):
    # 使用 mo.ui.refresh 触发数据刷新
    # 关键：直接使用 dataRefresh.value，让 marimo 检测到变化并触发 cell 重新执行
    # 在 SQL 查询的注释中使用，确保当值变化时 SQL 字符串变化，从而触发重新执行
    _refresh_value = dataRefresh.value
    
    try:
        # 在 SQL 查询的注释中使用 _refresh_value，确保响应式更新
        _df = spark.sql(f"""
            -- Refresh trigger: {_refresh_value}
            SELECT * FROM default.github_events_iceberg ORDER BY RAND() LIMIT 20
        """)
        _pandas_df = _df.toPandas()
        
        # Update state
        set_events(_pandas_df)
        
        # Update last refresh time
        current_time = time.strftime("%H:%M:%S")
        set_last_update(current_time)
        
        print(f"🔄 [Auto-refresh] Data updated at {current_time} - Found {len(_pandas_df)} records (refresh value: {_refresh_value})")
        
    except Exception as e:
        print(f"❌ [Auto-refresh] Error refreshing data: {e}")
    
    # 返回 _refresh_value 确保 marimo 检测到变化
    return _refresh_value


@app.cell
def _(dataRefresh, mo, get_last_update):
    # 注意：刷新组件需要被渲染才能工作，所以先渲染再隐藏
    # 或者不隐藏，让用户看到刷新状态
    dataRefresh.style({"display": None})
    
    mo.vstack([
        mo.md("## 📊 Live GitHub Events Data"),
        mo.md(f"*Last updated: {get_last_update()} • Auto-refresh every 30 seconds*"),
        dataRefresh  # 确保刷新组件被渲染（即使被隐藏）
    ])


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
