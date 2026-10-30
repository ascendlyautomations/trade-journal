#!/usr/bin/env python3
"""Backward-compatible entry: delegates to provision-prod-perf-accounts.py (15 users)."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

if __name__ == "__main__":
    target = Path(__file__).resolve().with_name("provision-prod-perf-accounts.py")
    raise SystemExit(subprocess.call([sys.executable, str(target)]))
