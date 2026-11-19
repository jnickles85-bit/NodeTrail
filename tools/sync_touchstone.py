#!/usr/bin/env python3
"""Vendor Touchstone from StatForge into MightiePack/Modules/Touchstone.

THE SHAPE. Eight of the sixteen vendored files are the pin's own blobs, byte for
byte. The other eight are the pin's blob plus one patch each, and every patch
starts with a header that names its reason. There is no third mechanism: no
anchored text editors, no asset retargeting, no guard insertion. If a file is not
pristine it is a patch, and every patch says why it exists.

WHY. A hash check was never the goal — a loud failure was. This tool fails
IMMEDIATELY and BY NAME when upstream moves:

  * the COPY check hashes each pristine file against the pin's blob. A file that
    drifted fails as "COPY: <file> is not the pin's blob".
  * the PATCH check re-derives each patched file: it reverses the patch out of
    the shipped file and hashes the result against the pin's blob. A patch that
    no longer applies to the pin fails as "PATCH: <patch> no longer applies to
    the pin for <file>" — naming both, never a vague diff.

Neither check needs a StatForge checkout, so CI runs both on every pull request
(see .github/workflows/ci.yml). `--verify-pin --src <checkout>` adds the one check
that DOES need upstream: that the checkout is the named commit and its blobs are
the ones the manifest names. Run it when a pin moves; it is the alarm for "the
manifest and the pin have parted company".

WHY THE PATCH CHECK RUNS BACKWARDS. The pin is a private repository, so CI cannot
fetch it and the pack does not commit a second copy of it. Reversal is equivalent
and needs neither: the shipped file minus the patch is a blob, and that blob's
sha256 is compared to the pin's. If the hashes agree, applying the same patch to
a blob with that hash reproduces the shipped file — the forward claim, proven
without the forward input. The forward direction still runs on a dev machine,
because `generate()` applies every patch to a real checkout.

THE PATCH LAYER'S SIZE IS A DECISION, NOT AN ACCIDENT. Eight patches remain
because the seams do not cover what they carry: the weighted engine (a scoring
model upstream retired on purpose — the one permanent divergence, recorded in
docs/touchstone-divergences.md), the pack's product surface (gear-for-spec
registry, toast block and its commands, tooltip line), and three presentation
layers upstream has no seam or model for (the measured row stack, the ledger
drawing, the Settings flow).

The source is StatForge at SOURCE_REF, cloned at run time, and the resolved commit
is printed so every sync names the upstream it was generated from::

    https://github.com/jnickles85-bit/StatForge.git@eebfba4

``--src`` still points the run at a local checkout (a pristine deploy folder or a
worktree) instead of cloning.

Usage:
    python3 tools/sync_touchstone.py                     # clone StatForge at SOURCE_REF
    python3 tools/sync_touchstone.py --ref <sha>         # …or move the pin deliberately
    python3 tools/sync_touchstone.py --src /path/to/checkout
    python3 tools/sync_touchstone.py --verify-only       # generate in memory, write nothing
    python3 tools/sync_touchstone.py --verify-shipped    # the two checks, no upstream needed
    python3 tools/sync_touchstone.py --verify-pin --src /path/to/checkout
    python3 tools/sync_touchstone.py --write-pin --src /path/to/checkout
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEST_ROOT = REPO_ROOT / "MightiePack" / "Modules" / "Touchstone"
TOC_PATH = REPO_ROOT / "MightiePack" / "MightiePack.toc"
PATCH_DIR = REPO_ROOT / "tools" / "touchstone-patches"
PIN_MANIFEST = PATCH_DIR / "pin.txt"

# The fold is generated from StatForge, not from a hand-kept local folder: the
# default source is the repository's own main, cloned at run time, and the
# resolved commit is printed with the result so a vendored tree can always be
# traced back to the upstream it came from.
SOURCE_URL = "https://github.com/jnickles85-bit/StatForge.git"

# THE PIN. A NAMED SHA, never a branch: a ref that moves under the cut is what
# made the changed-verdict sweep lie (card t_0153f144), and a pin that can move
# is a pin that cannot be checked.
#
# Provenance of ff64bc5: "Merge pull request #123 from
# jnickles85-bit/wt/t_ce1c4a4f" (2026-11-18, StatForge main), THE WIRE: the
# arbitration flag is TRUE and gates the seam at its call site, the renderer
# refuses a table with no state, the spec context survives every path, and
# compareDPS carries the spec instead of dropping it. It supersedes eebfba4
# (PR #121), whose four presentation seams — hosted chrome, theme, asset root,
# toast hook — plus t_4e61b67f's host opt-out are all still in it, so every
# vendored file still begins with upstream's own `if TouchstoneSkip then return
# end` and the pristine files are still the pin's blobs byte for byte.
#
# Card t_58762500 moved the pin here for one reason: the flag arrives with
# Arbitration.lua (a COPY-lane file) while the call lives in Verdict.lua, which
# this pack replaces wholesale with its weighted layer. The two halves are one
# wire and must move in one cut — a flag with no call is a seam that is ON in a
# file nobody reads, and every other check stays green while it happens.
SOURCE_REF = "ff64bc504e0c8043915c2cbf05e53a4cc270285f"

# Order is load-bearing. Verdict.lua must load before ChestAdvisor.lua
# (ChestAdvisor reads _G.Verdict at load time). Weights.lua sits directly after
# Constants.lua and before Verdict.lua: it writes `StatForge.Weights` onto the
# global Constants.lua creates, and Verdict.weightsFor probes that table AT CALL
# TIME. Marks.lua is the ONE arrow renderer every surface asks
# (`_G.TouchstoneMarks`), so a cut that left it behind would ship an advisor
# that draws no arrows at all.
#
# Card t_13c807af (Step 3 payload): StatOrders.lua and Arbitration.lua sit after
# Verdict.lua and before ChestAdvisor.lua. Both the comparator and the advisor
# resolve `Arbitration` at CALL time through the global that file publishes
# (Verdict.lua `local A = rawget(_G, "Arbitration")`, ChestAdvisor.lua the same,
# and `type(Arbitration) == "table"` in the tooltip's context label), so the
# module has to be loaded before either can ask. StatOrders.lua is the published
# order data the arbitration reads. Both are pristine: they go in the COPY lane.
# Calibration.lua is deliberately NOT vendored — it is a dev surface (/ts3cal)
# that no verdict path reads (P3's absence check is what keeps that true).
LUA_FILES = [
    "Constants.lua",
    "Weights.lua",
    "UI.lua",
    "OptionsTab.lua",
    "UpgradesTab.lua",
    "LogTab.lua",
    "Diagnostics.lua",
    "Probe.lua",
    "ChestAdvisor/Marks.lua",
    "ChestAdvisor/Verdict.lua",
    "ChestAdvisor/StatOrders.lua",
    "ChestAdvisor/Arbitration.lua",
    "ChestAdvisor/ChestAdvisor.lua",
    "GearAPI.lua",
    "Integration.lua",
    "Core.lua",
]
ASSET_FILES = ["ChestAdvisor/marker.tga"]

# The eight files whose patch carries something the seams do not. Everything not
# named here is vendored pristine — and the copy check proves it. This list is
# explicit on purpose: deriving it from the presence of a patch file would let a
# missing patch file silently turn a patched file into a "pristine" one.
PATCHED = [
    "UI.lua",
    "OptionsTab.lua",
    "UpgradesTab.lua",
    "LogTab.lua",
    "ChestAdvisor/Verdict.lua",
    "ChestAdvisor/ChestAdvisor.lua",
    "Integration.lua",
    "Core.lua",
]
PRISTINE = [name for name in LUA_FILES if name not in PATCHED]

# The module block as it must appear in MightiePack.toc, in order. Bootstrap.lua
# is hand-written (it owns the duplicate-load guard) and is not copied.
TOC_BLOCK = ["Modules/Touchstone/Bootstrap.lua"] + [
    "Modules/Touchstone/" + name for name in LUA_FILES
]


class SyncError(RuntimeError):
    pass


def read_text(path: Path) -> str:
    try:
        raw = path.read_text(encoding="utf-8-sig")
    except FileNotFoundError:
        raise SyncError("missing source file: {}".format(path))
    return raw.replace("\r\n", "\n").replace("\r", "\n")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)


def sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


# ── the pin manifest ─────────────────────────────────────────────────────────


def read_pin_manifest() -> dict:
    """{file name: sha256 of the pin's blob}, plus the ref it was written for."""
    if not PIN_MANIFEST.is_file():
        raise SyncError(
            "missing {}: it records the pin's blob hashes and the two shipped "
            "checks cannot run without it. Regenerate it with "
            "`--write-pin --src <StatForge checkout at {}>`.".format(
                PIN_MANIFEST.relative_to(REPO_ROOT), SOURCE_REF[:7]
            )
        )
    ref = None
    blobs = {}
    for line in read_text(PIN_MANIFEST).splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("ref "):
            ref = line.split()[1]
            continue
        digest, _, name = line.partition("  ")
        if len(digest) != 64 or not name:
            raise SyncError("{}: unreadable line {!r}".format(PIN_MANIFEST.name, line))
        blobs[name.strip()] = digest
    if ref is None:
        raise SyncError("{}: no `ref` line".format(PIN_MANIFEST.name))
    if ref != SOURCE_REF:
        raise SyncError(
            "{} is written for {} but SOURCE_REF is {}: the manifest and the pin "
            "have parted company. Re-run `--write-pin` against the new pin.".format(
                PIN_MANIFEST.name, ref, SOURCE_REF
            )
        )
    missing = [name for name in LUA_FILES if name not in blobs]
    if missing:
        raise SyncError(
            "{}: no hash for {}. Regenerate it with --write-pin.".format(
                PIN_MANIFEST.name, ", ".join(missing)
            )
        )
    return {"ref": ref, "blobs": blobs}


def write_pin_manifest(src_root: Path) -> None:
    head = git_commit_sha(src_root)
    if head != SOURCE_REF:
        raise SyncError(
            "refusing to write the manifest: the checkout is at {} but SOURCE_REF "
            "is {}. A manifest written from a different commit would pin hashes "
            "nothing else agrees with.".format(head or "no commit", SOURCE_REF)
        )
    lines = [
        "# The pin's blobs, one line per vendored file: <sha256>  <path>",
        "#",
        "# Written by `tools/sync_touchstone.py --write-pin --src <checkout at the",
        "# pin>`. The COPY and PATCH checks compare against these hashes, so a file",
        "# that is edited by hand, or a patch that stops applying to the pin, fails",
        "# in CI by name without needing StatForge (a private repository).",
        "#",
        "# Regenerate it ONLY when SOURCE_REF moves, and in the same commit.",
        "ref " + SOURCE_REF,
    ]
    for name in LUA_FILES:
        lines.append("{}  {}".format(sha256(read_text(src_root / name)), name))
    write_text(PIN_MANIFEST, "\n".join(lines) + "\n")
    print("sync_touchstone: wrote {} ({} blobs at {})".format(
        PIN_MANIFEST.relative_to(REPO_ROOT), len(LUA_FILES), SOURCE_REF[:7]))


# ── patch application ───────────────────────────────────────────────────────


def _patch_path(name: str) -> Path:
    return PATCH_DIR / (name.replace("/", "__") + ".patch")


def parse_hunks(patch_text: str, name: str) -> list:
    lines = patch_text.splitlines()
    hunks = []
    i = 0
    while i < len(lines):
        if lines[i].startswith("@@"):
            hunk = []
            i += 1
            while i < len(lines) and not lines[i].startswith("@@"):
                if lines[i].startswith("\\"):  # "\ No newline at end of file"
                    i += 1
                    continue
                hunk.append(lines[i])
                i += 1
            hunks.append(hunk)
            continue
        i += 1
    if not hunks:
        raise SyncError("{}: patch has no hunks".format(name))
    return hunks


def apply_hunks(text: str, hunks: list, name: str, label: str) -> str:
    """Apply hunks with exact context, or raise: no fuzzy matching, no drops."""
    ends_nl = text.endswith("\n")
    body = text.splitlines()
    cursor = 0
    out = []
    applied = 0
    for hunk in hunks:
        old_block = []
        new_block = []
        for hl in hunk:
            if hl.startswith("+"):
                new_block.append(hl[1:])
            elif hl.startswith("-"):
                old_block.append(hl[1:])
            elif hl.startswith(" "):
                old_block.append(hl[1:])
                new_block.append(hl[1:])
            elif hl == "":
                old_block.append("")
                new_block.append("")
            else:
                raise SyncError("{}: unreadable patch line: {!r}".format(name, hl[:80]))
        if not old_block:
            raise SyncError(
                "{}: patch hunk has no context and cannot be uniquely anchored".format(name)
            )
        last = len(body) - len(old_block)
        matches = [pos for pos in range(cursor, last + 1)
                   if body[pos:pos + len(old_block)] == old_block]
        if not matches:
            raise SyncError(
                "{}: {} hunk not found (anchor drifted): {!r}".format(
                    label, name, old_block[0][:70])
            )
        if len(matches) > 1:
            raise SyncError(
                "{}: {} hunk matched {} times, expected exactly 1 (context is not "
                "unique)".format(label, name, len(matches))
            )
        found = matches[0]
        out.extend(body[cursor:found])
        out.extend(new_block)
        cursor = found + len(old_block)
        applied += 1
    if applied == 0:
        raise SyncError("{}: patch applied zero hunks".format(name))
    out.extend(body[cursor:])
    result = "\n".join(out)
    if ends_nl or text == "":
        result += "\n"
    return result


def apply_named_patch(name: str, text: str) -> str:
    path = _patch_path(name)
    if not path.is_file():
        raise SyncError(
            "{} is in PATCHED but {} does not exist".format(name, path.relative_to(REPO_ROOT))
        )
    patch_text = read_text(path)
    if patch_text.strip() == "":
        raise SyncError("{}: patch file is empty (zero hunks)".format(path.name))
    return apply_hunks(text, parse_hunks(patch_text, name), name, "PATCH")


def reverse_patch_text(patch_text: str) -> str:
    """Swap the sides of a patch: the post-image becomes the pre-image.

    The file headers (`--- a/f`, `+++ b/f`) are dropped, and ONLY those: a Lua
    comment line is `-- …`, and the third dash of a `---` line inside a hunk is
    patch content that happens to look like a header.
    """
    out = []
    seen_hunk = False
    for line in patch_text.splitlines():
        if line.startswith("@@"):
            seen_hunk = True
        elif not seen_hunk and (line.startswith("--- ") or line.startswith("+++ ")):
            continue            # file headers: the applicator ignores them anyway
        if line.startswith("+"):
            out.append("-" + line[1:])
        elif line.startswith("-"):
            out.append("+" + line[1:])
        else:
            out.append(line)
    return "\n".join(out) + "\n"


# ── generate ────────────────────────────────────────────────────────────────


def generate(src_root: Path) -> dict:
    """Return {dest path: text}. The pin's blob, plus the patch if there is one."""
    if not src_root.is_dir():
        raise SyncError("--src is not a directory: {}".format(src_root))
    outputs = {}
    for name in LUA_FILES:
        text = read_text(src_root / name)
        if name in PATCHED:
            text = apply_named_patch(name, text)
        outputs[name] = text
    return outputs


def write_outputs(src_root: Path, outputs: dict) -> None:
    for name, text in outputs.items():
        write_text(DEST_ROOT / name, text)
    for name in ASSET_FILES:
        src = src_root / name
        if not src.is_file():
            raise SyncError("missing source asset: {}".format(src))
        dest = DEST_ROOT / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(src.read_bytes())


# ── audits ──────────────────────────────────────────────────────────────────


def audit_toc() -> list:
    """Check the TOC block, SV declarations and the Assets line. Returns problems."""
    problems = []
    try:
        toc = read_text(TOC_PATH)
    except SyncError as exc:
        return [str(exc)]

    entries = []
    for line in toc.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            entries.append(stripped)

    start = None
    for index, entry in enumerate(entries):
        if entry == TOC_BLOCK[0]:
            start = index
            break
    if start is None:
        problems.append("TOC has no {} entry".format(TOC_BLOCK[0]))
    else:
        got = entries[start : start + len(TOC_BLOCK)]
        if got != TOC_BLOCK:
            problems.append(
                "TOC Touchstone block is out of order:\n  expected {}\n  got      {}".format(
                    TOC_BLOCK, got
                )
            )

    for entry in ASSET_FILES:
        if entry in entries:
            problems.append(
                "{} is in the TOC body; textures belong on the Assets line only".format(entry)
            )

    header = {}
    for line in toc.splitlines():
        if line.startswith("## ") and ":" in line:
            key, _, value = line[3:].partition(":")
            header[key.strip()] = value.strip()

    saved = header.get("SavedVariables", "")
    for var in ("MightiePackDB", "NodeTrailDB", "StatForgeDB"):
        if var not in [part.strip() for part in saved.split(",")]:
            problems.append("## SavedVariables is missing {}".format(var))
    per_char = header.get("SavedVariablesPerCharacter", "")
    if "ChestAdvisorDB" not in [part.strip() for part in per_char.split(",")]:
        problems.append("## SavedVariablesPerCharacter is missing ChestAdvisorDB")
    assets = header.get("Assets", "")
    if "Modules/Touchstone/ChestAdvisor/marker.tga" not in assets:
        problems.append("## Assets does not name Modules/Touchstone/ChestAdvisor/marker.tga")

    return problems


_SAVED_VARS = re.compile(r"\b\d+/[A-Za-z0-9]+-[A-Za-z0-9]+/SavedVariables/([A-Za-z0-9_]+\.lua)")
_WIN_USER = re.compile(r"[A-Za-z]:[\\/]Users[\\/][^`'\"\s)]*")
_POSIX_USER = re.compile(r"(?:/mnt/[a-z]/|/home/|/Users/)[^`'\"\s)]*")


def audit_outputs(outputs: dict) -> list:
    """The invariants the pack's own contracts depend on, checked on the bytes.

    These are not "did the merge work" checks — the specs prove behaviour. They are
    the cheap structural facts that a re-pin must not quietly lose, and each one
    names the file it is about.
    """
    problems = []
    for name, text in outputs.items():
        if _SAVED_VARS.search(text) or _WIN_USER.search(text) or _POSIX_USER.search(text):
            problems.append("{} still carries a client path".format(name))
        head = text.splitlines()[:4]
        if not head or head[-1] != "if TouchstoneSkip then return end":
            problems.append(
                "{} does not carry the host opt-out on its fourth line "
                "(the pin ships it; a file without it runs with the module off)".format(name)
            )

    core = outputs.get("Core.lua", "")
    if 'CreateFrame("Frame")' in core:
        problems.append("Core.lua still creates an event frame at load")
    if "SlashCmdList.TOUCHSTONE = touchstoneSlash" not in core:
        problems.append("Core.lua does not register SlashCmdList.TOUCHSTONE inside SF.Enable")
    advisor = outputs.get("ChestAdvisor/ChestAdvisor.lua", "")
    if "function ChestAdvisor.Enable()" not in advisor:
        problems.append("ChestAdvisor.lua has no ChestAdvisor.Enable()")
    if "function SF.EnableIntegrations()" not in outputs.get("Integration.lua", ""):
        problems.append("Integration.lua has no SF.EnableIntegrations()")
    if 'TOOLTIP_PREFIX = "Touchstone: "' in advisor:
        problems.append("ChestAdvisor.lua still renders the addon's name into the tooltip line")
    if "local v2, r2, w2 = ChestAdvisor._memoVerdict" in advisor:
        problems.append(
            "ChestAdvisor.lua declares w2 inside the branch that assigns it; the "
            "diag row below cannot see it"
        )
    if "\tlocal a, b, c = fn()" not in advisor:
        problems.append(
            "ChestAdvisor.lua's verdict memo drops the third value; a memo HIT would "
            "answer the same verdict with no weighted detail"
        )

    verdict = outputs.get("ChestAdvisor/Verdict.lua", "")
    start = verdict.find("function Verdict.playerHitPercent")
    if start < 0:
        problems.append("Verdict.lua has no Verdict.playerHitPercent")
    else:
        nxt = verdict.find("\nfunction ", start + 1)
        body = verdict[max(0, start - 2500): start] + verdict[start: nxt if nxt > 0 else None]
        if "local function isSecretNumber" not in body or "issecretvalue" not in body:
            problems.append(
                "Verdict.playerHitPercent has no issecretvalue / isSecretNumber guard"
            )
        if "if bSec or mSec then return nil end" not in verdict[start: nxt if nxt > 0 else None]:
            problems.append(
                "Verdict.playerHitPercent does not refuse a secret half before adding"
            )
    return problems


# ── the two shipped checks ───────────────────────────────────────────────────


def _shipped_text(name: str) -> str:
    path = DEST_ROOT / name
    if not path.is_file():
        raise SyncError("shipped file missing: {}".format(name))
    return read_text(path)


def check_pristine(blobs: dict) -> list:
    """COPY: every pristine file's sha256 is the pin's blob."""
    problems = []
    for name in PRISTINE:
        try:
            text = _shipped_text(name)
        except SyncError as exc:
            problems.append("COPY: {}".format(exc))
            continue
        got = sha256(text)
        want = blobs[name]
        if got != want:
            problems.append(
                "COPY: {} is not the pin's blob — sha256 {} != {} (StatForge {}). "
                "This file has no patch: re-copy it from the pin.".format(
                    name, got[:12], want[:12], SOURCE_REF[:7]
                )
            )
    return problems


def check_patched(blobs: dict) -> list:
    """PATCH: every patch reverses out of the shipped file back to the pin's blob."""
    problems = []
    for name in PATCHED:
        patch = _patch_path(name)
        if not patch.is_file():
            problems.append(
                "PATCH: {} is missing for {} — the file is not pristine, so its "
                "patch is the only thing that can account for the difference.".format(
                    patch.name, name)
            )
            continue
        try:
            shipped = _shipped_text(name)
        except SyncError as exc:
            problems.append("PATCH: {}".format(exc))
            continue
        patch_text = read_text(patch)
        try:
            parse_hunks(patch_text, name)
            pinned = apply_hunks(shipped, parse_hunks(reverse_patch_text(patch_text), name),
                                 name, "PATCH")
        except SyncError as exc:
            detail = str(exc)
            if detail.startswith("PATCH: "):
                detail = detail[len("PATCH: "):]
            problems.append(
                "PATCH: {} no longer applies to the pin for {} — {}. The shipped "
                "file is not this patch's result. Re-cut the patch against {}.".format(
                    patch.name, name, detail, SOURCE_REF[:7])
            )
            continue
        got = sha256(pinned)
        if got != blobs[name]:
            problems.append(
                "PATCH: {} no longer applies to the pin for {} — reversing it gives "
                "sha256 {} but the pin's blob is {}. Re-cut the patch against {}.".format(
                    patch.name, name, got[:12], blobs[name][:12], SOURCE_REF[:7])
            )
    return problems


def verify_pin(src_root: Path, blobs: dict) -> list:
    """PIN: the checkout is the named commit and its blobs are the manifest's."""
    problems = []
    head = git_commit_sha(src_root)
    if head != SOURCE_REF:
        problems.append(
            "PIN: the checkout is at {} but SOURCE_REF is {}. Point --src at the "
            "pinned commit (git checkout {}) and re-run.".format(
                head or "no commit", SOURCE_REF, SOURCE_REF[:7])
        )
    for name in LUA_FILES:
        got = sha256(read_text(src_root / name))
        if got != blobs[name]:
            problems.append(
                "PIN: {} at {} hashes to {} but {} records {}. The pin moved, or the "
                "manifest was written from another commit: regenerate it with "
                "--write-pin.".format(name, (head or "")[:7], got[:12],
                                      PIN_MANIFEST.name, blobs[name][:12])
            )
    return problems


def _git(args: list, cwd: Path) -> str:
    done = subprocess.run(
        ["git", "-C", str(cwd)] + args,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False,
    )
    if done.returncode != 0:
        raise SyncError("git {}: {}".format(" ".join(args), done.stderr.strip()))
    return done.stdout.strip()


def git_commit_sha(root: Path) -> str:
    """The full commit of a git checkout, or "" when the folder is not one."""
    try:
        return _git(["rev-parse", "HEAD"], root)
    except (SyncError, OSError):
        return ""


def resolve_source(src: str | None, ref: str) -> tuple:
    """Return (checkout root, printed label, temp clone to clean up or None)."""
    if src:
        root = Path(src).expanduser().resolve()
        if not root.is_dir():
            raise SyncError("--src is not a directory: {}".format(root))
        sha = git_commit_sha(root)
        return root, "{}@{}".format(root, (sha or "unknown")[:7]), None

    clone = Path(tempfile.mkdtemp(prefix="touchstone-src-"))
    steps = [
        ["git", "init", "--quiet", str(clone)],
        ["git", "-C", str(clone), "remote", "add", "origin", SOURCE_URL],
        ["git", "-C", str(clone), "fetch", "--quiet", "--depth", "1", "origin", ref],
        ["git", "-C", str(clone), "checkout", "--quiet", "FETCH_HEAD"],
    ]
    for step in steps:
        done = subprocess.run(step, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if done.returncode != 0:
            shutil.rmtree(clone, ignore_errors=True)
            raise SyncError(
                "{} failed: {}".format(" ".join(step), (done.stderr or "").strip())
            )
    sha = git_commit_sha(clone)
    if not sha:
        shutil.rmtree(clone, ignore_errors=True)
        raise SyncError("cloned source has no commit: {}".format(clone))
    return clone, "{}@{}".format(SOURCE_URL, sha[:7]), clone


# ── self-test ───────────────────────────────────────────────────────────────


def _self_test_patches() -> int:
    """Fixture tests for the applicator and its reverse direction; no checkout needed."""

    def expect_error(label, fn, needle):
        try:
            fn()
        except SyncError as exc:
            if needle not in str(exc):
                raise AssertionError(
                    "{}: error {!r} did not contain {!r}".format(label, str(exc), needle)
                )
            return
        raise AssertionError("{}: expected SyncError containing {!r}".format(label, needle))

    text = "a\nb\nc\n"
    patch = "--- a/f\n+++ b/f\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n"
    out = apply_hunks(text, parse_hunks(patch, "f"), "f", "PATCH")
    if out != "a\nB\nc\n":
        raise AssertionError("unique apply produced {!r}".format(out))
    # The reverse direction puts the original bytes back.
    back = apply_hunks(out, parse_hunks(reverse_patch_text(patch), "f"), "f", "PATCH")
    if back != text:
        raise AssertionError("reverse apply produced {!r}".format(back))

    dup = "a\nb\nc\na\nb\nc\n"
    expect_error("duplicate context",
                 lambda: apply_hunks(dup, parse_hunks(patch, "f"), "f", "PATCH"),
                 "matched 2 times")
    expect_error("zero hunks", lambda: parse_hunks("--- a/f\n+++ b/f\n", "f"), "no hunks")
    expect_error("missing hunk",
                 lambda: apply_hunks("x\ny\n", parse_hunks(patch, "f"), "f", "PATCH"),
                 "hunk not found")
    expect_error(
        "no context hunk",
        lambda: apply_hunks(text, parse_hunks("--- a/f\n+++ b/f\n@@ -1,0 +1,1 @@\n+x\n", "f"),
                            "f", "PATCH"),
        "hunk has no context",
    )
    print("sync_touchstone patch self-test: ok")
    return 0


# ── main ────────────────────────────────────────────────────────────────────


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--src", default=None,
        help="path to a pristine StatForge checkout; omit to clone {} at {}".format(
            SOURCE_URL, SOURCE_REF[:7]),
    )
    parser.add_argument(
        "--ref", default=SOURCE_REF,
        help="git ref to clone when --src is not given (default: the pin, {})".format(
            SOURCE_REF[:7]),
    )
    parser.add_argument(
        "--verify-only", action="store_true",
        help="generate in memory, run the audits, write nothing",
    )
    parser.add_argument(
        "--verify-shipped", action="store_true",
        help="the COPY and PATCH checks against the committed files; needs no upstream "
             "checkout (this is the CI gate)",
    )
    parser.add_argument(
        "--verify-pin", action="store_true",
        help="check that --src is SOURCE_REF and its blobs match the pin manifest "
             "(needs a checkout; run it when the pin moves)",
    )
    parser.add_argument(
        "--write-pin", action="store_true",
        help="rewrite the pin manifest from --src (only when SOURCE_REF moves)",
    )
    parser.add_argument(
        "--self-test-patches", action="store_true",
        help="run the patch applicator's own fixtures and exit (no checkout needed)",
    )
    args = parser.parse_args(argv)

    if args.self_test_patches:
        return _self_test_patches()

    try:
        if (args.verify_shipped or args.verify_pin) and not args.src:
            # The CI path (and the quick local one): both checks, no clone.
            blobs = read_pin_manifest()["blobs"]
            problems = check_pristine(blobs) + check_patched(blobs)
            if problems:
                for problem in problems:
                    print(problem, file=sys.stderr)
                print("sync_touchstone: {} problem(s); nothing was written".format(
                    len(problems)), file=sys.stderr)
                return 2
            print("sync_touchstone: COPY   {} pristine files are the pin's blobs".format(
                len(PRISTINE)))
            print("sync_touchstone: PATCH  {} patches reverse to the pin's blobs".format(
                len(PATCHED)))
            return 0

        temp_clone = None
        try:
            src_root, source, temp_clone = resolve_source(args.src, args.ref)
            if args.write_pin:
                write_pin_manifest(src_root)
                return 0
            blobs = read_pin_manifest()["blobs"]
            outputs = generate(src_root)
            problems = audit_toc() + audit_outputs(outputs)
            if args.verify_pin:
                problems += verify_pin(src_root, blobs)
            if args.verify_shipped:
                problems += check_pristine(blobs) + check_patched(blobs)
                for name, text in outputs.items():
                    try:
                        shipped = _shipped_text(name)
                    except SyncError as exc:
                        problems.append("COPY: {}".format(exc))
                        continue
                    if shipped != text:
                        problems.append(
                            "COPY: shipped {} does not match generate(pin)+patch; "
                            "re-run the sync or re-cut the patch".format(name)
                        )
            if problems:
                for problem in problems:
                    print(problem, file=sys.stderr)
                return 2
            if not args.verify_only and not args.verify_shipped and not args.verify_pin:
                write_outputs(src_root, outputs)
            print("sync_touchstone: source {}".format(source))
            print("sync_touchstone: {} lua files {} ({} pristine, {} patched); toc ok".format(
                len(outputs),
                "verified" if (args.verify_only or args.verify_shipped or args.verify_pin)
                else "written",
                len(PRISTINE), len(PATCHED)))
            return 0
        finally:
            if temp_clone is not None:
                shutil.rmtree(temp_clone, ignore_errors=True)
    except SyncError as exc:
        print("sync_touchstone: ERROR: " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
