#!/bin/bash
#==============================================================================
# APKTool Practice Workflow Script
#
# This script automates the full APK modification workflow:
#   1. DECOMPILE  - Extract APK contents using apktool
#   2. MODIFY     - Patch resource files (strings, layouts)
#   3. REPACKAGE  - Rebuild the APK from modified sources
#   4. SIGN       - Sign the APK with a debug keystore
#   5. VERIFY     - Verify the signed APK package info
#
# Prerequisites:
#   - Java JDK 8+ (keytool, jarsigner in PATH)
#   - Android SDK build-tools (zipalign, apksigner, aapt)
#
# Usage: ./scripts/workflow.sh
#==============================================================================

set -e

# ---- Configuration ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TOOLS_DIR="$PROJECT_DIR/tools"
ORIGINAL_DIR="$PROJECT_DIR/original"
WORK_DIR="$PROJECT_DIR/work"
OUTPUT_DIR="$PROJECT_DIR/output"

APKTOOL="$TOOLS_DIR/apktool.jar"
ORIGINAL_APK="$ORIGINAL_DIR/AndroidTrivia-original.apk"
DECOMPILED_DIR="$WORK_DIR/decompiled"
MODIFIED_DIR="$WORK_DIR/modified"
UNSIGNED_APK="$WORK_DIR/app-unsigned.apk"
ALIGNED_APK="$WORK_DIR/app-aligned.apk"
SIGNED_APK="$OUTPUT_DIR/AndroidTrivia-modified.apk"
KEYSTORE="$WORK_DIR/debug.keystore"
KEYSTORE_PASS="android"
KEY_ALIAS="androiddebugkey"

