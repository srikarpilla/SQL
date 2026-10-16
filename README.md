# Instacart Customer Retention & Churn Analytics

An end-to-end analytics project on **3.4 million real grocery orders**: a **Microsoft SQL Server** database, 20+ interview-style T-SQL analyses, SQL-engineered features, and a **Random Forest** model that predicts which customers are about to lapse.

> **Stack:** SQL Server (T-SQL) · Python · pandas · scikit-learn · SQLAlchemy/pyodbc · matplotlib · Streamlit

---

## Highlights

| | |
|---|---|
| Data scale | 3.4M orders, 32.4M order line items, 206,209 customers |
| SQL work | 21 analytical queries: joins, subqueries, CTEs, `CASE`, `RANK`, `ROW_NUMBER`, `LAG`, running totals |
| Performance | Query time cut from **X s to Y ms** with indexing (logical reads **A to B**) *(fill in your measured numbers)* |
| Model | Random Forest, **AUC 0.758**, **recall 74%** on lapsed customers (baseline logistic regression AUC 0.751) |
| Top churn drivers | Average gap between orders (50% importance), number of orders (29%) |

---

## Dataset

**Instacart Online Grocery Shopping Dataset (2017)**, real anonymized orders from Instacart.

- **Download (Kaggle mirror):** https://www.kaggle.com/datasets/yasserh/instacart-online-grocery-basket-analysis-dataset
- Six CSV files: `orders`, `order_products__prior`, `order_products__train`, `products`, `aisles`, `departments`
- About 200 MB zipped and over 1 GB unzipped
- Released for non-commercial and research use. The data is **not** included in this repository because of its size and license.

| Table | Rows |
|---|---|
| orders | 3,421,083 |
| order_products_prior | 32,434,489 |
| order_products_train | 1,384,617 |
| products | 49,688 |

**Dataset limitations (important for interpreting the results):**
- There are **no real dates or prices**, only `order_number` and `days_since_prior_order`.
- So retention is measured by **order number**, and "churn" is defined as a **lapse**: the customer's final gap between orders was **21 days or more**.

---

## Project structure

```
instacart-churn/
├── data/                     # CSVs go here (not committed)
├── sql/
│   ├── 01_schema.sql         # database and tables
│   ├── 02_load.sql           # BULK INSERT of the CSVs
│   ├── 03_indexes.sql        # indexes + performance benchmark
│   ├── 04_analysis.sql       # 21 interview-style queries
│   └── 05_features.sql       # RFM view + user_features table
├── src/
│   └── train.py              # model training and scoring
├── app/
│   └── dashboard.py          # Streamlit dashboard
├── docs/                     # plots and performance notes
├── requirements.txt
└── README.md
```

---

## How to run

