-- skinning_items_spec.lua — t_67f26739
--
-- The live run at Razor Hill (32 kills) exposed two blockers and two small
-- defects in the skinning probe/recorder. This spec replays the run's own
-- dump — the 18-event SKILL_LINES_CHANGED burst, both item windows on the
-- corpse ..10B81C, the 8613 cast and the 2.77s gap — and pins exactly what
-- the card demands:
--
--   A. the record carries the items its windows carried. In the live run the
--      STEP TEXT had them and the RECORD said "none seen", because a late
--      re-read of an already-emptied window replaced the list:
--        sk 220 LOOT_OPENED k=corpse g=..10B81C i=5466x1,4867x1
--        sk 228 LOOT_OPENED k=skin   g=..10B81C i=2318x1
--        record ... corpse items: none seen (late read) / skin items: none seen
--      The window read now writes INTO the record on LOOT_OPENED, on every
--      LOOT_SLOT_CLEARED and once more at LOOT_CLOSED, and an observed item can
--      never be un-observed by a later read of the same window.
--   B. a run of identical consecutive SKILL_LINES_CHANGED events collapses to
--      ONE dump line with a repeat count, and the duplicates counter reports
--      the suppressed 17 (the card's 18-event burst).
--   C. money is never an item: the coin slot is counted separately, and no
--      item list (step or record) may carry the word `money`.
--   D. a cast's 4th argument on this client is a CAST-BAR FRAME name, not a
--      spell name: the dump shows the spell id and never `CastBar-...`.
--   E. a missing unit name prints `unknown`, never `?`.
--
-- RED at HEAD (aed27bc) on every one of those: the record loses both lists,
-- the burst costs 18 ring slots and no line says (x18), the step prints
-- `i=...,money`, `last skin cast: ... name=CastBar-...`, and `who=?`.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end
local function at(t, i)
  if type(t) ~= "table" then return {} end
  return t[i or 1] or {}
end
local function onlyIf(cond, why, fn)
  if not cond then
    check(false, why)
    return
  end
  local ok, err = pcall(fn)
  check(ok, "section ran: " .. tostring(err))
end

-- ── chat capture ─────────────────────────────────────────────────────
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end }
local function clearChat() for i = #chat, 1, -1 do chat[i] = nil end end
local function chatText() return table.concat(chat, "\n") end

-- ── client stub ─────────────────────────────────────────────────────
SlashCmdList = {}
StaticPopupDialogs = {}
StaticPopup_Show = function() end
OKAY, CANCEL = "Okay", "Cancel"
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

local now = 765670
GetTime = function() return now end
GetZone = function() return "Durotar" end
GetSubzone = function() return "Razor Hill" end
GetRealmName = function() return "Forever" end
GetUnitName = function(u)
  if u == "player" then return "MightieBarb" end
  return nil
end
-- 8613 is NOT resolvable by name on this client: the 4th cast argument is the
-- cast bar, and GetSpellInfo answers nothing for it (live, dump sk 20/sk 240).
GetSpellInfo = function(id) return nil end
C_Map = {
  GetBestMapForUnit = function() return 1411 end,
  GetPlayerMapPosition = function()
    return { GetXY = function() return 0.5432, 0.2710 end }
  end,
}
local targetName, targetGuid, targetDead = nil, nil, false
UnitExists = function(u) return u == "target" and targetGuid ~= nil end
UnitIsDead = function(u) return u == "target" and targetDead == true end
UnitName = function(u) if u == "target" then return targetName end end
UnitGUID = function(u) if u == "target" then return targetGuid end end

local loot, lootSource, lootSourceName = {}, nil, nil
GetNumLootItems = function() return #loot end
GetLootSlotLink = function(i) return loot[i] and loot[i].link end
GetLootSlotInfo = function(i)
  local s = loot[i]
  -- the live shape: icon, name, count (no quality value), so the step line
  -- reads exactly like the card's "i=5466x1,4867x1"
  if s then return "icon", s.name, s.qty end
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

-- ════════════════════════════════════════════════════════════════════
-- A. the load surface
-- ════════════════════════════════════════════════════════════════════
check(type(P) == "table", "probe loaded")
check(type(R) == "table", "recorder loaded")
check(type(P) == "table" and type(P.RereadWindow) == "function",
  "the probe can re-read the open loot window")
check(type(R) == "table" and type(R.SetWindowItems) == "function",
  "the recorder accepts a read of the open window")
