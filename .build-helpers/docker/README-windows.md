# Windows MinGW-w64 builder

From the Engine_3 root:

```sh
./.build-helpers/scripts/docker-build-windows.sh
./.build-helpers/scripts/docker-shell-windows.sh
```

The build command creates the image if needed, builds Windows-target
dependencies, then runs `make -f .build-helpers/make/makefile.windows windows` to rebuild the
asset archive, cross-compile the 64-bit executable, and create
`distro/Diggers-R64-Windows-X64.7z`. GitHub Actions calls this same entry
point. `BUILD_TYPE` selects Release or Debug optimization; `JOBS` controls
parallelism and the 7-Zip worker count. Use the shell command for manual work;
it only starts Bash. To execute a different container command, pass it after
`--` to `docker-build-windows.sh`.

The build uses `x86_64-w64-mingw32` with the POSIX threading runtime. The
legacy `scripts/build-windows.sh` can still build the Windows project utility
or resource object, but the container build does not run that Windows utility.
The `.build-helpers/make/makefile.windows` build defaults to a beta executable; `BUILD_DEFINE`
can select `RELEASE` or `ALPHA`. MinGW keeps debug symbols in the object
instead of creating an MSVC `.pdb`.

The build compiles the pinned Windows dependencies automatically. To run
that step manually in the shell:

```sh
BUILD_TARGET=windows python3 .build-helpers/scripts/download-linux-dependencies.py
```

The Windows libraries and headers stay separate from native Linux outputs in
`lib/win64/` and `include/win64/`. The project is mounted at `/workspace` and
uses the Linux-hosted `x86_64-w64-mingw32` POSIX-thread-model cross compiler.
No Wine runtime or Windows-hosted compiler is used. Object and resource files
are written under `debug/`; the executable and distributable are written to
`bin/engine64.exe` and `distro/Diggers-R64-Windows-X64.7z`.

Rebuild the image and open a shell with:

```sh
WINDOWS_REBUILD_IMAGE=1 ./.build-helpers/scripts/docker-shell-windows.sh
BUILD_TARGET=windows python3 .build-helpers/scripts/download-linux-dependencies.py
make -f .build-helpers/make/makefile.windows windows
```

`BUILD_DEFINE` defaults to `BETA` and can be set to `RELEASE` or `ALPHA`.
Set `MINGW_CXX`, `MINGW_WINDRES`, or `SEVEN_ZIP` to override the native Linux
cross tools. `CONTAINER_ENGINE`
selects Docker or Podman (Podman is preferred when available); volume suffix
and container user can be set with `CONTAINER_VOLUME_SUFFIX`,
`CONTAINER_USE_HOST_USER`, and `CONTAINER_USER_SPEC`. Override the image with
`WINDOWS_BUILDER_IMAGE`, pull it with `WINDOWS_IMAGE_PULL=1`, or rebuild it with
`WINDOWS_REBUILD_IMAGE=1`. The `debian:trixie-slim` base tag is intentionally
movable, so rebuilding may update installed package versions.
