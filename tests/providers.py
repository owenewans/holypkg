#!/usr/bin/env python3
"""Verify provider identity, signatures and exclusive downloads with signed fixtures."""
import hashlib
import io
import json
import os
import pathlib
import subprocess
import sys
import tarfile
import tempfile

binary = str(pathlib.Path(sys.argv[1]).resolve())


def run(*args, success=True, env=None):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    assert (result.returncode == 0) == success, " ".join(args) + "\n" + result.stdout + result.stderr
    return result.stdout


def archive(path, files):
    with tarfile.open(path, "w:gz") as output:
        for name, data in files.items():
            entry = tarfile.TarInfo(name)
            entry.mode = 0o644
            entry.size = len(data)
            output.addfile(entry, io.BytesIO(data))


with tempfile.TemporaryDirectory(prefix="holypkg-providers-") as temporary:
    work = pathlib.Path(temporary)
    home = work / "gnupg"
    home.mkdir(mode=0o700)
    gpg = ["gpg", "--homedir", str(home), "--batch", "--pinentry-mode", "loopback", "--passphrase", ""]
    run(*gpg, "--quick-generate-key", "holypkg test <test@invalid>", "ed25519", "sign", "1d")
    listing = run(*gpg, "--with-colons", "--list-keys")
    fingerprint = next(line.split(":")[9] for line in listing.splitlines() if line.startswith("fpr:"))
    original = work / "source.asc"
    original.write_text(run(*gpg, "--armor", "--export", fingerprint))
    key = work / "selected.asc"
    run(binary, "key", "add", str(original), "--fingerprint", "0" * 40, "--keyring", str(key), success=False)
    assert not key.exists()
    run(binary, "key", "add", str(original), "--fingerprint", fingerprint, "--keyring", str(key))
    saved = key.read_bytes()
    run(binary, "key", "add", str(original), "--fingerprint", fingerprint, "--keyring", str(key), success=False)
    assert key.read_bytes() == saved

    wrappers = work / "bin"
    wrappers.mkdir()
    curl = wrappers / "curl"
    curl.write_text('''#!/usr/bin/env python3
import os, pathlib, shutil, sys, urllib.parse
args = sys.argv[1:]
source = pathlib.Path(os.environ["FIXTURE_MIRROR"]) / urllib.parse.urlparse(args[-1]).path.lstrip("/")
shutil.copyfile(source, args[args.index("--output") + 1])
''')
    curl.chmod(0o755)
    env = dict(os.environ, PATH=str(wrappers) + os.pathsep + os.environ["PATH"], FIXTURE_MIRROR=str(work / "mirror"))
    for provider, repo in [("arch", "core"), ("artix", "system")]:
        directory = work / "mirror" / repo / "os/x86_64"
        directory.mkdir(parents=True)
        version = "1:1.0-1" if provider == "artix" else "1.0-1"
        filename = f"fixture-{version}-any.pkg.tar.gz"
        package = directory / filename
        archive(package, {".PKGINFO": f"pkgname = fixture\npkgver = {version}\narch = any\n".encode(), "usr/share/fixture": b"payload\n"})
        digest = hashlib.sha256(package.read_bytes()).hexdigest()
        archive(directory / (repo + ".db"), {f"fixture-{version}/desc": f"%NAME%\nfixture\n\n%VERSION%\n{version}\n\n%ARCH%\nany\n\n%FILENAME%\n{filename}\n\n%SHA256SUM%\n{digest}\n\n%DEPENDS%\nnever-install-me\n\n".encode()})
        run(*gpg, "--detach-sign", str(package))
        common = [provider, "fixture", "--repo", repo, "--mirror", "https://fixture.invalid", "--keyring", str(key)]
        stage = work / (provider + "-stage")
        run(binary, *common, "--stage", str(stage), env=env)
        metadata = json.loads((stage / "package.json").read_text())
        assert metadata["provider"] == provider and metadata["repository"] == repo
        assert metadata["version"] == version
        assert metadata["signature_verified"] is True
        assert "never-install-me" in run(binary, "deps", *common, env=env)
        assert run(binary, "files", *common, env=env).strip() == "usr/share/fixture"
        run(binary, "info", *common, "--install", env=env, success=False)
        output = work / (provider + "-downloads")
        run(binary, "fetch", *common, "--output", str(output), env=env)
        (output / filename).write_bytes(b"existing file")
        run(binary, "fetch", *common, "--output", str(output), env=env, success=False)
        assert (output / filename).read_bytes() == b"existing file"
        pathlib.Path(str(package) + ".sig").write_bytes(b"invalid signature")
        run(binary, "fetch", *common, "--output", str(work / "rejected"), env=env, success=False)
        assert not (work / "rejected" / filename).exists()
        print("PASS", provider, "signature rejection, identity, dependency display and exclusive fetch")
    run("gpgconf", "--homedir", str(home), "--kill", "all")
    print("PASS explicit key fingerprint and no overwrite")
