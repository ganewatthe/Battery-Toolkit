#!/bin/zsh
#
# Re-sign locally built Battery Toolkit components.
#
# Builds produced by `xcodebuild` with a free Apple ID certificate embed
# `com.apple.security.get-task-allow` and an `application-identifier`
# entitlement without a provisioning profile. macOS kills the root daemon
# at launch in that state ("Launch Constraint Violation"). Re-sign the
# components after installing to strip those entitlements.
#
# Usage: ./resign-local.sh [path-to-app]
#
set -e

APP="${1:-/Applications/Battery Toolkit.app}"
IDENT="${CODESIGN_IDENTITY:-Apple Development: ganewatthe@gmail.com (9UWFXKRQ68)}"
OPTS="-o hard,kill,restrict,enforce,library-validation,library,runtime"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Empty entitlements for the daemon and service.
printf '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict/></plist>' > "$TMP/empty.plist"

# Extract entitlements and remove get-task-allow.
extract_no_debug() { # $1=path $2=out
  codesign -d --entitlements - --xml "$1" 2>/dev/null > "$2" || true
  /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$2" 2>/dev/null || true
}

# 1. Daemon: no entitlements at all.
codesign --force --sign "$IDENT" ${=OPTS} --entitlements "$TMP/empty.plist" \
  "$APP/Contents/Library/LaunchServices/me.mhaeuser.batterytoolkitd"

# 2. XPC service.
extract_no_debug "$APP/Contents/XPCServices/Battery Toolkit Service.xpc" "$TMP/service.plist"
codesign --force --sign "$IDENT" ${=OPTS} --entitlements "$TMP/service.plist" \
  "$APP/Contents/XPCServices/Battery Toolkit Service.xpc"

# 3. Autostart helper (keeps sandbox).
extract_no_debug "$APP/Contents/Library/LoginItems/AutostartHelper.app" "$TMP/helper.plist"
codesign --force --sign "$IDENT" ${=OPTS} --entitlements "$TMP/helper.plist" \
  "$APP/Contents/Library/LoginItems/AutostartHelper.app"

# 4. Outer app (keeps app group).
extract_no_debug "$APP" "$TMP/app.plist"
codesign --force --sign "$IDENT" ${=OPTS} --entitlements "$TMP/app.plist" "$APP"

codesign --verify --deep --strict "$APP"
echo "Re-signed successfully."