#!/bin/bash
# Copies client-safe Supabase/BFF configuration into the app bundle.
# Release archives must not depend on Xcode scheme environment variables.
set -euo pipefail

CONFIG_DIR="${SRCROOT}/TradeTraxs/Config"
DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Secrets.plist"

mkdir -p "$(dirname "${DEST}")"

copy_plist() {
    local source_path="$1"
    if [[ -f "${source_path}" ]]; then
        cp "${source_path}" "${DEST}"
        return 0
    fi
    return 1
}

if copy_plist "${CONFIG_DIR}/Secrets.plist"; then
    exit 0
fi

if copy_plist "${CONFIG_DIR}/Secrets.production.plist"; then
    exit 0
fi

if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_ANON_KEY:-}" ]]; then
    api_base_url="${API_BASE_URL:-https://www.tradetraxs.com}"
    cat > "${DEST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>SUPABASE_URL</key>
	<string>${SUPABASE_URL}</string>
	<key>SUPABASE_ANON_KEY</key>
	<string>${SUPABASE_ANON_KEY}</string>
	<key>API_BASE_URL</key>
	<string>${api_base_url}</string>
</dict>
</plist>
EOF
    exit 0
fi

if [[ "${CONFIGURATION}" == "Release" ]]; then
    echo "error: Release build is missing client configuration." >&2
    echo "Provide one of:" >&2
    echo "  TradeTraxs/Config/Secrets.plist" >&2
    echo "  TradeTraxs/Config/Secrets.production.plist" >&2
    echo "  SUPABASE_URL + SUPABASE_ANON_KEY build environment variables" >&2
    exit 1
fi

cp "${CONFIG_DIR}/Secrets.example.plist" "${DEST}"
