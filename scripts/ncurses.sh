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
LIB=$BASE/lib
FILEPREFIX=ncurses-
FILE=$FILEPREFIX$1
ZIP=$ARCHIVE/$FILE.tar.gz
ISOSX=`uname`

if [ ! -e $ZIP ]; then
  echo Error: $ZIP not found!
  LS=`ls $ARCHIVE/$FILEPREFIX* 2>/dev/null`
  if [ ! -z $LS ]; then
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

  ./configure --prefix=/usr --without-cxx --without-cxx-binding \
    --without-ada --without-progs --without-curses-h --with-static \
    --without-debug --enable-widec --enable-const --enable-ext-colors \
    --enable-sigwinch --enable-wgetch-events
  if [ ! $? -eq 0 ]; then
    exit 11
  fi

  if [ $ISOSX = 'Darwin' ]; then

    find . -type f -name Makefile | while read -r FILE; do
      mv -fv $FILE $FILE.patch
      if [ ! $? -eq 0 ]; then
        exit 12
      fi
      cat $FILE.patch | \
        sed 's|-O2|-O3 -arch '${1}' -mtune='${2}' -mmacosx-version-min='${3}' -target '${1}'-apple-darwin -Wno-deprecated-declarations -Wno-c++11-extensions|g' > $FILE
      if [ ! $? -eq 0 ]; then
        exit 13
      fi
    done
  fi

  make -j"$BUILD_JOBS"
  if [ ! $? -eq 0 ]; then
    exit 14
  fi

  mv -fv lib/libncursesw.a "nc64-${1}-${2}.a"
  if [ ! $? -eq 0 ]; then
    exit 15
  fi
}

build x86_64 generic 10.15
if [ $ISOSX = 'Darwin' ]; then
  build arm64 apple-m1 11.0
  lipo nc64-*.a -create -output "${LIB}/nc64.ma"
else
  cp -f nc64-x86_64-generic.a "${LIB}/nc64.la"
fi

if [ ! $? -eq 0 ]; then
  exit 16
fi

# Keep the documented prefix, and also expose ncurses.h for Engine's bare include.
install_headers "$BASE/include/ncurses" "$BASE/$FILE/include/"*.h || exit 17
install_headers "$BASE/include" "$BASE/$FILE/include/"*.h || exit 18
cp -f "$BASE/include/curses.h" "$BASE/include/ncurses.h" || exit 19
