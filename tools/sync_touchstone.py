#!/usr/bin/env python3
"""Vendor Touchstone 0.8.3 into MightiePack/Modules/Touchstone.

Copies the twelve upstream files (eleven .lua + the marker.tga asset) from a
``--src`` checkout, applies the five mechanical edits from
``TOUCHSTONE-FOLD-DESIGN.md`` by anchored text replacement, and then audits the
MightiePack TOC.

Every edit is anchored: if a marker is missing *or* occurs more than once the
script exits non-zero and writes nothing for that file. A half-patched module is
worse than a failed sync.

Usage:
    python3 tools/sync_touchstone.py --src /mnt/c/Users/jnick/touchstone-deploy
    python3 tools/sync_touchstone.py --src ... --verify-only
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEST_ROOT = REPO_ROOT / "MightiePack" / "Modules" / "Touchstone"
TOC_PATH = REPO_ROOT / "MightiePack" / "MightiePack.toc"

# Order is load-bearing; see the design doc section 5. Verdict.lua must load
# before ChestAdvisor.lua (ChestAdvisor reads _G.Verdict at load time).
LUA_FILES = [
    "Constants.lua",
    "UI.lua",
    "OptionsTab.lua",
    "UpgradesTab.lua",
    "LogTab.lua",
    "Diagnostics.lua",
    "Probe.lua",
    "ChestAdvisor/Verdict.lua",
    "ChestAdvisor/ChestAdvisor.lua",
    "Integration.lua",
    "Core.lua",
]
ASSET_FILES = ["ChestAdvisor/marker.tga"]

SKIP_GUARD = "if MightiePackTouchstoneSkip then return end\n"

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


def replace_once(text: str, name: str, anchor_id: str, old: str, new: str) -> str:
    """Replace exactly one anchored occurrence, or fail loudly."""
    count = text.count(old)
    if count == 0:
        raise SyncError(
            "{}: anchor not found ({}). Upstream text changed; re-read the "
            "design doc and update sync_touchstone.py before syncing.".format(name, anchor_id)
        )
    if count > 1:
        raise SyncError(
            "{}: anchor {} matched {} times, expected exactly 1".format(name, anchor_id, count)
        )
    return text.replace(old, new, 1)


def edit_core(text: str) -> str:
    """Replace the lifecycle frame with SF.Enable and gate the slash block."""
    text = replace_once(
        text,
        "Core.lua",
        "core.event-frame",
        (
            'local events = CreateFrame("Frame")\n'
            'events:RegisterEvent("ADDON_LOADED")\n'
            'events:RegisterEvent("PLAYER_LOGIN")\n'
            'events:SetScript("OnEvent", function(_, event, arg1)\n'
            "  if event == \"ADDON_LOADED\" and arg1 == SF.ADDON_NAME then\n"
            "    initDB()\n"
            '  elseif event == "PLAYER_LOGIN" then\n'
            "    initDB()\n"
            "    SF.CreateMinimapButton()\n"
            "    SF.UpdateMinimapButton()\n"
            "  end\n"
            "end)\n"
        ),
        (
            "-- Fold (MightiePack Touchstone module): the ADDON_LOADED / PLAYER_LOGIN\n"
            "-- event frame that used to live here is gone. MightiePack fires\n"
            "-- ADDON_LOADED for its own name after SavedVariables exist and calls\n"
            "-- SF.Enable() (defined at the end of this file). initDB above keeps its\n"
            "-- body unchanged. A disabled module creates no frame and no minimap\n"
            "-- button. SF.ADDON_NAME is no longer a behavioural gate anywhere.\n"
        ),
    )
    text = replace_once(
        text,
        "Core.lua",
        "core.slash-handler",
        "function SlashCmdList.TOUCHSTONE(msg)\n",
        (
            "-- Fold: the handler stays here, unchanged in body; only its\n"
            "-- registration moved into SF.Enable() below.\n"
            "local function touchstoneSlash(msg)\n"
        ),
    )
    text = replace_once(
        text,
        "Core.lua",
        "core.slash-strings",
        (
            'SLASH_TOUCHSTONE1 = "/touchstone"\n'
            'SLASH_TOUCHSTONE2 = "/sf"\n'
            'SLASH_TOUCHSTONE3 = "/statforge"\n'
        ),
        (
            "-- Fold (MightiePack Touchstone module): the single registration point.\n"
            "-- Called by the module once, after SavedVariables exist. The three slash\n"
            "-- strings and the handler registration live here so a disabled module\n"
            "-- answers no slash at all. Integration's surfaces are registered here too.\n"
            "function SF.Enable()\n"
            "  initDB()\n"
            "  SF.CreateMinimapButton()\n"
            "  SF.UpdateMinimapButton()\n"
            "  -- Integration.lua defines this and loads before Core.lua.\n"
            '  if type(SF.EnableIntegrations) == "function" then\n'
            "    SF.EnableIntegrations()\n"
            "  end\n"
            '  SLASH_TOUCHSTONE1 = "/touchstone"\n'
            '  SLASH_TOUCHSTONE2 = "/sf"\n'
            '  SLASH_TOUCHSTONE3 = "/statforge"\n'
            "  SlashCmdList.TOUCHSTONE = touchstoneSlash\n"
            "end\n"
        ),
    )
    return text


def edit_integration(text: str) -> str:
    return replace_once(
        text,
        "Integration.lua",
        "integration.load-calls",
        "SF.RegisterBlizzardSettings()\nSF.RegisterCompartment()\n",
        (
            "-- Fold (MightiePack Touchstone module): registration is deferred to\n"
            "-- SF.Enable() in Core.lua, so a disabled module adds no Blizzard settings\n"
            "-- category and no addon-compartment entry. Both functions above are\n"
            "-- unchanged; only the two calls moved.\n"
            "function SF.EnableIntegrations()\n"
            "  SF.RegisterBlizzardSettings()\n"
            "  SF.RegisterCompartment()\n"
           "end\n"
        ),
    )


def edit_chestadvisor(text: str) -> str:
    """Gate the slash/log registration, the quest/toast surfaces and the scan-frame tail."""
    text = replace_once(
        text,
        "ChestAdvisor/ChestAdvisor.lua",
        "ca.init-log-and-slash-call",
        "initLogAndSlash()\nend\n",
        (
            "-- Fold (MightiePack Touchstone module): initLogAndSlash() registers the\n"
            "-- four slash strings, the /up,/upgrade,/chestadvice,/ts handler and the\n"
            "-- disagreement log hooks. Its body below is unchanged; only the CALL is\n"
            "-- deferred to ChestAdvisor.Enable().\n"
            "ChestAdvisor._initLogAndSlash = function()\n"
            "\tif ChestAdvisor._slashAndLogEnabled then return end\n"
            "\tChestAdvisor._slashAndLogEnabled = true\n"
            "\tinitLogAndSlash()\n"
            "end\n"
            "end\n"
        ),
    )

    # The design doc's inventory listed only the getFrame() tail. Loading the
    # vendored file showed four more file-scope installers, one of which
    # (initQuestSurface) creates ChestAdvisor_QuestFrame. They are all deferred
    # here so a disabled module creates no frame and hooks nothing. Each one is
    # already a local function inside its own `do` block, so it is exposed on the
    # table rather than moved.
    text = replace_once(
        text,
        "ChestAdvisor/ChestAdvisor.lua",
        "ca.install-refresh-hooks-call",
        "-- Install the hooks at load time.\ninstallRefreshHooks()\n",
        (
            "-- Fold (MightiePack Touchstone module): hook installation is deferred to\n"
            "-- ChestAdvisor.Enable(). The function is already exposed as\n"
            "-- ChestAdvisor._installRefreshHooks above.\n"
        ),
    )
    text = replace_once(
        text,
        "ChestAdvisor/ChestAdvisor.lua",
        "ca.init-quest-surface-call",
        "ChestAdvisor._readWornLinks = readWornLinks\nend\ninitQuestSurface()\nend\n",
        (
            "ChestAdvisor._readWornLinks = readWornLinks\n"
            "end\n"
            "-- Fold (MightiePack Touchstone module): the quest surface owns\n"
            "-- ChestAdvisor_QuestFrame and the reward hooks; Enable() installs it.\n"
            "ChestAdvisor._initQuestSurface = initQuestSurface\n"
            "end\n"
        ),
    )
    text = replace_once(
        text,
        "ChestAdvisor/ChestAdvisor.lua",
        "ca.paperdoll-merchant-hook-calls",
        (
            "-- Install at load, then again on every scan event (the frames are created lazily).\n"
            "ChestAdvisor._installPaperDollHooks()\n"
            "ChestAdvisor._installMerchantHooks()\n"
        ),
        (
            "-- Fold (MightiePack Touchstone module): deferred to ChestAdvisor.Enable(),\n"
            "-- then re-attempted on every scan event (the frames are created lazily).\n"
        ),
    )
    text = replace_once(
        text,
        "ChestAdvisor/ChestAdvisor.lua",
        "ca.init-toast-surface-call",
        "ChestAdvisor._toastIsEnabled = toastIsEnabled\nend\ninitToastSurface()\nend\n",
        (
            "ChestAdvisor._toastIsEnabled = toastIsEnabled\n"
            "end\n"
            "-- Fold (MightiePack Touchstone module): the toast panel/frame is created by\n"
            "-- Enable() on first enabled load, not at file load.\n"
            "ChestAdvisor._initToastSurface = initToastSurface\n"
            "end\n"
        ),
    )

    # ---- Load-order safety (live bug 2026-11-07) ----------------------------
    # Upstream publishes these from the init function bodies and then CALLS the
    # init functions at load, so the exports exist before `scan` captures them.
    # The fold defers those calls to Enable(), which runs AFTER the captures —
    # so a load-time `local f = ChestAdvisor._x` captured nil forever and every
    # scan ended in "attempt to call a nil value" (client: ChestAdvisor.lua:4982).
    # Resolve at call time instead; the wrappers keep the same names and arity.
    text = replace_once(
        text,
        "ChestAdvisor/ChestAdvisor.lua",
        "ca.capture-quest-exports",
        (
            "local readWornLinks = ChestAdvisor._readWornLinks\n"
            "local judgeQuestReward = ChestAdvisor._judgeQuestReward\n"
        ),
        (
            "-- Fold (load order): these are published by Enable(); capture them at\n"
            "-- call time so a disabled-then-enabled module cannot leave nil behind.\n"
            "local function readWornLinks(...)\n"
            "\tlocal f = ChestAdvisor._readWornLinks\n"
            "\tif type(f) == \"function\" then return f(...) end\n"
            "end\n"
            "local function judgeQuestReward(...)\n"
            "\tlocal f = ChestAdvisor._judgeQuestReward\n"
            "\tif type(f) == \"function\" then return f(...) end\n"
            "end\n"
        ),
    )
    text = replace_once(
        text,
        "ChestAdvisor/ChestAdvisor.lua",
        "ca.capture-scan-exports",
        (
            "local maybeToastUpgrades = ChestAdvisor._maybeToastUpgrades\n"
            "local refreshQuestMarkers = ChestAdvisor.refreshQuestMarkers\n"
        ),
        (
            "-- Fold (load order): same reason as above — Enable() publishes these.\n"
            "local function maybeToastUpgrades(...)\n"
            "\tlocal f = ChestAdvisor._maybeToastUpgrades\n"
            "\tif type(f) == \"function\" then return f(...) end\n"
            "end\n"
            "local function refreshQuestMarkers(...)\n"
            "\tlocal f = ChestAdvisor.refreshQuestMarkers\n"
            "\tif type(f) == \"function\" then return f(...) end\n"
            "end\n"
        ),
    )

    tail_marker = "-- Ensure the frame exists at load time.\n"
    if text.count(tail_marker) != 1:
        raise SyncError(
            "ChestAdvisor/ChestAdvisor.lua: anchor ca.load-tail not found "
            "(or not unique): {!r}".format(tail_marker)
        )
    start = text.index(tail_marker)
    tail = text[start:]
    tail = tail.replace(
        "-- Ensure the frame exists at load time.",
        "-- Ensure the scan frame exists once the module is enabled.",
    )
    tail = tail.replace(
        "-- Card t_ed71a583: install the item-tooltip verdict line ONCE, at load.",
        "-- Card t_ed71a583: install the item-tooltip verdict line ONCE, on first enable.",
    )
    if "installTooltipHook()" not in tail:
        raise SyncError(
            "ChestAdvisor/ChestAdvisor.lua: anchor ca.load-tail has no "
            "installTooltipHook() call"
        )
    if tail.count("installTooltipHook()") != 1:
        raise SyncError(
            "ChestAdvisor/ChestAdvisor.lua: anchor ca.load-tail matched "
            "installTooltipHook() {} times".format(tail.count("installTooltipHook()"))
        )

    indented = "".join(
        ("\t" + line if line.strip() else line) for line in tail.splitlines(keepends=True)
    )
    new_tail = (
        "-- Fold (MightiePack Touchstone module): every load-time surface is installed\n"
        "-- here, in the order the file used to install them at load, and only when the\n"
        "-- module is enabled. The handlers above are unchanged.\n"
        "function ChestAdvisor.Enable()\n"
        "\tif ChestAdvisor._enabled then return end\n"
        "\tChestAdvisor._enabled = true\n"
        "\tChestAdvisor._installRefreshHooks()\n"
        "\tChestAdvisor._initQuestSurface()\n"
        "\tChestAdvisor._installPaperDollHooks()\n"
        "\tChestAdvisor._installMerchantHooks()\n"
        "\tChestAdvisor._initToastSurface()\n"
        "\tChestAdvisor._initLogAndSlash()\n"
        + indented
        + "end\n"
    )
    return text[:start] + new_tail


EDITORS = {
    "Core.lua": edit_core,
    "Integration.lua": edit_integration,
    "ChestAdvisor/ChestAdvisor.lua": edit_chestadvisor,
}


def load_guarded(src_root: Path, name: str) -> str:
    text = read_text(src_root / name)
    if text.startswith("if MightiePackTouchstoneSkip then return end"):
        raise SyncError(
            "{} already carries a skip guard — is --src pointing at a previous "
            "sync output instead of the pristine upstream checkout?".format(name)
        )
    return SKIP_GUARD + text


def generate(src_root: Path) -> dict:
    """Return {relative dest path: text} for every vendored file."""
    if not src_root.is_dir():
        raise SyncError("--src is not a directory: {}".format(src_root))
    outputs = {}
    for name in LUA_FILES:
        text = load_guarded(src_root, name)
        editor = EDITORS.get(name)
        if editor is not None:
            text = editor(text)
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


def audit_outputs(outputs: dict) -> list:
    problems = []
    for name, text in outputs.items():
        if not text.startswith(SKIP_GUARD):
            problems.append("{} does not start with the skip guard".format(name))

    core = outputs.get("Core.lua", "")
    if 'CreateFrame("Frame")' in core:
        problems.append("Core.lua still creates an event frame at load")
    if 'SlashCmdList.TOUCHSTONE = touchstoneSlash' not in core:
        problems.append("Core.lua does not register SlashCmdList.TOUCHSTONE inside SF.Enable")
    if "function ChestAdvisor.Enable()" not in outputs.get("ChestAdvisor/ChestAdvisor.lua", ""):
        problems.append("ChestAdvisor.lua has no ChestAdvisor.Enable()")
    if "function SF.EnableIntegrations()" not in outputs.get("Integration.lua", ""):
        problems.append("Integration.lua has no SF.EnableIntegrations()")
    return problems


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--src",
        required=True,
        help="path to the pristine touchstone-deploy checkout",
    )
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="regenerate in memory and audit everything, but write nothing",
    )
    args = parser.parse_args(argv)
    src_root = Path(args.src)

    try:
        outputs = generate(src_root)
        problems = audit_toc() + audit_outputs(outputs)
        if problems:
            for problem in problems:
                print("TOC/AUDIT: " + problem, file=sys.stderr)
            return 2
        if not args.verify_only:
            write_outputs(src_root, outputs)
        print(
            "sync_touchstone: {} lua files {}; toc ok".format(
                len(outputs), "verified" if args.verify_only else "written"
            )
        )
        return 0
    except SyncError as exc:
        print("sync_touchstone: ERROR: " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
