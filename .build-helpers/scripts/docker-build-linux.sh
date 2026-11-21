#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HELPER_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd -- "${HELPER_ROOT}/.." && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'USAGE'
Usage: .build-helpers/scripts/docker-build-linux.sh

Builds Linux dependencies, then uses the Linux Makefile to compile the game,
refresh its assets, and create the distro package in the builder container.
USAGE
  exit 0
fi
if (($#)); then
  echo "Error: this build script does not accept positional arguments." >&2
  exit 2
fi

if [[ -n "${CONTAINER_ENGINE:-}" ]]; then
  ENGINE="$CONTAINER_ENGINE"
elif command -v podman >/dev/null 2>&1; then
  ENGINE=podman
elif command -v docker >/dev/null 2>&1; then
  ENGINE=docker
else
  echo "Error: install Docker or Podman, or set CONTAINER_ENGINE." >&2
  exit 2
fi
if ! command -v "$ENGINE" >/dev/null 2>&1; then
  echo "Error: container engine '$ENGINE' was not found in PATH." >&2
  exit 2
fi

ENGINE_PATH="$(command -v "$ENGINE")"
ENGINE_NAME="$(basename -- "$ENGINE_PATH")"
ENGINE_IS_PODMAN=0
if [[ "$ENGINE_NAME" == podman* ]] || grep -qi podman "$ENGINE_PATH" 2>/dev/null; then
  ENGINE_IS_PODMAN=1
fi

IMAGE="${LINUX_BUILDER_IMAGE:-mhatxotic-engine-linux-builder:trixie-gcc14-deps-2026.11.16}"
if [[ "${LINUX_IMAGE_PULL:-0}" == "1" ]]; then
  "$ENGINE" pull "$IMAGE"
fi
if [[ "${LINUX_REBUILD_IMAGE:-0}" == "1" ]] || \
   ! "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Building Linux builder image '$IMAGE'..."
  "$ENGINE" build --tag "$IMAGE" \
    --file "${HELPER_ROOT}/docker/Dockerfile.linux" "${HELPER_ROOT}/docker"
fi

if [[ -n "${CONTAINER_VOLUME_SUFFIX+x}" ]]; then
  VOLUME_SUFFIX="$CONTAINER_VOLUME_SUFFIX"
elif [[ "$ENGINE_IS_PODMAN" == "1" ]]; then
  VOLUME_SUFFIX=:Z
else
  VOLUME_SUFFIX=
fi

RUN_ARGS=()
if [[ "${CONTAINER_USE_HOST_USER:-1}" == 1 ]]; then
  if [[ "$ENGINE_IS_PODMAN" == "1" ]]; then
    RUN_ARGS+=(--userns=keep-id)
  fi
  RUN_ARGS+=(--user "$(id -u):$(id -g)")
elif [[ -n "${CONTAINER_USER_SPEC:-}" ]]; then
  RUN_ARGS+=(--user "$CONTAINER_USER_SPEC")
fi

TTY_ARGS=(-i)
if [[ -t 0 && -t 1 ]]; then
  TTY_ARGS=(-it)
fi

exec "$ENGINE" run --rm "${TTY_ARGS[@]}" "${RUN_ARGS[@]}" \
  --volume "${PROJECT_ROOT}:/workspace${VOLUME_SUFFIX}" \
  --workdir /workspace \
  --env HOME=/tmp/engine-linux-build-home \
  --env TERM="${TERM:-xterm}" \
  --env BUILD_TYPE="${BUILD_TYPE:-Release}" \
  --env BUILD_DEFINE="${BUILD_DEFINE:-BETA}" \
  --env JOBS="${JOBS:-}" \
  --env SEVEN_ZIP="${SEVEN_ZIP:-7zz}" \
  "$IMAGE" bash -euo pipefail -c '
    mkdir -p "$HOME" ./bin ./debug ./distro
    python3 ./.build-helpers/scripts/download-linux-dependencies.py
    make --jobs="${JOBS:-$(nproc)}" -f .build-helpers/make/makefile.linux linux \
      BUILD_TYPE="${BUILD_TYPE:-Release}" \
      BUILD_DEFINE="${BUILD_DEFINE:-BETA}" \
      JOBS="${JOBS:-$(nproc)}"
    test -s ./bin/engine64.elf
    test -s ./Diggers/Diggers.adb
    test -s ./distro/Diggers-R64-Ubuntu-X64.7z
    cat > ./distro/start.sh <<START_SH
#!/usr/bin/env bash
set -euo pipefail

LC_ALL=C \
LANG=C \
XDG_SESSION_TYPE=wayland \
XCURSOR_THEME=Adwaita XCURSOR_SIZE=24 \
ALSOFT_DRIVERS=pipewire,pulse,alsa \
./Diggers.elf
START_SH
    chmod +x ./distro/start.sh
    find ./distro -maxdepth 1 -type f -name "Diggers-*-Ubuntu-X64.7z" \
      -print -quit | grep -q .
  '
