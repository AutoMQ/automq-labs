-- MySQL CDC 测试场景脚本
-- 运行这些操作来观察 Debezium 如何捕获不同类型的数据变更

USE debezium_test;

-- 场景 1: INSERT 操作 - 新用户注册和订单创建
INSERT INTO users (username, email, full_name, age, status, balance) VALUES
('new_customer_001', 'customer001@test.com', 'New Customer 001', 27, 'active', 0.00);

-- 记录用户注册活动
INSERT INTO user_activity_logs (user_id, activity_type, activity_description, ip_address) VALUES
(LAST_INSERT_ID(), 'register', 'New user registration completed', '203.0.113.10');

-- 等待 CDC 捕获
SELECT SLEEP(1) as wait_for_cdc;

-- 场景 2: 创建新产品和订单
INSERT INTO products (name, description, price, category, stock_quantity, sku) VALUES
('Wireless Headphones', 'High-quality Bluetooth headphones with noise cancellation', 199.99, 'Electronics', 45, 'WH-BT-NC');

INSERT INTO orders (user_id, order_number, total_amount, status, shipping_address, notes) VALUES
(1, 'ORD-2024-005', 199.99, 'pending', '555 Broadway, Seattle, WA 98101', 'First-time customer');

-- 添加订单详情
INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
(LAST_INSERT_ID(), (SELECT id FROM products WHERE sku = 'WH-BT-NC'), 1, 199.99);

SELECT SLEEP(1) as wait_for_cdc;

-- 场景 3: UPDATE 操作 - 批量更新用户余额
UPDATE users 
SET balance = balance + 100.00,
    status = 'active'
WHERE status IN ('pending', 'inactive')
  AND id <= 10;

-- 记录余额更新活动
INSERT INTO user_activity_logs (user_id, activity_type, activity_description, ip_address)
SELECT id, 'balance_update', CONCAT('Balance increased by $100.00, new balance: $', balance), '192.168.1.1'
FROM users 
WHERE status = 'active' AND balance >= 100.00
LIMIT 5;

SELECT SLEEP(1) as wait_for_cdc;

-- 场景 4: 订单状态更新 (模拟订单处理流程)
UPDATE orders 
SET status = 'confirmed',
    updated_at = CURRENT_TIMESTAMP,
    notes = CONCAT(COALESCE(notes, ''), ' - Order confirmed at ', NOW())
WHERE status = 'pending'
  AND order_date >= DATE_SUB(NOW(), INTERVAL 1 DAY);

SELECT SLEEP(1) as wait_for_cdc;

-- 场景 5: 产品价格批量调整 (模拟促销活动)
UPDATE products 
SET price = ROUND(price * 0.85, 2),  -- 15% 折扣
    updated_at = CURRENT_TIMESTAMP
WHERE category = 'Electronics' 
  AND price > 100.00;

SELECT SLEEP(1) as wait_for_cdc;

-- 场景 6: 复杂的事务操作 - 用户购买流程
START TRANSACTION;

-- 创建新用户
INSERT INTO users (username, email, full_name, age, status, balance) VALUES
('power_user_999', 'poweruser@example.com', 'Power User', 33, 'active', 5000.00);

SET @new_user_id = LAST_INSERT_ID();

-- 记录用户注册
INSERT INTO user_activity_logs (user_id, activity_type, activity_description, ip_address) VALUES
(@new_user_id, 'register', 'Power user account created', '10.0.0.100');

-- 创建订单
INSERT INTO orders (user_id, order_number, total_amount, status, shipping_address) VALUES
(@new_user_id, CONCAT('ORD-', DATE_FORMAT(NOW(), '%Y%m%d'), '-', LPAD(@new_user_id, 3, '0')), 0.00, 'pending', '777 Tech Avenue, San Francisco, CA 94105');

SET @new_order_id = LAST_INSERT_ID();

-- 添加多个商品到订单
INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
(@new_order_id, 1, 1, (SELECT price FROM products WHERE id = 1)),  -- MacBook Pro
(@new_order_id, 3, 2, (SELECT price FROM products WHERE id = 3)),  -- AirPods Pro x2
(@new_order_id, 7, 1, (SELECT price FROM products WHERE id = 7));  -- Wireless Keyboard

-- 更新订单总金额
UPDATE orders 
SET total_amount = (
    SELECT SUM(quantity * unit_price) 
    FROM order_items 
    WHERE order_id = @new_order_id
)
WHERE id = @new_order_id;

