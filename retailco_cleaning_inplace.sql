SET SQL_SAFE_UPDATES = 0;

-- =====================================================================
-- RetailCo Olist Project - Data Cleaning Script (In-Place)
-- This script cleans the existing tables directly. No backup copy
-- is created, so run it once and review each step's result.
-- =====================================================================


-- =====================================================================
-- 1. Standardize customer and geolocation text fields
-- =====================================================================

UPDATE olist_customers
SET
    customer_unique_id = LOWER(TRIM(customer_unique_id)),
    customer_city       = CONCAT(
                               UPPER(LEFT(TRIM(customer_city), 1)),
                               LOWER(SUBSTRING(TRIM(customer_city), 2))
                           ),
    customer_state      = UPPER(TRIM(customer_state));

UPDATE olist_geolocation
SET
    geolocation_city  = CONCAT(
                             UPPER(LEFT(TRIM(geolocation_city), 1)),
                             LOWER(SUBSTRING(TRIM(geolocation_city), 2))
                         ),
    geolocation_state = UPPER(TRIM(geolocation_state));


-- =====================================================================
-- 2. Fix invalid delivery dates (delivered before purchase)
-- =====================================================================

UPDATE olist_orders
SET order_delivered_customer_date = NULL
WHERE order_delivered_customer_date < order_purchase_timestamp;


-- =====================================================================
-- 3. Fix negative price / freight values
-- =====================================================================

UPDATE olist_order_items
SET
    price          = CASE WHEN price < 0         THEN NULL ELSE price END,
    freight_value  = CASE WHEN freight_value < 0 THEN NULL ELSE freight_value END;


-- =====================================================================
-- 4. Convert empty strings ('') to NULL across all text columns
-- =====================================================================

UPDATE olist_orders
SET
    order_id     = NULLIF(TRIM(order_id), ''),
    customer_id  = NULLIF(TRIM(customer_id), ''),
    order_status = NULLIF(TRIM(order_status), '');

UPDATE olist_order_items
SET
    order_id   = NULLIF(TRIM(order_id), ''),
    product_id = NULLIF(TRIM(product_id), '');
    -- order_item_id is numeric; left untouched (TRIM on int is unnecessary)

UPDATE olist_customers
SET
    customer_id               = NULLIF(TRIM(customer_id), ''),
    customer_unique_id        = NULLIF(TRIM(customer_unique_id), ''),
    customer_city              = NULLIF(TRIM(customer_city), ''),
    customer_state              = NULLIF(TRIM(customer_state), ''),
    customer_zip_code_prefix     = NULLIF(TRIM(customer_zip_code_prefix), '');

UPDATE olist_reviews
SET
    review_id = NULLIF(TRIM(review_id), ''),
    order_id  = NULLIF(TRIM(order_id), '');
    -- review_score is numeric; left untouched

UPDATE olist_geolocation
SET
    geolocation_zip_code_prefix = NULLIF(TRIM(geolocation_zip_code_prefix), ''),
    geolocation_city              = NULLIF(TRIM(geolocation_city), ''),
    geolocation_state              = NULLIF(TRIM(geolocation_state), '');


-- =====================================================================
-- 5. Remove duplicate order items (same order_id + order_item_id)
-- =====================================================================

DELETE FROM olist_order_items
WHERE (order_id, order_item_id, product_id) NOT IN (
    SELECT order_id, order_item_id, product_id
    FROM (
        SELECT order_id, order_item_id, product_id,
               ROW_NUMBER() OVER (
                   PARTITION BY order_id, order_item_id
                   ORDER BY product_id
               ) AS rn
        FROM olist_order_items
    ) t
    WHERE rn = 1
);


-- =====================================================================
-- 6. Remove reviews with no score (must happen before deleting
--    canceled orders, order is not important for this step)
-- =====================================================================

DELETE FROM olist_reviews
WHERE review_score IS NULL;


-- =====================================================================
-- 7. Remove canceled orders FIRST, then clean up everything that
--    references them. This fixes the ordering bug: deleting orphan
--    order_items/reviews BEFORE removing canceled orders leaves new
--    orphans behind once canceled orders are deleted.
-- =====================================================================

DELETE FROM olist_orders
WHERE order_status = 'canceled';

-- Now remove order_items pointing to orders that no longer exist
-- (covers both originally-orphaned rows and rows orphaned by step 7)
DELETE FROM olist_order_items
WHERE order_id NOT IN (SELECT order_id FROM olist_orders);

-- Now remove reviews pointing to orders that no longer exist
DELETE FROM olist_reviews
WHERE order_id NOT IN (SELECT order_id FROM olist_orders);


-- =====================================================================
-- 8. Build customer_lifetime (best customers, repeat behavior)
--    total_revenue includes price + freight_value
-- =====================================================================

DROP TABLE IF EXISTS customer_lifetime;
CREATE TABLE customer_lifetime AS
SELECT
    o.customer_id,
    COUNT(DISTINCT o.order_id)                                      AS total_orders,
    SUM(i.price + i.freight_value)                                  AS total_revenue,
    SUM(i.price + i.freight_value) / COUNT(DISTINCT o.order_id)     AS avg_order_value
FROM olist_orders AS o
JOIN olist_order_items AS i USING (order_id)
GROUP BY o.customer_id
ORDER BY total_revenue DESC;

SET SQL_SAFE_UPDATES = 1;

-- =====================================================================
-- END OF CLEANING SCRIPT
-- Tables now clean and consistent:
-- olist_orders, olist_order_items, olist_customers,
-- olist_reviews, olist_geolocation, customer_lifetime
-- =====================================================================
