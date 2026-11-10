if MightiePackTouchstoneSkip then return end
--- StatForge core: SavedVariables, events, slash commands, lifecycle.
--- UI shell lives in UI.lua + *Tab.lua.
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
  -- Integration.lua defines this and loads before Core.lua.
  if type(SF.EnableIntegrations) == "function" then
    SF.EnableIntegrations()
  end
  SLASH_TOUCHSTONE1 = "/touchstone"
  SLASH_TOUCHSTONE2 = "/sf"
  SLASH_TOUCHSTONE3 = "/statforge"
  SlashCmdList.TOUCHSTONE = touchstoneSlash
end
