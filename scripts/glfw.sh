#!/bin/bash

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

ARCHIVE=$BASE/archive
LIB=$LIB_DIR
FILEPREFIX=glfw-
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
        -D"GLFW_BUILD_DOCS=OFF" \
        -D"GLFW_BUILD_EXAMPLES=OFF" \
        -D"GLFW_BUILD_TESTS=OFF" \
        -D"BUILD_SHARED_LIBS=OFF" \
        $3 \
        ..
  if [ ! $? -eq 0 ]; then
    exit 7
  fi

  make -j"$BUILD_JOBS"
  if [ ! $? -eq 0 ]; then
    exit 8
  fi

  mv src/libglfw3.a "../glfw64-${1}-${2}.a"
  if [ ! $? -eq 0 ]; then
    exit 9
  fi

  cd ..
  if [ ! $? -eq 0 ]; then
    exit 10
  fi
}

ISOSX=`uname`
if [ "$BUILD_PLATFORM" = windows ]; then
  EXTRA="-DGLFW_BUILD_X11=OFF -DGLFW_BUILD_WAYLAND=OFF -DGLFW_BUILD_WIN32=ON"
  build x86_64 generic
  publish_library glfw64-x86_64-generic.a glfw64.la libglfw3.a
elif [ $ISOSX = 'Darwin' ]; then
  EXTRA="-DCMAKE_OSX_DEPLOYMENT_TARGET=10.15 -DCMAKE_OSX_ARCHITECTURES=x86_64"
  build x86_64 generic
  EXTRA="-DCMAKE_OSX_DEPLOYMENT_TARGET=11.0"
  build arm64 apple-m1
  lipo glfw64-*.a -create -output "${LIB}/glfw64.ma"
else
  build x86_64 generic
  mv glfw64-*.a "${LIB}/glfw64.la"
fi

if [ ! $? -eq 0 ]; then
  exit 11
fi

install_headers "$INCLUDE_ROOT/glfw" "$BASE/$FILE/include/GLFW" || exit 12
