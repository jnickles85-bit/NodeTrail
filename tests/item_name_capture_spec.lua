-- t_e27da774 — the item NAME is stored with the id at loot time.
--
-- Mightie's panel printed `item 249399  4%` under Briarthorn, and the card that
-- followed dressed it up as `unknown item 249399`. Neither is a name. 249399 is
-- **Frilled Lichen** — a real reagent his alchemy uses — and the name was in the
-- loot slot's own item link at the moment he gathered it:
--
--   |cnIQ2:|Hitem:249399::::::::21:1486:::::::::|h[Frilled Lichen]|h|r
--   (his SavedVariables, NodeTrailDB.herbs, record t=1794159424)
--
-- The old path stored the id and asked GetItemInfo at DRAW time, and
-- GetItemInfo answers nil for an id this client has not cached. So the fix is
-- not a better fallback label, it is keeping the name.
--
-- What this spec pins, and where:
--
--   A. CAPTURE (herb)     the real recorder, driven through the real loot
--                         events, stores `name` + id from the slot's link even
--                         when GetLootSlotInfo's name field is empty, and never
--                         stores a secret name.
--   B. CAPTURE (skinning) the probe's loot read takes the link's name, and the
--                         skinning record + the beast panel show it.
--   C. DRAW ORDER         stored name -> our table -> GetItemInfo -> the marker
--                         `item <id> (name unavailable)`; a stored name is
--                         preferred over a DIFFERENT client answer, and the
--                         client is not even asked when a name is stored.
--   D. RETRY              an id that printed the marker is asked again when the
--                         client announces item data, and the row changes; the
--                         watcher registers the item-data event when it exists.
--   E. REPORT             /nt ttdiag lists the id that could not be named and
--                         the lookups that failed — for herbs and beast drops.
--   F. MIGRATION          a record written before this change (id only) still
--                         renders, through the id lookup.
--
-- Every check reads a real product: a SavedVariables record, a panel row, a
-- diag line. The one fixture copied from the client is the link string above —
-- his own store, not an invented name.
--
-- On the parent commit there is no Data/ItemNames.lua: section 0 reports that,
-- every section that needs it reports "missing", and A/B/C/D/E fail
-- behaviourally (no traceback).

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

local F = dofile(root .. "/tests/support/fakeui.lua")
F.install({ width = 1920, height = 1080 })

time = time or os.time
CopyTable = function(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = type(v) == "table" and CopyTable(v) or v
  end
  return c
end
SlashCmdList = {}
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end }

-- ── the client ─────────────────────────────────────────────────────────────
-- The classic herb ids our own table knows; 249399 is the id from the report and
-- this client's GetItemInfo answers NOTHING for it — that is the whole point:
-- the name has to come from the loot slot, not from the item cache.
local ITEM_NAMES = {
  [2450] = "Briarthorn",
  [2452] = "Swiftthistle",
  [2447] = "Peacebloom",
  [765] = "Silverleaf",
  [2319] = "Medium Leather",
}
local itemInfoCalls = {}
GetItemInfo = function(id)
  itemInfoCalls[id] = (itemInfoCalls[id] or 0) + 1
  return ITEM_NAMES[id]
end

local now = 1000
GetTime = function() return now end
GetSpellInfo = function(id)
  local map = { [2366] = "Herb Gathering", [2259] = "Alchemy", [8613] = "Skinning" }
  return map[id]
end
IsFishingLoot = function() return false end
C_Map = {
  GetBestMapForUnit = function() return 1411 end,
  GetPlayerMapPosition = function()
    return { GetXY = function() return 0.4871, 0.3125 end }
  end,
}
GetUnitName = function(u) if u == "player" then return "Skinner" end return nil end
GetRealmName = function() return "TestRealm" end

-- Herbalism + Skinning, so both blocks are allowed to render.
local skillLines = {
  { name = "Herbalism", rank = 300 },
  { name = "Skinning", rank = 300 },
}
GetNumSkillLines = function() return #skillLines end
GetSkillLineInfo = function(i)
  local row = skillLines[i]
  if not row then return nil end
  return row.name, false, true, row.rank
end

-- The hovered unit, for the beast block.
local unit = { exists = false, guid = nil, ctype = "Beast", name = "Clattering Scorpid" }
UnitExists = function(u) return u == "mouseover" and unit.exists == true end
UnitGUID = function(u) if u ~= "mouseover" then return nil end return unit.guid end
UnitCreatureType = function(u) if u ~= "mouseover" then return nil end return unit.ctype end
UnitName = function(u) if u ~= "mouseover" then return nil end return unit.name end

