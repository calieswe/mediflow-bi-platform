DROP TABLE IF EXISTS stg_sales, stg_shipments, stg_inventory,
  fact_sales, fact_shipments, fact_inventory,
  dim_date, dim_product, dim_geography, dim_customer, dim_distributor, dim_manufacturing_site CASCADE;

CREATE TABLE stg_sales (
  distributor VARCHAR(200), customer_name VARCHAR(200), city VARCHAR(120), country VARCHAR(80),
  latitude VARCHAR(40), longitude VARCHAR(40), channel VARCHAR(60), sub_channel VARCHAR(60),
  product_name VARCHAR(160), product_class VARCHAR(80), quantity VARCHAR(40), price VARCHAR(40),
  sales VARCHAR(40), month VARCHAR(20), year VARCHAR(10),
  sales_rep VARCHAR(120), manager VARCHAR(120), sales_team VARCHAR(60)
);
CREATE TABLE stg_shipments (
  shipment_id VARCHAR(40), order_date VARCHAR(40), product_name VARCHAR(160), product_class VARCHAR(80),
  manufacturing_site VARCHAR(120), distributor_name VARCHAR(200), country VARCHAR(80),
  quantity_shipped VARCHAR(40), shipment_mode VARCHAR(60), scheduled_delivery_date VARCHAR(40),
  actual_delivery_date VARCHAR(40), freight_cost_usd VARCHAR(40), weight_kg VARCHAR(40), shipment_status VARCHAR(60)
);
CREATE TABLE stg_inventory (
  record_id VARCHAR(40), snapshot_date VARCHAR(40), product_name VARCHAR(160), product_class VARCHAR(80),
  manufacturing_site VARCHAR(120), batch_number VARCHAR(60), expiry_date VARCHAR(40), storage_condition VARCHAR(80),
  warehouse_country VARCHAR(80), quantity_on_hand VARCHAR(40), reorder_level VARCHAR(40), stockout_flag VARCHAR(20)
);

SELECT COUNT(*) FROM stg_sales;

-- warehouse tables
CREATE TABLE dim_date (date_key INT PRIMARY KEY, full_date DATE, year INT, month INT, month_name VARCHAR(10), quarter VARCHAR(4), season VARCHAR(10));
CREATE TABLE dim_product (product_key SERIAL PRIMARY KEY, product_name VARCHAR(160), product_class VARCHAR(80), category VARCHAR(60));
CREATE TABLE dim_geography (geo_key SERIAL PRIMARY KEY, country VARCHAR(80), region VARCHAR(60));
CREATE TABLE dim_customer (customer_key SERIAL PRIMARY KEY, customer_name VARCHAR(200), channel VARCHAR(60), sub_channel VARCHAR(60), city VARCHAR(120), country VARCHAR(80));
CREATE TABLE dim_distributor (distributor_key SERIAL PRIMARY KEY, distributor_name VARCHAR(200));
CREATE TABLE dim_manufacturing_site (site_key SERIAL PRIMARY KEY, site_name VARCHAR(120));
CREATE TABLE fact_sales (sale_id SERIAL PRIMARY KEY, date_key INT, product_key INT, geo_key INT, customer_key INT, distributor_key INT, quantity NUMERIC(14,2), price NUMERIC(12,2), sales NUMERIC(16,2), is_return SMALLINT);
CREATE TABLE fact_shipments (ship_id SERIAL PRIMARY KEY, date_key INT, product_key INT, geo_key INT, distributor_key INT, site_key INT, quantity INT, freight_usd NUMERIC(12,2), weight_kg NUMERIC(12,2), on_time SMALLINT, lead_time_days INT, status VARCHAR(60));
CREATE TABLE fact_inventory (inv_id SERIAL PRIMARY KEY, date_key INT, product_key INT, geo_key INT, site_key INT, storage_condition VARCHAR(80), quantity_on_hand INT, reorder_level INT, stockout_risk SMALLINT, days_to_expiry INT, expiry_risk_flag SMALLINT);

