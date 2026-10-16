CREATE DATABASE instacart;
GO
USE instacart;
GO

CREATE TABLE departments (department_id INT PRIMARY KEY, department VARCHAR(100));
CREATE TABLE aisles      (aisle_id INT PRIMARY KEY, aisle VARCHAR(100));
CREATE TABLE products (
    product_id INT PRIMARY KEY,
    product_name VARCHAR(300),
    aisle_id INT,
    department_id INT
);
CREATE TABLE orders (
    order_id INT PRIMARY KEY,
    user_id INT,
    eval_set VARCHAR(10),
    order_number INT,
    order_dow INT,
    order_hour_of_day INT,
    days_since_prior_order FLOAT NULL
);
CREATE TABLE order_products_prior (order_id INT, product_id INT, add_to_cart_order INT, reordered INT);
CREATE TABLE order_products_train (order_id INT, product_id INT, add_to_cart_order INT, reordered INT);


-------------------------------
BULK INSERT departments FROM 'D:\SQL\departments.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"', ROWTERMINATOR='0x0a', KEEPNULLS, TABLOCK);

BULK INSERT aisles FROM 'D:\SQL\aisles.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"', ROWTERMINATOR='0x0a', KEEPNULLS, TABLOCK);

BULK INSERT products FROM 'D:\SQL\products.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"', ROWTERMINATOR='0x0a', KEEPNULLS, TABLOCK);

BULK INSERT orders FROM 'D:\SQL\orders.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"', ROWTERMINATOR='0x0a', KEEPNULLS, TABLOCK);

BULK INSERT order_products_prior FROM 'D:\SQL\order_products__prior.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"', ROWTERMINATOR='0x0a', KEEPNULLS, TABLOCK, BATCHSIZE=1000000);

BULK INSERT order_products_train FROM 'D:\SQL\order_products__train.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"', ROWTERMINATOR='0x0a', KEEPNULLS, TABLOCK);
--------------------------------------------------
SELECT COUNT(*) FROM orders;                 
SELECT COUNT(*) FROM order_products_prior;  
------------------------
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
-- Also press Ctrl+M in SSMS to include the Actual Execution Plan

-- Cold-cache benchmark (development machines only!)
CHECKPOINT; DBCC DROPCLEANBUFFERS;

SELECT o.user_id, COUNT(*) AS items
FROM orders o
JOIN order_products_prior op ON op.order_id = o.order_id
WHERE o.user_id = 12345
GROUP BY o.user_id;
-----------creating indexs------------
CREATE INDEX idx_orders_user      ON orders (user_id, order_number);
CREATE INDEX idx_op_prior_order   ON order_products_prior (order_id) INCLUDE (product_id, reordered);
CREATE INDEX idx_op_prior_product ON order_products_prior (product_id);
------------------------------
CREATE CLUSTERED COLUMNSTORE INDEX cci_op_prior ON order_products_prior;
---------
select count(*) as total_orders , count(Distinct USER_ID) as total_users from Orders

select order_dow , count(*) as total_orders from orders 
group by order_dow 
order by total_orders desc

-----------
select user_id , count(*) as order_count from orders
group by user_id
having count(*) > 50 
order by user_id

-----------
select * from order_products_prior
select product_id , count(*) as total_times_ordered 
from order_products_prior
group by product_id
having count(*) > 10000
order by total_times_ordered  desc
--------------------------------------

select TOP 5 order_hour_of_day ,count(*) as total_orders
from orders
group by order_hour_of_day
order by total_orders desc;
-------------------------------------------------
select * from order_products_prior
select * from products
select * from departments
------
select top 10 p.product_name , count(*) as time_orderd
from order_products_prior op
join products p on op.product_id = p.product_id
group by p.product_name
order by time_orderd desc;
------------------------------------
select d.department , count(*) as total_times
from products p
join departments d on p.department_id = d.department_id
group by d.department
order by total_times desc
-------------------------
select p.product_id , p.product_name
from products p 
left join order_products_prior op on p.product_id = op.product_id
where op.product_id is null;




SELECT user_id, COUNT(*) AS order_count
FROM orders
GROUP BY user_id
HAVING COUNT(*) > (
    SELECT AVG(cnt) FROM (
        SELECT COUNT(*) AS cnt
        FROM orders
        GROUP BY user_id
    ) t
);

-- Q11. Second most popular product (OFFSET/FETCH instead of LIMIT/OFFSET)
SELECT product_id, COUNT(*) AS times_ordered
FROM order_products_prior
GROUP BY product_id
ORDER BY times_ordered DESC
OFFSET 1 ROWS FETCH NEXT 1 ROWS ONLY;

-- Q12. Loyalty classification
SELECT user_id, COUNT(*) AS order_count,
       CASE WHEN COUNT(*) >= 40 THEN 'Loyal'
            WHEN COUNT(*) >= 15 THEN 'Regular'
            ELSE 'New' END AS customer_type
FROM orders GROUP BY user_id;

-- Q13. Customers per type
SELECT customer_type, COUNT(*) AS customers
FROM (
    SELECT user_id,
           CASE WHEN COUNT(*) >= 40 THEN 'Loyal'
                WHEN COUNT(*) >= 15 THEN 'Regular'
                ELSE 'New' END AS customer_type
    FROM orders GROUP BY user_id
) t
GROUP BY customer_type;

