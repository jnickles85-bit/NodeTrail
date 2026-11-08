-- skindiag_spec.lua — t_a5f41944 (Skinning 1/3: in-client event probe)
--
-- Pins the card's three tests:
--   1. the probe registers only the events C_EventUtils.IsEventValid says
--      exist, records an invalid one as "invalid event", and the dump
--      prints the captured steps in order (every line <= 120 chars).
--   2. a stub loot window attached to a corpse GUID after a Skinning cast
--      is attributed to that creature (kind "skin"); an ordinary corpse
--      loot window is routed to the separate "corpse" class.
--   3. a researched baseline entry WITHOUT a source is not rendered by
--      the formatter the data-model document proposes.
-- Plus: module gating (off by default, honest message), the /mp alias,
-- the no-C_EventUtils client, and no SavedVariables writes.
--
-- RED at the parent commit (236c155 — no Modules/Skinning/, no skindiag
-- branch in Core.lua, no TOC lines): expect FAILs and EXIT=1.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end
-- Run a section only when its subject exists; otherwise report ONE clear
-- FAIL. On the parent commit (no Modules/Skinning/) this keeps the red run
-- informative instead of crashing halfway through.
local function onlyIf(cond, why, fn)
  if not cond then
    check(false, why)
    return
  end
  local ok, err = pcall(fn)
  check(ok, "section ran: " .. tostring(err))
end

-- ── TOC: both new files listed, in load order ───────────────────────
local function readToc()
  local f = assert(io.open(root .. "/MightiePack/MightiePack.toc", "r"))
  local content = f:read("*a")
  f:close()
  local lines = {}
  for line in content:gmatch("[^\r\n]+") do
    local t = (line:gsub("^%s+", ""):gsub("%s+$", ""))
    if t ~= "" and not t:match("^#") then table.insert(lines, t) end
  end
  return lines
end

local toc = readToc()
local pos = {}
for i, l in ipairs(toc) do pos[l] = i end
check(pos["Modules/Skinning/Probe.lua"] ~= nil, "TOC lists Modules/Skinning/Probe.lua")
check(pos["Modules/Skinning/Core.lua"] ~= nil, "TOC lists Modules/Skinning/Core.lua")
if pos["Modules/Skinning/Probe.lua"] and pos["Modules/Skinning/Core.lua"] then
  check(pos["Modules.lua"] < pos["Modules/Skinning/Probe.lua"],
    "TOC: Skinning files load after Modules.lua")
  check(pos["Modules/Skinning/Probe.lua"] < pos["Modules/Skinning/Core.lua"],
    "TOC: Probe.lua loads before Skinning/Core.lua")
  if pos["BugReport.lua"] then
    check(pos["Modules/Skinning/Core.lua"] < pos["BugReport.lua"],
      "TOC: Skinning loads before BugReport.lua")
  end
end

-- ── chat capture ────────────────────────────────────────────────────
local chat = {}
local reloads = 0
DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end,
}
local function clearChat()
  for i = #chat, 1, -1 do chat[i] = nil end
end
local function chatText()
  return table.concat(chat, "\n")
end

-- ── client stub ─────────────────────────────────────────────────────
SlashCmdList = {}
StaticPopupDialogs = {}
StaticPopup_Show = function() end
OKAY = "Okay"
CANCEL = "Cancel"
ReloadUI = function() reloads = reloads + 1 end
GameTooltip = {
  SetOwner = function() end, SetText = function() end,
  AddLine = function() end, Show = function() end, Hide = function() end,
}

local now = 2000
GetTime = function() return now end
GetSpellInfo = function(id)
  local names = { [99333] = "Skinning", [2366] = "Herb Gathering" }
  return names[id]
end
GetZone = function() return "Desolace" end
GetSubzone = function() return "Stonetalon" end
C_Map = {
  GetBestMapForUnit = function() return 572 end,
  GetPlayerMapPosition = function()
    return { GetXY = function() return 0.3123, 0.4456 end }
  end,
}
GetUnitName = function(u)
  if u == "player" then return "Mightie" end
  return "Cave Rat"
end
GetUnitGUID = function(u)
  if u == "player" then return "Player-0-1" end
  return "Creature-0-150-1234"
end

-- loot window stub (classic contract, same read the NodeTrail recorder uses)
local loot = {}
local lootSource = nil
local lootSourceName = nil
GetNumLootItems = function() return #loot end
GetLootSlotLink = function(i) return loot[i] and loot[i].link end
GetLootSlotInfo = function(i)
  local s = loot[i]
  if s then return "icon", s.name, s.qty, s.quality end
