#!/bin/sh
# Shared helpers sourced by the third-party dependency build scripts.

HOST_PLATFORM=$(uname -s)
BUILD_TARGET=${BUILD_TARGET:-auto}
if [ "$BUILD_TARGET" = auto ]; then
  if [ -n "${MINGW_TARGET:-}" ]; then
    BUILD_TARGET=windows
  else
    BUILD_TARGET=native
  fi
fi

if [ "$BUILD_TARGET" = windows ] || [ "$BUILD_TARGET" = win64 ] || [ "$BUILD_TARGET" = mingw64 ]; then
  BUILD_PLATFORM=windows
  MINGW_TARGET=${MINGW_TARGET:-x86_64-w64-mingw32}
  MINGW_THREAD_MODEL=${MINGW_THREAD_MODEL:-}
  if [ -z "$MINGW_THREAD_MODEL" ] && \
     command -v "${MINGW_TARGET}-g++-posix" >/dev/null 2>&1; then
    MINGW_THREAD_MODEL=posix
  fi
  case "$MINGW_THREAD_MODEL" in
    "") MINGW_COMPILER_SUFFIX= ;;
    posix|win32) MINGW_COMPILER_SUFFIX="-$MINGW_THREAD_MODEL" ;;
    *)
      echo "Error: MINGW_THREAD_MODEL must be posix or win32." >&2
      return 1
      ;;
  esac
  TARGET_TAG=win64
  LIB_DIR=${LIB_DIR:-$BASE/lib/$TARGET_TAG}
  INCLUDE_ROOT=${INCLUDE_ROOT:-$BASE/include/$TARGET_TAG}
  MINGW_PREFIX=${MINGW_PREFIX:-$BASE/build-windows/sysroot}
  MINGW_TOOLCHAIN_FILE=${MINGW_TOOLCHAIN_FILE:-$BASE/scripts/mingw64-toolchain.cmake}
  CC=${MINGW_TARGET}-gcc${MINGW_COMPILER_SUFFIX}
  CXX=${MINGW_TARGET}-g++${MINGW_COMPILER_SUFFIX}
  AR=${MINGW_TARGET}-ar
  RANLIB=${MINGW_TARGET}-ranlib
  RC=${MINGW_TARGET}-windres
  for tool in "$CC" "$CXX" "$AR" "$RANLIB" "$RC"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "Error: MinGW tool '$tool' is required for BUILD_TARGET=windows." >&2
      return 1
    fi
  done
  COMPILER_TARGET=$("$CC" -dumpmachine 2>/dev/null || true)
  if [ "$COMPILER_TARGET" != "$MINGW_TARGET" ]; then
    echo "Error: '$CC' targets '$COMPILER_TARGET', expected '$MINGW_TARGET'." >&2
    return 1
  fi
  if [ ! -f "$MINGW_TOOLCHAIN_FILE" ]; then
    echo "Error: CMake toolchain file not found: '$MINGW_TOOLCHAIN_FILE'." >&2
    return 1
  fi
  mkdir -p "$LIB_DIR" "$INCLUDE_ROOT" "$MINGW_PREFIX/include" "$MINGW_PREFIX/lib"
  # Keep host pkg-config metadata out of cross builds. Target libraries and
  # headers are staged in MINGW_PREFIX as their build scripts complete.
  PKG_CONFIG_PATH=
  PKG_CONFIG_LIBDIR="$MINGW_PREFIX/lib/pkgconfig:$MINGW_PREFIX/share/pkgconfig:/usr/$MINGW_TARGET/lib/pkgconfig"
  PKG_CONFIG_SYSROOT_DIR="/usr/$MINGW_TARGET"
  export BUILD_PLATFORM TARGET_TAG MINGW_TARGET MINGW_THREAD_MODEL MINGW_PREFIX MINGW_TOOLCHAIN_FILE
  export LIB_DIR INCLUDE_ROOT CC CXX AR RANLIB RC
  export PKG_CONFIG_PATH PKG_CONFIG_LIBDIR PKG_CONFIG_SYSROOT_DIR
else
  BUILD_PLATFORM=native
  TARGET_TAG=native
  LIB_DIR=${LIB_DIR:-$BASE/lib}
  INCLUDE_ROOT=${INCLUDE_ROOT:-$BASE/include}
  CC=${CC:-gcc}
  CXX=${CXX:-g++}
  AR=${AR:-ar}
  RANLIB=${RANLIB:-ranlib}
  mkdir -p "$LIB_DIR" "$INCLUDE_ROOT"
  export BUILD_PLATFORM TARGET_TAG LIB_DIR INCLUDE_ROOT CC CXX AR RANLIB
fi

if [ -n "${JOBS:-}" ]; then
  BUILD_JOBS=$JOBS
elif command -v nproc >/dev/null 2>&1; then
  BUILD_JOBS=$(nproc)
elif command -v getconf >/dev/null 2>&1; then
  BUILD_JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1')
