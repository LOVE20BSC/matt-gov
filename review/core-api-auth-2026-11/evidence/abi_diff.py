#!/usr/bin/env python3
"""Diff each contract ABI against its own interface ABI."""
import json
import subprocess

ROOT = "/Users/BigPolarBear/Documents/github/LOVE20BSC/core"
PAIRS = [
    ("LOVE20Token", "ILOVE20Token"),
    ("Launch", "ILaunch"),
    ("MemberNFT", "IMemberNFT"),
    ("Phase", "IPhase"),
    ("Stake", "IStake"),
    ("Submit", "ISubmit"),
    ("Vote", "IVote"),
    ("Mint", "IMint"),
]


def abi(name):
    p = subprocess.run(["forge", "inspect", name, "abi", "--json"], cwd=ROOT, capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit(f"inspect {name} failed: {p.stderr[:400]}")
    return json.loads(p.stdout)


def sig(e):
    return f'{e["name"]}({",".join(i["type"] for i in e.get("inputs", []))})'


def table(entries):
    return {sig(e): e.get("stateMutability") for e in entries if e.get("type") == "function"}


for impl, iface in PAIRS:
    a, b = table(abi(impl)), table(abi(iface))
    extra = sorted(set(a) - set(b))
    missing = sorted(set(b) - set(a))
    print(f"### {impl} vs {iface}: impl={len(a)} iface={len(b)}")
    print(f"  impl-only ({len(extra)}):")
    for s in extra:
        print(f"    + {s}  [{a[s]}]")
    if missing:
        print(f"  iface-only ({len(missing)}):")
        for s in missing:
            print(f"    - {s}  [{b[s]}]")
    mutdiff = [(s, a[s], b[s]) for s in sorted(set(a) & set(b)) if a[s] != b[s]]
    if mutdiff:
        print("  mutability mismatch:")
        for s, x, y in mutdiff:
            print(f"    ! {s}: impl={x} iface={y}")
