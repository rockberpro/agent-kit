#!/usr/bin/env bash
# Fixture: a retailer backend with two business domains (billing, inventory) and one
# hand-off between them. Runs in the case workspace.
set -euo pipefail

mkdir -p src/billing src/inventory src/shared .agents/memory .agents/rules

cat > README.md <<'EOF'
# Shop backend

Billing and inventory for a small retailer. Python 3.11, PostgreSQL.
EOF

cat > AGENTS.md <<'EOF'
# Shop backend — Agent Guide

## Memory Catalog

Persistent instructions live in `./.agents/memory/`. Index:
[.agents/memory/MEMORY.md](.agents/memory/MEMORY.md).

Notes and rules under `.agents/` are written in English (`en`).
EOF

cat > schema.sql <<'EOF'
-- billing
CREATE TABLE invoice (id serial PRIMARY KEY, customer_id int NOT NULL,
  status text NOT NULL CHECK (status IN ('draft','issued','cancelled','paid')),
  total_cents int NOT NULL, issued_at timestamptz);
CREATE TABLE invoice_item (invoice_id int REFERENCES invoice, product_id int, qty int, price_cents int);
CREATE TABLE payment (id serial PRIMARY KEY, invoice_id int REFERENCES invoice, amount_cents int, paid_at timestamptz);
-- inventory
CREATE TABLE product (id serial PRIMARY KEY, sku text UNIQUE, name text);
CREATE TABLE warehouse (id serial PRIMARY KEY, name text);
CREATE TABLE stock_movement (id serial PRIMARY KEY, product_id int REFERENCES product,
  warehouse_id int REFERENCES warehouse, delta int NOT NULL, reason text NOT NULL, at timestamptz DEFAULT now());
EOF

cat > src/shared/db.py <<'EOF'
import os
import psycopg

def connect():
    return psycopg.connect(os.environ["DATABASE_URL"])
EOF

cat > src/billing/invoices.py <<'EOF'
from shared.db import connect
from inventory.stock import reserve

def issue(invoice_id):
    """Issue a draft invoice. Reserves stock for every item: billing hands off to inventory here."""
    with connect() as db:
        items = db.execute("SELECT product_id, qty FROM invoice_item WHERE invoice_id=%s", (invoice_id,)).fetchall()
        for product_id, qty in items:
            reserve(db, product_id, qty, reason=f"invoice:{invoice_id}")
        db.execute("UPDATE invoice SET status='issued', issued_at=now() WHERE id=%s AND status='draft'", (invoice_id,))

def change_total(invoice_id, total_cents):
    # Tax authority rule: an issued invoice is never edited. Cancel it and issue a new one.
    with connect() as db:
        status = db.execute("SELECT status FROM invoice WHERE id=%s", (invoice_id,)).fetchone()[0]
        if status != "draft":
            raise ValueError("issued invoices are immutable; cancel and reissue")
        db.execute("UPDATE invoice SET total_cents=%s WHERE id=%s", (total_cents, invoice_id))
EOF

cat > src/billing/payments.py <<'EOF'
from shared.db import connect

def register(invoice_id, amount_cents):
    with connect() as db:
        db.execute("INSERT INTO payment (invoice_id, amount_cents, paid_at) VALUES (%s,%s,now())", (invoice_id, amount_cents))
        paid = db.execute("SELECT coalesce(sum(amount_cents),0) FROM payment WHERE invoice_id=%s", (invoice_id,)).fetchone()[0]
        total = db.execute("SELECT total_cents FROM invoice WHERE id=%s", (invoice_id,)).fetchone()[0]
        if paid >= total:
            db.execute("UPDATE invoice SET status='paid' WHERE id=%s", (invoice_id,))
EOF

cat > src/inventory/stock.py <<'EOF'
def on_hand(db, product_id):
    return db.execute("SELECT coalesce(sum(delta),0) FROM stock_movement WHERE product_id=%s", (product_id,)).fetchone()[0]

def reserve(db, product_id, qty, reason):
    # stock_movement is a ledger: rows are only ever inserted, never updated or deleted.
    if on_hand(db, product_id) < qty:
        raise ValueError("stock cannot go negative")
    db.execute("INSERT INTO stock_movement (product_id, warehouse_id, delta, reason) VALUES (%s, 1, %s, %s)",
               (product_id, -qty, reason))
EOF

git init -q
git add -A
git -c user.name=eval -c user.email=eval@example.com commit -qm "feat: shop backend"