-- ── SECRET values ──────────────────────────────────────────────────────────
-- A secret may be shown but never measured, searched or sliced. `searched`
-- counts every attempt to use one as a string, so "we never searched it" is a
-- fact this spec can read.
local searchedSecrets = 0
local secretMT = {
  __payload = true,
  __index = function()
    searchedSecrets = searchedSecrets + 1
    error("a secret string was measured", 2)
  end,
  __tostring = function()
    searchedSecrets = searchedSecrets + 1
    error("a secret string was formatted", 2)
  end,
  __concat = function()
    searchedSecrets = searchedSecrets + 1
    error("a secret string was concatenated", 2)
  end,
}
local function newSecret(text)
  return setmetatable({ text = text }, secretMT)
end
issecretvalue = function(v)
  return type(v) == "userdata" or (type(v) == "table" and getmetatable(v) == secretMT)
end

-- ── the loot window ────────────────────────────────────────────────────────
-- `link` is the client's own item link; in the real report the slot's name
-- field can be empty while the link still carries the name (the second shape
-- below), which is exactly why the link is what gets stored.
local loot, lootSource = {}, nil
GetNumLootItems = function() return #loot end
GetLootSlotLink = function(i) return loot[i] and loot[i].link end
GetLootSlotInfo = function(i)
  local s = loot[i]
  if s then return "icon", s.name, s.qty, s.quality end
end
GetLootSourceInfo = function() return lootSource end
GetLootSourceName = function() return nil end

-- The panel is measured for real by fakeui (glyph widths, anchors, rects), so
-- the frame factory stays fakeui's; this only adds the event surface a client
-- frame has and that the recorder/watch clock register on.
local frames = {}
local baseCreateFrame = _G.CreateFrame
CreateFrame = function(kind, name, parent)
  local f = baseCreateFrame(kind, name, parent)
  f.events = {}
  f.RegisterEvent = function(self, n) self.events[n] = true end
  f.UnregisterEvent = function(self, n) self.events[n] = nil end
  frames[#frames + 1] = f
  return f
end

-- ── load (TOC order for the files this spec needs) ─────────────────────────
local pkg = {}
local function loadFile(path)
  local f = assert(loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path))
  f("MightiePack", pkg)
end
local function loadAddon(path)
  local f = assert(loadfile(root .. "/MightiePack/" .. path))
  f("MightiePack", pkg)
end

-- The module this card adds. Missing on the parent commit: report it, do not die.
local okIN = pcall(loadFile, "Data/ItemNames.lua")
loadFile("locale/enUS.lua")
loadFile("Config.lua")
loadFile("Data/Recorder.lua")
loadFile("Data/HerbData.lua")
loadFile("Data/Profession.lua")
loadFile("Data/Recipes.lua")
pcall(loadFile, "Data/SkinHints.lua")
loadFile("UI/TooltipPanel.lua")
loadFile("UI/Tooltip.lua")
loadFile("Core.lua")
loadAddon("Modules/Skinning/Probe.lua")
loadAddon("Modules/Skinning/Record.lua")

local ns = pkg.NodeTrail
local T = ns.Tooltip
local P = ns.TooltipPanel
local HD = ns.HerbData
local HH = ns.SkinHints
local Rc = ns.Recorder
local IN = ns.ItemNames
local Probe = pkg.Skinning and pkg.Skinning.Probe
local SkinR = pkg.Skinning and pkg.Skinning.Recorder

NodeTrailDB = {
  recipes = {},
  profile = {},
  herbs = { schema = 1, total = 0, maps = {} },
  skinning = { enabled = true },
}

-- ═══ 0. the shared resolver exists and is the one everybody asks ══════════
check(okIN and type(IN) == "table", "0: Data/ItemNames.lua loads (the one item-name resolver)")
local HAS_IN = type(IN) == "table"

-- ── panel / diag drivers ──────────────────────────────────────────────────
local function panelLines()
  return P:TextLines()
end
local GameTooltip = F.newTooltip({
  lines = {},
  owner = UIParent,
  left = 400, bottom = 800, width = 180, height = 60,
})
_G.GameTooltip = GameTooltip
local function hover(name)
  GameTooltip.lines = { name, "Herbalism" }
  GameTooltip:SyncFirstLine()
  GameTooltip.shown = true
  pcall(T.Poll, T, GameTooltip)
  return GameTooltip
end
local function findRow(predicate)
  for _, l in ipairs(panelLines()) do
    if predicate(l) then return l end
  end
  return nil
end
local function diagText()
  chat = {}
  local ok, err = pcall(T.Diag, T)
  return ok, err, table.concat(chat, "\n")
end

