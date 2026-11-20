-- Host opt-out: a host that vendors these files sets TouchstoneSkip = true before
-- loading them, and every shipped file returns at this line. Unset -- the normal
-- case -- nothing changes. See README.md, "Embedding Touchstone in a host addon".
if TouchstoneSkip then return end
--- StatForge core: SavedVariables, events, slash commands, lifecycle.
--- UI shell lives in UI.lua + *Tab.lua.
-- Naming: StatForge is this repo; the addon it ships is Touchstone
-- (Touchstone.toc). The Lua namespace keeps the repo's name on purpose
-- (StatForge is the table, SF its alias), and nothing is being renamed.
---
--- The export / desktop-app half is RETIRED (card t_adf556d6). This file used to
--- carry three export-only hooks -- the PLAYER_LOGOUT auto-export, the
--- `/sf export` arm, and the BANKFRAME open/close bank-cache writes. All three
--- belonged to the export path (SF.CacheBank / SF.DoExport lived in the now
--- deleted Snapshot.lua), so they are gone with it. Do not re-add them: the
--- owner's ruling is that the addon gives in-game advice and needs no export.

StatForge = StatForge or {}
local SF = StatForge

local function initDB()
  StatForgeDB = StatForgeDB or {}
  StatForgeDB.ui = StatForgeDB.ui or {}
  -- firstUse defaults to true (nil means first use)
  if StatForgeDB.firstUse == nil then
    StatForgeDB.firstUse = true
  end
  -- NOTE (card t_adf556d6, AC-H): the export-only keys (bankCache, exports,
  -- lastExportAt, gearSetups) are no longer initialised. They are NOT deleted or
  -- renamed -- a name this file stops writing simply stops being written, and the
  -- owner's existing SavedVariables file keeps whatever it already holds. The
  -- variable itself is still declared and still written (window position,
  -- minimap state, deep-probe history), so nothing purges it.
end

-- Fold (MightiePack): the pack ships Touchstone OFF by default, but
-- ChestAdvisor.lua still assigns its first-run ChestAdvisorDB while it loads and
-- the client saves that table at logout. Upstream's table-identity test would
-- therefore read almost every pack character as a veteran and the line would
-- never show. The pack's ruling (owner, 2026-11-20): the line is for characters
-- that have never ENABLED Touchstone. It runs from SF.Enable() (load, or the
-- moment the module is switched on), never from a frame of its own.
--
-- A character is a veteran when its table already says so: readyAnnounced is
-- set (written by the first enable from this version on), or it carries
-- anything an enabled Touchstone writes. The first-run default is exactly
-- `{ role = {} }`, so any other key, or a recorded role, means it ran before.
local function advisorDBLooksUsed(db)
  for k, v in pairs(db) do
    if k ~= "role" then return true end
    if type(v) ~= "table" or next(v) ~= nil then return true end
  end
  return false
end

--- The one-time "ready" line, for characters that have never enabled
--- Touchstone. A veteran is marked announced and stays quiet.
--- ADD-ONLY: the only key this writes is readyAnnounced; nothing is removed.
function SF.MaybeAnnounceReady()
  local db = rawget(_G, "ChestAdvisorDB")
  if type(db) ~= "table" then return end
  if db.readyAnnounced == true then return end
  local veteran = advisorDBLooksUsed(db)
  db.readyAnnounced = true
  if veteran then return end
  SF.Print("ready — hover your bags")
end

-- Fold (MightiePack Touchstone module): the ADDON_LOADED / PLAYER_LOGIN
-- event frame that used to live here is gone. MightiePack fires
-- ADDON_LOADED for its own name after SavedVariables exist and calls
-- SF.Enable() (defined at the end of this file). initDB above keeps its
-- body unchanged. A disabled module creates no frame and no minimap
-- button. SF.ADDON_NAME is no longer a behavioural gate anywhere.

