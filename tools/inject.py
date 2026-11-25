#!/usr/bin/env python3
"""Inject a dylib into an iOS .ipa by adding an LC_LOAD_DYLIB command.

Pure-python Mach-O surgery - no Xcode, no optool, no insert_dylib required.
Handles thin arm64/arm64e binaries and fat (universal) containers.

Usage:
    python3 inject.py --ipa app.ipa --dylib CFMod.dylib --out app-modded.ipa \
                      [--entry @executable_path/Frameworks/CFMod.dylib] [--sign]
"""

import argparse
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM_64 = 0xCFFAEDFE
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF

LC_SEGMENT_64 = 0x19
LC_CODE_SIGNATURE = 0x1D
LC_LOAD_DYLIB = 0xC

# segment_command_64 layout
SEG64 = struct.Struct("<II16sQQQQiiII")
# section_64 layout: sectname[16] segname[16] addr Q size Q offset I align I reloff I nreloc I flags I r1 I r2 I
SECT64 = struct.Struct("<16s16sQQIIIIIIII")
DYLIB_CMD = struct.Struct("<IIIIII")


class PatchError(Exception):
    pass


def _align8(n):
    return (n + 7) & ~7


def _slice_thin(buf, offset=0, size=None):
    """Patch one thin Mach-O in place inside `buf`; returns bytes patched."""
    if size is None:
        size = len(buf) - offset
    blob = bytearray(buf[offset:offset + size])

    magic = struct.unpack_from("<I", blob, 0)[0]
    if magic != MH_MAGIC_64:
        raise PatchError("not a 64-bit little-endian Mach-O (magic=%#x)" % magic)

    _, cputype, _, filetype, ncmds, sizeofcmds, _, _ = struct.unpack_from("<IIIIIIII", blob, 0)

    cmds_off = 32
    first_section = None
    sig_cmd_off = None
    sig_cmd_size = 0

    p = cmds_off
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", blob, p)
        if cmdsize < 8 or p + cmdsize > len(blob):
            raise PatchError("corrupt load command table")
        if cmd == LC_CODE_SIGNATURE:
            sig_cmd_off, sig_cmd_size = p, cmdsize
        if cmd == LC_SEGMENT_64:
            _, _, segname, vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects, flags = \
                SEG64.unpack_from(blob, p)
            sp = p + SEG64.size
            for _s in range(nsects):
                sect = SECT64.unpack_from(blob, sp)
                off = sect[4]
                if off and (first_section is None or off < first_section):
                    first_section = off
                sp += SECT64.size
        p += cmdsize

    # If a code signature is present, drop it: the new header will not match it
    # and every signer we support rewrites it anyway.
    if sig_cmd_off is not None:
        del blob[sig_cmd_off:sig_cmd_off + sig_cmd_size]
        sizeofcmds -= sig_cmd_size
        ncmds -= 1

    entry = os.environ.get("ZA_DYLIB_ENTRY", "@executable_path/Frameworks/CFMod.dylib")
    path_bytes = entry.encode("utf-8") + b"\0"
    cmd_size = _align8(DYLIB_CMD.size + len(path_bytes))

    header_end = cmds_off + sizeofcmds
    if first_section is None:
        first_section = header_end + cmd_size + 0x1000
    free = first_section - header_end
    if free < cmd_size:
        raise PatchError(
            "not enough header padding: need %d bytes, have %d. "
            "Binary has no room for another load command." % (cmd_size, free))

    cmd = struct.pack("<IIIIII", LC_LOAD_DYLIB, cmd_size, 24, 2, 0x10000, 0x10000)
    cmd += path_bytes
    cmd += b"\0" * (cmd_size - len(cmd))

    blob[header_end:header_end] = cmd
    sizeofcmds += cmd_size
    ncmds += 1
    struct.pack_into("<II", blob, 16, ncmds, sizeofcmds)

    return bytes(blob)


