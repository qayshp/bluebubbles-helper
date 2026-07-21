#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/BlueBubblesHelper"
BUILD_DIR="$ROOT_DIR/.build/tests"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

export DEVELOPER_DIR
mkdir -p "$BUILD_DIR"

SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
xcrun --sdk macosx clang \
    -fobjc-arc \
    -fmodules \
    -Wall \
    -Wextra \
    -Werror \
    -isysroot "$SDKROOT" \
    -mmacosx-version-min=15.0 \
    -I "$SOURCE_DIR" \
    "$SOURCE_DIR/FindMyFriendPayload.m" \
    "$ROOT_DIR/Tests/FindMyFriendPayloadTests.m" \
    -framework Foundation \
    -o "$BUILD_DIR/FindMyFriendPayloadTests"

"$BUILD_DIR/FindMyFriendPayloadTests"
