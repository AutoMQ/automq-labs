-- MySQL 持续数据生成脚本
-- 该脚本创建存储过程，可以持续生成测试数据来观察 CDC 流

USE debezium_test;

-- 创建随机数据生成存储过程
DELIMITER //

-- 生成随机用户数据
CREATE PROCEDURE IF NOT EXISTS GenerateRandomUsers(IN batch_size INT)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE random_username VARCHAR(50);
    DECLARE random_email VARCHAR(100);
    DECLARE random_age INT;
    DECLARE random_balance DECIMAL(10,2);
    
    WHILE i < batch_size DO
        SET random_username = CONCAT('user_', UNIX_TIMESTAMP(), '_', i);
        SET random_email = CONCAT('test_', UNIX_TIMESTAMP(), '_', i, '@example.com');
        SET random_age = 18 + FLOOR(RAND() * 50);
        SET random_balance = ROUND(RAND() * 5000, 2);
        
        INSERT INTO users (username, email, full_name, age, status, balance) VALUES
        (
            random_username,
            random_email,
            CONCAT('Test User ', i),
            random_age,
            ELT(FLOOR(1 + RAND() * 3), 'active', 'inactive', 'pending'),
            random_balance
        );
        
        -- 记录用户创建活动
        INSERT INTO user_activity_logs (user_id, activity_type, activity_description, ip_address) VALUES
        (
            LAST_INSERT_ID(),
            'auto_register',
            CONCAT('Auto-generated user #', i),
            CONCAT('192.168.', FLOOR(1 + RAND() * 254), '.', FLOOR(1 + RAND() * 254))
        );
        
        SET i = i + 1;
    END WHILE;
END//

-- 生成随机产品数据
CREATE PROCEDURE IF NOT EXISTS GenerateRandomProducts(IN batch_size INT)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE categories TEXT DEFAULT 'Electronics,Kitchen,Office,Sports,Home,Books,Clothing,Toys,Health,Automotive';
    DECLARE category_count INT DEFAULT 10;
    DECLARE random_category VARCHAR(50);
    DECLARE random_price DECIMAL(10,2);
    DECLARE random_stock INT;
    
    WHILE i < batch_size DO
        SET random_category = SUBSTRING_INDEX(SUBSTRING_INDEX(categories, ',', FLOOR(1 + RAND() * category_count)), ',', -1);
        SET random_price = ROUND(10 + RAND() * 1000, 2);
        SET random_stock = FLOOR(RAND() * 200);
        
        INSERT INTO products (name, description, price, category, stock_quantity, sku, is_active) VALUES
        (
            CONCAT('Product_', UNIX_TIMESTAMP(), '_', i),
            CONCAT('Auto-generated test product description for item #', i),
            random_price,
            random_category,
            random_stock,
            CONCAT('SKU-', DATE_FORMAT(NOW(), '%Y%m%d'), '-', LPAD(i, 4, '0')),
            RAND() > 0.1  -- 90% 的产品是活跃的
        );
        
        SET i = i + 1;
    END WHILE;
END//

-- 生成随机订单数据
CREATE PROCEDURE IF NOT EXISTS GenerateRandomOrders(IN batch_size INT)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE random_user_id INT;
    DECLARE random_order_number VARCHAR(50);
    DECLARE random_total DECIMAL(10,2);
    DECLARE user_count INT;
    
    SELECT COUNT(*) INTO user_count FROM users WHERE status = 'active';
    
    IF user_count > 0 THEN
        WHILE i < batch_size DO
            -- 随机选择一个活跃用户
            SELECT id INTO random_user_id 
            FROM users 
            WHERE status = 'active' 
            ORDER BY RAND() 
            LIMIT 1;
            
            SET random_order_number = CONCAT('ORD-', DATE_FORMAT(NOW(), '%Y%m%d'), '-', UNIX_TIMESTAMP(), '-', i);
            SET random_total = ROUND(50 + RAND() * 2000, 2);
            
            INSERT INTO orders (user_id, order_number, total_amount, status, shipping_address, notes) VALUES
            (
                random_user_id,
                random_order_number,
                random_total,
                ELT(FLOOR(1 + RAND() * 5), 'pending', 'confirmed', 'shipped', 'delivered', 'cancelled'),
                CONCAT(FLOOR(100 + RAND() * 9900), ' Random St, Test City, TC ', LPAD(FLOOR(RAND() * 100000), 5, '0')),
                CONCAT('Auto-generated order #', i)
            );
            
            -- 记录订单创建活动
            INSERT INTO user_activity_logs (user_id, activity_type, activity_description, ip_address) VALUES
            (
                random_user_id,
                'order_created',
                CONCAT('Order ', random_order_number, ' created with amount $', random_total),
                CONCAT('10.0.', FLOOR(1 + RAND() * 254), '.', FLOOR(1 + RAND() * 254))
            );
            
            SET i = i + 1;
        END WHILE;
    END IF;
