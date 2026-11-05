#!/usr/bin/env python3
"""Static extraction for the group-chat interface-permission review.

This script only reports what is written where: every external/public entry,
its visibility/mutability/modifiers, and the ABI-vs-interface diff. It does not
judge whether an entry should be guarded; that pairing is in the reports.

Usage:
    python3 matt-gov/review/group-chat-api-auth-2026-11/evidence/auth_scan.py
"""

import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[4]
REPO = ROOT / "group-chat"
SRC = REPO / "src"

DECL = re.compile(r"^(abstract contract|contract|library|interface)\s+(\w+)", re.M)
FUNC = re.compile(r"\bfunction\s+(\w+)\s*\(")
MODIFIER = re.compile(r"\bmodifier\s+(\w+)")
VISIBILITY = ("external", "public", "internal", "private")
MUTABILITY = ("view", "pure", "payable", "nonpayable")

CONTRACTS = [
    ("GroupChat", "src/GroupChat.sol:GroupChat", "src/interfaces/IGroupChat.sol:IGroupChat"),
    ("GroupAdmin", "src/GroupAdmin.sol:GroupAdmin", "src/interfaces/IGroupAdmin.sol:IGroupAdmin"),
    ("GroupMember", "src/GroupMember.sol:GroupMember", "src/interfaces/IGroupMember.sol:IGroupMember"),
    (
        "GroupChatBanList",
        "src/GroupChatBanList.sol:GroupChatBanList",
        "src/interfaces/IGroupChatBanList.sol:IGroupChatBanList",
    ),
    (
        "TokenMainManager",
        "src/managers/TokenMainManager.sol:TokenMainManager",
        "src/interfaces/managers/ITokenScopeManagerBase.sol:ITokenScopeManagerBase",
    ),
    (
        "TokenGovManager",
        "src/managers/TokenGovManager.sol:TokenGovManager",
        "src/interfaces/managers/ITokenScopeManagerBase.sol:ITokenScopeManagerBase",
    ),
    (
        "TokenActionMainManager",
        "src/managers/TokenActionMainManager.sol:TokenActionMainManager",
        "src/interfaces/managers/ITokenActionScopeManagerBase.sol:ITokenActionScopeManagerBase",
    ),
    (
        "TokenActionGovManager",
        "src/managers/TokenActionGovManager.sol:TokenActionGovManager",
        "src/interfaces/managers/ITokenActionScopeManagerBase.sol:ITokenActionScopeManagerBase",
    ),
    (
        "AdminBanSource",
        "src/sources/ban/AdminBanSource.sol:AdminBanSource",
        "src/interfaces/sources/ban/IAdminBanSource.sol:IAdminBanSource",
    ),
    (
        "GovVotedBanSource",
        "src/sources/ban/GovVotedBanSource.sol:GovVotedBanSource",
        "src/interfaces/sources/ban/IGovVotedBanSource.sol:IGovVotedBanSource",
    ),
    (
        "GroupJoinScopeSource",
        "src/sources/scope/GroupJoinScopeSource.sol:GroupJoinScopeSource",
        "src/interfaces/sources/scope/IGroupJoinScopeSource.sol:IGroupJoinScopeSource",
    ),
    (
        "GroupMemberScope",
        "src/sources/scope/GroupMemberScope.sol:GroupMemberScope",
        "src/interfaces/sources/scope/IGroupMemberScope.sol:IGroupMemberScope",
    ),
]


def blank_comments(text):
    out = list(text)
    i, n = 0, 0
    while i < n:
        if text[i] == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                out[i] = " "
                i += 1
        elif text[i] == "/" and i + 1 < n and text[i + 1] == "*":
            out[i] = out[i + 1] = " "
            i += 2
            while i < n and not (text[i] == "*" and i + 1 < n and text[i + 1] == "/"):
                if text[i] != "\n":
                    out[i] = " "
                i += 1
            if i < n:
                out[i] = " "
                i += 1
                if i < n:
                    out[i] = " "
                    i += 1
        else:
            i += 1
    return "".join(out)


def match_paren(text, start):
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i
    return -1


def enclosing_unit(text, offset):
    name = kind = "?"
    for m in DECL.finditer(text):
        if m.start() > offset:
            break
        kind, name = m.group(1), m.group(2)
    return kind, name


