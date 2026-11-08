-- skinning_dump_spec.lua — t_11fc0755
--
-- The recorder captures items correctly (live proof, build 06984f6). What was
-- still wrong was the DUMP: it rendered only the NEWEST record, and the newest
-- record is by definition the corpse that died most recently — usually seconds
-- before the dump, with its loot windows still ahead of it:
--
--   record unknown g=..BF2A02 cid=3125 kill=UNIT_DIED
--     corpse items: none seen
--     skinning cast: none
--     skin items: none seen
--     gap corpse-close->skin-open: n/a (no skin window)
--
-- That mob died at the last step of the buffer, so `none seen` was correct and
-- useless: the dump always showcased the one record that CANNOT be complete.
--
-- What this spec pins:
--   A. the load surface: the dump renders a SET of records, not one
--   B. three records, newest complete first, each labelled `record i of n (...)`
--   C. a complete record carries BOTH item lists, from windows on the SAME GUID
--   D. the newest, still-in-flight corpse is kept LAST, marked `in progress`
--   E. no complete cycle yet: the dump says so in the card's words
--   F. the horizon: a corpse that can no longer gain a skin window is not
--      called `in progress` (and is never called complete either)
--   G. names: the creature's name when known, `unknown` when the client gives
--      none — never `?`
--   H. nothing regressed: money is not an item, `?x` is gone, every line fits
--      the 120-char chat cap, and the counts/accounting print ONCE
--
-- RED at HEAD (06984f6): Describe() renders R:Last(store) only, so B, D, E and
-- F all fail, and the header carries no `record i of n` label at all.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

-- ── chat capture ─────────────────────────────────────────────────────
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end }
local function clearChat() for i = #chat, 1, -1 do chat[i] = nil end end
local function chatText() return table.concat(chat, "\n") end

-- ── client stub (the same shape the other skinning specs use) ────────
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
GetUnitName = function(u)
  if u == "player" then return "MightieBarb" end
  return nil
end
-- 8613 is not resolvable by name on this client: the 4th cast argument is the
-- cast bar, and GetSpellInfo answers nothing for it.
GetSpellInfo = function() return nil end
C_Map = {
  GetBestMapForUnit = function() return 1411 end,
  GetPlayerMapPosition = function()
    return { GetXY = function() return 0.5432, 0.2710 end }
  end,
}
UnitExists = function() return false end
UnitIsDead = function() return false end
UnitName = function() return nil end
UnitGUID = function() return nil end

local loot, lootSource, lootSourceName = {}, nil, nil
GetNumLootItems = function() return #loot end
GetLootSlotLink = function(i) return loot[i] and loot[i].link end
GetLootSlotInfo = function(i)
  local s = loot[i]
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

-- a fresh package: fresh step buffer, fresh session store, fresh saved vars
local function newPackage(name)
  local pkg = {}
  frames = {}
  MightiePackDB = nil
  NodeTrailDB = nil
  loadPackage(pkg, name)
  boot(pkg, name)
  pkg.NodeTrail.SetSkinningEnabled(true)   -- the live run: sub-option ON
  pkg.Skinning.Enable()
  local P = pkg.Skinning.Probe
  local onEvent = P.frame:GetScript("OnEvent")
  return pkg, P, function(event, ...) onEvent(P.frame, event, ...) end
end

local CORPSE_ITEM = "|cffffffff|Hitem:5466::::::::1:::::::|h[Scorpion Scale]|h|r"
local SKIN_ITEM = "|cff1eff00|Hitem:2318::::::::1:::::::|h[Light Leather]|h|r"

local function corpseGuid(n)
  return string.format("Creature-0-4384-6-0-%d-0000ABCD%04X", 3120 + n, n)
