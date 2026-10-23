#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
DERIVED_DATA="${PROJECT_ROOT}/Build/DerivedData"
OUTPUT_DIR="${PROJECT_ROOT}/Build/Local"
APP_PATH="${DERIVED_DATA}/Build/Products/Release/KleanBytes.app"
HELPER_PATH="${DERIVED_DATA}/Build/Products/Release/KleanBytesPrivilegedHelper"
PACKAGED_APP="${OUTPUT_DIR}/KleanBytes.app"
TEAM_ID="YOUR_TEAM_ID"

/bin/mkdir -p "${DERIVED_DATA}" "${OUTPUT_DIR}"

/usr/bin/xcodebuild \
    -project "${PROJECT_ROOT}/KleanBytes.xcodeproj" \
    -scheme KleanBytesPrivilegedHelper \
    -configuration Release \
    -derivedDataPath "${DERIVED_DATA}" \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CODE_SIGN_STYLE=Automatic \
    ENABLE_HARDENED_RUNTIME=YES \
    build

/usr/bin/xcodebuild \
    -project "${PROJECT_ROOT}/KleanBytes.xcodeproj" \
    -scheme KleanBytes \
    -configuration Release \
    -derivedDataPath "${DERIVED_DATA}" \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    CODE_SIGN_STYLE=Automatic \
    ENABLE_HARDENED_RUNTIME=YES \
    build

IDENTITY_HASH=$(/usr/bin/security find-identity -v -p codesigning \
    | /usr/bin/awk '/Apple Development/ { print $2; exit }')
if [[ -z "${IDENTITY_HASH}" ]]; then
    print -u2 "Не найден сертификат Apple Development."
    exit 1
fi

/bin/rm -rf "${PACKAGED_APP}"
/usr/bin/ditto "${APP_PATH}" "${PACKAGED_APP}"
/bin/mkdir -p \
    "${PACKAGED_APP}/Contents/Resources" \
    "${PACKAGED_APP}/Contents/Library/LaunchDaemons"
/usr/bin/ditto \
    "${HELPER_PATH}" \
    "${PACKAGED_APP}/Contents/Resources/KleanBytesPrivilegedHelper"
/usr/bin/ditto \
    "${PROJECT_ROOT}/KleanBytesPrivilegedHelper/com.alllyxer.KleanBytes.PrivilegedHelper.plist" \
    "${PACKAGED_APP}/Contents/Library/LaunchDaemons/com.alllyxer.KleanBytes.PrivilegedHelper.plist"

/usr/bin/codesign \
    --force \
    --sign "${IDENTITY_HASH}" \
    --options runtime \
    --identifier com.alllyxer.KleanBytes.PrivilegedHelper \
    "${PACKAGED_APP}/Contents/Resources/KleanBytesPrivilegedHelper"
/usr/bin/codesign \
    --force \
    --sign "${IDENTITY_HASH}" \
    --options runtime \
    --preserve-metadata=entitlements,requirements \
    "${PACKAGED_APP}"

/usr/bin/codesign --verify --deep --strict --verbose=2 "${PACKAGED_APP}"
print "Готово: ${PACKAGED_APP}"