### 1. Prerequisites
- SQL Server (Developer or Express edition) and SQL Server Management Studio (SSMS)
- [ODBC Driver 17 or 18 for SQL Server](https://learn.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server)
- Python 3.10+

### 2. Get the data
Download the dataset from the Kaggle link above, then unzip the six CSVs into `data/` (or `C:\data\` if you use the `BULK INSERT` paths in `02_load.sql`).

### 3. Build the database
Run these in SSMS, **making sure the `instacart` database is selected**:

```
sql/01_schema.sql   ->  sql/02_load.sql   ->  sql/03_indexes.sql   ->  sql/05_features.sql
```

Check the load:
```sql
SELECT COUNT(*) FROM orders;               -- 3,421,083
SELECT COUNT(*) FROM order_products_prior; -- 32,434,489
SELECT COUNT(*) FROM user_features;        -- 206,209
```

### 4. Train the model
```bash
pip install -r requirements.txt
python src/train.py
```
Edit the `SERVER=` value in the connection string at the top of `train.py` to match your SQL Server instance name. The script trains the models, saves plots to `docs/`, saves `model.joblib`, and writes churn scores to the `user_churn_scores` table.

### 5. Launch the dashboard
```bash
streamlit run app/dashboard.py
```

---

## What the SQL covers

`sql/04_analysis.sql` has 21 queries of the kind asked in interviews and exams:

| Topic | Examples |
|---|---|
| Aggregation | Orders per weekday, peak hours, average days between orders |
| `GROUP BY` / `HAVING` | Customers with 50+ orders, products ordered 10,000+ times |
| Joins | Best-selling products, items per department, products never ordered (`LEFT JOIN` anti-join) |
| Subqueries | Customers above the average order count, 2nd most popular product |
| `CASE WHEN` | Customer loyalty tiers, simple RFM segments |
| Window functions | `RANK` top products per department, `ROW_NUMBER` first order per customer, `LAG` basket-size change, running totals |
| CTEs | High-reorder-rate customers |
| Retention | Retention curve by order number, lapsed-customer count |

---

## Feature engineering (in T-SQL)

Features use **only prior orders** and the label comes from each customer's **final order**, which avoids data leakage.

| Feature | Meaning |
|---|---|
| `avg_gap` | Average days between orders |
| `n_orders` | Number of prior orders |
| `reorder_ratio` | Share of items that were reorders |
| `avg_basket` | Average items per order |
| `avg_hour` | Average hour of day for orders |
| `weekend_share` | Share of orders on weekends |

**Target (`lapsed`):** 1 if the final gap between orders was 21+ days. Lapse rate in the data: **41.6%**.

---

## Model and results

A stratified 80/20 split (41,242 test customers). A logistic regression baseline is compared against a Random Forest (`n_estimators=200`, `max_depth=12`, `min_samples_leaf=20`, `class_weight="balanced_subsample"`).

| Model | AUC |
|---|---|
| Logistic regression (baseline) | 0.751 |
| **Random Forest** | **0.758** |

Random Forest on the test set (lapsed class):

| Precision | Recall | F1 |
|---|---|---|
| 0.59 | 0.74 | 0.66 |

**Feature importance**

| Feature | Importance |
|---|---|
| avg_gap | 0.495 |
| n_orders | 0.287 |
| reorder_ratio | 0.116 |
| avg_basket | 0.043 |
| avg_hour | 0.034 |
| weekend_share | 0.025 |

Plots: `docs/feature_importance.png`, `docs/confusion_matrix.png`, `docs/roc_curve.png`.

**Out-of-fold scoring:** the churn scores stored in `user_churn_scores` come from 5-fold cross-validation, so each customer is scored by a model that never saw them in training. 5-fold out-of-fold AUC: **X** *(fill in from the script output)*.

---

## Performance tuning

Measured with `SET STATISTICS IO, TIME ON` and actual execution plans, on a cold cache.

| Query | Before indexes | After indexes |
|---|---|---|
| Orders for one customer joined to items | X s / A reads | Y ms / B reads |

*(Fill in with your own numbers and add a plan screenshot in `docs/`.)*

---

## Business recommendations

1. **Target customers whose average gap is lengthening.** Average gap between orders is the strongest churn signal, so trigger win-back messages when a customer's gap passes their own normal pattern.
2. **Prioritize recall for win-back campaigns.** The model catches about 74% of customers who lapse. A coupon sent to a false alarm costs little compared with losing a customer.
3. **Protect early-life customers.** Order count is the second-strongest driver, so onboarding offers for customers with few orders should have the highest return.
4. **Add recency features next.** *(Update this point with your results if you add `last_gap` and `recent_gap` features.)*

---

## Limitations

- No real timestamps: "churn" is a proxy (a long final gap), not a confirmed departure.
- No price data, so monetary value in RFM is approximated by item counts.
- The model uses six aggregate behavior features. Product-level and recency features would likely improve it.
- A Random Forest's feature importance can favor high-variance features, so treat the ranking as indicative.

---

## Credits

- Data: the Instacart Online Grocery Shopping Dataset (2017), via the Kaggle mirror linked above. Used here for non-commercial, educational purposes.

## Author

**[srikar pilla]** · [LinkedIn](https://linkedin.com/in/srikar-pilla-81179425a) · [GitHub](https://github.com/srikarpilla)