-- dimensions
INSERT INTO dim_date
WITH RECURSIVE d AS (SELECT DATE '2017-01-01' dt UNION ALL SELECT dt+1 FROM d WHERE dt < DATE '2020-12-31')
SELECT TO_CHAR(dt,'YYYYMMDD')::int, dt, EXTRACT(YEAR FROM dt)::int, EXTRACT(MONTH FROM dt)::int, TO_CHAR(dt,'Mon'), 'Q'||EXTRACT(QUARTER FROM dt)::int,
 CASE WHEN EXTRACT(MONTH FROM dt) IN (12,1,2) THEN 'Winter' WHEN EXTRACT(MONTH FROM dt) IN (3,4,5) THEN 'Spring' WHEN EXTRACT(MONTH FROM dt) IN (6,7,8) THEN 'Summer' ELSE 'Autumn' END FROM d;

INSERT INTO dim_product (product_name, product_class, category)
SELECT DISTINCT TRIM(product_name), TRIM(product_class),
 CASE TRIM(product_class) WHEN 'Antimalarial' THEN 'Antimalarials' WHEN 'Antibiotics' THEN 'Antibiotics' WHEN 'Analgesics' THEN 'Analgesics' WHEN 'Antipiretics' THEN 'Antipyretics' WHEN 'Antiseptics' THEN 'Antiseptics' WHEN 'Mood Stabilizers' THEN 'CNS / Mood' ELSE 'Other' END
FROM stg_sales WHERE product_name IS NOT NULL;

INSERT INTO dim_geography (country, region)
SELECT DISTINCT TRIM(country), CASE TRIM(country) WHEN 'Poland' THEN 'Eastern Europe' WHEN 'Germany' THEN 'Western Europe' ELSE 'Other' END
FROM (SELECT country FROM stg_sales UNION SELECT country FROM stg_shipments UNION SELECT warehouse_country FROM stg_inventory) c WHERE TRIM(country) <> '' AND country IS NOT NULL;

INSERT INTO dim_customer (customer_name, channel, sub_channel, city, country)
SELECT DISTINCT ON (TRIM(customer_name)) TRIM(customer_name), TRIM(channel), TRIM(sub_channel), TRIM(city), TRIM(country)
FROM stg_sales WHERE customer_name IS NOT NULL ORDER BY TRIM(customer_name);

INSERT INTO dim_distributor (distributor_name)
SELECT DISTINCT TRIM(distributor) FROM stg_sales WHERE distributor IS NOT NULL AND TRIM(distributor) <> '';

INSERT INTO dim_manufacturing_site (site_name)
SELECT DISTINCT INITCAP(TRIM(manufacturing_site)) FROM (SELECT manufacturing_site FROM stg_shipments UNION SELECT manufacturing_site FROM stg_inventory) s WHERE TRIM(manufacturing_site) <> '' AND manufacturing_site IS NOT NULL;

-- facts
TRUNCATE fact_sales;

INSERT INTO fact_sales (date_key, product_key, geo_key, customer_key, distributor_key, quantity, price, sales, is_return)
SELECT dd.date_key, dp.product_key, dg.geo_key, dc.customer_key, ddist.distributor_key,
       s.quantity::numeric(14,2), s.price::numeric(12,2), s.sales::numeric(16,2),
       CASE WHEN s.sales::numeric < 0 THEN 1 ELSE 0 END
FROM (SELECT DISTINCT * FROM stg_sales) s          -- <-- removes the 4 exact-duplicate rows
JOIN dim_date dd ON dd.full_date = TO_DATE(s.year||'-'||s.month||'-01','YYYY-Month-DD')
JOIN dim_product dp ON dp.product_name = TRIM(s.product_name) AND dp.product_class = TRIM(s.product_class)
JOIN dim_geography dg ON dg.country = TRIM(s.country)
JOIN dim_customer dc ON dc.customer_name = TRIM(s.customer_name)
JOIN dim_distributor ddist ON ddist.distributor_name = TRIM(s.distributor);

SELECT COUNT(*) AS rows, ROUND(SUM(sales)) AS total_revenue FROM fact_sales;

