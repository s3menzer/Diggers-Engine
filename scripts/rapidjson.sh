#!/bin/sh

# This file is part of the Mhatxotic Engine source repository.
# @ https://github.com/Mhatxotic/Engine
# Copyright (c) Mhatxotic Design, 2006-present. All Rights Reserved.

if [ -z "${1:-}" ]; then
  echo "Usage: $0 [version] [optional-patch-relative-to-.build-helpers]"
  exit 1
fi

SCRIPT_DIR=$(readlink -f "$0")
BASE=$(dirname "$(dirname "$SCRIPT_DIR")")
cd "$BASE" || exit 1

. "$BASE/scripts/common.sh" || exit 1
ARCHIVE=$BASE/archive
FILEPREFIX=rapidjson-
FILE=$FILEPREFIX$1
ZIP=$(find_archive "$ARCHIVE/$FILE") || ZIP=
PATCH_FILE=
if [ -n "${2:-}" ]; then
  case "$2" in
    /*) PATCH_FILE=$2 ;;
    .build-helpers/*) PATCH_FILE=$BASE/$2 ;;
    *) PATCH_FILE=$BASE/.build-helpers/$2 ;;
  esac
  if [ ! -f "$PATCH_FILE" ]; then
    echo "Error: patch file '$PATCH_FILE' not found!" >&2
    exit 2
  fi
fi

if [ ! -e "$ZIP" ]; then
  echo "Error: $ZIP not found!" >&2
  LS=$(echo "$ARCHIVE/$FILEPREFIX"* 2>/dev/null)
  if [ -n "$LS" ]; then
    echo "Available files..."
    echo "$LS" | tr " " "\n"
  fi
  exit 2
fi

extract_if_missing "$FILE" "$ZIP"
if [ $? -ne 0 ]; then
  exit 3
fi

if [ -n "$PATCH_FILE" ]; then
  apply_patch_if_needed "$PATCH_FILE" "$BASE/$FILE"
  if [ $? -ne 0 ]; then
    exit 4
  fi
fi

cd "$FILE" || exit 5

# RapidJSON is header-only.
install_headers "$INCLUDE_ROOT/rapidjson" include/rapidjson
