#!/usr/bin/env python3
"""Test the native doas PAM policy and cache timeout in a disposable container."""
import errno
import os
import pathlib
import pty
import pwd
import select
import signal
import subprocess
import time

assert os.geteuid() == 0 and pathlib.Path('/run/.containerenv').exists(), 'disposable Podman container required'
try:
    pwd.getpwnam('owenewans')
except KeyError:
    subprocess.run(['useradd', '-m', '-g', 'users', '-s', '/bin/sh', 'owenewans'], check=True)
subprocess.run(['chpasswd'], input='owenewans:owenewans\n', text=True, check=True)
policy = pathlib.Path('/etc/doas.conf')
subprocess.run(['usermod', '-a', '-G', 'wheel', 'owenewans'], check=True)
policy.write_text('permit persist :wheel\n')
policy.chmod(0o600)
config = pathlib.Path('/etc/doas-persist.conf')


def session(command, password=False):
    child, fd = pty.fork()
    if child == 0:
        account = pwd.getpwnam('owenewans')
        os.chown(os.ttyname(0), account.pw_uid, account.pw_gid)
        os.initgroups(account.pw_name, account.pw_gid)
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)
        os.execv('/bin/sh', ['sh', '-c', command])
    output = bytearray()
    sent = False
    deadline = time.monotonic() + 20
    try:
        while time.monotonic() < deadline:
            if select.select([fd], [], [], 0.2)[0]:
                try:
                    part = os.read(fd, 65536)
                except OSError as exc:
                    if exc.errno == errno.EIO:
                        break
                    raise
                if not part:
                    break
                output.extend(part)
                if password and not sent and b'password:' in output.lower():
                    os.write(fd, b'owenewans\n')
                    sent = True
        else:
            os.killpg(child, signal.SIGKILL)
            raise AssertionError('authentication session timed out: ' + output.decode(errors='replace'))
        _, status = os.waitpid(child, 0)
        return os.waitstatus_to_exitcode(status), output.decode(errors='replace')
    finally:
        os.close(fd)


config.write_text('2\n')
config.chmod(0o644)
status, output = session('set -e; doas id -u; doas -n id -u; sleep 3; if doas -n true; then exit 9; else printf "CACHE_EXPIRED\\n"; fi', password=True)
assert status == 0 and 'CACHE_EXPIRED' in output, output
assert output.replace('\r', '').splitlines().count('0') >= 2, output
print('PASS password authentication, cache reuse and two-second expiration')
config.write_text('0\n')
status, output = session('set -e; doas true; if doas -n true; then exit 9; else printf "NO_CACHE\\n"; fi', password=True)
assert status == 0 and 'NO_CACHE' in output, output
print('PASS zero timeout requires authentication for each command')
for value in ['-1\n', '86401\n', 'two\n', '2\x00extra']:
    config.write_text(value)
    status, output = session('doas -n true')
    assert status != 0 and 'timeout' in output, output
config.write_text('2\n')
config.chmod(0o666)
status, output = session('doas -n true')
assert status != 0 and 'permissions' in output, output
config.chmod(0o644)
os.chown(config, pwd.getpwnam('owenewans').pw_uid, 100)
status, output = session('doas -n true')
assert status != 0 and 'ownership' in output, output
os.chown(config, 0, 0)
config.unlink()
config.symlink_to('/tmp/doas-timeout')
pathlib.Path('/tmp/doas-timeout').write_text('2\n')
status, output = session('doas -n true')
assert status != 0 and 'doas-persist.conf' in output, output
config.unlink()
os.mkfifo(config)
status, output = session('doas -n true')
assert status != 0 and 'permissions' in output, output
config.unlink()
config.write_text('300\n')
config.chmod(0o644)
print('PASS malformed, writable, untrusted-owner and symlink configurations rejected')
