-- skinning_guardless_spec.lua — t_4b4e9f8d
--
-- The live run this spec replays, verbatim from the card (Razor Hill, installed
-- build c220ec7 / commit f783ab6, map from the same dump):
--
--   sk 168 759876.51 UNIT_DIED   g=..EF7D0D
--   sk 169 759878.38 LOOT_OPENED k=unattributed i=-            <- no GUID, no items
--   sk 170 759878.39 LOOT_CLOSED
--   sk 171 759879.09 UNIT_SPELLCAST_START s=8613
--   sk 172 759881.05 UNIT_SPELLCAST_SUCCEEDED k=skin-cast s=8613
--   sk 175 759881.30 LOOT_OPENED k=unclassified g=..EF7D0D i=2934x1   <- IS the skin window
--
-- The classification itself was right (the same sequence worked when the
-- corpse window carried a GUID); it collapsed on the GUID-less window and took
-- the skin window with it. This spec pins the five things the card requires:
--
--   A. the load surface and the new attribution contract
--   B. a GUID-less window is attributed from the most recent UNIT_DIED, and the
--      dump says which rule produced the GUID: "g=..EF7D0D (from UNIT_DIED)"
--   C. ONE corpse record, with the late-arriving corpse items AND the skin
--      items under the death's GUID (the skin window is skin because of the
--      cast, not because the corpse window was attributed)
--   D. items that populate after LOOT_OPENED are re-read on LOOT_SLOT_CLEARED
--      and again just before LOOT_CLOSED
--   E. names: `record unknown` / `last kill: unknown` — a GUID never stands in
--      a name field, and a SECRET name is still shown whole
--   F. the accounting line reconciles a run shaped exactly like the live one
--      (15 kills, 4 corpse windows, 5 skin windows, 11 casts)
--
-- RED at dc94343, where: Classify() answers "unattributed" for a GUID-less
-- window; the cast is pinned to lastLoot.src (nil) so the skin window is
-- "unclassified"; nothing re-reads the slots; Describe prints "record ?"; and
-- there is no accounting line at all.
--
-- What is replayed from the client is the EVENT CHAIN and the timestamps. The
-- corpse item (7100) is the corpse drop confirmed on this client in the
-- 5455eea dump — the Razor Hill excerpt shows the corpse window with "i=-" and
-- never shows what it held, so nothing here invents a different item.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end
-- an empty list must FAIL, not crash the section: this spec has to run to the
-- end on dc94343 so its failure count is the real gap, not the first abort
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

-- ════════════════════════════════════════════════════════════════════
-- The SECRET simulator (same model as skindiag_secret_spec): a value only
-- `issecretvalue` recognises, whose every read raises the client's message and
-- whose only legal use is being shown.
-- ════════════════════════════════════════════════════════════════════
local secretMT = {}
local function newSecret(payload)
  return setmetatable({ payload = payload }, secretMT)
end
local function isSimSecret(v)
  return type(v) == "table" and getmetatable(v) == secretMT
end
local function payloadOf(v)
  if isSimSecret(v) then return rawget(v, "payload") end
  if type(v) == "string" then return v end
  return "<?>"
end
local READ_OPS = {
  sub = "slice", format = "format", find = "search", gsub = "substitute",
  match = "match", lower = "read", upper = "read", rep = "repeat",
  byte = "read", gmatch = "search", len = "measure",
}
secretMT.__index = setmetatable({}, {
  __index = function(_, k)
    return function()
      error("attempt to " .. (READ_OPS[k] or "read")
        .. " a secret string value, while execution tainted by 'MightiePack'", 2)
    end
  end,
})
secretMT.__len = function()
  error("attempt to get length of a secret string value, while execution tainted by 'MightiePack'", 2)
end
secretMT.__tostring = function()
  error("attempt to convert a secret string value, while execution tainted by 'MightiePack'", 2)
end
secretMT.__concat = function(a, b)
  return newSecret(payloadOf(a) .. payloadOf(b))
end
secretMT.__eq = function(a, b)
  return payloadOf(a) == payloadOf(b)
end

issecretvalue = isSimSecret

-- ── chat capture ─────────────────────────────────────────────────────
local chat = {}
local function flatten(v)
  if isSimSecret(v) then return rawget(v, "payload") end
  if type(v) == "string" then return v end
  if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
  return "<" .. type(v) .. ">"
