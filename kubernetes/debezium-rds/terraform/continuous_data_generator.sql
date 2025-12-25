-- 持续数据生成脚本
-- 该脚本创建一个存储过程，可以持续生成测试数据来观察 CDC 流

-- 创建数据生成函数
CREATE OR REPLACE FUNCTION debezium_test.generate_continuous_data(batch_size INTEGER DEFAULT 10)
RETURNS TEXT AS $$
DECLARE
    i INTEGER;
    user_id INTEGER;
    order_num TEXT;
    random_user TEXT;
    random_price DECIMAL;
    result_text TEXT := '';
BEGIN
    -- 生成用户数据
    FOR i IN 1..batch_size LOOP
        INSERT INTO debezium_test.users (
            username, 
            email, 
            full_name, 
            age, 
            status
        ) VALUES (
            'user_' || EXTRACT(EPOCH FROM NOW())::bigint || '_' || i,
            'user' || EXTRACT(EPOCH FROM NOW())::bigint || '_' || i || '@test.com',
            'Test User ' || i,
            20 + (random() * 40)::integer,
            CASE WHEN random() > 0.9 THEN 'inactive' ELSE 'active' END
        );
    END LOOP;
    
    result_text := result_text || 'Generated ' || batch_size || ' users. ';
    
    -- 生成产品数据
    FOR i IN 1..batch_size/2 LOOP
        random_price := (random() * 1000 + 10)::decimal(10,2);
        INSERT INTO debezium_test.products (
            name,
            description,
            price,
            category,
            stock_quantity,
            is_active
        ) VALUES (
            'Product_' || EXTRACT(EPOCH FROM NOW())::bigint || '_' || i,
            'Auto-generated test product ' || i,
            random_price,
            CASE (random() * 4)::integer 
                WHEN 0 THEN 'Electronics'
                WHEN 1 THEN 'Kitchen' 
                WHEN 2 THEN 'Office'
                ELSE 'Home'
            END,
            (random() * 100)::integer,
            random() > 0.1
        );
    END LOOP;
    
    result_text := result_text || 'Generated ' || batch_size/2 || ' products. ';
    
    -- 生成订单数据
    FOR i IN 1..batch_size/3 LOOP
        -- 随机选择一个用户
        SELECT id INTO user_id 
        FROM debezium_test.users 
        WHERE status = 'active' 
        ORDER BY random() 
        LIMIT 1;
        
        order_num := 'ORD-' || TO_CHAR(NOW(), 'YYYY-MM-DD') || '-' || 
                    LPAD((EXTRACT(EPOCH FROM NOW())::bigint % 10000)::text, 4, '0') || '-' || i;
        
        INSERT INTO debezium_test.orders (
            user_id,
            order_number,
            total_amount,
            status
        ) VALUES (
            user_id,
            order_num,
            (random() * 500 + 10)::decimal(10,2),
            CASE (random() * 3)::integer
                WHEN 0 THEN 'pending'
                WHEN 1 THEN 'confirmed'
                ELSE 'shipped'
            END
        );
    END LOOP;
    
    result_text := result_text || 'Generated ' || batch_size/3 || ' orders. ';
    
    -- 随机更新一些现有记录
    UPDATE debezium_test.users 
    SET age = age + 1, updated_at = CURRENT_TIMESTAMP
    WHERE id IN (
        SELECT id FROM debezium_test.users 
        ORDER BY random() 
        LIMIT batch_size/4
    );
    
    result_text := result_text || 'Updated ' || batch_size/4 || ' users. ';
    
    -- 随机更新订单状态
    UPDATE debezium_test.orders 
    SET status = CASE 
        WHEN status = 'pending' THEN 'confirmed'
        WHEN status = 'confirmed' THEN 'shipped'
        ELSE 'delivered'
    END,
    updated_at = CURRENT_TIMESTAMP
    WHERE id IN (
        SELECT id FROM debezium_test.orders 
        WHERE status != 'delivered'
        ORDER BY random() 
        LIMIT batch_size/5
    );
    
    result_text := result_text || 'Updated ' || batch_size/5 || ' orders.';
    
    RETURN result_text;
END;
$$ LANGUAGE plpgsql;

-- 创建清理函数
CREATE OR REPLACE FUNCTION debezium_test.cleanup_old_data(days_old INTEGER DEFAULT 1)
RETURNS TEXT AS $$
DECLARE
    deleted_count INTEGER;
    result_text TEXT := '';
BEGIN
    -- 删除旧的测试订单
    DELETE FROM debezium_test.orders 
    WHERE order_date < NOW() - INTERVAL '1 day' * days_old
    AND order_number LIKE 'ORD-%-%-%';
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    result_text := result_text || 'Deleted ' || deleted_count || ' old orders. ';
    
    -- 删除没有订单的旧测试用户
    DELETE FROM debezium_test.users 
    WHERE created_at < NOW() - INTERVAL '1 day' * days_old
    AND username LIKE 'user_%'
    AND id NOT IN (SELECT DISTINCT user_id FROM debezium_test.orders WHERE user_id IS NOT NULL);
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    result_text := result_text || 'Deleted ' || deleted_count || ' old users. ';
    
    -- 删除旧的测试产品
    DELETE FROM debezium_test.products 
    WHERE created_at < NOW() - INTERVAL '1 day' * days_old
    AND name LIKE 'Product_%';
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    result_text := result_text || 'Deleted ' || deleted_count || ' old products.';
    
    RETURN result_text;
END;
$$ LANGUAGE plpgsql;

-- 使用示例：
-- SELECT debezium_test.generate_continuous_data(20);  -- 生成20个批次的测试数据
-- SELECT debezium_test.cleanup_old_data(1);           -- 清理1天前的测试数据
