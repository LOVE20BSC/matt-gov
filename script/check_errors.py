#!/usr/bin/env python3
"""Generate the local-first error catalog and check structural rules.

Usage:
  python3 matt-gov/script/check_errors.py          # generate registry/errors.{json,md}
  python3 matt-gov/script/check_errors.py --check  # fail on violations or catalog drift

The catalog is a generated artifact. It is not a compile-time dependency; adding a
new contract only adds new interface files, never edits an existing error file.
Foundry's `cast` must be on PATH: selectors are computed from the canonical signatures.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPOS = ("core", "action", "group-chat", "libs")
REGISTRY = ROOT / "matt-gov" / "registry"
JSON_PATH = REGISTRY / "errors.json"
MD_PATH = REGISTRY / "errors.md"

ERROR_DECL = re.compile(r"\berror\s+([A-Za-z_]\w*)\s*\(([^)]*)\)\s*;", re.S)
REVERT = re.compile(r"\brevert\s+(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)\s*\(")
TYPE_DECL = re.compile(r"\b(?:interface|library|contract)\s+(\w+)(?:\s+is\s+([^{]+?))?\s*\{", re.S)
BARE_REVERT = re.compile(r"\brevert\s*\(\s*(?:\"|\))")
REQUIRE = re.compile(r"\brequire\s*\(")
IMPORT = re.compile(r'import\s+(?:\{([^}]*)\}|\*\s+as\s+\w+)\s+from\s+"([^"]+)"')


def import_repo(target: str) -> str | None:
    path = target[1:] if target.startswith("@") else target
    for name in REPOS:
        if path.startswith(f"{name}/"):
            return name
    return None


ENUM_NAMES: set[str] = set()

ELEMENTARY = {
    "address", "bool", "string", "bytes",
    "bytes1", "bytes2", "bytes3", "bytes4", "bytes5", "bytes6",
    "bytes7", "bytes8", "bytes9", "bytes10", "bytes11", "bytes12",
    "bytes13", "bytes14", "bytes15", "bytes16", "bytes17", "bytes18",
    "bytes19", "bytes20", "bytes21", "bytes22", "bytes23", "bytes24",
    "bytes25", "bytes26", "bytes27", "bytes28", "bytes29", "bytes30",
    "bytes31", "bytes32",
}


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def line_of(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def canonical_type(param: str) -> str:
    p = re.sub(r"\b(calldata|memory|storage|payable)\b", " ", param).strip()
    tokens = p.split()
    if not tokens:
        return "?"
    t = tokens[0]
    if t.endswith("[]"):
        return canonical_type(t[:-2]) + "[]"
    if t in ELEMENTARY:
        return t
    if t == "uint":
        return "uint256"
    if t == "int":
        return "int256"
    if t == "byte":
        return "bytes1"
    if re.fullmatch(r"u?int\d*", t) or re.fullmatch(r"(bytes|uint|int)\d+", t):
        return t
    if t in ENUM_NAMES:
        return "uint8"
    # Unknown named types (structs, contract types, fixed arrays) are not part of the
    # allowed error payload set. "?" makes collect report them instead of guessing.
    return "?"


def canonical_signature(name: str, params: str) -> str:
    parts = [p.strip() for p in params.split(",") if p.strip()]
    return f"{name}({','.join(canonical_type(p) for p in parts)})"


def selector_of(signature: str, cache: dict[str, str]) -> str:
    if signature in cache:
        return cache[signature]
    cast = shutil.which("cast")
    if cast is None:
        raise SystemExit("cast not found on PATH; install Foundry before generating the error catalog")
    try:
        out = subprocess.check_output(
            [cast, "sig", signature], text=True, stderr=subprocess.STDOUT
        ).strip()
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"cast sig failed for {signature}: {exc.output.strip()}") from exc
    if not re.fullmatch(r"0x[0-9a-fA-F]{8}", out):
        raise SystemExit(f"cast sig returned an unexpected selector for {signature}: {out}")
    cache[signature] = out
    return out


def error_params_one_per_line(clean: str, match: re.Match) -> bool:
    """True when a multi-parameter `error` declaration puts each parameter on its own line."""
    open_paren = clean.index("(", match.start())
    close_paren = match.end() - 1
    while clean[close_paren] != ")":
        close_paren -= 1
    starts, depth, seg = [], 0, open_paren + 1
    for i in range(seg, close_paren + 1):
        if i < close_paren:
            ch = clean[i]
            if ch in "([{":
                depth += 1
                continue
            if ch in ")]}":
                depth -= 1
                continue
            if ch != "," or depth:
                continue
        entry = clean[seg:i]
        if entry.strip():
            starts.append(seg + len(entry) - len(entry.lstrip()))
        seg = i + 1
    if len(starts) < 2:
        return True
    lines = [line_of(clean, start) for start in starts]
    open_line = line_of(clean, open_paren)
    close_line = line_of(clean, close_paren)
    if not (open_line < lines[0] and lines[-1] < close_line):
        return False
    return all(lines[i] > lines[i - 1] for i in range(1, len(lines)))


def collect() -> tuple[list[dict], list[str], dict]:
    declarations: list[dict] = []
    violations: list[str] = []
    reverts_by_repo: dict[str, list[dict]] = defaultdict(list)
    bases_by_repo: dict[str, dict[str, set[str]]] = defaultdict(dict)

    for repo in REPOS:
        src = ROOT / repo / "src"
        if not src.is_dir():
            continue
        for path in src.rglob("*.sol"):
            rel = path.relative_to(ROOT)
            if "/lib/" in f"/{rel}":
                continue
            clean = strip_comments(path.read_text())
            for enum_match in re.finditer(r"\benum\s+(\w+)", clean):
                ENUM_NAMES.add(enum_match.group(1))
            for type_match in TYPE_DECL.finditer(clean):
                bases = {
                    base.strip().split(".")[-1]
                    for base in (type_match.group(2) or "").split(",")
                    if base.strip()
                }
                bases_by_repo[repo][type_match.group(1)] = bases

    for repo in REPOS:
        src = ROOT / repo / "src"
        if not src.is_dir():
            continue
        for path in sorted(src.rglob("*.sol")):
            rel = path.relative_to(ROOT)
            if "/lib/" in f"/{rel}":
                continue
            raw = path.read_text()
            clean = strip_comments(raw)
            type_decls = [
                (m.start(), m.group(1))
                for m in re.finditer(r"\b(?:interface|library|contract)\s+(\w+)", clean)
            ]

            def enclosing_type(offset: int) -> str:
                name = path.stem
                for start, candidate in type_decls:
                    if start <= offset:
                        name = candidate
                    else:
                        break
                return name

            for m in ERROR_DECL.finditer(clean):
                name, params = m.group(1), m.group(2)
                loc = str(rel)
                line = line_of(clean, m.start())
                if "/interfaces/" not in f"/{loc}":
                    violations.append(f"{loc}:{line}: error {name} declared outside src/interfaces")
                if not error_params_one_per_line(clean, m):
                    violations.append(
                        f"{loc}:{line}: error {name} must put each parameter on its own line"
                    )
                signature = canonical_signature(name, params)
                if "?" in signature:
                    violations.append(
                        f"{loc}:{line}: error {name} uses a payload type outside address/enum/bytes32/integer"
                    )
                declarations.append(
                    {
                        "repo": repo,
                        "file": loc,
                        "interface": enclosing_type(m.start()),
                        "name": name,
                        "signature": signature,
                        "params": params.strip(),
                        "line": line,
                    }
                )

            for m in REVERT.finditer(clean):
                reverts_by_repo[repo].append(
                    {
                        "qualifier": m.group(1) or "",
                        "name": m.group(2),
                        "enclosing": enclosing_type(m.start()),
                        "file": str(rel),
                        "line": line_of(clean, m.start()),
                    }
                )

            for m in REQUIRED_BARE.finditer(clean):
                violations.append(
                    f"{rel}:{line_of(clean, m.start())}: bare require(...) in src"
                )
            for m in BARE_REVERT.finditer(clean):
                violations.append(
                    f"{rel}:{line_of(clean, m.start())}: bare revert() or revert(\"...\") in src"
                )
            for m in IMPORT.finditer(raw):
                symbols = [s.strip().split(" as ")[0].strip() for s in (m.group(1) or "").split(",")]
                target = m.group(2)
                if "IProtocolErrors" in target or "IProtocolErrors" in symbols:
                    violations.append(f"{rel}: imports central IProtocolErrors")
                source_repo = import_repo(target)
                if source_repo and source_repo != repo:
                    if target.endswith("Errors.sol") or any(s.endswith("Errors") for s in symbols):
                        violations.append(f"{rel}: cross-repo error import {target}")

    def ancestors(repo: str, type_name: str) -> set[str]:
        seen: set[str] = set()
        stack = [type_name]
        while stack:
            current = stack.pop()
            if current in seen:
                continue
            seen.add(current)
            stack.extend(bases_by_repo[repo].get(current, ()))
        return seen

    same_name_by_repo: dict[str, dict[str, list[dict]]] = defaultdict(lambda: defaultdict(list))
    for d in declarations:
        same_name_by_repo[d["repo"]][d["name"]].append(d)

    # Attach revert sites to declarations. A qualified revert belongs to the named
    # interface. An unqualified revert belongs to a same-name declaration in the
    # enclosing type's inheritance closure; if no declaration is reachable that way
    # (e.g. a library using a qualified-only union), fall back to every same-name
    # declaration in the repo so a valid site is never reported as a dead error.
    for d in declarations:
        sites = []
        for s in reverts_by_repo[d["repo"]]:
            if s["name"] != d["name"]:
                continue
            if s["qualifier"]:
                if s["qualifier"] != d["interface"]:
                    continue
            else:
                reachable = [
                    candidate
                    for candidate in same_name_by_repo[d["repo"]][d["name"]]
                    if candidate["interface"] in ancestors(d["repo"], s["enclosing"])
                ]
                if reachable and all(candidate is not d for candidate in reachable):
                    continue
            sites.append(f'{s["file"]}:{s["line"]}')
        d["revert_sites"] = sorted(set(sites))
        if not sites:
            violations.append(
                f'{d["file"]}:{d["line"]}: error {d["name"]} has no matching revert site in {d["repo"]}'
            )

    # One name must not carry two signatures across the protocol.
    by_name: dict[str, list[dict]] = defaultdict(list)
    for d in declarations:
        by_name[d["name"]].append(d)
    for name, items in sorted(by_name.items()):
        sigs = sorted({i["signature"] for i in items})
        if len(sigs) > 1:
            details = ", ".join(f'{i["repo"]}:{i["file"]}' for i in items)
            violations.append(f"error name {name} has multiple signatures {sigs} ({details})")

    # Dynamic types in error payloads are not allowed.
    for d in declarations:
        inner = d["signature"][d["signature"].find("(") + 1 : -1]
        types = [t for t in inner.split(",") if t]
        if any(t in ("string", "bytes") or t.endswith("[]") for t in types):
            violations.append(f'{d["file"]}:{d["line"]}: error {d["name"]} uses a dynamic payload')

    # Detect the old central model explicitly.
    for repo in REPOS:
        src = ROOT / repo / "src"
        if not src.is_dir():
            continue
        for path in src.rglob("*.sol"):
            rel = path.relative_to(ROOT)
            if "/lib/" in f"/{rel}":
                continue
            text = path.read_text()
            for token in ("IProtocolErrors", "ZeroField", "ValueOutOfRange(Field", "FieldMismatch", "ValueConflict(Field"):
                if token in text:
                    violations.append(f"{rel}: uses obsolete central error token {token}")

    # Naming warnings (not failures): new names should not use these prefixes.
    for d in declarations:
        if re.match(r"(Only|Must|Cannot)", d["name"]):
            violations.append(f'{d["file"]}:{d["line"]}: error {d["name"]} uses a banned rule-style prefix')

    return declarations, violations, reverts_by_repo


REQUIRED_BARE = REQUIRE  # require(...) is bare in this protocol; no reason strings are allowed


def build_catalog(declarations: list[dict], reverts_by_repo: dict) -> dict:
    cache: dict[str, str] = {}
    groups: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for d in declarations:
        groups[(d["repo"], d["signature"])].append(d)

    entries = []
    for (repo, signature), items in sorted(groups.items()):
        entries.append(
            {
                "repo": repo,
                "signature": signature,
                "selector": selector_of(signature, cache),
                "interfaces": sorted({d["interface"] for d in items}),
                "files": sorted({d["file"] for d in items}),
                "declarations": len(items),
                "revert_sites": sorted({s for d in items for s in d["revert_sites"]}),
            }
        )

    by_sig: dict[str, list[dict]] = defaultdict(list)
    for e in entries:
        by_sig[e["signature"]].append(e)
    shared = [
        {
            "signature": sig,
            "declarations": [
                f'{e["repo"]}:{",".join(e["interfaces"])}' for e in items
            ],
        }
        for sig, items in sorted(by_sig.items())
        if len({e["repo"] for e in items}) > 1
    ]
    return {
        "generated_by": "matt-gov/script/check_errors.py",
        "policy": "local-first: each module declares its own errors; generated catalog only",
        "summary": {
            "declarations": len(declarations),
            "signatures": len(entries),
            "unique_signatures": len(by_sig),
            "repos": {repo: sum(1 for d in declarations if d["repo"] == repo) for repo in REPOS},
        },
        "errors": entries,
        "shared_signatures": shared,
    }


def render_md(catalog: dict) -> str:
    lines = [
        "# Error catalog (generated)",
        "",
        "Generated by `matt-gov/script/check_errors.py`; do not edit by hand.",
        "Local-first: each module owns its errors; the catalog is a view, not a source dependency.",
        "Rows are grouped by repo + signature; interfaces list every local declaration site.",
        "",
        "| repo | signature | selector | interfaces | declarations | revert sites |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for e in catalog["errors"]:
        lines.append(
            f'| {e["repo"]} | `{e["signature"]}` | `{e["selector"]}` | '
            + ", ".join(f"`{i}`" for i in e["interfaces"])
            + f' | {e["declarations"]} | '
            + ", ".join(f"`{s}`" for s in e["revert_sites"])
            + " |"
        )
    lines.append("")
    lines.append(
        f'Total: {catalog["summary"]["declarations"]} declarations, '
        f'{catalog["summary"]["unique_signatures"]} unique signatures.'
    )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail on violations or catalog drift")
    args = parser.parse_args()

    declarations, violations, reverts_by_repo = collect()
    catalog = build_catalog(declarations, reverts_by_repo)
    if any(entry["selector"] == "?" for entry in catalog["errors"]):
        violations.append("catalog contains unresolved selectors")
    json_text = json.dumps(catalog, indent=2, sort_keys=True) + "\n"
    md_text = render_md(catalog)

    REGISTRY.mkdir(parents=True, exist_ok=True)
    if args.check:
        if not JSON_PATH.exists():
            violations.append(f"{JSON_PATH.relative_to(ROOT)} is missing; run without --check to generate")
        elif JSON_PATH.read_text() != json_text:
            violations.append(f"{JSON_PATH.relative_to(ROOT)} is out of date; regenerate it")
        if not MD_PATH.exists():
            violations.append(f"{MD_PATH.relative_to(ROOT)} is missing; run without --check to generate")
        elif MD_PATH.read_text() != md_text:
            violations.append(f"{MD_PATH.relative_to(ROOT)} is out of date; regenerate it")
    else:
        JSON_PATH.write_text(json_text)
        MD_PATH.write_text(md_text)
        print(f"wrote {JSON_PATH.relative_to(ROOT)} and {MD_PATH.relative_to(ROOT)}")

    print(f'declarations: {catalog["summary"]["declarations"]}, '
          f'signatures: {catalog["summary"]["signatures"]}, '
          f'unique signatures: {catalog["summary"]["unique_signatures"]}, '
          f'violations: {len(violations)}')
    for v in violations:
        print(f"  {v}")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
