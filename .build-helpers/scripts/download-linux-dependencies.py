#!/usr/bin/env python3
"""Fetch pinned Linux third-party archives and build missing libraries."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import ssl
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parents[1]
MANIFEST = PROJECT_ROOT / ".build-helpers" / "versions-linux.json"
ALLOWED_FORMATS = {"tar.gz", "tar.xz", "tar.bz2", "zip", "7z"}
CHUNK_SIZE = 1024 * 1024


class FetchError(Exception):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(CHUNK_SIZE), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_manifest() -> dict:
    try:
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise FetchError(f"Cannot read manifest {MANIFEST}: {exc}") from exc
    if data.get("schema_version") != 3 or data.get("platform") != "linux":
        raise FetchError(f"Unsupported dependency manifest: {MANIFEST}")
    return data


def resolve_build_args(library: str, spec: dict, libs: dict) -> list[str]:
    args = spec.get("build-script-args", [])
    if not isinstance(args, list) or not all(isinstance(arg, str) for arg in args):
        raise FetchError(f"{library}: build-script-args must be an array of strings")
    result = []
    for arg in args:
        match = re.fullmatch(r"\$([a-z0-9-]+)-version\$", arg)
        if not match:
            if arg.startswith("$"):
                raise FetchError(f"{library}: unsupported build-script argument reference {arg!r}")
            result.append(arg)
            continue
        version_key = match.group(1)
        if version_key not in libs or "version" not in libs[version_key]:
            raise FetchError(f"{library}: build argument references unknown library {version_key!r}")
        result.append(str(libs[version_key]["version"]))
    return result


def artifacts_in_order(manifest: dict, only: set[str] | None = None) -> list[tuple[str, str, list[str], dict]]:
    found: list[tuple[str, str, list[str], dict]] = []
    by_filename: dict[str, dict] = {}
    libs = manifest.get("libs")
    if not isinstance(libs, dict) or not libs:
        raise FetchError("Dependency manifest must contain a non-empty 'libs' object")
    unknown = (only or set()) - set(libs)
    if unknown:
        raise FetchError("Unknown --only library/libraries: " + ", ".join(sorted(unknown)))

    # Select dependencies recursively, then retain the manifest's declared
    # order (which is the requested build/dependency order).
    wanted: set[str] = set()
    active: set[str] = set()

    def include(name: str) -> None:
        if name in active:
            raise FetchError(f"Dependency cycle involving library {name!r}")
        if name in wanted:
            return
        if name not in libs:
            raise FetchError(f"Unknown dependency library {name!r}")
        active.add(name)
        dependencies = libs[name].get("dependencies", [])
        if not isinstance(dependencies, list) or not all(isinstance(dep, str) for dep in dependencies):
            raise FetchError(f"{name}: dependencies must be an array of library names")
        for dependency in dependencies:
            include(dependency)
        active.remove(name)
        wanted.add(name)

    if only:
        for name in only:
            include(name)
        # Some scripts build multiple libraries in one invocation. Include
        # peers only when they share the exact script arguments and patch.
        changed = True
        while changed:
            changed = False
            for name in tuple(wanted):
                name_spec = libs[name]
                script = name_spec.get("build-script")
                script_args = resolve_build_args(name, name_spec, libs)
                script_patch = name_spec.get("patch")
                for peer, peer_spec in libs.items():
                    if (peer_spec.get("build-script") == script
                            and resolve_build_args(peer, peer_spec, libs) == script_args
                            and peer_spec.get("patch") == script_patch
                            and peer not in wanted):
                        include(peer)
                        changed = True
    else:
        for name in libs:
            include(name)

    for library, spec in libs.items():
        if library not in wanted:
            continue
        script = spec.get("build-script")
        if (not isinstance(script, str) or not script.endswith(".sh")
                or Path(script).name != script):
            raise FetchError(f"{library}: invalid or missing build-script")
        archive = spec.get("archive")
        if not isinstance(archive, dict):
            raise FetchError(f"{library}: archive must be an object")
        patch = spec.get("patch")
        if patch is not None:
            if not isinstance(patch, str) or not patch:
                raise FetchError(f"{library}: patch must be a non-empty relative path")
            patch_relative = Path(patch)
            patch_root = MANIFEST.parent.resolve()
            patch_path = (patch_root / patch_relative).resolve()
            if (patch_relative.is_absolute() or ".." in patch_relative.parts
                    or not patch_path.is_relative_to(patch_root)):
                raise FetchError(f"{library}: patch must be a safe path relative to {MANIFEST.parent}")
            if not patch_path.is_file():
                raise FetchError(f"{library}: patch file not found: {patch_path}")
        artifact = {
            "archive": archive.get("filename", ""),
            "url": archive.get("url", ""),
            "sha256": archive.get("sha256"),
            "format": archive.get("format"),
            "library_output": spec.get("library-output"),
            "header_outputs": spec.get("header-outputs", []),
            "patch": patch,
        }
        output = artifact["library_output"]
        if output is not None:
            safe = Path(output)
            if safe.is_absolute() or ".." in safe.parts or safe.parts[:1] != ("lib",):
                raise FetchError(f"{library}: library-output must be a safe path under lib/")
        header_outputs = artifact["header_outputs"]
        if (not isinstance(header_outputs, list)
                or not all(isinstance(path, str) and path for path in header_outputs)):
            raise FetchError(f"{library}: header-outputs must be an array of paths")
        for header_output in header_outputs:
            safe = Path(header_output)
            if safe.is_absolute() or ".." in safe.parts or safe.parts[:1] != ("include",):
                raise FetchError(f"{library}: header-outputs must contain safe paths under include/")
        filename = artifact["archive"]
        if not filename or Path(filename).name != filename:
            raise FetchError(f"Unsafe or missing archive filename for {library}: {filename!r}")
        if artifact["format"] not in ALLOWED_FORMATS:
            raise FetchError(f"Unsupported archive format for {filename}: {artifact['format']!r}")
        if output_format(filename) != artifact["format"]:
            raise FetchError(
                f"{library}: archive filename extension does not match its format "
                f"({filename!r}, {artifact['format']!r})"
            )
        if not artifact["url"].startswith("https://"):
            raise FetchError(f"{library}: archive URL must use HTTPS")
        if filename in by_filename:
            if by_filename[filename] != artifact:
                raise FetchError(f"Conflicting archive metadata for {filename}")
            continue
        by_filename[filename] = artifact
        found.append((library, script, resolve_build_args(library, spec, libs), artifact))
    return found


def sidecar_path(archive: Path) -> Path:
    return archive.with_name(archive.name + ".sha256")


def provenance_path(archive: Path) -> Path:
    return archive.with_name(archive.name + ".provenance")


def read_sidecar(path: Path) -> str | None:
    try:
        text = path.read_text(encoding="ascii").strip()
    except OSError:
        return None
    token = text.split(maxsplit=1)[0] if text else ""
    if len(token) == 64 and all(ch in "0123456789abcdef" for ch in token.lower()):
        return token.lower()
    return None


def write_sidecar(path: Path, digest: str) -> None:
    sidecar = sidecar_path(path)
    fd, temp_name = tempfile.mkstemp(prefix=f".{sidecar.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="ascii") as stream:
            stream.write(f"{digest}  {path.name}\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, sidecar)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)
    marker = provenance_path(path)
    marker.write_text(f"raw-upstream-v1 {digest} {path.name}\n", encoding="ascii")


def read_provenance(path: Path) -> str | None:
    try:
        fields = provenance_path(path).read_text(encoding="ascii").strip().split(maxsplit=2)
    except OSError:
        return None
    if len(fields) != 3 or fields[0] != "raw-upstream-v1" or fields[2] != path.name:
        return None
    digest = fields[1].lower()
    if len(digest) == 64 and all(ch in "0123456789abcdef" for ch in digest):
        return digest
    return None


def output_format(filename: str) -> str | None:
    for suffix, archive_format in (
        (".tar.gz", "tar.gz"), (".tar.xz", "tar.xz"),
        (".tar.bz2", "tar.bz2"), (".zip", "zip"), (".7z", "7z"),
    ):
        if filename.endswith(suffix):
            return archive_format
    return None


def expected_cached_hash(artifact: dict) -> str | None:
    value = artifact.get("sha256")
    return value.lower() if isinstance(value, str) else None


def verify_existing(path: Path, artifact: dict, offline: bool) -> bool:
    if not path.exists():
        if offline:
            raise FetchError(f"Offline mode: missing {path}")
        return False

    sidecar_hash = read_sidecar(sidecar_path(path))
    pinned_hash = expected_cached_hash(artifact)
    provenance_hash = read_provenance(path)
    actual = sha256_file(path)
    if provenance_hash is not None and sidecar_hash == provenance_hash:
        if actual != provenance_hash:
            raise FetchError(
                f"Checksum mismatch for existing {path}: expected {provenance_hash}, "
                f"got {actual}. Preserving the file."
            )
        if pinned_hash and actual != pinned_hash:
            if offline:
                raise FetchError(
                    f"Checksum mismatch for existing {path}: expected upstream SHA-256 "
                    f"{pinned_hash}, got {actual}."
                )
            return False
        return True
    if pinned_hash and actual == pinned_hash:
        write_sidecar(path, pinned_hash)
        return True
    if sidecar_path(path).exists():
        if offline:
            raise FetchError(
                f"{path} has a legacy archive sidecar and may contain a normalized archive. "
                "Fetch it again to verify the upstream bytes."
            )
        return False
    raise FetchError(
        f"{path} already exists but has no verified .sha256 sidecar. "
        "Preserving it; move it aside after inspection before downloading."
    )


def download(url: str, destination: Path, expected_sha256: str | None,
             ssl_context: ssl.SSLContext) -> str:
    if not url.startswith("https://"):
        raise FetchError(f"Refusing non-HTTPS dependency URL: {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "Engine-2-dependency-fetcher/1"})
    digest = hashlib.sha256()
    try:
        with urllib.request.urlopen(request, timeout=60, context=ssl_context) as response, destination.open("wb") as output:
            final_url = response.geturl()
            if not final_url.startswith("https://"):
                raise FetchError(f"Download redirected to a non-HTTPS URL: {final_url}")
            while True:
                chunk = response.read(CHUNK_SIZE)
                if not chunk:
                    break
                output.write(chunk)
                digest.update(chunk)
            output.flush()
            os.fsync(output.fileno())
    except urllib.error.URLError as exc:
        if isinstance(exc.reason, ssl.SSLCertVerificationError):
            raise FetchError(
                f"TLS certificate verification failed for {url}: {exc.reason}. "
                "Update the system ca-certificates, or provide a trusted CA bundle "
                "with --ca-bundle PATH or SSL_CERT_FILE. TLS verification remains enabled."
            ) from exc
        raise FetchError(f"Download failed for {url}: {exc}") from exc
    except (TimeoutError, OSError) as exc:
        raise FetchError(f"Download failed for {url}: {exc}") from exc
    actual = digest.hexdigest()
    if expected_sha256 and actual != expected_sha256.lower():
        raise FetchError(f"Checksum mismatch for {url}: expected {expected_sha256}, got {actual}")
    return actual


def fetch_one(library: str, script: str, build_args: list[str], artifact: dict,
              archive_dir: Path, offline: bool, ssl_context: ssl.SSLContext) -> None:
    target = archive_dir / artifact["archive"]
    if verify_existing(target, artifact, offline):
        print(f"[cached] {target.relative_to(PROJECT_ROOT)}")
        return
    if offline:
        raise FetchError(f"Offline mode: missing {target}")

    archive_dir.mkdir(parents=True, exist_ok=True)
    download_fd, download_name = tempfile.mkstemp(prefix=f".{target.name}.", suffix=".download", dir=archive_dir)
    os.close(download_fd)
    downloaded = Path(download_name)
    try:
        print(f"[fetch] {library} via {script} {' '.join(build_args)}: {artifact['url']}", flush=True)
        final_hash = download(artifact["url"], downloaded, artifact.get("sha256"), ssl_context)
        if target.exists():
            previous_dir = Path(tempfile.mkdtemp(
                prefix=f".{target.name}.previous.", dir=archive_dir))
            os.replace(target, previous_dir / target.name)
            for old_metadata in (sidecar_path(target), provenance_path(target)):
                if old_metadata.exists():
                    os.replace(old_metadata, previous_dir / old_metadata.name)
            print(f"[preserved] previous archive at {previous_dir.relative_to(PROJECT_ROOT)}")
        os.replace(downloaded, target)
        write_sidecar(target, final_hash)
        print(f"[saved] {target.relative_to(PROJECT_ROOT)}  sha256={final_hash}")
    finally:
        downloaded.unlink(missing_ok=True)


def build_invocations(entries: list[tuple[str, str, list[str], dict]]) -> list[dict]:
    """Group libraries handled by the same script call, preserving manifest order."""
    invocations: list[dict] = []
    by_command: dict[tuple[str, tuple[str, ...], str | None], dict] = {}
    for library, script, build_args, artifact in entries:
        patch = artifact.get("patch")
        key = (script, tuple(build_args), patch)
        invocation = by_command.get(key)
        if invocation is None:
            invocation = {
                "script": script,
                "args": [*build_args, *([patch] if patch else [])],
                "libraries": [],
                "outputs": [],
                "headers": [],
            }
            by_command[key] = invocation
            invocations.append(invocation)
        invocation["libraries"].append(library)
        output = artifact.get("library_output")
        if output and output not in invocation["outputs"]:
            invocation["outputs"].append(output)
        for header in artifact.get("header_outputs", []):
            if header not in invocation["headers"]:
                invocation["headers"].append(header)
    return invocations


def output_is_built(invocation: dict) -> bool:
    outputs = invocation["outputs"]
    headers = invocation["headers"]
    return (bool(outputs or headers)
            and all((PROJECT_ROOT / output).is_file() for output in outputs)
            and all((PROJECT_ROOT / header).is_file() for header in headers))


def run_build_scripts(entries: list[tuple[str, str, list[str], dict]]) -> None:
    for invocation in build_invocations(entries):
        script_path = PROJECT_ROOT / "scripts" / invocation["script"]
        if not script_path.is_file():
            raise FetchError(f"Build script not found: {script_path}")
        if output_is_built(invocation):
            outputs = ", ".join(invocation["outputs"] + invocation["headers"])
            print(f"[ready] {', '.join(invocation['libraries'])}: outputs already exist ({outputs}); skipping")
            continue

        command = [str(script_path), *invocation["args"]]
        print(f"[build] (cwd={PROJECT_ROOT}) {shlex.join(command)}", flush=True)
        result = subprocess.run(command, cwd=PROJECT_ROOT, check=False)
        if result.returncode != 0:
            raise FetchError(
                f"Build script {invocation['script']} failed with exit status {result.returncode}"
            )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Download pinned Linux archives, build libraries, and install headers."
    )
    parser.add_argument("--dry-run", action="store_true", help="list planned downloads and builds without side effects")
    parser.add_argument("--download-only", action="store_true",
                        help="download or verify archives but do not run build scripts")
    parser.add_argument("--offline", action="store_true",
                        help="use verified cached archives without downloading")
    tls_options = parser.add_mutually_exclusive_group()
    tls_options.add_argument("--ca-bundle", metavar="PATH",
                             help="add a trusted PEM CA bundle while retaining system CAs and TLS verification")
    tls_options.add_argument("--insecure", action="store_true",
                             help="skip HTTPS certificate and hostname checks (unsafe; temporary workaround only)")
    parser.add_argument("--only", action="append", metavar="LIBRARY",
                        help="download one library and its dependencies; may be repeated, e.g. --only glfw")
    args = parser.parse_args()

    try:
        manifest = read_manifest()
        entries = artifacts_in_order(manifest, set(args.only) if args.only else None)
        if args.insecure:
            print("WARNING: HTTPS certificate and hostname verification are DISABLED. "
                  "Downloaded archives could be intercepted or modified.", file=sys.stderr)
            ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE
        else:
            # The default context honors SSL_CERT_FILE/SSL_CERT_DIR and keeps
            # normal certificate and hostname verification enabled. Add an
            # optional organization-specific CA to the system trust store.
            ssl_context = ssl.create_default_context()
        if args.ca_bundle:
            ca_bundle = Path(args.ca_bundle).expanduser().resolve()
            if not ca_bundle.is_file():
                raise FetchError(f"CA bundle does not exist or is not a file: {ca_bundle}")
            try:
                ssl_context.load_verify_locations(cafile=str(ca_bundle))
            except (OSError, ssl.SSLError) as exc:
                raise FetchError(f"Cannot load CA bundle {ca_bundle}: {exc}") from exc

        archive_relative = Path(manifest.get("archive_directory", "archive"))
        if archive_relative.is_absolute() or ".." in archive_relative.parts:
            raise FetchError(f"Unsafe archive directory in manifest: {archive_relative}")
        archive_dir = PROJECT_ROOT / archive_relative
        if args.dry_run:
            print(f"Project: {PROJECT_ROOT}")
            print(f"Archive directory: {archive_dir}")
            for library, script, build_args, artifact in entries:
                integrity = "pinned SHA-256" if artifact.get("sha256") else "HTTPS + locally recorded SHA-256 (no upstream digest pinned)"
                description = f"{script} {' '.join(build_args)}"
                print(f"{library:16} {description:32} {artifact['archive']}  [{integrity}]")
            if args.download_only:
                print("\nDownload-only mode: build scripts will not run.")
            else:
                print("\nDependency scripts (from project root):")
                for invocation in build_invocations(entries):
                    status = "[skip: output exists]" if output_is_built(invocation) else ""
                    command = ["scripts/" + invocation["script"], *invocation["args"]]
                    print(f"  {shlex.join(command)} {status}".rstrip())
            return 0

        for library, script, build_args, artifact in entries:
            fetch_one(library, script, build_args, artifact, archive_dir,
                      args.offline, ssl_context)
        if not args.download_only:
            run_build_scripts(entries)
    except FetchError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
