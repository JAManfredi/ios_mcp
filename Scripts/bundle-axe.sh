#!/bin/bash
# bundle-axe.sh — Download, verify, and package the axe accessibility engine for ios-mcp.
#
# Usage:
#   ./Scripts/bundle-axe.sh
#
# Environment variables:
#   AXE_VERSION   — axe release version (default: 0.4.0)
#   AXE_SHA256    — expected SHA-256 checksum of the downloaded archive
#   AXE_BASE_URL  — base URL for downloading axe releases
#
# The script:
#   1. Downloads a pinned axe release archive
#   2. Verifies SHA-256 checksum
#   3. Extracts to Vendor/axe/<version>/<arch>/
#   4. Fixes rpaths for framework loading
#   5. Ad-hoc codesigns the binary
#   6. Writes a checksum file for future verification

set -euo pipefail

# --- Configuration ---

AXE_VERSION="${AXE_VERSION:-0.4.0}"
AXE_SHA256="${AXE_SHA256:-}"
AXE_BASE_URL="${AXE_BASE_URL:-https://github.com/nicklama/axe/releases/download}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJECT_ROOT/Vendor/axe"

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
    arm64) ARCH_LABEL="arm64" ;;
    x86_64) ARCH_LABEL="x86_64" ;;
    *) echo "Error: Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

INSTALL_DIR="$VENDOR_DIR/$AXE_VERSION/$ARCH_LABEL"
DOWNLOAD_URL="$AXE_BASE_URL/v$AXE_VERSION/axe-$AXE_VERSION-$ARCH_LABEL.tar.gz"
ARCHIVE_NAME="axe-$AXE_VERSION-$ARCH_LABEL.tar.gz"
CHECKSUM_FILE="$INSTALL_DIR/.sha256"

# --- Functions ---

log() {
    echo "[bundle-axe] $*"
}

die() {
    echo "[bundle-axe] ERROR: $*" >&2
    exit 1
}

check_already_installed() {
    if [[ -f "$INSTALL_DIR/axe" && -f "$CHECKSUM_FILE" ]]; then
        log "axe $AXE_VERSION ($ARCH_LABEL) already installed at $INSTALL_DIR"
        log "To reinstall, remove $INSTALL_DIR and re-run."
        exit 0
    fi
}

download_archive() {
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    local archive_path="$tmp_dir/$ARCHIVE_NAME"

    log "Downloading axe $AXE_VERSION for $ARCH_LABEL..."
    log "URL: $DOWNLOAD_URL"

    if command -v curl &>/dev/null; then
        curl --fail --location --silent --show-error --output "$archive_path" "$DOWNLOAD_URL"
    elif command -v wget &>/dev/null; then
        wget --quiet --output-document="$archive_path" "$DOWNLOAD_URL"
    else
        die "Neither curl nor wget found. Install one and retry."
    fi

    if [[ ! -f "$archive_path" ]]; then
        die "Download failed — archive not found at $archive_path"
    fi

    echo "$archive_path"
}

verify_checksum() {
    local archive_path="$1"

    if [[ -z "$AXE_SHA256" ]]; then
        log "WARNING: No AXE_SHA256 provided — skipping checksum verification."
        log "Set AXE_SHA256 env var for verified downloads."
        return 0
    fi

    log "Verifying SHA-256 checksum..."
    local actual_sha256
    actual_sha256="$(shasum -a 256 "$archive_path" | awk '{print $1}')"

    if [[ "$actual_sha256" != "$AXE_SHA256" ]]; then
        die "Checksum mismatch!\n  Expected: $AXE_SHA256\n  Actual:   $actual_sha256"
    fi

    log "Checksum verified: $actual_sha256"
}

extract_archive() {
    local archive_path="$1"

    log "Extracting to $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
    tar xzf "$archive_path" -C "$INSTALL_DIR"

    if [[ ! -f "$INSTALL_DIR/axe" ]]; then
        # Archive might extract into a subdirectory — flatten if needed
        local nested
        nested="$(find "$INSTALL_DIR" -name "axe" -type f -perm +111 | head -1)"
        if [[ -n "$nested" ]]; then
            local nested_dir
            nested_dir="$(dirname "$nested")"
            if [[ "$nested_dir" != "$INSTALL_DIR" ]]; then
                mv "$nested_dir"/* "$INSTALL_DIR/" 2>/dev/null || true
                rmdir "$nested_dir" 2>/dev/null || true
            fi
        else
            die "axe binary not found after extraction"
        fi
    fi
}

fix_rpaths() {
    log "Fixing rpaths..."
    local binary="$INSTALL_DIR/axe"

    # Add @executable_path/Frameworks rpath if not already present
    if ! otool -l "$binary" 2>/dev/null | grep -q "@executable_path/Frameworks"; then
        install_name_tool -add_rpath "@executable_path/Frameworks" "$binary" 2>/dev/null || true
    fi

    # Fix any bundled dylibs/frameworks
    if [[ -d "$INSTALL_DIR/Frameworks" ]]; then
        find "$INSTALL_DIR/Frameworks" -name "*.dylib" -type f | while read -r dylib; do
            local dylib_name
            dylib_name="$(basename "$dylib")"
            install_name_tool -change \
                "/usr/local/lib/$dylib_name" \
                "@executable_path/Frameworks/$dylib_name" \
                "$binary" 2>/dev/null || true
        done
    fi
}

codesign_binary() {
    log "Ad-hoc codesigning..."
    codesign --force --sign - --timestamp=none "$INSTALL_DIR/axe"

    # Sign any bundled frameworks/dylibs
    if [[ -d "$INSTALL_DIR/Frameworks" ]]; then
        find "$INSTALL_DIR/Frameworks" \( -name "*.dylib" -o -name "*.framework" \) -type f | while read -r lib; do
            codesign --force --sign - --timestamp=none "$lib" 2>/dev/null || true
        done
    fi
}

write_checksum_file() {
    local archive_sha256
    archive_sha256="$(shasum -a 256 "$1" | awk '{print $1}')"

    log "Writing checksum file..."
    cat > "$CHECKSUM_FILE" <<EOF
# axe $AXE_VERSION ($ARCH_LABEL)
# Downloaded: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
archive_sha256=$archive_sha256
binary_sha256=$(shasum -a 256 "$INSTALL_DIR/axe" | awk '{print $1}')
EOF
}

# --- Main ---

main() {
    log "=== axe bundler for ios-mcp ==="
    log "Version: $AXE_VERSION | Arch: $ARCH_LABEL"

    check_already_installed

    # Download
    archive_path="$(download_archive)"

    # Override the trap set in download_archive to keep the file for now
    trap '' EXIT
    local tmp_dir
    tmp_dir="$(dirname "$archive_path")"
    trap 'rm -rf "$tmp_dir"' EXIT

    # Verify
    verify_checksum "$archive_path"

    # Extract
    extract_archive "$archive_path"

    # Fix rpaths
    fix_rpaths

    # Codesign
    codesign_binary

    # Record checksum
    write_checksum_file "$archive_path"

    log "=== Done ==="
    log "axe installed at: $INSTALL_DIR/axe"
    log "Run '$INSTALL_DIR/axe --version' to verify."
}

main "$@"
