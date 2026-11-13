#!/usr/bin/env python3
"""Check that caller checks live in `only*` modifiers.

Rules from dev-standards 5.5:

1. A caller check is a condition on `msg.sender`. It must sit in a
   `modifier only*`, or in an `_is*` predicate used by one. Receiver callbacks
   (`onERC721Received`) are exempt.
2. Every `modifier only*` must test the caller (directly on `msg.sender` or
   through an `_is*` predicate), revert, and end with `_;`.
3. Library files are in scope. A `modifier only*` declared inside a `library`
   must be applied to at least one entry in the same file: when the
   implementation body moves behind `delegatecall`, the library modifier is the
   whole auth surface, and an unattached one means an entry silently lost it.
4. An `_is*` predicate is exempt (it is the sanctioned home for a delegated
   check). A predicate whose name does NOT start with `_is` but whose `msg.sender`
   comparison is a *business* rule rather than an auth gate must not silently
   pass either: name it `_is*` when the `msg.sender` part is genuinely a
   predicate, or record it below in `BUSINESS_CALLER_CHECKS` with the reason.
   The allowlist is deliberately explicit: relaxing the rule for a whole file
   would let a future real auth check slip through unnoticed.

The checker validates caller-check placement and modifier shape. It does not
prove every write entry has an auth source, nor that a modifier is free of
state writes; those remain spec and review items. Entry -> auth-subject
mapping stays a spec requirement (dev-standards 5.5).

Usage:
    ./matt-gov/script/check_caller_auth.sh

Exit code 0 when clean, 1 when violations are found.
"""

import pathlib
import re
import sys

SKIP_DIRS = {"lib", "interfaces"}
EXEMPT = {"onERC721Received"}

# Functions whose `msg.sender` comparison is a business rule, not an auth gate.
# Key is "<path as found by the checker>:<function name>"; the value must say
# which business rule it is. Adding an entry here is a deliberate act: it removes
# the file's caller-check coverage for that one function only.
BUSINESS_CALLER_CHECKS = {
    "core/src/Stake.sol:_checkPromisedWaitingPhasesNotRewritten": (
        "phase 6.3 no-slippage change: promisedWaitingPhases may only be raised by the NFT holder. "
        "This is not 'who may call' (anybody may call stakeLiquidity/stakeBoost); it is a condition on "
        "the INPUT value whose verdict depends on the caller. The external callable never gates on it, "
        "so it cannot move into a modifier only*."
    ),
}

DECL = re.compile(r"\b(modifier|function)\s+(\w+)")
LIBRARY_DECL = re.compile(r"\blibrary\s+\w+")
CALLER_CMP = re.compile(r"(==|!=)\s*msg\.sender|msg\.sender\s*(==|!=)")
CALLER_LOOKUP = re.compile(r"\b(?:if|require|assert)\s*\([^;{}]*\[\s*msg\.sender\s*\]")
CALLER_TEST = re.compile(r"msg\.sender|_is\w+\s*\(")


def clean(text):
    """Blank comments and string literals, preserving offsets and newlines."""
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        char = text[i]
        if char == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                out[i] = " "
                i += 1
        elif char == "/" and i + 1 < n and text[i + 1] == "*":
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
        elif char in "\"'":
            quote = char
            out[i] = " "
            i += 1
            while i < n:
                if text[i] == "\\":
                    out[i] = " "
                    i += 1
                    if i < n and text[i] != "\n":
                        out[i] = " "
                        i += 1
                elif text[i] == quote:
                    out[i] = " "
                    i += 1
                    break
                else:
                    if text[i] != "\n":
                        out[i] = " "
                    i += 1
        else:
            i += 1
    return "".join(out)


def depths(text):
    result = [0] * (len(text) + 1)
    depth = 0
    for i, char in enumerate(text):
        result[i] = depth
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
    result[len(text)] = depth
    return result


def declarations(text):
    """Yield (kind, name, line, body) for declarations at file/contract level."""
    depth_at = depths(text)
    n = len(text)
    for match in DECL.finditer(text):
        if depth_at[match.start()] > 1:
            continue
        prefix = text[: match.start()].rstrip()
        if prefix and prefix[-1] not in "{};":
            continue
        cursor = match.end()
        while cursor < n and text[cursor] not in "{;":
            cursor += 1
        if cursor >= n or text[cursor] == ";":
            continue
        balance, end = 0, cursor
        while end < n:
            if text[end] == "{":
                balance += 1
            elif text[end] == "}":
                balance -= 1
                if balance == 0:
                    break
            end += 1
        if end >= n:
            break
        line = text.count("\n", 0, match.start()) + 1
        yield match.group(1), match.group(2), line, text[cursor + 1 : end]


def body_before_continue(body):
    return body.rsplit("_;", 1)[0] if "_;" in body else body


def check_modifier(name, body):
    head = body_before_continue(body).strip()
    if not head:
        return "body is empty"
    if not CALLER_TEST.search(head):
        return "does not test msg.sender or an _is* predicate"
    if not re.search(r"\brevert\b", head):
        return "has no revert"
    if not body.strip().endswith("_;"):
        return "does not end with _;"
    return None


def allowlisted(path, name):
    """True when this function is a registered business caller check (see BUSINESS_CALLER_CHECKS)."""
    return f"{path}:{name}" in BUSINESS_CALLER_CHECKS


def check_file(path):
    text = clean(path.read_text())
    violations = []
    library_modifiers = []
    for kind, name, line, body in declarations(text):
        if name in EXEMPT:
            continue
        if kind == "modifier":
            if name.startswith("only"):
                library_modifiers.append((name, line))
                reason = check_modifier(name, body)
                if reason:
                    violations.append((path, line, f"modifier {name}", reason))
            elif CALLER_CMP.search(body) or CALLER_LOOKUP.search(body):
                violations.append(
                    (path, line, f"modifier {name}", "caller check is not in a modifier only*")
                )
            continue
        if name.startswith("_is"):
            continue
        if (CALLER_CMP.search(body) or CALLER_LOOKUP.search(body)) and not allowlisted(path, name):
            violations.append(
                (path, line, f"function {name}", "caller check must move into a modifier only*")
            )
    if LIBRARY_DECL.search(text):
        for name, line in library_modifiers:
            # One occurrence is the definition; the modifier must also be attached to an entry.
            if len(re.findall(rf"\b{name}\b\s*\(", text)) < 2:
                violations.append(
                    (path, line, f"modifier {name}", "library modifier is not applied to any entry")
                )
    return violations


def main(roots):
    violations = []
    for root in roots:
        for path in sorted(pathlib.Path(root).rglob("*.sol")):
            if SKIP_DIRS & set(path.parts):
                continue
            violations.extend(check_file(path))
    for path, line, where, reason in violations:
        print(f"{path}:{line} in {where}: {reason}")
    print(f"violations: {len(violations)}")
    return 1 if violations else 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: check_caller_auth.py <src-root> [<src-root> ...]", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