check(type(R) == "table" and type(R.Describe) == "function",
  "the recorder renders its record for the dump")

-- the corpse GUIDs the live dump printed: ..ACBEF9 (GUID-less corpse window,
-- attributed from UNIT_DIED) and ..10B81C (cid 3125, both item windows)
local G1 = "Creature-0-4384-6-0-3124-0000ACBEF9"
local G2 = "Creature-0-4384-6-0-3125-000010B81C"
local CORPSE_ITEM1 = "|cffffffff|Hitem:5466::::::::1:::::::|h[Scorpid Scale]|h|r"
local CORPSE_ITEM2 = "|cffffffff|Hitem:4867::::::::1:::::::|h[Scorpid Venom]|h|r"
local SKIN_ITEM = "|cff1eff00|Hitem:2318::::::::1:::::::|h[Light Leather]|h|r"

local store, rec, out

onlyIf(type(P) == "table" and type(R) == "table",
  "probe or recorder missing — the replay is skipped",
  function()
  pkg.NodeTrail.SetSkinningEnabled(true)   -- the live run: sub-option ON
  pkg.Skinning.Enable()
  check(P.capturing == true, "capture on")
  local frame = P.frame
  local onEvent = frame:GetScript("OnEvent")
  local function fire(event, ...) onEvent(frame, event, ...) end

  -- ══════════════════════════════════════════════════════════════════
  -- B. the 18-event SKILL_LINES_CHANGED burst (sk 181..200, one timestamp)
  -- ══════════════════════════════════════════════════════════════════
  now = 765670.55
  for _ = 1, 18 do fire("SKILL_LINES_CHANGED") end
  check(#P.steps == 1,
    "18 identical SKILL_LINES_CHANGED events collapse to ONE ring slot, got "
    .. tostring(#P.steps))
  local burst = P.steps[1]
  check(burst and burst.event == "SKILL_LINES_CHANGED", "the burst is one skill-lines step")
  check(burst and type(burst.repeats) == "number" and burst.repeats == 18,
    "the collapsed step counts its repeats, got " .. tostring(burst and burst.repeats))
  check((P._suppressed.SKILL_LINES_CHANGED or 0) == 17,
    "17 duplicates are counted as suppressed, got "
    .. tostring(P._suppressed.SKILL_LINES_CHANGED))

  -- ══════════════════════════════════════════════════════════════════
  -- C. sk 201..208: the GUID-less corpse window and its skin window
  -- ══════════════════════════════════════════════════════════════════
  now = 765673.00
  fire("UNIT_DIED", G1)                     -- sk 201
  loot, lootSource, lootSourceName = {}, nil, "Clattering Scorpid"
  now = 765674.80
  fire("LOOT_OPENED")                       -- sk 202: no GUID, no items
  local open1 = P.steps[#P.steps]
  check(open1 and open1.detail:find("k=corpse", 1, true) ~= nil
    and open1.detail:find("(from UNIT_DIED)", 1, true) ~= nil,
    "the GUID-less corpse window is still attributed from the death: "
    .. tostring(open1 and open1.detail))
  now = 765674.90
  fire("LOOT_CLOSED")
  now = 765676.00
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "CastBar-80CD3B37C39E3787", 8613,
    "CastBar-80CD3B37C39E3787")            -- sk 208 cast, pinned to G1
  loot = { { link = SKIN_ITEM, name = "Light Leather", qty = 1, quality = 1 } }
  lootSource = G1
  now = 765677.20
  fire("LOOT_OPENED")                      -- sk 208: skin, g=..ACBEF9 i=2318x1
  local open2 = P.steps[#P.steps]
  check(open2 and open2.kind == "skin",
    "the skin window is still skin, got " .. tostring(open2 and open2.kind))
  check(open2 and open2.detail:find("i=2318x1", 1, true) ~= nil,
    "the skin window keeps its items on the line: " .. tostring(open2 and open2.detail))
  -- the player takes the hide: the window is empty from here on
  loot = {}
  now = 765677.30
  fire("LOOT_SLOT_CLEARED", 1)
  now = 765677.40
  fire("LOOT_CLOSED")

  -- ══════════════════════════════════════════════════════════════════
  -- D. sk 220..228: the corpse whose record lost its items
  -- ══════════════════════════════════════════════════════════════════
  now = 765700.00
  fire("UNIT_DIED", G2)
  loot = {
    { link = CORPSE_ITEM1, name = "Scorpid Scale", qty = 1, quality = 0 },
    { link = CORPSE_ITEM2, name = "Scorpid Venom", qty = 1, quality = 0 },
    -- the coin slot: no itemID (the client's money slot, never an item)
    { link = nil, name = "", qty = 57 },
  }
  lootSource, lootSourceName = G2, "Clattering Scorpid"
  now = 765701.50
  fire("LOOT_OPENED")                      -- sk 220
  local open3 = P.steps[#P.steps]
  check(open3 and open3.detail:find("g=..10B81C", 1, true) ~= nil,
    "the corpse window carries its GUID: " .. tostring(open3 and open3.detail))
  check(open3 and open3.detail:find("i=5466x1,4867x1", 1, true) ~= nil,
    "the corpse window's items are on the step line: " .. tostring(open3 and open3.detail))
  check(open3 and open3.detail:find("money", 1, true) == nil,
    "C: the coin slot is never in the item list: " .. tostring(open3 and open3.detail))
  check(open3 and open3.detail:find("coin=57", 1, true) ~= nil,
    "C: the coin is counted separately: " .. tostring(open3 and open3.detail))

  -- the player loots the corpse: each slot empties, the window reads less
  loot = { { link = CORPSE_ITEM2, name = "Scorpid Venom", qty = 1, quality = 0 },
    { link = nil, name = "", qty = 57 } }
  now = 765701.60
  fire("LOOT_SLOT_CLEARED", 1)             -- sk 221: one item left
  loot = { { link = nil, name = "", qty = 57 } }
  now = 765701.70
  fire("LOOT_SLOT_CLEARED", 2)             -- sk 222: the window is now empty
  loot = {}
  now = 765701.73
  fire("LOOT_CLOSED")                      -- sk 223: the close reads nothing

  now = 765704.30
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "CastBar-80CD3B37C39E3787", 8613,
    "CastBar-80CD3B37C39E3787")            -- sk 227 cast, pinned to G2
  loot = { { link = SKIN_ITEM, name = "Light Leather", qty = 1, quality = 1 } }
  lootSource = G2
  now = 765704.50
  fire("LOOT_OPENED")                      -- sk 228 = close + 2.77s
  loot = {}
  now = 765704.60
  fire("LOOT_SLOT_CLEARED", 1)
  now = 765704.70
  fire("LOOT_CLOSED")

  -- the card's other line: "k=cast s=75 who=?" — a cast whose unit the client
  -- did not name
  now = 765710.00
  fire("UNIT_SPELLCAST_START", nil, "cast-3", 75, nil)

  -- ══════════════════════════════════════════════════════════════════
  -- A'. the RECORD holds what its windows held
  -- ══════════════════════════════════════════════════════════════════
  store = select(1, R:Store())
  check(type(store) == "table", "the recorder has an active store")
  rec = store and store.records and store.records[G2]
  check(type(rec) == "table", "the ..10B81C corpse has a record")
  if type(rec) == "table" then
    check(rec.creatureID == 3125, "cid=3125, got " .. tostring(rec.creatureID))
    check(rec.killObserved == true, "the death was observed")
    check(type(rec.corpseItems) == "table" and #rec.corpseItems == 2,
      "the corpse list holds BOTH items its window carried, got "
      .. tostring(rec.corpseItems and #rec.corpseItems))
    check(at(rec.corpseItems).itemID == 5466 and at(rec.corpseItems).quantity == 1,
      "corpse item 5466x1 first, got " .. tostring(at(rec.corpseItems).itemID))
    check(at(rec.corpseItems, 2).itemID == 4867
      and at(rec.corpseItems, 2).quantity == 1,
      "corpse item 4867x1 second, got " .. tostring(at(rec.corpseItems, 2).itemID))
    check(type(rec.skinItems) == "table" and #rec.skinItems == 1,
      "the skin list holds its item, got " .. tostring(rec.skinItems and #rec.skinItems))
    check(at(rec.skinItems).itemID == 2318 and at(rec.skinItems).quantity == 1,
      "skin item 2318x1")
    check(rec.corpseToSkinGap == 2.77,
      "the gap corpse-close -> skin-open is 2.77s, got "
      .. tostring(rec.corpseToSkinGap))
    -- no item list anywhere on the record may carry the coin slot
    for _, it in ipairs(rec.corpseItems or {}) do
      check(it.itemID ~= nil and it.itemID > 0, "C: no id-less entry in the corpse list")
    end
    for _, it in ipairs(rec.skinItems or {}) do
      check(it.itemID ~= nil and it.itemID > 0, "C: no id-less entry in the skin list")
    end
  end
  local rec1 = store and store.records and store.records[G1]
  check(type(rec1) == "table" and at(rec1.skinItems).itemID == 2318,
    "the first corpse still keeps its skin item after the late empty read")
  check(type(rec1) == "table" and (rec1.corpseItems and #rec1.corpseItems or 0) == 0,
    "the GUID-less window really held nothing, so its corpse list is empty")

  -- ══════════════════════════════════════════════════════════════════
  -- E. the dump: the record quoted, one skill-lines line, no money, no
  --    cast-bar name, `unknown` instead of `?`
  -- ══════════════════════════════════════════════════════════════════
  clearChat()
  SlashCmdList.MIGHTIEPACK("skindiag dump")
  out = chatText()
  check(out:find("dump failed", 1, true) == nil, "the dump completed: " .. out)

  -- the card's record, now with its items. t_11fc0755 put the record's
  -- POSITION in the dump ahead of its name ("record 1 of 2 (complete) ..."), so
  -- the header is pinned from the label on; the name still follows our own text
  -- and the identity fields are unchanged.
  check(out:find("(complete) Clattering Scorpid g=..10B81C cid=3125 kill=UNIT_DIED", 1, true) ~= nil,
    "the record header is the card's: " .. out)
  check(out:find("corpse items: 5466x1,4867x1", 1, true) ~= nil,
    "THE RECORD SHOWS THE CORPSE ITEMS ITS WINDOW CARRIED: " .. out)
  check(out:find("skin items: 2318x1", 1, true) ~= nil,
    "THE RECORD SHOWS THE SKIN ITEMS ITS WINDOW CARRIED: " .. out)
  -- Scoped to the ..10B81C record: the dump now renders several records, and an
  -- older corpse whose window really was empty legitimately says `none seen`.
  -- What must never happen is THIS corpse being stored that way.
  local g2From = out:find("record 1 of 2 (complete) Clattering Scorpid g=..10B81C", 1, true)
  local g2Block = ""
  if g2From then
    local rest = out:sub(g2From)
    -- the block ends at the NEXT record header, or at the counts line
    local stop = rest:find("record %d+ of %d+ %(", 2)
    local stopCounts = rest:find("counts kills=", 1, true)
    if stopCounts and (not stop or stopCounts < stop) then stop = stopCounts end
    g2Block = stop and rest:sub(1, stop - 1) or rest
  end
  check(g2From ~= nil and g2Block:find("corpse items: none seen", 1, true) == nil,
    "no corpse of this run is stored as `none seen`: " .. out)
  check(out:find("skinning cast: 8613 ok", 1, true) ~= nil, "the cast is tied to the corpse")
  check(out:find("gap corpse-close->skin-open: 2.77s", 1, true) ~= nil,
    "the gap is shown: " .. out)

  -- B: ONE skill-lines line, with its repeat count, and the counter reports it
  local skLines = 0
  local skLine = nil
  for i = 1, #chat do
    if chat[i]:find("SKILL_LINES_CHANGED", 1, true) ~= nil
      and not chat[i]:find("suppressed duplicates", 1, true) then
      skLines = skLines + 1
      skLine = chat[i]
    end
  end
  check(skLines == 1,
    "B: the 18-event burst is ONE dump line, got " .. tostring(skLines))
  check(skLine ~= nil and skLine:find("(x18)", 1, true) ~= nil,
    "B: the collapsed line says how many it stands for: " .. tostring(skLine))
  check(out:find("suppressed duplicates:", 1, true) ~= nil
    and out:find("SKILL_LINES_CHANGEDx17", 1, true) ~= nil,
    "B: the duplicates counter includes the skill-line suppression: " .. out)

  -- C: no money anywhere in an item list
  for i = 1, #chat do
    local line = chat[i]
    if line:find("items: ", 1, true) ~= nil or line:find(" i=", 1, true) ~= nil
      or line:find("items+=", 1, true) ~= nil then
      check(line:find("money", 1, true) == nil,
        "C: no item list carries money: " .. line)
    end
  end
  check(out:find("coin=57", 1, true) ~= nil,
    "C: the coin is reported beside the items, not inside them: " .. out)

  -- D: the spell field shows the id and never the cast bar
  check(out:find("last skin cast: spell=8613", 1, true) ~= nil,
    "D: the last skin cast shows the spell id: " .. out)
  check(out:find("CastBar", 1, true) == nil,
    "D: a cast-bar frame name never reaches the dump: " .. out)

  -- E: a missing unit name says unknown
  check(out:find("who=unknown", 1, true) ~= nil,
    "E: a missing unit name prints `unknown`: " .. out)
  check(out:find("who=?", 1, true) == nil, "E: no `who=?` in the dump")
  check(out:find("spell=unknown", 1, true) == nil, "D: the spell field is a real id")

  -- the ring buffer is not eaten by the burst: the whole run fits
  check(#P.steps < P.MAX_STEPS,
    "the burst did not push real events out of the 120-slot ring, steps="
    .. tostring(#P.steps))

  -- every line still fits the chat cap
  local tooLong = 0
  for i = 1, #chat do
    if #chat[i] > 120 then
      tooLong = tooLong + 1
      io.stderr:write("LONG(" .. #chat[i] .. "): " .. chat[i] .. "\n")
    end
  end
  check(tooLong == 0, "every dump line is <= 120 chars (got " .. tooLong .. " longer)")

  -- The card asks for the resulting RECORD, quoted. With SKINNING_SPEC_QUOTE=1
  -- this spec prints it (the checks above are what make it true; this is the
  -- evidence line the handoff quotes).
  if os.getenv("SKINNING_SPEC_QUOTE") or os.getenv("SKINNING_SPEC_DUMP") then
    local inRec = os.getenv("SKINNING_SPEC_QUOTE") and not os.getenv("SKINNING_SPEC_DUMP")
    for i = 1, #chat do
      local line = chat[i]
      if not inRec then
        io.write(line .. "\n")
      else
        if line:find("record ", 1, true) then inRec = true end
        if inRec then
          if line:find("counts kills=", 1, true) then break end
          io.write(line .. "\n")
        end
      end
    end
  end
  end)

-- ════════════════════════════════════════════════════════════════════
-- F. a distinct argument or a later tick is NOT collapsed
-- ════════════════════════════════════════════════════════════════════
onlyIf(type(P) == "table" and type(P.RereadWindow) == "function",
  "probe missing — the collapse-scope checks are skipped", function()
  local pkg2 = {}
  frames = {}
  MightiePackDB = nil
  NodeTrailDB = nil
  loadPackage(pkg2, "MightiePack2")
  boot(pkg2, "MightiePack2")
  local P2 = pkg2.Skinning and pkg2.Skinning.Probe
  check(type(P2) == "table", "second package loaded")
  if type(P2) ~= "table" then return end
  pkg2.Skinning.Enable()
  local onEvent = P2.frame:GetScript("OnEvent")
  local function fire(event, ...) onEvent(P2.frame, event, ...) end

  now = 100
  fire("SKILL_LINES_CHANGED", 770)
  fire("SKILL_LINES_CHANGED", 770)   -- same tick, same argument -> collapsed
  check(#P2.steps == 1 and P2.steps[1].repeats == 2,
    "same argument on the same tick collapses, steps=" .. tostring(#P2.steps))
  fire("SKILL_LINES_CHANGED", 771)   -- same tick, DIFFERENT argument -> kept
  check(#P2.steps == 2,
    "a different argument is a different event, steps=" .. tostring(#P2.steps))
  now = 100 + P2.DUP_TICK + 0.01
  fire("SKILL_LINES_CHANGED", 771)   -- same argument, a later tick -> kept
  check(#P2.steps == 3,
    "a later tick is a new event, steps=" .. tostring(#P2.steps))
  check((P2._suppressed.SKILL_LINES_CHANGED or 0) == 1,
    "only the one duplicate is counted, got "
    .. tostring(P2._suppressed.SKILL_LINES_CHANGED))
end)

-- ════════════════════════════════════════════════════════════════════
-- G. the client constraints this card re-states
-- ════════════════════════════════════════════════════════════════════
check(type(P) == "table", "probe present for the constraint checks")
if type(P) == "table" then
  local registersCombatLog = false
  for _, e in ipairs(P.EVENTS or {}) do
    if e == "COMBAT_LOG_EVENT_UNFILTERED" then registersCombatLog = true end
  end
  check(not registersCombatLog,
    "COMBAT_LOG_EVENT_UNFILTERED is never registered (a protected event here)")
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
print("skinning_items_spec: ok")
