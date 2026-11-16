# Linux dependencies

Downloads and verifies dependency archives in `archive/`, then runs the
manifest's build scripts from the project root in dependency order. A build
script is skipped only when its library and declared header outputs exist.
Archives stay byte-for-byte in their upstream format; each build script
extracts what it needs. `scripts/simplewebp.sh` and `scripts/rapidjson.sh`
extract their pinned archives and install headers under `include/swp/` and
`include/rapidjson/`; neither library is compiled.
An optional `patch` entry is relative to `.build-helpers/` and is passed to the
build script as its final argument.

```sh
python3 .build-helpers/scripts/download-linux-dependencies.py [options]
```

Build scripts use the detected CPU count for parallel `make`; set `JOBS=N` to override.

- `--dry-run`: print the plan.
- `--download-only`: fetch/verify archives but do not build libraries.
- `--only LIBRARY`: process a library and its dependencies; repeat as needed.
- `--offline`: use verified cached archives without network access.
- `--ca-bundle PATH`: add a PEM CA bundle to the system trust store. Alternatively, set `SSL_CERT_FILE`.
- `--insecure`: disable HTTPS certificate and hostname checks. Unsafe; use only as a temporary workaround.

Prefer updating the system CA certificates or using a trusted CA bundle. `--insecure` disables certificate and hostname checks and should only be used temporarily; intercepted or modified downloads may then go unnoticed.