-- ── the herb recorder, driven through its real events ──────────────────────
local function armRecorder()
  if not Rc.frame then
    Rc:Enable()
  end
  return Rc.frame
end
local function fireRecorder(event, ...)
  local frame = armRecorder()
  local fn = frame:GetScript("OnEvent")
  assert(type(fn) == "function", "the recorder frame has no OnEvent script")
  fn(frame, event, ...)
end
local function gather(items, spellID)
  loot = items
  now = now + 1
  fireRecorder("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", spellID or 2366)
  now = now + 0.5
  fireRecorder("LOOT_OPENED")
end

-- ═══ A. CAPTURE (herb): the name rides with the id ═════════════════════════
-- The two shapes a custom reagent loot slot takes on this client. The first is
-- the reported one: the slot's own name field is present. The second is the
-- case the old code could not survive — the field is empty and GetItemInfo
-- knows nothing, so ONLY the link carries the name.
local LIVE_LINK = "|cnIQ2:|Hitem:249399::::::::21:1486:::::::::|h[Frilled Lichen]|h|r"
gather({
  { link = "|cnIQ1:|Hitem:2450::::::::21:1486:::::::::|h[Briarthorn]|h|r", name = "Briarthorn", qty = 2 },
  { link = LIVE_LINK, name = "Frilled Lichen", qty = 1 },
})

local db = ns.GetHerbDB()
local first = db.maps[1411] and db.maps[1411][1]
check(type(first) == "table", "A: the gather was recorded")
local recorded = {}
for _, it in ipairs(type(first) == "table" and first.items or {}) do
  recorded[it.id] = it
end
check(recorded[2450] ~= nil and recorded[249399] ~= nil,
  "A: both looted ids are in the record")
check(type(recorded[249399]) == "table" and recorded[249399].name == "Frilled Lichen",
  "A: 249399 is stored WITH its name, copied from the loot slot "
    .. "(got " .. tostring(type(recorded[249399]) == "table" and recorded[249399].name) .. ")")
if type(recorded[249399]) == "table" then
  print(("  record: { id = %s, name = %q, count = %s }")
    :format(tostring(recorded[249399].id), tostring(recorded[249399].name),
      tostring(recorded[249399].count)))
end

-- The shape that used to lose the name: no slot name at all.
gather({
  { link = LIVE_LINK, name = nil, qty = 1 },
})
local secondRec = db.maps[1411] and db.maps[1411][2]
local secondItem = type(secondRec) == "table" and secondRec.items and secondRec.items[1]
check(type(secondItem) == "table" and secondItem.name == "Frilled Lichen",
  "A2: an empty slot-name field still stores the name, because it comes from the link "
    .. "(got " .. tostring(type(secondItem) == "table" and secondItem.name) .. ")")

-- ...and a SECRET link is never searched: the record keeps the id, and the
-- client value is not measured, sliced or stored.
local secretLink = newSecret(LIVE_LINK)
local beforeSecret = searchedSecrets
gather({ { link = secretLink, name = nil, qty = 1 } })
local thirdRec = db.maps[1411] and db.maps[1411][3]
local thirdItem = type(thirdRec) == "table" and thirdRec.items and thirdRec.items[1]
check(searchedSecrets == beforeSecret,
  "A3: a secret link is not searched (" .. (searchedSecrets - beforeSecret) .. " attempt(s))")
check(type(thirdItem) == "table" and thirdItem.name == nil,
  "A3: a secret link stores no name — a secret never reaches SavedVariables")
check(type(thirdItem) == "table" and issecretvalue(thirdItem.name) == false,
  "A3: no secret value was written into the record")

