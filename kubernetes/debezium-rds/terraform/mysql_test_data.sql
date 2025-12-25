-- Debezium MySQL CDC 测试数据脚本
-- 该脚本用于创建测试表和数据，观察 MySQL CDC 事件

-- 1. 创建测试数据库 schema
CREATE DATABASE IF NOT EXISTS debezium_test;
USE debezium_test;

-- 2. 创建测试表

-- 用户表
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) NOT NULL,
    full_name VARCHAR(100),
    age INT,
    status ENUM('active', 'inactive', 'pending') DEFAULT 'active',
    balance DECIMAL(10,2) DEFAULT 0.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_username (username),
    INDEX idx_status (status),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 订单表
CREATE TABLE IF NOT EXISTS orders (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    order_number VARCHAR(50) UNIQUE NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    status ENUM('pending', 'confirmed', 'shipped', 'delivered', 'cancelled') DEFAULT 'pending',
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    shipping_address TEXT,
    notes TEXT,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_user_id (user_id),
    INDEX idx_order_number (order_number),
    INDEX idx_status (status),
    INDEX idx_order_date (order_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 产品表
CREATE TABLE IF NOT EXISTS products (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    category VARCHAR(50),
    stock_quantity INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    sku VARCHAR(50) UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_name (name),
    INDEX idx_category (category),
    INDEX idx_sku (sku),
    INDEX idx_is_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 订单详情表
CREATE TABLE IF NOT EXISTS order_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    unit_price DECIMAL(10,2) NOT NULL,
    total_price DECIMAL(10,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT,
    INDEX idx_order_id (order_id),
    INDEX idx_product_id (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 用户活动日志表 (用于测试大量 INSERT 操作)
CREATE TABLE IF NOT EXISTS user_activity_logs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    activity_type VARCHAR(50) NOT NULL,
    activity_description TEXT,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_user_id (user_id),
    INDEX idx_activity_type (activity_type),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. 插入初始测试数据

-- 插入用户数据
INSERT INTO users (username, email, full_name, age, status, balance) VALUES
('john_doe', 'john@example.com', 'John Doe', 30, 'active', 1500.50),
('jane_smith', 'jane@example.com', 'Jane Smith', 25, 'active', 2200.75),
('bob_wilson', 'bob@example.com', 'Bob Wilson', 35, 'active', 850.00),
('alice_brown', 'alice@example.com', 'Alice Brown', 28, 'active', 3200.25),
('charlie_davis', 'charlie@example.com', 'Charlie Davis', 32, 'inactive', 0.00),
('diana_jones', 'diana@example.com', 'Diana Jones', 29, 'active', 1800.90),
('frank_miller', 'frank@example.com', 'Frank Miller', 41, 'pending', 500.00)
ON DUPLICATE KEY UPDATE 
    email = VALUES(email),
    full_name = VALUES(full_name),
    age = VALUES(age),
    status = VALUES(status),
    balance = VALUES(balance);

-- 插入产品数据
INSERT INTO products (name, description, price, category, stock_quantity, sku) VALUES
('MacBook Pro 16"', 'Apple MacBook Pro with M2 Max chip', 2499.99, 'Electronics', 25, 'MBP-16-M2MAX'),
('iPhone 15 Pro', 'Latest iPhone with A17 Pro chip', 999.99, 'Electronics', 100, 'IP15-PRO-128'),
('AirPods Pro', 'Noise-cancelling wireless earbuds', 249.99, 'Electronics', 150, 'APP-2ND-GEN'),
('Magic Mouse', 'Wireless mouse for Mac', 79.99, 'Electronics', 80, 'MM-WHITE'),
('USB-C Cable', 'High-speed USB-C to USB-C cable', 19.99, 'Accessories', 500, 'USBC-2M'),
('Coffee Maker', 'Automatic drip coffee maker', 89.99, 'Kitchen', 30, 'CM-AUTO-12CUP'),
('Wireless Keyboard', 'Bluetooth mechanical keyboard', 129.99, 'Electronics', 60, 'KB-MECH-RGB'),
('Desk Lamp', 'LED desk lamp with adjustable brightness', 45.99, 'Office', 75, 'DL-LED-ADJ'),
('Water Bottle', 'Insulated stainless steel water bottle', 24.99, 'Sports', 200, 'WB-SS-32OZ'),
('Notebook Set', 'Set of 5 premium notebooks', 34.99, 'Office', 120, 'NB-SET-5PCS')
ON DUPLICATE KEY UPDATE 
    name = VALUES(name),
    description = VALUES(description),
    price = VALUES(price),
    category = VALUES(category),
    stock_quantity = VALUES(stock_quantity);

-- 插入初始订单数据
INSERT INTO orders (user_id, order_number, total_amount, status, shipping_address, notes) VALUES
(1, 'ORD-2024-001', 2499.99, 'confirmed', '123 Main St, New York, NY 10001', 'Rush delivery requested'),
(2, 'ORD-2024-002', 1279.97, 'shipped', '456 Oak Ave, Los Angeles, CA 90210', 'Leave at front door'),
(3, 'ORD-2024-003', 169.98, 'pending', '789 Pine St, Chicago, IL 60601', 'Call before delivery'),
(4, 'ORD-2024-004', 999.99, 'delivered', '321 Elm St, Houston, TX 77001', 'Delivered successfully')
ON DUPLICATE KEY UPDATE 
    total_amount = VALUES(total_amount),
    status = VALUES(status),
    shipping_address = VALUES(shipping_address),
    notes = VALUES(notes);

-- 插入订单详情
INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
(1, 1, 1, 2499.99),  -- MacBook Pro
(2, 2, 1, 999.99),   -- iPhone 15 Pro
(2, 3, 1, 249.99),   -- AirPods Pro
(2, 5, 1, 19.99),    -- USB-C Cable
(3, 4, 1, 79.99),    -- Magic Mouse
(3, 5, 3, 19.99),    -- USB-C Cable x3
(3, 8, 2, 24.99),    -- Water Bottle x2
(4, 2, 1, 999.99)    -- iPhone 15 Pro
ON DUPLICATE KEY UPDATE 
    quantity = VALUES(quantity),
    unit_price = VALUES(unit_price);

-- 插入一些用户活动日志
INSERT INTO user_activity_logs (user_id, activity_type, activity_description, ip_address, user_agent) VALUES
(1, 'login', 'User logged in successfully', '192.168.1.100', 'Mozilla/5.0 (Macintosh; Intel Mac OS X)'),
(1, 'view_product', 'Viewed MacBook Pro 16" product page', '192.168.1.100', 'Mozilla/5.0 (Macintosh; Intel Mac OS X)'),
(1, 'add_to_cart', 'Added MacBook Pro 16" to cart', '192.168.1.100', 'Mozilla/5.0 (Macintosh; Intel Mac OS X)'),
(2, 'login', 'User logged in successfully', '10.0.1.50', 'Mozilla/5.0 (iPhone; CPU iPhone OS)'),
(2, 'search', 'Searched for "iPhone 15"', '10.0.1.50', 'Mozilla/5.0 (iPhone; CPU iPhone OS)'),
(3, 'register', 'New user account created', '172.16.0.25', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)');

-- 4. 显示初始数据统计
SELECT 'Database Setup Complete!' as status;

SELECT 
    'users' as table_name, 
    COUNT(*) as record_count,
    MIN(created_at) as earliest_record,
    MAX(updated_at) as latest_update
FROM users
UNION ALL
SELECT 
    'orders' as table_name, 
    COUNT(*) as record_count,
    MIN(order_date) as earliest_record,
    MAX(updated_at) as latest_update
FROM orders
UNION ALL
SELECT 
    'products' as table_name, 
    COUNT(*) as record_count,
    MIN(created_at) as earliest_record,
    MAX(updated_at) as latest_update
FROM products
UNION ALL
SELECT 
    'order_items' as table_name, 
    COUNT(*) as record_count,
    MIN(created_at) as earliest_record,
    MAX(created_at) as latest_update
FROM order_items
UNION ALL
SELECT 
    'user_activity_logs' as table_name, 
    COUNT(*) as record_count,
    MIN(created_at) as earliest_record,
    MAX(created_at) as latest_update
FROM user_activity_logs;

SELECT 'Tables created successfully! Ready for CDC testing.' as message;
