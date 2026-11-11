-- skindiag_secret_spec.lua — t_1ed3b421
--
-- The blocker this pins, in the card's own words:
--
--   "MightiePack: skindiag: dump failed: .../Modules/Skinning/Probe.lua:908:
--    attempt to get length of local 'line' (a secret string value, while
--    execution tainted by 'MightiePack')"
--
-- The client hands back SECRET strings for creature names (UnitName and
-- friends). A secret may be SHOWN; it may not be measured (#), sliced (:sub),
-- formatted, found, substituted or converted (tostring) — each of those
-- raises, and the whole dump died on the last line of a run whose data had
-- already been collected.
--
-- This spec models a secret faithfully: a value the client marks secret by
-- `issecretvalue`, whose every read (length, slice, format, find, gsub,
-- tostring) RAISES the client's own message, and whose only legal operation
-- is being concatenated onto text and shown. It then pushes such values
-- through every dump path the addon has:
--
--   A. a mob NAME on a kill step and on the record header (Describe)
--   B. a mob NAME as the loot-source name of the corpse and skin windows
--   C. a cast name (the cast-bar name this client sends)
--   D. an item name from GetLootSlotInfo
--   E. a secret GUID on UNIT_DIED
--   F. a secret zone
--   G. a handler that fails with a secret error object
--   H. a 100+ step run, dumped end to end
--
-- plus the two other defects on the card:
--   I. the ?x0 coin slot is not an item and never appears
--   J. the first line of a dump says whether the sub-option is on and WHERE
--      the records went
--
-- RED at c220ec7: the dump raises inside pcall(P.Diag), so the slash command
-- prints "dump failed" and every name check fails (the old code tostring()ed
-- and sliced the name at capture time and in Describe).

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

-- ════════════════════════════════════════════════════════════════════
-- The SECRET simulator: a value only `issecretvalue` may recognise.
-- Any read of it raises exactly what the live client raised.
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
  -- the one legal use: shown, never measured
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
local function clearChat()
  for i = #chat, 1, -1 do chat[i] = nil end
end
local function chatText() return table.concat(chat, "\n") end

-- ── client stub ──────────────────────────────────────────────────────
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
GetRealmName = function() return "Forever" end
GetUnitName = function(u)
  if u == "player" then return "Bowdecia" end
  return nil
end
GetSpellInfo = function() return nil end

-- a zone the client marks secret (F)
local zoneValue = "Desolace"
GetZone = function() return zoneValue end
GetSubzone = function() return "Valley of Bones" end

C_Map = {
  GetBestMapForUnit = function() return 1411 end,
  GetPlayerMapPosition = function()
    return { GetXY = function() return 0.4871, 0.3125 end }
  end,
}

local targetName, targetGuid, targetDead = nil, nil, false
UnitExists = function(u) return u == "target" end
UnitIsDead = function(u) return u == "target" and targetDead == true end
UnitName = function(u) if u == "target" then return targetName end end
UnitGUID = function(u) if u == "target" then return targetGuid end end

local loot, lootSource, lootSourceName = {}, nil, nil
local lootBoom = nil
GetNumLootItems = function()
  if lootBoom then error(lootBoom) end
  return #loot
end
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

-- ── load (the TOC order for the files this spec needs) ──────────────
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
-- t_ba64b076: the sub-option is ON by default now, so the "records go to the
-- session buffer only" half of this spec has to be OFF the way a player turns
-- it off — an explicit opt-out (skinUserSet). A saved false with no user-set
-- flag would be switched on by the one-time migration, and these dump
-- assertions would then be reading the DB path instead of the buffer.
NodeTrailDB = { skinning = { enabled = false, skinUserSet = true } }
local pkg = {}
loadPackage(pkg, "MightiePack")
boot(pkg, "MightiePack")

local ns = pkg.Skinning
local P = type(ns) == "table" and ns.Probe or nil
local R = type(ns) == "table" and ns.Recorder or nil
check(type(P) == "table", "pkg.Skinning.Probe loaded")
check(type(R) == "table", "pkg.Skinning.Recorder loaded")

local function dump()
  clearChat()
  local ok, err = pcall(SlashCmdList.MIGHTIEPACK, "skindiag dump")
  local text = chatText()
  local joined = text
  if not ok then joined = text .. "\n<raised: " .. tostring(err) .. ">" end
  return joined, text
end
local function noDumpFailure(text, where)
  check(text:find("dump failed", 1, true) == nil,
    where .. ": the dump did not fail (" .. text:gsub("\n", " | ") .. ")")
  check(text:find("secret string value", 1, true) == nil,
    where .. ": no secret-string error was raised or printed")
  check(text:find("not printable", 1, true) == nil,
    where .. ": every step line was printable")
end

onlyIf(type(P) == "table" and type(R) == "table",
  "probe or recorder missing at this commit — the secret-path checks are skipped",
  function()

  -- Arming the namespace is what the sub-option does (t_80ffe952): capture on.
  if not P.enabled then P:Enable() end
  if not P.capturing then P:Toggle() end
  check(P.capturing == true, "capture on for the secret run")
  local onEvent = P.frame and P.frame:GetScript("OnEvent")
  check(type(onEvent) == "function", "the probe frame has an OnEvent handler")
  local function fire(event, ...) onEvent(P.frame, event, ...) end

  local CORPSE = "Creature-0-7072-1-48-3124-F090F29C6F"

  -- ══════════════════════════════════════════════════════════════════
  -- A–D: a full chain whose every client-supplied string is a SECRET
  -- ══════════════════════════════════════════════════════════════════
  targetGuid, targetDead = CORPSE, true
  targetName = newSecret("Vile Familiar")
  now = 3000
  fire("PLAYER_TARGET_CHANGED")          -- TARGET_DEAD, secret name

  lootSource = CORPSE
  lootSourceName = newSecret("Vile Familiar")
  loot = {
    -- the coin slot exactly as the client reports it: no itemID, no quantity,
    -- an empty name — the c220ec7 dump printed this as "?x0"
    { link = nil, name = "", qty = 0 },
    { link = "|cffffffff|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h|r",
      name = newSecret("Linen Cloth"), qty = 1, quality = 0 },
    { link = "|cffffffff|Hitem:117::::::::1:::::::|h[Tough Jerky]|h|r",
      name = newSecret("Tough Jerky"), qty = 1, quality = 0 },
  }
  now = 3001
  fire("LOOT_OPENED")                    -- corpse window, secret source name

  now = 3002
  fire("UNIT_DIED", CORPSE)              -- the live death shape (GUID argument)
  now = 3003
  fire("UNIT_SPELLCAST_START", "player", "cast-0", 8613, newSecret("CastBar-1B595C"))
  now = 3004
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 8613, newSecret("CastBar-1B595C"))
  now = 3005
  loot = {
    { link = "|cff1eff00|Hitem:2934::::::::1:::::::|h[Torn Scorpid Hide]|h|r",
      name = newSecret("Torn Scorpid Hide"), qty = 1, quality = 1 },
  }
  fire("LOOT_OPENED")                    -- skin window, same corpse GUID
  now = 3006
  fire("LOOT_CLOSED")

  local out, text = dump()
  noDumpFailure(text, "chain with every string secret")

  -- the names are SHOWN, not dropped
  check(out:find("Vile Familiar", 1, true) ~= nil,
    "the secret creature name is shown in the dump (" .. out:gsub("\n", " | ") .. ")")
  check(out:find("record ", 1, true) ~= nil, "the record header is printed")
  check(out:find("record 1 of 1 (complete) Vile Familiar", 1, true) ~= nil,
    "the record header names the corpse, with the name appended after our own text")
  check(out:find("g=..F29C6F", 1, true) ~= nil,
    "the record still carries the shortened corpse GUID")
  check(out:find("cid=3124", 1, true) ~= nil,
    "the record still carries the creature entry")
  check(out:find("kill=UNIT_DIED", 1, true) ~= nil, "the kill is still attributed")

  -- ══════════════════════════════════════════════════════════════════
  -- I: the coin slot is not an item
  -- ══════════════════════════════════════════════════════════════════
  check(out:find("?x0", 1, true) == nil, "no ?x0 coin slot in the dump")
  check(out:find("i=?", 1, true) == nil, "no unnamed item in a step's item list")
  check(out:find("corpse items: 2589x1,117x1", 1, true) ~= nil,
    "the corpse list holds the two real items and nothing else (" .. out:gsub("\n", " | ") .. ")")
  -- t_67f26739 supersedes the old `,money` label: MONEY IS NOT AN ITEM. The coin
  -- slot used to be appended to the item list as ",money"; an item list now
  -- carries items only, and the coin is counted in its own `coin=` field. This
  -- client's coin slot reports no amount at all, so nothing is printed for it.
  check(out:find(",money", 1, true) == nil,
    "the coin slot is never appended to an item list (money is not an item)")
  check(out:find("coin=", 1, true) == nil or out:find("coin=%d", 1, true) ~= nil,
    "and a coin the client did not count is not invented either")
  check(out:find("?x", 1, true) == nil, "no id-less slot anywhere in the dump")

  -- ══════════════════════════════════════════════════════════════════
  -- J: the first line states the sub-option and where the records went
  -- ══════════════════════════════════════════════════════════════════
  local firstLine = text:match("^[^\n]*")
  check(firstLine ~= nil and firstLine:find("capture", 1, true) ~= nil,
    "the first dump line reports capture (got: " .. tostring(firstLine) .. ")")
  check(firstLine ~= nil and firstLine:find("sub-option", 1, true) ~= nil,
    "the first dump line states the sub-option (got: " .. tostring(firstLine) .. ")")
  check(firstLine ~= nil and firstLine:find("records:", 1, true) ~= nil,
    "the first dump line states where the records went (got: " .. tostring(firstLine) .. ")")
  check(firstLine ~= nil and firstLine:find("session buffer", 1, true) ~= nil,
    "with the sub-option off it says the records stay in the session buffer")
  check(firstLine ~= nil and firstLine:find("steps=", 1, true) ~= nil,
    "the first dump line reports the step count")

  -- and with the sub-option ON the same line names the DB
  NodeTrailDB = NodeTrailDB or {}
  NodeTrailDB.skinning = NodeTrailDB.skinning or {}
  NodeTrailDB.skinning.enabled = true
  local outOn, textOn = dump()
  noDumpFailure(textOn, "sub-option on")
  local firstOn = textOn:match("^[^\n]*") or ""
  check(firstOn:find("sub%-option ON") ~= nil or firstOn:find("sub-option ON", 1, true) ~= nil,
    "sub-option on: the line says ON (got: " .. firstOn .. ")")
  check(firstOn:find("NodeTrailDB.skinning", 1, true) ~= nil,
    "sub-option on: the line says the records are saved to NodeTrailDB.skinning")
  check(outOn:find("Vile Familiar", 1, true) ~= nil,
    "sub-option on: the secret name is still shown")

  -- ══════════════════════════════════════════════════════════════════
  -- E: a secret GUID on UNIT_DIED
  -- ══════════════════════════════════════════════════════════════════
  now = 3100
  fire("UNIT_DIED", newSecret("Creature-0-7072-1-48-3124-ABCDEF123456"))
  local outGuid, textGuid = dump()
  noDumpFailure(textGuid, "secret GUID on UNIT_DIED")
  check(outGuid:find("UNIT_DIED", 1, true) ~= nil,
    "the secret-GUID death still produced a step")

  -- ══════════════════════════════════════════════════════════════════
  -- F: a secret zone
  -- ══════════════════════════════════════════════════════════════════
  zoneValue = newSecret("Desolace")
  now = 3200
  fire("PLAYER_ENTERING_WORLD", false)
  local outZone, textZone = dump()
  noDumpFailure(textZone, "secret zone")
  check(outZone:find("PLAYER_ENTERING_WORLD", 1, true) ~= nil,
    "a secret zone does not lose the step")
  zoneValue = "Desolace"

  -- ══════════════════════════════════════════════════════════════════
  -- G: a handler that fails with a secret error object
  -- ══════════════════════════════════════════════════════════════════
  lootBoom = newSecret("the client refused this read")
  now = 3300
  local okFire = pcall(fire, "LOOT_OPENED")
  check(okFire, "an event handler that fails with a secret does not raise out of OnEvent")
  lootBoom = nil
  local outErr = dump()
  check(outErr ~= nil, "a client read that fails is absorbed by the guarded loot read")
  -- the recorded failure may itself be a value the client marked secret: the
  -- line must say so instead of measuring it
  P._error = newSecret("the client refused this read")
  local outErr2, textErr2 = dump()
  noDumpFailure(textErr2, "error line carrying a secret")
  check(outErr2:find("last error:", 1, true) ~= nil,
    "a failure is reported on its own line")
  check(outErr2:find("a secret value", 1, true) ~= nil,
    "the error line says the value could not be read")
  P._error = nil

  -- ══════════════════════════════════════════════════════════════════
  -- H: a 100+ step run, dumped end to end
  -- ══════════════════════════════════════════════════════════════════
  targetDead = false
  for i = 1, 130 do
    now = 4000 + i
    fire("PLAYER_ENTERING_WORLD", false)
  end
  check(#P.steps == P.MAX_STEPS,
    "the ring buffer holds a full run (" .. tostring(#P.steps) .. "/" .. tostring(P.MAX_STEPS) .. ")")
  check(#P.steps >= 100, "the run is 100+ steps")
  local outBig, textBig = dump()
  noDumpFailure(textBig, "100+ step run")
  check(outBig:find("older step(s) held in the ring buffer", 1, true) ~= nil,
    "the dump says how many older steps the ring holds")
  check(outBig:find("PLAYER_ENTERING_WORLD", 1, true) ~= nil,
    "the dump printed the captured steps")

  -- every printed line is short enough for one chat line: the cap applies to
  -- text the addon built, and a secret name is appended after it
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
-- The dump must never measure a value the client marked secret: the same
-- run is repeated with a value whose LENGTH raises, and the source of the
-- dump path is checked to keep a single printer.
-- ════════════════════════════════════════════════════════════════════
onlyIf(type(P) == "table",
  "probe missing at this commit — the source audit is skipped", function()
  local function read(p)
    local fh = io.open(root .. "/MightiePack/" .. p, "r")
    if not fh then return nil end
    local t = fh:read("*a")
    fh:close()
    return t
  end
  local probe = read("Modules/Skinning/Probe.lua")
  local record = read("Modules/Skinning/Record.lua")
  check(probe ~= nil and record ~= nil, "both skinning files are readable")
  if probe and record then
    -- the old crash site: string.format over a line carrying a name, then #line
    check(probe:find("if #line > self.LINE_CAP", 1, true) == nil,
      "Probe.lua no longer measures a formatted line that may carry a name")
    check(record:find("\"record \" .. tostring(rec.name", 1, true) == nil,
      "Record.lua no longer tostring()es the creature name into the record line")
    check(probe:find("cut(name", 1, true) == nil and probe:find("cut(srcName", 1, true) == nil,
      "Probe.lua no longer slices a client name")
    check(record:find("guidSuffix(rec.guid)", 1, true) ~= nil,
      "Record.lua still shortens the GUID through the guarded helper")
  end
end)

if failed > 0 then
  io.stderr:write("skindiag_secret_spec: " .. failed .. " check(s) failed\n")
  os.exit(1)
end
print("skindiag_secret_spec: ok")
