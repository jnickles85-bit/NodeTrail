local addonName, pkg = ...

MightiePack = pkg
pkg.addonName = addonName

function pkg.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99MightiePack|r: " .. tostring(msg or ""))
end

-- TOC metadata, provider chain (t_5507a0ba).
--
-- On the Forever 16001 client the global GetAddOnMetadata does not exist,
-- so /mpack status printed "version unknown / interface unknown" for a
-- perfectly good TOC. The modern surface is C_AddOns.GetAddOnMetadata;
-- the legacy global is the fallback. Both are pcall'd and both must
-- return a non-empty string, and the provider is resolved at CALL time —
-- a client (or a test stub) that adds or removes either one after load
-- must be honoured, never cached.
function pkg.GetAddOnMeta(addon, field)
  if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnMetadata) == "function" then
    local ok, val = pcall(C_AddOns.GetAddOnMetadata, addon, field)
    if ok and type(val) == "string" and val ~= "" then
      -- @project-version@ is substituted by the packager; a source checkout has
      -- not been through it, and printing the raw token in /mp help reads as a bug.
      if val:find("^@.*@$") then return "dev" end
      return val
    end
  end
  if type(GetAddOnMetadata) == "function" then
    local ok, val = pcall(GetAddOnMetadata, addon, field)
    if ok and type(val) == "string" and val ~= "" then
      return val
    end
  end
  return nil
end

-- Pack version from the TOC, via GetAddOnMeta. Nil-safe: a missing provider
-- or an empty string returns nil rather than a stale hardcoded string.
--
-- This is the ONE place the tag's "v" is taken off (card t_c02c1643). The
-- packager substitutes the TOC's `## Version:` line from the git TAG, so a
-- tagged build arrives as "v0.3.12-beta" — the tag's own leading v included —
-- while a hand-edited TOC has none. Removing it here means every caller can add
-- its own convention (the window header prefixes "v", the Options footer
-- prefixes " v") without asking whether a v is already there. Two consumers
-- each guessed instead, and the footer read "MightiePack vv0.3.12-beta"; the
-- next consumer someone wrote would have doubled it too.
--
-- A source-checkout token (@project-version@) is not a version: it answers
-- "dev" here, the same word GetAddOnMeta's modern path already returns, so the
-- two provider paths agree and no caller can print "@project-version@" back.
function pkg.PackVersion()
  if type(pkg.GetAddOnMeta) ~= "function" then
    return nil
  end
  local ok, val = pcall(pkg.GetAddOnMeta, pkg.addonName or "MightiePack", "Version")
  if not ok or type(val) ~= "string" then
    return nil
  end
  val = val:gsub("^%s+", ""):gsub("%s+$", "")
  if val == "" then return nil end
  -- The packager's unsubstituted token: a dev build, not a version string.
  if val:find("^@.*@$") then return "dev" end
  val = val:gsub("^[vV]", "")
  if val == "" then return nil end
  return val
end

-- NodeTrail used to be the gathering module. It is its own addon now (card
-- t_75309c97), so the pack's default list holds Touchstone only. The
-- `modules.NodeTrail` key in an existing MightiePackDB is left exactly as it is:
-- the pack no longer has a module to read it, and dropping a saved key is not
-- this card's business.
pkg.moduleDefaults = {
  Touchstone = false,
}

function pkg.GetSettings()
  if type(MightiePackDB) ~= "table" then
    MightiePackDB = {}
  end
  if type(MightiePackDB.modules) ~= "table" then
    MightiePackDB.modules = {}
  end
  for name, def in pairs(pkg.moduleDefaults or {}) do
    if MightiePackDB.modules[name] == nil then
      MightiePackDB.modules[name] = def
    end
  end
  return MightiePackDB
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    pkg.GetSettings()
    if type(pkg.EnableModules) == "function" then
      pkg.EnableModules()
    end
    f:UnregisterEvent("ADDON_LOADED")
  end
end)

-- Protected-action reporter.
--
-- When the client refuses an addon call, it fires ADDON_ACTION_BLOCKED (or
-- _FORBIDDEN) with (addonName, functionName) and raises the modal
--   "<addon> has been blocked from an action only available to the Blizzard UI"
-- The modal never says WHICH function, and the taint log only flushes on a
-- clean exit — so without this the only way to identify the call is to guess.
-- The event arguments are public, so printing them answers it in one line.
local guard = CreateFrame("Frame")
for _, ev in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
  if type(guard.RegisterEvent) == "function" then
    pcall(guard.RegisterEvent, guard, ev)
  end
end
if type(guard.SetScript) == "function" then
  guard:SetScript("OnEvent", function(_, event, who, what)
    pkg.Print(("%s: the client refused a protected call — addon=%s function=%s")
      :format(tostring(event), tostring(who), tostring(what)))
  end)
end

