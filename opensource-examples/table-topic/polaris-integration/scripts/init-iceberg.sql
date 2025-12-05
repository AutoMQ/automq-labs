-- Create and inspect an Iceberg table via Polaris REST catalog headers set in AutoMQ
-- Example: Create a sample Iceberg table and list tables in the default namespace
CREATE TABLE IF NOT EXISTS default.sample_iceberg_table (
  id INT,
  name STRING
) USING ICEBERG;

SHOW TABLES IN default;
