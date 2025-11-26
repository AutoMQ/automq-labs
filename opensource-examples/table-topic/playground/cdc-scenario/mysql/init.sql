-- Initialize MySQL database for CDC testing with demo operations
CREATE DATABASE IF NOT EXISTS sampledb;
USE sampledb;

-- Create users table (main table for CDC testing)
CREATE TABLE users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  first_name VARCHAR(255) NOT NULL,
  last_name VARCHAR(255) NOT NULL,
  email VARCHAR(255) UNIQUE NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Insert initial sample data
INSERT INTO users (first_name, last_name, email) VALUES
('John', 'Doe', 'john.doe@example.com'),
('Jane', 'Smith', 'jane.smith@example.com'),
('Peter', 'Jones', 'peter.jones@example.com'),
('Alice', 'Williams', 'alice.williams@example.com'),
('Bob', 'Brown', 'bob.brown@example.com');

-- Demo CDC Operations: INSERT (新增数据)
INSERT INTO users (first_name, last_name, email) VALUES
('CDC', 'Test1', 'cdc.test1@example.com'),
('CDC', 'Test2', 'cdc.test2@example.com');

-- Demo CDC Operations: UPDATE (修改数据)
UPDATE users SET 
  email = 'john.doe.updated@example.com',
  updated_at = CURRENT_TIMESTAMP
WHERE first_name = 'John' AND last_name = 'Doe';

UPDATE users SET 
  first_name = 'Jane Updated',
  updated_at = CURRENT_TIMESTAMP
WHERE email = 'jane.smith@example.com';

-- Demo CDC Operations: DELETE (删除数据)
DELETE FROM users WHERE first_name = 'CDC' AND last_name = 'Test2';

-- Demo Schema Evolution: ADD COLUMN (添加列)
ALTER TABLE users ADD COLUMN phone VARCHAR(20) DEFAULT NULL;
ALTER TABLE users ADD COLUMN status ENUM('active', 'inactive') DEFAULT 'active';
ALTER TABLE users ADD COLUMN age INT DEFAULT NULL;

-- Insert data with new columns
INSERT INTO users (first_name, last_name, email, phone, status, age) VALUES
('Schema', 'Test', 'schema.test@example.com', '123-456-7890', 'active', 30);

-- Update existing records with new column values
UPDATE users SET 
  phone = '555-0001',
  status = 'active',
  age = 25
WHERE first_name = 'Peter';

-- Demo Schema Evolution: DROP COLUMN (删除列)
ALTER TABLE users DROP COLUMN age;

-- Demo Schema Evolution: MODIFY COLUMN (修改列)
ALTER TABLE users MODIFY COLUMN phone VARCHAR(30);

-- More CDC operations after schema changes
INSERT INTO users (first_name, last_name, email, phone, status) VALUES
('Final', 'Test', 'final.test@example.com', '+1-555-123-4567', 'inactive');

-- Final update operation
UPDATE users SET status = 'active' WHERE status = 'inactive';

-- Create a dedicated user for CDC testing
DROP USER IF EXISTS 'debezium'@'%';
CREATE USER 'debezium'@'%' IDENTIFIED BY 'dbz';
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'debezium'@'%';
GRANT ALL PRIVILEGES ON sampledb.* TO 'debezium'@'%';
FLUSH PRIVILEGES;
