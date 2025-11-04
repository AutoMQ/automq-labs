-- make sure the `metastore` database exists
CREATE DATABASE IF NOT EXISTS metastore;

-- drop the `hive` user if it exists
DROP USER IF EXISTS 'hive'@'%';

-- create the `hive` user and grant privileges
CREATE USER 'hive'@'%' IDENTIFIED BY 'hive';
GRANT ALL PRIVILEGES ON metastore.* TO 'hive'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