-- 更新产品库存
UPDATE products p
JOIN order_items oi ON p.id = oi.product_id
SET p.stock_quantity = p.stock_quantity - oi.quantity
WHERE oi.order_id = @new_order_id;

-- 扣除用户余额
UPDATE users 
SET balance = balance - (SELECT total_amount FROM orders WHERE id = @new_order_id)
WHERE id = @new_user_id;

-- 记录购买活动
INSERT INTO user_activity_logs (user_id, activity_type, activity_description, ip_address) VALUES
(@new_user_id, 'purchase', CONCAT('Order ', @new_order_id, ' created with total amount $', (SELECT total_amount FROM orders WHERE id = @new_order_id)), '10.0.0.100');

COMMIT;

SELECT SLEEP(2) as wait_for_transaction_cdc;

-- 场景 7: DELETE 操作 - 清理测试数据
-- 删除旧的活动日志 (模拟数据清理)
DELETE FROM user_activity_logs 
WHERE created_at < DATE_SUB(NOW(), INTERVAL 7 DAY)
  AND activity_type IN ('view_product', 'search');

SELECT SLEEP(1) as wait_for_cdc;

-- 场景 8: 大批量操作 - 模拟高并发场景
-- 批量插入用户活动日志
INSERT INTO user_activity_logs (user_id, activity_type, activity_description, ip_address, user_agent)
SELECT 
    u.id,
    'bulk_activity',
    CONCAT('Bulk generated activity #', (@row_number := @row_number + 1)),
    CONCAT('192.168.', FLOOR(1 + RAND() * 254), '.', FLOOR(1 + RAND() * 254)),
    'Mozilla/5.0 (Bulk Test Agent)'
FROM users u
CROSS JOIN (SELECT @row_number := 0) r
WHERE u.status = 'active'
LIMIT 50;

SELECT SLEEP(1) as wait_for_cdc;

-- 场景 9: 条件性批量更新
UPDATE users u
JOIN (
    SELECT user_id, COUNT(*) as order_count, SUM(total_amount) as total_spent
    FROM orders 
    WHERE status IN ('delivered', 'confirmed')
    GROUP BY user_id
    HAVING COUNT(*) >= 1
) o ON u.id = o.user_id
SET u.status = 'active',
    u.balance = u.balance + (o.total_spent * 0.05);  -- 5% 返现奖励

SELECT SLEEP(1) as wait_for_cdc;

-- 场景 10: 软删除模拟 (更新状态而不是真删除)
UPDATE orders 
SET status = 'cancelled',
    notes = CONCAT(COALESCE(notes, ''), ' - Cancelled due to inventory shortage')
WHERE status = 'pending' 
  AND total_amount > 1000.00
LIMIT 2;

SELECT SLEEP(1) as wait_for_cdc;

-- 显示最终统计信息
SELECT 'CDC Test Scenarios Completed!' as status;

SELECT 
    'Final Data Statistics:' as summary_type,
    '' as table_name,
    '' as record_count,
    '' as latest_activity
UNION ALL
SELECT 
    '',
    'users' as table_name, 
    COUNT(*) as record_count,
    MAX(updated_at) as latest_activity
FROM users
UNION ALL
SELECT 
    '',
    'orders' as table_name, 
    COUNT(*) as record_count,
    MAX(updated_at) as latest_activity
FROM orders
UNION ALL
SELECT 
    '',
    'products' as table_name, 
    COUNT(*) as record_count,
    MAX(updated_at) as latest_activity
FROM products
UNION ALL
SELECT 
    '',
    'order_items' as table_name, 
    COUNT(*) as record_count,
    MAX(created_at) as latest_activity
FROM order_items
UNION ALL
SELECT 
    '',
    'user_activity_logs' as table_name, 
    COUNT(*) as record_count,
    MAX(created_at) as latest_activity
FROM user_activity_logs;

-- 显示最近的变更摘要
SELECT 'Recent Changes Summary:' as summary;

SELECT 'New Users:' as change_type, COUNT(*) as count
FROM users 
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 10 MINUTE)
UNION ALL
SELECT 'New Orders:' as change_type, COUNT(*) as count
FROM orders 
WHERE order_date >= DATE_SUB(NOW(), INTERVAL 10 MINUTE)
UNION ALL
SELECT 'New Activity Logs:' as change_type, COUNT(*) as count
FROM user_activity_logs 
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 10 MINUTE);
