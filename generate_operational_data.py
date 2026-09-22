# =====================================================================
# MediFlow BI — Generate the synthetic operational datasets
# Creates raw_shipments.csv and raw_inventory.csv from the REAL sales
# catalogue, so they integrate with pharma-data.csv.
#
# Requirements: Python 3, pandas, numpy.  Run from the Pharma_Data folder
# (the folder containing pharma-data.csv).
# =====================================================================
import pandas as pd
import numpy as np

rng = np.random.default_rng(41)   # fixed seed so results are reproducible

# ---------------------------------------------------------------------
# 1. Read the REAL sales data and pull out the real reference lists
#    (products, product classes, distributors, and their countries).
#    Building the synthetic data from these means it will join to sales.
# ---------------------------------------------------------------------
sales = pd.read_csv("pharma-data.csv", low_memory=False)

# unique products with their class and a typical price
products = (sales.groupby(["Product Name", "Product Class"])["Price"]
                 .median().reset_index())
products.columns = ["ProductName", "ProductClass", "Price"]
products = products.drop_duplicates("ProductName").reset_index(drop=True)

# the 29 real distributors, and the country each mainly sells in
sales["Distributor"] = sales["Distributor"].astype(str).str.strip()
dist_country = (sales.groupby("Distributor")["Country"]
                     .agg(lambda x: x.mode().iloc[0]).reset_index())
distributors = dist_country["Distributor"].tolist()
country_of = dict(zip(dist_country["Distributor"], dist_country["Country"]))

# MediFlow's own manufacturing plants, and the country each is in
sites = ["Frankfurt Plant", "Warsaw Plant", "Krakow Facility", "Munich Plant", "Poznan Site"]
site_country = {"Frankfurt Plant": "Germany", "Warsaw Plant": "Poland",
                "Krakow Facility": "Poland", "Munich Plant": "Germany", "Poznan Site": "Poland"}
# assign each product to the plant that makes it
products["Site"] = [sites[i] for i in rng.integers(0, len(sites), len(products))]
site_of = dict(zip(products.ProductName, products.Site))

# date range and a seasonal weighting (winter busier) matching the sales years
dates = pd.date_range("2017-01-01", "2020-12-31", freq="D")
month_weight = np.array([1.35,1.30,1.15,.95,.85,.80,.78,.82,.95,1.10,1.20,1.30])
w = month_weight[dates.month.values - 1]; w = w / w.sum()

ISO = lambda d: d.strftime("%Y-%m-%d")   # write dates in one clean format

# ---------------------------------------------------------------------
# 2. Helper functions to add REALISTIC data-quality problems on purpose,
#    so the ETL process has real cleaning to do (whitespace, mixed case).
# ---------------------------------------------------------------------
def messy_case(v):                       # randomly upper/lower/leave a value
    r = rng.random()
    return v.upper() if r < .25 else (v.lower() if r < .5 else v)
def pad(v):                              # sometimes add stray spaces
    return (" " + str(v) + "  ") if rng.random() < .25 else str(v)

# ---------------------------------------------------------------------
# 3. SHIPMENTS: MediFlow ships finished products to its distributors.
#    On-time delivery is calibrated to ~88% (a realistic service level).
# ---------------------------------------------------------------------
N = 9000
order_date = pd.to_datetime(rng.choice(dates, N, p=w))
pi = rng.integers(0, len(products), N)          # a random product per row
di = rng.integers(0, len(distributors), N)      # a random distributor per row

scheduled = order_date + pd.to_timedelta(7, unit="D")     # 7-day promised SLA
on_time = rng.random(N) < 0.88                            # 88% delivered on time
early = rng.integers(0, 3, N); late = rng.integers(1, 9, N)
actual = pd.to_datetime(np.where(on_time,
            scheduled - pd.to_timedelta(early, unit="D"),  # on-time: on/before
            scheduled + pd.to_timedelta(late,  unit="D"))) # late: after

