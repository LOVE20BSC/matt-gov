#!/usr/bin/env python3
"""ABI surface diff between each contract and its declared interface.

Usage (from core/):
    export PATH="$HOME/.foundry/bin:$PATH"
    forge build
    python3 ../matt-gov/review/core-review-plan-2026-11/evidence/abi-diff.py

Compares out/<Contract>.sol/<Contract>.json against out/<Interface>.sol/<Interface>.json
after normalising each entry to (type, name, inputs, outputs, stateMutability).
"""

import json
import os

PAIRS = [
    ("Stake", "IStake"),
    ("Mint", "IMint"),
    ("Launch", "ILaunch"),
    ("MemberNFT", "IMemberNFT"),
    ("Submit", "ISubmit"),
    ("Vote", "IVote"),
    ("Phase", "IPhase"),
    ("LOVE20Token", "ILOVE20Token"),
]


def signatures(path):
    with open(path) as handle:
        payload = json.load(handle)
    found = set()
    for entry in payload["abi"]:
        kind = entry["type"]
        if kind == "constructor":
            found.add(("constructor", tuple(i["type"] for i in entry["inputs"])))
        elif kind in ("receive", "fallback"):
            found.add((kind,))
        elif kind in ("function", "event", "error"):
            found.add((
                kind,
                entry.get("name"),
                tuple(i["type"] for i in entry.get("inputs", [])),
                tuple(o["type"] for o in entry.get("outputs", [])),
                entry.get("stateMutability"),
            ))
    return found


def main():
    for contract, interface in PAIRS:
        impl_path = f"out/{contract}.sol/{contract}.json"
        iface_path = f"out/{interface}.sol/{interface}.json"
        if not os.path.exists(impl_path) or not os.path.exists(iface_path):
            print(f"{contract}: missing artifact")
            continue
        impl = signatures(impl_path)
        iface = signatures(iface_path)
        missing = sorted(iface - impl)
        extra = sorted(impl - iface)
        print(f"== {contract} vs {interface}: iface={len(iface)} impl={len(impl)}")
        if missing:
            print("  declared but NOT implemented:")
            for item in missing:
                print(f"    {item}")
        if extra:
            print("  implemented but NOT declared:")
            for item in extra:
                print(f"    {item}")
        if not missing and not extra:
            print("  exact match")


if __name__ == "__main__":
    main()
