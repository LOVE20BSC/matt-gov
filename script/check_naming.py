#!/usr/bin/env python3
"""Check function and state-variable naming against matt-gov/docs/naming-standards.md.

Usage:
  python3 matt-gov/script/check_naming.py                  # report violations
  python3 matt-gov/script/check_naming.py --check          # fail on regressions vs baseline
  python3 matt-gov/script/check_naming.py --update-baseline # rewrite registry/naming-baseline.txt

The baseline is a per-file-symbol list, not a count: a fixed site and a new violation
elsewhere cannot cancel out. Burn it down; never add to it except when a rename is in flight.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPOS = ("core", "action", "group-chat", "libs")
BASELINE = ROOT / "matt-gov" / "registry" / "naming-baseline.txt"

# Interface-mandated names: EIP-721/20/165 and the Uniswap V2 surface.
STD_EXEMPT = {
    "ownerOf", "balanceOf", "totalSupply", "allowance", "transfer", "transferFrom",
    "approve", "supportsInterface", "tokenURI", "name", "symbol", "decimals",
    "getReserves", "getAmountsOut", "getPair", "token0", "token1", "factory",
}

BANNED_VERBS = ("get", "fetch", "query", "read", "load", "do", "handle", "process", "manage")
MEMBER_KEYS = {"memberId", "voterId", "verifierId", "providerId", "recipientId", "adminId"}
BANNED_TOKENS = {
    "num", "amt", "addr", "cnt", "idx", "len", "val", "tmp", "temp",
    "arr", "str", "mgr", "cfg", "args", "param",
}
BARE_NAMES = {"state", "states", "data", "info", "tmp", "temp", "foo", "bar", "baz"}
ENTITY_NAMES = {"token", "group", "member", "sender", "owner", "voter", "provider", "recipient"}
PREDICATE = re.compile(r"^(is|has|can|should)[A-Z]")
UPPER = re.compile(r"^[A-Z][A-Z0-9_]*$")
CAMEL = re.compile(r"^[a-z][A-Za-z0-9]*$")
PASCAL = re.compile(r"^[A-Z][A-Za-z0-9]*$")

VIS = ("public", "external", "internal", "private")


def strip_comments(text: str) -> str:
    """Blank out comments and string bodies while preserving offsets."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                out[i] = " "
                i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            while i < n and not (text[i] == "*" and i + 1 < n and text[i + 1] == "/"):
                if text[i] != "\n":
                    out[i] = " "
                i += 1
            for j in (i, i + 1):
                if j < n and text[j] != "\n":
                    out[j] = " "
            i += 2
        elif c in "\"'":
            q = c
            i += 1
            while i < n and text[i] != q:
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] != "\n":
                    out[i] = "x"
                i += 1
            i += 1
        else:
            i += 1
    return "".join(out)


def split_top(body: str, base: int):
    """Yield (kind, header, inner, pos) for top-level statements of a contract body."""
    i, n = 0, len(body)
    buf, buf_start = [], 0
    while i < n:
        c = body[i]
        if c == "{":
            header = "".join(buf).strip()
            d, i = 1, i + 1
            start = i
            while i < n and d:
                if body[i] == "{":
                    d += 1
                elif body[i] == "}":
                    d -= 1
                i += 1
            yield ("block", header, body[start:i - 1], base + buf_start)
            buf, buf_start = [], i
        elif c == ";":
            yield ("stmt", "".join(buf).strip(), "", base + buf_start)
            buf, buf_start = [], i + 1
            i += 1
        else:
            if not buf:
                buf_start = i
            buf.append(c)
            i += 1


def params_of(s: str):
    s = s.strip()
    if not s:
        return []
    parts, depth, cur = [], 0, []
    for ch in s:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    if cur:
        parts.append("".join(cur).strip())
    out = []
    for p in parts:
        toks = [t for t in p.split() if t not in ("calldata", "memory", "storage", "payable", "indexed")]
        if not toks:
            continue
        if len(toks) == 1:
            out.append(("", toks[0]))
        else:
            out.append((toks[0], toks[-1]))
    return out


def tokens_of(name: str):
    parts = re.split(r"_", name)
    out = []
    for p in parts:
        out += [t for t in re.findall(r"[A-Z]+(?![a-z])|[A-Z][a-z0-9]*|[a-z0-9]+", p)]
    return out


