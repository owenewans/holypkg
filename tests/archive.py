#!/usr/bin/env python3
"""Exercise real archive conversion, including hostile filesystem layouts."""
import io
import json
import pathlib
import subprocess
import sys
import tarfile
import tempfile

binary = str(pathlib.Path(sys.argv[1]).resolve())


def make(path, extra=()):
    with tarfile.open(path, "w") as archive:
        for name, data, kind, target in [
            (".PKGINFO", b"pkgname = sample\npkgver = 1:2.0-3\narch = x86_64\ndepend = never-install\n", None, ""),
            (".INSTALL", b"touch /tmp/holypkg-must-not-execute\n", None, ""),
            ("usr/bin/sample", b"#!/bin/sh\nprintf 'sample\\n'\n", None, ""),
            *extra,
        ]:
            entry = tarfile.TarInfo(name)
            entry.uid = entry.gid = 0
            entry.mode = 0o755 if name.startswith("usr/bin/") else 0o644
            if kind is not None:
                entry.type = kind
                entry.linkname = target
                archive.addfile(entry)
            else:
                entry.size = len(data)
                archive.addfile(entry, io.BytesIO(data))


def convert(source, stage, *options):
    return subprocess.run([binary, "convert", str(source), "--provider", "artix", "--stage", str(stage), *options], capture_output=True, text=True)


with tempfile.TemporaryDirectory(prefix="holypkg-test-") as tmp:
    tmp = pathlib.Path(tmp)
    source = tmp / "sample.pkg.tar"
    make(source, [("usr/bin/alias", b"", tarfile.SYMTYPE, "sample"), ("install/doinst.sh", b"touch /tmp/foreign-script\n", None, "")])
    stage = tmp / "stage"
    result = convert(source, stage)
    assert result.returncode == 0, result.stdout + result.stderr
    metadata = json.loads((stage / "package.json").read_text())
    assert metadata["provider"] == "artix"
    assert metadata["version"] == "1:2.0-3"
    assert (stage / "root/usr/bin/alias").is_symlink()
    assert not (stage / "root/.INSTALL").exists()
    assert not (stage / "root/install/doinst.sh").exists()
    assert (stage / "root/usr/doc/sample/holypkg/original/install/doinst.sh").is_file()
    assert (stage / "root/usr/doc/sample/holypkg/original/.INSTALL").read_text().startswith("touch")
    assert len((stage / "root/install/slack-desc").read_text().splitlines()) == 11
    assert convert(source, stage).returncode != 0, "existing stage overwritten"

    attacks = {
        "parent": [("../escaped", b"bad", None, "")],
        "absolute": [("/tmp/escaped", b"bad", None, "")],
        "symlink-parent": [("opt", b"", tarfile.SYMTYPE, "/tmp"), ("opt/escaped", b"bad", None, "")],
        "hardlink": [("usr/bin/evil", b"", tarfile.LNKTYPE, "../../etc/passwd")],
        "duplicate": [("usr/bin/sample", b"bad", None, "")],
        "metadata-link": [(".PKGINFO", b"", tarfile.SYMTYPE, "/etc/passwd")],
        "provenance-link": [("usr/doc", b"", tarfile.SYMTYPE, "/tmp")],
    }
    for name, entries in attacks.items():
        source = tmp / (name + ".tar")
        make(source, entries)
        result = convert(source, tmp / name)
        assert result.returncode != 0, name + " accepted"
        assert convert(source, tmp / (name + "-root"), "--owner", "root").returncode != 0
        assert not (tmp / "escaped").exists()
        print("PASS", name)
    print("PASS metadata, symlinks, stage preservation and foreign script quarantine")
    source = tmp / "ownership.tar"
    make(source)
    with tarfile.open(source, "a", format=tarfile.PAX_FORMAT) as output:
        entry = tarfile.TarInfo("usr/share/owned")
        entry.pax_headers = {"uid": "10000000000", "gid": "10000000001"}
        output.addfile(entry, io.BytesIO())
        output.addfile(tarfile.TarInfo("usr/share/root"), io.BytesIO())
    assert convert(source, tmp / "ownership-rejected").returncode != 0
    stage = tmp / "ownership-explicit"
    result = convert(source, stage, "--owner", "root")
    assert result.returncode == 0, result.stdout + result.stderr
    assert json.loads((stage / "package.json").read_text())["ownership"] == "root"
    original = json.loads((stage / "root/usr/doc/sample/holypkg/source-files.json").read_text())
    assert next(e for e in original if e["path"] == "usr/share/owned")["uid"] == 10000000000
    assert next(e for e in original if e["path"] == "usr/share/root")["uid"] == 0
    print("PASS explicit ownership rule and PAX ownership provenance")
