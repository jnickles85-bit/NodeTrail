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
            "\tfadeFor = nil, shownAt = nil, showMs = nil, lastEnd = nil,\n"
            "}\n"
        ),
        (
            "\tfadeFor = nil, shownAt = nil, showMs = nil, lastEnd = nil,\n"
            "\t-- t_fe7a636a: the show's deadline in the client's own clock, and\n"
            "\t-- the counters for the repairs below. `deadline` is refreshed by the\n"
            "\t-- countdown every tick, so a finish step can require that the\n"
            "\t-- configured lifetime really elapsed instead of trusting whichever\n"
            "\t-- animation callback arrived.\n"
            "\tdeadline = nil, fadeArmedAt = nil, lastTickPrinted = nil,\n"
            "\trevived = 0, alphaRestored = 0,\n"
            "}\n"
        ),
    )

    # ---- the trace itself, and the switch ------------------------------------
    text = replace_once(
        text,
        name,
        "ca.toast-trace-helpers",
        "local drawToast, advanceToast, showToastItem, toastFinishShow, toastMeasure\n",
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
            "\t\tpcall(toastRT.fadeIn.Play, toastRT.fadeIn)\n"
            "\telse\n"
        ),
        (
            "local function toastPlayFadeIn(f, showId)\n"
            "\ttoastStopAnimations()\n"
            "\tif type(f.SetAlpha) ~= \"function\" then return end\n"
            "\tpcall(f.SetAlpha, f, 0)\n"
            "\tif type(toastRT.fadeIn) == \"table\" and type(toastRT.fadeIn.Play) == \"function\" then\n"
            "\t\tpcall(toastRT.fadeIn.Play, toastRT.fadeIn)\n"
            "\t\tTRACE.line(\"fadeIn play id=\" .. tostring(showId))\n"
            "\telse\n"
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
            "\t\t-- trace and does nothing else. It has no finish path at all; if this\n"
            "\t\t-- client delivers OnFinished from a Stop() (the behaviour the\n"
            "\t\t-- fade-out's guard exists for), the trace says so instead of a\n"
            "\t\t-- comment asserting it.\n"
            "\t\tif type(ag.SetScript) == \"function\" then\n"
            "\t\t\tag:SetScript(\"OnFinished\", function()\n"
            "\t\t\t\tTRACE.line(\"animation finished: group=fadeIn id=\"\n"
            "\t\t\t\t\t.. tostring(toastRT.showId)\n"
            "\t\t\t\t\t.. \" fadeFor=\" .. tostring(toastRT.fadeFor))\n"
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
            "\t\t\t\tlocal id = toastRT.fadeFor\n"
            "\t\t\t\tif id == nil then return end\n"
            "\t\t\t\ttoastRT.fadeFor = nil\n"
            "\t\t\t\tpcall(toastFinishShow, id)\n"
            "\t\t\tend)\n"
        ),
        (
            "\t\t\tag:SetScript(\"OnFinished\", function()\n"
            "\t\t\t\tlocal id = toastRT.fadeFor\n"
            "\t\t\t\tTRACE.line(\"animation finished: group=fadeOut id=\"\n"
            "\t\t\t\t\t.. tostring(toastRT.showId)\n"
            "\t\t\t\t\t.. \" fadeFor=\" .. tostring(id))\n"
            "\t\t\t\tif id == nil then return end\n"
            "\t\t\t\ttoastRT.fadeFor = nil\n"
            "\t\t\t\tpcall(toastFinishShow, id, \"fadeOnFinished\")\n"
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
            "\tlocal ms = toastMeasure()\n"
            "\tif ms then toastRT.showMs = ms end\n"
            "\ttoastRT.shownAt = nil\n"
            "\ttoastRT.fadeFor = nil\n"
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
            "\tlocal ms = toastMeasure()\n"
            "\tif ms then toastRT.showMs = ms end\n"
            "\ttoastRT.shownAt = nil\n"
            "\ttoastRT.fadeFor = nil\n"
            "\ttoastRT.deadline = nil\n"
            "\ttoastRT.fadeArmedAt = nil\n"
            "\ttoastRT.lastTickPrinted = nil\n"
        ),
    )

    # ---- the expiry: trace it, stamp the arm, name the reasons ---------------
    text = replace_once(
        text,
        name,
        "ca.toast-expire-reason",
        (
            "toastExpire = function()\n"
            "\tif type(toastRT.ticker) == \"table\" and type(toastRT.ticker.Cancel) == \"function\" then\n"
            "\t\tpcall(toastRT.ticker.Cancel, toastRT.ticker)\n"
            "\tend\n"
            "\ttoastRT.ticker = nil\n"
            "\tif not toastActive then return end\n"
            "\ttoastRT.lastEnd = \"expired\"\n"
            "\tlocal showId = toastRT.showId\n"
        ),
        (
            "toastExpire = function(reason)\n"
            "\tif type(toastRT.ticker) == \"table\" and type(toastRT.ticker.Cancel) == \"function\" then\n"
            "\t\tpcall(toastRT.ticker.Cancel, toastRT.ticker)\n"
            "\tend\n"
            "\ttoastRT.ticker = nil\n"
            "\tif not toastActive then return end\n"
            "\ttoastRT.lastEnd = \"expired\"\n"
            "\tlocal showId = toastRT.showId\n"
            "\tTRACE.line(\"expire id=\" .. tostring(showId) .. \" reason=\"\n"
            "\t\t.. tostring(reason or \"timer\"))\n"
        ),
    )
    text = replace_once(
        text,
        name,
        "ca.toast-expire-arm-trace",
        (
            "\t\ttoastRT.fadeFor = showId\n"
            "\t\tlocal played = pcall(fade.Play, fade)\n"
        ),
        (
            "\t\ttoastRT.fadeFor = showId\n"
            "\t\ttoastRT.fadeArmedAt = TRACE.now()\n"
            "\t\tlocal played = pcall(fade.Play, fade)\n"
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
            "\t\telse\n"
            "\t\t\ttoastRT.shownAt = nil\n"
            "\t\tend\n"
            "\t\t-- Re-anchor from the persisted position on every show: the panel may have\n"
        ),
        (
            "\t\telse\n"
            "\t\t\ttoastRT.shownAt = nil\n"
            "\t\tend\n"
            "\t\t-- t_fe7a636a: the deadline this show must survive to, on the same\n"
            "\t\t-- clock the countdown ticks on. The finish step refuses to end a\n"
            "\t\t-- show before it.\n"
            "\t\ttoastRT.deadline = (toastRT.shownAt or TRACE.now()) + toastRT.lifetimeLeft\n"
            "\t\ttoastRT.fadeArmedAt = nil\n"
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
            "\t\t\t\ttoastRT.lastEnd = \"dismissed\"\n"
            "\t\t\t\tlocal ms = toastMeasure and toastMeasure()\n"
        ),
        (
            "\t\t\t\ttoastRT.lastEnd = \"dismissed\"\n"
            "\t\t\t\t-- t_fe7a636a: a dismiss is the one end that may come before the\n"
            "\t\t\t\t-- deadline (the player asked for it). It is traced as both an\n"
            "\t\t\t\t-- expire and a finish so every end reads in the same vocabulary.\n"
            "\t\t\t\tlocal dismissedLeft = tonumber(toastRT.lifetimeLeft) or 0\n"
            "\t\t\t\tif dismissedLeft < 0 then dismissedLeft = 0 end\n"
            "\t\t\t\tTRACE.line(\"expire id=\" .. tostring(toastRT.showId) .. \" reason=dismiss\")\n"
            "\t\t\t\tTRACE.line(\"finish id=\" .. tostring(toastRT.showId)\n"
            "\t\t\t\t\t.. \" reason=dismiss lifeLeft=\" .. TRACE.sec(dismissedLeft))\n"
            "\t\t\t\ttoastRT.deadline = nil\n"
            "\t\t\t\ttoastRT.fadeArmedAt = nil\n"
            "\t\t\t\tlocal ms = toastMeasure and toastMeasure()\n"
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
            "\t\tshowMs = toastRT.showMs,\n"
            "\t\tlastEnd = toastRT.lastEnd,\n"
            "\t}\n"
        ),
        (
            "\t\tlifetime = toastLifetime(),\n"
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
            "\telseif subword == \"toasts\" or subword == \"testtoast\" then\n"
            "\t\tok, out = cmdTestToast()\n"
        ),
        (
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
    text = replace_once(
        text,
        name,
        "ca.toast-diag-trace",
        (
            "\t\t\t\t.. \"\\nconfigured lifetime: \"\n"
            "\t\t\t\t.. string.format(\"%.2fs\", tonumber(ts.lifetime) or 0)\n"
            "\t\t\t\t.. \" | last show on screen: \" .. measured\n"
        ),
        (
            "\t\t\t\t.. \"\\nconfigured lifetime: \"\n"
            "\t\t\t\t.. string.format(\"%.2fs\", tonumber(ts.lifetime) or 0)\n"
            "\t\t\t\t.. \" | last show on screen: \" .. measured\n"
            "\t\t\t\t-- t_fe7a636a: the trace switch and the repairs, so a flash\n"
            "\t\t\t\t-- report comes with the numbers that explain it.\n"
            "\t\t\t\t.. \" | trace: \" .. (ts.debug and \"ON\" or \"off\")\n"
            "\t\t\t\t.. \"\\nrevived this session: \" .. tostring(ts.revived)\n"
            "\t\t\t\t.. \" | alpha restored: \" .. tostring(ts.alphaRestored)\n"
            "\t\t\t\t.. \" | deadline left: \"\n"
            "\t\t\t\t.. (tonumber(ts.deadlineLeft)\n"
            "\t\t\t\t\tand string.format(\"%.2fs\", ts.deadlineLeft) or \"-\")\n"
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

    return text


EDITORS = {
    "Core.lua": edit_core,
    "Integration.lua": edit_integration,
    "ChestAdvisor/ChestAdvisor.lua": edit_chestadvisor,
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

    # t_c2e67619: the addon's own name is not rendered into the tooltip, and the
    # duplicate guard must not still key on the prefix it used to carry.
    advisor = outputs.get("ChestAdvisor/ChestAdvisor.lua", "")
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
