# Docker

## Refresh image
```
  podman build --pull --no-cache \
    -t mhatxotic-engine-linux-builder:trixie-gcc14-deps-2026.11.16 \
    -f .build-helpers/docker/Dockerfile.linux \
    .build-helpers/docker
```

## Start shell
```
    ./.build-helpers/scripts/docker-shell-linux.sh
```

## Full Linux build
```sh
./.build-helpers/scripts/docker-build-linux.sh
```

The build entry point creates the image if needed, downloads/builds the Linux
dependencies, then runs `.build-helpers/make/makefile.linux` to compile the
game, refresh the Diggers assets, and create the distro package. GitHub Actions
uses the same script. If dependencies are already built, invoke the Makefile
from the project root with `make -f .build-helpers/make/makefile.linux linux`.
`BUILD_TYPE`, `BUILD_DEFINE`, and `JOBS` configure it; `SEVEN_ZIP` selects the
7-Zip command (default `7zz`).
