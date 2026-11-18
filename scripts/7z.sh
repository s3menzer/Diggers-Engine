#!/bin/sh

# This file is part of the Mhatxotic Engine source repository.
# @ https://github.com/Mhatxotic/Engine
# Copyright (c) Mhatxotic Design, 2006-present. All Rights Reserved.

if [ -z "${1:-}" ]; then
  echo "Usage: $0 [version]" >&2
  exit 1
fi

SCRIPT_DIR=$(readlink -f "$0")
BASE=$(dirname "$(dirname "$SCRIPT_DIR")")
cd "$BASE" || exit 1

. "$BASE/scripts/common.sh" || exit 1

# This archive provides a Windows executable for the Wine-based MinGW build.
if [ "$BUILD_PLATFORM" != windows ]; then
  echo "Skipping Windows 7-Zip install for BUILD_TARGET=$BUILD_TARGET."
  exit 0
fi

case "$1" in
  ''|*[!0-9.]* )
    echo "Error: invalid 7-Zip version '$1'." >&2
    exit 2
    ;;
esac
VERSION_COMPACT=$(printf '%s' "$1" | tr -d '.')
case "$VERSION_COMPACT" in
  ''|*[!0-9]* )
    echo "Error: invalid 7-Zip version '$1'." >&2
    exit 2
    ;;
esac

ARCHIVE=$BASE/archive
FILE="7z${VERSION_COMPACT}-extra"
ZIP=$(find_archive "$ARCHIVE/$FILE") || ZIP=
if [ -z "$ZIP" ] || [ ! -f "$ZIP" ]; then
  echo "Error: 7-Zip archive '$ARCHIVE/$FILE.7z' not found." >&2
  exit 3
fi

if command -v 7zz >/dev/null 2>&1; then
  EXTRACTOR=$(command -v 7zz)
elif command -v 7z >/dev/null 2>&1; then
  EXTRACTOR=$(command -v 7z)
else
  echo "Error: 7zz (or 7z) is required to extract '$ZIP'." >&2
  exit 4
fi

DEST=$BASE/util
mkdir -p "$DEST" || exit 5
STAGING=$(mktemp -d "$DEST/.7z-extra.XXXXXX") || exit 5
cleanup() {
  if [ -n "$STAGING" ]; then
    rm -rf "$STAGING"
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

"$EXTRACTOR" x -y -aos "$ZIP" "-o$STAGING" >/dev/null || exit 6
SEVEN_ZIP_EXE=$(find "$STAGING" -type f -iname '7za.exe' -print -quit)
if [ -z "$SEVEN_ZIP_EXE" ]; then
  echo "Error: '$ZIP' did not contain 7za.exe." >&2
  exit 7
fi

# Preserve optional companion DLLs beside the renamed command-line executable.
SEVEN_ZIP_DIR=$(dirname "$SEVEN_ZIP_EXE")
for DLL in 7za.dll 7z.dll; do
  if [ -f "$SEVEN_ZIP_DIR/$DLL" ]; then
    cp -f "$SEVEN_ZIP_DIR/$DLL" "$DEST/$DLL" || exit 8
  fi
done
mv -f "$SEVEN_ZIP_EXE" "$DEST/7Z.EXE" || exit 8

echo "Installed Windows 7-Zip $1: $DEST/7Z.EXE"
