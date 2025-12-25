-- CDC 测试场景脚本
-- 运行这些操作来观察 Debezium 如何捕获不同类型的数据变更

-- 场景 1: INSERT 操作 - 新用户注册
INSERT INTO debezium_test.users (username, email, full_name, age, status) VALUES
('new_user_001', 'newuser001@example.com', 'New User 001', 26, 'active');

-- 等待一下让 CDC 捕获
SELECT pg_sleep(2);

-- 场景 2: 创建订单 (关联数据)
INSERT INTO debezium_test.orders (user_id, order_number, total_amount, status) VALUES
((SELECT id FROM debezium_test.users WHERE username = 'john_doe'), 'ORD-2024-001', 1999.99, 'pending');

INSERT INTO debezium_test.orders (user_id, order_number, total_amount, status) VALUES
((SELECT id FROM debezium_test.users WHERE username = 'jane_smith'), 'ORD-2024-002', 42.98, 'pending');

SELECT pg_sleep(2);

-- 场景 3: UPDATE 操作 - 更新用户信息
UPDATE debezium_test.users 
SET age = 31, full_name = 'John Doe Sr.' 
WHERE username = 'john_doe';

-- 更新订单状态
UPDATE debezium_test.orders 
SET status = 'confirmed', total_amount = 2099.99 
WHERE order_number = 'ORD-2024-001';

SELECT pg_sleep(2);

-- 场景 4: 批量更新操作
UPDATE debezium_test.products 
SET price = price * 0.9, stock_quantity = stock_quantity - 1 
WHERE category = 'Electronics';

SELECT pg_sleep(2);

-- 场景 5: DELETE 操作
-- 首先删除依赖的订单
DELETE FROM debezium_test.orders WHERE order_number = 'ORD-2024-002';

-- 然后删除用户
DELETE FROM debezium_test.users WHERE username = 'charlie_davis';

SELECT pg_sleep(2);

-- 场景 6: 复杂的事务操作
BEGIN;

-- 添加新产品
INSERT INTO debezium_test.products (name, description, price, category, stock_quantity) VALUES
('Gaming Keyboard', 'RGB mechanical gaming keyboard', 129.99, 'Electronics', 75);

-- 创建新用户
INSERT INTO debezium_test.users (username, email, full_name, age, status) VALUES
('gamer_pro', 'gamer@example.com', 'Pro Gamer', 22, 'active');

-- 创建订单
INSERT INTO debezium_test.orders (user_id, order_number, total_amount, status) VALUES
((SELECT id FROM debezium_test.users WHERE username = 'gamer_pro'), 'ORD-2024-003', 129.99, 'pending');

-- 提交事务
COMMIT;

SELECT pg_sleep(2);

-- 显示当前状态
SELECT 'Current state after CDC test operations:' as status;

SELECT 'Users:' as table_name;
SELECT id, username, email, full_name, age, status, created_at, updated_at 
FROM debezium_test.users ORDER BY id;

SELECT 'Orders:' as table_name;
SELECT id, user_id, order_number, total_amount, status, order_date, updated_at 
FROM debezium_test.orders ORDER BY id;

SELECT 'Products:' as table_name;
SELECT id, name, price, category, stock_quantity, is_active 
FROM debezium_test.products ORDER BY id;
