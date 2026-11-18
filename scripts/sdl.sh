#!/bin/sh

# This file is part of the Mhatxotic Engine source repository.
# @ https://github.com/Mhatxotic/Engine
# Copyright (c) Mhatxotic Design, 2006-present. All Rights Reserved.

if [ -z $1 ]; then
  echo Usage: $0 [version]
  exit 1
fi

SCRIPT_DIR=$(readlink -f "$0")
BASE=$(dirname $(dirname "$SCRIPT_DIR"))
cd "$BASE" || exit 1

. "$BASE/scripts/common.sh" || exit 1
ISOSX=`uname`
if [ $ISOSX = 'Darwin' ]; then
  ISOSX=1
  EXTRA=-D"CMAKE_OSX_DEPLOYMENT_TARGET=10.9"
else
  ISOSX=0
fi
ARCHIVE=$BASE/archive
LIB=$LIB_DIR
FILEPREFIX=sdl2-
FILE=$FILEPREFIX$1
ZIP=$(find_archive "$ARCHIVE/$FILE") || ZIP=

if [ -z "$ZIP" ] || [ ! -e "$ZIP" ]; then
  echo Error: $ZIP not found!
  LS=`echo $ARCHIVE/$FILEPREFIX* 2>/dev/null`
  if [ ! -z "${LS}" ]; then
    echo Available files...
    echo $LS | tr " " "\n"
  fi
  exit 2
fi

extract_if_missing "$FILE" "$ZIP"
if [ ! $? -eq 0 ]; then
  exit 3
fi

cd $FILE
if [ ! $? -eq 0 ]; then
  exit 5
fi

build()
{
  BUILDDIR="build-${TARGET_TAG}-${1}"
  rm -rfv "$BUILDDIR" 2>/dev/null
  mkdir -p "$BUILDDIR" 2>/dev/null
  cd "$BUILDDIR"
  if [ ! $? -eq 0 ]; then
    exit 6
  fi

  cmake_configure -D"CMAKE_BUILD_TYPE=Release" \
        -D"CMAKE_C_FLAGS=-mtune=${2}" \
        $EXTRA \
        -D"SDL_SHARED=OFF" \
        -D"SDL_STATIC=ON" \
        -D"SDL_TEST=OFF" \
        -D"SDL_BUILD_TESTS=OFF" \
        -D"SDL_TESTS=OFF" \
        -D"SDL_INSTALL_TESTS=OFF" \
        $3 \
        ..
  if [ ! $? -eq 0 ]; then
    exit 7
  fi

  make -j"$BUILD_JOBS"
  if [ ! $? -eq 0 ]; then
    exit 8
  fi

  mv "libSDL2.a" "../libSDL2-${1}-${2}.a"
  if [ ! $? -eq 0 ]; then
    exit 9
  fi

  cd ..
  if [ ! $? -eq 0 ]; then
    exit 10
  fi
}

if [ "$BUILD_PLATFORM" = windows ]; then
  EXTRA=
  build x86_64 generic
  publish_library libSDL2-x86_64-generic.a sdl64.la libSDL2.a
elif [ $ISOSX -eq 1 ]; then
  build x86_64 generic -DCMAKE_OSX_ARCHITECTURES=x86_64
  build arm64 apple-m1
  lipo libSDL2-*.a -create -output "${LIB}/sdl64.ma"
else
  build x86_64 generic
  mv libSDL2-*.a "${LIB}/sdl64.la"
fi
if [ ! $? -eq 0 ]; then
  exit 11
fi

install_headers "$INCLUDE_ROOT/SDL2" "$BASE/$FILE/include"/*.h || exit 12