SLASH_MIGHTIEPACK1 = "/mightiepack"
SLASH_MIGHTIEPACK2 = "/mpack"
-- Card t_2d2c37b0 (the reshape): the alias table is now an explicit inventory.
-- Every slash this pack registers is listed here with the surface it opens, and
-- every retirement is listed with what replaced it. A dangling alias is worse
-- than a missing one: the player types the command they have used for months,
-- gets the generic usage text, and concludes the addon is broken.
--
-- Retired by this card (deliberately, listed here so it stays listed):
--
--   /nt, /nodetrail     LEFT the pack with NodeTrail (card t_75309c97). The
--                       standalone addon owns them; the pack registers neither.
--   /mp skindiag        a SUBCOMMAND, not an alias: it answered for the
--                       Skinning tab's diagnostics, which left with NodeTrail.
--                       It is not silently dropped — it answers with where the
--                       diagnostics went (see the handler below), because a
--                       player who typed it deserves a sentence, not usage text.
--
-- Still live, all of them landing on one of the window's two tabs:
--
--   /mp, /mpack, /mightiepack   -> Pack Settings
--   /up, /upgrade, /chestadvice, /ts,
--   /touchstone, /sf, /statforge -> Touchstone
--
-- The Touchstone aliases are registered by the vendored body and rerouted to
-- this window by Window/TouchstoneTab.lua's seam; this file does not re-register
-- them, it only names them, so the inventory and the code cannot disagree
-- silently (tests/slash_retirement_spec.lua checks both ends).
pkg.SlashAliases = {
  { aliases = { "/mightiepack", "/mpack", "/mp" }, tab = "settings", owner = "mightiepack" },
  { aliases = { "/up", "/upgrade", "/chestadvice", "/ts" }, tab = "touchstone", owner = "chestadvisor" },
  { aliases = { "/touchstone", "/sf", "/statforge" }, tab = "touchstone", owner = "touchstone" },
}

pkg.RetiredSlashAliases = {
  { alias = "/nt", reason = "moved out with NodeTrail (t_75309c97) — the standalone addon owns it" },
  { alias = "/nodetrail", reason = "moved out with NodeTrail (t_75309c97) — the standalone addon owns it" },
  { alias = "/mp skindiag", reason = "a subcommand for the Skinning tab's diagnostics, which left with NodeTrail" },
}

SLASH_MIGHTIEPACK3 = "/mp"

--- Is the standalone NodeTrail addon installed on this client?
---
--- NodeTrail moved out of the pack (card t_75309c97). The pack does not load,
--- read or write anything of NodeTrail's any more, but it does keep declaring
--- `NodeTrailDB` for one migration window: that declaration is what lets a
--- player's herb and skinning history be read by the game and carried into
--- NodeTrail.lua on the first login with both addons installed. When NodeTrail
--- is present, the pack's help points at it instead of answering for it.
---
--- Folder existence, not load state: `MightiePack` sorts before `NodeTrail`, so
--- at our load time IsAddOnLoaded is false even when the player has it. This is
--- the same provider chain Modules/Touchstone/Bootstrap.lua uses, and `false`
--- (not nil) only when a detector actually answered.
function pkg.NodeTrailInstalled()
  local api = rawget(_G, "C_AddOns")
  if type(api) == "table" and type(api.DoesAddOnExist) == "function" then
    local ok, exists = pcall(api.DoesAddOnExist, "NodeTrail")
    if ok then return exists and true or false end
  end
  local info = rawget(_G, "GetAddOnInfo")
  if type(info) == "function" then
    local ok, name = pcall(info, "NodeTrail")
    if ok then return name ~= nil end
  end
  local loaded = rawget(_G, "IsAddOnLoaded")
  if type(loaded) == "function" then
    local ok, on = pcall(loaded, "NodeTrail")
    if ok then return on and true or false end
  end
  return false
end