def by_keys(name: str):
    """By<Key> segments, with a trailing Count/Total stripped from the last one."""
    segs = re.split(r"By(?=[A-Z])", name)[1:]
    out = []
    for i, s in enumerate(segs):
        if i == len(segs) - 1:
            s = re.sub(r"(Count|Total)$", "", s)
        if s:
            out.append(s)
    return out


class File:
    def __init__(self, path: Path, repo: str):
        self.path = path
        self.repo = repo
        self.raw = path.read_text(encoding="utf-8")
        self.src = strip_comments(self.raw)
        self.rel = str(path.relative_to(ROOT))
        self.contracts = []  # dicts
        self.structs = []
        self.enums = []
        self._parse()

    def line(self, pos: int) -> int:
        return self.src.count("\n", 0, pos) + 1

    def _parse(self):
        for m in re.finditer(r"\b(contract|interface|library)\s+(\w+)", self.src):
            depth = self.src.count("{", 0, m.start()) - self.src.count("}", 0, m.start())
            if depth != 0:
                continue
            i = m.end()
            while i < len(self.src) and self.src[i] != "{":
                i += 1
            if i >= len(self.src):
                continue
            start, d = i + 1, 1
            j = i + 1
            while j < len(self.src) and d:
                if self.src[j] == "{":
                    d += 1
                elif self.src[j] == "}":
                    d -= 1
                j += 1
            rec = dict(kind=m.group(1), name=m.group(2), line=self.line(m.start()),
                       functions=[], state=[], modifiers=[])
            self.contracts.append(rec)
            body = self.src[start:j - 1]
            self._body(rec, body, start)
        # file-level structs and enums
        for m in re.finditer(r"^\s*(struct|enum)\s+(\w+)", self.src, re.M):
            depth = self.src.count("{", 0, m.start()) - self.src.count("}", 0, m.start())
            if depth != 0:
                continue
            self._type_decl(m.group(1), m.group(2), m.start())

    def _type_decl(self, kind, name, pos):
        i = self.src.index("{", pos)
        d, j = 1, i + 1
        while j < len(self.src) and d:
            if self.src[j] == "{":
                d += 1
            elif self.src[j] == "}":
                d -= 1
            j += 1
        inner = self.src[i + 1:j - 1]
        if kind == "struct":
            fields = []
            for part in inner.split(";"):
                toks = part.split()
                if len(toks) >= 2:
                    fields.append((toks[0], toks[-1]))
            self.structs.append(dict(name=name, fields=fields, line=self.line(pos), kind="struct"))
        else:
            self.enums.append(dict(name=name, values=[v.strip() for v in inner.split(",") if v.strip()],
                                   line=self.line(pos), kind="enum"))

    def _body(self, rec, body, base):
        for kind, header, inner, pos in split_top(body, base):
            h = re.sub(r"\s+", " ", header).strip()
            if h.startswith("function"):
                m = re.match(r"function\s+(\w+)\s*\((.*?)\)(.*)$", h)
                if not m:
                    continue
                rest = m.group(3)
                rec["functions"].append(dict(
                    name=m.group(1),
                    params=params_of(m.group(2)),
                    vis=next((v for v in VIS if re.search(r"\b" + v + r"\b", rest)), ""),
                    mut="view" if re.search(r"\bview\b", rest) else ("pure" if re.search(r"\bpure\b", rest) else ""),
                    returns=re.search(r"\breturns\s*\((.*)\)", rest).group(1) if re.search(r"\breturns\s*\(", rest) else "",
                    line=self.line(pos),
                ))
            elif h.startswith("constructor") or h.startswith("fallback") or h.startswith("receive"):
                continue
            elif h.startswith("modifier"):
                m = re.match(r"modifier\s+(\w+)", h)
                if m:
                    rec["modifiers"].append(dict(name=m.group(1), line=self.line(pos)))
            elif h.startswith("struct") or h.startswith("enum"):
                self._type_decl(h.split()[0], h.split()[1], pos)
            elif kind == "stmt":
                st = re.sub(r"\s+", " ", header).strip()
                if not st or st.startswith(("using ", "event ", "error ", "type ", "import ", "pragma ")):
                    continue
                mm = re.match(r"(mapping\s*\(.*?\)|\S+)\s*(.*)$", st)
                if not mm:
                    continue
                ty, rest = mm.group(1), mm.group(2)
                rt = rest.split()
                vis = next((v for v in VIS if v in rt), "")
                if not vis:
                    continue
                kd = "constant" if "constant" in rt else ("immutable" if "immutable" in rt else "")
                names = [w for w in rt if re.match(r"^[A-Za-z_]\w*$", w)
                         and w not in VIS + ("constant", "immutable", "override")]
                if not names:
                    continue
                rec["state"].append(dict(type=ty, name=names[0], vis=vis, kind=kd, line=self.line(pos)))


