#!/usr/bin/env python3
"""Static extraction of every function entry in action/src with its caller-check shape.

This is the source of every entry table in this review folder. It does not judge
whether a write entry *should* be guarded; it only reports what is written where,
so the human review can pair each entry with its authorization subject.

Usage:
    python3 matt-gov/review/action-api-auth-2026-11/evidence/auth_scan.py
"""

import pathlib
import re

SRC = pathlib.Path(__file__).resolve().parents[4] / "action" / "src"

DECL = re.compile(r"^(abstract contract|contract|library|interface)\s+(\w+)", re.M)
FUNC = re.compile(r"\bfunction\s+(\w+)\s*\(")
MODIFIER = re.compile(r"\bmodifier\s+(\w+)")
VISIBILITY = ("external", "public", "internal", "private")
MUTABILITY = ("view", "pure", "payable", "nonpayable")


def blank_comments(text):
    out = list(text)
    i, n = 0, 0
    while i < len(text):
        if text[i] == "/" and i + 1 < len(text) and text[i + 1] == "/":
            while i < len(text) and text[i] != "\n":
                out[i] = " "
                i += 1
        elif text[i] == "/" and i + 1 < len(text) and text[i + 1] == "*":
            out[i] = out[i + 1] = " "
            i += 2
            while i < len(text) and not (text[i] == "*" and i + 1 < len(text) and text[i + 1] == "/"):
                if text[i] != "\n":
                    out[i] = " "
                i += 1
            if i < len(text):
                out[i] = " "
                i += 1
                if i < len(text):
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
        # signature tail runs to the body brace or the terminating semicolon
        brace = text.find("{", tail_start)
        semi = text.find(";", tail_start)
        if semi != -1 and (brace == -1 or semi < brace):
            tail_end, has_body = semi, False
        else:
            tail_end, has_body = brace, True
        tail = text[tail_start:tail_end]
        # modifiers sit before the returns clause; the return list is not part of the signature shape
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
                "file": path.name,
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


def modifier_bodies(path):
    raw = path.read_text()
    text = blank_comments(raw)
    out = []
    for m in MODIFIER.finditer(text):
        name = m.group(1)
        open_paren = text.find("(", m.start())
        close_paren = match_paren(text, open_paren) if open_paren != -1 else -1
        brace = text.find("{", close_paren)
        if brace == -1:
            continue
        depth, end = 0, brace
        for i in range(brace, len(text)):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        body = text[brace:end]
        out.append(
            {
                "file": path.name,
                "name": name,
                "checks_sender": "msg.sender" in body or "_is" in body,
                "reverts": "revert" in body,
                "ends_with_underscore": body.rstrip().rstrip("}").rstrip().endswith("_;"),
                "line": raw[: m.start()].count("\n") + 1,
            }
        )
    return out


def main():
    files = sorted(p for p in SRC.rglob("*.sol") if "interfaces" not in p.parts)
    all_rows, all_mods = [], []
    for path in files:
        all_rows.extend(scan(path))
        all_mods.extend(modifier_bodies(path))

    print("=" * 100)
    print("A. 外部/公开入口（ABI 可见）")
    print("=" * 100)
    print(f"{'unit':<24}{'function':<28}{'vis':<10}{'mut':<12}{'modifiers':<34}line")
    print("-" * 100)
    for r in all_rows:
        if r["visibility"] not in ("external", "public"):
            continue
        if not r["modifiers"] and r["mutability"] in ("view", "pure"):
            continue
        mods = ",".join(r["modifiers"]) or "-"
        print(
            f"{r['unit']:<24}{r['name']:<28}{r['visibility']:<10}"
            f"{r['mutability']:<12}{mods:<34}{r['file']}:{r['line']}"
        )

    print()
    print("=" * 100)
    print("B. 写入口统计（mutability 非 view/pure，且 ABI 可见）")
    print("=" * 100)
    per_unit = {}
    for r in all_rows:
        if r["visibility"] not in ("external", "public"):
            continue
        if r["mutability"] in ("view", "pure"):
            continue
        per_unit.setdefault(r["unit"], []).append(r)
    for unit in sorted(per_unit):
        entries = per_unit[unit]
        guarded = [e for e in entries if e["modifiers"]]
        print(f"{unit:<24} 写入口 {len(entries):>2}  带 modifier {len(guarded):>2}  无 modifier {len(entries) - len(guarded):>2}")
        for e in entries:
            mark = "AUTH" if e["modifiers"] else "NONE"
            print(f"    [{mark}] {e['name']:<26} {','.join(e['modifiers']) or '-'}")
    print()
    total = sum(len(v) for v in per_unit.values())
    print(f"写入口合计: {total}")

    print()
    print("=" * 100)
    print("C. modifier 定义与形状（dev-standards §5.5）")
    print("=" * 100)
    print(f"{'file':<30}{'modifier':<26}{'sender':<8}{'revert':<8}{'ends _;':<9}line")
    print("-" * 100)
    for m in sorted(all_mods, key=lambda x: (x["file"], x["name"])):
        print(
            f"{m['file']:<30}{m['name']:<26}{str(m['checks_sender']):<8}"
            f"{str(m['reverts']):<8}{str(m['ends_with_underscore']):<9}{m['line']}"
        )

    print()
    print("=" * 100)
    print("D. 库的 external 函数（public library 直接调用面）")
    print("=" * 100)
    for r in all_rows:
        if r["kind"] != "library" or r["visibility"] != "external":
            continue
        mut = "view" if r["mutability"] == "view" else "WRITE"
        print(f"{r['unit']:<22}{r['name']:<28}{mut:<8}{','.join(r['modifiers']) or '-'}")


if __name__ == "__main__":
    main()
