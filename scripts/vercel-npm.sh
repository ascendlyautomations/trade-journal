#!/usr/bin/env bash
# Vercel sets NPM_CONFIG_CACHE_DIR for pnpm workspace caching. npm 11+ rejects
# the unknown `cache-dir` key (npm uses `cache`). Clear before invoking npm.
set -euo pipefail
unset npm_config_cache_dir NPM_CONFIG_CACHE_DIR 2>/dev/null || true
exec npm "$@"
