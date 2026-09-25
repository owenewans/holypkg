#!/usr/bin/env python3
"""Build a signed-current test image and run pkgtools tests through Podman."""
import argparse
import concurrent.futures
import hashlib
import pathlib
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work', type=pathlib.Path, required=True)
parser.add_argument('--mirror', default='https://slackware.osuosl.org/slackware64-current')
parser.add_argument('--build-tools', action='store_true')
parser.add_argument('--prepare-only', action='store_true')
parser.add_argument('--profile', type=pathlib.Path, help='additional explicit build packages')
args = parser.parse_args()
work = args.work.resolve()
work.mkdir(parents=True, exist_ok=True)
repo = pathlib.Path(__file__).resolve().parent.parent
base = args.mirror.rstrip('/')
fingerprint = 'EC5649DA401E22ABFA6736EF6A4463C040102233'


def run(*command, **kwargs):
    return subprocess.run(command, check=True, **kwargs)


def download(url, output):
    run('curl', '-fsSL', '--proto', '=https', '--proto-redir', '=https', '--retry', '3', '--max-time', '240', url, '-o', str(output))


for filename in ['GPG-KEY', 'CHECKSUMS.md5', 'CHECKSUMS.md5.asc', 'PACKAGES.TXT']:
    download(base + '/' + filename, work / filename)
gnupg = work / 'gnupg'
gnupg.mkdir(mode=0o700, exist_ok=True)
listing = run('gpg', '--homedir', str(gnupg), '--batch', '--with-colons', '--show-keys', str(work / 'GPG-KEY'), capture_output=True, text=True).stdout
primary = False
fingerprints = []
for line in listing.splitlines():
    if line.startswith('pub:'):
        primary = True
    elif primary and line.startswith('fpr:'):
        fingerprints.append(line.split(':')[9])
        primary = False
if fingerprints != [fingerprint]:
    raise SystemExit('unexpected Slackware signing key')
run('gpg', '--batch', '--yes', '--dearmor', '--output', str(work / 'slackware.gpg'), str(work / 'GPG-KEY'))
run('gpgv', '--keyring', str(work / 'slackware.gpg'), str(work / 'CHECKSUMS.md5.asc'), str(work / 'CHECKSUMS.md5'))
checksums = {}
for line in (work / 'CHECKSUMS.md5').read_text().splitlines():
    match = re.match(r'^([a-f0-9]{32})\s+\*?(?:\./)?(.+)$', line)
    if match:
        checksums[match[2]] = match[1]
if hashlib.md5((work / 'PACKAGES.TXT').read_bytes()).hexdigest() != checksums['PACKAGES.TXT']:
    raise SystemExit('package index checksum mismatch; snapshot changed, retry')
catalog = {}
for record in (work / 'PACKAGES.TXT').read_text().split('PACKAGE NAME:  ')[1:]:
    name = record.splitlines()[0]
    location = re.search(r'PACKAGE LOCATION:  (.+)', record)[1].removeprefix('./')
    catalog[name.rsplit('-', 3)[0]] = location + '/' + name
names = '''aaa_base aaa_glibc-solibs aaa_libraries aaa_terminfo acl attr bash bin
bzip2 coreutils cracklib dialog diffutils e2fsprogs elogind elvis etc file findutils
gawk gettext gmp gnupg grep gzip iproute2 libcgroup libpsl libpwquality libseccomp
libunistring mpfr ncurses net-tools nvi openssl pam patch pcre pcre2 pkgtools
procps-ng sed shadow slackpkg sysfsutils tar time tree utempter util-linux wget
which xz libarchive zstd zlib curl ca-certificates libidn2 brotli nghttp2 nghttp3
ngtcp2 openssl-solibs libffi libxml2 binutils gnupg2 libgcrypt libgpg-error libassuan
npth pinentry libcap libcap-ng gcc glibc make m4 autoconf automake libtool pkgconf
python3 sqlite libtirpc readline expat rpm cpio libssh2 gnutls nettle libtasn1
p11-kit lz4 lua icu4c cyrus-sasl kernel-headers elfutils lzlib'''.split()
if args.build_tools:
    names.extend('gcc-g++ cmake rust popt libuv bison flex ninja llvm libedit scdoc gettext-tools guile gc'.split())
if args.profile:
    names.extend(line.strip() for line in args.profile.read_text().splitlines() if line.strip() and not line.startswith('#'))
names = list(dict.fromkeys(names))
if set(names) - catalog.keys():
    raise SystemExit('unknown explicit packages: ' + str(sorted(set(names) - catalog.keys())))
cache = work / 'current-packages'
cache.mkdir(exist_ok=True)
expected = {pathlib.Path(catalog[name]).name for name in names}
for old in cache.glob('*.txz'):
    if old.name not in expected:
        old.unlink()


def fetch(name):
    path = catalog[name]
    output = cache / pathlib.Path(path).name
    if not output.exists() or hashlib.md5(output.read_bytes()).hexdigest() != checksums[path]:
        partial = output.with_suffix('.part')
        download(base + '/' + path, partial)
        if hashlib.md5(partial.read_bytes()).hexdigest() != checksums[path]:
            raise RuntimeError('package checksum mismatch: ' + path)
        partial.rename(output)
    return hashlib.sha256(output.read_bytes()).hexdigest() + '  ' + output.name


with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    hashes = list(pool.map(fetch, names))
(work / 'snapshot.sha256').write_text('\n'.join(hashes) + '\n')
(work / 'Containerfile').write_text('''FROM docker.io/vbatts/slackware@sha256:9dcaa22275e6a6cb25b9f6690885a321b44c326535ddf752b798dc206b82fd26
COPY current-packages /packages
RUN upgradepkg --install-new /packages/aaa_glibc-solibs-*.txz && \\
    upgradepkg --install-new /packages/aaa_libraries-*.txz && \\
    upgradepkg --install-new /packages/pkgtools-*.txz && \\
    upgradepkg --install-new /packages/*.txz && /sbin/ldconfig && /usr/sbin/update-ca-certificates && test -s /etc/ssl/certs/ca-certificates.crt && rm -rf /packages
''')
image = 'localhost/holypkg-current-tests'
run('podman', 'build', '-t', image, str(work))
if args.prepare_only:
    raise SystemExit(0)
for test in ['archive', 'providers', 'formats', 'lifecycle', 'rootless']:
    options = ['--user', '1000:1000'] if test == 'rootless' else []
    with (work / (test + '.log')).open('w') as log:
        run('podman', 'run', '--rm', *options, '-v', str(repo) + ':/src:ro', image,
            'python3', '/src/tests/' + test + '.py', '/src/zig-out/bin/holypkg', stdout=log, stderr=subprocess.STDOUT)
    print('PASS Slackware-current', test, flush=True)
