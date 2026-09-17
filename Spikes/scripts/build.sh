#!/bin/bash
# Builds the unsigned spike app into Spikes/build/Products/Livepaper.app.
# Each build gets a new CFBundleVersion so "build twice with a source change" (S0c)
# and "after a rebuild" (S0, S1) are real.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
VERSION=${1:-$(date +%Y%m%d%H%M%S)}
xcodebuild -project LivepaperSpike.xcodeproj -scheme Livepaper -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData \
  CURRENT_PROJECT_VERSION="$VERSION" -quiet build 2>&1 \
  | { grep -E "^/.*(error|warning):|^error:|BUILD (FAILED|SUCCEEDED)" || true; }
[ -d build/DerivedData/Build/Products/Release/Livepaper.app ] || { echo "build failed"; exit 1; }
rm -rf build/Products && mkdir -p build/Products
cp -R build/DerivedData/Build/Products/Release/Livepaper.app build/Products/
echo "built build/Products/Livepaper.app (version $VERSION)"
find build/Products/Livepaper.app -maxdepth 4 -name "*.appex"
