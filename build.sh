#!/bin/bash
# Perch -- build script
#
# Compiles the Objective-C source into a double-clickable .app bundle.
# Run this ONCE on your Snow Leopard Mac; the resulting .app appears here.
#
# Requirements:
#   Xcode 3.2+ with Command Line Tools (MacPorts already requires this)
#
# Usage:
#   chmod +x build.sh
#   ./build.sh

set -e

# Work in the directory containing this script
cd "$(dirname "$0")"

APP_BUNDLE="Perch.app"
BINARY="FrigateNative"

echo ""
echo "=== Perch -- Build ==="
echo ""

# --- Find a compiler ---
find_compiler() {
    for CC_CANDIDATE in \
        /Developer/usr/bin/clang \
        /usr/bin/clang \
        /opt/local/bin/clang \
        /Developer/usr/bin/gcc \
        /usr/bin/gcc-4.2 \
        /usr/bin/gcc \
        /opt/local/bin/gcc; do
        if [ -x "$CC_CANDIDATE" ]; then
            echo "$CC_CANDIDATE"
            return 0
        fi
    done
    return 1
}

CC=$(find_compiler) || {
    echo "ERROR: No C compiler found."
    echo "  Install Xcode 3.2 from your Snow Leopard install DVD."
    exit 1
}

echo "Compiler : $CC"
echo "Output   : $(pwd)/$APP_BUNDLE"
echo ""

# --- Check Cocoa framework ---
if [ ! -d "/System/Library/Frameworks/Cocoa.framework" ]; then
    echo "ERROR: Cocoa.framework not found."
    echo "  Make sure the full Xcode SDK is installed."
    exit 1
fi

# --- Create .app bundle ---
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# --- Compile ---
echo "Compiling..."

# Try clang first (-fblocks), fall back to gcc without it
"$CC" \
    -arch x86_64 \
    -mmacosx-version-min=10.6 \
    -framework Cocoa \
    -framework QTKit \
    -fblocks \
    -fobjc-exceptions \
    -O2 \
    -o "$APP_BUNDLE/Contents/MacOS/$BINARY" \
    main.m AppDelegate.m FrigateAPI.m SimpleJSON.m 2>/dev/null \
|| \
"$CC" \
    -arch x86_64 \
    -mmacosx-version-min=10.6 \
    -framework Cocoa \
    -framework QTKit \
    -fobjc-exceptions \
    -O2 \
    -o "$APP_BUNDLE/Contents/MacOS/$BINARY" \
    main.m AppDelegate.m FrigateAPI.m SimpleJSON.m

echo "Compiled OK"

# --- Copy Info.plist and PkgInfo ---
cp "Info.plist" "$APP_BUNDLE/Contents/Info.plist"
printf 'APPLFRG' > "$APP_BUNDLE/Contents/PkgInfo"

# --- Copy icon if present ---
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "Icon     : copied AppIcon.icns"
fi

# --- Done ---
echo ""
echo "Build succeeded!"
echo ""
echo "  App: $(pwd)/$APP_BUNDLE"
echo ""
echo "  Double-click 'Perch.app' to launch."
echo ""