end
-- the GUID suffix Record.lua prints (".." + the last six characters)
local function suffixOf(guid)
  return ".." .. guid:sub(#guid - 5)
end

-- ── dump helpers ─────────────────────────────────────────────────────
-- One entry per `record i of n (state)` header, with the lines under it.
local function recordBlocks(lines)
  local blocks, cur = {}, nil
  for _, line in ipairs(lines) do
    local i, n, state = line:match("record (%d+) of (%d+) %(([%a%s%-]+)%)")
    if i then
      cur = { i = tonumber(i), n = tonumber(n), state = state, head = line, lines = {} }
      blocks[#blocks + 1] = cur
    elseif line:find("counts kills=", 1, true) then
      cur = nil
    elseif cur then
      cur.lines[#cur.lines + 1] = line
    end
  end
  return blocks
end
local function blockText(b)
  local bits = { b.head }
  for _, l in ipairs(b.lines) do bits[#bits + 1] = l end
  return table.concat(bits, "\n")
end
local function dumpLines()
  clearChat()
  SlashCmdList.MIGHTIEPACK("skindiag dump")
  return chat
end

-- ════════════════════════════════════════════════════════════════════
-- A. the load surface
-- ════════════════════════════════════════════════════════════════════
local pkg, P, fire = newPackage("MightiePack")
local R = pkg.Skinning and pkg.Skinning.Recorder
check(type(R) == "table", "recorder loaded")
check(type(R) == "table" and type(R.Describe) == "function",
  "the recorder renders its records for the dump")

local okAll = type(R) == "table" and type(R.DumpSet) == "function"
check(okAll, "A: the dump renders a SET of records (Record.DumpSet)")
check(type(R) == "table" and R.DUMP_RECORDS == 3,
  "A: the dump shows three records, got " .. tostring(type(R) == "table" and R.DUMP_RECORDS))
if type(R) == "table" and type(R.DumpSet) == "function" then
  local set = R:DumpSet(select(1, R:Store()))
  check(type(set) == "table" and #set == 0, "A: an empty store yields an empty set")
end

-- ════════════════════════════════════════════════════════════════════
-- B/C/D. four closed cycles + one corpse still in flight
-- ════════════════════════════════════════════════════════════════════
local function cycle(t0, n, name)
  now = t0
  fire("UNIT_DIED", corpseGuid(n))
  loot = { { link = CORPSE_ITEM, name = "Scorpion Scale", qty = 1, quality = 0 },
    { link = nil, name = "", qty = 57 } }          -- the coin slot is not an item
  lootSource, lootSourceName = corpseGuid(n), name
  now = t0 + 1
  fire("LOOT_OPENED")                              -- corpse window
  loot = { { link = nil, name = "", qty = 57 } }
  now = t0 + 2
  fire("LOOT_SLOT_CLEARED", 1)
  now = t0 + 2.50
  fire("LOOT_CLOSED")
  now = t0 + 3
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "CastBar-1B595C", 8613, "CastBar-1B595C")
  loot = { { link = SKIN_ITEM, name = "Light Leather", qty = 1, quality = 1 } }
  lootSource = corpseGuid(n)
  now = t0 + 4
  fire("LOOT_OPENED")                              -- skin window, same GUID
  loot = {}
  now = t0 + 4.50
  fire("LOOT_SLOT_CLEARED", 1)
  now = t0 + 5
  fire("LOOT_CLOSED")
end

cycle(2000, 1, "Clattering Scorpid")
cycle(2010, 2, "Clattering Scorpid")
cycle(2020, 3, "Clattering Scorpid")
cycle(2030, 4, "Scorpid Worker")
-- the corpse the dump used to showcase: killed seconds ago, nothing looted yet
now = 2040
fire("UNIT_DIED", corpseGuid(5))

local store = select(1, R:Store())
do
  local rec4 = store.records[corpseGuid(4)]
  check(type(rec4) == "table", "B: the fourth corpse has a record")
  check(type(rec4) == "table" and #rec4.corpseItems == 1 and rec4.corpseItems[1].itemID == 5466,
    "B: the fourth record carries its corpse items")
  check(type(rec4) == "table" and #rec4.skinItems == 1 and rec4.skinItems[1].itemID == 2318,
    "B: and its skin items, kept separate")
end

local lines = dumpLines()
local out = table.concat(lines, "\n")
check(out:find("dump failed", 1, true) == nil, "B: the dump completed: " .. out)

local blocks = recordBlocks(lines)
check(#blocks == 3, "B: the dump renders THREE records, got " .. tostring(#blocks)
  .. ": " .. out)

if #blocks == 3 then
  -- newest complete first: corpse 4, then 3, then 2 — corpse 1 is off the dump
  check(blocks[1].i == 1 and blocks[1].n == 3, "B: the first label reads `record 1 of 3`, got `"
    .. tostring(blocks[1].head) .. "`")
  check(blocks[2].i == 2 and blocks[2].n == 3, "B: the second label reads `record 2 of 3`")
  check(blocks[3].i == 3 and blocks[3].n == 3, "B: the third label reads `record 3 of 3`")

  check(blocks[1].state == "complete", "B: record 1 is complete, got `"
    .. tostring(blocks[1].state) .. "`")
  check(blocks[2].state == "complete", "B: record 2 is complete, got `"
    .. tostring(blocks[2].state) .. "`")
  check(blocks[3].state == "in progress", "D: the newest record is in progress, got `"
    .. tostring(blocks[3].state) .. "`")

  -- the labels the card names, exactly
  check(out:find("record 1 of 3 (complete)", 1, true) ~= nil,
    "C: the dump prints `record 1 of 3 (complete)`: " .. out)
  check(out:find("record 3 of 3 (in progress)", 1, true) ~= nil,
    "D: the dump prints `record 3 of 3 (in progress)`: " .. out)

  -- the complete record is the fourth corpse, and BOTH lists are on it
  check(blocks[1].head:find(suffixOf(corpseGuid(4)), 1, true) ~= nil,
    "C: record 1 is the newest complete corpse (" .. suffixOf(corpseGuid(4)) .. "): "
    .. blocks[1].head)
  check(blocks[1].head:find("cid=3124", 1, true) ~= nil,
    "C: record 1 names the creature entry: " .. blocks[1].head)
  check(blocks[1].head:find("Scorpid Worker", 1, true) ~= nil,
    "G: the creature's name is shown when it is known: " .. blocks[1].head)
  local t1 = blockText(blocks[1])
  check(t1:find("where: z=Durotar 1411@.543,.271", 1, true) ~= nil,
    "C: the record still carries its zone and position, one line down: " .. t1)
  check(t1:find("corpse items: 5466x1", 1, true) ~= nil,
    "C: record 1 shows its corpse items: " .. t1)
  check(t1:find("skin items: 2318x1", 1, true) ~= nil,
    "C: record 1 shows its skin items: " .. t1)
  check(t1:find("none seen", 1, true) == nil,
    "C: a complete record shows no `none seen` list: " .. t1)
  check(t1:find("skinning cast: 8613 ok", 1, true) ~= nil,
    "C: the successful 8613 cast is on the complete record: " .. t1)
  check(t1:find("gap corpse-close->skin-open: 1.50s", 1, true) ~= nil,
    "C: the gap between the two windows is on it: " .. t1)

  -- same GUID on both windows: the two LOOT_OPENED steps of this corpse
  local s4 = suffixOf(corpseGuid(4))
  local corpseStep, skinStep
  for _, l in ipairs(lines) do
    if l:find("LOOT_OPENED", 1, true) and l:find(s4, 1, true) then
      if l:find("k=corpse", 1, true) then corpseStep = l end
      if l:find("k=skin", 1, true) then skinStep = l end
    end
  end
  check(corpseStep ~= nil and skinStep ~= nil,
    "C: both windows of that corpse were captured on its GUID: " .. out)
  check(corpseStep ~= nil and skinStep ~= nil and corpseStep:find(s4, 1, true) ~= nil
    and skinStep:find(s4, 1, true) ~= nil,
    "C: the corpse window and the skin window carry the SAME GUID: "
    .. tostring(corpseStep) .. " / " .. tostring(skinStep))

  -- the in-flight corpse: named or not, it says nothing it did not see
  check(blocks[3].head:find(suffixOf(corpseGuid(5)), 1, true) ~= nil,
    "D: the last record is the corpse killed seconds ago, got "
    .. blocks[3].head)
  check(blocks[3].head:find("unknown", 1, true) ~= nil,
    "G: a name the client never gave reads `unknown`: " .. blocks[3].head)
  check(blocks[3].head:find("?", 1, true) == nil,
    "G: `?` is not what an unknown name reads: " .. blocks[3].head)
  local t3 = blockText(blocks[3])
  check(t3:find("skin items: none seen", 1, true) ~= nil,
    "D: and says plainly that its skin window has not happened: " .. t3)

  -- the fourth-oldest complete record is off the dump (three is the cap); the
  -- step lines still carry every GUID, so this is checked on the record headers
  local heads = {}
  for i = 1, #blocks do heads[i] = blocks[i].head end
  local headText = table.concat(heads, "\n")
  check(headText:find(suffixOf(corpseGuid(1)), 1, true) == nil,
    "B: only three records print — corpse 1 is not a record on the dump: " .. headText)
  check(headText:find(suffixOf(corpseGuid(3)), 1, true) ~= nil,
    "B: record 2 is the second-newest complete corpse: " .. headText)
  check(headText:find(suffixOf(corpseGuid(2)), 1, true) == nil,
    "B: and corpse 2 is off the dump too (three slots, one taken by the "
    .. "in-flight corpse): " .. headText)
end

-- only ONE counts line and ONE accounting line, however many records print
do
  local counts, acct, rate = 0, 0, 0
  for _, l in ipairs(lines) do
    if l:find("counts kills=", 1, true) then counts = counts + 1 end
    if l:find("accounting: kills=", 1, true) then acct = acct + 1 end
    if l:find("no rate is computed", 1, true) then rate = rate + 1 end
  end
  check(counts == 1, "H: the counts line prints once, got " .. tostring(counts))
  check(acct == 1, "H: the accounting line prints once, got " .. tostring(acct))
  check(rate == 1, "H: the `no rate` line prints once, got " .. tostring(rate))
  check(out:find("counts kills=5", 1, true) ~= nil,
    "H: the counts still describe the whole store: " .. out)
end

-- ── H. nothing regressed ─────────────────────────────────────────────
check(out:find("money", 1, true) == nil, "H: money is never an item: " .. out)
check(out:find("?x", 1, true) == nil, "H: no id-less slot anywhere in the dump")
check(out:find("coin=%d") ~= nil,
  "H: the coin the client DID count stays a separate field, never an item: " .. out)
do
  local tooLong = 0
  for _, l in ipairs(lines) do
    if #l > 120 then
      tooLong = tooLong + 1
      io.stderr:write("LONG(" .. #l .. "): " .. l .. "\n")
    end
  end
  check(tooLong == 0, "H: every dump line is <= 120 chars (got " .. tooLong .. " longer)")
end

-- ════════════════════════════════════════════════════════════════════
-- E. no complete cycle yet: the dump says so, in the card's words
-- ════════════════════════════════════════════════════════════════════
do
  local pkg2, P2, fire2 = newPackage("MightiePack2")
  local R2 = pkg2.Skinning.Recorder
  now = 3000
  fire2("UNIT_DIED", corpseGuid(11))
  loot, lootSource, lootSourceName = {}, corpseGuid(11), "Durotar Boar"
  now = 3001
  fire2("LOOT_OPENED")                 -- corpse window, nothing in it
  now = 3002
  fire2("LOOT_CLOSED")

  local lines2 = dumpLines()
  local out2 = table.concat(lines2, "\n")
  check(out2:find("dump failed", 1, true) == nil, "E: the dump completed: " .. out2)
  check(out2:find("no complete corpse->skin cycle captured yet — kill, loot, skin one more mob",
      1, true) ~= nil,
    "E: the empty case says so plainly, in the card's words: " .. out2)
  local b2 = recordBlocks(lines2)
  check(#b2 == 1, "E: the one corpse seen is still shown, got " .. tostring(#b2))
  if #b2 == 1 then
    check(b2[1].state == "in progress", "E: and it is marked in progress, got `"
      .. tostring(b2[1].state) .. "`")
    check(out2:find("(complete)", 1, true) == nil,
      "E: nothing claims to be complete: " .. out2)
  end
end

-- ════════════════════════════════════════════════════════════════════
-- F. the horizon: a corpse that can no longer gain a skin window is
--    neither complete nor in progress
-- ════════════════════════════════════════════════════════════════════
do
  local pkg3, P3, fire3 = newPackage("MightiePack3")
  local R3 = pkg3.Skinning.Recorder
  now = 4000
  fire3("UNIT_DIED", corpseGuid(21))
  loot, lootSource, lootSourceName = {}, corpseGuid(21), "Durotar Boar"
  now = 4001
  fire3("LOOT_OPENED")
  loot = {}
  now = 4002
  fire3("LOOT_CLOSED")
  -- the player walked away and came back much later: no skin window is coming
  now = 4002 + (type(R3) == "table" and (R3.DUMP_HORIZON or 120) or 120) + 10

  local lines3 = dumpLines()
  local out3 = table.concat(lines3, "\n")
  check(out3:find("dump failed", 1, true) == nil, "F: the dump completed: " .. out3)
  check(out3:find("(in progress)", 1, true) == nil,
    "F: a corpse past the horizon is not called in progress: " .. out3)
  check(out3:find("(complete)", 1, true) == nil,
    "F: and it is not called complete either (it never had a skin window): " .. out3)
  local b3 = recordBlocks(lines3)
  check(#b3 == 1, "F: the settled corpse is still shown, got " .. tostring(#b3))
  if #b3 == 1 then
    check(b3[1].state == "no skin window", "F: it is labelled settled, got `"
      .. tostring(b3[1].state) .. "`")
  end
  check(out3:find("no complete corpse->skin cycle captured yet", 1, true) ~= nil,
    "F: and the dump still says no cycle has completed: " .. out3)
end

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("skinning_dump_spec: ok")
