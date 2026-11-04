#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
python3 scripts/verify_models.py

case "${1:-simulator}" in
  simulator) sdk=iphonesimulator; destination='generic/platform=iOS Simulator' ;;
  device) sdk=iphoneos; destination='generic/platform=iOS' ;;
  *) echo 'Usage: bash scripts/build.sh [simulator|device]' >&2; exit 2 ;;
esac

xcodebuild \
  -project Video_Lane_Test.xcodeproj \
  -scheme Video_Lane_Test \
  -configuration Release \
  -sdk "$sdk" \
  -destination "$destination" \
  -derivedDataPath "${ADAS_BUILD_ROOT:-$repo_root/DerivedData}" \
  CODE_SIGNING_ALLOWED=NO \
  build