def collect():
    files = []
    for repo in REPOS:
        for p in sorted((ROOT / repo / "src").rglob("*.sol")):
            files.append(File(p, repo))
    return files


def check(files):
    out = []

    def add(rule, sym, f, line, msg):
        out.append(dict(rule=rule, repo=f.repo, file=f.rel, line=line, symbol=sym, msg=msg))

    for f in files:
        for c in f.contracts:
            if c["kind"] == "interface" and not re.match(r"^I[A-Z]\w*$", c["name"]):
                add("N15", c["name"], f, c["line"], "接口名必须是 I + PascalCase")
            for fn in c["functions"]:
                name, line = fn["name"], fn["line"]
                base = name.lstrip("_")
                frozen_getter = bool(UPPER.match(base))
                if not CAMEL.match(base) and not frozen_getter:
                    add("N01", name, f, line, "函数名必须 lowerCamelCase（冻结值 getter 除外）")
                if name.startswith("_") and fn["vis"] in ("public", "external"):
                    add("N19", name, f, line, "public/external 函数不得带 _ 前缀")
                if not name.startswith("_") and fn["vis"] in ("internal", "private") and c["kind"] != "library":
                    add("N19", name, f, line, "internal/private 函数必须带 _ 前缀")
                low = name.lower()
                if name not in STD_EXEMPT and any(low.startswith(v) and name[len(v):len(v) + 1].isupper() for v in BANNED_VERBS):
                    add("N02", name, f, line, "禁用动词前缀 " + "/".join(BANNED_VERBS))
                if UPPER.match(name) and fn["params"]:
                    add("N03", name, f, line, "冻结值命名不得带参数（返回值随入参变化）")
                if fn["vis"] in ("external", "public"):
                    single_bool = fn["returns"].strip() == "bool"
                    if single_bool and fn["params"] and not PREDICATE.match(name) and name not in STD_EXEMPT:
                        add("N04", name, f, line, "带参数的单个 bool 返回必须是 is/has/can/should 谓词")
                    for key in by_keys(name):
                        if not re.search(r"(Id|Ids|Address|Addresses)$", key):
                            continue
                        keys = {p[1][:1].upper() + p[1][1:] for p in fn["params"]}
                        if key == "Ids" and any(p[1].endswith("Ids") for p in fn["params"]):
                            continue
                        if key not in keys:
                            add("N05", name, f, line, f"By{key} 没有同名入参")
                    if "Count" in name and not name.endswith("Count"):
                        add("N06", name, f, line, "Count 必须是最后一个词")
                    if name.endswith("Of") and name not in STD_EXEMPT:
                        add("N20", name, f, line, "自有读取函数用 By<Key>，不用 Of 后缀")
                    if name.startswith("total") and any(p[1] in MEMBER_KEYS for p in fn["params"]):
                        add("N21", name, f, line, "total* 只用于社区级聚合，成员级聚合用 By<MemberId>")
                    if name.startswith("g") and name[1:2].isupper():
                        add("N22", name, f, line, "禁用单字母语义前缀 g，按语义命名")
                    for p in fn["params"]:
                        if c["kind"] == "interface" and p[1].endswith("_"):
                            add("N12", name, f, line, f"接口参数 {p[1]} 不应带 _ 后缀")
                if name.endswith("Data"):
                    add("N13", name, f, line, "Data 后缀不表达任何语义")

                for tok in tokens_of(name):
                    if tok.lower() in BANNED_TOKENS:
                        add("N07", name, f, line, f"禁用词 {tok}")
                if name.lstrip("_") in BARE_NAMES or len(name.lstrip("_")) < 3:
                    add("N11", name, f, line, "名字过短或为裸 state/data/info")
            for sv in c["state"]:
                name, line = sv["name"], sv["line"]
                if sv["kind"] == "constant":
                    if not UPPER.match(name) or name.startswith("_"):
                        add("N09", name, f, line, "constant 必须 UPPER_SNAKE 且不带 _ 前缀")
                elif sv["kind"] == "immutable":
                    if not UPPER.match(name) or name.startswith("_"):
                        add("N10", name, f, line, "immutable 必须 UPPER_SNAKE 且不带 _ 前缀")
                else:
                    if sv["vis"] == "public" and name.startswith("_"):
                        add("N08", name, f, line, "public 状态变量不得带 _ 前缀")
                    if sv["vis"] != "public" and not name.startswith("_"):
                        add("N08", name, f, line, "非 public 状态变量必须带 _ 前缀")
                if name.endswith("Data"):
                    add("N13", name, f, line, "Data 后缀不表达任何语义")

                if name.lstrip("_") in BARE_NAMES or len(name.lstrip("_")) < 3:
                    add("N11", name, f, line, "名字过短或为裸 state/data/info")
                for tok in tokens_of(name):
                    if tok.lower() in BANNED_TOKENS:
                        add("N07", name, f, line, f"禁用词 {tok}")
            seen_names = {}
            for fn in c["functions"]:
                if fn["vis"] in ("external", "public"):
                    seen_names.setdefault(fn["name"], []).append(fn["line"])
            for nm, lines in seen_names.items():
                if len(lines) > 1:
                    add("N23", nm, f, lines[1], "禁止外部函数重载")
            for md in c["modifiers"]:
                if not re.match(r"^(only|non)[A-Z]\w*$", md["name"]):
                    add("N18", md["name"], f, md["line"], "modifier 用 only<Role> / non<State> 形式")
        for st in f.structs:
            for ty, fname in st["fields"]:
                if not CAMEL.match(fname):
                    add("N17", f"{st['name']}.{fname}", f, st["line"], "结构体字段必须 lowerCamelCase")
                if ty == "address" and fname in ENTITY_NAMES:
                    add("N14", f"{st['name']}.{fname}", f, st["line"], "address 字段名必须带 Address 后缀")
                for tok in tokens_of(fname):
                    if tok.lower() in BANNED_TOKENS:
                        add("N07", f"{st['name']}.{fname}", f, st["line"], f"禁用词 {tok}")
        for en in f.enums:
            for v in en["values"]:
                if not PASCAL.match(v):
                    add("N16", f"{en['name']}.{v}", f, en["line"], "枚举成员必须 PascalCase")
    # dedupe by (repo, rule, file, symbol): interface + implementation declare the same name
    seen, uniq = set(), []
    for v in out:
        k = (v["repo"], v["rule"], v["file"], v["symbol"])
        if k in seen:
            continue
        seen.add(k)
        uniq.append(v)
    uniq.sort(key=lambda v: (v["rule"], v["repo"], v["file"], v["line"]))
    return uniq


