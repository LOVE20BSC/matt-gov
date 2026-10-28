#!/usr/bin/env python3
"""Check that every declared error is referenced by at least one test.

Rule from error-standards 9 (failure contract): each reachable error needs a
selector + payload assertion. The assertion itself is a review item; what can be
checked mechanically is that the error is mentioned in the test tree at all --
an error no test ever touches is either dead (forbidden) or silently unproven.

Scope: any textual reference in `<repo>/test/**/*.sol` counts (`<Error>.selector`,
`abi.encodeWithSelector(...)`, an interface-qualified name). Mocks and other
`src` files do not count as tests.

Usage:
    ./script/check_error_tests.py
    ./script/check_error_tests.py ../core ../action ../group-chat

Exit code 0 when clean, 1 when an error has no test reference (or a repo
contributes no errors / no tests, which means the paths are wrong).
"""

import pathlib
import re
import sys

DEFAULT_REPOS = ("core", "action", "group-chat")

DECL = re.compile(r"\berror\s+(\w+)\s*\(")


def declarations(paths):
    found = {}
    for path in paths:
        if "lib" in path.parts:
            continue
        for match in DECL.finditer(path.read_text()):
            found.setdefault(match.group(1), path)
    return found


def main(argv):
    workspace = pathlib.Path(__file__).resolve().parent.parent.parent
    names = argv or DEFAULT_REPOS
    untested = []
    for name in names:
        repo = pathlib.Path(name)
        if not repo.is_absolute():
            repo = workspace / name
        src = sorted(repo.glob("src/**/*.sol"))
        tests = sorted(repo.glob("test/**/*.sol"))
        if not src or not tests:
            print(f"{repo.name}: no sources or no tests under {repo}")
            return 1

        declared = declarations(src)
        if not declared:
            print(f"{repo.name}: no error declarations under {repo / 'src'}")
            return 1

        text = "\n".join(path.read_text() for path in tests)
        missing = sorted(one for one in declared if not re.search(r"\b" + one + r"\b", text))
        for one in missing:
            untested.append((declared[one], one))
        print(f"{repo.name}: errors {len(declared)}, untested {len(missing)}")

    for path, one in untested:
        print(f"{path}: {one}")
    print(f"untested errors: {len(untested)}")
    return 1 if untested else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
