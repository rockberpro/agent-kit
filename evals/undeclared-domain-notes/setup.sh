#!/usr/bin/env bash
# Fixture: an existing harness whose domain notes are not named domain-*.md and carry no
# kind:, with rules/ holding only memory.md. Runs in the case workspace.
set -euo pipefail

mkdir -p src/billing src/inventory .agents/memory .agents/rules

cat > AGENTS.md <<'EOF'
# Shop backend — Agent Guide

## Memory Catalog

Persistent instructions live in `./.agents/memory/`. Index:
[.agents/memory/MEMORY.md](.agents/memory/MEMORY.md).

Notes and rules under `.agents/` are written in English (`en`).
EOF

cat > src/billing/invoices.py <<'EOF'
def change_total(invoice_id, total_cents):
    # Tax authority rule: an issued invoice is never edited. Cancel it and issue a new one.
    raise PermissionError("issued invoices are immutable")
EOF

cat > src/inventory/stock.py <<'EOF'
def reserve(db, product_id, qty, reason):
    # stock_movement is append-only; stock never goes negative.
    db.execute("INSERT INTO stock_movement (product_id, delta, reason) VALUES (%s, %s, %s)",
               (product_id, -qty, reason))
EOF

cat > .agents/memory/MEMORY.md <<'EOF'
# Shop backend — index

- [Domains](domains.md) — the map: billing and inventory, and the hand-off between them.
- [Billing](billing.md) — invoices; an issued invoice is never edited.
- [Inventory](inventory.md) — append-only stock ledger.
EOF

cat > .agents/memory/domains.md <<'EOF'
# Domains

Back to the [index](MEMORY.md).

- **Billing** — [billing](billing.md). Issuing an invoice reserves stock.
- **Inventory** — [inventory](inventory.md). Owns stock_movement.
EOF

cat > .agents/memory/billing.md <<'EOF'
# Billing

Back to the [index](MEMORY.md). See also: [domains](domains.md).

Code in `src/billing/`. An issued invoice is never edited: cancel and reissue.
EOF

cat > .agents/memory/inventory.md <<'EOF'
# Inventory

Back to the [index](MEMORY.md). See also: [domains](domains.md).

Code in `src/inventory/`. `stock_movement` is append-only; stock never goes negative.
EOF

cat > .agents/rules/memory.md <<'EOF'
# Memory — keep the notes in sync with the code

- Before changing code in an area, read the note that covers it — index:
  `.agents/memory/MEMORY.md`.
EOF

git init -q
git add -A
git -c user.name=eval -c user.email=eval@example.com commit -qm "feat: shop backend"
