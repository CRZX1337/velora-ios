#!/usr/bin/env python3
"""Verifies a packaged Velora IPA.

Checks the bundle layout, the identity keys the app must keep, the packaged
privacy manifest against its source, the flattened icons, the arm64 Mach-O and
the ad-hoc code signature. Exits non-zero and prints ::error:: annotations when
anything deviates.

Usage: scripts/verify-ipa.py <path/to/Velora.ipa>
"""

from __future__ import annotations

import hashlib
import os
import plistlib
import struct
import sys
import zipfile

EXPECTED_ENTRIES = [
    "Payload/Speedometer.app/AppIcon60x60@2x.png",
    "Payload/Speedometer.app/AppIcon60x60@3x.png",
    "Payload/Speedometer.app/Info.plist",
    "Payload/Speedometer.app/PrivacyInfo.xcprivacy",
    "Payload/Speedometer.app/Speedometer",
]

EXPECTED_INFO = {
    "CFBundleIdentifier": "com.velora.app",
    "CFBundleDisplayName": "Velora",
    "CFBundleExecutable": "Speedometer",
    "CFBundleName": "Velora",
    "CFBundleShortVersionString": "1.0",
    "MinimumOSVersion": "26.0",
    "LSRequiresIPhoneOS": True,
    "UIDeviceFamily": [1],
}

EXPECTED_APIS = {
    "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
    "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
}

ICONS = (("AppIcon60x60@2x.png", 120), ("AppIcon60x60@3x.png", 180))
BUNDLE_ROOT = "Payload/Speedometer.app"
LC_CODE_SIGNATURE = 0x1D
CSMAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
MH_MAGIC_64 = 0xFEEDFACF
CPU_TYPE_ARM64 = 0x0100000C
MH_EXECUTE = 2


def collect_problems(ipa: str, source_manifest: str) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    archive = zipfile.ZipFile(ipa)
    names = archive.namelist()

    for entry in EXPECTED_ENTRIES:
        if entry not in names:
            problems.append(f"missing entry: {entry}")
    unexpected = sorted(set(names) - set(EXPECTED_ENTRIES))
    if unexpected:
        problems.append(f"unexpected entries: {unexpected}")

    info = plistlib.loads(archive.read(f"{BUNDLE_ROOT}/Info.plist"))
    for key, value in EXPECTED_INFO.items():
        if info.get(key) != value:
            problems.append(f"Info.plist {key} is {info.get(key)!r}, expected {value!r}")

    icons = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {})
    if icons.get("CFBundleIconFiles") != ["AppIcon60x60"]:
        problems.append(f"unexpected CFBundleIconFiles: {icons.get('CFBundleIconFiles')!r}")
    if "NSLocationWhenInUseUsageDescription" not in info:
        problems.append("missing NSLocationWhenInUseUsageDescription")

    manifest = plistlib.loads(archive.read(f"{BUNDLE_ROOT}/PrivacyInfo.xcprivacy"))
    with open(source_manifest, "rb") as handle:
        source = plistlib.load(handle)
    if manifest != source:
        problems.append(f"packaged privacy manifest differs from {source_manifest}")

    declared = {
        entry["NSPrivacyAccessedAPIType"]: entry["NSPrivacyAccessedAPITypeReasons"]
        for entry in manifest["NSPrivacyAccessedAPITypes"]
    }
    if declared != EXPECTED_APIS:
        problems.append(f"unexpected privacy APIs: {declared}")
    if manifest["NSPrivacyTracking"] is not False:
        problems.append("NSPrivacyTracking must be false")

    for name, size in ICONS:
        data = archive.read(f"{BUNDLE_ROOT}/{name}")
        width, height = struct.unpack(">II", data[16:24])
        if (width, height) != (size, size):
            problems.append(f"{name} is {width}x{height}, expected {size}x{size}")

    binary = archive.read(f"{BUNDLE_ROOT}/Speedometer")
    magic, cpu, _subtype, filetype = struct.unpack("<IiiI", binary[:16])
    if magic != MH_MAGIC_64:
        problems.append(f"executable is not a 64-bit Mach-O (magic {magic:#x})")
    if cpu != CPU_TYPE_ARM64:
        problems.append(f"executable is not arm64 (cputype {cpu:#x})")
    if filetype != MH_EXECUTE:
        problems.append(f"executable is not MH_EXECUTE (filetype {filetype})")

    signature = None
    offset = 32
    for _ in range(struct.unpack("<I", binary[16:20])[0]):
        command, command_size = struct.unpack("<II", binary[offset : offset + 8])
        if command == LC_CODE_SIGNATURE:
            data_offset, data_size = struct.unpack("<II", binary[offset + 8 : offset + 16])
            signature = binary[data_offset : data_offset + data_size]
        offset += command_size

    if signature is None:
        problems.append("executable carries no LC_CODE_SIGNATURE (unsigned)")
    else:
        signature_magic = struct.unpack(">I", signature[:4])[0]
        if signature_magic != CSMAGIC_EMBEDDED_SIGNATURE:
            problems.append(f"unexpected code signature magic {signature_magic:#x}")

    print(f"IPA: {ipa} ({os.path.getsize(ipa)} bytes, sha256 {hashlib.sha256(open(ipa, 'rb').read()).hexdigest()})")
    print(f"Entries: {names}")
    print(
        "Bundle: "
        f"{info['CFBundleIdentifier']} / {info['CFBundleDisplayName']} / "
        f"iOS {info['MinimumOSVersion']} / {info['CFBundleExecutable']}"
    )
    print(f"Privacy APIs: {declared}, tracking={manifest['NSPrivacyTracking']}")
    print(f"Signature: {'ad-hoc superblob present' if signature is not None else 'none'}")
    return problems, names


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: verify-ipa.py <path/to/Velora.ipa>", file=sys.stderr)
        return 2

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    source_manifest = os.path.join(root, "App", "Resources", "PrivacyInfo.xcprivacy")
    problems, _names = collect_problems(argv[1], source_manifest)

    for problem in problems:
        print(f"::error::{problem}")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