END//

-- 生成随机订单项目
CREATE PROCEDURE IF NOT EXISTS GenerateRandomOrderItems(IN orders_to_fill INT)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE order_id INT;
    DECLARE product_id INT;
    DECLARE random_quantity INT;
    DECLARE product_price DECIMAL(10,2);
    DECLARE items_per_order INT;
    DECLARE j INT;
    
    DECLARE order_cursor CURSOR FOR 
        SELECT id FROM orders 
        WHERE id NOT IN (SELECT DISTINCT order_id FROM order_items)
        ORDER BY RAND()
        LIMIT orders_to_fill;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN order_cursor;
    
    read_loop: LOOP
        FETCH order_cursor INTO order_id;
        IF done THEN
            LEAVE read_loop;
        END IF;
        
        SET items_per_order = 1 + FLOOR(RAND() * 5);  -- 1-5 items per order
        SET j = 0;
        
        WHILE j < items_per_order DO
            SELECT id, price INTO product_id, product_price 
            FROM products 
            WHERE is_active = 1 
            ORDER BY RAND() 
            LIMIT 1;
            
            SET random_quantity = 1 + FLOOR(RAND() * 3);  -- 1-3 quantity
            
            INSERT IGNORE INTO order_items (order_id, product_id, quantity, unit_price) VALUES
            (order_id, product_id, random_quantity, product_price);
            
            SET j = j + 1;
        END WHILE;
        
        -- 更新订单总金额
        UPDATE orders 
        SET total_amount = (
            SELECT SUM(quantity * unit_price) 
            FROM order_items 
            WHERE order_id = order_id
        )
        WHERE id = order_id;
        
    END LOOP;
    
    CLOSE order_cursor;
END//

-- 模拟用户活动
CREATE PROCEDURE IF NOT EXISTS GenerateUserActivity(IN activity_count INT)
BEGIN
    DECLARE i INT DEFAULT 0;
    DECLARE random_user_id INT;
    DECLARE activity_types TEXT DEFAULT 'login,logout,view_product,add_to_cart,remove_from_cart,search,profile_update,password_change,wishlist_add';
    DECLARE activity_type_count INT DEFAULT 9;
    DECLARE random_activity_type VARCHAR(50);
    
    WHILE i < activity_count DO
        SELECT id INTO random_user_id 
        FROM users 
        WHERE status = 'active' 
        ORDER BY RAND() 
        LIMIT 1;
        
        IF random_user_id IS NOT NULL THEN
            SET random_activity_type = SUBSTRING_INDEX(SUBSTRING_INDEX(activity_types, ',', FLOOR(1 + RAND() * activity_type_count)), ',', -1);
            
            INSERT INTO user_activity_logs (user_id, activity_type, activity_description, ip_address, user_agent) VALUES
            (
                random_user_id,
                random_activity_type,
                CONCAT('Auto-generated ', random_activity_type, ' activity #', i),
                CONCAT(
                    CASE FLOOR(RAND() * 3)
                        WHEN 0 THEN '192.168.'
                        WHEN 1 THEN '10.0.'
                        ELSE '172.16.'
                    END,
                    FLOOR(1 + RAND() * 254), '.', FLOOR(1 + RAND() * 254)
                ),
                CASE FLOOR(RAND() * 4)
                    WHEN 0 THEN 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                    WHEN 1 THEN 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
                    WHEN 2 THEN 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15'
                    ELSE 'Mozilla/5.0 (Android 13; Mobile; rv:109.0) Gecko/111.0 Firefox/111.0'
                END
            );
        END IF;
        
        SET i = i + 1;
    END WHILE;
END//

-- 批量更新用户数据 (模拟用户行为变化)
CREATE PROCEDURE IF NOT EXISTS UpdateRandomUsers(IN update_count INT)
BEGIN
    DECLARE i INT DEFAULT 0;
    
    WHILE i < update_count DO
        UPDATE users 
        SET 
            age = age + FLOOR(RAND() * 3) - 1,  -- age 可能 +1, 0, 或 -1
            balance = balance + (RAND() * 200 - 100),  -- balance 随机变化 -100 到 +100
            status = CASE 
                WHEN RAND() > 0.95 THEN 
                    ELT(FLOOR(1 + RAND() * 3), 'active', 'inactive', 'pending')
                ELSE status 
            END,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = (
            SELECT id FROM (
                SELECT id FROM users ORDER BY RAND() LIMIT 1
            ) as temp_table
        );
        
        SET i = i + 1;
    END WHILE;
