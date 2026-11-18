#!/bin/sh

# This file is part of the Mhatxotic Engine source repository.
# @ https://github.com/Mhatxotic/Engine
# Copyright (c) Mhatxotic Design, 2006-present. All Rights Reserved.

if [ -z $2 ]; then
  echo Usage: $0 [version] [zlibversion]
  exit 1
fi

SCRIPT_DIR=$(readlink -f "$0")
BASE=$(dirname $(dirname "$SCRIPT_DIR"))
cd "$BASE" || exit 1

. "$BASE/scripts/common.sh" || exit 1
ARCHIVE=$BASE/archive
LIB=$LIB_DIR
FILEPREFIX=libpng-
FILEPREFIX2=zlib-
FILE=$FILEPREFIX$1
FILE2=$FILEPREFIX2$2
ZIP=$(find_archive "$ARCHIVE/$FILE") || ZIP=
ZIP2=$(find_archive "$ARCHIVE/$FILE2") || ZIP2=
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
  if [ ! -z $LS ]; then
    echo Available files...
    echo $LS
  fi
  exit 3
fi

extract_if_missing "$FILE" "$ZIP"
if [ ! $? -eq 0 ]; then
  exit 4
fi

extract_if_missing "$FILE2" "$ZIP2"
if [ ! $? -eq 0 ]; then
  exit 5
fi

cd $FILE
if [ ! $? -eq 0 ]; then
  exit 6
fi

ZLIBDIR=`realpath ../${FILE2}`

build()
{
  make clean 2>/dev/null

  if [ "$BUILD_PLATFORM" = windows ]; then
    CC="$CC" CFLAGS="-O3 -mtune=generic" \
      CPPFLAGS="-I$MINGW_PREFIX/include" \
      LDFLAGS="-L$MINGW_PREFIX/lib" \
      configure_target --disable-shared --enable-static \
        --with-zlib-prefix="$MINGW_PREFIX"
  elif [ $ISOSX = 'Darwin' ]; then
    ./configure --with-zlib-prefix="${ZLIBDIR}" \
                CC="gcc -O3 \
                -arch ${1} -mtune=${2} -mmacosx-version-min=10.15"
  else
    ./configure --with-zlib-prefix="${ZLIBDIR}" \
                CC="gcc -O3 "
  fi

  if [ ! $? -eq 0 ]; then
    cat config.log
    exit 7
  fi

  make -j"$BUILD_JOBS"
  if [ ! $? -eq 0 ]; then
    exit 8
  fi

  mv .libs/libpng16.a "png64-${1}-${2}.a"
  if [ ! $? -eq 0 ]; then
    exit 9
  fi
}

if [ "$BUILD_PLATFORM" = windows ]; then
  build x86_64 generic
  publish_library png64-x86_64-generic.a png64.la libpng16.a
elif [ $ISOSX = 'Darwin' ]; then
  build x86_64 generic
  build arm64 apple-m1
  lipo png64-*.a -create -output "${LIB}/png64.ma"
else
  build x86_64 generic
  cp -f png64-x86_64-generic.a "${LIB}/png64.la"
fi

if [ ! $? -eq 0 ]; then
  exit 10
fi

install_headers "$INCLUDE_ROOT/png" \
  "$BASE/$FILE/png.h" "$BASE/$FILE/pngconf.h" "$BASE/$FILE/pnglibconf.h" || exit 11