SlashCmdList.MIGHTIEPACK = function(msg)
  local raw = (msg or ""):match("^%s*(.-)%s*$") or ""
  -- `rest` is the SECOND capture: `local x = s:match(...)` takes only
  -- the first capture back, which would be the command word itself.
  local first, rest = raw:match("^(%S+)%s*(.*)$")
  first = (first or ""):lower()
  rest = (rest or ""):match("^%s*(.-)%s*$") or ""
  if first == "" or first == "options" or first == "config" then
    if type(pkg.OpenOptions) == "function" then
      pkg.OpenOptions()
    end
  elseif first == "status" then
    -- t_e9996745: identity header so `/mpack status` output is a
    -- self-describing bug report: addon version + Interface (both from the
    -- TOC via GetAddOnMetadata("MightiePack", ...)), client build number
    -- (select(4, GetBuildInfo())) plus the full GetBuildInfo() version
    -- string, current locale, and whether GatherMate2 is loaded.
    -- Every API is guarded against a missing function AND a nil/empty
    -- return: this file must print "unknown" and never error in an
    -- environment where the stub does not define the globals at all
    -- (umbrella_spec defines none of them).
    -- t_5507a0ba: the provider chain (C_AddOns.GetAddOnMetadata, then the
    -- legacy global, then "unknown") lives in pkg.GetAddOnMeta because the
    -- Forever client has no global GetAddOnMetadata at all.
    local function tocMeta(what)
      if type(pkg.GetAddOnMeta) ~= "function" then
        return nil
      end
      local ok, val = pcall(pkg.GetAddOnMeta, addonName, what)
      if ok and type(val) == "string" and val ~= "" then
        return val
      end
      return nil
    end
    pkg.Print("version " .. (tocMeta("Version") or "unknown"))

    local iface = tocMeta("Interface") or "unknown"

    local build, clientVersion = "unknown", "unknown"
    if type(GetBuildInfo) == "function" then
      -- real contract: major, minor, patch, build, platform, locale, serverName
      local ok, major, minor, patch, buildNum = pcall(GetBuildInfo)
      if ok and type(buildNum) == "string" and buildNum ~= "" then
        build = buildNum
        if type(major) == "string" and type(minor) == "string" and type(patch) == "string" then
          clientVersion = major .. "." .. minor .. "." .. patch .. "." .. buildNum
        end
      end
    end

    local loc = "unknown"
    if type(GetLocale) == "function" then
      local ok, l = pcall(GetLocale)
      if ok and type(l) == "string" and l ~= "" then
        loc = l
      end
    end

    local gm2 = "unknown"
    if type(IsAddOnLoaded) == "function" then
      local ok, loaded = pcall(IsAddOnLoaded, "GatherMate2")
      if ok then
        gm2 = loaded and "loaded" or "not loaded"
      end
    end

    pkg.Print(("interface %s, build %s, client %s, locale %s, GatherMate2: %s")
      :format(iface, build, clientVersion, loc, gm2))

    -- NodeTrail was the only gathering module; it is its own addon now (card
    -- t_75309c97). The pack's own module list is Touchstone alone.
    for _, name in ipairs(pkg.moduleOrder or {}) do
      local def = pkg.modules and pkg.modules[name]
      if def then
        local state = pkg.IsModuleEnabled(name) and "on" or "off"
        local line = (def.title or name) .. ": " .. state
        if def.stub then
          line = line .. " (coming soon)"
        end
        if def.inert then
          -- EnableModules marks a refusing module as loaded; without this the
          -- status line would claim a module is running while it is inert.
          line = line .. " (inert - standalone Touchstone installed)"
        elseif def.loaded then
          line = line .. " (loaded)"
        end
        pkg.Print(line)
      end
    end
    if pkg.NodeTrailInstalled() then
      pkg.Print("NodeTrail: a separate addon, installed (/nt help for its commands)")
    else
      pkg.Print("NodeTrail: a separate addon, not installed")
    end
  elseif first == "skindiag" or first == "herbs" or first == "skinning" then
    -- Retired by card t_2d2c37b0. These answered for the Herbs and Skinning
    -- tabs' diagnostics; both tabs left with NodeTrail (t_75309c97). The player
    -- gets a sentence naming where they went instead of the generic usage text:
    -- a retired command that shrugs is indistinguishable from a broken one.
    local nt = type(pkg.NodeTrailInstalled) == "function" and pkg.NodeTrailInstalled() == true
    pkg.Print("/mp " .. first .. " moved out of the pack with NodeTrail.")
    if nt then
      pkg.Print("NodeTrail is installed here: /nt " .. first .. " (or /nt help).")
    else
      pkg.Print("Install NodeTrail (separate addon) for the herb and skinning diagnostics.")
    end
  elseif first == "bug" then
    -- Same popup as the options-panel "Report a bug" button.
    if type(pkg.OpenBugReport) == "function" then
      pkg.OpenBugReport()
    else
      pkg.Print("bug report form unavailable (BugReport module did not load)")
    end
  elseif first == "idea" then
    -- Same popup as the options-panel "Suggest an idea" button.
    -- Only the first token of the rest selects Area (e.g. `/mp idea
    -- nodetrail please` fills NodeTrail); extra words are ignored.
    if type(pkg.OpenIdeaReport) == "function" then
      pkg.OpenIdeaReport(rest)
    else
      pkg.Print("idea form unavailable (BugReport module did not load)")
    end
  else
    -- keep the historical usage line verbatim (existing callers/tests
    -- rely on it).
    pkg.Print("/mpack [options|status]")
    pkg.Print("/mpack bug — open the bug report form (no upload — copy and paste into Discord)")
    pkg.Print("/mpack idea — open the idea form (no upload — copy and paste into Discord)")
    if type(pkg.NodeTrailInstalled) == "function" and pkg.NodeTrailInstalled() == true then
      -- NodeTrail is its own addon. When it is installed, this pack points at
      -- it instead of pretending to answer for it.
      pkg.Print("NodeTrail is a separate addon now: /nt help")
    end
  end
end
