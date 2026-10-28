#!/usr/bin/env python3
"""Check that error payloads quoted in docs match the declarations in `src`.

Rules from error-standards 3 (naming) and 4 (payload):

1. A doc may quote an error with its full field list, e.g.
   `DescriptionTooLong(uint256 length, uint256 maxLength)`. The types and the
   parameter names must match the declaration in `src` byte for byte.
2. Renaming a parameter is an ABI change (`inputs[].name`), so it must land on
   both sides in the same commit. This script is the gate for the doc side.

Scope: only references that spell out `<type> <name>` pairs are checked. Bare
value lists (`GroupCapacityExceeded(groupId, actual, limit)`) and names that no
`src` file declares (OZ standard errors) are skipped. `docs/specs/CHANGES-*.md`
and `docs/adr/**` are historical records and are skipped.

Usage:
    ./script/check_doc_payloads.py                 # docs/ + sibling src trees
    ./script/check_doc_payloads.py docs ../core/src ../action/src

Exit code 0 when clean, 1 when a payload or a parameter name differs.
"""

import pathlib
import re
import sys

DEFAULT_SRC = ("core/src", "action/src", "group-chat/src")
SKIP_DOC_GLOBS = ("specs/CHANGES-*.md",)
SKIP_DOC_DIRS = {"adr"}

DECL = re.compile(r"\berror\s+(\w+)\s*\(([^)]*)\)")
REF = re.compile(r"\b([A-Z]\w+)\(([^()\n]*)\)")
PAIR = re.compile(r"^([A-Za-z_][\w\[\]\.]*)\s+([a-z_]\w*)$")


def params(body):
    """Parse `uint256 length, uint256 maxLength` into (type, name) pairs."""
    out = []
    for item in body.split(","):
        item = item.strip()
        if not item:
            continue
        match = PAIR.match(item)
        if not match:
            return None
        out.append((match.group(1), match.group(2)))
    return tuple(out)


def declarations(roots):
    found = {}
    for root in roots:
        for path in sorted(pathlib.Path(root).rglob("*.sol")):
            if "lib" in path.parts:
                continue
            for match in DECL.finditer(path.read_text()):
                shape = params(match.group(2))
                if shape is None:
                    continue
                found.setdefault(match.group(1), set()).add(shape)
    return found


def skipped(path, docs_root):
    if SKIP_DOC_DIRS & set(path.relative_to(docs_root).parts[:-1]):
        return True
    return any(path.match(glob) for glob in SKIP_DOC_GLOBS)


def check_doc(path, docs_root, declared):
    violations = []
    checked = 0
    if skipped(path, docs_root):
        return violations, checked
    for number, line in enumerate(path.read_text().splitlines(), 1):
        for match in REF.finditer(line):
            name = match.group(1)
            if name not in declared:
                continue
            shape = params(match.group(2))
            if shape is None:
                continue
            checked += 1
            if shape not in declared[name]:
                expected = " | ".join(
                    f"{name}({', '.join(f'{t} {n}' for t, n in one)})"
                    for one in sorted(declared[name])
                )
                quoted = f"{name}({', '.join(f'{t} {n}' for t, n in shape)})"
                violations.append((path, number, quoted, expected))
    return violations, checked


def main(argv):
    workspace = pathlib.Path(__file__).resolve().parent.parent.parent
    if argv and not argv[0].startswith("-"):
        docs_root = pathlib.Path(argv[0])
        roots = argv[1:] or [str(workspace / one) for one in DEFAULT_SRC]
    else:
        docs_root = workspace / "matt-gov" / "docs"
        roots = [str(workspace / one) for one in DEFAULT_SRC]

    declared = declarations(roots)
    if not declared:
        print(f"no error declarations found under {', '.join(roots)}")
        return 1

    violations = []
    checked = 0
    for path in sorted(docs_root.rglob("*.md")):
        found, seen = check_doc(path, docs_root, declared)
        checked += seen
        violations.extend(found)

    for path, number, quoted, expected in violations:
        print(f"{path}:{number}: {quoted}")
        print(f"    declaration: {expected}")
    print(f"errors declared: {len(declared)}, refs checked: {checked}, mismatches: {len(violations)}")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
