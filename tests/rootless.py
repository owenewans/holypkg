#!/usr/bin/env python3
"""Verify unprivileged makepkg output ownership without changing payload modes."""
import io
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile

assert os.geteuid() != 0, "run as an unprivileged container user"
binary = str(pathlib.Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="holypkg-rootless-") as temporary:
    work = pathlib.Path(temporary)
    source = work / "fixture.tar"
    with tarfile.open(source, "w") as archive:
        for name, data, mode in [
            (".PKGINFO", b"pkgname = rootless-fixture\npkgver = 1.0-1\narch = any\n", 0o644),
            ("etc/rootless-fixture", b"private configuration\n", 0o640),
            ("usr/bin/rootless-fixture", b"#!/bin/sh\nexit 0\n", 0o755),
        ]:
            entry = tarfile.TarInfo(name)
            entry.mode = mode
            entry.size = len(data)
            archive.addfile(entry, io.BytesIO(data))
    stage = work / "stage"
    subprocess.run([binary, "convert", str(source), "--provider", "arch", "--stage", str(stage)], check=True)
    subprocess.run([binary, "pack", str(stage), "--output", str(work)], check=True)
    package = next(work.glob("*.txz"))
    with tarfile.open(package, "r:xz") as archive:
        entries = {entry.name.removeprefix("./"): entry for entry in archive}
    assert all(entry.uid == 0 and entry.gid == 0 for entry in entries.values())
    assert entries["etc/rootless-fixture"].mode == 0o640
    assert entries["usr/bin/rootless-fixture"].mode == 0o755
    assert (stage / "root/etc/rootless-fixture").stat().st_uid == os.geteuid()
    print("PASS non-root package ownership and payload permissions")
