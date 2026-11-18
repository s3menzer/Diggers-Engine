#!/bin/sh

# This file is part of the Mhatxotic Engine source repository.
# @ https://github.com/Mhatxotic/Engine
# Copyright (c) Mhatxotic Design, 2006-present. All Rights Reserved.

if [ -z $1 ]; then
  echo Usage: $0 [version]
  exit 7
fi

SCRIPT_DIR=$(readlink -f "$0")
BASE=$(dirname $(dirname "$SCRIPT_DIR"))
cd "$BASE" || exit 1

. "$BASE/scripts/common.sh" || exit 1
ARCHIVE=$BASE/archive
LIB=$LIB_DIR
FILEPREFIX=zlib-
FILE=$FILEPREFIX$1
ZIP=$(find_archive "$ARCHIVE/$FILE") || ZIP=

if [ -z "$ZIP" ] || [ ! -e "$ZIP" ]; then
  echo Error: $ZIP not found!
  LS=`echo $ARCHIVE/$FILEPREFIX*`
  if [ ! -z "${LS}" ]; then
    echo Available files...
    echo $LS
  fi
  exit 8
fi

extract_if_missing "$FILE" "$ZIP"
if [ ! $? -eq 0 ]; then
  exit 9
fi

cd $FILE
if [ ! $? -eq 0 ]; then
  exit 10
fi

build()
{
  make clean 2>/dev/null


  if [ "$BUILD_PLATFORM" = windows ]; then
    CHOST="$MINGW_TARGET" ./configure --static
  else
    ./configure --static
  fi
              # --archs="-arch ${1}"
  if [ ! $? -eq 0 ]; then
    exit 11
  fi

  # mv -fv Makefile Makefile.patch
  # if [ ! $? -eq 0 ]; then
  #   exit 12
  # fi
  # cat Makefile.patch | \
  #   sed 's|-O3|-O3 -mtune='${2}' -mmacosx-version-min=10.15|g' > Makefile
  # if [ ! $? -eq 0 ]; then
  #   exit 13
  # fi

  make -j"$BUILD_JOBS" static
  if [ ! $? -eq 0 ]; then
    exit 14
  fi

  mv -fv libz.a "zlib64-${1}-${2}.a"
  if [ ! $? -eq 0 ]; then
    exit 15
  fi
}

build x86_64 generic
if [ "$BUILD_PLATFORM" = windows ]; then
  publish_library zlib64-x86_64-generic.a zlib64.la libz.a
else
  cp -f zlib64-x86_64-generic.a "${LIB}/zlib64.la" || exit 16
fi

install_headers "$INCLUDE_ROOT/zlib" \
  "$BASE/$FILE/zlib.h" "$BASE/$FILE/zconf.h" || exit 17
if [ "$BUILD_PLATFORM" = windows ]; then
  install_headers "$MINGW_PREFIX/include" \
    "$BASE/$FILE/zlib.h" "$BASE/$FILE/zconf.h" || exit 18
fi