def patch_binary(path, entry):
    os.environ["ZA_DYLIB_ENTRY"] = entry
    with open(path, "rb") as fh:
        data = fh.read()

    magic = struct.unpack_from(">I", data, 0)[0]
    if magic in (FAT_MAGIC, FAT_MAGIC_64):
        nfat = struct.unpack_from(">I", data, 4)[0]
        slices = []
        magic_struct = ">II" if magic == FAT_MAGIC else ">IIQQII"
        base = 8
        for i in range(nfat):
            if magic == FAT_MAGIC:
                cputype, cpusub, off, size, align = struct.unpack_from(">IIIII", data, base)
                base += 20
            else:
                cputype, cpusub, off, size, align, _res = struct.unpack_from(">IIQQII", data, base)
                base += 32
            slices.append((off, size, cputype))
        out = bytearray()
        # rebuild by patching each slice independently and keeping fat header as-is
        out = bytearray(data)
        for off, size, cputype in slices:
            patched = _slice_thin(bytes(out), off, size)
            if len(patched) != size:
                raise PatchError("slice size changed during patch (unsupported)")
            out[off:off + size] = patched
        data = bytes(out)
    else:
        data = _slice_thin(data)

    with open(path, "wb") as fh:
        fh.write(data)


def find_executable(app_dir):
    plist_path = os.path.join(app_dir, "Info.plist")
    with open(plist_path, "rb") as fh:
        info = plistlib.load(fh)
    exe = info.get("CFBundleExecutable")
    if not exe:
        raise PatchError("Info.plist has no CFBundleExecutable")
    exe_path = os.path.join(app_dir, exe)
    if not os.path.isfile(exe_path):
        raise PatchError("executable %s not found in bundle" % exe)
    return exe, exe_path


def ensure_frameworks_dir(app_dir):
    fw = os.path.join(app_dir, "Frameworks")
    os.makedirs(fw, exist_ok=True)
    return fw


def sign_thin(path):
    """Ad-hoc sign so dyld accepts the dylib on TrollStore/jailbroken devices."""
    ldid = shutil.which("ldid")
    if ldid:
        subprocess.run([ldid, "-S", path], check=False)
        return "ldid"
    codesign = shutil.which("codesign")
    if codesign:
        subprocess.run([codesign, "-f", "-s", "-", path], check=False)
        return "codesign"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ipa", required=True)
    ap.add_argument("--dylib", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--entry", default="@executable_path/Frameworks/CFMod.dylib")
    ap.add_argument("--sign", action="store_true")
    args = ap.parse_args()

    work = tempfile.mkdtemp(prefix="ipak-")
    try:
        with zipfile.ZipFile(args.ipa) as zf:
            zf.extractall(work)

        payload = os.path.join(work, "Payload")
        apps = [d for d in os.listdir(payload) if d.endswith(".app")] if os.path.isdir(payload) else []
        if len(apps) != 1:
            raise PatchError("expected exactly one .app in Payload, found %d" % len(apps))
        app_dir = os.path.join(payload, apps[0])

        exe_name, exe_path = find_executable(app_dir)
        print("[*] bundle  : %s" % apps[0])
        print("[*] binary  : %s" % exe_name)

        fw = ensure_frameworks_dir(app_dir)
        dst = os.path.join(fw, os.path.basename(args.dylib))
        shutil.copy2(args.dylib, dst)
        print("[*] dylib   : Frameworks/%s (%d bytes)" % (os.path.basename(dst), os.path.getsize(dst)))

        patch_binary(exe_path, args.entry)
        print("[*] patched : LC_LOAD_DYLIB %s" % args.entry)

        if args.sign:
            who = sign_thin(dst)
            print("[*] sign    : %s" % (who or "no signer available (sign it yourself)"))

        out_path = args.out
        if os.path.exists(out_path):
            os.remove(out_path)
        with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for root, _dirs, files in os.walk(work):
                for f in files:
                    full = os.path.join(root, f)
                    rel = os.path.relpath(full, work)
                    zf.write(full, rel)
        print("[+] wrote %s (%.1f MB)" % (out_path, os.path.getsize(out_path) / 1e6))
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    try:
        main()
    except PatchError as e:
        print("[!] %s" % e, file=sys.stderr)
        sys.exit(1)
