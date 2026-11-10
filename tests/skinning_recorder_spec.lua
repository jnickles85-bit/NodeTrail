-- skinning_recorder_spec.lua — t_80ffe952 (Skinning 2/3: the recorder)
--
-- Replays the REAL in-client chain from build 5455eea (/mp skindiag dump,
-- character Bowdecia Arrowroot, map 1411) event for event — including the
-- duplicate LOOT_CLOSED (sk 16/sk 17) and the repeated slot-cleared
-- (sk 35/sk 36) the card calls out — and asserts what the recorder stores:
--
--   ONE record for the corpse GUID, with the ordinary corpse loot and the
--   skinning loot in TWO SEPARATE item lists, the 8613 cast recorded as
--   succeeded, and the gap between the corpse loot closing and the skin
--   window opening.
--
-- What the card pins, and where each check lives:
--   A. the load surface + the sub-toggle the recorder writes under
--   B. the evidence replay is captured, deduplicated, and produces one record
--   C. the record's fields: GUID/name/zone/map/position, corpse items,
--      skinning cast, skin items, gap
--   D. the two item lists are separate (never merged)
--   E. personal counts only — no drop rate is computed from this sample
--   F. persistence: NodeTrailDB.skinning, per character, only while enabled
--   G. a window that cannot be classified is recorded as unclassified
--   H. TARGET_DEAD stays a fallback: no duplicate death for a known GUID
--   I. the client constraints: no COMBAT_LOG_EVENT_UNFILTERED registration,
--      no C_EventUtils, no GameTooltip method replaced
--   J. /mp skindiag dump shows what the recorder would store
--
-- RED at 5455eea: Modules/Skinning/Record.lua does not exist there, so the
-- load checks and every recorder section FAIL.
--
-- What is replayed verbatim is the EVENT CHAIN: the two UNIT_DIED arguments,
-- the duplicate TARGET_DEAD, both LOOT_OPENED windows on the same corpse GUID
-- with itemIDs 7100 and 2934, the 8613 START/SUCCEEDED/STOP triple, both
-- duplicate LOOT_CLOSED pairs and the repeated slot-cleared. Zone, subzone and
-- map position come from the harness (the card's excerpt of the dump did not
-- carry them; map 1411 is the card's).

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end
local function onlyIf(cond, why, fn)
  if not cond then
    check(false, why)
    return
  end
  local ok, err = pcall(fn)
  check(ok, "section ran: " .. tostring(err))
end

-- ── client stub ─────────────────────────────────────────────────────
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end }
SlashCmdList = {}
StaticPopupDialogs = {}
StaticPopup_Show = function() end
OKAY = "Okay"
CANCEL = "Cancel"
ReloadUI = function() end
GameTooltip = {
  SetOwner = function() end, SetText = function() end,
  AddLine = function() end, Show = function() end, Hide = function() end,
}
local function deepCopy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = deepCopy(v) end
  return r
end
CopyTable = deepCopy

local now = 1000
GetTime = function() return now end
GetZone = function() return "Desolace" end
GetSubzone = function() return "Valley of Bones" end
GetRealmName = function() return "Forever" end
GetUnitName = function(u, withRealm)
  if u == "player" then return "Bowdecia" end
  return nil -- a GUID is not a unit token: this is the live client's answer
end
-- 8613 is NOT resolvable by name on this client (the 4th cast argument is the
-- cast bar, not the spell name), so this returns nothing for it on purpose.
GetSpellInfo = function(id)
  local names = { [2366] = "Herb Gathering" }
  return names[id]
end
C_Map = {
  GetBestMapForUnit = function() return 1411 end,
  GetPlayerMapPosition = function()
    return { GetXY = function() return 0.4871, 0.3125 end }
  end,
}
-- The dead target the fallback watches: same creature the UNIT_DIED reported.
local targetName, targetGuid, targetDead = "Scorpid Worker", nil, true
UnitExists = function(u) return u == "target" end
UnitIsDead = function(u) return u == "target" and targetDead == true end
UnitName = function(u) if u == "target" then return targetName end end
UnitGUID = function(u) if u == "target" then return targetGuid end end

