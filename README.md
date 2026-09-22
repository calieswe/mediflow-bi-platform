# MediFlow — Pharmaceutical BI Platform

An end-to-end business intelligence project for a pharmaceutical supply chain (team project, NCI Higher Diploma in Data Analytics).

## What it does
Turns raw sales, shipment and inventory data into decision-ready dashboards for inventory health, delivery performance, demand forecasting and executive reporting.

## Tools & techniques
- **PostgreSQL** — star-schema data warehouse (3 fact tables, 6 conformed dimensions)
- **SQL** — ETL: cleaning, standardising and integrating the source data
- **Power BI + DAX** — data model, KPI measures and four interactive dashboards
- **Python (pandas)** — synthetic data generation

## Files
- `MediFlow SQL.sql` — ETL and data-warehouse build scripts
- `MediFlow BI.pbix` — Power BI report (data model, DAX, four dashboards)
- `generate_operational_data.py` — Python script that generates the synthetic data
- `MediFlow BI report.docx` — full project report
- `pharma-data - Sample.csv` — sample of the sales data
- `raw_inventory.csv`, `raw_shipments.csv` — synthetic inventory and shipment data

## Data
`pharma-data - Sample.csv` is a small sample of the sales data. The full sales dataset is from Kaggle: [https://www.kaggle.com/datasets/krishangupta33/pharmaceutical-company-wholesale-retail-data?utm_source]. Shipment and inventory data are synthetic, generated in Python by `generate_operational_data.py`.
  