INSERT INTO fact_shipments (date_key, product_key, geo_key, distributor_key, site_key, quantity, freight_usd, weight_kg, on_time, lead_time_days, status)
SELECT dd.date_key, dp.product_key, dg.geo_key, ddist.distributor_key, dsite.site_key, sh.quantity_shipped::int,
 NULLIF(NULLIF(TRIM(sh.freight_cost_usd),'N/A'),'')::numeric(12,2), NULLIF(TRIM(sh.weight_kg),'')::numeric(12,2),
 CASE WHEN TO_DATE(sh.actual_delivery_date,'YYYY-MM-DD') <= TO_DATE(sh.scheduled_delivery_date,'YYYY-MM-DD') THEN 1 ELSE 0 END,
 (TO_DATE(sh.actual_delivery_date,'YYYY-MM-DD') - TO_DATE(sh.order_date,'YYYY-MM-DD')), INITCAP(TRIM(sh.shipment_status))
FROM stg_shipments sh
JOIN dim_date dd ON dd.full_date = TO_DATE(sh.order_date,'YYYY-MM-DD')
JOIN dim_product dp ON dp.product_name = TRIM(sh.product_name)
JOIN dim_geography dg ON dg.country = TRIM(sh.country)
JOIN dim_distributor ddist ON ddist.distributor_name = TRIM(sh.distributor_name)
JOIN dim_manufacturing_site dsite ON dsite.site_name = INITCAP(TRIM(sh.manufacturing_site))
WHERE sh.quantity_shipped::int > 0;

INSERT INTO fact_inventory (date_key, product_key, geo_key, site_key, storage_condition, quantity_on_hand, reorder_level, stockout_risk, days_to_expiry, expiry_risk_flag)
SELECT dd.date_key, dp.product_key, dg.geo_key, dsite.site_key, INITCAP(TRIM(iv.storage_condition)),
 NULLIF(NULLIF(TRIM(iv.quantity_on_hand),'N/A'),'')::int, NULLIF(TRIM(iv.reorder_level),'')::int,
 CASE WHEN LOWER(TRIM(iv.stockout_flag)) IN ('yes','true','1') OR (COALESCE(NULLIF(NULLIF(TRIM(iv.quantity_on_hand),'N/A'),'')::int,0) <= COALESCE(NULLIF(TRIM(iv.reorder_level),'')::int,0)) THEN 1 ELSE 0 END,
 (TO_DATE(iv.expiry_date,'YYYY-MM-DD') - DATE '2020-12-31'),
 CASE WHEN (TO_DATE(iv.expiry_date,'YYYY-MM-DD') - DATE '2020-12-31') BETWEEN 0 AND 90 THEN 1 ELSE 0 END
FROM stg_inventory iv
JOIN dim_date dd ON dd.full_date = TO_DATE(iv.snapshot_date,'YYYY-MM-DD')
JOIN dim_product dp ON dp.product_name = TRIM(iv.product_name)
JOIN dim_geography dg ON dg.country = TRIM(iv.warehouse_country)
JOIN dim_manufacturing_site dsite ON dsite.site_name = INITCAP(TRIM(iv.manufacturing_site));

-- verify
SELECT 'fact_sales' t, COUNT(*) FROM fact_sales
UNION ALL SELECT 'fact_shipments', COUNT(*) FROM fact_shipments
UNION ALL SELECT 'fact_inventory', COUNT(*) FROM fact_inventory;


SELECT
  (SELECT ROUND(100.0*SUM(on_time)/COUNT(*),1) FROM fact_shipments WHERE status='Delivered') AS on_time_pct,
  (SELECT ROUND(100.0*SUM(stockout_risk)/COUNT(*),1) FROM fact_inventory) AS stockout_pct,
  (SELECT ROUND(100.0*SUM(expiry_risk_flag)/COUNT(*),1) FROM fact_inventory) AS expiry_pct,
  (SELECT ROUND(SUM(sales)) FROM fact_sales) AS total_revenue;