#!/usr/bin/env python3
"""Extract TradeTraxs platform hooks from a pg_dump of Supabase-managed schemas.

Input: schema-only dump of auth + storage (no storage.objects rows).
Output: SQL safe to apply on a fresh Supabase project after public/demo DDL.

Preserves: auth.users signup trigger, storage RLS policies, grants on storage tables.
Drops: CREATE SCHEMA/TABLE/TYPE/INDEX/FUNCTION owned by Supabase on managed schemas.
"""
from __future__ import annotations

import re
import sys
from typing import Iterable, List, Sequence

MANAGED_SCHEMAS = frozenset({"auth", "storage", "realtime", "graphql_public", "extensions"})

# Whole-statement exclusions (case-insensitive, first non-comment line).
_EXCLUDE_PATTERNS: Sequence[re.Pattern[str]] = (
    re.compile(r"^CREATE\s+SCHEMA\b", re.I),
    re.compile(r"^CREATE\s+TABLE\b", re.I),
    re.compile(r"^CREATE\s+SEQUENCE\b", re.I),
    re.compile(r"^CREATE\s+TYPE\b", re.I),
    re.compile(r"^CREATE\s+INDEX\b", re.I),
    re.compile(r"^CREATE\s+UNIQUE\s+INDEX\b", re.I),
    re.compile(r"^CREATE\s+FOREIGN\s+TABLE\b", re.I),
    re.compile(r"^CREATE\s+FUNCTION\b", re.I),
    re.compile(r"^CREATE\s+OR\s+REPLACE\s+FUNCTION\b", re.I),
    re.compile(r"^ALTER\s+TABLE\b", re.I),
    re.compile(r"^ALTER\s+TYPE\b", re.I),
    re.compile(r"^ALTER\s+SEQUENCE\b", re.I),
    re.compile(r"^ALTER\s+DEFAULT\s+PRIVILEGES\b", re.I),
    re.compile(r"^COMMENT\s+ON\b", re.I),
    re.compile(r"^REVOKE\b", re.I),
    re.compile(r"^ALTER\s+PUBLICATION\b", re.I),
    re.compile(r"^CREATE\s+PUBLICATION\b", re.I),
    re.compile(r"^CREATE\s+SUBSCRIPTION\b", re.I),
    re.compile(r"^CREATE\s+EVENT\s+TRIGGER\b", re.I),
    re.compile(r"^ALTER\s+EVENT\s+TRIGGER\b", re.I),
    re.compile(r"^CREATE\s+EXTENSION\b", re.I),
    re.compile(r"^ALTER\s+EXTENSION\b", re.I),
    re.compile(r"^SET\b", re.I),
    re.compile(r"^SELECT\s+pg_catalog\.set_config\b", re.I),
)

_STORAGE_POLICY = re.compile(r"^(?:DROP\s+POLICY|CREATE\s+POLICY)\b.*\bON\s+storage\.", re.I | re.S)
_STORAGE_GRANT = re.compile(
    r"^(?:GRANT|REVOKE)\b.*\bON\s+(?:TABLE\s+)?storage\.(?:objects|buckets)\b", re.I | re.S
)
_AUTH_USERS_TRIGGER = re.compile(
    r"^(?:DROP\s+TRIGGER|CREATE\s+TRIGGER|ALTER\s+TABLE)\b.*\bauth\.users\b", re.I | re.S
)
_AUTH_TRIGGER_NAME = re.compile(r"\bon_auth_user_created\b", re.I)


def split_sql_statements(sql: str) -> List[str]:
    """Split pg_dump plain SQL into statements, respecting dollar-quoted bodies."""
    statements: List[str] = []
    buf: List[str] = []
    in_dollar_body = False

    for raw_line in sql.splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()
        if not buf and (not stripped or stripped.startswith("--")):
            continue
        buf.append(line)

        if in_dollar_body:
            if stripped.endswith(";") and "$$" in stripped:
                statements.append("\n".join(buf).strip())
                buf = []
                in_dollar_body = False
            continue

        if re.search(r"\bAS\s+\$\$", line, re.I):
            in_dollar_body = True
            continue

        if stripped.endswith(";"):
            statements.append("\n".join(buf).strip())
            buf = []

    if buf:
        statements.append("\n".join(buf).strip())
    return statements


def _first_sql_line(statement: str) -> str:
    for line in statement.splitlines():
        s = line.strip()
        if not s or s.startswith("--"):
            continue
        return s
    return ""


def _managed_schema_reference(statement: str) -> bool:
    for schema in MANAGED_SCHEMAS:
        if re.search(rf"\b{re.escape(schema)}\.", statement, re.I):
            return True
    return False


def classify_statement(statement: str) -> str:
    """Return include, exclude, or error."""
    head = _first_sql_line(statement)
    if not head:
        return "exclude"

    if _STORAGE_POLICY.search(statement) or _STORAGE_GRANT.search(statement):
        return "include"

    if _AUTH_USERS_TRIGGER.search(statement) and _AUTH_TRIGGER_NAME.search(statement):
        return "include"

    for pat in _EXCLUDE_PATTERNS:
        if pat.search(head):
            return "exclude"

    if _managed_schema_reference(statement):
        return "error"

    return "exclude"


def filter_managed_dump(sql: str) -> str:
    included: List[str] = []
    errors: List[str] = []

    for stmt in split_sql_statements(sql):
        kind = classify_statement(stmt)
        if kind == "include":
            included.append(stmt)
        elif kind == "error":
            preview = _first_sql_line(stmt)[:120]
            errors.append(preview)

    if errors:
        msg = "unclassified managed-schema statements (refusing to drop silently):\n  - " + "\n  - ".join(
            errors[:20]
        )
        if len(errors) > 20:
            msg += f"\n  ... and {len(errors) - 20} more"
        raise SystemExit(msg)

    if not any(_AUTH_TRIGGER_NAME.search(s) for s in included):
        raise SystemExit("filtered output missing auth.on_auth_user_created trigger statements")

    if not any(_STORAGE_POLICY.search(s) for s in included):
        raise SystemExit("filtered output missing storage.objects/buckets policies")

    header = (
        "-- TradeTraxs platform custom hooks (generated; do not edit by hand)\n"
        "-- Apply after schema_application.sql on a fresh Supabase staging project.\n"
        "\\set ON_ERROR_STOP on\n\n"
    )

    def sort_key(s: str) -> tuple[int, str]:
        upper = s.lstrip().upper()
        if upper.startswith("DROP TRIGGER"):
            return (0, s)
        if upper.startswith("CREATE TRIGGER"):
            return (1, s)
        if upper.startswith("ALTER TABLE") and _AUTH_TRIGGER_NAME.search(s):
            return (2, s)
        if upper.startswith("DROP POLICY"):
            return (3, s)
        if upper.startswith("CREATE POLICY"):
            return (4, s)
        if upper.startswith("GRANT") or upper.startswith("REVOKE"):
            return (5, s)
        return (9, s)

    ordered = sorted(included, key=sort_key)
    body = "\n\n".join(ordered)
    if body and not body.endswith("\n"):
        body += "\n"
    return header + body


def main(argv: Sequence[str]) -> int:
    if len(argv) != 3:
        print("usage: split-managed-schema-dump.py <managed_raw.sql> <schema_platform_custom.sql>", file=sys.stderr)
        return 2
    raw_path, out_path = argv[1], argv[2]
    with open(raw_path, encoding="utf-8") as f:
        raw = f.read()
    filtered = filter_managed_dump(raw)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(filtered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
