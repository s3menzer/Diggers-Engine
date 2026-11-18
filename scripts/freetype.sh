#!/bin/sh

# This file is part of the Mhatxotic Engine source repository.
# @ https://github.com/Mhatxotic/Engine
# Copyright (c) Mhatxotic Design, 2006-present. All Rights Reserved.

if [ -z $3 ]; then
  echo Usage: $0 [version] [zlibversion] [pngversion]
  exit 1
fi

SCRIPT_DIR=$(readlink -f "$0")
BASE=$(dirname $(dirname "$SCRIPT_DIR"))
cd "$BASE" || exit 1

. "$BASE/scripts/common.sh" || exit 1
ARCHIVE=$BASE/archive
LIB=$LIB_DIR
INCLUDE=$INCLUDE_ROOT/ft
FILEPREFIX=freetype-
FILEPREFIX2=zlib-
FILEPREFIX3=libpng-
FILE=$FILEPREFIX$1
FILE2=$FILEPREFIX2$2
FILE3=$FILEPREFIX3$3
ZIP=$(find_archive "$ARCHIVE/$FILE") || ZIP=
ZIP2=$(find_archive "$ARCHIVE/$FILE2") || ZIP2=
ZIP3=$(find_archive "$ARCHIVE/$FILE3") || ZIP3=
ISOSX=`uname`

if [ -z "$ZIP" ] || [ ! -e "$ZIP" ]; then
  echo Error 1: $ZIP not found!
  LS=`ls $ARCHIVE/$FILEPREFIX* 2>/dev/null`
  if [ ! -z "${LS}" ]; then
    echo Available files...
    echo $LS
  fi
  exit 2
fi

if [ -z "$ZIP2" ] || [ ! -e "$ZIP2" ]; then
  echo Error 2: $ZIP2 not found!
  LS=`ls $ARCHIVE/$FILEPREFIX2* 2>/dev/null`
  if [ ! -z "${LS}" ]; then
    echo Available files...
    echo $LS
  fi
  exit 3
fi

if [ -z "$ZIP3" ] || [ ! -e "$ZIP3" ]; then
  echo Error 3: $ZIP3 not found!
  LS=`ls $ARCHIVE/$FILEPREFIX3* 2>/dev/null`
  if [ ! -z "${LS}" ]; then
    echo Available files...
    echo $LS
  fi
  exit 4
fi

extract_if_missing "$FILE" "$ZIP"
if [ ! $? -eq 0 ]; then exit 5; fi

extract_if_missing "$FILE2" "$ZIP2"
if [ ! $? -eq 0 ]; then exit 6; fi

extract_if_missing "$FILE3" "$ZIP3"
if [ ! $? -eq 0 ]; then exit 7; fi

cd $FILE
if [ ! $? -eq 0 ]; then exit 8; fi

ZLIBDIR=`realpath ../${FILE2}`
PNGDIR=`realpath ../${FILE3}`

build()
{
  BUILDDIR="build-${TARGET_TAG}-${1}"
  rm -rfv "$BUILDDIR" 2>/dev/null
  mkdir "$BUILDDIR" 2>/dev/null
  cd "$BUILDDIR"
  if [ ! $? -eq 0 ]; then exit 9; fi

  cmake_configure -D"CMAKE_BUILD_TYPE=Release" \
        -D"CMAKE_POLICY_VERSION_MINIMUM=3.5" \
        -D"CMAKE_C_FLAGS=-mtune=${2}" \
        -D"FT_DISABLE_HARFBUZZ=TRUE" \
        -D"FT_DISABLE_BZIP2=TRUE" \
        -D"FT_DISABLE_BROTLI=TRUE" \
        -D"FT_REQUIRE_ZLIB=TRUE" \
        -D"ZLIB_INCLUDE_DIR=${ZLIBDIR}" \
        -D"ZLIB_LIBRARY_RELEASE=${ZLIBDIR}/zlib64-${1}-${2}.a" \
        -D"FT_REQUIRE_PNG=TRUE" \
        -D"PNG_INCLUDE_DIR=${PNGDIR}" \
        -D"PNG_LIBRARY_RELEASE=${PNGDIR}/png64-${1}-${2}.a" \
        $4 \
        ..
  if [ ! -e Makefile ]; then exit 10; fi

  make -j"$BUILD_JOBS"
  if [ ! $? -eq 0 ]; then exit 11; fi

  mv -fv libfreetype.a "../ft64-${1}-${2}.a"
  if [ ! $? -eq 0 ]; then exit 12; fi

  cd ..
  if [ ! $? -eq 0 ]; then exit 13; fi
}

# Build for each platform
if [ "$BUILD_PLATFORM" = windows ]; then
  ZLIBDIR="$MINGW_PREFIX/include"
  PNGDIR="$MINGW_PREFIX/include/png"
  BUILDDIR="build-${TARGET_TAG}-x86_64"
  rm -rfv "$BUILDDIR" 2>/dev/null
  mkdir -p "$BUILDDIR" || exit 9
  cd "$BUILDDIR" || exit 9
  cmake_configure -D"CMAKE_BUILD_TYPE=Release" \
        -D"CMAKE_POLICY_VERSION_MINIMUM=3.5" \
        -D"CMAKE_C_FLAGS=-mtune=generic" \
        -D"FT_DISABLE_HARFBUZZ=TRUE" \
        -D"FT_DISABLE_BZIP2=TRUE" \
        -D"FT_DISABLE_BROTLI=TRUE" \
        -D"FT_REQUIRE_ZLIB=TRUE" \
        -D"ZLIB_INCLUDE_DIR=${ZLIBDIR}" \
        -D"ZLIB_LIBRARY_RELEASE=${MINGW_PREFIX}/lib/libz.a" \
        -D"FT_REQUIRE_PNG=TRUE" \
        -D"PNG_INCLUDE_DIR=${PNGDIR}" \
        -D"PNG_PNG_INCLUDE_DIR=${PNGDIR}" \
        -D"PNG_LIBRARY_RELEASE=${MINGW_PREFIX}/lib/libpng16.a" \
        "$BASE/$FILE"
  [ -e Makefile ] || exit 10
  make -j"$BUILD_JOBS" || exit 11
  mv -fv libfreetype.a ../ft64-x86_64-generic.a || exit 12
  cd "$BASE/$FILE" || exit 13
  publish_library ft64-x86_64-generic.a ft64.la libfreetype.a
elif [ $ISOSX = 'Darwin' ]; then
  build x86_64 generic 10.15
  build arm64 apple-m1 11.0

  # Join libraries together and put in place
  lipo ft64-*.a -create -output "${LIB}/ft64.ma"
else
  build x86_64 generic 10.15
  cp -f ft64-x86_64-generic.a "${LIB}/ft64.la"
fi

if [ $? -ne 0 ]; then exit 14; fi

install_headers "$INCLUDE" "$BASE/$FILE/include/ft2build.h" || exit 15
install_headers "$INCLUDE/freetype" "$BASE/$FILE/include/freetype" || exit 16
