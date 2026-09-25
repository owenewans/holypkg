#!/usr/bin/env python3
"""Require a signature and reject damaged RPM payloads with the native verifier."""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

signer = str(pathlib.Path(sys.argv[1]).resolve())
verifier = '/usr/libexec/holypkg-rpm/bin/rpmkeys'


def run(*args, success=True, env=None):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
    assert (result.returncode == 0) == success, ' '.join(args) + '\n' + result.stdout
    return result.stdout


with tempfile.TemporaryDirectory(prefix='holypkg-rpm-verification-') as temporary:
    work = pathlib.Path(temporary)
    home = work / 'gnupg'
    home.mkdir(mode=0o700)
    env = dict(os.environ, GNUPGHOME=str(home))
    gpg = ['gpg', '--homedir', str(home), '--batch', '--pinentry-mode', 'loopback', '--passphrase', '']
    run(*gpg, '--quick-generate-key', 'holypkg fixture <fixture@invalid>', 'rsa2048', 'sign', '1d')
    listing = run(*gpg, '--with-colons', '--list-keys')
    fingerprint = next(line.split(':')[9] for line in listing.splitlines() if line.startswith('fpr:'))
    key = work / 'key.asc'
    key.write_text(run(*gpg, '--armor', '--export', fingerprint))
    spec = work / 'fixture.spec'
    spec.write_text('''Name: signature-fixture
Version: 1.0
Release: 1
Summary: signature fixture
License: Unlicense
BuildArch: noarch
%description
signature fixture
%install
mkdir -p %{buildroot}/usr/share/signature-fixture
printf 'verified payload\\n' > %{buildroot}/usr/share/signature-fixture/file
%files
/usr/share/signature-fixture/file
''')
    run('rpmbuild', '-bb', '--define', '_topdir ' + str(work / 'rpm'), str(spec))
    unsigned = next((work / 'rpm/RPMS').rglob('*.rpm'))
    trust = work / 'trust'
    trust.mkdir()
    verify = [verifier, '--dbpath', str(trust), '--define', '_pkgverify_level all', '--define', '_pkgverify_flags 0', '--checksig']
    run(verifier, '--dbpath', str(trust), '--import', str(key))
    run(*verify, str(unsigned), success=False)
    signed = work / 'signed.rpm'
    shutil.copyfile(unsigned, signed)
    run(signer, '--define', '_openpgp_sign gpg', '--define', '_openpgp_sign_id ' + fingerprint, '--addsign', str(signed), env=env)
    run(*verify, str(signed))
    untrusted = work / 'untrusted'
    untrusted.mkdir()
    run(verifier, '--dbpath', str(untrusted), '--define', '_pkgverify_level all', '--checksig', str(signed), success=False)
    damaged = work / 'damaged.rpm'
    raw = bytearray(signed.read_bytes())
    raw[-1] ^= 1
    damaged.write_bytes(raw)
    run(*verify, str(damaged), success=False)
    run('gpgconf', '--homedir', str(home), '--kill', 'all')
    print('PASS signed RPM; unsigned, unknown-key and modified payloads rejected')
