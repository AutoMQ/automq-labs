-- Debezium PostgreSQL CDC 测试数据脚本
-- 该脚本用于创建测试表和数据，观察 CDC 事件

-- 1. 创建测试表
CREATE SCHEMA IF NOT EXISTS debezium_test;

-- 用户表
CREATE TABLE IF NOT EXISTS debezium_test.users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) NOT NULL,
    full_name VARCHAR(100),
    age INTEGER,
    status VARCHAR(20) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 订单表
CREATE TABLE IF NOT EXISTS debezium_test.orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES debezium_test.users(id),
    order_number VARCHAR(50) UNIQUE NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 产品表
CREATE TABLE IF NOT EXISTS debezium_test.products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    category VARCHAR(50),
    stock_quantity INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 2. 创建更新时间戳的触发器函数
CREATE OR REPLACE FUNCTION debezium_test.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 为用户表添加更新时间戳触发器
DROP TRIGGER IF EXISTS update_users_updated_at ON debezium_test.users;
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON debezium_test.users
    FOR EACH ROW
    EXECUTE FUNCTION debezium_test.update_updated_at_column();

-- 为订单表添加更新时间戳触发器
DROP TRIGGER IF EXISTS update_orders_updated_at ON debezium_test.orders;
CREATE TRIGGER update_orders_updated_at
    BEFORE UPDATE ON debezium_test.orders
    FOR EACH ROW
    EXECUTE FUNCTION debezium_test.update_updated_at_column();

-- 3. 插入初始测试数据
INSERT INTO debezium_test.users (username, email, full_name, age, status) VALUES
('john_doe', 'john@example.com', 'John Doe', 30, 'active'),
('jane_smith', 'jane@example.com', 'Jane Smith', 25, 'active'),
('bob_wilson', 'bob@example.com', 'Bob Wilson', 35, 'active'),
('alice_brown', 'alice@example.com', 'Alice Brown', 28, 'active'),
('charlie_davis', 'charlie@example.com', 'Charlie Davis', 32, 'inactive')
ON CONFLICT (username) DO NOTHING;

INSERT INTO debezium_test.products (name, description, price, category, stock_quantity) VALUES
('Laptop Pro 15', 'High-performance laptop for professionals', 1999.99, 'Electronics', 50),
('Wireless Mouse', 'Ergonomic wireless mouse', 29.99, 'Electronics', 200),
('Coffee Mug', 'Ceramic coffee mug 350ml', 12.99, 'Kitchen', 100),
('Notebook Set', 'Set of 3 premium notebooks', 19.99, 'Office', 150),
('USB Cable', 'USB-C to USB-A cable 2m', 9.99, 'Electronics', 300)
ON CONFLICT DO NOTHING;

-- 4. 显示当前数据
SELECT 'Users Table:' as table_name;
SELECT * FROM debezium_test.users ORDER BY id;

SELECT 'Products Table:' as table_name;
SELECT * FROM debezium_test.products ORDER BY id;

SELECT 'Tables created successfully! You can now run the CDC test scenarios.';