pn = [products.ProductName[i] for i in pi]
dn = [distributors[j] for j in di]
shipments = pd.DataFrame({
    "ShipmentID": ["SHP%06d" % (i+1) for i in range(N)],
    "OrderDate": [ISO(d) for d in order_date],
    "ProductName": [pad(x) for x in pn],
    "ProductClass": [products.ProductClass[i] for i in pi],
    "ManufacturingSite": [pad(messy_case(site_of[x])) for x in pn],
    "DistributorName": [pad(x) for x in dn],
    "Country": [country_of[x] for x in dn],
    "QuantityShipped": np.clip(rng.lognormal(4.6, 1, N).astype(int), 5, 6000).astype(object),
    "ShipmentMode": rng.choice(["Air","Truck","Ocean","Air Charter"], N).astype(object),
    "ScheduledDeliveryDate": [ISO(d) for d in scheduled],
    "ActualDeliveryDate": [ISO(d) for d in actual],
    "FreightCostUSD": rng.uniform(50, 5000, N).round(2).astype(object),
    "WeightKg": rng.uniform(5, 900, N).round(1).astype(object),
    "ShipmentStatus": [messy_case(x) for x in rng.choice(
        ["Delivered","Shipped","In Transit","Pending","Cancelled"], N, p=[.7,.1,.1,.06,.04])],
})
# inject some missing/invalid values and duplicates (real-world messiness)
shipments.loc[shipments.sample(frac=.03, random_state=1).index, "FreightCostUSD"] = "N/A"
shipments.loc[shipments.sample(frac=.02, random_state=2).index, "WeightKg"] = ""
shipments.loc[shipments.sample(n=40, random_state=3).index, "QuantityShipped"] = -rng.integers(1, 500, 40)
shipments.loc[shipments.sample(frac=.04, random_state=4).index, "ShipmentMode"] = ""
shipments = pd.concat([shipments, shipments.sample(n=55, random_state=5)], ignore_index=True)  # duplicates
shipments.to_csv("raw_shipments.csv", index=False)

# ---------------------------------------------------------------------
# 4. INVENTORY: snapshots of MediFlow's finished-goods stock.
#    Stock-out rate is calibrated to a realistic ~5%.
# ---------------------------------------------------------------------
M = 3000
snapshot = pd.to_datetime(rng.choice(dates, M, p=w))
pi = rng.integers(0, len(products), M)
expiry = snapshot + pd.to_timedelta(rng.integers(60, 1100, M), unit="D")   # shelf life
storage = rng.choice(["room temperature","Refrigerated","controlled substance","Frozen"], M).astype(object)
# stock-out flag mostly "No"/"FALSE" so the stock-out rate stays realistic (~5%)
flag = rng.choice(["Yes","No","TRUE","FALSE","1","0"], M, p=[.02,.60,.005,.30,.005,.07])
pn = [products.ProductName[i] for i in pi]

inventory = pd.DataFrame({
    "RecordID": ["INV%06d" % (i+1) for i in range(M)],
    "SnapshotDate": [ISO(d) for d in snapshot],
    "ProductName": [pad(x) for x in pn],
    "ProductClass": [products.ProductClass[i] for i in pi],
    "ManufacturingSite": [pad(messy_case(site_of[x])) for x in pn],
    "BatchNumber": ["B"+d.strftime("%y%m")+"-%04d" % n for d, n in zip(snapshot, rng.integers(1, 9999, M))],
    "ExpiryDate": [ISO(d) for d in expiry],
    "StorageCondition": [pad(messy_case(x)) for x in storage],
    "WarehouseCountry": [site_country[site_of[x]] for x in pn],
    "QuantityOnHand": rng.integers(200, 10000, M).astype(object),   # usually well above reorder
    "ReorderLevel": rng.integers(50, 400, M).astype(object),
    "StockoutFlag": flag,
})
inventory.loc[inventory.sample(frac=.02, random_state=6).index, "QuantityOnHand"] = "N/A"
inventory.loc[inventory.sample(frac=.02, random_state=7).index, "ReorderLevel"] = ""
inventory = pd.concat([inventory, inventory.sample(n=45, random_state=8)], ignore_index=True)  # duplicates
inventory.to_csv("raw_inventory.csv", index=False)

print("Done. Wrote raw_shipments.csv (%d rows) and raw_inventory.csv (%d rows)."
      % (len(shipments), len(inventory)))