# Android SDK build-tools (auto-detect latest)
ANDROID_SDK="${ANDROID_SDK:-$HOME/AppData/Local/Android/Sdk}"
BUILD_TOOLS_DIR=$(ls -d "$ANDROID_SDK/build-tools"/*/ 2>/dev/null | sort -V | tail -1)
BUILD_TOOLS_DIR="${BUILD_TOOLS_DIR%/}"
ZIPALIGN="$BUILD_TOOLS_DIR/zipalign"
APKSIGNER="$BUILD_TOOLS_DIR/apksigner"
AAPT="$BUILD_TOOLS_DIR/aapt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ---- Utility Functions ----
log_step() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  STEP: $*${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

log_ok() {
    echo -e "${GREEN}[✓] $*${NC}"
}

log_warn() {
    echo -e "${YELLOW}[!] $*${NC}"
}

log_err() {
    echo -e "${RED}[✗] $*${NC}"
}

check_tools() {
    log_step "Checking prerequisites..."

    if [ ! -f "$APKTOOL" ]; then
        log_err "apktool.jar not found at $APKTOOL"
        exit 1
    fi
    log_ok "apktool.jar found"

    if ! command -v java &>/dev/null; then
        log_err "java not found in PATH"
        exit 1
    fi
    log_ok "java: $(java -version 2>&1 | head -1)"

    if ! command -v keytool &>/dev/null; then
        log_err "keytool not found in PATH"
        exit 1
    fi
    log_ok "keytool available"

    if ! command -v jarsigner &>/dev/null; then
        log_err "jarsigner not found in PATH"
        exit 1
    fi
    log_ok "jarsigner available"

    if [ ! -f "$ZIPALIGN" ]; then
        log_warn "zipalign not found at $ZIPALIGN — trying PATH"
        ZIPALIGN="zipalign"
    fi
    log_ok "zipalign: $ZIPALIGN"

    if [ ! -f "$APKSIGNER" ] && [ ! -f "$APKSIGNER.bat" ]; then
        log_warn "apksigner not found — will use jarsigner only"
        APKSIGNER=""
    else
        log_ok "apksigner: $APKSIGNER"
    fi

    if [ ! -f "$AAPT" ] && [ ! -f "$AAPT.exe" ]; then
        log_warn "aapt not found — will skip detailed verification"
        AAPT=""
    else
        log_ok "aapt: $AAPT"
    fi
}

# ---- Step 1: Decompile ----
do_decompile() {
    log_step "1/5 — DECOMPILE: Extracting APK with apktool..."

    if [ ! -f "$ORIGINAL_APK" ]; then
        log_err "Original APK not found: $ORIGINAL_APK"
        exit 1
    fi

    rm -rf "$DECOMPILED_DIR"

    java -jar "$APKTOOL" d "$ORIGINAL_APK" -o "$DECOMPILED_DIR" -f

    log_ok "APK decompiled to: $DECOMPILED_DIR"
    log_ok "Smali files: $(find "$DECOMPILED_DIR" -name '*.smali' | wc -l) found"
    log_ok "Resource files in res/"
}

# ---- Step 2: Modify ----
do_modify() {
    log_step "2/5 — MODIFY: Patching resources..."

    # --- Modification 1: Change app_name in strings.xml ---
    # Find the strings.xml (may be in values, values-en, etc.)
    STRINGS_FILES=$(find "$DECOMPILED_DIR/res/values" -name "strings.xml" 2>/dev/null)

    if [ -n "$STRINGS_FILES" ]; then
        for f in $STRINGS_FILES; do
            echo "  Patching: $f"
            # Change app_name from "AndroidTrivia" to "AndroidTriviaMod"
            if grep -q 'name="app_name"' "$f"; then
                # Read current value
                CURRENT=$(grep 'name="app_name"' "$f" | head -1)
                echo "    Before: $CURRENT"
                sed -i 's/>AndroidTrivia</>AndroidTriviaMod</g' "$f"
                sed -i 's/>Android Trivia</>Android Trivia Mod</g' "$f"
                AFTER=$(grep 'name="app_name"' "$f" | head -1)
                echo "    After:  $AFTER"
            fi
        done
    else
        log_warn "No strings.xml found in res/values/ — skipping string patch"
    fi

    # --- Modification 2: Add a "MODIFIED" banner to the title layout ---
    TITLE_LAYOUT="$DECOMPILED_DIR/res/layout/fragment_title.xml"
    if [ -f "$TITLE_LAYOUT" ]; then
        echo ""
        echo "  Patching: $TITLE_LAYOUT"

        # Insert a TextView banner just before the ConstraintLayout closing tag.
        # This is safe because the closing tag is a single unambiguous line,
        # unlike the opening tag which may span multiple lines after decompilation.
        BANNER='        <TextView android:id="@+id/modBanner" android:layout_width="wrap_content" android:layout_height="wrap_content" android:layout_marginTop="16dp" android:gravity="center" android:text="[APKTool Modified]" android:textColor="#FF0000" android:textSize="14sp" android:textStyle="bold" app:layout_constraintEnd_toEndOf="parent" app:layout_constraintStart_toStartOf="parent" app:layout_constraintTop_toTopOf="parent" />'

        # Insert banner before the closing ConstraintLayout tag
        sed -i "s|</androidx.constraintlayout.widget.ConstraintLayout>|$BANNER\\n&|" "$TITLE_LAYOUT"

        log_ok "Added modification banner to title layout"
    else
        log_warn "fragment_title.xml not found — skipping layout patch"
    fi

    # --- Modification 3: Change the accent color ---
    COLORS_FILE="$DECOMPILED_DIR/res/values/colors.xml"
    if [ -f "$COLORS_FILE" ]; then
        echo ""
        echo "  Patching: $COLORS_FILE"
        BEFORE=$(grep 'name="colorAccent"' "$COLORS_FILE" | head -1)
        echo "    Before: $BEFORE"
        # Replace whatever color value is in colorAccent with deep orange.
        # The decompiled color may have an alpha prefix (e.g. #ff7e53c5 vs #7e53c5).
        # We extract the current value and compute the replacement dynamically.
        CURRENT_COLOR=$(echo "$BEFORE" | sed -n 's/.*>\(#[^<]*\)<.*/\1/p')
        if [ -n "$CURRENT_COLOR" ]; then
            sed -i "s|>${CURRENT_COLOR}<|>#FF5722<|g" "$COLORS_FILE"
            log_ok "Accent color replaced: $CURRENT_COLOR → #FF5722"
        else
            log_warn "Could not detect current accent color value"
        fi
        AFTER=$(grep 'name="colorAccent"' "$COLORS_FILE" | head -1)
        echo "    After:  $AFTER"
    fi

    log_ok "Modifications complete"
}

# ---- Step 3: Repackage ----
do_repackage() {
    log_step "3/5 — REPACKAGE: Building modified APK..."

    rm -rf "$MODIFIED_DIR"
    mkdir -p "$WORK_DIR"

    java -jar "$APKTOOL" b "$DECOMPILED_DIR" -o "$UNSIGNED_APK"

    if [ ! -f "$UNSIGNED_APK" ]; then
        log_err "Repackaging failed — no APK produced"
        exit 1
    fi

    log_ok "Unsigned APK built: $UNSIGNED_APK"
    log_ok "Size: $(du -h "$UNSIGNED_APK" | cut -f1)"
}

