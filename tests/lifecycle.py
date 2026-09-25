#!/usr/bin/env python3
"""Run only inside a disposable Slackware container or VM."""
import io
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile

binary = str(pathlib.Path(sys.argv[1]).resolve())
if os.geteuid() != 0 or not pathlib.Path("/etc/slackware-version").exists():
    raise SystemExit("requires root inside a disposable Slackware environment")
if pathlib.Path("/usr/bin/holypkg-fixture").exists():
    raise SystemExit("fixture path already exists")


def run(*args):
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        raise AssertionError(" ".join(args) + "\n" + result.stdout)
    return result.stdout


def source(path, version):
    with tarfile.open(path, "w") as archive:
        payload = {
            ".PKGINFO": (f"pkgname = holypkg-fixture\npkgver = {version}\narch = x86_64\ndepend = absent-dependency\n".encode(), 0o644),
            ".INSTALL": (b"touch /tmp/holypkg-script-executed\n", 0o755),
            "install/doinst.sh": (b"touch /tmp/holypkg-script-executed\n", 0o755),
            "usr/bin/holypkg-fixture": (f"#!/bin/sh\nprintf '{version}\\n'\n".encode(), 0o755),
            "etc/holypkg-fixture.conf": (b"fixture=true\n", 0o640),
        }
        if version == "1.0-1":
            payload["usr/share/holypkg-fixture-obsolete"] = (b"old\n", 0o644)
        for name, (data, mode) in payload.items():
            entry = tarfile.TarInfo(name)
            entry.mode = mode
            entry.size = len(data)
            archive.addfile(entry, io.BytesIO(data))
        link = tarfile.TarInfo("usr/bin/holypkg-fixture-link")
        link.type = tarfile.SYMTYPE
        link.linkname = "holypkg-fixture"
        archive.addfile(link)


with tempfile.TemporaryDirectory(prefix="holypkg-lifecycle-") as temporary:
    work = pathlib.Path(temporary)
    for version in ["1.0-1", "1.1-2"]:
        foreign = work / (version + ".tar")
        stage = work / ("stage-" + version)
        source(foreign, version)
        run(binary, "convert", str(foreign), "--provider", "artix", "--stage", str(stage))
        run(binary, "pack", str(stage), "--output", str(work))
        packages = sorted(work.glob("*.txz"))
        package = packages[-1]
        run("installpkg" if version == "1.0-1" else "upgradepkg", str(package))
        assert run("/usr/bin/holypkg-fixture").strip() == version
        assert run("/usr/bin/holypkg-fixture-link").strip() == version
        assert pathlib.Path("/etc/holypkg-fixture.conf").stat().st_mode & 0o777 == 0o640
        assert not pathlib.Path("/tmp/holypkg-script-executed").exists()
        assert list(pathlib.Path("/var/lib/pkgtools/packages").glob("holypkg-fixture-*-1_holyartix"))
        conflict = subprocess.run([binary, "collisions", str(stage)], capture_output=True, text=True)
        assert conflict.returncode != 0
        assert "already owned by: holypkg-fixture-" in conflict.stdout, conflict.stdout + conflict.stderr
        print("PASS installed", version)
    assert not pathlib.Path("/usr/share/holypkg-fixture-obsolete").exists()
    run("removepkg", "holypkg-fixture")
    assert not pathlib.Path("/usr/bin/holypkg-fixture").exists()
    assert not pathlib.Path("/usr/bin/holypkg-fixture-link").is_symlink()
    assert not list(pathlib.Path("/var/lib/pkgtools/packages").glob("holypkg-fixture-*"))
    print("PASS upgrade cleanup, removal, permissions, collisions and script quarantine")
