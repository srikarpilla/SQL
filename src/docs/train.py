import os
import urllib.parse
import joblib
import pandas as pd
import matplotlib.pyplot as plt
from sqlalchemy import create_engine
from sklearn.model_selection import train_test_split, cross_val_predict, StratifiedKFold
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import (roc_auc_score, f1_score, precision_score, recall_score,
                             classification_report, confusion_matrix,
                             ConfusionMatrixDisplay, RocCurveDisplay)
import matplotlib
matplotlib.use("Agg")      # save plots to files without opening a GUI window                             

os.makedirs("docs", exist_ok=True)

# ---------------------------------------------------------------
# 1. Connect to SQL Server and load the feature table
# ---------------------------------------------------------------
params = urllib.parse.quote_plus(
    "DRIVER={ODBC Driver 17 for SQL Server};"
    "SERVER=LAPTOP-1R5MTQFI;"      # change to your server name
    "DATABASE=instacart;"
    "Trusted_Connection=yes;"
    "TrustServerCertificate=yes;"
)
engine = create_engine("mssql+pyodbc:///?odbc_connect=" + params, fast_executemany=True)

df = pd.read_sql("SELECT * FROM user_features", engine).dropna()
X = df.drop(columns=["user_id", "lapsed"]).astype(float)
y = df["lapsed"].astype(int)

print("Rows:", len(df))
print("Lapse rate:", round(y.mean(), 3))

# ---------------------------------------------------------------
# 2. Train/test split (stratified keeps the class ratio)
# ---------------------------------------------------------------
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, stratify=y, random_state=42)

# ---------------------------------------------------------------
# 3. Baseline: Logistic Regression
# ---------------------------------------------------------------
baseline = make_pipeline(StandardScaler(), LogisticRegression(max_iter=1000))
baseline.fit(X_train, y_train)
base_proba = baseline.predict_proba(X_test)[:, 1]
print("\nBaseline (LogReg) AUC:", round(roc_auc_score(y_test, base_proba), 4))

# ---------------------------------------------------------------
# 4. Random Forest model
# ---------------------------------------------------------------
rf = RandomForestClassifier(
    n_estimators=200,
    max_depth=12,
    min_samples_leaf=20,
    class_weight="balanced_subsample",   # handles class imbalance
    n_jobs=-1,
    random_state=42)

rf.fit(X_train, y_train)

proba = rf.predict_proba(X_test)[:, 1]
pred = (proba >= 0.5).astype(int)

print("\n=== Random Forest results (test set) ===")
print("AUC      :", round(roc_auc_score(y_test, proba), 4))
print("F1       :", round(f1_score(y_test, pred), 4))
print("Precision:", round(precision_score(y_test, pred), 4))
print("Recall   :", round(recall_score(y_test, pred), 4))
print("\n", classification_report(y_test, pred))

# ---------------------------------------------------------------
# 5. Feature importance
# ---------------------------------------------------------------
imp = pd.Series(rf.feature_importances_, index=X.columns).sort_values()
print("Feature importance:\n", imp.sort_values(ascending=False).round(4))

imp.plot(kind="barh", title="Random Forest feature importance")
plt.tight_layout()
plt.savefig("docs/feature_importance.png")
plt.close()

# ---------------------------------------------------------------
# 6. Confusion matrix and ROC curve (for the README)
# ---------------------------------------------------------------
ConfusionMatrixDisplay(confusion_matrix(y_test, pred),
                       display_labels=["Active", "Lapsed"]).plot()
plt.savefig("docs/confusion_matrix.png")
plt.close()

RocCurveDisplay.from_estimator(rf, X_test, y_test, name="Random Forest")
RocCurveDisplay.from_estimator(baseline, X_test, y_test, name="Logistic Regression",
                               ax=plt.gca())
plt.title("ROC curve: Random Forest vs baseline")
plt.savefig("docs/roc_curve.png")
plt.close()

# ---------------------------------------------------------------
# 7. Out-of-fold churn risk for ALL users (honest scores for the dashboard)
#    Each user is scored by a model that never saw that user in training.
# ---------------------------------------------------------------
cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
oof = cross_val_predict(rf, X, y, cv=cv, method="predict_proba", n_jobs=1)[:, 1]
print("\n5-fold out-of-fold AUC:", round(roc_auc_score(y, oof), 4))

# ---------------------------------------------------------------
# 8. Save model and write scores back to SQL Server
# ---------------------------------------------------------------
rf.fit(X, y)                             # final model on all data
joblib.dump(rf, "model.joblib")

scores = pd.DataFrame({"user_id": df["user_id"].values, "churn_risk": oof})
scores.to_sql("user_churn_scores", engine, if_exists="replace", index=False)
print("Saved model.joblib and user_churn_scores table.")