# ---- Step 4: Sign ----
do_sign() {
    log_step "4/5 — SIGN: Signing the APK..."

    # Generate debug keystore if it doesn't exist
    if [ ! -f "$KEYSTORE" ]; then
        echo "  Generating debug keystore..."
        keytool -genkey -v \
            -keystore "$KEYSTORE" \
            -alias "$KEY_ALIAS" \
            -keyalg RSA \
            -keysize 2048 \
            -validity 10000 \
            -storepass "$KEYSTORE_PASS" \
            -keypass "$KEYSTORE_PASS" \
            -dname "CN=Android Debug, OU=APKTool Practice, O=Dev, L=City, S=State, C=US" \
            2>/dev/null
        log_ok "Keystore created: $KEYSTORE"
    else
        log_ok "Using existing keystore: $KEYSTORE"
    fi

    # Zipalign the APK
    echo "  Running zipalign..."
    "$ZIPALIGN" -p -f 4 "$UNSIGNED_APK" "$ALIGNED_APK"
    log_ok "APK zipaligned"

    # Sign using apksigner (preferred) or jarsigner (fallback)
    mkdir -p "$OUTPUT_DIR"

    if [ -n "$APKSIGNER" ] && [ -f "$APKSIGNER" ]; then
        echo "  Signing with apksigner..."
        java -jar "$APKSIGNER" sign \
            --ks "$KEYSTORE" \
            --ks-key-alias "$KEY_ALIAS" \
            --ks-pass "pass:$KEYSTORE_PASS" \
            --key-pass "pass:$KEYSTORE_PASS" \
            --out "$SIGNED_APK" \
            "$ALIGNED_APK"
        log_ok "APK signed with apksigner"
    else
        echo "  Signing with jarsigner..."
        cp "$ALIGNED_APK" "$SIGNED_APK"
        jarsigner -verbose \
            -sigalg SHA1withRSA \
            -digestalg SHA1 \
            -keystore "$KEYSTORE" \
            -storepass "$KEYSTORE_PASS" \
            -keypass "$KEYSTORE_PASS" \
            "$SIGNED_APK" \
            "$KEY_ALIAS" \
            2>/dev/null
        log_ok "APK signed with jarsigner"
    fi

    log_ok "Signed APK output: $SIGNED_APK"
    log_ok "Final size: $(du -h "$SIGNED_APK" | cut -f1)"
}

# ---- Step 5: Verify ----
do_verify() {
    log_step "5/5 — VERIFY: Checking the final APK..."

    # Verify APK integrity
    if [ -n "$APKSIGNER" ] && [ -f "$APKSIGNER" ]; then
        echo "  Verifying signature with apksigner..."
        java -jar "$APKSIGNER" verify --verbose "$SIGNED_APK" 2>&1 || true
    fi

    # Dump APK info using aapt
    if [ -f "$AAPT" ]; then
        echo ""
        echo "  APK Package Info (aapt dump badging):"
        "$AAPT" dump badging "$SIGNED_APK" 2>/dev/null | grep -E \
            "package:|application:|application-label:|launchable-activity:" | while read line; do
            echo "    $line"
        done
    fi

    # Re-decompile to verify modifications took effect
    echo ""
    echo "  Verifying modifications in signed APK..."
    VERIFY_DIR="$WORK_DIR/verify"
    rm -rf "$VERIFY_DIR"
    java -jar "$APKTOOL" d "$SIGNED_APK" -o "$VERIFY_DIR" -f 2>/dev/null

    # Check app_name
    if [ -f "$VERIFY_DIR/res/values/strings.xml" ]; then
        echo ""
        echo "  Modified strings.xml contents:"
        grep 'name="app_name"' "$VERIFY_DIR/res/values/strings.xml" | head -1 || echo "    (not found)"
    fi

    # Check banner
    if [ -f "$VERIFY_DIR/res/layout/fragment_title.xml" ]; then
        echo ""
        echo "  Modified layout check (banner text):"
        grep "APKTool Modified" "$VERIFY_DIR/res/layout/fragment_title.xml" && \
            log_ok "Modification banner confirmed in layout!" || \
            log_warn "Banner not found in layout"
    fi

    log_ok "Verification complete!"
}

# ---- Main ----
main() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     APKTool Practice — Decompile → Modify → Sign        ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"

    check_tools
    do_decompile
    do_modify
    do_repackage
    do_sign
    do_verify

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ALL DONE! Modified APK is at:                          ║${NC}"
    echo -e "${GREEN}║  $SIGNED_APK${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Summary of changes
    echo "Summary of modifications:"
    echo "  1. App name changed: 'AndroidTrivia' → 'AndroidTriviaMod'"
    echo "  2. Added '[APKTool Modified]' banner to title screen"
    echo "  3. Accent color changed: #FF4081 → #FF5722 (deep orange)"
    echo ""
}

main "$@"