elif command -v sysctl >/dev/null 2>&1; then
  BUILD_JOBS=$(sysctl -n hw.ncpu 2>/dev/null || printf '1')
else
  BUILD_JOBS=1
fi

case "$BUILD_JOBS" in
  ''|*[!0-9]*|0)
    echo "Error: JOBS must be a positive integer (got '$BUILD_JOBS')." >&2
    return 1
    ;;
esac

extract_if_missing() (
  if [ "$#" -ne 2 ]; then
    echo "Usage: extract_if_missing <destination> <archive>" >&2
    exit 2
  fi

  destination=$1
  archive=$2
  if [ -d "$destination" ]; then
    echo "Skipping extraction; '$destination' already exists."
    exit 0
  fi

  destination_parent=$(dirname "$destination")
  destination_name=$(basename "$destination")
  mkdir -p "$destination_parent"
  extract_dir=$(mktemp -d "$destination_parent/.$destination_name.extract.XXXXXX")
  cleanup() {
    if [ -n "$extract_dir" ]; then
      rm -rf "$extract_dir"
    fi
  }
  trap cleanup EXIT
  trap 'exit 1' HUP INT TERM

  case "$archive" in
    *.tar.gz|*.tgz)
      command -v tar >/dev/null 2>&1 || { echo "Error: tar is required to extract '$archive'." >&2; exit 1; }
      tar -xzf "$archive" -C "$extract_dir"
      ;;
    *.tar.xz|*.txz)
      command -v tar >/dev/null 2>&1 || { echo "Error: tar is required to extract '$archive'." >&2; exit 1; }
      tar -xJf "$archive" -C "$extract_dir"
      ;;
    *.tar.bz2|*.tbz2|*.tbz)
      command -v tar >/dev/null 2>&1 || { echo "Error: tar is required to extract '$archive'." >&2; exit 1; }
      tar -xjf "$archive" -C "$extract_dir"
      ;;
    *.tar)
      command -v tar >/dev/null 2>&1 || { echo "Error: tar is required to extract '$archive'." >&2; exit 1; }
      tar -xf "$archive" -C "$extract_dir"
      ;;
    *.zip)
      command -v unzip >/dev/null 2>&1 || { echo "Error: unzip is required to extract '$archive'." >&2; exit 1; }
      unzip -n -q "$archive" -d "$extract_dir"
      ;;
    *.7z)
      if command -v 7zz >/dev/null 2>&1; then
        7zz x -aos "$archive" "-o$extract_dir"
      elif command -v 7z >/dev/null 2>&1; then
        7z x -aos "$archive" "-o$extract_dir"
      else
        echo "Error: 7zz (or 7z) is required to extract '$archive'." >&2
        exit 1
      fi
      ;;
    *)
      echo "Error: unsupported archive extension: '$archive'." >&2
      exit 1
      ;;
  esac

  # Upstream archives often wrap their files in a version- or commit-named
  # directory. Flatten that one wrapper into the build script's destination.
  set -- "$extract_dir"/* "$extract_dir"/.[!.]* "$extract_dir"/..?*
  top_entry=
  entry_count=0
  for entry do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    top_entry=$entry
    entry_count=$((entry_count + 1))
  done
  if [ "$entry_count" -eq 0 ]; then
    echo "Error: archive '$archive' extracted no files." >&2
    exit 1
  fi
  if [ "$entry_count" -eq 1 ] && [ -d "$top_entry" ] && [ ! -L "$top_entry" ]; then
    mv "$top_entry" "$destination"
    rmdir "$extract_dir"
    extract_dir=
  else
    mv "$extract_dir" "$destination"
    extract_dir=
  fi
)

find_archive() {
  if [ "$#" -ne 1 ]; then
    echo "Usage: find_archive <archive-path-without-extension>" >&2
    return 2
  fi
  archive_stem=$1
  for archive_suffix in .tar.gz .tar.xz .tar.bz2 .tgz .txz .tbz2 .zip .7z .tar; do
    if [ -f "$archive_stem$archive_suffix" ]; then
      printf '%s\n' "$archive_stem$archive_suffix"
      return 0
    fi
  done
  return 1
}

cmake_configure() {
  # Every caller changes into a dedicated build directory and passes its
  # source directory as the final CMake argument. Make that build location
  # explicit so stale source-tree caches cannot silently redirect artifacts.
  cmake_source=
  for cmake_arg do cmake_source=$cmake_arg; done
  if [ -n "$cmake_source" ] && [ -d "$cmake_source" ]; then
    cmake_source=$(CDPATH= cd "$cmake_source" 2>/dev/null && pwd -P) || return 1
    if [ -f "$cmake_source/CMakeCache.txt" ]; then
      cache_dir=$(sed -n 's/^CMAKE_CACHEFILE_DIR:INTERNAL=//p' \
        "$cmake_source/CMakeCache.txt" | head -n 1)
      cache_source=$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' \
        "$cmake_source/CMakeCache.txt" | head -n 1)
      if [ "$cache_dir" = "$cmake_source" ] \
          && [ "$cache_source" = "$cmake_source" ]; then
        echo "Removing stale in-source CMake cache from '$cmake_source'." >&2
        rm -f "$cmake_source/CMakeCache.txt" || return 1
        rm -rf "$cmake_source/CMakeFiles" || return 1
      fi
    fi
  fi

  if [ "$BUILD_PLATFORM" = windows ]; then
    cmake \
      -B "$PWD" \
      -D"CMAKE_TOOLCHAIN_FILE=$MINGW_TOOLCHAIN_FILE" \
      -D"CMAKE_INSTALL_PREFIX=$MINGW_PREFIX" \
      -D"CMAKE_INSTALL_LIBDIR=lib" \
      -D"CMAKE_INSTALL_INCLUDEDIR=include" \
      -D"CMAKE_PREFIX_PATH=$MINGW_PREFIX" \
      -D"CMAKE_FIND_ROOT_PATH=/usr/$MINGW_TARGET;$MINGW_PREFIX" \
      -D"CMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER" \
      -D"CMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY" \
      -D"CMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY" \
      -D"CMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY" \
      "$@"
  else
    cmake -B "$PWD" "$@"
  fi
}

configure_target() {
  if [ "$BUILD_PLATFORM" = windows ]; then
    build_triplet=$(gcc -dumpmachine 2>/dev/null || printf '%s' x86_64-linux-gnu)
    ./configure --build="$build_triplet" --host="$MINGW_TARGET" "$@"
  else
    ./configure "$@"
  fi
}

publish_library() {
  if [ "$#" -lt 2 ]; then
    echo "Usage: publish_library <built-library> <output-name> [sysroot-name...]" >&2
    return 2
  fi
  built_library=$1
  output_name=$2
  shift 2
  if [ ! -f "$built_library" ]; then
    echo "Error: built library not found: '$built_library'." >&2
    return 1
  fi
  mkdir -p "$LIB_DIR"
  cp -f "$built_library" "$LIB_DIR/$output_name" || return 1
  if [ "$BUILD_PLATFORM" = windows ] && [ "$#" -gt 0 ]; then
    mkdir -p "$MINGW_PREFIX/lib"
    for sysroot_name do
      cp -f "$built_library" "$MINGW_PREFIX/lib/$sysroot_name" || return 1
    done
  fi
}

apply_patch_if_needed() (
  if [ "$#" -ne 2 ]; then
    echo "Usage: apply_patch_if_needed <patch-file> <source-directory>" >&2
    exit 2
  fi

  patch_file=$1
  source_dir=$2
  if [ ! -f "$patch_file" ]; then
    echo "Error: patch file not found: '$patch_file'." >&2
    exit 1
  fi
  if [ ! -d "$source_dir" ]; then
    echo "Error: patch target directory not found: '$source_dir'." >&2
    exit 1
  fi
  if ! command -v patch >/dev/null 2>&1; then
    echo "Error: patch is required to apply '$patch_file'." >&2
    exit 1
  fi

  reverse_output=$(LC_ALL=C patch --batch --dry-run --silent --reverse \
    -p1 -d "$source_dir" -i "$patch_file" 2>&1)
  reverse_status=$?
  if [ "$reverse_status" -eq 0 ] \
    && ! printf '%s\n' "$reverse_output" | grep -Fq "Unreversed patch detected"; then
    echo "Skipping patch; '$patch_file' is already applied."
    exit 0
  fi
  if ! patch --batch --dry-run --silent -p1 -d "$source_dir" -i "$patch_file"; then
    echo "Error: patch '$patch_file' does not apply cleanly to '$source_dir'." >&2
    exit 1
  fi
  patch --batch -p1 -d "$source_dir" -i "$patch_file"
)

install_headers() (
  if [ "$#" -lt 2 ]; then
    echo "Usage: install_headers <destination-directory> <header-file-or-directory>..." >&2
    exit 2
  fi

  destination=$1
  shift
  copy_headers_to() {
    copy_destination=$1
    shift
    mkdir -p "$copy_destination" || exit 1
    for copy_source do
      if [ -d "$copy_source" ]; then
        cp -R "$copy_source"/. "$copy_destination"/ || exit 1
      elif [ -f "$copy_source" ]; then
        cp -f "$copy_source" "$copy_destination"/ || exit 1
      else
        echo "Error: header source not found: '$copy_source'." >&2
        exit 1
      fi
    done
  }

  copy_headers_to "$destination" "$@"
  if [ "${BUILD_PLATFORM:-native}" = windows ]; then
    case "$destination" in
      "$INCLUDE_ROOT"/*)
        relative_destination=${destination#"$INCLUDE_ROOT"/}
        copy_headers_to "$MINGW_PREFIX/include/$relative_destination" "$@"
        ;;
    esac
  fi
)
