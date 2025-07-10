import os
from pyspark.sql import SparkSession
from pyspark.sql.functions import from_json, col
from pyspark.sql.types import StructType, StructField, StringType, FloatType, IntegerType

# Environment and Configuration
ICEBERG_CATALOG_URI = os.environ.get("ICEBERG_CATALOG_URI", "http://rest:8181")
ICEBERG_WAREHOUSE = os.environ.get("ICEBERG_WAREHOUSE", "s3://warehouse/wh/")

# Database
ICEBERG_DATABASE = "default"

# Table Names
SOURCE_TABLE_NAME = f"{ICEBERG_DATABASE}.telemetry"
TARGET_TABLE_NAME = f"{ICEBERG_DATABASE}.vehicle"

def get_spark_session():
    """Creates and returns a Spark session with Iceberg and Kafka configurations."""
    return (
        SparkSession.builder
        .appName("IcebergSparkStreamingJob")
        .getOrCreate()
    )

def main():
    """Main function to run the Spark Streaming job."""
    spark = get_spark_session()
    spark.sparkContext.setLogLevel("INFO")

    # --- Stream from Source Table to Target Structured Iceberg Table ---
    print(f"Starting stream from source table '{SOURCE_TABLE_NAME}' to target table '{TARGET_TABLE_NAME}'.")

    # Define the schema for the structured data within the JSON 'value' column
    json_schema = StructType([
        StructField("iccid", StringType(), True),
        StructField("speed", FloatType(), True),
        StructField("request", IntegerType(), True),
        StructField("response", IntegerType(), True)
    ])

    # Create the target structured table if it doesn't exist
    # The schema is based on the transformation result
    spark.sql(f"""
        CREATE TABLE IF NOT EXISTS {TARGET_TABLE_NAME} (
            vin STRING,
            iccid STRING,
            speed FLOAT,
            request INT,
            response INT,
            event_timestamp TIMESTAMP
        )
        USING iceberg
    """)
    print(f"Ensured target table '{TARGET_TABLE_NAME}' exists.")

    spark.sql(f"DESCRIBE TABLE EXTENDED {TARGET_TABLE_NAME}").show(truncate=False)

    # Read from the source Iceberg table as a stream
    source_stream_df = spark.readStream.format("iceberg").load(SOURCE_TABLE_NAME)

    # Parse the JSON 'value' column and structure the data
    # The source table schema is key: string, value: string, timestamp: timestamp
    structured_stream_df = (
        source_stream_df
        .withColumn("jsonData", from_json(col("value"), json_schema))
        .select(
            col("key").alias("vin"),
            col("jsonData.iccid").alias("iccid"),
            col("jsonData.speed").alias("speed"),
            col("jsonData.request").alias("request"),
            col("jsonData.response").alias("response"),
            col("timestamp").alias("event_timestamp")
        )
    )

    # Write the structured data to the final Iceberg table
    query_structured = (
        structured_stream_df.writeStream
        .format("iceberg")
        .outputMode("append")
        .trigger(processingTime="30 seconds")
        .option("path", TARGET_TABLE_NAME)
        .option("checkpointLocation", f"s3a://warehouse/checkpoints/structured_iceberg_checkpoint")
        .start()
    )

    print("Structured data streaming query started. Waiting for termination...")

    # Await termination for the streaming query
    query_structured.awaitTermination()

if __name__ == "__main__":
    main()
