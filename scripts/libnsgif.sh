#!/bin/bash

# This file is part of the Mhatxotic Engine source repository.
# @ https://github.com/Mhatxotic/Engine
# Copyright (c) Mhatxotic Design, 2006-present. All Rights Reserved.

if [ -z $1 ]; then
  echo Usage: $0 [version]
  exit 1;
fi

SCRIPT_DIR=$(readlink -f "$0")
BASE=$(dirname $(dirname "$SCRIPT_DIR"))
cd "$BASE" || exit 1

. "$BASE/scripts/common.sh" || exit 1
ARCHIVE=$BASE/archive
LIB=$LIB_DIR
FILEPREFIX=libnsgif-
FILE=$FILEPREFIX$1
ZIP=$(find_archive "$ARCHIVE/$FILE") || ZIP=

if [ -z "$ZIP" ] || [ ! -e "$ZIP" ]; then
  echo Error: $ZIP not found!
  LS=`ls $ARCHIVE/$FILEPREFIX* 2>/dev/null`
  if [ ! -z "${LS}" ]; then
    echo Available files...
    echo $LS
  fi
  exit 2;
fi

extract_if_missing "$FILE" "$ZIP"
if [ ! $? -eq 0 ]; then
  exit 3;
fi

cd $FILE
if [ ! $? -eq 0 ]; then
  exit 4;
fi

build()
{
  "$CC" -O3 $ARCH$1 $EXTRA -Iinclude -c src/*.c

  if [ ! $? -eq 0 ]; then
    exit 5;
  fi

  rm -rfv "nsgif64-${1}-${2}.a" 2>/dev/null
  "$AR" rcs "nsgif64-${1}-${2}.a" *.o
  if [ ! $? -eq 0 ]; then
    exit 6;
  fi

  rm -rfv *.o
}

PLATFORM=$(uname)
if [ "$BUILD_PLATFORM" = windows ]; then
  ARCH="-D"
  EXTRA="-DWIN32 -D_WIN32"
  build x86_64 generic
  publish_library nsgif64-x86_64-generic.a nsgif64.la libnsgif.a
elif [ "$PLATFORM" == 'Linux' ]; then
  ARCH="-D"
  EXTRA=""
  build x86_64 generic
  cp -f nsgif64-*.a "${LIB}/nsgif64.la"
else
  ARCH="-arch "
  EXTRA="-mmacosx-version-min=10.15"
  build arm64 apple-m1
  build x86_64 generic
  lipo nsgif64-*.a -create -output "${LIB}/nsgif64.ma"
fi

if [ ! $? -eq 0 ]; then
  exit 7;
fi

install_headers "$INCLUDE_ROOT/gif" "$BASE/$FILE/include"/*.h || exit 8