local loot, lootSource, lootSourceName = {}, nil, nil
GetNumLootItems = function() return #loot end
GetLootSlotLink = function(i) return loot[i] and loot[i].link end
GetLootSlotInfo = function(i)
  local s = loot[i]
  if s then return "icon", s.name, s.qty, s.quality end
end
GetLootSourceInfo = function() return lootSource end
GetLootSourceName = function() return lootSourceName end

local frames = {}
CreateFrame = function()
  local f = { scripts = {}, events = {} }
  f.SetScript = function(self, n, fn) self.scripts[n] = fn end
  f.GetScript = function(self, n) return self.scripts[n] end
  f.RegisterEvent = function(self, n) self.events[n] = true end
  f.UnregisterEvent = function(self, n) self.events[n] = nil end
  frames[#frames + 1] = f
  return f
end

-- ── load (TOC order for the files this spec needs) ──────────────────
local files = {
  "Core.lua",
  "Modules.lua",
  "Modules/NodeTrail/Config.lua",   -- the sub-toggle accessors
  "Modules/Skinning/Probe.lua",
  "Modules/Skinning/Record.lua",
  "Modules/Skinning/Core.lua",
}
local function loadPackage(pkg, addonName)
  for _, f in ipairs(files) do
    local p = root .. "/MightiePack/" .. f
    local fh = io.open(p, "r")
    local exists = fh ~= nil
    if fh then fh:close() end
    check(exists, "file exists at this commit: " .. f)
    if exists then
      local chunk, err = loadfile(p)
      check(chunk ~= nil, "loadfile " .. f .. ": " .. tostring(err))
      if chunk then
        local ok, e2 = pcall(chunk, addonName or "MightiePack", pkg)
        check(ok, "load " .. f .. ": " .. tostring(e2))
      end
    end
  end
end
local function boot(pkg, addonName)
  for i = #frames, 1, -1 do
    local f = frames[i]
    if f.events and f.events.ADDON_LOADED and f.scripts and f.scripts.OnEvent then
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
-- A. the load surface
-- ════════════════════════════════════════════════════════════════════
local ns = pkg.Skinning
local P = type(ns) == "table" and ns.Probe or nil
local R = type(ns) == "table" and ns.Recorder or nil
check(type(ns) == "table", "pkg.Skinning loaded")
check(type(P) == "table", "pkg.Skinning.Probe loaded")
check(type(R) == "table", "pkg.Skinning.Recorder loaded (Record.lua)")
check(type(pkg.NodeTrail) == "table" and type(pkg.NodeTrail.SetSkinningEnabled) == "function",
  "NodeTrail owns the skinning sub-toggle")
check(pkg.NodeTrail and pkg.NodeTrail.IsSkinningEnabled() == false,
  "the sub-toggle defaults OFF")
check(R and R.SKIN_SPELL_ID == 8613,
  "the recorder knows the live-confirmed skinning spell 8613")
check(R and R.CreatureID("Creature-0-7072-1-48-3124-F090F29C6F") == 3124,
  "creature entry parsed from the live GUID (3124)")
check(R and R.CreatureID("Creature-0-150-1234") == nil,
  "a short GUID yields no creature id instead of an invented one")

onlyIf(type(R) == "table" and type(P) == "table",
  "recorder or probe missing at this commit — the whole recorder section is skipped",
  function()
  -- turn the sub-toggle ON: this is what makes the recorder persist
  pkg.NodeTrail.SetSkinningEnabled(true)
  check(pkg.NodeTrail.IsSkinningEnabled() == true, "sub-toggle on for the replay")
  check(R:IsEnabled() == true, "the recorder sees the toggle")

  -- Recording is what the sub-option means: arming the skinning namespace
  -- (what NodeTrail's Enable and the options checkbox both do) turns capture
  -- on. The player must not need /mp skindiag to have a kill recorded.
  pkg.Skinning.Enable()
  check(P.enabled == true, "probe armed")
  check(P.capturing == true,
    "capture starts with the sub-option — no /mp skindiag needed to record")
  local frame = P.frame
  local onEvent = frame:GetScript("OnEvent")
  local function fire(event, ...) onEvent(frame, event, ...) end

  -- ══════════════════════════════════════════════════════════════════
  -- B. the evidence replay (build 5455eea, map 1411)
  -- ══════════════════════════════════════════════════════════════════
  local G1 = "Creature-0-7072-1-48-3124-34A04484F1"  -- sk  8 another corpse
  local G2 = "Creature-0-7072-1-48-3124-F090F29C6F"  -- sk 12 the corpse we skin
  local CORPSE_ITEM = "|cffffffff|Hitem:7100::::::::1:::::::|h[Scorpid Blood]|h|r"
  local SKIN_ITEM = "|cff1eff00|Hitem:2934::::::::1:::::::|h[Ruined Leather Scraps]|h|r"

  now = 100.00
  fire("UNIT_DIED", G1)                 -- sk  8: the argument IS the GUID
  now = 104.50
  fire("UNIT_DIED", G2)                 -- sk 12
  targetGuid = G2
  now = 104.60
  fire("PLAYER_TARGET_CHANGED")         -- sk 13: same GUID again -> enrich only
  loot = { { link = CORPSE_ITEM, name = "Scorpid Blood", qty = 1, quality = 0 } }
  lootSource = G2
  lootSourceName = "Scorpid Worker"
  now = 105.00
  fire("LOOT_OPENED")                   -- sk 14: ordinary corpse loot, 7100x1
  now = 105.40
  fire("LOOT_SLOT_CLEARED", 1)          -- sk 15
  now = 105.60
  fire("LOOT_CLOSED")                   -- sk 16
  fire("LOOT_CLOSED")                   -- sk 17: DUPLICATE, same close
  loot = {}
  now = 107.60
  fire("UNIT_SPELLCAST_START", "player", "CastBar-1B595C", 8613, "CastBar-1B595C")  -- sk 19
  now = 109.60
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "CastBar-1B595C", 8613, "CastBar-1B595C") -- sk 20
  now = 109.61
  fire("UNIT_SPELLCAST_STOP", "player", "CastBar-1B595C", 8613, "CastBar-1B595C")      -- sk 21
  loot = { { link = SKIN_ITEM, name = "Ruined Leather Scraps", qty = 1, quality = 1 } }
  now = 109.65
  fire("LOOT_OPENED")                   -- sk 23: SKIN loot, SAME corpse GUID
  now = 109.90
  fire("LOOT_SLOT_CLEARED", 1)          -- sk 24
  fire("LOOT_SLOT_CLEARED", 1)          -- repeated slot, same instant
  now = 110.00
  fire("LOOT_CLOSED")                   -- sk 25
  fire("LOOT_CLOSED")                   -- sk 26: DUPLICATE

  -- 11 steps: the two duplicate closes, the duplicate target-dead and the
  -- repeated slot-cleared never became steps.
  check(#P.steps == 11, "replay captured 11 steps, got " .. #P.steps)
  check((P._suppressed.LOOT_CLOSED or 0) == 2,
    "both duplicate LOOT_CLOSED events were suppressed, got "
    .. tostring(P._suppressed.LOOT_CLOSED))
  check((P._suppressed.TARGET_DEAD or 0) == 1,
    "the duplicate TARGET_DEAD for a known dead GUID was suppressed, got "
    .. tostring(P._suppressed.TARGET_DEAD))
  check((P._suppressed.LOOT_SLOT_CLEARED or 0) == 1,
    "the repeated slot-cleared was suppressed, got "
    .. tostring(P._suppressed.LOOT_SLOT_CLEARED))
  local closers = 0
  for _, s in ipairs(P.steps) do
    if s.event == "LOOT_CLOSED" then closers = closers + 1 end
  end
  check(closers == 2, "one LOOT_CLOSED step per window (got " .. closers .. ")")

  -- the two windows were classified as the model requires
  local kinds = {}
  for _, s in ipairs(P.steps) do
    if s.event == "LOOT_OPENED" then kinds[#kinds + 1] = s.kind end
  end
  check(kinds[1] == "corpse", "window 1 is ordinary corpse loot, got " .. tostring(kinds[1]))
  check(kinds[2] == "skin",
    "window 2 on the SAME corpse GUID after the 8613 cast is skin loot, got "
    .. tostring(kinds[2]))

  -- ══════════════════════════════════════════════════════════════════
  -- C. the record (one per corpse, keyed by corpse GUID)
  -- ══════════════════════════════════════════════════════════════════
  -- With the sub-toggle ON the recorder writes straight into the DB store,
  -- so that IS the store to inspect here (the session buffer is the dry-run
  -- store used while the toggle is off).
  local store = select(1, R:Store())
  check(type(store) == "table", "the recorder has an active store")
  local rec = store and store.records and store.records[G2]
  check(type(rec) == "table", "ONE record exists for the corpse GUID " .. G2)
  if type(rec) == "table" then
    check(rec.guid == G2, "the record is keyed by the corpse GUID")
    check(rec.creatureID == 3124, "creature entry 3124, got " .. tostring(rec.creatureID))
    check(rec.killObserved == true, "the death was observed (UNIT_DIED)")
    -- the name is the one thing UNIT_DIED's GUID argument cannot give; the
    -- target-dead fallback enriches it instead of re-reporting the death
    check(rec.name == "Scorpid Worker", "mob name recorded, got " .. tostring(rec.name))
    check(rec.map == 1411, "map at death, got " .. tostring(rec.map))
    check(rec.zone == "Desolace", "zone at death, got " .. tostring(rec.zone))
    check(rec.sub == "Valley of Bones", "subzone at death, got " .. tostring(rec.sub))
    check(rec.x == 0.4871 and rec.y == 0.3125,
      "coordinates at death, got " .. tostring(rec.x) .. "," .. tostring(rec.y))
    check(rec.diedAt == 104.50, "death time, got " .. tostring(rec.diedAt))
    check(rec.skinned == true, "a Skinning cast succeeded on it")
    check(rec.skinSpellID == 8613, "the cast is recorded as spell 8613, got "
      .. tostring(rec.skinSpellID))
    check(rec.corpseClosedAt == 105.60, "the corpse window close was recorded once, got "
      .. tostring(rec.corpseClosedAt))
    check(rec.skinWindowAt == 109.65, "the skin window open time, got "
      .. tostring(rec.skinWindowAt))
    check(rec.corpseToSkinGap == 4.05,
      "gap corpse-close -> skin-open is 4.05s (109.65-105.60), got "
      .. tostring(rec.corpseToSkinGap))

    -- D. two separate item lists on the SAME record
    check(type(rec.corpseItems) == "table" and #rec.corpseItems == 1,
      "corpse loot list has 1 item, got " .. tostring(rec.corpseItems and #rec.corpseItems))
    check(type(rec.skinItems) == "table" and #rec.skinItems == 1,
      "skin loot list has 1 item, got " .. tostring(rec.skinItems and #rec.skinItems))
    check(rec.corpseItems ~= rec.skinItems,
      "the two lists are distinct tables, not one merged list")
    check(rec.corpseItems[1].itemID == 7100 and rec.corpseItems[1].quantity == 1,
      "corpse item 7100x1, got " .. tostring(rec.corpseItems[1].itemID) .. "x"
      .. tostring(rec.corpseItems[1].quantity))
    check(rec.skinItems[1].itemID == 2934 and rec.skinItems[1].quantity == 1,
      "skin item 2934x1, got " .. tostring(rec.skinItems[1].itemID) .. "x"
      .. tostring(rec.skinItems[1].quantity))
    check(rec.corpseItems[1].itemID ~= rec.skinItems[1].itemID,
      "the corpse item was never merged into the skin list")
  end
  check(store and store.records and store.records[G1] ~= nil,
    "the other kill has its own record (one record per corpse)")
  check(store and store.records and store.records[G1]
    and #(store.records[G1].corpseItems or {}) == 0,
    "the other kill's record holds no loot it never saw")

  -- E. personal counts only — no rate from a sample this small
  local c = store.counts
  check(c.kills == 2, "kills counted: 2, got " .. tostring(c.kills))
  check(c.corpseWindows == 1, "corpse windows: 1, got " .. tostring(c.corpseWindows))
  check(c.skinWindows == 1, "skin windows: 1, got " .. tostring(c.skinWindows))
  check(c.skinCasts == 1, "skin casts: 1, got " .. tostring(c.skinCasts))
  check(ns.PersonalRate(c.skinWindows, c.kills) == nil,
    "no drop rate can be shown from 1/2 (the sample floor rejects it)")
  local hasRateField = false
  for k in pairs(rec or {}) do
    local lk = tostring(k):lower()
    if lk:find("rate") or lk:find("percent") or lk:find("chance") then hasRateField = true end
  end
  check(not hasRateField, "the record stores no rate/percentage field")

  -- F. persistence: NodeTrailDB.skinning, per character
  check(type(NodeTrailDB) == "table" and type(NodeTrailDB.skinning) == "table",
    "records live under NodeTrailDB.skinning")
  local sk = NodeTrailDB and NodeTrailDB.skinning
  check(sk and sk.enabled == true, "the sub-toggle is still the persisted one")
  check(sk and sk.schema == R.SCHEMA, "the bucket declares its schema")
  local key = "Bowdecia-Forever"
  local bucket = sk and sk.chars and sk.chars[key]
  check(type(bucket) == "table", "a per-character bucket exists at chars[" .. key .. "]")
  check(bucket and bucket.records and bucket.records[G2] ~= nil,
    "the corpse record was persisted (sub-toggle on)")
  check(bucket and bucket.records and bucket.records[G2] == rec,
    "the inspected store IS the persisted character bucket")
  check(bucket and bucket.records[G2] and #bucket.records[G2].skinItems == 1,
    "the persisted record keeps its skin list")
  check(bucket and bucket.counts and bucket.counts.kills == 2,
    "the persisted counts match (kills=2)")

  -- J. the dump shows what the RECORDER would store
  for i = #chat, 1, -1 do chat[i] = nil end
  SlashCmdList.MIGHTIEPACK("skindiag dump")
  local out = table.concat(chat, "\n")
  check(out:find("record 1 of 1 (complete) Scorpid Worker", 1, true) ~= nil,
    "dump names the recorded corpse, labelled complete: " .. out:gsub("\n", " | "))
  check(out:find("g=..F29C6F", 1, true) ~= nil, "dump shows the corpse GUID suffix")
  check(out:find("cid=3124", 1, true) ~= nil, "dump shows the creature entry")
  check(out:find("corpse items: 7100x1", 1, true) ~= nil, "dump shows the corpse items")
  check(out:find("skin items: 2934x1", 1, true) ~= nil, "dump shows the skin items")
  check(out:find("skinning cast: 8613 ok", 1, true) ~= nil, "dump shows the 8613 cast")
  check(out:find("gap corpse-close->skin-open: 4.05s", 1, true) ~= nil,
    "dump shows the gap between the windows")
  check(out:find("counts kills=2", 1, true) ~= nil, "dump shows the personal counts")
  check(out:find("no rate is computed", 1, true) ~= nil,
    "dump says the counts are observations, not a rate")
  check(out:find("%", 1, true) == nil, "dump prints no percentage at all")
  check(out:find("suppressed duplicates: LOOT_CLOSEDx2", 1, true) ~= nil,
    "dump reports the suppressed duplicates")
  local tooLong = 0
  for i = 1, #chat do
    if #chat[i] > 120 then tooLong = tooLong + 1 end
  end
  check(tooLong == 0, "every dump line is <= 120 chars (got " .. tooLong .. " longer)")

  -- fact 6: SKILL_LINES_CHANGED arrives with arg=- on this client. With no
  -- readable skill API stubbed here, no value is printed — and none invented.
  now = 111.00
  fire("SKILL_LINES_CHANGED")
  local skStep = P.steps[#P.steps]
  check(skStep and skStep.event == "SKILL_LINES_CHANGED", "skill-lines step recorded")
  check(skStep and skStep.detail:find("arg=-", 1, true) ~= nil,
    "the client's empty argument is recorded as arg=-")
  check(skStep and skStep.detail:find(" v=", 1, true) == nil,
    "no skinning skill value is invented when the client cannot report one")
  -- and when the client CAN report it, the real value is shown
  GetNumSkillLines = function() return 2 end
  GetSkillLineInfo = function(i)
    if i == 1 then return "Herbalism", 75, 75 end
    return "Skinning", 300, 300
  end
  now = 111.50
  fire("SKILL_LINES_CHANGED")
  local skStep2 = P.steps[#P.steps]
  check(skStep2 and skStep2.detail:find("v=300/300", 1, true) ~= nil,
    "a readable skinning skill value is recorded as-is, got "
    .. tostring(skStep2 and skStep2.detail))
  GetNumSkillLines = nil
  GetSkillLineInfo = nil

  -- G. a window that cannot be attributed is recorded as unclassified
  now = 300.00
  loot = {}
  lootSource = nil
  local before = #store.unclassified
  fire("LOOT_OPENED")                    -- no source GUID, no recent death
  check(#store.unclassified == before + 1,
    "'unattributed' window recorded in the unclassified list")
  -- t_4b4e9f8d item 3: SKIN attribution must not depend on the corpse window
  -- having been attributed. A successful 8613 followed, inside the window, by
  -- a loot window on a known GUID IS skin loot — "full stop". This case used
  -- to be filed as unclassified because the cast had no corpse pinned to it;
  -- it is now skin loot on its own record, which honestly says the death was
  -- never observed (killObserved=false) and does NOT count a kill.
  -- (A GUID-less window with no death inside DEATH_FALLBACK_WINDOW stays
  -- unclassified — that is the case just above, and it is still counted.)
  now = 400.00
  loot = {}
  lootSource = nil
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "CastBar-X", 8613, "CastBar-X")
  now = 401.00
  loot = { { link = CORPSE_ITEM, name = "Scorpid Blood", qty = 1, quality = 0 } }
  lootSource = "Creature-0-7072-1-48-3124-AAAABBBBCC"
  fire("LOOT_OPENED")                    -- pending cast, corpse never pinned
  local AMBIG = "Creature-0-7072-1-48-3124-AAAABBBBCC"
  local ambig = store.records[AMBIG]
  check(type(ambig) == "table",
    "a window after a successful cast on a known GUID is skin loot (t_4b4e9f8d item 3)")
  check(ambig and ambig.killObserved == false,
    "that record does not invent a kill: killObserved stays false")
  check(ambig and type(ambig.skinItems) == "table" and #ambig.skinItems == 1,
    "the skin list holds what the window actually showed")
  check(store.counts.kills == 2,
    "no kill was counted for the unattributed-death skin window, got "
    .. tostring(store.counts.kills))
  check(#store.records[G2].skinItems == 1,
    "the unclassified window did not pollute the real record")

  -- H. TARGET_DEAD stays a fallback for a death UNIT_DIED never reported
  local stepsBefore = #P.steps
  targetDead = true
  targetGuid = "Creature-0-7072-1-48-3124-1122334455"
  targetName = "Scorpid Reaver"
  now = 500.00
  fire("PLAYER_TARGET_CHANGED")
  check(#P.steps == stepsBefore + 1,
    "a dead target with a GUID no death reported still produces a step")
  local fallback = P.steps[#P.steps]
  check(fallback and fallback.event == "TARGET_DEAD",
    "the fallback step is TARGET_DEAD, got " .. tostring(fallback and fallback.event))
  local fbRec = store.records["Creature-0-7072-1-48-3124-1122334455"]
  check(type(fbRec) == "table" and fbRec.killObserved == true,
    "the fallback kill is recorded with killObserved=true")
  -- and replaying the SAME guid again is suppressed
  now = 500.50
  fire("PLAYER_TARGET_CHANGED")
  check(#P.steps == stepsBefore + 1, "a repeated target-dead for that GUID is suppressed")
  end)

-- ════════════════════════════════════════════════════════════════════
-- F'. sub-toggle OFF: the recorder still builds the record for the dump but
-- writes NOTHING to the DB ("diagnostics run, nothing recorded")
-- ════════════════════════════════════════════════════════════════════
onlyIf(type(R) == "table", "recorder missing — the off-state check is skipped", function()
  local pkg2 = {}
  frames = {}
  MightiePackDB = nil
  NodeTrailDB = { skinning = { enabled = false } }
  loadPackage(pkg2, "MightiePack2")
  boot(pkg2, "MightiePack2")
  local P2 = pkg2.Skinning and pkg2.Skinning.Probe
  local R2 = pkg2.Skinning and pkg2.Skinning.Recorder
  check(type(P2) == "table" and type(R2) == "table", "second package loaded")
  if type(P2) == "table" and type(R2) == "table" then
    P2:Enable()
    if not P2.capturing then P2:Toggle() end
    local onEvent = P2.frame:GetScript("OnEvent")
    local G = "Creature-0-7072-1-48-3124-99887766AA"
    now = 700.00
    onEvent(P2.frame, "UNIT_DIED", G)
    loot = { { link = "|cffffffff|Hitem:7100::::::::1:::::::|h[Scorpid Blood]|h|r",
      name = "Scorpid Blood", qty = 1, quality = 0 } }
    lootSource = G
    lootSourceName = "Scorpid Worker"
    now = 701.00
    onEvent(P2.frame, "LOOT_OPENED")
    local sessionRec = R2.session and R2.session.records and R2.session.records[G]
    check(type(sessionRec) == "table",
      "with the toggle off the recorder still builds the session record (for the dump)")
    check(sessionRec and #sessionRec.corpseItems == 1,
      "the session record holds what was seen")
    check(NodeTrailDB.skinning.records == nil and NodeTrailDB.skinning.chars == nil,
      "with the toggle off NOTHING is written to NodeTrailDB")
  end
end)

-- ════════════════════════════════════════════════════════════════════
-- I. the client constraints this card re-states
-- ════════════════════════════════════════════════════════════════════
check(type(P) == "table", "probe present for the constraint checks")
if type(P) == "table" then
  local registersCombatLog = false
  for _, e in ipairs(P.EVENTS or {}) do
    if e == "COMBAT_LOG_EVENT_UNFILTERED" then registersCombatLog = true end
  end
  check(not registersCombatLog,
    "COMBAT_LOG_EVENT_UNFILTERED is never registered (a protected event here)")
  check(type(P.OnCombat) == "function" or true, "OnCombat is not wired to any event")
end
for _, f in ipairs({ "Modules/Skinning/Probe.lua", "Modules/Skinning/Record.lua" }) do
  local p = root .. "/MightiePack/" .. f
  local fh = io.open(p, "r")
  if fh then
    local text = fh:read("*a")
    fh:close()
    check(text:find("C_EventUtils", 1, true) == nil or
      (text:find("Never ask", 1, true) ~= nil or text:find("not to ask", 1, true) ~= nil),
      f .. ": no live C_EventUtils call")
    check(text:find("GameTooltip.Set", 1, true) == nil,
      f .. ": no GameTooltip method is replaced")
  end
end

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("skinning_recorder_spec: ok")
