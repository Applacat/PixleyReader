#!/bin/bash
# Fix XcodeGen bug: missing package back-reference for local packages
# See: https://github.com/yonaskolb/XcodeGen/issues/1549
#
# XcodeGen creates XCLocalSwiftPackageReference correctly but omits the
# required "package = <ref>" line in XCSwiftPackageProductDependency.
# This causes Xcode to show "Missing package product 'aimdRenderer'".
#
# Usage: Run after every `xcodegen generate`
#   xcodegen generate && bash scripts/fix-local-packages.sh

set -euo pipefail

PBXPROJ="AIMDReader.xcodeproj/project.pbxproj"

if [ ! -f "$PBXPROJ" ]; then
    echo "Error: $PBXPROJ not found. Run from PixleyWriter/ directory."
    exit 1
fi

# Find the GUID of the XCLocalSwiftPackageReference for aimdRenderer
LOCAL_REF=$(grep -oE '^[[:space:]]+[A-F0-9]+' <<< "$(grep 'XCLocalSwiftPackageReference "Packages/aimdRenderer"' "$PBXPROJ" | head -1)" | tr -d '[:space:]')

if [ -z "$LOCAL_REF" ]; then
    echo "Warning: Could not find XCLocalSwiftPackageReference for aimdRenderer"
    exit 1
fi

# Check if the fix is already applied
if grep -q "package = $LOCAL_REF" "$PBXPROJ"; then
    echo "Package reference already present, skipping."
    exit 0
fi

# Insert "package = <ref>;" before "productName = aimdRenderer;" in the
# XCSwiftPackageProductDependency section
sed -i '' "s/			productName = aimdRenderer;/			package = $LOCAL_REF \/* XCLocalSwiftPackageReference \"Packages\/aimdRenderer\" *\/;\n			productName = aimdRenderer;/" "$PBXPROJ"

# Verify fix was applied
if grep -q "package = $LOCAL_REF" "$PBXPROJ"; then
    echo "Fixed: Added package reference $LOCAL_REF to XCSwiftPackageProductDependency"
else
    echo "Error: Fix failed to apply"
    exit 1
fi