end
GetLootSourceInfo = function() return lootSource end
GetLootSourceName = function() return lootSourceName end

-- Event validity comes from the CLIENT, by trying to register: this harness
-- refuses exactly one card event, LOOT_SLOT_CLEARED, the same way the live
-- client answers an event it does not know
-- ("Attempt to register unknown event"). Validity is NOT asked of
-- C_EventUtils — that namespace is restricted, and calling it pops the
-- "blocked from an action only available to the Blizzard UI" modal
-- (see event_gate_spec).
local unknownEvents = { LOOT_SLOT_CLEARED = true }

-- ── frame harness ───────────────────────────────────────────────────
local frames = {}
CreateFrame = function()
  local f = { scripts = {}, events = {} }
  f.SetScript = function(self, n, fn) self.scripts[n] = fn end
  f.GetScript = function(self, n) return self.scripts[n] end
  f.RegisterEvent = function(self, n)
    if unknownEvents[n] then
      error('Attempt to register unknown event "' .. tostring(n) .. '"', 2)
    end
    self.events[n] = true
  end
  f.UnregisterEvent = function(self, n) self.events[n] = nil end
  frames[#frames + 1] = f
  return f
end

-- ── load the addon (the files this spec needs, in TOC order) ────────
local files = {
  "Core.lua",
  "Modules.lua",
  "Modules/Skinning/Probe.lua",
  "Modules/Skinning/Core.lua",
}
local function loadPackage(pkg, addonName)
  for _, f in ipairs(files) do
    local p = root .. "/MightiePack/" .. f
    local chunk, err = loadfile(p)
    check(chunk ~= nil, "loadfile " .. f .. ": " .. tostring(err))
    if chunk then
      local ok, e2 = pcall(chunk, addonName or "MightiePack", pkg)
      check(ok, "load " .. f .. ": " .. tostring(e2))
    end
  end
end
local function boot(pkg, addonName)
  -- the umbrella Core.lua's own ADDON_LOADED frame is the newest one
  for i = #frames, 1, -1 do
    local f = frames[i]
    if f.events.ADDON_LOADED and f.scripts.OnEvent then
      local ok, e = pcall(f.scripts.OnEvent, f, "ADDON_LOADED", addonName or "MightiePack")
      check(ok, "ADDON_LOADED: " .. tostring(e))
      return
    end
  end
  check(false, "no ADDON_LOADED frame found")
end

MightiePackDB = nil
NodeTrailDB = nil
local pkg = {}
loadPackage(pkg, "MightiePack")
boot(pkg, "MightiePack")

-- ════════════════════════════════════════════════════════════════════
-- Section A: the probe is NodeTrail's sub-feature, not a module
-- (t_5507a0ba: "Skinning should be inside NodeTrail")
-- ════════════════════════════════════════════════════════════════════
check(type(pkg.modules) == "table" and pkg.modules.Skinning == nil,
  "Skinning is NOT a registered module (no sibling checkbox)")
check(pkg.moduleDefaults and pkg.moduleDefaults.Skinning == nil,
  "moduleDefaults has no Skinning entry any more")
local orderHasSkinning = false
for _, n in ipairs(pkg.moduleOrder or {}) do
  if n == "Skinning" then orderHasSkinning = true end
end
check(not orderHasSkinning, "moduleOrder has no Skinning entry")
check(type(pkg.Skinning) == "table", "the skinning namespace still loads from the TOC")

local ns = pkg.Skinning
local P = ns and ns.Probe
check(type(P) == "table", "pkg.Skinning.Probe loaded")
check(P.enabled ~= true, "probe is not armed until NodeTrail or a diagnostic asks")

-- CHOICE (also stated in the completion summary): a diagnostic is allowed
-- to run while the sub-toggle is off. This spec never loads NodeTrail, so
-- the sub-toggle reads off here — exactly the "diagnostics with skinning
-- off" case.
clearChat()
local okOff = pcall(SlashCmdList.MIGHTIEPACK, "skindiag dump")
check(okOff, "/mp skindiag dump while skinning is off does not error")
local offText = chatText()
check(offText:find("skinning is off", 1, true) ~= nil,
  "off-state line says skinning is off (got: " .. offText:gsub("\n", " | ") .. ")")
check(offText:find("NodeTrail", 1, true) ~= nil,
  "off-state line names the NodeTrail sub-option it lives under")
check(offText:find("nothing recorded", 1, true) ~= nil,
  "off-state line says nothing is recorded")
check(P.enabled == true, "the diagnostic armed the probe (registration only, no DB write)")

local haveProbe = type(P) == "table" and type(P.frame) == "table"
check(haveProbe, "pkg.Skinning.Probe is live with an event frame")

onlyIf(haveProbe,
  "probe absent at this commit — registration/capture/dump checks skipped", function()
local frame = P.frame
check(P.enabled == true, "probe armed (the diagnostic started it)")
local before = #frames
P:Enable()
check(#frames == before, "Probe:Enable is idempotent (no second frame)")

-- Card test 1a: only the valid events are registered.
for _, e in ipairs(P.EVENTS) do
  if e == "LOOT_SLOT_CLEARED" then
    check(frame.events[e] == nil, "LOOT_SLOT_CLEARED NOT registered (the client refuses it)")
    check(P._events[e] == "invalid event", "invalid event recorded as the literal 'invalid event'")
  else
    check(frame.events[e] == true, "registered valid event: " .. e)
    check(P._events[e] == true, "event state true: " .. e)
  end
end
check(#P.EVENTS == 10, "the card's full event set is covered (10 events)")

-- ════════════════════════════════════════════════════════════════════
-- Section B: capture gating — nothing is recorded until toggled on
-- ════════════════════════════════════════════════════════════════════
local onEvent = frame:GetScript("OnEvent")
check(type(onEvent) == "function", "probe frame has an OnEvent handler")
local function fire(event, ...)
  onEvent(frame, event, ...)
end

loot = { { link = "|cffffffff|Hitem:1709::::::::1:::::::|h[Cave Rat Meat]|h|r", name = "Cave Rat Meat", qty = 2, quality = 0 } }
lootSource = "Creature-0-150-1234"
lootSourceName = "Cave Rat"
fire("LOOT_OPENED")
fire("UNIT_DIED", "target")
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-0", 99333, "Skinning")
check(#P.steps == 0, "capture off: no step recorded (got " .. #P.steps .. ")")
check(P.lastSkin == nil, "capture off: no skin cast recorded either")

clearChat()
SlashCmdList.MIGHTIEPACK("skindiag")
check(P.capturing == true, "/mp skindiag toggles capture on")
check(chatText():find("capture ON", 1, true) ~= nil, "toggle prints capture ON")
clearChat()
SlashCmdList.MIGHTIEPACK("skindiag")
check(P.capturing == false, "/mp skindiag toggles capture off again")
check(chatText():find("capture off", 1, true) ~= nil, "toggle prints capture off")
SlashCmdList.MIGHTIEPACK("skindiag") -- back on for the capture below
check(P.capturing == true, "capture on for the chain")

-- ════════════════════════════════════════════════════════════════════
-- Section C: the chain is captured in order (card test 1b)
-- ════════════════════════════════════════════════════════════════════
now = 2000
fire("PLAYER_ENTERING_WORLD")
now = 2001
fire("UNIT_DIED", "target")
now = 2002
loot = { { link = "|cffffffff|Hitem:1709::::::::1:::::::|h[Cave Rat Meat]|h|r", name = "Cave Rat Meat", qty = 2, quality = 0 } }
fire("LOOT_OPENED") -- window 1: ordinary corpse loot
now = 2003
loot = {}
fire("LOOT_SLOT_CLEARED", 1) -- handler fires even where the event is invalid
now = 2004
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 99333, "Skinning")
now = 2005
loot = {
  { link = "|cff1eff00|Hitem:1843::::::::1:::::::|h[Cave Rat Tusk]|h|r", name = "Cave Rat Tusk", qty = 1, quality = 1 },
  { link = "|cff1eff00|Hitem:1844::::::::2:::::::|h[Cave Rat Pelt]|h|r", name = "Cave Rat Pelt", qty = 3, quality = 1 },
}
fire("LOOT_OPENED") -- window 2: the skin (same corpse GUID, after a cast)
now = 2006
fire("LOOT_CLOSED")
now = 2007
fire("SKILL_LINES_CHANGED", 770)
now = 2008
lootSourceName = "Ratkin"
-- a non-death combat log event: must be dropped (the card says deaths only)
fire("COMBAT_LOG_EVENT_UNFILTERED", 8.0, "SWING",
  "Player-0-1", "Mightie", 1,
  "Creature-0-150-9999", "Ratkin", 2,
  "SpellId", 99999)
-- a death: captured
fire("COMBAT_LOG_EVENT_UNFILTERED", 9.0, "SPELL_DAMAGE",
  "Player-0-1", "Mightie", 1,
  "Creature-0-150-9999", "Ratkin", 2,
  "SpellId", 7384, "SpellName", "Rend", "targetDead")

local expect = {
  "PLAYER_ENTERING_WORLD",
  "UNIT_DIED",
  "LOOT_OPENED",
  "LOOT_SLOT_CLEARED",
  "UNIT_SPELLCAST_SUCCEEDED",
  "LOOT_OPENED",
  "LOOT_CLOSED",
  "SKILL_LINES_CHANGED",
  "COMBAT_LOG_EVENT_UNFILTERED",
}
check(#P.steps == #expect,
  "captured " .. #P.steps .. " steps, expected " .. #expect
  .. " (non-death COMBAT_LOG must be dropped)")
local orderOk = true
local got = {}
for i = 1, #expect do
  local s = P.steps[i]
  got[i] = s and s.event or "nil"
  if not s or s.event ~= expect[i] then orderOk = false end
end
check(orderOk, "steps recorded in fire order: " .. table.concat(got, ","))

-- ════════════════════════════════════════════════════════════════════
-- Section D: attribution (card test 2)
-- ════════════════════════════════════════════════════════════════════
local corpseGuid = "Creature-0-150-1234"
local w1 = P.steps[3]
local w2 = P.steps[6]
check(w1 and w1.kind == "corpse",
  "window 1 (no skin cast yet) is the ordinary corpse class, got " .. tostring(w1 and w1.kind))
check(w1 and w1.src == corpseGuid, "window 1 carries the corpse GUID")
check(w1 and w1.items and #w1.items == 1 and w1.items[1].id == 1709,
  "window 1 itemID parsed from the item link")
check(w1 and w1.items and w1.items[1].qty == 2 and w1.items[1].quality == 0,
  "window 1 quantity + quality recorded")
check(w2 and w2.kind == "skin",
  "window 2 (SAME corpse GUID, after a Skinning cast) is the skin class, got " .. tostring(w2 and w2.kind))
check(w2 and w2.src == corpseGuid,
  "skin attributed to the SAME corpse GUID (the creature), got " .. tostring(w2 and w2.src))
check(w2 and w2.items and #w2.items == 2,
  "skin window keeps every slot")
check(w2 and w2.items and w2.items[1].id == 1843 and w2.items[1].qty == 1,
  "skin slot 1: itemID + quantity")
check(w2 and w2.items and w2.items[2].id == 1844 and w2.items[2].qty == 3
  and w2.items[2].quality == 1, "skin slot 2: itemID + quantity + quality")
check(type(w2 and w2.items[1].link) == "string" and w2.items[1].link:find("item:1843", 1, true) ~= nil,
  "itemLink kept in the step record")
check(P.lastSkin and P.lastSkin.spellID == 99333,
  "the skinning cast's spellID is recorded (99333)")
check(P.lastKill and P.lastKill.guid == "Creature-0-150-9999",
  "the death's creature GUID is recorded")

-- a window on a DIFFERENT corpse, no cast of its own: ordinary class
now = 2010
loot = { { link = "|cff1eff00|Hitem:1843::::::::1:::::::|h[Ratkin Tusk]|h|r", name = "Ratkin Tusk", qty = 1, quality = 1 } }
lootSource = "Creature-0-150-9999"
fire("LOOT_OPENED")
local w3 = P.steps[#P.steps]
check(w3 and w3.kind == "corpse",
  "a loot window on another corpse (no cast) stays in the corpse class, got " .. tostring(w3 and w3.kind))
check(w3 and w3.src == "Creature-0-150-9999", "window 3 carries its own corpse GUID")

-- a cast older than SKIN_WINDOW must not classify the window as skin
now = 2101
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-2", 99333, "Skinning")
now = 2101 + P.SKIN_WINDOW + 9
loot = { { link = "|cffffffff|Hitem:1709::::::::1:::::::|h[Ratkin Meat]|h|r", name = "Ratkin Meat", qty = 1, quality = 0 } }
fire("LOOT_OPENED")
local w4 = P.steps[#P.steps]
check(w4 and w4.kind == "corpse",
  "a cast older than SKIN_WINDOW does not classify a window as skin, got " .. tostring(w4 and w4.kind))

-- a window with no resolvable source GUID is "unattributed", never
-- silently filed as ordinary corpse loot
now = 2200
loot = {}
fire("LOOT_OPENED")
local w5 = P.steps[#P.steps]
check(w5 and w5.kind == "unattributed",
  "a window with no resolvable source GUID is unattributed, got " .. tostring(w5 and w5.kind))

-- and zone/subzone + map position are on every step record
check(w2 and type(w2.detail) == "string" and w2.detail:find("z=Desolace", 1, true) ~= nil,
  "every step detail carries the zone (z=Desolace)")
check(w2 and w2.detail:find("572@", 1, true) ~= nil,
  "every step detail carries the map ID + player position")

-- ════════════════════════════════════════════════════════════════════
-- Section E: the dump (card test 1c) — ordered lines, <= 120 chars each
-- ════════════════════════════════════════════════════════════════════
clearChat()
local okD = pcall(SlashCmdList.MIGHTIEPACK, "skindiag dump")
check(okD, "/mp skindiag dump does not error")
local out = chatText()
check(out:find("capture on", 1, true) ~= nil, "dump reports the capture state")
check(out:find("LOOT_SLOT_CLEARED=invalid event", 1, true) ~= nil,
  "dump names the invalid event as 'invalid event'")
check(out:find("last skin cast: spell=99333", 1, true) ~= nil,
  "dump shows the last skinning cast")
check(out:find("last kill: Cave Rat", 1, true) ~= nil
  or out:find("last kill: Ratkin", 1, true) ~= nil,
  "dump shows the last kill")

-- steps print in capture order
local i1 = out:find("PLAYER_ENTERING_WORLD", 1, true)
local i2 = i1 and out:find("UNIT_DIED", i1, true)
local i3 = i2 and out:find("LOOT_OPENED", i2, true)
local i4 = i3 and out:find("k=skin-cast", i3, true)
local i5 = i4 and out:find("k=skin ", i4, true)
local i6 = i5 and out:find("LOOT_CLOSED", i5, true)
local i7 = i6 and out:find("SKILL_LINES_CHANGED", i6, true)
local i8 = i7 and out:find("COMBAT_LOG_EVENT_UNFILTERED", i7, true)
check(i1 and i2 and i3 and i4 and i5 and i6 and i7 and i8,
  "dump prints the captured steps in order")

local tooLong = 0
for i = 1, #chat do
  if #chat[i] > 120 then
    tooLong = tooLong + 1
    io.stderr:write("LONG(" .. #chat[i] .. "): " .. chat[i] .. "\n")
  end
end
check(tooLong == 0, "every dump line is <= 120 chars (got " .. tooLong .. " longer)")
end)

-- ════════════════════════════════════════════════════════════════════
-- Section F: the data-model formatter (card test 3)
-- ════════════════════════════════════════════════════════════════════
onlyIf(type(ns) == "table",
  "data-model formatter absent at this commit — baseline checks skipped", function()
local F = ns.FormatBaseline
check(type(F) == "function", "ns.FormatBaseline exists (the design's UI formatter)")
check(F({ rate = 0.75 }) == nil,
  "baseline WITHOUT a source is NOT rendered (nil)")
check(F({ rate = 0.75, source = "" }) == nil, "an empty source is not rendered")
check(F("75%") == nil, "a non-table baseline is not rendered")
check(F({ source = "wowhead" }) == nil, "a baseline without a rate is not rendered")
local withSource = F({ rate = 0.75, source = "wowhead", date = "2026-11-07" })
check(type(withSource) == "string", "a baseline WITH a source renders")
if type(withSource) == "string" then
  check(withSource:find("wowhead", 1, true) ~= nil, "rendered baseline names its source")
  check(withSource:find("2026-11-07", 1, true) ~= nil, "rendered baseline names its date")
  check(withSource:find("research", 1, true) ~= nil,
    "rendered baseline is visibly marked distinct from a personal count")
  check(withSource:find("75", 1, true) ~= nil, "rendered baseline shows the rate")
end

local PR = ns.PersonalRate
check(type(PR) == "function", "ns.PersonalRate exists (minimum-sample rule)")
check(ns.MIN_KILLS and ns.MIN_KILLS >= 5, "a minimum sample is declared (MIN_KILLS)")
check(PR(3, 4) == nil, "below the minimum sample: no rate is shown")
check(PR(10, 10) == 100, "at the minimum sample: 10/10 -> 100%")
check(PR(7, 20) == 35, "7 of 20 -> 35%")
check(PR(21, 20) == nil, "impossible samples (skins > kills) are not rendered")
end)

-- ════════════════════════════════════════════════════════════════════
-- Section G: /mp alias, usage line, no SavedVariables
-- ════════════════════════════════════════════════════════════════════
check(SLASH_MIGHTIEPACK3 == "/mp",
  "the /mp alias is registered (the card literally says /mp skindiag)")
check(type(SlashCmdList.MIGHTIEPACK) == "function",
  "/mp and /mpack share the same dispatcher")

clearChat()
SlashCmdList.MIGHTIEPACK("bogus")
check(chatText():find("/mp skindiag", 1, true) ~= nil,
  "usage lists the skindiag commands")

local onlyModules = true
for k in pairs(MightiePackDB or {}) do
  if k ~= "modules" then onlyModules = false end
end
check(onlyModules, "no new SavedVariables: the probe buffer is session-only")

-- ════════════════════════════════════════════════════════════════════
-- Section H: a client that accepts every event (no event refused)
-- ════════════════════════════════════════════════════════════════════
local savedUnknown = unknownEvents
unknownEvents = {}
local pkg2 = {}
local framesBefore = #frames
loadPackage(pkg2, "MightiePack2")
boot(pkg2, "MightiePack2")
check(pkg2.modules == nil or pkg2.modules.Skinning == nil,
  "all-events client: still no Skinning module entry")
check(type(pkg2.Skinning) == "table", "all-events client: skinning namespace loads")
if type(pkg2.Skinning) == "table" then
  pkg2.Skinning.Enable()
  local P2 = pkg2.Skinning.Probe
  check(P2 and P2.enabled == true, "all-events client: probe still enables")
  if P2 and P2.frame then
    check(#frames > framesBefore, "all-events client: a frame was created")
    check(P2.frame.events.LOOT_SLOT_CLEARED == true,
      "all-events client: every event registers when the client accepts it")
    local allTrue = true
    for _, e in ipairs(P2.EVENTS) do
      if P2._events[e] ~= true then allTrue = false end
    end
    check(allTrue, "all-events client: no event is wrongly marked invalid")
    clearChat()
    local ok2 = pcall(SlashCmdList.MIGHTIEPACK, "skindiag")
    check(ok2, "all-events client: /mp skindiag still does not error")
  end
else
  check(false, "all-events client: Skinning namespace missing")
end
unknownEvents = savedUnknown

-- ════════════════════════════════════════════════════════════════════
-- Section I: turning the sub-option off is immediate — no UI reload
-- (t_5507a0ba: the card asks whether the reload confirmation is genuinely
-- required; it is not, because P:Disable unregisters the probe's events)
-- Section H re-registered /mp for its second package, so this section
-- drives the LIVE dispatcher's package (MightiePack) — the same
-- namespace /mp skindiag resolves to.
-- ════════════════════════════════════════════════════════════════════
onlyIf(type(MightiePack and MightiePack.Skinning and MightiePack.Skinning.Disable) == "function",
  "ns.Disable absent at this commit — the no-reload-off checks are skipped", function()
  local reloadsBefore = reloads
  local livePkg = MightiePack
  check(type(livePkg) == "table" and type(livePkg.Skinning) == "table",
    "the live package exposes the skinning namespace")
  local liveNs = livePkg.Skinning
  local liveP = liveNs.Probe
  liveNs.Enable()
  check(liveP.enabled == true, "Enable arms the probe")
  if not liveP.capturing then liveP:Toggle() end
  check(liveP.capturing == true, "capture on before the disable")
  local offFrame = liveP.frame
  liveNs.Disable()
  check(liveP.enabled == false, "Disable turns the probe off")
  check(liveP.capturing == false, "Disable stops capture")
  check(#(liveP.steps or {}) == 0, "Disable drops the session buffer")
  local stillRegistered = false
  if offFrame and offFrame.events then
    for _, e in ipairs(liveP.EVENTS) do
      if offFrame.events[e] == true then stillRegistered = true end
    end
  end
  check(not stillRegistered, "Disable unregisters every event on the probe frame")
  check(reloads == reloadsBefore, "Disable does not ask for a reload")
  liveNs.Disable()
  check(liveP.enabled == false, "Disable is idempotent")
  -- and the diagnostic must still work after a disable
  clearChat()
  local okAfter = pcall(SlashCmdList.MIGHTIEPACK, "skindiag")
  check(okAfter, "skindiag still runs after the probe was disabled")
  check(liveP.enabled == true, "skindiag re-arms the probe after a disable")
  liveNs.Disable()
end)

-- ════════════════════════════════════════════════════════════════════
if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("skindiag_spec: ok")
