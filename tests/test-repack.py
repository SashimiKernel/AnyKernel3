"""Exercise the real ARM magiskboot and AK3 core using AOSP boot fixtures.

Usage: python3 tests/test-repack.py /path/to/qemu-arm-static /path/to/mkbootimg.py
The fixture generator is AOSP platform/system/tools/mkbootimg.
"""
from pathlib import Path
import hashlib
import os
import shlex
import shutil
import struct
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
qemu, mkbootimg = (Path(p).resolve() for p in sys.argv[1:])

def run(args, cwd=None, allowed=(0,)):
    result = subprocess.run([str(x) for x in args], cwd=cwd, capture_output=True, text=True)
    if result.returncode not in allowed:
        raise AssertionError(f'{args}: exit {result.returncode}\n{result.stdout}\n{result.stderr}')
    return result

with tempfile.TemporaryDirectory() as temporary:
    base = Path(temporary)
    tools = base / 'tools'
    tools.mkdir()
    for name in ('busybox', 'magiskboot'):
        binary = tools / (name + '.arm')
        shutil.copyfile(root / 'tools' / name, binary)
        binary.chmod(0o755)
        wrapper = tools / name
        wrapper.write_text('#!/bin/sh\nexec ' + shlex.join([str(qemu), str(binary)]) + ' "$@"\n')
        wrapper.chmod(0o755)
    mb = tools / 'magiskboot'
    bb = tools / 'busybox'
    for name in ('cpio',):
        wrapper = tools / name
        wrapper.write_text('#!/bin/sh\nexec ' + shlex.join([str(bb), name]) + ' "$@"\n')
        wrapper.chmod(0o755)
    init = base / 'init.rc'
    init.write_text('on early-init\n    setprop sashimi.fixture preserved\n')
    ramdisk = base / 'fixture.cpio'
    run([mb, 'cpio', ramdisk, f'add 0644 init.rc {init}'])
    old_kernel = base / 'old.Image'
    new_kernel = bytes(56) + b'ARM\x64' + bytes(range(256)) * 128
    old_kernel.write_bytes(bytes(56) + b'ARM\x64' + b'old-kernel' * 4096)
    def dtb(cpu):
        # Empty, structurally valid flattened device tree with a distinct boot CPU.
        return struct.pack('>10I', 0xd00dfeed, 72, 56, 72, 40, 17, 16, cpu, 0, 16) + bytes(16) + struct.pack('>4I', 1, 0, 2, 9)
    old_dtb = base / 'old.dtb'
    old_dtb.write_bytes(dtb(0))
    for kind, version in [('boot', 3), ('vendor', 3)]:
        work = base / f'{kind}{version}'
        work.mkdir()
        (work / 'anykernel.sh').write_text('do.modules=0\n')
        if kind == 'vendor':
            src = work / 'built-modules'
            src.mkdir()
            (src / 'mmi_relay.ko').write_bytes(b'sashimi-recovery-module-fixture')
            (src / 'modules.dep').write_text('mmi_relay.ko:\n')
            (src / 'modules.load').write_text('mmi_relay.ko\n')
            (src / 'modules.alias').write_text('alias fixture mmi_relay\n')
            for name in ('modules-load-recovery.txt', 'no-load.txt'):
                shutil.copyfile(root / name, work / name)
            run(['bash', root / 'place-modules.sh', src, work / 'modules/vendor/lib/modules', '/vendor/lib/modules'], cwd=work)
            # Original setup_ak stages vendor_ramdisk as the vendor boot's RAMDISK.
            assert 'mv -f vendor_ramdisk vendor_boot-files/ramdisk;' in (root / 'tools/ak3-core.sh').read_text()
            (work / 'vendor_ramdisk').rename(work / 'ramdisk')
        partition = work / 'original.img'
        command = [sys.executable, mkbootimg, '--header_version', str(version)]
        if kind == 'boot':
            command += ['--kernel', old_kernel, '--ramdisk', ramdisk, '--output', partition]
            (work / 'Image').write_bytes(new_kernel)
        else:
            command += ['--pagesize', '4096', '--vendor_ramdisk', ramdisk, '--dtb', old_dtb,
                        '--vendor_boot', partition, '--vendor_cmdline', 'sashimi.fixture=preserved']
            if version == 4:
                command += ['--ramdisk_type', 'dlkm', '--ramdisk_name', 'dlkm',
                            '--vendor_ramdisk_fragment', ramdisk]
            (work / 'dtb').write_bytes(dtb(1))
        run(command)
        with partition.open('ab') as stream:
            stream.write(bytes(1024 * 1024 - stream.tell()))
        original = hashlib.sha256(partition.read_bytes()).digest()
        core = (root / 'tools/ak3-core.sh').read_text()
        assert core.endswith('setup_ak;\n')
        definitions = work / 'core-functions.sh'
        definitions.write_text(core[:-len('setup_ak;\n')])
        script = work / 'prepare.sh'
        script.write_text(f'''AKHOME={shlex.quote(str(work))}; OUTFD=1;
. {shlex.quote(str(definitions))}
BIN={shlex.quote(str(tools))}; PATH="$BIN:$PATH";
BLOCK={shlex.quote(str(partition))}; RAMDISK_COMPRESSION=auto; PATCH_VBMETA_FLAG=auto;
ui_print() {{ :; }}
abort() {{ echo "$*" >&2; exit 1; }}
dump_boot;
repack_ramdisk;
prepare_boot;
[ "$BOOT_PREPARED_FOR" = "$BLOCK" ] && [ -s "$AKHOME/boot-new.img" ];
''')
        run([bb, 'ash', script], cwd=work)
        assert hashlib.sha256(partition.read_bytes()).digest() == original, 'prepare_boot wrote the partition'
        extracted = work / 'check'
        extracted.mkdir()
        run([mb, 'unpack', '-h', work / 'boot-new.img'], cwd=extracted, allowed=(0, 3))
        if kind == 'boot':
            assert (extracted / 'kernel').read_bytes() == new_kernel
            archives = [extracted / 'ramdisk.cpio']
        else:
            assert (extracted / 'dtb').read_bytes() == dtb(1)
            assert 'sashimi.fixture=preserved' in (extracted / 'header').read_text()
            archives = ([extracted / 'ramdisk.cpio'] if version == 3 else
                        sorted((extracted / 'vendor_ramdisk').glob('*.cpio')))
            assert len(archives) == (1 if version == 3 else 2)
        for number, archive in enumerate(archives):
            entry = extracted / f'init-{number}.rc'
            run([mb, 'cpio', archive, f'extract init.rc {entry}'])
            assert entry.read_bytes() == init.read_bytes()
        if kind == 'vendor':
            module = extracted / 'mmi_relay.ko'
            recovery = extracted / 'modules.load.recovery'
            run([mb, 'cpio', archives[0], f'extract lib/modules/mmi_relay.ko {module}'])
            run([mb, 'cpio', archives[0], f'extract lib/modules/modules.load.recovery {recovery}'])
            assert module.read_bytes() == b'sashimi-recovery-module-fixture'
            assert recovery.read_text().splitlines() == ['mmi_relay.ko']
            print('PASS: recovery module and load list retained with do.modules=0')
        print(f'PASS: {kind} v{version}, prepare without writes, payload and ramdisk preservation')
