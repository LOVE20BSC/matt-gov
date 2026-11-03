#!/usr/bin/env python3
"""Extract external/public function heads and their modifiers from core/src."""
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path("/Users/BigPolarBear/Documents/github/LOVE20BSC/core")
SRC = ROOT / "src"
CONTRACTS = ["LOVE20Token", "Launch", "MemberNFT", "Phase", "Stake", "Submit", "Vote", "Mint"]

KEYWORDS = {
    "public", "external", "internal", "private",
    "pure", "view", "payable", "virtual", "override",
    "returns", "memory", "calldata", "storage",
}

MODIFIER = re.compile(r"^(\w+)(\(.*\))?$")


def clean(text: str) -> str:
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                out[i] = " "; i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            out[i] = out[i + 1] = " "; i += 2
            while i < n and not (text[i] == "*" and i + 1 < n and text[i + 1] == "/"):
                if text[i] != "\n":
                    out[i] = " "
                i += 1
            if i < n:
                out[i] = " "; i += 1
                if i < n:
                    out[i] = " "; i += 1
        elif c in "\"'":
            q = c; out[i] = " "; i += 1
            while i < n:
                if text[i] == "\\":
                    out[i] = " "; i += 1
                    if i < n and text[i] != "\n":
                        out[i] = " "; i += 1
                elif text[i] == q:
                    out[i] = " "; i += 1; break
                else:
                    if text[i] != "\n":
                        out[i] = " "
                    i += 1
        else:
            i += 1
    return "".join(out)


def match_paren(text: str, start: int) -> int:
    depth = 0
    i = start
    while i < len(text):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def split_top(text: str) -> list[str]:
    """Split a modifier tail by top-level whitespace."""
    parts, buf, depth = [], [], 0
    for ch in text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch.isspace() and depth == 0:
            if buf:
                parts.append("".join(buf)); buf = []
        else:
            buf.append(ch)
    if buf:
        parts.append("".join(buf))
    return parts


def parse(path: pathlib.Path):
    raw = path.read_text()
    text = clean(raw)
    results = []
    # depth map
    depth = 0
    depths = []
    for ch in text:
        depths.append(depth)
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
    for m in re.finditer(r"\b(function|constructor)\b", text):
        if depths[m.start()] != 1:
            continue
        kind = m.group(1)
        i = m.end()
        # name
        name = ""
        nm = re.match(r"\s*(\w+)", text[i:])
        if kind == "function" and nm:
            name = nm.group(1)
            i += nm.end()
        # params
        while i < len(text) and text[i].isspace():
            i += 1
        if i >= len(text) or text[i] != "(":
            continue
        end = match_paren(text, i)
        if end < 0:
            continue
        params = raw[i:end + 1]
        rest_start = end + 1
        # head end: first '{' or ';' at paren depth 0
        j, pdepth = rest_start, 0
        while j < len(text):
            ch = text[j]
            if ch == "(":
                pdepth += 1
            elif ch == ")":
                pdepth -= 1
            elif ch in "{;" and pdepth == 0:
                break
            j += 1
        tail = raw[rest_start:j]
        line = raw.count("\n", 0, m.start()) + 1
        visibility, mutability, modifiers = "", "", []
        toks = split_top(clean(tail))
        k = 0
        while k < len(toks):
            tok = toks[k]
            if tok in ("public", "external", "internal", "private"):
                visibility = tok
            elif tok in ("pure", "view", "payable"):
                mutability = tok
            elif tok.startswith("returns("):
                pass
            elif tok == "returns":
                pass
            elif MODIFIER.match(tok) and MODIFIER.match(tok).group(1) not in KEYWORDS:
                mod = tok
                # modifier args follow as separate token starting with '('
                if k + 1 < len(toks) and toks[k + 1].startswith("("):
                    mod += toks[k + 1]; k += 1
                modifiers.append(mod)
            k += 1
        results.append({
            "contract": path.stem, "kind": kind, "name": name or "(constructor)",
            "line": line, "visibility": visibility, "mutability": mutability,
            "modifiers": modifiers, "params": " ".join(params.split()),
        })
    return results


def abi(contract: str):
    p = subprocess.run(
        ["forge", "inspect", contract, "abi", "--json"],
        cwd=ROOT, capture_output=True, text=True,
    )
    if p.returncode != 0:
        return None
    return json.loads(p.stdout)


def main():
    rows = []
    for c in CONTRACTS:
        rows.extend(parse(SRC / f"{c}.sol"))
    out = {"functions": rows, "abi": {}}
    for c in CONTRACTS:
        a = abi(c)
        out["abi"][c] = [
            {
                "type": e.get("type"),
                "name": e.get("name"),
                "inputs": ",".join(i["type"] for i in e.get("inputs", [])),
                "stateMutability": e.get("stateMutability"),
            }
            for e in (a or []) if e.get("type") == "function"
        ]
    json.dump(out, open("/tmp/auth_scan.json", "w"), indent=1)
    for r in rows:
        if r["kind"] != "function":
            continue
        if r["visibility"] in ("public", "external"):
            mark = " ".join(r["modifiers"]) or "-"
            print(f'{r["contract"]}.{r["name"]}\t{r["visibility"]}\t{r["mutability"] or "-"}\t{mark}\tL{r["line"]}')
    print("---ABI counts---")
    for c in CONTRACTS:
        print(c, len(out["abi"][c]))


if __name__ == "__main__":
    main()
