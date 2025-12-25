-- PostgreSQL setup script for Debezium
-- Run this script after the database is created to set up proper permissions

-- Connect to the database as the master user (dbadmin)
-- psql -h <endpoint> -p 5432 -U dbadmin -d testdb

-- Create a dedicated user for Debezium with replication privileges
CREATE USER debezium WITH ENCRYPTED PASSWORD 'debezium_password_change_me';

-- Grant replication privileges (required for logical replication)
ALTER USER debezium WITH REPLICATION;

-- Grant necessary database privileges
GRANT CONNECT ON DATABASE testdb TO debezium;
GRANT USAGE ON SCHEMA public TO debezium;
GRANT CREATE ON SCHEMA public TO debezium;

-- Grant privileges on existing tables (and future ones)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO debezium;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO debezium;

-- Create a test table for CDC testing
CREATE TABLE IF NOT EXISTS customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Grant permissions on the test table
GRANT SELECT ON customers TO debezium;
GRANT USAGE ON SEQUENCE customers_id_seq TO debezium;

-- Insert some test data
INSERT INTO customers (name, email) VALUES 
    ('John Doe', 'john@example.com'),
    ('Jane Smith', 'jane@example.com'),
    ('Bob Johnson', 'bob@example.com');

-- Verify logical replication is enabled
SHOW rds.logical_replication;
SHOW wal_level;
SHOW max_replication_slots;
SHOW max_wal_senders;

-- Create a logical replication slot for Debezium (optional - Debezium can create this)
-- SELECT pg_create_logical_replication_slot('debezium_slot', 'pgoutput');

-- List current replication slots
SELECT slot_name, plugin, slot_type, database, active FROM pg_replication_slots;
