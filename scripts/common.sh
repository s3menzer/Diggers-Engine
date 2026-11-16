#!/bin/sh
# Shared helpers sourced by the third-party dependency build scripts.

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
  mkdir -p "$destination" || exit 1
  for source do
    if [ -d "$source" ]; then
      cp -R "$source"/. "$destination"/ || exit 1
    elif [ -f "$source" ]; then
      cp -f "$source" "$destination"/ || exit 1
    else
      echo "Error: header source not found: '$source'." >&2
      exit 1
    fi
  done
)