def scan(path):
    raw = path.read_text()
    text = blank_comments(raw)
    rows = []
    for m in FUNC.finditer(text):
        name = m.group(1)
        open_paren = text.index("(", m.start())
        close_paren = match_paren(text, open_paren)
        if close_paren < 0:
            continue
        tail_start = close_paren + 1
        brace = text.find("{", tail_start)
        semi = text.find(";", tail_start)
        if semi != -1 and (brace == -1 or semi < brace):
            tail_end, has_body = semi, False
        else:
            tail_end, has_body = brace, True
        tail = text[tail_start:tail_end]
        if "returns" in tail:
            tail = tail.split("returns", 1)[0]
        words = re.findall(r"\w+", tail)
        visibility = next((w for w in words if w in VISIBILITY), "public" if not has_body else "-")
        mutability = next((w for w in words if w in MUTABILITY), "nonpayable")
        modifiers = [
            w
            for w in words
            if w not in VISIBILITY
            and w not in MUTABILITY
            and w not in {"virtual", "override", "returns"}
        ]
        kind, unit = enclosing_unit(text, m.start())
        rows.append(
            {
                "file": str(path.relative_to(REPO)),
                "unit": unit,
                "kind": kind,
                "name": name,
                "visibility": visibility,
                "mutability": mutability,
                "modifiers": modifiers,
                "line": raw[: m.start()].count("\n") + 1,
            }
        )
    return rows


def abi(spec):
    raw = subprocess.run(
        ["forge", "inspect", spec, "abi", "--json"],
        cwd=REPO,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return json.loads(raw)


def functions_from_abi(items):
    result = {}
    for item in items:
        if item.get("type") != "function":
            continue
        name = item["name"]
        inputs = tuple(i["type"] for i in item.get("inputs", []))
        outputs = tuple(o["type"] for o in item.get("outputs", []))
        result[name] = {
            "inputs": inputs,
            "outputs": outputs,
            "stateMutability": item.get("stateMutability", "nonpayable"),
        }
    return result


def main():
    print("# group-chat 接口调用权限专项 · 证据输出")
    rev = subprocess.run(
        ["git", "rev-parse", "--short", "HEAD"], cwd=REPO, check=True, capture_output=True, text=True
    ).stdout.strip()
    status = subprocess.run(
        ["git", "status", "--porcelain"], cwd=REPO, check=True, capture_output=True, text=True
    ).stdout.strip()
    print(f"# 基线 group-chat@{rev}  工作树 {len(status.splitlines())} 项改动")

    print("\n## 1. check_caller_auth.py group-chat/src")
    check = subprocess.run(
        ["bash", str(ROOT / "matt-gov" / "script" / "check_caller_auth.sh"), "src"],
        cwd=REPO,
        check=False,
        capture_output=True,
        text=True,
    )
    print(check.stdout.strip() or check.stderr.strip())

    print("\n## 2. ABI 对账（实现 vs 自有接口）")
    for name, contract_spec, interface_spec in CONTRACTS:
        contract = functions_from_abi(abi(contract_spec))
        interface = functions_from_abi(abi(interface_spec))
        missing = sorted(set(contract) - set(interface))
        extra = sorted(set(interface) - set(contract))
        mismatched = []
        for key in sorted(set(contract) & set(interface)):
            if contract[key] != interface[key]:
                mismatched.append(
                    f"{key}: impl={contract[key]} iface={interface[key]}"
                )
        print(f"\n{name} vs {interface_spec.split(':')[-1]}:")
        print(f"  impl={len(contract)} iface={len(interface)}")
        print(f"  impl-only={missing or 'none'}")
        print(f"  iface-only={extra or 'none'}")
        print(f"  mismatched={mismatched or 'none'}")

    print("\n## 3. 函数计数（ABI）")
    for name, contract_spec, _ in CONTRACTS:
        contract = functions_from_abi(abi(contract_spec))
        writes = [k for k, v in contract.items() if v["stateMutability"] not in ("view", "pure")]
        reads = [k for k, v in contract.items() if v["stateMutability"] in ("view", "pure")]
        print(f"{name}: ABI {len(contract)} = 写 {len(writes)} + 读 {len(reads)}")

    print("\n## 4. 鉴权扫描（入口表来源）")
    rows = []
    for path in sorted(SRC.rglob("*.sol")):
        if "interfaces" in path.parts:
            continue
        rows.extend(scan(path))
    rows.sort(key=lambda r: (r["file"], r["line"]))
    header = f"{'unit':24} {'function':30} {'vis':9} {'mut':11} {'modifiers':48} line"
    print(header)
    print("-" * len(header))
    for r in rows:
        if r["visibility"] not in ("external", "public"):
            continue
        print(
            f"{r['unit']:24} {r['name']:30} {r['visibility']:9} {r['mutability']:11} "
            f"{','.join(r['modifiers']) or '-':48} {r['file']}:{r['line']}"
        )

    print("\n## 5. 无 only* modifier 的外部写入口")
    for r in rows:
        if r["visibility"] not in ("external", "public"):
            continue
        if r["mutability"] in ("view", "pure"):
            continue
        if any(m.startswith("only") for m in r["modifiers"]):
            continue
        print(f"{r['unit']}.{r['name']}  {r['file']}:{r['line']}  modifiers={r['modifiers'] or '-'}")

    print("\n## 6. 证据命令")
    print("forge test")
    print("bash matt-gov/script/check_caller_auth.sh src")
    print("forge inspect <path>:<contract> abi --json")


if __name__ == "__main__":
    main()
