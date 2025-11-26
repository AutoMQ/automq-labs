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
    
    # State management
    get_events, set_events = mo.state(value=[])
    get_last_update, set_last_update = mo.state(value="Never")
    get_star_count, set_star_count = mo.state(value=0)
    get_total_events, set_total_events = mo.state(value=0)
    
    return (get_events, set_events, get_last_update, set_last_update, get_star_count, set_star_count, get_total_events, set_total_events, time)


@app.cell
def _(mo):
    mo.md(r"""
    # 🚀 GitHub Events Real-Time Analytics
    
    This project demonstrates how to leverage **[AutoMQ Table Topic](https://github.com/AutoMQ/automq)** to transform streaming GitHub events into Apache Iceberg format for real-time analytics.
    
    This solution ingests **GitHub Events** from [GH Archive](https://www.gharchive.org/) into AutoMQ, where the **Table Topic** feature automatically converts the streaming data into Apache Iceberg tables. Spark can then query these tables directly, enabling real-time analysis of open-source community activities without the traditional ETL complexity.
    
    **Data Source**: [GH Archive](https://www.gharchive.org/) - Public GitHub timeline events  
    ---
    """)
    return

@app.cell
def _(mo):
    # Create auto-refresh component, refresh every 60 seconds (1 minute)
    dataRefresh = mo.ui.refresh(options=["60s"], default_interval="60s")
    return (dataRefresh,)


@app.cell(hide_code=True)
def _(dataRefresh, get_events, set_events, get_last_update, set_last_update, get_star_count, set_star_count, get_total_events, set_total_events, spark, time):
    # Use mo.ui.refresh to trigger data refresh
    # Key: directly use dataRefresh.value to let marimo detect changes and trigger cell re-execution
    # Use in SQL query comments to ensure SQL string changes when value changes, triggering re-execution
    _refresh_value = dataRefresh.value
    
    try:
        # 1. Get star count (WatchEvent) for last 3 days
        star_df = spark.sql(f"""
            -- Refresh trigger: {_refresh_value}
            SELECT COUNT(*) as star_count
            FROM default.github_events_iceberg
            WHERE type = 'WatchEvent'
            AND created_at >= DATE_SUB(CURRENT_DATE(), 3)
        """)
        star_count = star_df.collect()[0]['star_count']
        set_star_count(star_count)
        
        # 2. Get total event count for last 3 days
        total_df = spark.sql(f"""
            -- Refresh trigger: {_refresh_value}
            SELECT COUNT(*) as total_count
            FROM default.github_events_iceberg
            WHERE created_at >= DATE_SUB(CURRENT_DATE(), 3)
        """)
        total_count = total_df.collect()[0]['total_count']
        set_total_events(total_count)
        
        # 3. Get recent event list
        _df = spark.sql(f"""
            -- Refresh trigger: {_refresh_value}
            SELECT * FROM default.github_events_iceberg ORDER BY created_at DESC LIMIT 20
        """)
        _pandas_df = _df.toPandas()
        
        # Update state
        set_events(_pandas_df)
        
        # Update last refresh time
        current_time = time.strftime("%H:%M:%S")
        set_last_update(current_time)
        
        print(f"🔄 [Auto-refresh] Data updated at {current_time} - Stars: {star_count}, Total Events: {total_count}, Recent Events: {len(_pandas_df)}")
        
    except Exception as e:
        print(f"❌ [Auto-refresh] Error refreshing data: {e}")
    
    # Return _refresh_value to ensure marimo detects changes
    return _refresh_value


@app.cell(hide_code=True)
def _(spark):
    # Get top 10 repositories by star count for last 3 days (no auto-refresh)
    try:
        top_repos_df = spark.sql("""
            SELECT 
                repo_name,
                COUNT(*) as star_count
            FROM default.github_events_iceberg
            WHERE type = 'WatchEvent'
            AND created_at >= DATE_SUB(CURRENT_DATE(), 3)
            GROUP BY repo_name
            ORDER BY star_count DESC
            LIMIT 10
        """)
        top_repos_pandas = top_repos_df.toPandas()
        if top_repos_pandas is not None and len(top_repos_pandas) > 0:
            print(f"✓ Loaded top {len(top_repos_pandas)} repositories")
        else:
            print("⚠️ No repository data found")
    except Exception as e:
        print(f"❌ Error fetching top repos: {e}")
        import traceback
        traceback.print_exc()
        top_repos_pandas = None
    
    return top_repos_pandas


@app.cell
def _(dataRefresh, mo, get_last_update, get_star_count, get_total_events):
    # Note: refresh component needs to be rendered to work, so render first then hide
    # Or don't hide it, let users see the refresh status
    dataRefresh.style({"display": None})
    
    # First row: show star count on left, total events on right
    stats_row = mo.hstack([
        mo.md(f"""
        ### ⭐ Recent Stars (3 days)
        **{get_star_count():,}** stars
        """),
        mo.md(f"""
        ### 📊 Total Events (3 days)
        **{get_total_events():,}** events
        """)
    ], justify="space-between")
    
    mo.vstack([
        mo.md("## 📊 Live GitHub Events Data"),
        mo.md(f"*Last updated: {get_last_update()} • Auto-refresh every 60 seconds*"),
        stats_row,
        dataRefresh  # Ensure refresh component is rendered (even if hidden)
    ])


@app.cell
def _(mo, top_repos_pandas):
    # Display top 10 repositories by star count for last 3 days
    if top_repos_pandas is not None and len(top_repos_pandas) > 0:
        top_repos_table = mo.ui.table(
            top_repos_pandas,
            selection=None,
            show_column_summaries=False
        )
        result = mo.vstack([
            mo.md("### 🏆 Top 10 Repositories by Stars (Last 3 Days)"),
            top_repos_table
        ])
    else:
        result = mo.vstack([
            mo.md("### 🏆 Top 10 Repositories by Stars (Last 3 Days)"),
            mo.md("*No data available - Please check if there are WatchEvent records in the database*")
        ])
    
    result


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
        mo.md("### 📋 Recent GitHub Events"),
        table
    ])
    return


if __name__ == "__main__":
    app.run()