def key(v):
    return f"{v['rule']}|{v['repo']}|{v['file'].split('/', 1)[-1]}|{v['symbol']}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--update-baseline", action="store_true")
    args = ap.parse_args()

    violations = check(collect())
    keys = sorted({key(v) for v in violations})

    if args.update_baseline:
        BASELINE.parent.mkdir(parents=True, exist_ok=True)
        BASELINE.write_text("\n".join(keys) + "\n", encoding="utf-8")
        print(f"baseline written: {len(keys)} entries")
        return 0

    by_rule = {}
    for v in violations:
        by_rule.setdefault(v["rule"], []).append(v)

    for rule in sorted(by_rule):
        items = by_rule[rule]
        print(f"\n[{rule}] {len(items)}")
        for v in items:
            print(f"  {v['repo']}/{v['file'].split('/src/')[-1]}:{v['line']}  {v['symbol']}  — {v['msg']}")

    print("\n--- summary ---")
    for rule in sorted(by_rule):
        print(f"{rule}: {len(by_rule[rule])}")
    print(f"total: {len(violations)}")

    if args.check:
        base = set()
        if BASELINE.exists():
            base = {ln.strip() for ln in BASELINE.read_text(encoding="utf-8").splitlines() if ln.strip()}
        new = [k for k in keys if k not in base]
        if new:
            print("\nNEW violations not in baseline:")
            for k in new:
                print("  " + k)
            return 1
        print(f"ok: {len(keys)} known violations, 0 new")
    return 0


if __name__ == "__main__":
    sys.exit(main())
