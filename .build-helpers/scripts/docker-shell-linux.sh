#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HELPER_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd -- "${HELPER_ROOT}/.." && pwd)"
FORCE_ROOT=0

while (($#)); do
  case "$1" in
    --root)
      FORCE_ROOT=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: .build-helpers/scripts/docker-shell-linux.sh [--root] [--] [bash arguments...]
USAGE
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

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
if ! "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Building Linux builder image '$IMAGE'..."
  "$ENGINE" build --tag "$IMAGE" \
    --file "${HELPER_ROOT}/docker/Dockerfile.linux" "${HELPER_ROOT}/docker"
fi

if [[ -n "${CONTAINER_VOLUME_SUFFIX+x}" ]]; then
  VOLUME_SUFFIX="$CONTAINER_VOLUME_SUFFIX"
elif [[ "$ENGINE_IS_PODMAN" == 1 ]]; then
  VOLUME_SUFFIX=:Z
else
  VOLUME_SUFFIX=
fi

RUN_ARGS=()
if [[ "$FORCE_ROOT" == "1" ]]; then
  echo "Starting as container root; apt changes are temporary and mounted files may be root-owned."
elif [[ "${CONTAINER_USE_HOST_USER:-1}" == 1 ]]; then
  if [[ "$ENGINE_IS_PODMAN" == 1 ]]; then
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
  "$IMAGE" bash -i
