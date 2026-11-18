#!/bin/sh

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
FILEPREFIX=sqlite-amalgamation
FILE=$FILEPREFIX-$1
ZIP=$(find_archive "$ARCHIVE/$FILE") || ZIP=
ISOSX=`uname`

if [ -z "$ZIP" ] || [ ! -e "$ZIP" ]; then
  echo Error: $ZIP not found!
  LS=`ls $ARCHIVE/$FILEPREFIX* 2>/dev/null`
  if [ ! -z "$LS" ]; then
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
  OS_FLAGS=-DSQLITE_OS_UNIX
  if [ "$BUILD_PLATFORM" = windows ]; then
    OS_FLAGS=
  fi
  "$CC" -O3 -mtune=$2 \
    -DSQLITE_DEFAULT_AUTOVACUUM=2 -DSQLITE_TEMP_STORE=2 \
    -DSQLITE_ENABLE_NULL_TRIM $OS_FLAGS -DSQLITE_OMIT_LOAD_EXTENSION \
    -DSQLITE_OMIT_WAL -DSQLITE_OMIT_UTF16 -DSQLITE_OMIT_DEPRECATED \
    -DSQLITE_THREADSAFE -DSQLITE_ENABLE_MATH_FUNCTIONS \
    -c sqlite3.c
  if [ ! $? -eq 0 ]; then
    exit 5;
  fi

  rm -rfv "sqlite64-${1}-${2}.a" 2>/dev/null

  "$AR" rcs "sqlite64-${1}-${2}.a" sqlite3.o
  if [ ! $? -eq 0 ]; then
    exit 6;
  fi

  rm -rfv sqlite3.o 2>/dev/null
}


if [ "$BUILD_PLATFORM" = windows ]; then
  build x86_64 generic
  publish_library sqlite64-x86_64-generic.a sqlite64.la libsqlite3.a
elif [ $ISOSX = 'Darwin' ]; then
  build x86_64 generic
  build arm64 apple-m1
  lipo sqlite64*.a -create -output "${LIB}/sqlite64.ma"
else
  build x86_64 generic
  cp -f sqlite64*.a "${LIB}/sqlite64.la"
fi

if [ ! $? -eq 0 ]; then
  exit 7;
fi

install_headers "$INCLUDE_ROOT/sql" \
  "$BASE/$FILE/sqlite3.h" "$BASE/$FILE/sqlite3ext.h" || exit 8
