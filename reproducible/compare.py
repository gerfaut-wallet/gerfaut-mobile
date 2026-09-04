#!/usr/bin/env python3
"""Compare two APKs entry by entry, ignoring the signature.

Two uses:

  compare.py a.apk b.apk
      Two rebuilds of the same commit. Any difference is a bug.

  compare.py --signed released.apk rebuilt-unsigned.apk
      A published release against your own unsigned rebuild. The APK
      signing block and the v1 signature files under META-INF are
      expected to differ and are skipped; everything else must match.

Exit code 0 means the two APKs carry the same payload.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
import zipfile

V1_SIGNATURE_SUFFIXES = (".SF", ".RSA", ".DSA", ".EC")


def is_v1_signature(name: str) -> bool:
    if not name.startswith("META-INF/"):
        return False
    return name.endswith(V1_SIGNATURE_SUFFIXES) or name == "META-INF/MANIFEST.MF"


def entries(path: str, skip_signature: bool) -> dict[str, tuple]:
    found = {}
    with zipfile.ZipFile(path) as zf:
        for info in zf.infolist():
            if skip_signature and is_v1_signature(info.filename):
                continue
            digest = hashlib.sha256(zf.read(info)).hexdigest()
            found[info.filename] = (info.compress_type, info.CRC, info.file_size, digest)
    return found


def sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("first")
    parser.add_argument("second")
    parser.add_argument(
        "--signed",
        action="store_true",
        help="the first APK is signed: skip the v1 signature files",
    )
    args = parser.parse_args()

    left = entries(args.first, args.signed)
    right = entries(args.second, args.signed)

    if not args.signed:
        first_hash, second_hash = sha256(args.first), sha256(args.second)
        if first_hash == second_hash:
            print(f"identical: {first_hash}")
            return 0
        print(f"{args.first}: {first_hash}")
        print(f"{args.second}: {second_hash}")

    problems = 0
    for name in sorted(set(left) - set(right)):
        print(f"only in {args.first}: {name}")
        problems += 1
    for name in sorted(set(right) - set(left)):
        print(f"only in {args.second}: {name}")
        problems += 1
    for name in sorted(set(left) & set(right)):
        if left[name] != right[name]:
            print(f"differs: {name}")
            print(f"    {args.first}: {left[name]}")
            print(f"    {args.second}: {right[name]}")
            problems += 1

    order_left = [n for n in left if n in right]
    order_right = [n for n in right if n in left]
    if problems == 0 and order_left != order_right:
        print("entries carry the same content but in a different order")
        problems += 1

    if problems:
        print(f"\n{problems} difference(s)")
        return 1

    if args.signed:
        print("payload identical, only the signature differs")
    else:
        print("payload identical, but the files are not byte for byte equal")
    return 0


if __name__ == "__main__":
    sys.exit(main())