end
DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, m) chat[#chat + 1] = flatten(m) end,
}
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

local now = 1000
GetTime = function() return now end
GetZone = function() return "Durotar" end
GetSubzone = function() return "Razor Hill" end
GetRealmName = function() return "Forever" end
GetUnitName = function(u, withRealm)
  if u == "player" then return "MightieBarb" end
  return nil -- a GUID is not a unit token: this is the live client's answer
end
-- 8613 is NOT resolvable by name on this client (the 4th cast argument is the
-- cast bar), so this returns nothing for it on purpose.
GetSpellInfo = function(id) return nil end
C_Map = {
  GetBestMapForUnit = function() return 1411 end,
  GetPlayerMapPosition = function()
    return { GetXY = function() return 0.4871, 0.3125 end }
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
-- A. the load surface and the attribution contract
-- ════════════════════════════════════════════════════════════════════
check(type(P) == "table", "probe loaded")
check(type(R) == "table", "recorder loaded")
check(type(P) == "table" and type(P.Classify) == "function",
  "the probe classifies loot windows")
if type(P) == "table" and type(P.Classify) == "function" then
  check(type(P.DEATH_FALLBACK_WINDOW) == "number" and P.DEATH_FALLBACK_WINDOW > 0,
    "there is a BOUNDED fallback window for a GUID-less loot window, got "
    .. tostring(P.DEATH_FALLBACK_WINDOW))
  check(type(P.RecentDeath) == "function",
    "the probe can name the most recent death inside that window")
  check(type(P.RereadWindow) == "function",
    "the probe can re-read the open loot window")
  local kind, guid, rule = P:Classify(nil, 1000)
  check(kind == "unattributed" and guid == nil,
    "with no source GUID and no death in the window, nothing is invented: got k="
    .. tostring(kind) .. " g=" .. tostring(guid))
  check(type(rule) == "string", "the classifier names the rule it used")
end
if type(R) == "table" then
  check(type(R.SetWindowItems) == "function",
    "the recorder accepts a late read of the open window")
  check(type(R.AccountingLine) == "function",
    "the recorder produces the accounting line")
  check(type(R.DisplayName) == "function",
    "the recorder decides what a NAME field may print")
end

onlyIf(type(R) == "table" and type(P) == "table",
  "probe or recorder missing at this commit — the replay is skipped",
  function()
  pkg.NodeTrail.SetSkinningEnabled(true)
  pkg.Skinning.Enable()
  check(P.capturing == true, "capture on")
  local frame = P.frame
  local onEvent = frame:GetScript("OnEvent")
  local function fire(event, ...) onEvent(frame, event, ...) end

  -- ══════════════════════════════════════════════════════════════════
  -- B/C/D. the Razor Hill replay (the card's own timestamps)
  -- ══════════════════════════════════════════════════════════════════
  -- the GUID whose creature entry is 3099 (the live record said cid=3099) and
  -- whose suffix is ..EF7D0D, exactly as the dump printed it
  local G = "Creature-0-4384-6-0-3099-00001EF7D0D"
  local CORPSE_ITEM = "|cffffffff|Hitem:7100::::::::1:::::::|h[Scorpid Blood]|h|r"
  local SKIN_ITEM = "|cff1eff00|Hitem:2934::::::::1:::::::|h[Ruined Leather Scraps]|h|r"

  now = 759876.51
  fire("UNIT_DIED", G)                 -- sk 168: the argument IS the corpse GUID

  -- sk 169: the corpse window opens with NO GUID and NO items
  loot, lootSource, lootSourceName = {}, nil, nil
  now = 759878.38
  fire("LOOT_OPENED")

  local open1 = P.steps[#P.steps]
  check(open1 and open1.event == "LOOT_OPENED", "the GUID-less window was captured")
  check(open1 and open1.kind == "corpse",
    "a GUID-less window falls back to the most recent UNIT_DIED: k="
    .. tostring(open1 and open1.kind) .. " (the old code said 'unattributed')")
  check(open1 and open1.detail:find("g=..EF7D0D", 1, true) ~= nil,
    "the window is attributed to the death's GUID: " .. tostring(open1 and open1.detail))
  check(open1 and open1.detail:find("(from UNIT_DIED)", 1, true) ~= nil,
    "the dump says WHICH rule produced the GUID: " .. tostring(open1 and open1.detail))
  check(open1 and open1.detail:find("i=-", 1, true) ~= nil,
    "the open really carried no items (this is the late-fill case): "
    .. tostring(open1 and open1.detail))

  -- the client fills the slots: LOOT_SLOT_CLEARED is the moment to re-read.
  -- The live close was 0.01s after the open (sk 169 -> sk 170), so the slot is
  -- placed inside that gap — the card's own requirement that a late fill is
  -- recorded needs the frame in which it can be read.
  loot = { { link = CORPSE_ITEM, name = "Scorpid Blood", qty = 1, quality = 0 } }
  now = 759878.385
  fire("LOOT_SLOT_CLEARED", 1)
  local slot1 = P.steps[#P.steps]
  check(slot1 and slot1.event == "LOOT_SLOT_CLEARED", "slot-cleared captured")
  check(slot1 and slot1.detail:find("items+=7100x1", 1, true) ~= nil,
    "the slot-cleared re-read picked up the items the open did not have: "
    .. tostring(slot1 and slot1.detail))

  -- sk 170: the window closes (the live run closed it 0.01s after opening)
  now = 759878.39
  fire("LOOT_CLOSED")

  -- sk 171/172: the Skinning cast, by spell ID (the 4th argument is the bar)
  now = 759879.09
  fire("UNIT_SPELLCAST_START", "player", "CastBar-1B595C", 8613, "CastBar-1B595C")
  now = 759881.05
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "CastBar-1B595C", 8613, "CastBar-1B595C")

  -- sk 175: the skin window IS the skin window, on a known GUID, after 8613
  loot = { { link = SKIN_ITEM, name = "Ruined Leather Scraps", qty = 1, quality = 1 } }
  lootSource = G
  now = 759881.30
  fire("LOOT_OPENED")

  local open2 = P.steps[#P.steps]
  check(open2 and open2.event == "LOOT_OPENED", "the skin window was captured")
  check(open2 and open2.kind == "skin",
    "a successful 8613 followed by a loot window is SKIN loot, got k="
    .. tostring(open2 and open2.kind) .. " (the old code said 'unclassified')")
  check(open2 and open2.detail:find("i=2934x1", 1, true) ~= nil,
    "the skin window keeps its items on the line: " .. tostring(open2 and open2.detail))
  check(open2 and open2.detail:find("(from UNIT_DIED)", 1, true) == nil,
    "the skin window's GUID came from the loot source, not from the fallback")

  now = 759881.40
  fire("LOOT_SLOT_CLEARED", 1)
  now = 759881.50
  fire("LOOT_CLOSED")

  -- ── C. ONE record, keyed by the death's GUID ──────────────────────
  local store = select(1, R:Store())
  check(type(store) == "table", "the recorder has an active store")
  local rec = store and store.records and store.records[G]
  check(type(rec) == "table",
    "ONE corpse record exists, under the death's GUID " .. G)
  if type(rec) == "table" then
    check(rec.creatureID == 3099, "creature entry 3099, got " .. tostring(rec.creatureID))
    check(rec.killObserved == true, "the death was observed (UNIT_DIED)")
    check(rec.diedAt == 759876.51, "death time, got " .. tostring(rec.diedAt))
    check(rec.corpseLootOpens == 1,
      "one corpse window on the record, got " .. tostring(rec.corpseLootOpens))
    check(rec.skinned == true, "the 8613 cast was recorded against the corpse")
    check(rec.skinSpellID == 8613, "as spell 8613, got " .. tostring(rec.skinSpellID))
    check(rec.skinWindowAt == 759881.30,
      "the skin window open time, got " .. tostring(rec.skinWindowAt))
    check(rec.corpseClosedAt == 759878.39,
      "the corpse window close, got " .. tostring(rec.corpseClosedAt))
    check(rec.corpseToSkinGap == 2.91,
      "gap corpse-close -> skin-open is 2.91s (759881.30-759878.39), got "
      .. tostring(rec.corpseToSkinGap))

    -- D. the late corpse fill is IN the record (not "none seen")
    check(type(rec.corpseItems) == "table" and #rec.corpseItems == 1,
      "the corpse list holds the item the window filled in late, got "
      .. tostring(rec.corpseItems and #rec.corpseItems))
    check(at(rec.corpseItems).itemID == 7100
      and at(rec.corpseItems).quantity == 1,
      "corpse item 7100x1 (read on slot-cleared, not at the empty open)")

    -- C. the skin items are under the DEATH's GUID, on the same record
    check(type(rec.skinItems) == "table" and #rec.skinItems == 1,
      "the skin list holds what the skin window showed, got "
      .. tostring(rec.skinItems and #rec.skinItems))
    check(at(rec.skinItems).itemID == 2934
      and at(rec.skinItems).quantity == 1,
      "skin item 2934x1 on the death's record")
    check(rec.corpseItems ~= rec.skinItems,
      "the corpse and skin lists stay separate tables")
    check(at(rec.corpseItems).itemID ~= nil
      and at(rec.corpseItems).itemID ~= at(rec.skinItems).itemID,
      "the corpse item was never merged into the skin list, or the reverse")
  end
  check(store and store.records and #store.unclassified == 0,
    "nothing was left unattributed in this sequence, got "
    .. tostring(store and #store.unclassified))

  -- one kill, one corpse window, one skin window, one cast — all matched
  local c = store.counts
  check(c.kills == 1, "kills=1, got " .. tostring(c.kills))
  check(c.corpseWindows == 1, "corpse-windows=1, got " .. tostring(c.corpseWindows))
  check(c.skinWindows == 1, "skin-windows=1, got " .. tostring(c.skinWindows))
  check(c.skinCasts == 1, "skin-casts=1, got " .. tostring(c.skinCasts))

  -- ── E/F. the dump: names, the rule, and the accounting line ──────
  clearChat()
  SlashCmdList.MIGHTIEPACK("skindiag dump")
  local out = chatText()
  check(out:find("dump failed", 1, true) == nil, "the dump completed: " .. out)
  check(out:find("record unknown", 1, true) ~= nil,
    "with no name seen the record says `unknown` (never '?'): " .. out)
  check(out:find("record ?", 1, true) == nil, "the old `record ?` is gone")
  check(out:find("g=..EF7D0D", 1, true) ~= nil, "the record shows the GUID suffix")
  check(out:find("cid=3099", 1, true) ~= nil, "the record shows the creature entry")
  check(out:find("corpse items: 7100x1", 1, true) ~= nil,
    "the record shows the corpse item that arrived late: " .. out)
  check(out:find("(late read)", 1, true) ~= nil,
    "the dump says the corpse window was re-read")
  check(out:find("skin items: 2934x1", 1, true) ~= nil,
    "the record shows the skin items under the death's GUID")
  check(out:find("skinning cast: 8613 ok", 1, true) ~= nil, "the 8613 cast is shown")
  check(out:find("gap corpse-close->skin-open: 2.91s", 1, true) ~= nil,
    "the gap between the two windows is shown")
  check(out:find("last kill: unknown", 1, true) ~= nil,
    "`last kill` says unknown rather than falling back to the GUID: " .. out)
  check(out:find(G, 1, true) == nil,
    "the full GUID never stands in a name field (it would appear verbatim)")
  check(out:find("accounting: kills=1 corpse-windows=1 skin-windows=1 casts=1", 1, true) ~= nil,
    "the accounting line reconciles this run: " .. out)
  check(out:find("lost kills=0 windows=0 casts=0", 1, true) ~= nil,
    "and states that nothing was lost")

  -- ══════════════════════════════════════════════════════════════════
  -- D (second shape). items that only appear just BEFORE the close are
  -- still read: LOOT_CLOSED re-reads the window it is about to lose.
  -- ══════════════════════════════════════════════════════════════════
  local G2 = "Creature-0-4384-6-0-3124-0000AABBCCDD"
  loot, lootSource, lootSourceName = {}, nil, nil
  now = 760100.00
  fire("UNIT_DIED", G2)
  now = 760100.50
  fire("LOOT_OPENED")                  -- no GUID (falls back), no items
  local before = #P.steps
  loot = { { link = CORPSE_ITEM, name = "Scorpid Blood", qty = 2, quality = 0 } }
  now = 760101.00
  fire("LOOT_CLOSED")                  -- nothing was taken: the close re-reads
  local closeStep = P.steps[#P.steps]
  check(closeStep and closeStep.event == "LOOT_CLOSED", "the close was captured")
  check(closeStep and closeStep.detail:find("items-final=7100x2", 1, true) ~= nil,
    "the close re-read the window before losing it: "
    .. tostring(closeStep and closeStep.detail))
  local rec2 = store.records[G2]
  check(type(rec2) == "table" and at(rec2.corpseItems).itemID == 7100
    and at(rec2.corpseItems).quantity == 2,
    "the record holds what the client showed just before the close")
  check(#P.steps == before + 1, "the close produced exactly one step")

  -- ══════════════════════════════════════════════════════════════════
  -- E. a name that is really the GUID never reaches a name field
  -- ══════════════════════════════════════════════════════════════════
  local G3 = "Creature-0-4384-6-0-3124-000011223344"
  targetGuid, targetDead = G3, true
  targetName = G3                    -- the live failure: UnitName answers the GUID
  now = 761000.00
  fire("PLAYER_TARGET_CHANGED")
  local rec3 = store.records[G3]
  check(type(rec3) == "table", "the fallback kill was recorded")
  check(rec3 and rec3.name == nil,
    "a GUID offered as a name is not stored as one, got " .. tostring(rec3 and rec3.name))
  clearChat()
  SlashCmdList.MIGHTIEPACK("skindiag dump")
  local out3 = chatText()
  check(out3:find(G3, 1, true) == nil,
    "the GUID is printed only as a suffix, never in a name field: " .. out3)
  check(out3:find("last kill: unknown", 1, true) ~= nil,
    "`last kill: unknown` with the GUID beside it: " .. out3)

  -- ══════════════════════════════════════════════════════════════════
  -- E'. a SECRET name still reaches the dump — and the dump survives
  -- ══════════════════════════════════════════════════════════════════
  local G4 = "Creature-0-4384-6-0-3124-000055667788"
  targetGuid, targetDead = G4, true
  targetName = newSecret("Razormane Scavenger")   -- a SECRET client string
  now = 761100.00
  fire("PLAYER_TARGET_CHANGED")
  clearChat()
  SlashCmdList.MIGHTIEPACK("skindiag dump")
  local out4 = chatText()
  check(out4:find("dump failed", 1, true) == nil,
    "the dump survives a secret name: " .. out4)
  check(out4:find("Razormane Scavenger", 1, true) ~= nil,
    "the secret name is SHOWN, not dropped: " .. out4)
  check(out4:find("last kill: unknown", 1, true) == nil,
    "a secret name is not replaced by `unknown`")
  check(out4:find("accounting: kills=", 1, true) ~= nil,
    "the accounting line still prints with a live secret in the buffer")
  local tooLong = 0
  for i = 1, #chat do
    if #chat[i] > 120 then tooLong = tooLong + 1 end
  end
  check(tooLong == 0, "every dump line is <= 120 chars (got " .. tooLong .. " longer)")
  end)

-- ════════════════════════════════════════════════════════════════════
-- F. the accounting line reconciles a run shaped like the LIVE one:
-- 15 kills, 4 corpse windows, 5 skin windows, 11 casts. The old counts line
-- printed exactly that and said nothing about the 11 corpses it lost.
-- ════════════════════════════════════════════════════════════════════
onlyIf(type(R) == "table", "recorder missing — the accounting section is skipped", function()
  local pkg2 = {}
  frames = {}
  MightiePackDB = nil
  NodeTrailDB = nil
  loadPackage(pkg2, "MightiePack2")
  boot(pkg2, "MightiePack2")
  local P2 = pkg2.Skinning and pkg2.Skinning.Probe
  local R2 = pkg2.Skinning and pkg2.Skinning.Recorder
  check(type(P2) == "table" and type(R2) == "table", "second package loaded")
  if type(P2) ~= "table" or type(R2) ~= "table" then return end

  pkg2.NodeTrail.SetSkinningEnabled(true)
  pkg2.Skinning.Enable()
  local onEvent = P2.frame:GetScript("OnEvent")
  local function fire(event, ...) onEvent(P2.frame, event, ...) end
  local function G(n)
    return string.format("Creature-0-4384-6-0-3124-0000ABCD%04X", n)
  end

  -- 15 kills
  for i = 1, 15 do
    now = 1000 + i * 100
    fire("UNIT_DIED", G(i))
  end
  -- 4 corpse windows (the other 11 corpses are never looted — the live run)
  for i = 1, 4 do
    loot = { { link = "|cffffffff|Hitem:7100::::::::1:::::::|h[Scorpid Blood]|h|r",
      name = "Scorpid Blood", qty = 1, quality = 0 } }
    lootSource = G(i)
    lootSourceName = nil
    now = 2000 + i * 100
    fire("LOOT_OPENED")
    now = 2000 + i * 100 + 1
    fire("LOOT_CLOSED")
  end
  -- 11 casts, 5 of which are followed by a loot window (= skin loot)
  for i = 1, 11 do
    now = 4000 + i * 100
    fire("UNIT_SPELLCAST_SUCCEEDED", "player", "CastBar-1B595C", 8613, "CastBar-1B595C")
    if i <= 5 then
      loot = { { link = "|cff1eff00|Hitem:2934::::::::1:::::::|h[Ruined Leather Scraps]|h|r",
        name = "Ruined Leather Scraps", qty = 1, quality = 1 } }
      lootSource = G(10 + i)
      now = 4000 + i * 100 + 1
      fire("LOOT_OPENED")
      now = 4000 + i * 100 + 2
      fire("LOOT_CLOSED")
    end
  end

  local store2 = select(1, R2:Store())
  local c = store2.counts
  check(c.kills == 15, "kills=15, got " .. tostring(c.kills))
  check(c.corpseWindows == 4, "corpse-windows=4, got " .. tostring(c.corpseWindows))
  check(c.skinWindows == 5, "skin-windows=5, got " .. tostring(c.skinWindows))
  check(c.skinCasts == 11, "skin-casts=11, got " .. tostring(c.skinCasts))

  if type(R2.Accounting) ~= "function" then
    check(false, "the recorder can account for the run at this commit")
    return
  end
  local a = R2:Accounting(store2)
  check(a.kills == 15 and a.corpseWindows == 4 and a.skinWindows == 5
    and a.casts == 11, "the accounting reads the same counts")
  check(a.killsNoWindow == 11,
    "11 kills produced no corpse window and are SAID to, got "
    .. tostring(a.killsNoWindow))
  check(a.castsNoWindow == 6,
    "6 casts produced no skin window and are SAID to, got "
    .. tostring(a.castsNoWindow))

  local line = R2:AccountingLine(store2)
  -- the print site prefixes "Skinning skindiag: " (19 chars) before the
  -- 120-char cap, so the line body must stay under 101
  check(type(line) == "string" and #line <= 101,
    "the accounting line survives the dump's 120-char cap, got "
    .. tostring(line and #line))
  check(line:find("kills=15", 1, true) ~= nil, "accounting names the kills: " .. line)
  check(line:find("corpse-windows=4", 1, true) ~= nil, "and the corpse windows: " .. line)
  check(line:find("skin-windows=5", 1, true) ~= nil, "and the skin windows: " .. line)
  check(line:find("casts=11", 1, true) ~= nil, "and the casts: " .. line)
  check(line:find("lost kills=11", 1, true) ~= nil,
    "and how many kills lost their window: " .. line)
  check(line:find("casts=6", 1, true) ~= nil,
    "and how many casts produced no window: " .. line)

  -- the line must READ BACK the same numbers it printed (reconciles)
  local k = tonumber(line:match("kills=(%d+)"))
  local cw = tonumber(line:match("corpse%-windows=(%d+)"))
  local nw = tonumber(line:match("lost kills=(%d+)"))
  check(k == 15 and cw == 4 and nw == 11 and (cw + nw) == k,
    "corpse windows + kills without a window == kills (" .. tostring(cw) .. "+"
    .. tostring(nw) .. " vs " .. tostring(k) .. ")")

  clearChat()
  SlashCmdList.MIGHTIEPACK("skindiag dump")
  local out = chatText()
  check(out:find("counts kills=15 corpse-windows=4 skin-windows=5 skin-casts=11", 1, true) ~= nil,
    "the dump still states the counts: " .. out)
  check(out:find(line, 1, true) ~= nil, "and prints the accounting line under them")
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
print("skinning_guardless_spec: ok")
