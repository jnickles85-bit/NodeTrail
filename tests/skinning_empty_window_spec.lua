-- skinning_empty_window_spec.lua — t_a2f44fb2
--
-- "it should still count the skin even if i dont get loot from the kill"
--
-- The measured defect (reporting laptop, client 1.60.1 build 70888, map 1411):
--
--   sk 31 UNIT_DIED   k=death unit=creature g=..475CDA
--   sk 33 UNIT_DIED   k=death unit=creature g=..0CC9AE
--   sk 34 LOOT_OPENED k=corpse g=..0CC9AE (from UNIT_DIED) i=-      <- empty corpse
--   sk 35 LOOT_CLOSED k=loot-closed prev=corpse                     <- 10 ms later
--   sk 36 UNIT_SPELLCAST_START     k=cast s=8613 who=player
--   sk 38 UNIT_SPELLCAST_START     k=cast s=8613 who=player
--   sk 39 UNIT_SPELLCAST_SUCCEEDED k=skin-cast s=8613 who=player
--   sk 41 LOOT_OPENED k=corpse g=..475CDA i=2934x1                  <- the SKIN window
--   ...
--   counts kills=8 corpse-windows=3 skin-windows=1 skin-casts=2
--   accounting: ... | lost kills=5 windows=0 casts=1
--
-- A corpse with nothing in it still gets a LOOT_OPENED/LOOT_CLOSED pair. The
-- recorder took ANY window as "the corpse the player just looted", so the cast
-- pinned to the empty ..0CC9AE: the empty corpse was marked skinned = true with
-- no items, and the REAL skin window on ..475CDA was filed as ordinary corpse
-- loot. One of two casts produced a skin window — `lost casts=1` is the addon
-- reporting this itself.
--
-- THE FIXTURE is that sequence, step for step (sk 31..43). The excerpt above
-- prints only the interesting lines; the steps it elides are reconstructed
-- here and each is commented. They are not free invention: the dump's own
-- totals pin them down.
--
--   * sk 32 — a second event for the corpse ..475CDA (a target-dead enrichment:
--     it fills the mob's NAME in and produces no step, which is why the excerpt
--     jumps to 33).
--   * sk 37 — a SKILL_LINES_CHANGED step between the two cast STARTs.
--   * sk 40 — the cast's UNIT_SPELLCAST_STOP (the documented 8613 triple is
--     START -> SUCCEEDED -> STOP).
--   * sk 42, sk 43 — the second successful cast the dump counts
--     (`skin-casts=2`) and the skin window it produced. No window may sit
--     between a cast and the window that identifies its corpse, so this cycle
--     opens with the cast: its corpse was never looted for ordinary drops and
--     never seen dying in this slice, which is exactly rule 3 below.
--
-- The numbers this slice reports are therefore, BEFORE the fix
-- (proven on the tag, see the RED run):
--   corpse-windows=3 skin-windows=0 casts=2 | lost casts=2
-- — i.e. BOTH casts lost their window: the first was stolen by the empty corpse
-- and the second was pinned to the corpse whose window the first one lost. The
-- dump quoted on the card reports 1 skin window and lost casts=1 over a whole
-- session (8 kills), because one of its cycles was well-behaved and fell
-- outside this excerpt. After the fix this slice reports:
--   corpse-windows=1 skin-windows=2 casts=2 | lost casts=0
--
-- What this spec pins (the card's four rules):
--   A. the replay is captured, and the empty window is a window of its own
--   B. rule 1 — a window with NO items is never a valid cast pin
--   C. rule 2 — the skin window's own GUID is authoritative: ..475CDA keeps
--      skinned=true and skinItems=2934x1 even though the last loot was an
--      empty window on ANOTHER corpse
--   D.      — ..0CC9AE keeps an empty corpse window and is NOT marked skinned
--   E. rule 3 — a skin on a corpse whose kill was never observed still counts
--   F. rule 4 — ordinary corpse loot never enters the skinning fields and skin
--      loot never enters corpseItems
--   G. the counts/accounting the dump reports (2 / 2 / 0)
--   H. an already-skinned corpse is never skinned a second time
--   I. the product rule itself: the skin counts with NO loot window at all
--
-- RED at 710b0ea, where the pin is taken from any window and the cast is never
-- claimed by the window that follows it.

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

-- ── client stub (the shape skinning_recorder_spec uses) ─────────────
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
GetSpellInfo = function(id) return ({ [2366] = "Herb Gathering" })[id] end
C_Map = {
  GetBestMapForUnit = function() return 1411 end,
  GetPlayerMapPosition = function()
    return { GetXY = function() return 0.4871, 0.3125 end }
  end,
}
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
  "Modules/NodeTrail/Config.lua",
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

local ns = pkg.Skinning
local P = type(ns) == "table" and ns.Probe or nil
local R = type(ns) == "table" and ns.Recorder or nil
check(type(P) == "table", "probe loaded")
check(type(R) == "table", "recorder loaded")

onlyIf(type(P) == "table" and type(R) == "table",
  "probe or recorder missing at this commit — the replay is skipped",
  function()
  pkg.NodeTrail.SetSkinningEnabled(true)
  pkg.Skinning.Enable()
  check(P.capturing == true, "capture on")
  local frame = P.frame
  local onEvent = frame:GetScript("OnEvent")
  local function fire(event, ...) onEvent(frame, event, ...) end

  -- the two corpses of the dump, by their printed suffixes and creature entry
  local A = "Creature-0-7072-1-48-3124-0000475CDA"   -- sk 31  ..475CDA
  local B = "Creature-0-7072-1-48-3124-00000CC9AE"   -- sk 33  ..0CC9AE
  -- the corpse of the second cast's cycle, whose death is outside this slice
  local X = "Creature-0-7072-1-48-3124-0000B4A5F9"
  local CORPSE_ITEM = "|cffffffff|Hitem:7100::::::::1:::::::|h[Scorpid Blood]|h|r"
  local SKIN_2934 = "|cff1eff00|Hitem:2934::::::::1:::::::|h[Ruined Leather Scraps]|h|r"
  local SKIN_2318 = "|cffffffff|Hitem:2318::::::::1:::::::|h[Light Leather]|h|r"

  -- ══════════════════════════════════════════════════════════════════
  -- A. the replay (sk 31..43)
  -- ══════════════════════════════════════════════════════════════════
  loot, lootSource, lootSourceName = {}, nil, nil
  now = 1000.00
  fire("UNIT_DIED", A)                       -- sk 31
  targetGuid, targetName = A, "Scorpid Worker"
  now = 1001.00
  fire("PLAYER_TARGET_CHANGED")              -- sk 32: enrich the name only
  now = 1006.00
  fire("UNIT_DIED", B)                       -- sk 33
  -- sk 34: the corpse window of ..0CC9AE, NO items, and the client hands back
  -- no source GUID at all (the dump's "(from UNIT_DIED)")
  loot, lootSource, lootSourceName = {}, nil, "Scorpid Worker"
  now = 1008.00
  fire("LOOT_OPENED")
  now = 1008.01
  fire("LOOT_CLOSED")                        -- sk 35, ten milliseconds later
  now = 1010.00
  fire("UNIT_SPELLCAST_START", "player", "CastBar-1B595C", 8613, "CastBar-1B595C")  -- sk 36
  now = 1011.00
  fire("SKILL_LINES_CHANGED")                -- sk 37 (elided in the excerpt)
  now = 1013.00
  fire("UNIT_SPELLCAST_START", "player", "CastBar-1B595C", 8613, "CastBar-1B595C")  -- sk 38
  now = 1013.50
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "CastBar-1B595C", 8613, "CastBar-1B595C") -- sk 39
  -- what THIS cast was pinned to, sampled before anything else happens: the
  -- only window before it is the empty corpse window of ..0CC9AE
  local pinAfterFirstCast = P.lastSkin and P.lastSkin.guid
  now = 1014.00
  fire("UNIT_SPELLCAST_STOP", "player", "CastBar-1B595C", 8613, "CastBar-1B595C") -- sk 40
  -- sk 41: THE SKIN WINDOW — the corpse the cast was actually applied to
  loot = { { link = SKIN_2934, name = "Ruined Leather Scraps", qty = 1, quality = 1 } }
  lootSource, lootSourceName = A, "Scorpid Worker"
  now = 1015.00
  fire("LOOT_OPENED")
  loot = {}
  now = 1015.50
  fire("LOOT_CLOSED")
  -- sk 42/43: the second skinning cast (its START is not one of the lines the
  -- excerpt prints) and the window it produced
  now = 1016.00
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "CastBar-1B595C", 8613, "CastBar-1B595C")
  loot = { { link = SKIN_2318, name = "Light Leather", qty = 1, quality = 1 } }
  lootSource, lootSourceName = X, "Scorpid Worker"
  now = 1016.50
  fire("LOOT_OPENED")
  loot = {}
  now = 1017.00
  fire("LOOT_CLOSED")

  check(#P.steps > 0, "the replay was captured, got " .. #P.steps .. " steps")

  local opens, kills, casts = {}, 0, 0
  for _, s in ipairs(P.steps) do
    if s.event == "LOOT_OPENED" then opens[#opens + 1] = s end
    if s.event == "UNIT_DIED" then kills = kills + 1 end
    if s.event == "UNIT_SPELLCAST_SUCCEEDED" then casts = casts + 1 end
  end
  check(kills == 2, "two deaths in the slice, got " .. kills)
  check(casts == 2, "two successful 8613 casts in the slice, got " .. casts)
  check(#opens == 3, "three loot windows in the slice, got " .. #opens)

  local store = select(1, R:Store())
  check(type(store) == "table", "the recorder has an active store")
  local recA = store and store.records and store.records[A]
  local recB = store and store.records and store.records[B]
  local recX = store and store.records and store.records[X]
  check(type(recA) == "table", "a record exists for the skinned corpse ..475CDA")
  check(type(recB) == "table", "a record exists for the empty corpse ..0CC9AE")

  -- B. rule 1: a window with NO items is never a valid cast pin
  -- The empty window opened BEFORE the casts, so what the cast was pinned to is
  -- decided by that window alone. Pre-fix, the pin is ..0CC9AE (and the empty
  -- corpse is then marked skinned with no items).
  check(P.lastSkin ~= nil, "the successful cast was recorded by the probe")
  check(pinAfterFirstCast == nil,
    "an empty corpse window pins nothing: the cast is not pinned to "
    .. tostring(pinAfterFirstCast))
  check(P.lastSkin and P.lastSkin.guid == nil,
    "and the second cast is not pinned by the skin window it followed, got "
    .. tostring(P.lastSkin and P.lastSkin.guid))

  -- the two windows the dump names, in order: the empty corpse window, then the
  -- window that follows the cast
  check(opens[1] and opens[1].kind == "corpse",
    "sk 34 (no items) is an ordinary corpse window, got "
    .. tostring(opens[1] and opens[1].kind))
  check(opens[1] and opens[1].src == B,
    "sk 34 belongs to ..0CC9AE, got " .. tostring(opens[1] and opens[1].src))
  check(opens[2] and opens[2].kind == "skin",
    "sk 41 is the SKIN window once the cast is not stolen by the empty corpse, got k="
    .. tostring(opens[2] and opens[2].kind))
  check(opens[2] and opens[2].src == A,
    "sk 41 is the skin window of ..475CDA, got " .. tostring(opens[2] and opens[2].src))
  check(opens[3] and opens[3].kind == "skin",
    "sk 43 is the second cast's skin window, got k="
    .. tostring(opens[3] and opens[3].kind))

  -- C. rule 2: the skin window's own GUID is authoritative
  if type(recA) == "table" then
    check(recA.skinned == true,
      "..475CDA IS skinned: a successful 8613 cast landed inside SKIN_WINDOW and "
      .. "the window on its own GUID came after it")
    check(recA.skinSpellID == 8613,
      "the skin is recorded as spell 8613, got " .. tostring(recA.skinSpellID))
    check(type(recA.skinItems) == "table" and #recA.skinItems == 1,
      "the skin list holds 1 item, got " .. tostring(recA.skinItems and #recA.skinItems))
    if type(recA.skinItems) == "table" and recA.skinItems[1] then
      check(recA.skinItems[1].itemID == 2934 and recA.skinItems[1].quantity == 1,
        "skin items are 2934x1, got " .. tostring(recA.skinItems[1].itemID) .. "x"
        .. tostring(recA.skinItems[1].quantity))
    end
    check(recA.skinWindowAt == 1015.00,
      "the skin window time is sk 41, got " .. tostring(recA.skinWindowAt))
  end

  -- D. ..0CC9AE keeps its own empty window and is NOT skinned
  if type(recB) == "table" then
    check((recB.corpseLootOpens or 0) == 1,
      "..0CC9AE keeps its one corpse window, got " .. tostring(recB.corpseLootOpens))
    check(type(recB.corpseItems) == "table" and #recB.corpseItems == 0,
      "the empty corpse window holds no items, got "
      .. tostring(recB.corpseItems and #recB.corpseItems))
    check(recB.skinned ~= true,
      "..0CC9AE was never skinned (nothing was cast on it): skinned="
      .. tostring(recB.skinned))
    check(type(recB.skinItems) == "table" and #recB.skinItems == 0,
      "and it owns no skin loot, got "
      .. tostring(recB.skinItems and #recB.skinItems))
  end

  -- E. rule 3: a skin on a corpse whose kill was never observed still counts
  check(type(recX) == "table",
    "the second skin window's corpse has a record (RecordFor created it)")
  if type(recX) == "table" then
    check(recX.killObserved == false,
      "its death was not observed in this slice: killObserved stays false")
    check(recX.skinned == true, "but the skin still counts: skinned=true")
    check(type(recX.skinItems) == "table" and #recX.skinItems == 1,
      "its skin list holds the window's item, got "
      .. tostring(recX.skinItems and #recX.skinItems))
  end

  -- F. rule 4: the two streams stay separate — skin loot is never in a corpse
  -- list, and a corpse window never contributes to a skin list
  if type(recA) == "table" then
    check(type(recA.corpseItems) == "table" and #recA.corpseItems == 0,
      "skin loot never enters corpseItems (..475CDA corpse list is empty, got "
      .. tostring(recA.corpseItems and #recA.corpseItems) .. ")")
  end
  if type(recX) == "table" then
    check(type(recX.corpseItems) == "table" and #recX.corpseItems == 0,
      "and the second skin window's corpse has no corpse list either, got "
      .. tostring(recX.corpseItems and #recX.corpseItems))
    check(recX.skinItems and recX.skinItems[1]
      and recX.skinItems[1].itemID == 2318,
      "the skin list holds the skin item 2318")
  end
  for guid, rec in pairs(store.records or {}) do
    for _, it in ipairs(type(rec.corpseItems) == "table" and rec.corpseItems or {}) do
      check(it.itemID ~= 2934 and it.itemID ~= 2318,
        "no skinning item (" .. tostring(it.itemID) .. ") appears in a corpse list ("
        .. tostring(guid) .. ")")
    end
  end

  -- G. the counts the dump reports
  local c = store.counts
  check(c.kills == 2, "kills=2, got " .. tostring(c.kills))
  check(c.corpseWindows == 1,
    "corpse-windows=1 (only the empty ..0CC9AE window is ordinary corpse loot), got "
    .. tostring(c.corpseWindows))
  check(c.skinWindows == 2,
    "skin-windows=2 (..475CDA and the second cast's), got " .. tostring(c.skinWindows))
  check(c.skinCasts == 2, "skin-casts=2, got " .. tostring(c.skinCasts))
  local acct = R:Accounting(store)
  check(acct.castsNoWindow == 0,
    "lost casts=0: every successful cast produced its skin window, got "
    .. tostring(acct.castsNoWindow))
  check(acct.unattributedWindows == 0,
    "no window went unattributed, got " .. tostring(acct.unattributedWindows))
  local line = R:AccountingLine(store)
  check(line:find("skin-windows=2", 1, true) ~= nil, "accounting line: " .. line)
  check(line:find("casts=2 | lost kills=1 windows=0 casts=0", 1, true) ~= nil,
    "accounting line reconciles with lost casts=0: " .. line)

  -- the same numbers through the dump, the surface the player reads
  for i = #chat, 1, -1 do chat[i] = nil end
  SlashCmdList.MIGHTIEPACK("skindiag dump")
  local out = table.concat(chat, "\n")
  check(out:find("counts kills=2 corpse-windows=1 skin-windows=2 skin-casts=2", 1, true) ~= nil,
    "the dump counts line reports 2 casts / 2 skin windows: " .. out:gsub("\n", " | "))
  check(out:find("casts=2 | lost kills=1 windows=0 casts=0", 1, true) ~= nil,
    "the dump accounting line reports lost casts=0")
  check(out:find("skin items: 2318x1", 1, true) ~= nil,
    "the dump shows the second cast's skin items")
  check(out:find("skinning cast: 8613 ok", 1, true) ~= nil,
    "the corpse the second cast claimed is shown as skinned by 8613")
  check(out:find("corpse items: 2934", 1, true) == nil,
    "no corpse-items line carries the skinning item: " .. out:gsub("\n", " | "))
  check(out:find("skin items: 7100", 1, true) == nil,
    "no skin-items line carries a corpse item: " .. out:gsub("\n", " | "))
  local tooLong = 0
  for i = 1, #chat do
    if #chat[i] > 120 then tooLong = tooLong + 1 end
  end
  check(tooLong == 0, "every dump line is <= 120 chars (got " .. tooLong .. " longer)")

  -- H. an already-skinned corpse is never skinned a second time
  local Z = "Creature-0-7072-1-48-3124-0000C0FFEE"
  now = 2000.00
  fire("UNIT_DIED", Z)
  loot, lootSource, lootSourceName = {}, Z, "Scorpid Worker"
  now = 2001.00
  fire("LOOT_OPENED")                    -- empty: cannot pin the cast either
  now = 2001.50
  fire("LOOT_CLOSED")
  now = 2002.00
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "CastBar-1B595C", 8613, "CastBar-1B595C")
  local skinItemsBefore = recA and type(recA.skinItems) == "table" and #recA.skinItems or 0
  loot = { { link = CORPSE_ITEM, name = "Scorpid Blood", qty = 1, quality = 0 } }
  lootSource, lootSourceName = A, "Scorpid Worker"
  now = 2003.00
  fire("LOOT_OPENED")                    -- on the corpse that is ALREADY skinned
  local guardOpen = P.steps[#P.steps]
  check(guardOpen and guardOpen.kind == "corpse",
    "a window on an already-skinned corpse is corpse loot, never a second skin, got k="
    .. tostring(guardOpen and guardOpen.kind))
  check(recA and type(recA.skinItems) == "table" and #recA.skinItems == skinItemsBefore,
    "and it adds nothing to that corpse's skin list")
  now = 2003.50
  fire("LOOT_CLOSED")

  -- I. the product rule itself: the skin counts even with NO loot window at all
  local W = "Creature-0-7072-1-48-3124-0000D15EA5"
  now = 3000.00
  fire("UNIT_DIED", W)
  loot = { { link = CORPSE_ITEM, name = "Scorpid Blood", qty = 1, quality = 0 } }
  lootSource, lootSourceName = W, "Scorpid Worker"
  now = 3001.00
  fire("LOOT_OPENED")                    -- a real corpse window: this CAN pin
  loot = {}
  now = 3001.50
  fire("LOOT_CLOSED")
  now = 3002.00
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "CastBar-1B595C", 8613, "CastBar-1B595C")
  local recW = store.records[W]
  check(type(recW) == "table", "the corpse has a record")
  check(recW and recW.skinned == true,
    "'it should still count the skin even if i dont get loot from the kill': "
    .. "skinned=" .. tostring(recW and recW.skinned))
  check(recW and type(recW.skinItems) == "table" and #recW.skinItems == 0,
    "and the skin list is honestly empty (no window was ever shown)")
  -- the same corpse, when the client DOES open the skin window: one record,
  -- two separate lists, the corpse item and the skinning item never mixed
  loot = { { link = SKIN_2318, name = "Light Leather", qty = 1, quality = 1 } }
  lootSource, lootSourceName = W, "Scorpid Worker"
  now = 3003.00
  fire("LOOT_OPENED")
  check(recW and type(recW.corpseItems) == "table" and #recW.corpseItems == 1
    and recW.corpseItems[1].itemID == 7100,
    "the corpse list holds the corpse item only")
  check(recW and type(recW.skinItems) == "table" and #recW.skinItems == 1
    and recW.skinItems[1].itemID == 2318,
    "the skin list holds the skinning item only")
  check(recW and recW.corpseItems ~= recW.skinItems,
    "the two lists are distinct tables on one record")
  now = 3003.50
  fire("LOOT_CLOSED")
  end)

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("skinning_empty_window_spec: ok")