-- ═══ B. CAPTURE (skinning): the same rule, one resolver ════════════════════
onlyIf(type(Probe) == "table" and type(Probe.ReadLoot) == "function",
  "B: the skinning probe's loot read exists (Modules/Skinning/Probe.lua)",
  function()
    loot = { { link = LIVE_LINK, name = nil, qty = 3, quality = 2 } }
    local items = Probe:ReadLoot()
    check(type(items) == "table" and #items == 1, "B: the skin window's slot is read")
    check(items[1].id == 249399, "B: the id comes from the link (249399)")
    check(items[1].name == "Frilled Lichen",
      "B: the skinned item's name comes from the link "
        .. "(got " .. tostring(items[1].name) .. ")")

    onlyIf(type(SkinR) == "table",
      "B: the skinning recorder exists",
      function()
        local CID = 3125
        local guid = ("Creature-0-7072-1-48-%d-%012X"):format(CID, 7)
        SkinR:OnKill({ guid = guid, t = 5000, name = "Clattering Scorpid" })
        SkinR:OnCorpseLoot({
          guid = guid, t = 5001,
          items = { { id = 5466, name = "Scorpid Stinger", qty = 1 } },
        })
        SkinR:OnSkinCast({ guid = guid, t = 5002, spellID = 8613 })
        SkinR:OnSkinLoot({ guid = guid, t = 5003, items = items })
        local bucket = SkinR:GetDB() and NodeTrailDB.skinning.chars
          and NodeTrailDB.skinning.chars[SkinR.CharKey()]
        local rec = bucket and bucket.records and bucket.records[guid]
        check(type(rec) == "table" and type(rec.skinItems) == "table"
          and rec.skinItems[1] and rec.skinItems[1].name == "Frilled Lichen",
          "B: the skinning RECORD keeps the name, not just the id")
        -- The panel's own label: GetItemInfo still knows nothing about 249399.
        check(ITEM_NAMES[249399] == nil, "B: this client's GetItemInfo cannot name 249399")
        local label = HH and HH.ItemName
          and HH.ItemName({ itemID = 249399, name = "Frilled Lichen", count = 3 })
        check(label == "Frilled Lichen",
          "B: the beast row prints the stored name, not `item 249399` "
            .. "(got " .. tostring(label) .. ")")
      end)
  end)

-- ═══ C. DRAW ORDER ═════════════════════════════════════════════════════════
-- The stored name wins even when the client answers something DIFFERENT, and
-- GetItemInfo is not asked at all when a name is stored.
local function seedBriarthorn(gathers, extra)
  for i = 1, gathers do
    local items = { { id = 2450, name = "Briarthorn", count = 1 } }
    if i == 1 and extra then
      items[#items + 1] = extra
    end
    ns.RecordHerb(100, 0.5, 0.5, items)
  end
end

NodeTrailDB.herbs = { schema = 1, total = 0, maps = {} }
seedBriarthorn(25, { id = 249399, name = "Frilled Lichen", count = 1 })
itemInfoCalls[249399] = nil
hover("Briarthorn")
local rowC = findRow(function(l) return l == "Frilled Lichen | 4%" end)
check(rowC == "Frilled Lichen | 4%",
  "C: the panel prints the name the record stored (" .. tostring(rowC) .. ")")
check(ITEM_NAMES[249399] == nil,
  "C: ...while GetItemInfo still cannot name 249399 (so the name came from the record)")
local callsAfterStored = itemInfoCalls[249399] or 0
check(callsAfterStored == 0,
  "C2: a stored name is used without asking the client at all ("
    .. callsAfterStored .. " ask(s) for 249399)")

-- A stored name beats a DIFFERENT client answer: the client's cache is stale or
-- simply wrong, and the loot slot is what the player was shown.
ITEM_NAMES[249399] = "Pinecone of Doom"
hover("Briarthorn")
local rowC3 = findRow(function(l) return l == "Frilled Lichen | 4%" end)
check(rowC3 == "Frilled Lichen | 4%",
  "C3: the stored name is preferred over a different GetItemInfo answer ("
    .. tostring(rowC3) .. ")")
ITEM_NAMES[249399] = nil

-- ═══ D. MIGRATION: a record written BEFORE this change still renders ═══════
-- No `name` field at all: the draw-time lookup is what it always was.
NodeTrailDB.herbs = { schema = 1, total = 0, maps = {} }
seedBriarthorn(25, { id = 249399, count = 1 })
hover("Briarthorn")
local rowD = findRow(function(l)
  return type(l) == "string" and l:find("249399", 1, true) ~= nil
end)
check(rowD == "item 249399 (name unavailable) | 4%",
  "D: a name-less record renders through the marker, never a bare id ("
    .. tostring(rowD) .. ")")
local bareD = findRow(function(l)
  return type(l) == "string" and l:match("^item %d+$") ~= nil
end)
check(bareD == nil, "D: no row prints a bare `item N` (" .. tostring(bareD) .. ")")

-- ...and the same record renders its CLIENT name when the client knows the id.
ITEM_NAMES[249399] = "Frilled Lichen"
hover("Briarthorn")
local rowD2 = findRow(function(l) return l == "Frilled Lichen | 4%" end)
check(rowD2 == "Frilled Lichen | 4%",
  "D2: the id lookup still names an old record when the client knows the id ("
    .. tostring(rowD2) .. ")")
ITEM_NAMES[249399] = nil

-- ═══ E. RETRY: an id that could not be named is asked again ═══════════════
onlyIf(HAS_IN, "E: Data/ItemNames.lua is missing — the retry cannot be exercised", function()
  -- The marker is on screen right now (section D left the row at 249399).
  hover("Briarthorn")
  local before = IN.Asks(249399)
  check(before > 0, "E: the failed lookup was counted (" .. before .. " ask(s))")

  -- The client announces item data and now knows the id.
  ITEM_NAMES[249399] = "Frilled Lichen"
  local refreshed = IN.OnItemData("ITEM_DATA_LOAD_RESULT")
  check(refreshed == true, "E: the item-data event re-polls the panel")
  local rowE = findRow(function(l) return l == "Frilled Lichen | 4%" end)
  check(rowE == "Frilled Lichen | 4%",
    "E: after the client announces item data the row becomes the name ("
      .. tostring(rowE) .. ")")
  check(IN.Asks(249399) > before,
    "E: the retry asked GetItemInfo again (" .. IN.Asks(249399) .. " asks)")

  -- The watcher registers the item-data event when the client has one.
  local okWatch = IN.Watch()
  check(okWatch == true, "E2: the retry clock starts")
  local watcher
  for i = #frames, 1, -1 do
    if frames[i].events and frames[i].events["ITEM_DATA_LOAD_RESULT"] then
      watcher = frames[i]
      break
    end
  end
  check(watcher ~= nil,
    "E2: ITEM_DATA_LOAD_RESULT is registered (a client that has it) — got: "
      .. tostring(IN._diag.watch))
  if watcher then
    check(type(watcher.scripts.OnEvent) == "function",
      "E2: the watch frame has an OnEvent script")
    -- Firing it is what the client does; the row must stay a name.
    local okFire = pcall(watcher.scripts.OnEvent, watcher, "ITEM_DATA_LOAD_RESULT")
    check(okFire, "E2: the watch frame's OnEvent runs")
  end
  ITEM_NAMES[249399] = nil
end)

-- ═══ F. REPORT: /nt ttdiag lists the id and the failed lookups ════════════
-- A record with no name and a client that cannot name the id: the marker is on
-- the panel, and the diag has to say WHICH id and WHICH lookups failed.
NodeTrailDB.herbs = { schema = 1, total = 0, maps = {} }
seedBriarthorn(25, { id = 249399, count = 1 })
hover("Briarthorn")
local okDiag, errDiag, outF = diagText()
check(okDiag, "F: /nt ttdiag runs (" .. tostring(errDiag) .. ")")
check(outF:find("herb item: item id: 249399 -> no stored name · GetItemInfo answered nothing", 1, true) ~= nil,
  "F: the diag reports the id, that nothing was stored, and that the client answered nothing ("
    .. outF .. ")")
check(outF:find('· gather · the panel prints "item 249399 (name unavailable)"', 1, true) ~= nil,
  "F: the diag says what the panel prints (" .. outF .. ")")
check(outF:find("herb item: item names: id 249399 could not be named — lookups attempted", 1, true) ~= nil,
  "F: the unnamed id is listed with the lookups that failed (" .. outF .. ")")

-- The same id, once stored, is reported as named — and the client is still asked
-- (the operator's question is "did this client know it").
NodeTrailDB.herbs = { schema = 1, total = 0, maps = {} }
seedBriarthorn(25, { id = 249399, name = "Frilled Lichen", count = 1 })
hover("Briarthorn")
local okDiag2, _, outF2 = diagText()
check(okDiag2, "F2: /nt ttdiag runs")
check(outF2:find('herb item: item id: 249399 -> stored "Frilled Lichen"', 1, true) ~= nil,
  "F2: the diag quotes the stored name (" .. outF2 .. ")")
check(outF2:find('· the panel prints "Frilled Lichen"', 1, true) ~= nil,
  "F2: the diag says the panel prints it (" .. outF2 .. ")")

-- ═══ G. CONSTRAINTS ═══════════════════════════════════════════════════════
local function readAll(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
local namesSrc = readAll(root .. "/MightiePack/Modules/NodeTrail/Data/ItemNames.lua")
if namesSrc then
  check(namesSrc:find("C_Event" .. "Utils", 1, true) == nil,
    "G: ItemNames.lua never touches the restricted event-validity namespace")
  check(namesSrc:find("COMBAT_LOG_EVENT_UNFILTERED", 1, true) == nil,
    "G: ItemNames.lua never registers COMBAT_LOG_EVENT_UNFILTERED")
end
check(T._error == nil, "G: the tooltip module recorded no error (" .. tostring(T._error) .. ")")
check(Rc._error == nil, "G: the recorder recorded no error (" .. tostring(Rc._error) .. ")")

if failed > 0 then
  io.stderr:write(failed .. " item-name check(s) failed\n")
  os.exit(1)
end
print("item_name_capture_spec: ok")
