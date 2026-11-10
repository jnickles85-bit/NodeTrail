#!/usr/bin/env python3
"""Vendor Touchstone from StatForge into MightiePack/Modules/Touchstone.

Copies the twelve upstream files (eleven .lua + the marker.tga asset) from a
StatForge checkout, applies the fold's edits by anchored text replacement, and then
audits the MightiePack TOC.

The fold's design record is the per-edit comment block in this file: what each edit
is for, why the anchor is the text it is, and what breaks if it is removed. There is
no separate design document.

The source is StatForge ``main``, cloned at run time, and the resolved commit is
printed so every sync names the upstream it was generated from::

    https://github.com/jnickles85-bit/StatForge.git@80accdd

``--src`` still points the run at a local checkout (a pristine deploy folder or
a worktree) instead of cloning; the resolved commit — when the folder is a git
checkout — is printed the same way.

Every edit is anchored: if a marker is missing *or* occurs more than once the
script exits non-zero and writes nothing for that file. A half-patched module is
worse than a failed sync.

Usage:
    python3 tools/sync_touchstone.py                     # clone StatForge main
    python3 tools/sync_touchstone.py --ref 80accdd       # …or pin a commit
    python3 tools/sync_touchstone.py --src /mnt/c/.../touchstone-deploy
    python3 tools/sync_touchstone.py --verify-only
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEST_ROOT = REPO_ROOT / "MightiePack" / "Modules" / "Touchstone"
TOC_PATH = REPO_ROOT / "MightiePack" / "MightiePack.toc"

# The fold is generated from StatForge, not from a hand-kept local folder: the
# default source is the repository's own main, cloned at run time, and the
# resolved commit is printed with the result so a vendored tree can always be
# traced back to the upstream it came from.
SOURCE_URL = "https://github.com/jnickles85-bit/StatForge.git"
# Pinned, not "main": a sync must reproduce the tree it was reviewed against, and
# `git clone --branch main` would silently move with upstream. `--ref main` still
# resolves to whatever main is at run time, for a deliberate catch-up.
SOURCE_REF = "80accdd47b4db127d929ae1010f5b34a96a74e83"

# Order is load-bearing. Verdict.lua must load
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
        "ChestAdvisor._toastLifetimeMax = TOAST_LIFETIME_MAX\nend\ninitToastSurface()\nend\n",
        (
            "ChestAdvisor._toastLifetimeMax = TOAST_LIFETIME_MAX\n"
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

    # ---- No addon name in the rendered tooltip line (t_c2e67619) -----------
    # The gear tooltip line read "Touchstone: Upgrade — …". The addon's own
    # name is not wanted there: the verdict word leads. The display prefix is
    # emptied rather than deleted, so every surface that renders it (the item
    # tooltip's four headlines and the bag/quest hover explain lines) loses the
    # name together and cannot drift apart.
    text = replace_once(
        text,
        "ChestAdvisor/ChestAdvisor.lua",
        "ca.tooltip-display-prefix",
        'local TOOLTIP_PREFIX = "Touchstone: "\n',
        (
            "-- Fold (MightiePack, t_c2e67619): the addon's own name is not\n"
            "-- written into the player's tooltip. The verdict word leads the\n"
            "-- line. Every rendered surface reads this one constant, so they all\n"
            "-- lose the name together. The duplicate guard below needs a marker\n"
            "-- of its own now — see ca.tooltip-duplicate-guard.\n"
            'local TOOLTIP_PREFIX = ""\n'
        ),
    )
    # ... and the duplicate guard has to change WITH it: it searched the line
    # for the prefix, which is now empty (an empty pattern matches every
    # string, so the guard would answer "our line is here" for any tooltip and
    # the verdict line would never appear at all). It keys on what the line
    # DOES lead with instead: a verdict word from the renderer's own vocabulary
    # followed by the headline separator, after the colour escape is stripped.
    text = replace_once(
        text,
        "ChestAdvisor/ChestAdvisor.lua",
        "ca.tooltip-duplicate-guard",
        (
            "\t\t-- The prefix is searched for ANYWHERE in the line, not at position 1:\n"
            '\t\t-- our line opens with a colour escape ("|cff...Touchstone: ..."), so the\n'
            "\t\t-- text never starts at the prefix. (The client renders the escape, so on\n"
            "\t\t-- screen the prefix IS the first visible word.)\n"
            '\t\tif ok2 and type(text) == "string"\n'
            "\t\t\tand text:find(TOOLTIP_PREFIX, 1, true) ~= nil then\n"
            "\t\t\treturn true\n"
            "\t\tend\n"
        ),
        (
            "\t\t-- Fold (MightiePack, t_c2e67619): the rendered line carries no\n"
            "\t\t-- addon name any more, so this guard cannot look for one. It looks\n"
            "\t\t-- for what the line DOES lead with: a verdict word followed by the\n"
            "\t\t-- headline separator, read from the same vocabulary the renderer\n"
            "\t\t-- uses, so render and detection cannot drift. The colour escape the\n"
            "\t\t-- line opens with is stripped first (the client hands back the\n"
            "\t\t-- marked-up string), and the comparison is anchored at position 1 —\n"
            "\t\t-- a verdict word appearing inside some other line never matches.\n"
            '\t\tif ok2 and type(text) == "string" then\n'
            '\t\t\tlocal plain = text:gsub("^%|c%x%x%x%x%x%x%x%x", ""):gsub("^%|r", "")\n'
            "\t\t\tfor _, word in pairs(TOOLTIP_UI.words) do\n"
            '\t\t\t\tlocal marker = word .. " — "\n'
            "\t\t\t\tif plain:sub(1, #marker) == marker then\n"
            "\t\t\t\t\treturn true\n"
            "\t\t\t\tend\n"
            "\t\t\tend\n"
            "\t\tend\n"
        ),
    )

    # ---- t_fe7a636a: the toast trace, and the lifetime as the authority -----
    # "The upgrade toast is a flash" was reported against a build whose early-hide
    # fix is in. The spec harness measured 3750 ms, so the harness was not
    # describing the client: some transition ran early there and nothing in the
    # addon could say which. This fold adds the switch that prints every
    # transition, and then makes the configured lifetime the one thing that
    # decides when a show ends.
    text = edit_toast_trace(text)

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


def edit_toast_trace(text: str) -> str:
    """t_fe7a636a: trace every toast transition, then make the lifetime rule.

    The toast has five ways to end (countdown, the fade-out group's OnFinished,
    that group's fallback timer, a right-click, a scan repair) and the client
    reported a show that died in milliseconds while the harness measured 3750.
    A harness cannot say which transition ran early on a client, so this fold
    does two things, in that order:

      1. `/up toastdebug` prints a GetTime-stamped line for every transition of
         one toast (off by default, ring-buffered because the toast is on screen
         for seconds and nobody can read chat that fast).
      2. The configured lifetime becomes the authority for when a show ends:
         the countdown publishes a deadline, every callback-driven finish is
         refused before it, the fade-in is no longer the only thing that raises
         the alpha, a panel hidden during a live show is put back, and a scan
         that lands while a toast is up may only repair a show that is already
         past its deadline with no fade-out in flight (the old test,
         `lifetimeLeft <= 0`, is true for the whole fade-out window and cut the
         fade short).
    """
    name = "ChestAdvisor/ChestAdvisor.lua"

    # ---- the runtime state the deadline and the repairs need -----------------
    text = replace_once(
        text,
        name,
        "ca.toast-deadline-state",
        (
            "\tcurrent = nil, hovered = false, lifetimeLeft = 0,\n"
            "\theld = {}, deferred = false,\n"
            "\tfadeIn = nil, fadeOut = nil, ticker = nil, afterId = 0,\n"
            "}\n"
        ),
        (
            "\tcurrent = nil, hovered = false, lifetimeLeft = 0,\n"
            "\theld = {}, deferred = false,\n"
            "\tfadeIn = nil, fadeOut = nil, ticker = nil, afterId = 0,\n"
            "\t-- t_fe7a636a: the show's deadline in the client's own clock, and\n"
            "\t-- the counters for the repairs below. `deadline` is refreshed by the\n"
            "\t-- countdown every tick, so a finish step can require that the\n"
            "\t-- configured lifetime really elapsed instead of trusting whichever\n"
            "\t-- animation callback arrived.\n"
            "\tdeadline = nil, fadeArmedAt = nil, lastTickPrinted = nil,\n"
            "\trevived = 0, alphaRestored = 0,\n"
            "\t-- t_4bae0617: the measurement. `shownAt` is GetTime() at the show;\n"
            "\t-- showMs and lastEnd are the measured on-screen time and the word\n"
            "\t-- for how that show ended (nil until one has).\n"
            "\tshownAt = nil, showMs = nil, lastEnd = nil,\n"
            "}\n"
        ),
    )

    # ---- the trace itself, and the switch ------------------------------------
    text = replace_once(
        text,
        name,
        "ca.toast-trace-helpers",
        "local drawToast, advanceToast, showToastItem, toastFinishShow\n",
        (
            "-- ---- t_fe7a636a: the toast's own trace ---------------------------------\n"
            "--\n"
            "-- A toast can end from the countdown, the fade-out group's OnFinished,\n"
            "-- that group's fallback timer, a right-click, or a scan that runs while\n"
            "-- one is up. A tester who reports \"it is a flash\" leaves exactly one\n"
            "-- question: WHICH transition ran early. This prints all of them with the\n"
            "-- client's own clock (GetTime, three decimals). It is OFF until\n"
            "-- /up toastdebug turns it on, and it writes nothing until then.\n"
            "--\n"
            "-- Vocabulary, one line per transition, `t=` always last:\n"
            "--   show id=<n>                      showToastItem starts drawing\n"
            "--   shown id=<n> alpha=<a>           after f:Show()\n"
            "--   fadeIn play id=<n>               the fade-in group was played\n"
            "--   animation finished: group=<fadeIn|fadeOut> id=<n> fadeFor=<nil|id>\n"
            "--   tick id=<n> left=<seconds>       at most once per second\n"
            "--   expire id=<n> reason=<timer|dismiss|rescan|other>\n"
            "--   finish id=<n> reason=<fadeOnFinished|fadeTimer|dismiss|rescan>\n"
            "--      lifeLeft=<seconds>\n"
            "-- plus what the fix adds, so a flash is diagnosed from the text:\n"
            "--   finish refused: id=<n> reason=<r> left=<seconds>\n"
            "--   alpha restore id=<n> was=<a>     the fade-in left the panel at 0\n"
            "--   revive id=<n> left=<seconds>     a hidden panel was shown again\n"
            "local TRACE = { on = false, buf = {}, max = 80 }\n"
            "function TRACE.now()\n"
            "\tif type(GetTime) == \"function\" then\n"
            "\t\tlocal ok, t = pcall(GetTime)\n"
            "\t\tif ok and type(t) == \"number\" then return t end\n"
            "\tend\n"
            "\treturn 0\n"
            "end\n"
            "function TRACE.fmt(num)\n"
            "\treturn string.format(\"%.3f\", tonumber(num) or 0)\n"
            "end\n"
            "function TRACE.sec(num)\n"
            "\treturn string.format(\"%.2f\", tonumber(num) or 0)\n"
            "end\n"
            "function TRACE.line(msg, at)\n"
            "\tif not TRACE.on then return end\n"
            "\tlocal line = tostring(msg) .. \" t=\" .. TRACE.fmt(at or TRACE.now())\n"
            "\tTRACE.buf[#TRACE.buf + 1] = line\n"
            "\twhile #TRACE.buf > TRACE.max do table.remove(TRACE.buf, 1) end\n"
            "\t-- Straight to the chat frame: this is a raw trace a tester copies\n"
            "\t-- back, not one of the addon's own messages, so it carries no\n"
            "\t-- \"Touchstone:\" wrapper and no colour on the payload.\n"
            "\tif DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == \"function\" then\n"
            "\t\tpcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME,\n"
            "\t\t\t\"|cff66fcf1toast debug|r \" .. line)\n"
            "\telseif type(print) == \"function\" then\n"
            "\t\tpcall(print, \"toast debug \" .. line)\n"
            "\tend\n"
            "end\n"
            "-- The switch behind /up toastdebug: `on|off|dump`, and a bare call\n"
            "-- toggles. Turning it ON clears the buffer, so the lines a tester reads\n"
            "-- back describe the toast they are about to raise and not an old one.\n"
            "ChestAdvisor.toastDebug = function(mode)\n"
            "\tlocal m = type(mode) == \"string\" and mode:lower() or \"\"\n"
            "\tif m == \"dump\" then\n"
            "\t\tif #TRACE.buf == 0 then\n"
            "\t\t\treturn true, \"no trace lines yet — /up toastdebug on, then /up toasts\"\n"
            "\t\tend\n"
            "\t\treturn true, table.concat(TRACE.buf, \"\\n\")\n"
            "\tend\n"
            "\tif m == \"on\" then\n"
            "\t\tTRACE.on = true\n"
            "\t\tTRACE.buf = {}\n"
            "\telseif m == \"off\" then\n"
            "\t\tTRACE.on = false\n"
            "\telse\n"
            "\t\tTRACE.on = not TRACE.on\n"
            "\t\tif TRACE.on then TRACE.buf = {} end\n"
            "\tend\n"
            "\treturn true, \"toast debug is \" .. (TRACE.on and \"ON\" or \"off\")\n"
            "\t\t.. \" — /up toasts raises one; /up toastdebug dump prints the last \"\n"
            "\t\t.. tostring(TRACE.max) .. \" lines\"\n"
            "end\n"
            "\n"
            "local drawToast, advanceToast, showToastItem, toastFinishShow, toastMeasure\n"
        ),
    )

    # ---- the show start ------------------------------------------------------
    text = replace_once(
        text,
        name,
        "ca.toast-playfadein-trace",
        (
            "local function toastPlayFadeIn(f)\n"
            "\ttoastStopAnimations()\n"
            "\tif type(f.SetAlpha) ~= \"function\" then return end\n"
            "\tpcall(f.SetAlpha, f, 0)\n"
            "\tif type(toastRT.fadeIn) == \"table\" and type(toastRT.fadeIn.Play) == \"function\" then\n"
            "\t\tlocal played = pcall(toastRT.fadeIn.Play, toastRT.fadeIn)\n"
            "\t\tif played then\n"
        ),
        (
            "local function toastPlayFadeIn(f, showId)\n"
            "\ttoastStopAnimations()\n"
            "\tif type(f.SetAlpha) ~= \"function\" then return end\n"
            "\tpcall(f.SetAlpha, f, 0)\n"
            "\tif type(toastRT.fadeIn) == \"table\" and type(toastRT.fadeIn.Play) == \"function\" then\n"
            "\t\tlocal played = pcall(toastRT.fadeIn.Play, toastRT.fadeIn)\n"
            "\t\tif played then\n"
            "\t\t\tTRACE.line(\"fadeIn play id=\" .. tostring(showId))\n"
            "\t\t\t-- t_fe7a636a: `Play` can succeed and the group still never\n"
            "\t\t\t-- start (this client drops a group that was Stopped and Played\n"
            "\t\t\t-- in one frame). The alpha this function set to 0 is then the\n"
            "\t\t\t-- panel's resting alpha, and the restore below is the only\n"
            "\t\t\t-- thing making the show visible — so name that repair, with the\n"
            "\t\t\t-- alpha it rescued, instead of leaving a flash unexplained.\n"
            "\t\t\tlocal running = true\n"
            "\t\t\tif type(toastRT.fadeIn.IsPlaying) == \"function\" then\n"
            "\t\t\t\tlocal okp, playing = pcall(toastRT.fadeIn.IsPlaying, toastRT.fadeIn)\n"
            "\t\t\t\tif okp then running = (playing == true) end\n"
            "\t\t\tend\n"
            "\t\t\tif not running then\n"
            "\t\t\t\ttoastRT.alphaRestored = (toastRT.alphaRestored or 0) + 1\n"
            "\t\t\t\tTRACE.line(\"alpha restore id=\" .. tostring(showId) .. \" was=0.000\")\n"
            "\t\t\tend\n"
        ),
    )

    # ---- the measurement (card t_4bae0617) -----------------------------------
    # The toast's own on-screen time, from the client's clock. The specs and
    # /up diag read it, and it is the number that turned "it is a flash" from a
    # report into a measurement. `shownAt` is stamped by the show; every end
    # path clears it, so nil means "nothing measured yet", never zero.
    text = replace_once(
        text,
        name,
        "ca.toast-measure",
        "local drawToast, advanceToast, showToastItem, toastFinishShow, toastMeasure\n",
        (
            "local drawToast, advanceToast, showToastItem, toastFinishShow, toastMeasure\n"
            "toastMeasure = function()\n"
            "\tif type(toastRT.shownAt) ~= \"number\" or type(GetTime) ~= \"function\" then\n"
            "\t\treturn nil\n"
            "\tend\n"
            "\tlocal ok, now = pcall(GetTime)\n"
            "\tif not ok or type(now) ~= \"number\" then return nil end\n"
            "\treturn math.floor((now - toastRT.shownAt) * 1000 + 0.5)\n"
            "end\n"
        ),
    )

    # ---- the fade-in group reports its own OnFinished (trace only) -----------
    text = replace_once(
        text,
        name,
        "ca.toast-fadein-onfinished-trace",
        (
            "\t\ttoastRT.fadeIn = ag\n"
            "\tend\n"
        ),
        (
            "\t\t-- t_fe7a636a: the fade-IN group reports its own OnFinished to the\n"
            "\t\t-- trace — and CHAINS to whatever the build above installed (the\n"
            "\t\t-- alpha restore this file needs when a finished Alpha animation\n"
            "\t\t-- would otherwise restore the frame's own alpha). Chaining, not\n"
            "\t\t-- replacing: the trace must not undo the upstream fix it explains.\n"
            "\t\tif type(ag.SetScript) == \"function\" then\n"
            "\t\t\tlocal prior = type(ag.GetScript) == \"function\"\n"
            "\t\t\t\tand ag:GetScript(\"OnFinished\") or nil\n"
            "\t\t\tag:SetScript(\"OnFinished\", function()\n"
            "\t\t\t\tTRACE.line(\"animation finished: group=fadeIn id=\"\n"
            "\t\t\t\t\t.. tostring(toastRT.showId)\n"
            "\t\t\t\t\t.. \" fadeFor=\" .. tostring(toastRT.fadeFor))\n"
            "\t\t\t\tif type(prior) == \"function\" then pcall(prior) end\n"
            "\t\t\tend)\n"
            "\t\tend\n"
            "\t\ttoastRT.fadeIn = ag\n"
            "\tend\n"
        ),
    )

    # ---- the fade-out handler traces before it decides -----------------------
    text = replace_once(
        text,
        name,
        "ca.toast-fadeout-onfinished-trace",
        (
            "\t\t\tag:SetScript(\"OnFinished\", function()\n"
            "\t\t\t\tpcall(toastFinishShow, toastRT.fadeId)\n"
            "\t\t\tend)\n"
        ),
        (
            "\t\t\tag:SetScript(\"OnFinished\", function()\n"
            "\t\t\t\tTRACE.line(\"animation finished: group=fadeOut id=\"\n"
            "\t\t\t\t\t.. tostring(toastRT.showId)\n"
            "\t\t\t\t\t.. \" fadeFor=\" .. tostring(toastRT.fadeId))\n"
            "\t\t\t\tpcall(toastFinishShow, toastRT.fadeId, \"fadeOnFinished\")\n"
            "\t\t\tend)\n"
        ),
    )

    # ---- the countdown: deadline, revive, throttled tick ---------------------
    text = replace_once(
        text,
        name,
        "ca.toast-ticker-deadline",
        (
            "\ttoastRT.ticker = C_Timer.NewTicker(TOAST.tick, function()\n"
            "\t\tif not toastActive then return end\n"
            "\t\tif showId ~= nil and toastRT.showId ~= showId then return end\n"
            "\t\tif toastRT.hovered or (toastFrame and toastFrame.dragging) then return end\n"
            "\t\ttoastRT.lifetimeLeft = toastRT.lifetimeLeft - TOAST.tick\n"
            "\t\tif toastRT.lifetimeLeft <= 0 then\n"
            "\t\t\ttoastExpire()\n"
            "\t\tend\n"
            "\tend)\n"
        ),
        (
            "\ttoastRT.ticker = C_Timer.NewTicker(TOAST.tick, function()\n"
            "\t\tif not toastActive then return end\n"
            "\t\tif showId ~= nil and toastRT.showId ~= showId then return end\n"
            "\t\tlocal now = TRACE.now()\n"
            "\t\t-- t_fe7a636a: the panel must be ON SCREEN while this show is live.\n"
            "\t\t-- If anything outside this block took it away (an animation quirk, a\n"
            "\t\t-- client-side hide, a path nobody has found yet) the show would run\n"
            "\t\t-- invisibly — which is exactly what \"a flash, then nothing\" looks\n"
            "\t\t-- like from the outside. Put it back, and say so.\n"
            "\t\tif toastRT.fadeFor == nil and (toastRT.lifetimeLeft or 0) > 0\n"
            "\t\t\tand type(toastFrame) == \"table\" then\n"
            "\t\t\tlocal tf = toastFrame\n"
            "\t\t\tlocal shownNow = true\n"
            "\t\t\tif type(tf.IsShown) == \"function\" then\n"
            "\t\t\t\tlocal okS, s = pcall(tf.IsShown, tf)\n"
            "\t\t\t\tif okS then shownNow = (s ~= false) end\n"
            "\t\t\tend\n"
            "\t\t\tif not shownNow then\n"
            "\t\t\t\tif type(tf.Show) == \"function\" then pcall(tf.Show, tf) end\n"
            "\t\t\t\ttf.shown = true\n"
            "\t\t\t\tif type(tf.SetAlpha) == \"function\" then pcall(tf.SetAlpha, tf, 1) end\n"
            "\t\t\t\ttf.alpha = 1\n"
            "\t\t\t\ttoastRT.revived = (toastRT.revived or 0) + 1\n"
            "\t\t\t\tTRACE.line(\"revive id=\" .. tostring(showId) .. \" left=\"\n"
            "\t\t\t\t\t.. TRACE.sec(toastRT.lifetimeLeft), now)\n"
            "\t\t\tend\n"
            "\t\tend\n"
            "\t\tif toastRT.hovered or (toastFrame and toastFrame.dragging) then return end\n"
            "\t\ttoastRT.lifetimeLeft = toastRT.lifetimeLeft - TOAST.tick\n"
            "\t\t-- The deadline the finish step obeys. Refreshed from the clock on\n"
            "\t\t-- every tick, so the countdown and the finish cannot disagree even\n"
            "\t\t-- when a tick is late (and a hover pause moves it with the pause).\n"
            "\t\ttoastRT.deadline = now + toastRT.lifetimeLeft\n"
            "\t\tif (toastRT.lifetimeLeft or 0) > 0 and TRACE.on then\n"
            "\t\t\tlocal whole = math.floor(toastRT.lifetimeLeft)\n"
            "\t\t\tif toastRT.lastTickPrinted ~= whole then\n"
            "\t\t\t\ttoastRT.lastTickPrinted = whole\n"
            "\t\t\t\tTRACE.line(\"tick id=\" .. tostring(showId) .. \" left=\"\n"
            "\t\t\t\t\t.. TRACE.sec(toastRT.lifetimeLeft), now)\n"
            "\t\t\tend\n"
            "\t\tend\n"
            "\t\tif toastRT.lifetimeLeft <= 0 then\n"
            "\t\t\ttoastExpire(\"timer\")\n"
            "\t\tend\n"
            "\tend)\n"
        ),
    )

    # ---- the finish: the deadline is the authority ---------------------------
    text = replace_once(
        text,
        name,
        "ca.toast-finish-deadline",
        (
            "toastFinishShow = function(showId)\n"
            "\tif showId ~= nil and toastRT.showId ~= showId then return end\n"
            "\tif not toastActive then return end\n"
            "\ttoastRT.showId = (toastRT.showId or 0) + 1\n"
        ),
        (
            "toastFinishShow = function(showId, reason)\n"
            "\tif showId ~= nil and toastRT.showId ~= showId then return end\n"
            "\tif not toastActive then return end\n"
            "\t-- t_fe7a636a: the configured lifetime is the authority. Only a\n"
            "\t-- right-click dismiss may end a show early; every callback-driven end\n"
            "\t-- (the fade-out's OnFinished, its fallback timer, a scan repair) waits\n"
            "\t-- for the deadline the countdown published. A client that reports\n"
            "\t-- OnFinished early — or delivers a stale Stop() after the fade-out was\n"
            "\t-- armed — therefore cannot eat a live toast, and the trace names the\n"
            "\t-- attempt instead of hiding it.\n"
            "\tlocal now = TRACE.now()\n"
            "\treason = reason or \"other\"\n"
            "\tif reason ~= \"dismiss\" and type(toastRT.deadline) == \"number\"\n"
            "\t\tand now + 0.001 < toastRT.deadline then\n"
            "\t\tTRACE.line(\"finish refused: id=\" .. tostring(showId)\n"
            "\t\t\t.. \" reason=\" .. reason .. \" left=\"\n"
            "\t\t\t.. TRACE.sec(toastRT.deadline - now), now)\n"
            "\t\treturn\n"
            "\tend\n"
            "\tlocal lifeLeft = tonumber(toastRT.lifetimeLeft) or 0\n"
            "\tif lifeLeft < 0 then lifeLeft = 0 end\n"
            "\tTRACE.line(\"finish id=\" .. tostring(showId) .. \" reason=\" .. reason\n"
            "\t\t.. \" lifeLeft=\" .. TRACE.sec(lifeLeft), now)\n"
            "\t-- t_4bae0617: the measurement this end just made, kept for /up diag\n"
            "\t-- and the specs. `shownAt` is cleared so a later read cannot measure\n"
            "\t-- a show that is already gone.\n"
            "\tlocal ms = toastMeasure()\n"
            "\tif ms then toastRT.showMs = ms end\n"
            "\ttoastRT.shownAt = nil\n"
            "\ttoastRT.fadeFor = nil\n"
            "\ttoastRT.deadline = nil\n"
            "\ttoastRT.fadeArmedAt = nil\n"
            "\ttoastRT.lastTickPrinted = nil\n"
            "\ttoastRT.showId = (toastRT.showId or 0) + 1\n"
        ),
    )

    # ---- the expiry: trace it, stamp the arm, name the reasons ---------------
    text = replace_once(
        text,
        name,
        "ca.toast-expire-reason",
        (
            "toastExpire = function()\n"
            "\ttoastStopTimer()\n"
            "\tif not toastActive then return end\n"
            "\tlocal showId = toastRT.showId\n"
        ),
        (
            "toastExpire = function(reason)\n"
            "\ttoastStopTimer()\n"
            "\tif not toastActive then return end\n"
            "\tlocal showId = toastRT.showId\n"
            "\ttoastRT.lastEnd = \"expired\"\n"
            "\tTRACE.line(\"expire id=\" .. tostring(showId) .. \" reason=\"\n"
            "\t\t.. tostring(reason or \"timer\"))\n"
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.toast-expire-arm-trace",
        (
            "\ttoastRT.fadeId = showId\n"
        ),
        (
            "\ttoastRT.fadeId = showId\n"
            "\t-- t_fe7a636a: the fade-out is now in flight for THIS show. The\n"
            "\t-- guard is the fold's own marker (upstream's fadeId names the show\n"
            "\t-- the group was armed for, not whether a fade is still running), and\n"
            "\t-- toastFinishShow clears it, so a scan can tell \"a show whose\n"
            "\t-- lifetime is spent but whose fade is still playing\" from a dead one.\n"
            "\ttoastRT.fadeFor = showId\n"
            "\ttoastRT.fadeArmedAt = TRACE.now()\n"
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.toast-expire-timer-reason",
        (
            "\t\t\tC_Timer.After(delay, function()\n"
            "\t\t\t\tpcall(toastFinishShow, showId)\n"
            "\t\t\tend)\n"
            "\t\t\treturn\n"
            "\t\tend\n"
            "\tend\n"
            "\tpcall(toastFinishShow, showId)\n"
            "end\n"
        ),
        (
            "\t\t\tC_Timer.After(delay, function()\n"
            "\t\t\t\tpcall(toastFinishShow, showId, \"fadeTimer\")\n"
            "\t\t\tend)\n"
            "\t\t\treturn\n"
            "\t\tend\n"
            "\tend\n"
            "\tpcall(toastFinishShow, showId, \"fadeTimer\")\n"
            "end\n"
        ),
    )

    # ---- the show: trace, deadline, and the alpha safety net ----------------
    text = replace_once(
        text,
        name,
        "ca.toast-show-trace",
        (
            "showToastItem = function(item)\n"
            "\ttoastRT.showId = (toastRT.showId or 0) + 1\n"
            "\tlocal showId = toastRT.showId\n"
            "\tlocal f = ensureToast()\n"
        ),
        (
            "showToastItem = function(item)\n"
            "\ttoastRT.showId = (toastRT.showId or 0) + 1\n"
            "\tlocal showId = toastRT.showId\n"
            "\tTRACE.line(\"show id=\" .. tostring(showId))\n"
            "\tlocal f = ensureToast()\n"
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.toast-show-deadline",
        (
            "\t\ttoastRT.lifetimeLeft = toastLifetime()\n"
            "\t\t-- Re-anchor from the persisted position on every show: the panel may have\n"
        ),
        (
            "\t\ttoastRT.lifetimeLeft = toastLifetime()\n"
            "\t\t-- t_4bae0617: the show's own clock stamp. The measured on-screen\n"
            "\t\t-- time is then the client's number, not the addon's opinion.\n"
            "\t\ttoastRT.shownAt = TRACE.now()\n"
            "\t\t-- t_fe7a636a: the deadline this show must survive to, on the same\n"
            "\t\t-- clock the countdown ticks on. The finish step refuses to end a\n"
            "\t\t-- show before it.\n"
            "\t\ttoastRT.deadline = toastRT.shownAt + toastRT.lifetimeLeft\n"
            "\t\ttoastRT.fadeArmedAt = nil\n"
            "\t\ttoastRT.fadeFor = nil\n"
            "\t\ttoastRT.lastTickPrinted = nil\n"
            "\t\t-- Re-anchor from the persisted position on every show: the panel may have\n"
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.toast-shown-trace-alpha-net",
        (
            "\t\tf:Show()\n"
            "\t\ttoastActive = true\n"
            "\t\ttoastFired = toastFired + 1\n"
            "\t\ttoastPlayFadeIn(f)\n"
            "\t\ttoastStartTimer(showId)\n"
        ),
        (
            "\t\tf:Show()\n"
            "\t\ttoastActive = true\n"
            "\t\ttoastFired = toastFired + 1\n"
            "\t\tlocal alphaAtShow = 1\n"
            "\t\tif type(f.GetAlpha) == \"function\" then\n"
            "\t\t\tlocal okA, av = pcall(f.GetAlpha, f)\n"
            "\t\t\tif okA and type(av) == \"number\" then alphaAtShow = av end\n"
            "\t\tend\n"
            "\t\tTRACE.line(\"shown id=\" .. tostring(showId) .. \" alpha=\"\n"
            "\t\t\t.. TRACE.sec(alphaAtShow))\n"
            "\t\ttoastPlayFadeIn(f, showId)\n"
            "\t\ttoastStartTimer(showId)\n"
            "\t\t-- t_fe7a636a: the fade-in must not be the only thing that makes the\n"
            "\t\t-- panel visible. The alpha was just set to 0 and this client can drop\n"
            "\t\t-- a group that was Stopped and Played in one frame (the behaviour the\n"
            "\t\t-- fade-out's guard already exists for); the toast would then be an\n"
            "\t\t-- invisible show whose only visible frame is the one before the set.\n"
            "\t\t-- One timer puts the alpha back if the animation did not.\n"
            "\t\tif type(C_Timer) == \"table\" and type(C_Timer.After) == \"function\" then\n"
            "\t\t\tC_Timer.After((TOAST.fadeIn or 0.18) + 0.05, function()\n"
            "\t\t\t\tif not toastActive or toastRT.showId ~= showId then return end\n"
            "\t\t\t\tif toastRT.fadeFor ~= nil then return end\n"
            "\t\t\t\tlocal tf = toastFrame\n"
            "\t\t\t\tif type(tf) ~= \"table\" or type(tf.SetAlpha) ~= \"function\" then return end\n"
            "\t\t\t\tlocal cur = 1\n"
            "\t\t\t\tif type(tf.GetAlpha) == \"function\" then\n"
            "\t\t\t\t\tlocal okA, av = pcall(tf.GetAlpha, tf)\n"
            "\t\t\t\t\tif okA and type(av) == \"number\" then cur = av end\n"
            "\t\t\t\tend\n"
            "\t\t\t\tif cur < 0.98 then\n"
            "\t\t\t\t\tpcall(tf.SetAlpha, tf, 1)\n"
            "\t\t\t\t\ttf.alpha = 1\n"
            "\t\t\t\t\ttoastRT.alphaRestored = (toastRT.alphaRestored or 0) + 1\n"
            "\t\t\t\t\tTRACE.line(\"alpha restore id=\" .. tostring(showId)\n"
            "\t\t\t\t\t\t.. \" was=\" .. TRACE.sec(cur))\n"
            "\t\t\t\tend\n"
            "\t\t\tend)\n"
            "\t\tend\n"
        ),
    )

    # ---- the dismiss: traced with the same vocabulary ------------------------
    text = replace_once(
        text,
        name,
        "ca.toast-dismiss-trace",
        (
            "\t\t\t\tif type(self.Hide) == \"function\" then pcall(self.Hide, self) end\n"
            "\t\t\t\tself.shown = false\n"
            "\t\t\t\ttoastActive = false\n"
            "\t\t\t\ttoastRT.current = nil\n"
            "\t\t\t\ttoastRT.hovered = false\n"
            "\t\t\t\ttoastRT.lifetimeLeft = 0\n"
        ),
        (
            "\t\t\t\tif type(self.Hide) == \"function\" then pcall(self.Hide, self) end\n"
            "\t\t\t\tself.shown = false\n"
            "\t\t\t\ttoastActive = false\n"
            "\t\t\t\ttoastRT.current = nil\n"
            "\t\t\t\ttoastRT.hovered = false\n"
            "\t\t\t\ttoastRT.lifetimeLeft = 0\n"
            "\t\t\t\t-- t_4bae0617: the measured time this show was up, and the word\n"
            "\t\t\t\t-- for how it ended, taken BEFORE the clock stamp is cleared.\n"
            "\t\t\t\tlocal dismissedMs = toastMeasure and toastMeasure() or nil\n"
            "\t\t\t\tif dismissedMs then toastRT.showMs = dismissedMs end\n"
            "\t\t\t\ttoastRT.shownAt = nil\n"
            "\t\t\t\ttoastRT.lastEnd = \"dismissed\"\n"
            "\t\t\t\t-- t_fe7a636a: a dismiss is the one end that may come before the\n"
            "\t\t\t\t-- deadline (the player asked for it). It is traced as both an\n"
            "\t\t\t\t-- expire and a finish so every end reads in the same vocabulary.\n"
            "\t\t\t\tTRACE.line(\"expire id=\" .. tostring(toastRT.showId) .. \" reason=dismiss\")\n"
            "\t\t\t\tTRACE.line(\"finish id=\" .. tostring(toastRT.showId)\n"
            "\t\t\t\t\t.. \" reason=dismiss lifeLeft=\" .. TRACE.sec(0))\n"
            "\t\t\t\ttoastRT.deadline = nil\n"
            "\t\t\t\ttoastRT.fadeArmedAt = nil\n"
            "\t\t\t\ttoastRT.fadeFor = nil\n"
        ),
    )

    # ---- a scan may repair a stuck show, never cut a live one ---------------
    text = replace_once(
        text,
        name,
        "ca.toast-rescan-guard",
        (
            "\t-- A toast whose lifetime already elapsed must not stay up. OnFinished is\n"
            "\t-- supposed to hide it; if that step never ran, toastActive would block\n"
            "\t-- every later upgrade behind a faded panel.\n"
            "\tif toastActive and (toastRT.lifetimeLeft or 0) <= 0 then\n"
            "\t\tpcall(toastFinishShow, toastRT.showId)\n"
            "\tend\n"
        ),
        (
            "\t-- A toast whose lifetime already elapsed must not stay up. OnFinished is\n"
            "\t-- supposed to hide it; if that step never ran, toastActive would block\n"
            "\t-- every later upgrade behind a faded panel.\n"
            "\t--\n"
            "\t-- t_fe7a636a: but a scan must NEVER cut a live toast short. The old test\n"
            "\t-- (`lifetimeLeft <= 0`) is true for the whole fade-out window, so a scan\n"
            "\t-- landing there finished the show on the spot and cut the fade — and this\n"
            "\t-- is the path the card asked about, so it is traced. Only a show that is\n"
            "\t-- past its deadline AND has no fade-out in flight is repaired here; the\n"
            "\t-- fade's own OnFinished/fallback timer owns the normal end.\n"
            "\tif toastActive and toastRT.fadeFor == nil\n"
            "\t\tand (toastRT.lifetimeLeft or 0) <= -TOAST.tick then\n"
            "\t\tTRACE.line(\"expire id=\" .. tostring(toastRT.showId) .. \" reason=rescan\")\n"
            "\t\tpcall(toastFinishShow, toastRT.showId, \"rescan\")\n"
            "\tend\n"
        ),
    )

    # ---- what /up diag reads ------------------------------------------------
    text = replace_once(
        text,
        name,
        "ca.toast-state-trace",
        (
            "\t\tlifetime = toastLifetime(),\n"
            "\t\theld = #toastRT.held,\n"
            "\t\tdeferred = toastRT.deferred,\n"
            "\t}\n"
        ),
        (
            "\t\tlifetime = toastLifetime(),\n"
            "\t\theld = #toastRT.held,\n"
            "\t\tdeferred = toastRT.deferred,\n"
            "\t\t-- t_4bae0617: the measurement, read by /up diag and the specs.\n"
            "\t\t-- showMs is nil until a show has ended; lastEnd is the word for\n"
            "\t\t-- how that end happened (\"expired\" / \"dismissed\").\n"
            "\t\tshowMs = toastRT.showMs,\n"
            "\t\tlastEnd = toastRT.lastEnd,\n"
            "\t\t-- t_fe7a636a: the trace switch and the repairs the fix performed.\n"
            "\t\t-- Read by /up diag only; nothing on the panel ever shows them.\n"
            "\t\tdebug = TRACE.on,\n"
            "\t\tdeadlineLeft = (toastActive and type(toastRT.deadline) == \"number\")\n"
            "\t\t\tand math.max(0, toastRT.deadline - TRACE.now()) or nil,\n"
            "\t\trevived = toastRT.revived or 0,\n"
            "\t\talphaRestored = toastRT.alphaRestored or 0,\n"
            "\t}\n"
        ),
    )

    # ---- /up toastdebug, its help line, and the /up diag block --------------
    text = replace_once(
        text,
        name,
        "ca.toastdebug-command",
        (
            "-- /up tooltip <on|off> — the sibling of /up toast, on the SAME per-character\n"
        ),
        (
            "-- /up toastdebug [on|off|dump] — t_fe7a636a: the toast's transition trace.\n"
            "-- Off by default. Every line is the client's own GetTime at three decimals,\n"
            "-- and `dump` prints the last lines back because a toast is on screen for\n"
            "-- seconds: the point is to read the trace AFTER it is gone.\n"
            "local function cmdToastDebug(msg)\n"
            "\tlocal word = (msg:match(\"^toastdebug%s+(%a+)%s*$\") or \"\"):lower()\n"
            "\tif type(ChestAdvisor.toastDebug) ~= \"function\" then\n"
            "\t\treturn false, \"the toast surface is not loaded (is the Touchstone module off?)\"\n"
            "\tend\n"
            "\tif word == \"\" then word = nil end\n"
            "\tlocal ok, out = ChestAdvisor.toastDebug(word)\n"
            "\treturn ok ~= false, out\n"
            "end\n"
            "\n"
            "-- /up tooltip <on|off> — the sibling of /up toast, on the SAME per-character\n"
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.toastdebug-dispatch",
        (
            "\telseif subword == \"toast\" then\n"
            "\t\tok, out = cmdToast(trimmed)\n"
        ),
        (
            "\telseif subword == \"toast\" then\n"
            "\t\tok, out = cmdToast(trimmed)\n"
            "\telseif subword == \"toasts\" or subword == \"testtoast\" then\n"
            "\t\tok, out = cmdTestToast()\n"
            "\telseif subword == \"toastdebug\" then\n"
            "\t\tok, out = cmdToastDebug(trimmed)\n"
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.toastdebug-help",
        (
            "\t\t.. \"  /up tooltip <on|off>  turn the item-tooltip verdict line on or off (persisted; default on)\\n\"\n"
        ),
        (
            "\t\t.. \"  /up toastdebug [on|off|dump]  print every transition of one toast with GetTime stamps\\n\"\n"
            "\t\t.. \"                 (off by default; /up toasts raises one, dump prints the last lines)\\n\"\n"
            "\t\t.. \"  /up tooltip <on|off>  turn the item-tooltip verdict line on or off (persisted; default on)\\n\"\n"
        ),
    )
    # ---- /up diag: the toast block is UNCONDITIONAL --------------------------
    # Upstream nests the toast's diag block inside the walk-ledger branch, so a
    # tester who runs /up toasts on a fresh login (no scan ledger yet) gets no
    # toast line at all — and the toast's lifetime is exactly what is measurable
    # with no scan behind it (card t_4bae0617). The block is lifted out of that
    # branch and installed above it, one indentation level shallower, carrying
    # the measurement and the card t_fe7a636a trace fields.
    text = replace_once(
        text,
        name,
        "ca.diag-toast-unconditional",
        "\t\tlocal ts = ChestAdvisor.toastState and ChestAdvisor.toastState() or nil\n\t\tif type(ts) == \"table\" then\n\t\t\tsummary = summary .. \"\\n--- toast ---\"\n\t\t\t\t\t.. \"\\nenabled: \" .. tostring(ts.enabled)\n\t\t\t\t\t.. \" | shown: \" .. tostring(ts.shown)\n\t\t\t\t\t.. \" | queued: \" .. tostring(ts.queue)\n\t\t\t\t\t.. \" | told this session: \" .. tostring(ts.told)\n\t\t\t\t\t.. \" | cap-dropped: \" .. tostring(ts.dropped)\n\t\t\t\t\t-- t_cf2ad83c (U3): the behaviour this card added, so a human\n\t\t\t\t\t-- asking for diagnostics can see the hold and the hover pause.\n\t\t\t\t\t.. \"\\nhovered: \" .. tostring(ts.hovered)\n\t\t\t\t\t.. \" | lifetime left: \" .. tostring(ts.lifetimeLeft)\n\t\t\t\t\t.. \" | held for combat: \" .. tostring(ts.held)\n\t\t\t\t\t.. \" | deferred: \" .. tostring(ts.deferred)\n\t\tend\n",
        "",
    )
    text = replace_once(
        text,
        name,
        "ca.diag-toast-unconditional-move",
        (
            "\tif type(d.ledger) == \"table\" then\n"
            "\t\tlocal ld = d.ledger\n"
        ),
        "\tlocal ts = ChestAdvisor.toastState and ChestAdvisor.toastState() or nil\n\tif type(ts) == \"table\" then\n\t\tlocal measured = \"not shown yet\"\n\t\tif type(ts.showMs) == \"number\" then\n\t\t\tmeasured = string.format(\"%.2fs\", ts.showMs / 1000)\n\t\t\t\t.. \" (\" .. tostring(ts.lastEnd or \"?\") .. \")\"\n\t\tend\n\t\tsummary = summary .. \"\\n--- toast ---\"\n\t\t\t\t.. \"\\nenabled: \" .. tostring(ts.enabled)\n\t\t\t\t.. \" | shown: \" .. tostring(ts.shown)\n\t\t\t\t.. \" | fired: \" .. tostring(ts.fired)\n\t\t\t\t.. \" | queued: \" .. tostring(ts.queue)\n\t\t\t\t.. \" | told this session: \" .. tostring(ts.told)\n\t\t\t\t.. \" | cap-dropped: \" .. tostring(ts.dropped)\n\t\t\t\t.. \"\\nhovered: \" .. tostring(ts.hovered)\n\t\t\t\t.. \" | lifetime left: \" .. tostring(ts.lifetimeLeft)\n\t\t\t\t.. \" | held for combat: \" .. tostring(ts.held)\n\t\t\t\t.. \" | deferred: \" .. tostring(ts.deferred)\n\t\t\t\t.. \"\\nconfigured lifetime: \"\n\t\t\t\t.. string.format(\"%.2fs\", tonumber(ts.lifetime) or 0)\n\t\t\t\t.. \" | last show on screen: \" .. measured\n\t\t\t\t-- t_fe7a636a: the trace switch and the repairs, so a flash\n\t\t\t\t-- report comes with the numbers that explain it.\n\t\t\t\t.. \" | trace: \" .. (ts.debug and \"ON\" or \"off\")\n\t\t\t\t.. \"\\nrevived this session: \" .. tostring(ts.revived)\n\t\t\t\t.. \" | alpha restored: \" .. tostring(ts.alphaRestored)\n\t\t\t\t.. \" | deadline left: \"\n\t\t\t\t.. (tonumber(ts.deadlineLeft)\n\t\t\t\t\tand string.format(\"%.2fs\", ts.deadlineLeft) or \"-\")\n\t\tend\n"
        + (
            "\tif type(d.ledger) == \"table\" then\n"
            "\t\tlocal ld = d.ledger\n"
        ),
    )

    # ---- what /up diag reads ------------------------------------------------
    text = replace_once(
        text,
        name,
        "ca.toast-advance-reason",
        (
            "advanceToast = function()\n"
            "\tif toastActive then\n"
            "\t\ttoastExpire()\n"
            "\t\treturn\n"
            "\tend\n"
        ),
        (
            "advanceToast = function()\n"
            "\tif toastActive then\n"
            "\t\t-- t_fe7a636a: not the countdown and not a scan — `other` is the\n"
            "\t\t-- honest word for this path in the trace vocabulary.\n"
            "\t\ttoastExpire(\"other\")\n"
            "\t\treturn\n"
            "\tend\n"
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.toast-disabled-expire-trace",
        (
            "\tif not toastIsEnabled() then\n"
            "\t\ttoastQueue = {}\n"
            "\t\tif toastFrame then toastFrame:Hide() end\n"
            "\t\ttoastActive = false\n"
            "\t\treturn\n"
            "\tend\n"
        ),
        (
            "\tif not toastIsEnabled() then\n"
            "\t\ttoastQueue = {}\n"
            "\t\t-- t_fe7a636a: this path takes a live toast off screen because the\n"
            "\t\t-- SETTING says off. It is traced, because a bad SavedVariables value\n"
            "\t\t-- would look exactly like a flash from the outside.\n"
            "\t\tif toastActive then\n"
            "\t\t\tTRACE.line(\"expire id=\" .. tostring(toastRT.showId) .. \" reason=other\")\n"
            "\t\tend\n"
            "\t\tif toastFrame then toastFrame:Hide() end\n"
            "\t\ttoastActive = false\n"
            "\t\treturn\n"
            "\tend\n"
        ),
    )

    # ---- Card t_3a744b4a: the weighted verdict reaches the player -------------
    # The comparator now decides from the profile's weights and returns the number
    # (and the profile's name) as a third value. These edits carry it to the two
    # places rows are built and teach the tooltip renderer to print it:
    #
    #   * buildSpec names the CLIENT's role word, so the weight table can pick the
    #     active profile (a Protection paladin is TANK, not the conservative
    #     "spell" proxy the stat ORDER uses);
    #   * both row builders store `weighted` / `profile` on the row;
    #   * TOOLTIP_UI.weighted renders "Downgrade — weighted -16 vs <worn> [Profile]"
    #     with the delta list (which still carries every stat, zero-weight ones
    #     included) as the supporting detail line.
    name = "ChestAdvisor/ChestAdvisor.lua"
    # Card t_3a744b4a's spec edits are gone: upstream #89/#90 (t_984bc8ac) reads
    # the client identity ONCE in buildSpec and publishes `clientRole` on the spec
    # table itself, which is exactly what the weighted layer needs. Re-stitching
    # `local specIdentity = readSpecIdentity()` here would be a second read of the
    # same client call, in the same function, for a field upstream already fills.
    text = replace_once(
        text,
        name,
        "ca.tooltip-weighted-words",
        '\t\tUNKNOWN     = "Can\'t judge",\n',
        (
            '\t\tUNKNOWN     = "Can\'t judge",\n'
            "\t\t-- Card t_3a744b4a: two DISPLAY words, not two new tokens. A weighted\n"
            "\t\t-- row is still NOT_UPGRADE; which of these the player sees comes from\n"
            "\t\t-- the sign of the weighted total. They live in this closed table so the\n"
            "\t\t-- duplicate guard (tooltipHasOurLine) recognises them as our own line.\n"
            '\t\tDOWNGRADE   = "Downgrade",\n'
            '\t\tNO_CHANGE   = "No change",\n'
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.tooltip-weighted",
        "-- One verdict, as the tooltip renders it: a coloured HEADLINE (the verdict in\n",
        _tabify(
            """-- The weighted line (card t_3a744b4a). One rule: a row that carries a
-- weighted total renders ITS number and ITS profile, so the verdict can be
-- checked against the arithmetic beside it:
--
--     Downgrade — weighted -16 vs Lambent Scale Cloak [Retribution]
--     -4 Str, +3 Sta, -3 Armor, -2 Spi
--
-- The word comes from the sign of the total (NOT_UPGRADE stays the token; a loss
-- is a "Downgrade" and a weighted zero is "No change"); the profile is quoted so
-- a wrong one is visible instead of silent. The detail line is the same
-- statDeltas arithmetic every other branch prints, and it lists EVERY differing
-- stat — a zero-weight stat like Stamina is supporting detail here, never the
-- reason for the verdict above it.
--
-- Returns nil for a row with no weighted total (a weapon row, a legacy persisted
-- row, an UNKNOWN), so every existing line renders byte-identically.
function TOOLTIP_UI.weighted(row, order)
  if type(row) ~= "table" or type(row.weighted) ~= "number" then return nil end
  local total = row.weighted
  local number = (Verdict and type(Verdict.numText) == "function")
    and Verdict.numText(total) or tostring(total)
  local head = "weighted " .. number
  if type(row.wornLink) == "string" then
    head = head .. " vs " .. itemNameOf(row.wornLink)
  end
  if type(row.profile) == "string" then
    head = head .. " [" .. row.profile .. "]"
  end
  local word = TOOLTIP_UI.word(row.verdict)
  if row.verdict == "NOT_UPGRADE" then
    if total < 0 then word = TOOLTIP_UI.words.DOWNGRADE
    else word = TOOLTIP_UI.words.NO_CHANGE end
  end
  local detail = nil
  if type(row.chestWornLines) == "table" and #row.chestWornLines > 0
    and Verdict and type(Verdict.statTable) == "function"
    and type(Verdict.statDeltas) == "function"
    and type(Verdict.deltaText) == "function" then
    local api = apiBySideOf(row.id, type(row.wornLink) == "string"
      and itemIDOf(row.wornLink) or nil)
    local cand = Verdict.statTable(row.lines, "candidate", api and api.candidate or nil)
    local eq = Verdict.statTable(row.chestWornLines, "worn", api and api.worn or nil)
    -- The row's own stat order when this caller did not pass one: the bag walk
    -- stores the character's class and role word, so the arithmetic reads in the
    -- order the player's profile ranks — "-4 Str, +3 Sta, -3 Armor, -2 Spi" —
    -- instead of alphabetically. classRoleOrder is the one resolver; there is no
    -- second copy of the order here.
    local deltaOrder = order
    if deltaOrder == nil and type(row.class) == "string"
      and Verdict and type(Verdict.classRoleOrder) == "function" then
      deltaOrder = Verdict.classRoleOrder(row.class, row.role)
    end
    local dtext = Verdict.deltaText(Verdict.statDeltas(cand, eq, deltaOrder), TOOLTIP_DELTA_MAX)
    if dtext ~= "" then detail = dtext end
  end
  return { word = word, head = head, detail = detail }
end

-- One verdict, as the tooltip renders it: a coloured HEADLINE (the verdict in
"""
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.tooltip-weighted-branch",
        '\tlocal out = {}\n\tif row.verdict == "UPGRADE" then\n',
        _tabify(
            """  local out = {}
  local weighted = TOOLTIP_UI.weighted(row, order)
  if weighted ~= nil then
    local esc = TOOLTIP_GREY
    local colour = "grey"
    if row.verdict == "UPGRADE" then
      esc, colour = TOOLTIP_GREEN, "green"
    elseif row.verdict == TRADE_OFF_VERDICT then
      esc, colour = TOOLTIP_AMBER, "amber"
    end
    out[#out + 1] = {
      text = esc .. TOOLTIP_PREFIX .. weighted.word .. " — " .. weighted.head,
      colour = colour,
    }
    if weighted.detail and showDetail then
      out[#out + 1] = { text = TOOLTIP_GREY .. weighted.detail, colour = "grey" }
    end
  elseif row.verdict == "UPGRADE" then
"""
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.quest-row-weighted",
        "\tlocal function done(v, reason)\n\t\trow.verdict = v\n\t\trow.reason = reason\n\t\treturn v, reason, row",
        (
            "\tlocal function done(v, reason, weighted)\n"
            "\t\trow.verdict = v\n"
            "\t\trow.reason = reason\n"
            "\t\t-- Card t_3a744b4a: the number and the profile the verdict came from,\n"
            "\t\t-- so the reward-panel tooltip can quote both. nil when the outcome did\n"
            "\t\t-- not come from the weights (a decline, an unresolved profile).\n"
            "\t\tif type(weighted) == \"table\" then\n"
            "\t\t\trow.weighted = weighted.total\n"
            "\t\t\trow.profile = weighted.profile\n"
            "\t\tend\n"
            "\t\treturn v, reason, row"
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.quest-evaluate-weighted",
        (
            "\tlocal v, reason = Verdict.evaluate(\n"
            "\t\t{ canUse = canUseV, line = lines },\n"
            "\t\t{ line = wornLines },\n"
            "\t\tspec,\n"
            "\t\tapi,\n"
            "\t\tslotWord(invSlot)\n"
            "\t)\n"
        ),
        (
            "\tlocal v, reason, weighted = Verdict.evaluate(\n"
            "\t\t{ canUse = canUseV, line = lines },\n"
            "\t\t{ line = wornLines },\n"
            "\t\tspec,\n"
            "\t\tapi,\n"
            "\t\tslotWord(invSlot)\n"
            "\t)\n"
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.quest-done-weighted",
        "\treturn done(v, reason)\nend\n\n-- Clear every quest marker",
        "\treturn done(v, reason, weighted)\nend\n\n-- Clear every quest marker",
    )
    text = replace_once(
        text,
        name,
        "ca.bag-evaluate-weighted",
        "\t\t\t\t\t\tlocal v2, r2 = Verdict.evaluate(",
        "\t\t\t\t\t\tlocal v2, r2, w2 = Verdict.evaluate(",
    )
    text = replace_once(
        text,
        name,
        "ca.bag-row-weighted",
        (
            "verdicts[link] = {\n"
            "\t\t\t\t\t\t\tbag = bag, slot = slot, id = id,\n"
            "\t\t\t\t\t\t\tverdict = v,\n"
            "\t\t\t\t\t\t\treason = reason,\n"
            "\t\t\t\t\t\t\trole = roleLabel,"
        ),
        (
            "verdicts[link] = {\n"
            "\t\t\t\t\t\t\tbag = bag, slot = slot, id = id,\n"
            "\t\t\t\t\t\t\tverdict = v,\n"
            "\t\t\t\t\t\t\treason = reason,\n"
            "\t\t\t\t\t\t\trole = roleLabel,\n"
            "\t\t\t\t\t\t\t-- Card t_3a744b4a: the weighted total this row was decided on\n"
            "\t\t\t\t\t\t\t-- and the profile that supplied the weights. Two scalars, so a\n"
            "\t\t\t\t\t\t\t-- persisted diag row stays small; nil on every outcome that did\n"
            "\t\t\t\t\t\t\t-- not come from the weights (a weapon row, a decline).\n"
            "\t\t\t\t\t\t\tweighted = w2 and w2.total or nil,\n"
            "\t\t\t\t\t\t\tprofile = w2 and w2.profile or nil,"
        ),
    )

    text = edit_chestadvisor_tiebreak(text)
    text = edit_chestadvisor_weighted_local(text)

    # ---- the test toast, and the timing the module ships (card t_4bae0617) ----
    # These two features have no home in StatForge: they were added to the local
    # deploy copy the fold used to vendor from, so moving the source to StatForge
    # main means the fold has to carry them itself. Nothing here is invented —
    # it is the shipped behaviour from the deploy, re-anchored onto the new toast.
    text = replace_once(
        text,
        name,
        "ca.testtoast-command",
        (
            "ChestAdvisor._maybeToastUpgrades = maybeToastUpgrades\n"
        ),
        (
            "-- ---- t_4bae0617: the deterministic test toast ---------------------------\n"
            "--\n"
            "-- An upgrade toast otherwise needs a real bag item the scan happens to judge\n"
            "-- an UPGRADE, which can take an hour of play — so nothing about its lifetime,\n"
            "-- fade or dismiss behaviour could be checked on demand. `/up toasts` raises\n"
            "-- one through the REAL path: the entry is queued exactly where a scan queues\n"
            "-- one and drawn by showToastItem (no second renderer, no second queue), and\n"
            "-- the message is built by buildToastMessage like any other show.\n"
            "--\n"
            "-- The synthetic entry carries NO link and NO item id, which is the point: the\n"
            "-- icon falls back cleanly through the same `tex or TOAST_FALLBACK_ICON` the\n"
            "-- real path uses, and buildToastMessage takes its documented fallback\n"
            "-- wording. It touches NOTHING the scan owns — no toastedLinks (so the dedupe\n"
            "-- set is not polluted), no ChestAdvisorDB.log (written only by a verdict), and\n"
            "-- no baseline flag (toastSeenFirstScan is only ever set by\n"
            "-- maybeToastUpgrades).\n"
            "--\n"
            "-- Returns { started, queued, dropped }: the first call draws immediately, the\n"
            "-- second while one is up JOINS THE QUEUE (a rotation, never a second panel),\n"
            "-- and the tail past TOAST_MAX is a stated drop like the scan's own.\n"
            "local TOAST_TEST_NAME = \"Test Upgrade\"\n"
            "ChestAdvisor.testToast = function(n)\n"
            "\tn = tonumber(n) or 1\n"
            "\tif n < 1 then n = 1 end\n"
            "\tlocal started, queued, dropped = 0, 0, 0\n"
            "\tfor _ = 1, math.floor(n) do\n"
            "\t\tlocal entry = { name = TOAST_TEST_NAME, test = true }\n"
            "\t\t-- The cap is the same one a scan batch obeys, so a tester cannot use\n"
            "\t\t-- this to grow a queue the real path could never grow.\n"
            "\t\tif #toastQueue >= TOAST_MAX then\n"
            "\t\t\ttoastDropped = toastDropped + 1\n"
            "\t\t\tdropped = dropped + 1\n"
            "\t\telse\n"
            "\t\t\ttoastQueue[#toastQueue + 1] = entry\n"
            "\t\t\tqueued = queued + 1\n"
            "\t\t\tif not toastActive then\n"
            "\t\t\t\tshowToastItem(table.remove(toastQueue, 1))\n"
            "\t\t\t\tqueued = queued - 1\n"
            "\t\t\t\tstarted = started + 1\n"
            "\t\t\tend\n"
            "\t\tend\n"
            "\tend\n"
            "\treturn { started = started, queued = queued, dropped = dropped }\n"
            "end\n"
            "ChestAdvisor._maybeToastUpgrades = maybeToastUpgrades\n"
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.testtoast-command-slash",
        (
            "\treturn true, \"toast \" .. w\n"
            "end\n"
        ),
        (
            "\treturn true, \"toast \" .. w\n"
            "end\n"
            "\n"
            "-- /up toasts (alias /up testtoast) — t_4bae0617: raise the upgrade toast on\n"
            "-- demand, so its lifetime, fade and dismiss can be checked without waiting\n"
            "-- for a real upgrade to drop. It goes through ChestAdvisor.testToast, which\n"
            "-- queues and shows through the REAL path.\n"
            "local function cmdTestToast()\n"
            "\tif type(ChestAdvisor.testToast) ~= \"function\" then\n"
            "\t\treturn false, \"the toast surface is not loaded (is the Touchstone module off?)\"\n"
            "\tend\n"
            "\tif not toastIsEnabled() then\n"
            "\t\treturn false, \"the toast is off — /up toast on, then /up toasts\"\n"
            "\tend\n"
            "\tChestAdvisor.testToast(1)\n"
            "\tlocal st = type(ChestAdvisor.toastState) == \"function\"\n"
            "\t\tand ChestAdvisor.toastState() or {}\n"
            "\treturn true, string.format(\n"
            "\t\t\"test toast: %s | queued: %s | lifetime: %.1fs — /up diag reports fired and the measured time\",\n"
            "\t\tst.shown and \"showing\" or \"not showing\", tostring(st.queue or 0),\n"
            "\t\ttonumber(st.lifetime) or 0)\n"
            "end\n"
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.testtoast-help",
        (
            "\t\t.. \"  /up toast <on|off>  turn the \\\"Upgrade found!\\\" toast on or off (persisted; default on)\\n\"\n"
        ),
        (
            "\t\t.. \"  /up toast <on|off>  turn the \\\"Upgrade found!\\\" toast on or off (persisted; default on)\\n\"\n"
            "\t\t.. \"  /up toasts / /up testtoast  raise one \\\"Test Upgrade\\\" toast NOW — the real panel and the real path\\n\"\n"
        ),
    )

    # The toast's timing is the MODULE's contract, not upstream's: the specs pin
    # 3.5 s of lifetime, a 0.25 s fade-out and a 0.18 s fade-in, and every one of
    # those numbers is what the shipped panel has always used. StatForge main
    # changed its own defaults (6 s / 1.0 s); adopting them silently would change
    # the panel under the player and break the measurement the specs grade, so the
    # fold keeps its numbers and says so here rather than in a hidden diff.
    text = replace_once(
        text,
        name,
        "ca.toast-timing-pin",
        (
            "local TOAST = {\n"
            "\taccent = { 0.400, 0.988, 0.945 },   -- #66FCF1, the window's own accent\n"
            "\tfadeIn = 0.25,\n"
            "\tfadeOut = 1.0,\n"
            "\tslide = 18,\n"
            "\ttick = 0.25,\n"
            "}\n"
        ),
        (
            "local TOAST = {\n"
            "\taccent = { 0.400, 0.988, 0.945 },   -- #66FCF1, the window's own accent\n"
            "\t-- Fold: the toast's timing is the module's shipped contract (and what\n"
            "\t-- tests/toast_test_spec.lua + tests/toast_trace_spec.lua grade), so the\n"
            "\t-- vendored copy keeps its own fade-in/fade-out lengths.\n"
            "\tfadeIn = 0.18,\n"
            "\tfadeOut = 0.25,\n"
            "\tslide = 18,\n"
            "\ttick = 0.25,\n"
            "}\n"
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.toast-lifetime-pin",
        "local TOAST_DEFAULTS = { enabled = true, lifetime = 6 }\n",
        (
            "-- Fold: 3.5 s is the lifetime this module ships and the one its specs\n"
            "-- measure. Upstream's own default (6 s) is a different panel; the\n"
            "-- player-facing number stays the fold's.\n"
            "local TOAST_DEFAULTS = { enabled = true, lifetime = 3.5 }\n"
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.toast-lifetime-help",
        (
            "\t\t.. \"  /up toast lifetime <s>  seconds the toast stays up, 1-30 (persisted; default 6)\\n\"\n"
        ),
        (
            "\t\t.. \"  /up toast lifetime <s>  seconds the toast stays up, 1-30 (persisted; default 3.5)\\n\"\n"
        ),
    )

    return text


# ---- Card t_c4911603: the tiebreaker flag reaches the player ----------------
#
# The comparator's third tier is only useful if the line says so. A tiebreaker
# row keeps its ordinary verdict token and its ordinary colour, but the sentence
# becomes "Upgrade — tiebreaker (+64 Armor, +2 Stamina) vs <worn> [Retribution]"
# (and "Not an upgrade — tiebreaker (...)" the other way), so a survivability
# gain is never read as a damage gain. The signed deltas ride on the row as
# `tiebreak` beside `weighted`/`profile`.
def edit_chestadvisor_weighted_local(text: str) -> str:
    """Hoist `w2` out of the else branch that assigns it.

    Upstream declares the weighted result inside one branch:

        else
          canUseV = canUse(id)
          local v2, r2, w2 = Verdict.evaluate(...)
          v, reason = v2, r2
        end

    ...and then reads `w2` further down, when it builds the persisted diag row
    (`weighted = w2 and w2.total`, `profile = w2 and w2.profile`,
    `tiebreak = w2 and w2.tiebreak`). Those three reads are outside the branch, so
    upstream is reading an undefined global: the diag has never recorded the
    weighted total, the profile or the tiebreak, and `luacheck` catches it as
    "accessing undefined variable 'w2'" six times.

    The fix is a declaration in the enclosing scope and a plain assignment inside
    the branch. No behaviour changes: the three fields were nil before and now
    carry the values they were always meant to carry.
    """
    text = replace_once(
        text,
        "ChestAdvisor/ChestAdvisor.lua",
        "ca.weighted-scope-declaration",
        "\t\t\t\t\titemsWalked = itemsWalked + 1\n"
        "\t\t\t\t\tlocal v, reason\n"
        "\t\t\t\t\tlocal canUseV\n",
        "\t\t\t\t\titemsWalked = itemsWalked + 1\n"
        "\t\t\t\t\tlocal v, reason\n"
        "\t\t\t\t\tlocal canUseV\n"
        "\t\t\t\t\t-- Fold: the weighted result is read by the diag row far below, so\n"
        "\t\t\t\t\t-- it is declared here. Upstream declares it inside the else that\n"
        "\t\t\t\t\t-- assigns it, and that row therefore read an undefined global.\n"
        "\t\t\t\t\tlocal w2\n",
    )
    text = replace_once(
        text,
        "ChestAdvisor/ChestAdvisor.lua",
        "ca.weighted-scope-assignment",
        "\t\t\t\t\t\tlocal v2, r2, w2 = Verdict.evaluate(\n",
        "\t\t\t\t\t\tlocal v2, r2\n"
        "\t\t\t\t\t\tv2, r2, w2 = Verdict.evaluate(\n",
    )
    return text


def edit_chestadvisor_tiebreak(text: str) -> str:
    """Card t_c4911603: render, and persist, the tiebreaker flag."""
    name = "ChestAdvisor/ChestAdvisor.lua"

    text = replace_once(
        text,
        name,
        "ca.tooltip-tiebreak-doc",
        "-- row, an UNKNOWN), so every existing line renders byte-identically.\n",
        (
            "-- row, an UNKNOWN), so every existing line renders byte-identically.\n"
            "--\n"
            "-- A row that carries `tiebreak` (card t_c4911603) was decided by the ranked\n"
            "-- survivability tiebreakers because the damage total was tied. Its sentence is\n"
            "-- \"tiebreaker (+64 Armor, +2 Stamina)\" — the signed deltas, candidate minus\n"
            "-- equipped — and NOT a weighted number, because the gain is not damage. The\n"
            "-- ordinary word for its token is used unchanged (\"Upgrade\" / \"Not an\n"
            "-- upgrade\"), so the flag is the only difference from a damage verdict.\n"
        ),
    )

    text = replace_once(
        text,
        name,
        "ca.tooltip-tiebreak-head",
        (
            "function TOOLTIP_UI.weighted(row, order)\n"
            '\tif type(row) ~= "table" or type(row.weighted) ~= "number" then return nil end\n'
            "\tlocal total = row.weighted\n"
            "\tlocal number = (Verdict and type(Verdict.numText) == \"function\")\n"
            "\t\tand Verdict.numText(total) or tostring(total)\n"
            '\tlocal head = "weighted " .. number\n'
            '\tif type(row.wornLink) == "string" then\n'
            '\t\thead = head .. " vs " .. itemNameOf(row.wornLink)\n'
            "\tend\n"
            '\tif type(row.profile) == "string" then\n'
            '\t\thead = head .. " [" .. row.profile .. "]"\n'
            "\tend\n"
            "\tlocal word = TOOLTIP_UI.word(row.verdict)\n"
            '\tif row.verdict == "NOT_UPGRADE" then\n'
            "\t\tif total < 0 then word = TOOLTIP_UI.words.DOWNGRADE\n"
            "\t\telse word = TOOLTIP_UI.words.NO_CHANGE end\n"
            "\tend\n"
        ),
        (
            "function TOOLTIP_UI.weighted(row, order)\n"
            '\tif type(row) ~= "table" or type(row.weighted) ~= "number" then return nil end\n'
            "\tlocal total = row.weighted\n"
            "\tlocal vs = nil\n"
            '\tif type(row.wornLink) == "string" then\n'
            '\t\tvs = " vs " .. itemNameOf(row.wornLink)\n'
            "\tend\n"
            "\tlocal profile = nil\n"
            '\tif type(row.profile) == "string" then\n'
            '\t\tprofile = " [" .. row.profile .. "]"\n'
            "\tend\n"
            "\tlocal word, head\n"
            '\tif type(row.tiebreak) == "string" and row.tiebreak ~= "" then\n'
            "\t\t-- Card t_c4911603: the damage total was tied and the profile's RANKED\n"
            "\t\t-- tiebreaker decided. The line is deliberately a different sentence from\n"
            "\t\t-- an ordinary weighted upgrade — \"tiebreaker (+64 Armor, +2 Stamina)\"\n"
            "\t\t-- rather than a number — because the gain is survivability, not damage.\n"
            "\t\t-- The deltas are signed from the candidate's side, so the same text says\n"
            "\t\t-- which way the tie broke in both directions. A NOT_UPGRADE keeps the\n"
            "\t\t-- card's own word (\"Not an upgrade\"), never \"Downgrade\": no damage was\n"
            "\t\t-- lost here, the equipped piece simply won the tiebreak.\n"
            '\t\thead = "tiebreaker (" .. row.tiebreak .. ")" .. (vs or "") .. (profile or "")\n'
            '\t\tword = (row.verdict == "UPGRADE") and TOOLTIP_UI.words.UPGRADE\n'
            "\t\t\tor TOOLTIP_UI.words.NOT_UPGRADE\n"
            "\telse\n"
            "\t\tlocal number = (Verdict and type(Verdict.numText) == \"function\")\n"
            "\t\t\tand Verdict.numText(total) or tostring(total)\n"
            '\t\thead = "weighted " .. number .. (vs or "") .. (profile or "")\n'
            "\t\tword = TOOLTIP_UI.word(row.verdict)\n"
            '\t\tif row.verdict == "NOT_UPGRADE" then\n'
            "\t\t\tif total < 0 then word = TOOLTIP_UI.words.DOWNGRADE\n"
            "\t\t\telse word = TOOLTIP_UI.words.NO_CHANGE end\n"
            "\t\tend\n"
            "\tend\n"
        ),
    )

    text = replace_once(
        text,
        name,
        "ca.quest-row-tiebreak",
        (
            "\t\t\trow.weighted = weighted.total\n"
            "\t\t\trow.profile = weighted.profile\n"
            "\t\tend\n"
        ),
        (
            "\t\t\trow.weighted = weighted.total\n"
            "\t\t\trow.profile = weighted.profile\n"
            "\t\t\t-- Card t_c4911603: nil on every ordinary outcome; the signed\n"
            "\t\t\t-- ranked deltas when the tiebreaker decided, so the line can say\n"
            "\t\t\t-- \"tiebreaker (...)\" instead of \"weighted 0\".\n"
            "\t\t\trow.tiebreak = weighted.tiebreak\n"
            "\t\tend\n"
        ),
    )

    text = replace_once(
        text,
        name,
        "ca.bag-row-tiebreak",
        (
            "\t\t\t\t\t\t\tweighted = w2 and w2.total or nil,\n"
            "\t\t\t\t\t\t\tprofile = w2 and w2.profile or nil,"
        ),
        (
            "\t\t\t\t\t\t\tweighted = w2 and w2.total or nil,\n"
            "\t\t\t\t\t\t\tprofile = w2 and w2.profile or nil,\n"
            "\t\t\t\t\t\t\t-- Card t_c4911603: the signed ranked deltas when a\n"
            "\t\t\t\t\t\t\t-- tiebreaker decided the row, nil otherwise (same\n"
            "\t\t\t\t\t\t\t-- two-scalar economy as `weighted`/`profile`: one\n"
            "\t\t\t\t\t\t\t-- short string, and only on tiebroken rows).\n"
            "\t\t\t\t\t\t\ttiebreak = w2 and w2.tiebreak or nil,"
        ),
    )

    return text


# ---- Card t_3a744b4a: the verdict follows the profile's WEIGHTS --------------
#
# Live defect (Mightie, Retribution paladin): a cloak that is -4 Str / -3 Armor /
# -2 Spi for +3 Sta read "Trade-off — better on some stats, worse on others",
# because the comparator counted DIRECTIONS: one stat up and one stat down is a
# trade-off no matter how lopsided the pair is. The owner's ruling: "A gain in any
# secondary stat must not automatically trigger 'trade-off'; evaluate the
# weighted result and show the stamina gain only as supporting detail."
#
# The replacement is one weighted total — sum over every differing stat of
# `delta x weight(profile, stat)` — compared against one named epsilon. It is the
# addon's ONLY scoring path; there is no second one to disagree with it. The
# documented stat ORDER keeps its job (it words a reason and it seeds the
# relevance set), it no longer decides.
#
# The upstream text is injected verbatim at two anchors in Verdict.lua; the
# indentation is written here with spaces and tabified by `_tabify` so what lands
# in the vendored file uses the file's own tab indentation.


def _tabify(block: str) -> str:
    """Turn leading two-space indentation into the tabs the vendored file uses."""
    out = []
    for line in block.split("\n"):
        stripped = line.lstrip(" ")
        pad = len(line) - len(stripped)
        if pad and stripped and pad % 2 == 0:
            line = "\t" * (pad // 2) + stripped
        out.append(line)
    return "\n".join(out)


VERDICT_WEIGHTS_BLOCK = _tabify(
    """-- ---- The stat weights (card t_3a744b4a): the ONE scoring path --------------
--
-- WHY THIS EXISTS. The verdict used to be decided by DIRECTION: the dominance
-- test over the relevance set answered "better on some, worse on others" for any
-- pair with one stat up and one stat down, however lopsided. The live case
-- (Retribution paladin, Mightie):
--
--     equipped  Lambent Scale Cloak   19 Armor  +4 Str  +2 Spi
--     hovered   Barkeeper's Cloak     16 Armor  +3 Sta
--     printed   "Trade-off — better on some stats, worse on others"
--
-- -4 Str and -3 Armor for +3 Sta is not a sidegrade on a damage profile. The
-- owner's ruling: a gain in any secondary stat must never, on its own, force a
-- trade-off; weigh the difference and show the secondary as supporting detail.
--
-- WHAT DECIDES NOW. One number:
--
--     weighted = sum over every stat that DIFFERS of (delta x weight(profile, stat))
--
-- and one named noise floor, Verdict.WEIGHT_EPSILON. In order:
--
--     weighted >= +epsilon                         -> UPGRADE
--     weighted <= -epsilon                         -> NOT_UPGRADE (a downgrade)
--     |weighted| < epsilon, a stat up AND one down  -> TRADE_OFF
--     otherwise (every difference one-directional) -> NOT_UPGRADE (no change)
--
-- "No change" and "downgrade" are the same TOKEN — NOT_UPGRADE, the closed token
-- vocabulary is untouched — and differ only in the player WORD the renderer
-- chooses from the sign of `weighted` (ChestAdvisor.lua, TOOLTIP_UI.weighted).
--
-- THIS IS THE ONLY SCORING PATH. There is no second table, no per-item score and
-- no separate "upgrade score" function anywhere in the addon: a number printed
-- beside a verdict is this number. The documented ORDERS above keep their two
-- jobs (they word a reason, and relevanceSet seeds the tiebreak set) and no
-- longer decide anything.
--
-- THE WEIGHTS. One profile per class AND role. The values come from the stat
-- order the corpus already documents for that class/role (stat-weights §8.1):
-- the first term scores 4 points per point of stat, the second 1, the third 0.
-- A stat the order does not name — Spirit on a warrior, Armor on a damage
-- profile — scores 0, which is the whole point: a zero-weight stat is SUPPORTING
-- DETAIL. It still appears in the delta list; it can never move the verdict.
-- The two tank profiles are the exception the owner asked for explicitly: they
-- put Stamina (and Armor/Block) on top, so the SAME item pair legitimately reads
-- as an upgrade for a Protection character. That is the proof the weights drive
-- the verdict — see tests/touchstone_weights_spec.lua.
--
-- `w` is points per point of the stat. A word absent from `w` is weight 0.
Verdict.WEIGHTS = {
  WARRIOR = {
    melee = { name = "Arms/Fury", w = { Strength = 4, Stamina = 1 } },
    tank  = { name = "Protection", w = { Stamina = 4, Armor = 2, Strength = 1, Block = 1 } },
  },
  PALADIN = {
    -- DAMAGER -> melee (str>int>sta). Stamina is the order's third term and the
    -- survivability stat: weight 0, so it cannot decide a damage verdict.
    melee = { name = "Retribution", w = { Strength = 4, Intellect = 1 } },
    spell = { name = "Holy", w = { Intellect = 4, Stamina = 1 } },
    tank  = { name = "Protection", w = { Stamina = 4, Armor = 2, Intellect = 1, Strength = 1, Block = 1 } },
  },
  ROGUE = {
    melee = { name = "Combat", w = { Agility = 4, Strength = 1 } },
  },
  HUNTER = {
    melee = { name = "Hunter", w = { Agility = 4, Stamina = 1 } },
  },
  MAGE = {
    spell = { name = "Mage", w = { Intellect = 4, Spirit = 1 } },
  },
  PRIEST = {
    spell = { name = "Priest", w = { Intellect = 4, Spirit = 1 } },
  },
  WARLOCK = {
    spell = { name = "Warlock", w = { Intellect = 4, Spirit = 1 } },
  },
  -- C1b (t_03a1196c): a feral Druid has no documented order, so it also has no
  -- weights. Its rows already stop at "no stat order resolved" before the
  -- comparator, and a caller that reaches the comparator gets the unavailable
  -- verdict below — never a guessed feral model.
  DRUID = {
    spell = { name = "Balance", w = { Intellect = 4, Agility = 1 } },
  },
  SHAMAN = {
    melee = { name = "Enhancement", w = { Strength = 4, Intellect = 1 } },
    spell = { name = "Elemental", w = { Intellect = 4, Strength = 1 } },
  },
}

-- The noise floor. Weights are whole points per point of stat, so with the
-- tables above the only total inside the band is 0 — the constant exists so the
-- band has ONE definition that a future fractional weight cannot silently
-- collapse back into a strict `> 0` test.
Verdict.WEIGHT_EPSILON = 1

-- The client's three-word role vocabulary (TANK / HEALER / DAMAGER) to a weights
-- role key. This is NOT ROLE_ALIAS (the stat-order alias, whose conservative
-- TANK -> spell proxy for a paladin is a separate ruling): here it only picks
-- which weight table scores the row. A class absent from this table resolves
-- from its own role word alone, so a pure class is unaffected.
Verdict.PROFILE_ROLE = {
  PALADIN = { TANK = "tank", HEALER = "spell", DAMAGER = "melee" },
  WARRIOR = { TANK = "tank", DAMAGER = "melee" },
}

-- The active profile for a spec, or nil.
--
--   spec — { class = <CLASS token>, role = <melee|spell|nil>,
--            clientRole = <TANK|HEALER|DAMAGER|nil> (optional) }
--
-- Resolution order: the CLIENT's role word when this class maps it, then the
-- addon's own role word, then — for a class with exactly ONE profile — that
-- profile (a pure class ignores the role argument, exactly as classRoleOrder
-- does). A hybrid with no resolved role returns nil: no profile, no guess.
function Verdict.profileFor(spec)
  if type(spec) ~= "table" then return nil end
  local class = spec.class
  local byRole = (type(class) == "string") and Verdict.WEIGHTS[class] or nil
  if type(byRole) ~= "table" then return nil end
  local alias = (type(class) == "string") and Verdict.PROFILE_ROLE[class] or nil
  local client = type(spec.clientRole) == "string" and spec.clientRole or nil
  if client ~= nil and type(alias) == "table" then
    local word = alias[client]
    if type(word) == "string" and type(byRole[word]) == "table" then
      return byRole[word]
    end
  end
  if type(spec.role) == "string" and type(byRole[spec.role]) == "table" then
    return byRole[spec.role]
  end
  -- A PURE class ignores the role argument (exactly as classRoleOrder does) and
  -- resolves the profile keyed by its one documented order word. A HYBRID must
  -- name a role: "no role resolved" is nil here too, never a default profile —
  -- which is why a feral Druid (a documented role with no documented order, and
  -- therefore no weights) resolves to nothing instead of silently scoring as
  -- Balance.
  if not isHybrid(class) then
    local orders = Verdict.ORDERS[class]
    if type(orders) == "table" then
      for word in pairs(orders) do
        if type(byRole[word]) == "table" then return byRole[word] end
      end
    end
  end
  return nil
end

-- A signed number as the tooltip and the reason print it: "+16", "-16", "0",
-- "1.5". Only the sign is added; the value is the arithmetic itself.
function Verdict.numText(n)
  if type(n) ~= "number" then return tostring(n) end
  local text
  if n == math.floor(n) then
    text = string.format("%d", n)
  else
    text = string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", "")
  end
  if n > 0 and text:sub(1, 1) ~= "+" then text = "+" .. text end
  return text
end

-- The weighted total for one pair under one profile.
--
--   returns { total = <number>,        the verdict's number
--             parts = { { word, delta, weight, contribution }, ... },
--             scored = <n>,           differing stats with a NON-ZERO weight
--             up = <n>, down = <n> }  differing stats that rose / fell
--
-- A stat neither side carries is absent from both tables and contributes
-- nothing; a stat one side carries is a KNOWN absence (the parse zero-fills it,
-- gates 5 and 8 having already refused anything unclassifiable), so it weighs in
-- at its full delta.
function Verdict.weightedTotal(candStats, eqStats, profile)
  local weights = (type(profile) == "table") and profile.w or nil
  if type(weights) ~= "table" then return nil end
  local cand = (type(candStats) == "table") and candStats or {}
  local eq = (type(eqStats) == "table") and eqStats or {}
  local words, seen = {}, {}
  for word in pairs(cand) do
    if not seen[word] then seen[word] = true; words[#words + 1] = word end
  end
  for word in pairs(eq) do
    if not seen[word] then seen[word] = true; words[#words + 1] = word end
  end
  table.sort(words)
  local total, parts, scored, up, down = 0, {}, 0, 0, 0
  for _, word in ipairs(words) do
    local delta = (tonumber(cand[word]) or 0) - (tonumber(eq[word]) or 0)
    if delta ~= 0 then
      local weight = tonumber(weights[word]) or 0
      local contribution = delta * weight
      total = total + contribution
      parts[#parts + 1] = {
        word = word, delta = delta, weight = weight, contribution = contribution,
      }
      if weight ~= 0 then scored = scored + 1 end
      if delta > 0 then up = up + 1 else down = down + 1 end
    end
  end
  return { total = total, parts = parts, scored = scored, up = up, down = down }
end

-- The stored reason: the number the verdict came from, and the profile it came
-- from, so a wrong profile is visible in the Upgrades tab and in /up diag
-- instead of silent. `kind` adds the words for the two non-obvious outcomes.
function Verdict.weightedReason(w, profile, kind)
  local head = "weighted " .. Verdict.numText(w.total)
    .. " [" .. tostring(type(profile) == "table" and profile.name or "no profile") .. "]"
  if kind == "trade-off" then
    return head .. " — better on some stats, worse on others"
  elseif kind == "no change" then
    return head .. " — no change"
  end
  return head
end

-- The verdict from the weights. Returns the same (verdict, reason) pair
-- Verdict.evaluate returns, plus a THIRD value — { total, profile } — for a row
-- that wants to render the number, or nil when the outcome did not come from
-- the weights (an unavailable profile, or the armour-material veto below, which
-- is a different reason entirely and must not be dressed as a weighted line).
--
-- `allow` is evaluate's own armour-material veto (a cloth item on a plate wearer
-- is never an upgrade, however the weights add up); a caller outside evaluate
-- passes nil and gets the raw weighted verdict.
function Verdict.weightedVerdict(candStats, eqStats, spec, allow)
  if type(allow) ~= "function" then
    allow = function(verdict, reason) return verdict, reason end
  end
  local profile = Verdict.profileFor(spec)
  if profile == nil then
    -- Requirement 5: NO WEIGHTS IS NOT A TRADE-OFF. Fall through to direction
    -- counting and the player gets an amber "your call" for a pair nothing
    -- weighed — the exact silence-with-an-answer this card removes.
    local class = type(spec) == "table" and spec.class or nil
    local role = type(spec) == "table" and spec.role or nil
    return "UNKNOWN", "verdict unavailable: no stat weights for this character (class "
      .. tostring(class or "unknown") .. ", role " .. tostring(role or "unresolved") .. ")"
  end
  local w = Verdict.weightedTotal(candStats, eqStats, profile)
  if w == nil then
    return "UNKNOWN", "verdict unavailable: the " .. tostring(profile.name)
      .. " profile carries no weights"
  end
  local detail = { total = w.total, profile = profile.name }
  local eps = Verdict.WEIGHT_EPSILON
  if w.total >= eps then
    local verdict, reason = allow("UPGRADE", Verdict.weightedReason(w, profile, "upgrade"))
    if verdict ~= "UPGRADE" then return verdict, reason end
    return verdict, reason, detail
  end
  if w.total <= -eps then
    return "NOT_UPGRADE", Verdict.weightedReason(w, profile, "downgrade"), detail
  end
  if w.up > 0 and w.down > 0 then
    local verdict, reason = allow(TRADE_OFF, Verdict.weightedReason(w, profile, "trade-off"))
    if verdict ~= TRADE_OFF then return verdict, reason end
    return verdict, reason, detail
  end
  return "NOT_UPGRADE", Verdict.weightedReason(w, profile, "no change"), detail
end

-- ⚠ TEST INSTRUMENTATION ONLY, exactly like Verdict.LEGACY_ORDER_DECIDES above.
-- `true` restores the pre-card direction count so a fixture can be run through
-- both comparators in one VM and diffed. No shipped path sets it.
Verdict.LEGACY_DOMINANCE_DECIDES = false

"""
)

# Anchor: the doc comment that opens the evaluate section, immediately after the
# trade-off reason helper. The weights block lands between them, so it loads
# before evaluate and after relevanceSet/TRADE_OFF.
VERDICT_WEIGHTS_ANCHOR = "-- The tri-state comparator.\n"

# The weighted decision replaces the direction count at gate 9. The old block is
# kept behind LEGACY_DOMINANCE_DECIDES (below) so it stays reachable from a test
# and the shipped default is the weighted verdict.
VERDICT_GATE9_ANCHOR = (
    "\tlocal outcome, firstDiff = Verdict.dominance(candStats, eqStats, terms)\n"
)

VERDICT_GATE9_OPEN = _tabify(
    """-- ⚠ THE WEIGHTED VERDICT (card t_3a744b4a). This is the shipped decision:
-- the profile's weighted total, in the threshold order the card spells out. The
-- number (and the profile's own name) travel back to the caller as the third
-- return value so a rendered line can quote them.
--
-- The direction count below is reachable ONLY through LEGACY_DOMINANCE_DECIDES,
-- which is test instrumentation (it exists so a fixture can be run through both
-- comparators in one VM and diffed). It is read here, so the switch really does
-- switch: with it set, the weighted path is skipped and the old block runs.
if not Verdict.LEGACY_DOMINANCE_DECIDES then
  local v, r, d = Verdict.weightedVerdict(candStats, eqStats, spec_, allow)
  if v ~= nil then return v, r, d end
end

if Verdict.LEGACY_DOMINANCE_DECIDES then
"""
)

VERDICT_GATE9_CLOSE_OLD = (
    "\treturn \"NOT_UPGRADE\", \"equal to what's equipped — not a strict improvement\"\n"
    "end\n"
    "\n"
    "-- ---- Tier B (t_73e20edb): the off-hand slot"
)
VERDICT_GATE9_CLOSE_NEW = (
    "\treturn \"NOT_UPGRADE\", \"equal to what's equipped — not a strict improvement\"\n"
    "\tend\n"
    "end\n"
    "\n"
    "-- ---- Tier B (t_73e20edb): the off-hand slot"
)


def edit_verdict(text: str) -> str:
    """Card t_3a744b4a: the verdict follows the active profile's weights."""
    name = "ChestAdvisor/Verdict.lua"
    text = replace_once(text, name, "verdict.weights", VERDICT_WEIGHTS_ANCHOR,
                        VERDICT_WEIGHTS_BLOCK + VERDICT_WEIGHTS_ANCHOR)
    text = replace_once(text, name, "verdict.weighted-gate", VERDICT_GATE9_ANCHOR,
                        VERDICT_GATE9_OPEN + VERDICT_GATE9_ANCHOR)
    text = replace_once(text, name, "verdict.weighted-gate-close", VERDICT_GATE9_CLOSE_OLD,
                        VERDICT_GATE9_CLOSE_NEW)
    text = edit_verdict_tiebreak(text)
    return text


# ---- Card t_c4911603: the SECOND TIER — Agility, then Armor/Stamina ---------
#
# Retribution scored `w = { Strength = 4, Intellect = 1 }`: no Agility at all
# (so Dagmire Gauntlets vs Gloves of the Fang came out close) and no
# Stamina/Armor (so `51 Armor / +4 Str` leather boots vs `115 Armor / +4 Str /
# +2 Sta` mail boots scored 0 and read "no change").
#
# The fix is not a bigger weight table. Damage decides first (Strength, Spell
# Power, Agility, Intellect — the numbers researched for WoW: Forever in
# t_f758a377); Stamina and Armor are an ORDERED tiebreaker list consulted only
# when the damage total is zero, and a decided tiebreaker is flagged as such.
#
# These are anchored folds over the text t_3a744b4a already injects, so the
# vendored files stay generated: hand-editing them would be reverted by the next
# sync.
def edit_verdict_tiebreak(text: str) -> str:
    """Card t_c4911603: Agility as damage, Armor/Stamina as ranked tiebreakers."""
    name = "ChestAdvisor/Verdict.lua"

    # (a) the decision table in the doc block gains the tied branch.
    text = replace_once(
        text,
        name,
        "verdict.tiers-decision-table",
        (
            "-- and one named noise floor, Verdict.WEIGHT_EPSILON. In order:\n"
            "--\n"
            "--     weighted >= +epsilon                         -> UPGRADE\n"
            "--     weighted <= -epsilon                         -> NOT_UPGRADE (a downgrade)\n"
            "--     |weighted| < epsilon, a stat up AND one down  -> TRADE_OFF\n"
            "--     otherwise (every difference one-directional) -> NOT_UPGRADE (no change)\n"
        ),
        (
            "-- and one named noise floor, Verdict.WEIGHT_EPSILON. In order:\n"
            "--\n"
            "--     weighted >= +epsilon                         -> UPGRADE\n"
            "--     weighted <= -epsilon                         -> NOT_UPGRADE (a downgrade)\n"
            "--     |weighted| < epsilon                          -> damage is TIED, so a\n"
            "--                                                     profile with ranked\n"
            "--                                                     tiebreakers answers next\n"
            "--     ... tied, no tiebreaker decides, mixed signs  -> TRADE_OFF\n"
            "--     ... tied, no tiebreaker decides, one-way      -> NOT_UPGRADE (no change)\n"
            "--\n"
            "-- The tiebreaker tier (card t_c4911603) is an ORDER, not another number: the\n"
            "-- profile's `tiebreak` list is walked in rank order and the first stat whose two\n"
            "-- sides differ decides, so no survivability delta can ever outweigh a damage\n"
            "-- point. When it decides, the verdict keeps its ordinary token and gains the\n"
            "-- word \"tiebreaker\" plus the signed deltas — a visibly different answer from a\n"
            "-- damage upgrade because the gain is not damage.\n"
        ),
    )

    # (b) the doc paragraph that explains a profile's shape.
    text = replace_once(
        text,
        name,
        "verdict.tiers-doc",
        "-- `w` is points per point of the stat. A word absent from `w` is weight 0.\n"
        "Verdict.WEIGHTS = {\n",
        (
            "-- `w` is points per point of the stat. A word absent from `w` is weight 0.\n"
            "--\n"
            "-- TWO TIERS, RETRIBUTION ONLY (card t_c4911603). A profile may carry\n"
            "-- `tiebreak = { <stat>, ... }`: an ORDERED list consulted ONLY when the damage\n"
            "-- total is exactly zero. Damage stats decide first and always; a tiebreaker can\n"
            "-- never outweigh one point of Strength or Agility. The entries are ranked, not\n"
            "-- weighted — the first ranked stat whose two sides differ decides, so a large\n"
            "-- number on a lower-ranked stat cannot outvote a higher-ranked one. This is\n"
            "-- Mightie's rule, and it is what keeps the -16 cloak case a downgrade while\n"
            "-- letting `+64 Armor / +2 Sta` at equal Strength read as a (flagged) upgrade.\n"
            "-- The Ret table's numbers are the ones researched for WoW: Forever in card\n"
            "-- t_f758a377 (vault: wiki/addons/touchstone-ret-stat-weights.md §2):\n"
            "--   Strength 4, SpellPower 4 (= 1.00 x Str against a sourced 1.04 median),\n"
            "--   Agility 2.5 (= 0.625 x Str for a 0.64 median), Intellect 2,\n"
            "--   Armor > Stamina as ranked tiebreakers (25 Armor ~= 1 Sta of effective HP).\n"
            "-- Holy and Protection keep their own rows: the same research card says their\n"
            "-- numbers need separate evidence, and none of it is used here.\n"
            "Verdict.WEIGHTS = {\n"
        ),
    )

    # (c) the Retribution row itself.
    text = replace_once(
        text,
        name,
        "verdict.ret-two-tier-row",
        (
            "\tPALADIN = {\n"
            "\t\t-- DAMAGER -> melee (str>int>sta). Stamina is the order's third term and the\n"
            "\t\t-- survivability stat: weight 0, so it cannot decide a damage verdict.\n"
            '\t\tmelee = { name = "Retribution", w = { Strength = 4, Intellect = 1 } },\n'
        ),
        (
            "\tPALADIN = {\n"
            "\t\t-- DAMAGER -> melee. Card t_c4911603 (research t_f758a377): the damage\n"
            "\t\t-- tier is Strength + SpellPower (the Forever sim's top Ret stat, 1.04 x\n"
            "\t\t-- Strength) + Agility (0.64 x Strength, carried as 2.5) + Intellect; the\n"
            "\t\t-- ranked tiebreakers are Armor then Stamina. Stamina and Armor appear\n"
            "\t\t-- ONLY in `tiebreak`, never in `w` — see the block above.\n"
            "\t\tmelee = {\n"
            '\t\t\tname = "Retribution",\n'
            "\t\t\tw = { Strength = 4, SpellPower = 4, Agility = 2.5, Intellect = 2 },\n"
            '\t\t\ttiebreak = { "Armor", "Stamina" },\n'
            "\t\t},\n"
        ),
    )

    # (d) the noise floor drops below the smallest total a 2.5 weight can make.
    text = replace_once(
        text,
        name,
        "verdict.tiers-epsilon",
        (
            "-- The noise floor. Weights are whole points per point of stat, so with the\n"
            "-- tables above the only total inside the band is 0 — the constant exists so the\n"
            "-- band has ONE definition that a future fractional weight cannot silently\n"
            "-- collapse back into a strict `> 0` test.\n"
            "Verdict.WEIGHT_EPSILON = 1\n"
        ),
        (
            "-- The noise floor. Weights are points per point of stat; the Ret table\n"
            "-- (t_c4911603) carries the fractional 2.5, so the band must be smaller than the\n"
            "-- smallest NON-zero total that table can produce. Every weight is a multiple of\n"
            "-- 0.5 (4, 2.5, 2), so 0.25 sits strictly between a true zero and the smallest\n"
            "-- real difference and no genuine 0.5 gain is swallowed — the reason\n"
            "-- t_f758a377 pinned epsilon <= 0.25. With the old whole-point `1` a pair such as\n"
            "-- +1 Agility / -1 Intellect would net 0.5 and read \"no change\".\n"
            "-- The constant exists so the band has ONE definition that only the totals table\n"
            "-- can move. The tiebreaker tier below is gated on this same band, which is safe\n"
            "-- for exactly the reason above: no total these tables can produce lands inside\n"
            "-- it, so \"inside the band\" IS a true tie.\n"
            "Verdict.WEIGHT_EPSILON = 0.25\n"
        ),
    )

    # (e) the ranked-tiebreaker helpers, between weightedTotal and the reason.
    text = replace_once(
        text,
        name,
        "verdict.tiebreak-helpers",
        "-- The stored reason: the number the verdict came from, and the profile it came\n",
        (
            "-- The ranked tiebreakers a profile declares, or nil.\n"
            "--\n"
            "-- The list is ORDER, not arithmetic: entries are consulted in the order the\n"
            "-- profile wrote them, and the first one whose two sides differ decides. This is\n"
            "-- why a big Armor number cannot outvote a higher-ranked stat, and why the\n"
            "-- profile is the only place the ranking lives (the research card ranks Armor\n"
            "-- above Stamina for Ret; swapping them is a one-line change here, not a new\n"
            "-- weight table).\n"
            "function Verdict.tiebreakStats(profile)\n"
            "\tlocal ranked = (type(profile) == \"table\") and profile.tiebreak or nil\n"
            "\tif type(ranked) ~= \"table\" or #ranked == 0 then return nil end\n"
            "\treturn ranked\n"
            "end\n"
            "\n"
            "-- The tiebreaker comparison for one pair under one profile.\n"
            "--\n"
            "--   returns nil when the profile declares no tiebreakers, when the parse is not\n"
            "--   two tables, or when every ranked stat is equal on both sides (nothing to\n"
            "--   break — the caller keeps the ordinary words);\n"
            "--   otherwise { stat = <deciding word>, dir = 1|-1,\n"
            "--               parts = { { word, delta }, ... },   -- NON-ZERO deltas, ranked\n"
            "--               text = \"+64 Armor, +2 Stamina\" }    -- candidate - equipped\n"
            "--\n"
            "-- A stat absent on one side is a KNOWN absence and weighs in at its full delta,\n"
            "-- exactly as weightedTotal treats it. The deltas are signed from the candidate's\n"
            "-- side, so the printed text says which way the tie broke without a second word.\n"
            "function Verdict.tiebreakTotal(candStats, eqStats, profile)\n"
            "\tlocal ranked = Verdict.tiebreakStats(profile)\n"
            "\tif ranked == nil then return nil end\n"
            "\tlocal cand = (type(candStats) == \"table\") and candStats or {}\n"
            "\tlocal eq   = (type(eqStats)   == \"table\") and eqStats   or {}\n"
            "\tlocal parts, deciding, dir = {}, nil, nil\n"
            "\tfor _, word in ipairs(ranked) do\n"
            "\t\tlocal delta = (tonumber(cand[word]) or 0) - (tonumber(eq[word]) or 0)\n"
            "\t\tif delta ~= 0 then\n"
            "\t\t\tparts[#parts + 1] = { word = word, delta = delta }\n"
            "\t\t\tif deciding == nil then\n"
            "\t\t\t\tdeciding = word\n"
            "\t\t\t\tdir = (delta > 0) and 1 or -1\n"
            "\t\t\tend\n"
            "\t\tend\n"
            "\tend\n"
            "\tif deciding == nil then return nil end\n"
            "\tlocal bits = {}\n"
            "\tfor _, p in ipairs(parts) do\n"
            "\t\tbits[#bits + 1] = Verdict.numText(p.delta) .. \" \" .. p.word\n"
            "\tend\n"
            "\treturn { stat = deciding, dir = dir, parts = parts, text = table.concat(bits, \", \") }\n"
            "end\n"
            "\n"
            "-- The stored reason: the number the verdict came from, and the profile it came\n"
        ),
    )

    # (f) the reason learns the tiebreaker sentence.
    text = replace_once(
        text,
        name,
        "verdict.tiers-reason",
        (
            "function Verdict.weightedReason(w, profile, kind)\n"
            '\tlocal head = "weighted " .. Verdict.numText(w.total)\n'
            "\t\t.. \" [\" .. tostring(type(profile) == \"table\" and profile.name or \"no profile\") .. \"]\"\n"
            '\tif kind == "trade-off" then\n'
            '\t\treturn head .. " — better on some stats, worse on others"\n'
            '\telseif kind == "no change" then\n'
            '\t\treturn head .. " — no change"\n'
            "\tend\n"
            "\treturn head\n"
            "end\n"
        ),
        (
            "function Verdict.weightedReason(w, profile, kind, tiebreakText)\n"
            '\tlocal head = "weighted " .. Verdict.numText(w.total)\n'
            "\t\t.. \" [\" .. tostring(type(profile) == \"table\" and profile.name or \"no profile\") .. \"]\"\n"
            '\tif kind == "trade-off" then\n'
            '\t\treturn head .. " — better on some stats, worse on others"\n'
            '\telseif kind == "no change" then\n'
            '\t\treturn head .. " — no change"\n'
            '\telseif (kind == "tiebreaker upgrade" or kind == "tiebreaker downgrade")\n'
            '\t\tand type(tiebreakText) == "string" then\n'
            "\t\t-- Damage was tied; the flag and the ranked deltas ARE the reason. The\n"
            "\t\t-- sign of each delta says which side the tie broke for.\n"
            '\t\treturn head .. " — tiebreaker (" .. tiebreakText .. ")"\n'
            "\tend\n"
            "\treturn head\n"
            "end\n"
        ),
    )

    # (g) the third return value's doc gains the tiebreak fields.
    text = replace_once(
        text,
        name,
        "verdict.tiers-detail-doc",
        "-- is a different reason entirely and must not be dressed as a weighted line).\n",
        (
            "-- is a different reason entirely and must not be dressed as a weighted line).\n"
            "-- When the ranked tiebreaker decided, that third value also carries\n"
            "-- { tiebreak = \"<signed deltas>\", tiebreakDir = 1|-1 } so the renderer can flag\n"
            "-- the answer without re-deriving it from the reason text.\n"
        ),
    )

    # (h) the tier itself, between the negative threshold and the trade-off words.
    text = replace_once(
        text,
        name,
        "verdict.tiers-decide",
        (
            "\tif w.total <= -eps then\n"
            '\t\treturn "NOT_UPGRADE", Verdict.weightedReason(w, profile, "downgrade"), detail\n'
            "\tend\n"
        ),
        (
            "\tif w.total <= -eps then\n"
            '\t\treturn "NOT_UPGRADE", Verdict.weightedReason(w, profile, "downgrade"), detail\n'
            "\tend\n"
            "\t-- DAMAGE IS TIED. Only now may the profile's ranked tiebreakers speak (card\n"
            "\t-- t_c4911603): a profile without a `tiebreak` list — every profile but Ret —\n"
            "\t-- falls straight through to the words below, byte-identically to before.\n"
            "\t-- The tier is a flag on the answer, not a second number: the verdict is the\n"
            "\t-- ordinary UPGRADE / NOT_UPGRADE token and the reason says \"tiebreaker\", so\n"
            "\t-- a survivability gain can never be mistaken for damage.\n"
            "\tlocal tb = Verdict.tiebreakTotal(candStats, eqStats, profile)\n"
            "\tif tb ~= nil then\n"
            '\t\tlocal kind = (tb.dir > 0) and "tiebreaker upgrade" or "tiebreaker downgrade"\n'
            "\t\tlocal reason = Verdict.weightedReason(w, profile, kind, tb.text)\n"
            "\t\tdetail.tiebreak = tb.text\n"
            "\t\tdetail.tiebreakDir = tb.dir\n"
            "\t\tif tb.dir > 0 then\n"
            "\t\t\t-- The armour-material veto still applies to a tiebreaker upgrade: a\n"
            "\t\t\t-- cloth piece on a mail wearer is never an upgrade, however the tie\n"
            "\t\t\t-- broke (the same call the damage tier makes).\n"
            '\t\t\tlocal verdict, why = allow("UPGRADE", reason)\n'
            '\t\t\tif verdict ~= "UPGRADE" then return verdict, why end\n'
            "\t\t\treturn verdict, why, detail\n"
            "\t\tend\n"
            '\t\treturn "NOT_UPGRADE", reason, detail\n'
            "\tend\n"
        ),
    )

    return text



EDITORS = {
    "Core.lua": edit_core,
    "Integration.lua": edit_integration,
    "ChestAdvisor/ChestAdvisor.lua": edit_chestadvisor,
    "ChestAdvisor/Verdict.lua": edit_verdict,
}


ASSET_LITERAL = '"Interface\\\\AddOns\\\\Touchstone\\\\ChestAdvisor\\\\marker.tga"'
ASSET_CONST = "MIGHTIEPACK_TOUCHSTONE_ASSETS"
ASSET_PREAMBLE = (
    "-- Fold: asset paths point at where the module actually lives. Upstream\n"
    "-- hardcodes Interface\\AddOns\\Touchstone\\... which does not exist once the\n"
    "-- files are vendored under MightiePack/Modules/Touchstone/ — the bag arrow\n"
    "-- and the toast arrow then render as nothing and the upgrade never shows.\n"
    "local _mpAddonName = ...\n"
    "local " + ASSET_CONST + " = \"Interface\\\\AddOns\\\\\"\n"
    "\t.. tostring(_mpAddonName or \"MightiePack\")\n"
    "\t.. \"\\\\Modules\\\\Touchstone\\\\ChestAdvisor\\\\\"\n"
)


def retarget_assets(text: str, name: str) -> str:
    """Point Touchstone's own art at the vendored location, once per file."""
    if ASSET_LITERAL not in text:
        return text
    text = text.replace(ASSET_LITERAL, "(" + ASSET_CONST + " .. \"marker.tga\")")
    # The constant has to exist before first use; put it right after the guard.
    marker = "if MightiePackTouchstoneSkip then return end\n"
    if not text.startswith(marker):
        raise SyncError("{}: skip guard missing before asset rewrite".format(name))
    return text[: len(marker)] + ASSET_PREAMBLE + text[len(marker):]


def load_guarded(src_root: Path, name: str) -> str:
    text = read_text(src_root / name)
    if text.startswith("if MightiePackTouchstoneSkip then return end"):
        raise SyncError(
            "{} already carries a skip guard — is --src pointing at a previous "
            "sync output instead of the pristine upstream checkout?".format(name)
        )
    return SKIP_GUARD + text


# ── personal data scrub ────────────────────────────────────────────────
# Upstream captures carry the author's own client paths: a character folder,
# an account name, a Windows drive path. They are comments, but the pack ships
# to strangers, so the sync rewrites them on the way in — every time, because
# the next upstream sync would otherwise put them straight back.
_SAVED_VARS = re.compile(r"\b\d+/[A-Za-z0-9]+-[A-Za-z0-9]+/SavedVariables/([A-Za-z0-9_]+\.lua)")
_WIN_USER = re.compile(r"[A-Za-z]:[\\/]Users[\\/][^`'\"\s)]*")
# The same leak on this side of the fence: WSL mounts, home directories, macOS
# user folders. A capture comment pasted from any of them must not ship.
_POSIX_USER = re.compile(r"(?:/mnt/[a-z]/|/home/|/Users/)[^`'\"\s)]*")


def scrub_personal(text: str) -> str:
    text = _SAVED_VARS.sub(lambda m: "SavedVariables/" + m.group(1), text)
    text = _WIN_USER.sub("<local client path>", text)
    text = _POSIX_USER.sub("<local client path>", text)
    return text


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
        text = retarget_assets(text, name)
        outputs[name] = scrub_personal(text)
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
        if _SAVED_VARS.search(text) or _WIN_USER.search(text) or _POSIX_USER.search(text):
            problems.append("{} still carries a client path after the scrub".format(name))
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

    # t_c2e67619: the addon's own name is not rendered into the tooltip, and the
    # duplicate guard must not still key on the prefix it used to carry.
    advisor = outputs.get("ChestAdvisor/ChestAdvisor.lua", "")
    if "local v2, r2, w2 = Verdict.evaluate" in advisor:
        problems.append(
            "ChestAdvisor.lua still declares w2 inside the branch that assigns it; "
            "the diag row below cannot see it"
        )
    if "\t\t\t\t\tlocal w2\n" not in advisor:
        problems.append("ChestAdvisor.lua has no hoisted w2 declaration")
    if 'TOOLTIP_PREFIX = "Touchstone: "' in advisor:
        problems.append(
            "ChestAdvisor.lua still renders the addon's name into the tooltip line"
        )
    if "text:find(TOOLTIP_PREFIX" in advisor:
        problems.append(
            "ChestAdvisor.lua's duplicate guard still searches for the tooltip "
            "prefix (empty since t_c2e67619 — it would match every line)"
        )
    return problems


def _git(args: list, cwd: Path) -> str:
    """Run one git command, returning its stripped stdout (raises on failure)."""
    done = subprocess.run(
        ["git", "-C", str(cwd)] + args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if done.returncode != 0:
        raise SyncError("git {}: {}".format(" ".join(args), done.stderr.strip()))
    return done.stdout.strip()


def git_commit(root: Path) -> str:
    """The short commit of a git checkout, or "" when the folder is not one."""
    if not (root / ".git").exists():
        return ""
    try:
        return _git(["rev-parse", "--short", "HEAD"], root)
    except SyncError:
        return ""


def resolve_source(src: str | None, ref: str) -> tuple:
    """Return (checkout root, printed label, temp clone to clean up or None)."""
    if src:
        root = Path(src).expanduser().resolve()
        if not root.is_dir():
            raise SyncError("--src is not a directory: {}".format(root))
        sha = git_commit(root)
        return root, "{}@{}".format(root, sha or "unknown"), None

    clone = Path(tempfile.mkdtemp(prefix="touchstone-src-"))
    # Fetch the ref by name, then check out the PINNED commit: `clone --branch`
    # only understands branch/tag names, so a SOURCE_REF that is a bare commit
    # cannot be cloned that way. Fetching by SHA is supported by GitHub; when the
    # caller asked for a branch (--ref main) we take that branch's tip instead.
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
    sha = git_commit(clone)
    if not sha:
        shutil.rmtree(clone, ignore_errors=True)
        raise SyncError("cloned source has no commit: {}".format(clone))
    return clone, "{}@{}".format(SOURCE_URL, sha), clone


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--src",
        default=None,
        help=(
            "path to a pristine Touchstone checkout; omit to clone "
            "{} ({}) at run time".format(SOURCE_URL, SOURCE_REF)
        ),
    )
    parser.add_argument(
        "--ref",
        default=SOURCE_REF,
        help="git ref to clone when --src is not given (default: {})".format(SOURCE_REF),
    )
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="regenerate in memory and audit everything, but write nothing",
    )
    args = parser.parse_args(argv)

    temp_clone = None
    try:
        src_root, source, temp_clone = resolve_source(args.src, args.ref)
        outputs = generate(src_root)
        problems = audit_toc() + audit_outputs(outputs)
        if problems:
            for problem in problems:
                print("TOC/AUDIT: " + problem, file=sys.stderr)
            return 2
        if not args.verify_only:
            write_outputs(src_root, outputs)
        print("sync_touchstone: source {}".format(source))
        print(
            "sync_touchstone: {} lua files {}; toc ok".format(
                len(outputs), "verified" if args.verify_only else "written"
            )
        )
        return 0
    except SyncError as exc:
        print("sync_touchstone: ERROR: " + str(exc), file=sys.stderr)
        return 1
    finally:
        if temp_clone is not None:
            shutil.rmtree(temp_clone, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