-- Card t_916be2d9: the addon is now Touchstone. The slash handler keeps its
-- single implementation; the global is renamed to match the addon identity.
-- Three slash STRINGS all reach this one handler (see the SLASH_* block at the
-- bottom of this file): /touchstone (canonical), /sf (the owner's muscle
-- memory, retained as an alias), and /statforge (the retired name, retained so
-- an old habit still lands somewhere rather than erroring silently).
--
-- /ts is NOT one of them (card t_83f9795c, commits 81d514e and 5656449; kept
-- by t_6696b35a). The client strips the slash word, so a second registration
-- of the string "/ts" on this handler would either steal it from the advisor
-- or be the dead copy. /ts stays SLASH_CHESTADVISOR4, exactly once.
-- Fold: the handler stays here, unchanged in body; only its
-- registration moved into SF.Enable() below.
local function touchstoneSlash(msg)
  local arg = (msg or ""):match("^%s*(.-)%s*$"):lower()
  -- NOTE (card t_adf556d6): the `debug` arm is gone too. It called
  -- SF.DebugContainers, which lived in the deleted Snapshot.lua and reported
  -- on the export's container scan. `/sf diag` (the client API sweep) covers
  -- what a container problem actually needs.
  if arg == "diag" or arg == "diagnostics" then
    SF.ShowDiagnosticsPanel()
    return
  end
  if arg == "doctor" then
    SF.PrintDiagnosticsReport()
    SF.ShowDiagnosticsPanel()
    return
  end
  if arg == "probe" then
    -- Writes the readout into SavedVariables so it reaches disk on /reload,
    -- instead of asking the tester to copy an uncopyable chat frame.
    SF.DeepProbe()
    return
  end
  if arg == "stats" or (arg:match("^stats%s") ~= nil) then
    -- Card t_acc9fd97 (item 2): the owner's unit reading. The item comes
    -- from the link the owner pastes into the command; the arm word is
    -- matched on the lowercased msg (as every other arm is) but the LINK is
    -- re-pulled from the RAW msg — an item link's hex must not be folded.
    -- The probe reports the client's own C_Item.GetItemStats pairs verbatim
    -- (key, value, type), which is the evidence that decides the
    -- HIT/CRIT/DODGE/PARRY rating-vs-percent question the card defers.
    local link = (msg or ""):match("^%s*stats%s+(.-)%s*$")
    SF.StatProbe(link)
    return
  end
  if arg == "export" then
    -- Retired by card t_adf556d6. The arm is gone; the word is NOT silently
    -- swallowed into ToggleMain, it says what happened so an old habit learns.
    SF.Print("export is retired — Touchstone advises in game now (/touchstone)")
    return
  end
  if arg == "gear" then
    -- Retired with the Gear tab (card t_adf556d6).
    SF.Print("import/equip is retired — Touchstone advises in game now (/touchstone)")
    return
  end
  if arg == "options" then
    SF.ShowMain("options")
    return
  end
  SF.ToggleMain()
end
-- Fold (MightiePack Touchstone module): the single registration point.
-- Called by the module once, after SavedVariables exist. The three slash
-- strings and the handler registration live here so a disabled module
-- answers no slash at all. Integration's surfaces are registered here too.
function SF.Enable()
  initDB()
  SF.CreateMinimapButton()
  SF.UpdateMinimapButton()
  -- Fold: upstream calls this on PLAYER_LOGIN; the module's Enable is the
  -- pack's one init point (load, or the toggle). Add-only: readyAnnounced only.
  SF.MaybeAnnounceReady()
  -- Integration.lua defines this and loads before Core.lua.
  if type(SF.EnableIntegrations) == "function" then
    SF.EnableIntegrations()
  end
  SLASH_TOUCHSTONE1 = "/touchstone"
  SLASH_TOUCHSTONE2 = "/sf"
  SLASH_TOUCHSTONE3 = "/statforge"
  SlashCmdList.TOUCHSTONE = touchstoneSlash
end
