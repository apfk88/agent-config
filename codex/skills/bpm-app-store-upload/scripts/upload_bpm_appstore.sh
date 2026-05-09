#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: upload_bpm_appstore.sh [--no-upload] [--team-id TEAM_ID]

Run from /Users/kvamme/dev/personal/BPM.

Archives BPM.xcodeproj scheme BPM for generic iOS, then uploads the archive to
App Store Connect through Xcode's signed-in account unless --no-upload is set.
USAGE
}

NO_UPLOAD=0
TEAM_ID="${TEAM_ID:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-upload)
      NO_UPLOAD=1
      shift
      ;;
    --team-id)
      TEAM_ID="${2:-}"
      if [[ -z "$TEAM_ID" ]]; then
        echo "error: --team-id requires a value" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

PROJECT="BPM.xcodeproj"
SCHEME="BPM"
CONFIGURATION="Release"
DESTINATION="generic/platform=iOS"

if [[ ! -d "$PROJECT" ]]; then
  echo "error: run from the BPM repo root; missing $PROJECT" >&2
  exit 2
fi

if [[ -z "$TEAM_ID" ]]; then
  TEAM_ID="$(
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings 2>/dev/null \
      | awk '/^[[:space:]]*DEVELOPMENT_TEAM = / { print $3; exit }'
  )"
fi

if [[ -z "$TEAM_ID" ]]; then
  echo "error: could not infer DEVELOPMENT_TEAM; pass --team-id TEAM_ID" >&2
  exit 2
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_PATH="build/BPM-${STAMP}.xcarchive"
EXPORT_PATH="build/upload-${STAMP}"
UPLOAD_OPTIONS="build/UploadOptions-${STAMP}.plist"

mkdir -p build
printf '%s\n' "$STAMP" > build/.last-appstore-stamp

echo "Archiving BPM to ${ARCHIVE_PATH}"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  -allowProvisioningUpdates

if [[ "$NO_UPLOAD" -eq 1 ]]; then
  echo "Archive succeeded: ${ARCHIVE_PATH}"
  exit 0
fi

/usr/bin/plutil -create xml1 "$UPLOAD_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :method string app-store-connect" "$UPLOAD_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :destination string upload" "$UPLOAD_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :signingStyle string automatic" "$UPLOAD_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :teamID string ${TEAM_ID}" "$UPLOAD_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :stripSwiftSymbols bool true" "$UPLOAD_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :uploadSymbols bool true" "$UPLOAD_OPTIONS"

echo "Uploading BPM archive to App Store Connect"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$UPLOAD_OPTIONS" \
  -allowProvisioningUpdates

echo "Upload flow completed for ${ARCHIVE_PATH}"
