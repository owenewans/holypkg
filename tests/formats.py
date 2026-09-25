#!/usr/bin/env python3
"""Exercise Debian, RPM and generic binary archive staging in Slackware."""
import io
import json
import pathlib
import subprocess
import sys
import tarfile
import tempfile

binary = str(pathlib.Path(sys.argv[1]).resolve())


def run(*args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert result.returncode == 0, " ".join(args) + "\n" + result.stdout
    return result.stdout


def tar(files):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as output:
        for name, data in files.items():
            entry = tarfile.TarInfo(name)
            entry.mode = 0o644
            entry.size = len(data)
            output.addfile(entry, io.BytesIO(data))
    return buffer.getvalue()


def ar(files, path):
    with path.open("wb") as output:
        output.write(b"!<arch>\n")
        for name, data in files.items():
            header = f"{name + '/':<16}{0:<12}{0:<6}{0:<6}{'100644':<8}{len(data):<10}`\n".encode()
            assert len(header) == 60
            output.write(header + data)
            if len(data) % 2:
                output.write(b"\n")


with tempfile.TemporaryDirectory(prefix="holypkg-formats-") as temporary:
    work = pathlib.Path(temporary)
    deb = work / "fixture.deb"
    ar({
        "debian-binary": b"2.0\n",
        "control.tar.gz": tar({
            "./control": b"Package: format-fixture\nVersion: 2:1.0-4\nArchitecture: amd64\nDescription: binary fixture\nDepends: never-installed\n",
            "./postinst": b"#!/bin/sh\ntouch /tmp/foreign-format-executed\n",
        }),
        "data.tar.gz": tar({"./usr/share/format-fixture/file": b"payload\n"}),
    }, deb)
    for provider in ["debian", "ubuntu"]:
        stage = work / provider
        run(binary, "convert", str(deb), "--provider", provider, "--stage", str(stage))
        metadata = json.loads((stage / "package.json").read_text())
        assert metadata["version"] == "2:1.0-4"
        assert metadata["provider"] == provider
        assert (stage / "root/usr/doc/format-fixture/holypkg/debian-control/postinst").exists()
        assert "touch /tmp/foreign-format-executed" in run(binary, "scripts", str(deb), "--provider", provider)
        print("PASS", provider, "payload, metadata and script isolation")

    spec = work / "fixture.spec"
    spec.write_text('''Name: format-fixture
Version: 1.0
Release: 2
Summary: binary fixture
License: Unlicense
BuildArch: noarch
%description
binary fixture
%install
mkdir -p %{buildroot}/usr/share/format-fixture
printf 'payload\\n' > %{buildroot}/usr/share/format-fixture/file
%post
touch /tmp/foreign-format-executed
%files
/usr/share/format-fixture/file
''')
    run("rpmbuild", "-bb", "--define", "_topdir " + str(work / "rpm"), str(spec))
    rpm = next((work / "rpm/RPMS").rglob("*.rpm"))
    for provider in ["fedora", "opensuse"]:
        stage = work / provider
        run(binary, "convert", str(rpm), "--provider", provider, "--stage", str(stage))
        assert (stage / "root/usr/share/format-fixture/file").read_text() == "payload\n"
        assert "touch /tmp/foreign-format-executed" in (stage / "root/usr/doc/format-fixture/holypkg/rpm-scripts.txt").read_text()
        print("PASS", provider, "payload, metadata and script isolation")

    generic = work / "upstream.tar.gz"
    generic.write_bytes(tar({"bin/format-fixture": b"binary fixture\n"}))
    for provider in ["github", "url"]:
        stage = work / provider
        run(binary, "convert", str(generic), "--provider", provider, "--name", "format-fixture", "--version", "1.0", "--prefix", "/opt/fixture", "--stage", str(stage))
        assert (stage / "root/opt/fixture/bin/format-fixture").exists()
        print("PASS", provider, "explicit prefix")
    assert not pathlib.Path("/tmp/foreign-format-executed").exists()