-- Q14. Top 3 products per department (RANK)
SELECT * FROM (
    SELECT d.department, p.product_name, COUNT(*) AS times_ordered,
           RANK() OVER (PARTITION BY d.department ORDER BY COUNT(*) DESC) AS rnk
    FROM order_products_prior op
    JOIN products p    ON op.product_id = p.product_id
    JOIN departments d ON p.department_id = d.department_id
    GROUP BY d.department, p.product_name
) t
WHERE rnk <= 3;

-- Q15. Each customer's first order (ROW_NUMBER)
SELECT user_id, order_id, order_dow, order_hour_of_day
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY order_number) AS rn
    FROM orders
) t
WHERE rn = 1;

-- Q16. Basket-size change vs previous order (LAG)
SELECT order_id, user_id, order_number, items,
       items - LAG(items) OVER (PARTITION BY user_id ORDER BY order_number) AS change_from_prev
FROM (
    SELECT o.order_id, o.user_id, o.order_number, COUNT(*) AS items
    FROM orders o
    JOIN order_products_prior op ON o.order_id = op.order_id
    GROUP BY o.order_id, o.user_id, o.order_number
) t
WHERE user_id <= 100;

-- Q17. Running order count per customer
SELECT user_id, order_number,
       COUNT(*) OVER (PARTITION BY user_id ORDER BY order_number
                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_orders
FROM orders WHERE user_id <= 100;

-- Q18. Customers with reorder rate above 70% (CAST fixes integer AVG)
WITH user_reorders AS (
    SELECT o.user_id, ROUND(100.0 * AVG(CAST(op.reordered AS FLOAT)), 1) AS reorder_pct
    FROM orders o
    JOIN order_products_prior op ON o.order_id = op.order_id
    GROUP BY o.user_id
)
SELECT user_id, reorder_pct FROM user_reorders
WHERE reorder_pct > 70 ORDER BY reorder_pct DESC;

-- Q19. Retention curve: customers reaching each order number
SELECT order_number, COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(DISTINCT user_id) FROM orders), 1) AS retention_pct
FROM orders
WHERE order_number <= 20
GROUP BY order_number ORDER BY order_number;

-- Q20. Customers who lapsed (final gap of 21+ days)
SELECT COUNT(*) AS lapsed_customers
FROM orders
WHERE eval_set IN ('train', 'test') AND days_since_prior_order >= 21;

-- Q21. Simple RFM-style segments
SELECT user_id, COUNT(*) AS frequency,
       ROUND(AVG(days_since_prior_order), 1) AS avg_gap,
       CASE WHEN COUNT(*) >= 30 AND AVG(days_since_prior_order) <= 10 THEN 'Champion'
            WHEN COUNT(*) >= 15 THEN 'Loyal'
            WHEN AVG(days_since_prior_order) >= 20 THEN 'At risk'
            ELSE 'Regular' END AS segment
FROM orders WHERE eval_set = 'prior'
GROUP BY user_id;

---------------------------------------------
-- RFM view (used by the dashboard)
CREATE OR ALTER VIEW rfm AS
SELECT user_id,
       COUNT(*) AS frequency,
       AVG(days_since_prior_order) AS avg_gap,
       CASE WHEN COUNT(*) >= 30 AND AVG(days_since_prior_order) <= 10 THEN 'Champion'
            WHEN COUNT(*) >= 15 THEN 'Loyal'
            WHEN AVG(days_since_prior_order) >= 20 THEN 'At risk'
            ELSE 'Regular' END AS segment
FROM orders WHERE eval_set = 'prior'
GROUP BY user_id;
GO

-- Feature table
DROP TABLE IF EXISTS user_features;
GO

WITH basket AS (
    SELECT order_id, COUNT(*) AS items, SUM(reordered) AS reordered_items
    FROM order_products_prior
    GROUP BY order_id
),
features AS (
    SELECT o.user_id,
           COUNT(*)                                              AS n_orders,
           AVG(o.days_since_prior_order)                         AS avg_gap,
           AVG(CAST(b.items AS FLOAT))                           AS avg_basket,
           CAST(SUM(b.reordered_items) AS FLOAT) / SUM(b.items)  AS reorder_ratio,
           AVG(CAST(o.order_hour_of_day AS FLOAT))               AS avg_hour,
           AVG(CASE WHEN o.order_dow IN (0, 6) THEN 1.0 ELSE 0.0 END) AS weekend_share
    FROM orders o
    JOIN basket b ON o.order_id = b.order_id
    WHERE o.eval_set = 'prior'
    GROUP BY o.user_id
),
label AS (
    SELECT user_id,
           CASE WHEN days_since_prior_order >= 21 THEN 1 ELSE 0 END AS lapsed
    FROM orders
    WHERE eval_set IN ('train', 'test')
)
SELECT f.*, l.lapsed
INTO user_features
FROM features f
JOIN label l ON f.user_id = l.user_id;
GO

SELECT COUNT(*) FROM user_features;


-----------------------------------------
SELECT TOP 10 * FROM user_churn_scores
ORDER BY churn_risk DESC;
SELECT COUNT(*) FROM user_churn_scores; 

USE instacart;

SELECT DB_NAME() AS current_db;        
SELECT COUNT(*) FROM user_features;    
SELECT TOP 10 * FROM user_churn_scores ORDER BY churn_risk DESC;
SELECT COUNT(*) FROM user_churn_scores;  