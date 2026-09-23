#!/usr/bin/env bash
# Fixture: an existing harness with one domain, two area notes that declare paths: and
# no kind:, one conceptual note, and rules/ holding only memory.md. Runs in the case
# workspace.
set -euo pipefail

mkdir -p jobs src/webhooks .agents/memory .agents/rules

cat > AGENTS.md <<'EOF'
# Notes service — Agent Guide

## Memory Catalog

Persistent instructions live in `./.agents/memory/`. Index:
[.agents/memory/MEMORY.md](.agents/memory/MEMORY.md).

Notes and rules under `.agents/` are written in English (`en`).
EOF

cat > jobs/cleanup.py <<'EOF'
def run(db):
    # Soft-deleted rows are kept 30 days for the audit export; never hard-delete earlier.
    db.execute("DELETE FROM notes WHERE deleted_at < now() - interval '30 days'")
EOF

cat > src/webhooks/receive.py <<'EOF'
def receive(request, secret):
    # The signature is checked on the raw body, before any JSON parsing.
    return verify(request.body, request.headers["X-Signature"], secret)
EOF

cat > .agents/memory/MEMORY.md <<'EOF'
# Notes service — index

- [Conventions](conventions.md) — errors are returned, not raised, across modules.
- [Scheduled jobs](jobs.md) — why cleanup waits 30 days.
- [Incoming webhooks](webhooks.md) — signature on the raw body.
EOF

cat > .agents/memory/conventions.md <<'EOF'
# Conventions

Back to the [index](MEMORY.md).

Errors are returned, not raised, across module boundaries.
EOF

cat > .agents/memory/jobs.md <<'EOF'
---
paths:
  - "jobs/**"
---

# Scheduled jobs

Back to the [index](MEMORY.md).

`cleanup` hard-deletes notes soft-deleted more than 30 days ago; the audit export reads
them until then.
EOF

cat > .agents/memory/webhooks.md <<'EOF'
---
paths:
  - "src/webhooks/**"
---

# Incoming webhooks

Back to the [index](MEMORY.md).

The signature is verified on the raw body; parsing first changes the bytes.
EOF

cat > .agents/rules/memory.md <<'EOF'
# Memory — keep the notes in sync with the code

- Before changing code in an area, read the note that covers it — index:
  `.agents/memory/MEMORY.md`.
EOF

git init -q
git add -A
git -c user.name=eval -c user.email=eval@example.com commit -qm "feat: notes service"