END//

-- 综合数据生成存储过程
CREATE PROCEDURE IF NOT EXISTS GenerateMixedTestData(
    IN user_batch INT,
    IN product_batch INT, 
    IN order_batch INT,
    IN activity_batch INT,
    IN update_batch INT
)
BEGIN
    DECLARE exit handler for sqlexception
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    -- 生成用户
    IF user_batch > 0 THEN
        CALL GenerateRandomUsers(user_batch);
    END IF;
    
    -- 生成产品
    IF product_batch > 0 THEN
        CALL GenerateRandomProducts(product_batch);
    END IF;
    
    -- 生成订单
    IF order_batch > 0 THEN
        CALL GenerateRandomOrders(order_batch);
        CALL GenerateRandomOrderItems(order_batch);
    END IF;
    
    -- 生成活动日志
    IF activity_batch > 0 THEN
        CALL GenerateUserActivity(activity_batch);
    END IF;
    
    -- 更新用户
    IF update_batch > 0 THEN
        CALL UpdateRandomUsers(update_batch);
    END IF;
    
    COMMIT;
    
    -- 返回统计信息
    SELECT 
        'Data Generation Complete!' as status,
        user_batch as users_generated,
        product_batch as products_generated,
        order_batch as orders_generated,
        activity_batch as activities_generated,
        update_batch as users_updated;
        
END//

-- 清理旧测试数据的存储过程
CREATE PROCEDURE IF NOT EXISTS CleanupOldTestData(IN days_old INT)
BEGIN
    DECLARE deleted_logs INT DEFAULT 0;
    DECLARE deleted_items INT DEFAULT 0;
    DECLARE deleted_orders INT DEFAULT 0;
    DECLARE deleted_products INT DEFAULT 0;
    DECLARE deleted_users INT DEFAULT 0;
    
    -- 删除旧的活动日志
    DELETE FROM user_activity_logs 
    WHERE created_at < DATE_SUB(NOW(), INTERVAL days_old DAY)
      AND activity_type LIKE 'auto_%';
    SET deleted_logs = ROW_COUNT();
    
    -- 删除旧的自动生成订单项目
    DELETE oi FROM order_items oi
    JOIN orders o ON oi.order_id = o.id
    WHERE o.order_date < DATE_SUB(NOW(), INTERVAL days_old DAY)
      AND o.order_number LIKE 'ORD-%-%';
    SET deleted_items = ROW_COUNT();
    
    -- 删除旧的自动生成订单
    DELETE FROM orders 
    WHERE order_date < DATE_SUB(NOW(), INTERVAL days_old DAY)
      AND order_number LIKE 'ORD-%-%';
    SET deleted_orders = ROW_COUNT();
    
    -- 删除旧的自动生成产品
    DELETE FROM products 
    WHERE created_at < DATE_SUB(NOW(), INTERVAL days_old DAY)
      AND name LIKE 'Product_%';
    SET deleted_products = ROW_COUNT();
    
    -- 删除旧的自动生成用户 (没有订单的)
    DELETE FROM users 
    WHERE created_at < DATE_SUB(NOW(), INTERVAL days_old DAY)
      AND username LIKE 'user_%'
      AND id NOT IN (SELECT DISTINCT user_id FROM orders WHERE user_id IS NOT NULL);
    SET deleted_users = ROW_COUNT();
    
    SELECT 
        'Cleanup Complete!' as status,
        deleted_logs as activity_logs_deleted,
        deleted_items as order_items_deleted,
        deleted_orders as orders_deleted,
        deleted_products as products_deleted,
        deleted_users as users_deleted;
        
END//

DELIMITER ;

-- 使用示例和说明
SELECT 'MySQL CDC Continuous Data Generator Ready!' as status;
SELECT 'Use these procedures to generate test data:' as instructions;
SELECT 'CALL GenerateMixedTestData(5, 3, 8, 20, 5);  -- Generate mixed data' as example_1;
SELECT 'CALL GenerateUserActivity(100);               -- Generate user activities' as example_2;
SELECT 'CALL CleanupOldTestData(1);                   -- Cleanup data older than 1 day' as example_3;
