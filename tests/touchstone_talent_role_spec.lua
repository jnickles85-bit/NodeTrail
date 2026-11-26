-- AUTO ROLE FROM TALENT POINTS (fk/talent-auto-role).
--
-- The owner (Nov 26): "read talents to determine the actual role of the player.
-- Then the player wont have to go in and make sure its set correctly. Unless he
-- has to." On the Forever client every class has ONE specialization, so the
-- client's spec read answers the class name; the talents are a trait tree whose
-- three groups are the classic trees (C_ClassTalents / C_Traits). This spec
-- drives the REAL vendored ChestAdvisor against a modelled client of that shape:
--   A. EVERY CLASS, EVERY TREE: 21 points in a tree picks that tree's registry
--      spec, and buildSpec builds it (weights key, client role, order word).
--      Druid Feral is Feral (Cat). Localized names map by position; the list
--      may arrive out of order; orderIndex may start at 0 or 1.
--   B. NO PICK: a tie, no points, the wrong tree count, a recognised name at the
--      wrong position, an unreadable value.
--   C. FALLBACKS: every missing, nil-returning or erroring call, and a value
--      that errors when read, give no pick and today's behaviour; a failed read
--      is retried, a good one is kept until the talents change.
--   D. PRECEDENCE: Gear-for, then a recorded Melee/Spell role, then Auto; Clear
--      is Auto.
--   E. EVENTS: the talent events are registered (one the client rejects costs
--      nothing else) and re-judge only when the pick moved.
--   F. THE PROBE: `/ts talents` and the tail of `/up diag` print each tree's
--      name, orderIndex and points and what Auto picked; reading writes nothing.
--   G. SETTINGS: the Auto box says "Auto (Holy: healer)" or "Auto".
--   M. MUTATIONS: the unmutated files run through the leg command first and must
--      report 0 failed; each mutant must report "N check(s), K failed", K > 0.
--      Skipped inside a leg (TS_ADVISOR_SRC set).
--
-- Run from the repo root:  lua5.1 tests/touchstone_talent_role_spec.lua

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."
local TOUCH = root .. "/MightiePack/Modules/Touchstone/"
local ADVISOR_SRC = os.getenv("TS_ADVISOR_SRC") or (TOUCH .. "ChestAdvisor/ChestAdvisor.lua")
local OPTIONS_SRC = os.getenv("TS_OPTIONS_SRC") or (TOUCH .. "OptionsTab.lua")
local IN_LEG = os.getenv("TS_ADVISOR_SRC") ~= nil

local failed, checks = 0, 0
local function check(cond, msg)
  checks = checks + 1
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local C = dofile(root .. "/tests/support/wowclient.lua")
C.Install({ width = 1920, height = 1080 })
tinsert = table.insert
tremove = table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
MightiePackDB = { modules = {} }
StatForgeDB = { ui = { scale = 1 }, firstUse = false }
ChestAdvisorDB = { context = "leveling", role = {} }
local pkg = { PackVersion = function() return "0.5.0" end }
_G.MightiePack = pkg

local CLASS = { "Paladin", "PALADIN" }
function UnitClass(unit) if unit == "player" then return CLASS[1], CLASS[2], 2 end end
function UnitLevel(unit) if unit == "player" then return 34 end end
function UnitName(unit) if unit == "player" then return "Stank" end end
function GetInventoryItemLink() return nil end

local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end,
  GetName = function() return "ChatFrame1" end }

-- Every frame the module creates, with the events it registers. The client
-- rejects one unknown event name by raising, the way a real client does.
local frames = {}
local REJECTED = "ACTIVE_COMBAT_CONFIG_CHANGED"
local realCreate = CreateFrame
CreateFrame = function(...)
  local f = realCreate(...)
  f.__events = {}
  f.RegisterEvent = function(self, e)
    if e == REJECTED then error("unknown event " .. e) end
    self.__events[e] = true
  end
  frames[#frames + 1] = f
  return f
end

local function loadPath(path, label)
  local chunk, err = loadfile(path)
  check(chunk ~= nil, "loadfile " .. label .. ": " .. tostring(err))
  if not chunk then return end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. label .. ": " .. tostring(e))
end
for _, name in ipairs({ "Bootstrap.lua", "Constants.lua", "Weights.lua", "UI.lua",
  "UpgradesTab.lua", "LogTab.lua", "ChestAdvisor/Marks.lua", "ChestAdvisor/Verdict.lua",
  "ChestAdvisor/StatOrders.lua", "ChestAdvisor/Arbitration.lua" }) do
  loadPath(TOUCH .. name, name)
end
loadPath(ADVISOR_SRC, "ChestAdvisor.lua")
local CA, V = _G.ChestAdvisor, _G.Verdict
if type(CA) ~= "table" or type(V) ~= "table" then
  io.stderr:write("FAIL: the vendored tree did not load\n")
  print(("%d check(s), %d failed"):format(checks + 1, failed + 1))
  os.exit(1)
end
local okEnable, enableErr = pcall(CA.Enable)
check(okEnable, "ChestAdvisor.Enable runs: " .. tostring(enableErr))

local function has(fn) return type(CA[fn]) == "function" end
check(has("readTalentTrees") and has("pickTalentTree") and has("autoTalentPick") and has("talentsReport")
  and has("autoRoleText") and has("_onTalentsChanged") and type(CA.TALENT_TREES) == "table",
  "the Auto role surface is published")
-- Every advisor call is protected: a mutant that throws must fail checks, not
-- stop the spec before its result line.
local function call(fn, ...)
  if not has(fn) then return nil end
  local res = { pcall(CA[fn], ...) }
  if not res[1] then
    check(false, "ChestAdvisor." .. fn .. " threw: " .. tostring(res[2]))
    return nil
  end
  return unpack(res, 2)
end
local function build()
  local ok, spec = pcall(CA.buildSpec)
  check(ok and type(spec) == "table", "buildSpec returns a spec: " .. tostring(spec))
  return (ok and type(spec) == "table") and spec or {}
end

-- ---- the modelled client --------------------------------------------------
local client
local function install(o)
  o = o or {}
  local names = o.names
  local points = o.points or { 0, 0, 0 }
  local base = o.base or 0
  client = { calls = 0 }
  C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 1486, CLASS[1], "", 0, "DAMAGER" end,
  }
  C_ClassTalents = {
    GetActiveConfigID = function() client.calls = client.calls + 1; return 7 end,
    GetTraitTreeForSpec = function(id) return id == 1486 and 860 or nil end,
  }
  C_Traits = {
    GetConfigInfo = function() return { treeIDs = { 860 } } end,
    GetGroupDisplayInfoByTreeID = function(t)
      local out = {}
      if t ~= 860 then return out end
      for i, n in ipairs(names) do
        out[#out + 1] = { groupID = 100 + i, treeID = t, orderIndex = base + i - 1, displayName = n,
          icon = 0, skillLineID = 0 }
      end
      if o.reverse then
        local r = {}
        for i = #out, 1, -1 do r[#r + 1] = out[i] end
        out = r
      end
      return out
    end,
    GetGroupCurrencyInfo = function(_, ids)
      local out = {}
      for _, id in ipairs(ids) do
        out[#out + 1] = { traitNodeGroupID = id, currencyInfos = { { spent = points[id - 100] } } }
      end
      return out
    end,
  }
  if o.after then o.after() end
  call("_onTalentsChanged", "spec")
end
local function uninstall()
  C_SpecializationInfo, C_ClassTalents, C_Traits = nil, nil, nil
  call("_onTalentsChanged", "spec")
end
local function setClass(display, token)
  CLASS[1], CLASS[2] = display, token
  if has("_clearClassCache") then CA._clearClassCache() end
end
local function setDB(gearFor, role)
  ChestAdvisorDB.gearFor = gearFor
  ChestAdvisorDB.role = role and { [CLASS[2]] = role } or {}
end
local function pickKey(token)
  local p = call("autoTalentPick", token or CLASS[2])
  return type(p) == "table" and p.entry and p.entry.key or nil
end

-- ---- A. every class, every tree --------------------------------------------
local EXPECT = {
  WARRIOR = { "Warrior", { "Arms", "Fury", "Protection" }, { "arms", "fury", "prot" }, { "damage", "damage", "tank" } },
  PALADIN = { "Paladin", { "Holy", "Protection", "Retribution" }, { "holy", "prot", "ret" }, { "healer", "tank", "damage" } },
  HUNTER  = { "Hunter", { "Beast Mastery", "Marksmanship", "Survival" }, { "beast_mastery", "marksmanship", "survival" },
              { "damage", "damage", "damage" } },
  ROGUE   = { "Rogue", { "Assassination", "Combat", "Subtlety" }, { "assassination", "combat", "subtlety" },
              { "damage", "damage", "damage" } },
  PRIEST  = { "Priest", { "Discipline", "Holy", "Shadow" }, { "disc", "holy", "shadow" }, { "healer", "healer", "damage" } },
  SHAMAN  = { "Shaman", { "Elemental", "Enhancement", "Restoration" }, { "elemental", "enhancement", "resto" },
              { "damage", "damage", "healer" } },
  MAGE    = { "Mage", { "Arcane", "Fire", "Frost" }, { "arcane", "fire", "frost" }, { "damage", "damage", "damage" } },
  WARLOCK = { "Warlock", { "Affliction", "Demonology", "Destruction" }, { "affliction", "demonology", "destruction" },
              { "damage", "damage", "damage" } },
  DRUID   = { "Druid", { "Balance", "Feral Combat", "Restoration" }, { "balance", "feral_cat", "resto" },
              { "damage", "damage", "healer" } },
}
local ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
setDB(nil, nil)
for _, token in ipairs(ORDER) do
  local e = EXPECT[token]
  setClass(e[1], token)
  setDB(nil, nil)
  for i = 1, 3 do
    local pts = { 2, 3, 4 }
    pts[i] = 21
    install({ names = e[2], points = pts })
    local key = pickKey(token)
    check(key == e[3][i], ("A/%s: %d points in %s picks %s (got %s)"):format(token, 21, e[2][i], e[3][i], tostring(key)))
    local spec = build()
    local entry = CA.lookupSpec(token, e[3][i])
    check(type(spec) == "table" and spec.weightsKey == e[3][i] and entry ~= nil
      and spec.clientRole == entry.role and spec.role == entry.orderWord and spec.profileSource == "talents",
      ("A/%s: buildSpec builds %s from the talents (got %s/%s/%s)"):format(token, e[3][i],
        tostring(spec and spec.weightsKey), tostring(spec and spec.clientRole), tostring(spec and spec.profileSource)))
    check(call("autoRoleText", token) == ("Auto (%s: %s)"):format(e[2][i], e[4][i]),
      ("A/%s: the Settings text for %s (got %s)"):format(token, e[2][i], tostring(call("autoRoleText", token))))
  end
end
-- Localized names map by position; the list may arrive out of order; base 1.
setClass("Paladin", "PALADIN")
setDB(nil, nil)
install({ names = { "Sagrado", "Protección", "Reprensión" }, points = { 31, 5, 0 } })
check(pickKey() == "holy" and call("autoRoleText") == "Auto (Sagrado: healer)",
  "A: localized names map by position, and the client's own name is shown (got " .. tostring(call("autoRoleText")) .. ")")
install({ names = EXPECT.PALADIN[2], points = { 0, 0, 30 }, reverse = true })
check(pickKey() == "ret", "A: a list that arrives out of order is sorted by orderIndex (got " .. tostring(pickKey()) .. ")")
install({ names = EXPECT.PALADIN[2], points = { 30, 0, 0 }, base = 1 })
check(pickKey() == "holy", "A: orderIndex starting at 1 reads the same")
setClass("Druid", "DRUID")
install({ names = { "Balance", "Feral", "Restoration" }, points = { 0, 30, 0 } })
check(pickKey() == "feral_cat", "A: a druid's Feral reads as Feral (Cat), by position or by its short name")

-- ---- B. no pick ------------------------------------------------------------
setClass("Paladin", "PALADIN")
setDB(nil, nil)
local function noPick(label, o, why)
  install(o)
  local p, w = call("autoTalentPick", "PALADIN")
  check(p == nil, "B: " .. label .. ": no Auto pick (got " .. tostring(p and p.entry.key) .. ")")
  if why then
    check(type(w) == "string" and w:find(why, 1, true) ~= nil, "B: " .. label .. ": says why (got " .. tostring(w) .. ")")
  end
  local spec = build()
  check(spec.weightsKey == nil, "B: " .. label .. ": today's behaviour, no Auto spec (got " .. tostring(spec.weightsKey) .. ")")
end
noPick("a tie", { names = EXPECT.PALADIN[2], points = { 11, 11, 0 } }, "tie")
noPick("a tie below a lower tree", { names = EXPECT.PALADIN[2], points = { 3, 11, 11 } }, "tie")
noPick("no points", { names = EXPECT.PALADIN[2], points = { 0, 0, 0 } }, "no talent points spent")
noPick("two trees", { names = { "Holy", "Protection" }, points = { 20, 0 } }, "expected 3")
noPick("four trees", { names = { "Holy", "Protection", "Retribution", "Extra" }, points = { 20, 0, 0, 0 } }, "expected 3")
noPick("a recognised name at the wrong position", { names = { "Protection", "Holy", "Retribution" }, points = { 20, 0, 0 } },
  "expected Holy")
noPick("an unreadable point value", { names = EXPECT.PALADIN[2], points = { 20, 0, 0 }, after = function()
  C_Traits.GetGroupCurrencyInfo = function(_, ids)
    local out = {}
    for i, id in ipairs(ids) do out[i] = { traitNodeGroupID = id, currencyInfos = { { spent = (i == 1) and "20" or 0 } } } end
    return out
  end
end })
install({ names = EXPECT.PALADIN[2], points = { 1, 0, 0 } })
check(pickKey() == "holy", "B: one point is a pick (the most points wins; there is no threshold)")
do
  local p, w = call("pickTalentTree", "PALADIN", { { name = "Holy", spent = "20" },
    { name = "Protection", spent = 0 }, { name = "Retribution", spent = 0 } })
  check(p == nil and type(w) == "string" and w:find("unreadable", 1, true) ~= nil,
    "B: the pick itself refuses a point value that is not a number (got " .. tostring(w) .. ")")
  local q, wq = call("pickTalentTree", "PALADIN", { { name = "Holy", spent = -1 },
    { name = "Protection", spent = 0 }, { name = "Retribution", spent = 0 } })
  check(q == nil and type(wq) == "string" and wq:find("unreadable", 1, true) ~= nil, "B: and a negative one")
  check(call("pickTalentTree", "DEATHKNIGHT", {}) == nil, "B: a class with no tree map: no pick")
end

-- ---- C. fallbacks ----------------------------------------------------------
local function broken(label, mutate, why)
  noPick(label, { names = EXPECT.PALADIN[2], points = { 25, 0, 0 }, after = mutate }, why)
end
broken("no C_ClassTalents", function() C_ClassTalents = nil end, "not on this client")
broken("no C_Traits", function() C_Traits = nil end, "not on this client")
broken("no GetActiveConfigID", function() C_ClassTalents.GetActiveConfigID = nil end, "not on this client")
broken("GetActiveConfigID returns nil", function() C_ClassTalents.GetActiveConfigID = function() return nil end end,
  "no active talent loadout")
broken("GetActiveConfigID errors", function() C_ClassTalents.GetActiveConfigID = function() error("x") end end,
  "no active talent loadout")
broken("no tree from either route", function()
  C_ClassTalents.GetTraitTreeForSpec = nil; C_Traits.GetConfigInfo = nil end, "no talent tree")
broken("both tree routes error", function()
  C_ClassTalents.GetTraitTreeForSpec = function() error("x") end
  C_Traits.GetConfigInfo = function() error("x") end end, "no talent tree")
broken("no GetGroupDisplayInfoByTreeID", function() C_Traits.GetGroupDisplayInfoByTreeID = nil end, "not on this client")
broken("the tree list is empty", function() C_Traits.GetGroupDisplayInfoByTreeID = function() return {} end end,
  "no talent trees listed")
broken("the tree list errors", function() C_Traits.GetGroupDisplayInfoByTreeID = function() error("x") end end,
  "no talent trees listed")
broken("a tree without orderIndex", function()
  C_Traits.GetGroupDisplayInfoByTreeID = function() return { { groupID = 101, displayName = "Holy" },
    { groupID = 102, orderIndex = 1 }, { groupID = 103, orderIndex = 2 } } end end, "could not be read")
broken("no GetGroupCurrencyInfo", function() C_Traits.GetGroupCurrencyInfo = nil end, "not on this client")
broken("the points list is empty", function() C_Traits.GetGroupCurrencyInfo = function() return {} end end,
  "no talent points read")
broken("the points list errors", function() C_Traits.GetGroupCurrencyInfo = function() error("x") end end,
  "no talent points read")
broken("no currency entries at all", function() C_Traits.GetGroupCurrencyInfo = function(_, ids)
  local out = {}
  for i, id in ipairs(ids) do out[i] = { traitNodeGroupID = id, currencyInfos = {} } end
  return out end end, "no talent points read")
broken("a value that errors when it is read", function()
  C_Traits.GetGroupDisplayInfoByTreeID = function()
    local secret = setmetatable({}, { __index = function() error("secret") end })
    return { secret, secret, secret }
  end end, "the talent read failed")
-- The spec route missing: the config's own tree is read instead.
install({ names = EXPECT.PALADIN[2], points = { 25, 0, 0 }, after = function() C_ClassTalents.GetTraitTreeForSpec = nil end })
check(pickKey() == "holy", "C: without GetTraitTreeForSpec the config's tree is read")
-- A failed read is retried on the next build; a good one is kept until an event.
uninstall()
check(pickKey() == nil, "C: no API, no pick")
install({ names = EXPECT.PALADIN[2], points = { 25, 0, 0 }, after = function() C_Traits = nil end })
local saved = {
  GetGroupDisplayInfoByTreeID = function(t)
    local out = {}
    for i, n in ipairs(EXPECT.PALADIN[2]) do out[i] = { groupID = 100 + i, orderIndex = i - 1, displayName = n } end
    return out
  end,
  GetGroupCurrencyInfo = function(_, ids)
    local out, pts = {}, { 25, 0, 0 }
    for i, id in ipairs(ids) do out[i] = { traitNodeGroupID = id, currencyInfos = { { spent = pts[id - 100] } } } end
    return out
  end,
}
C_Traits = saved
local holyPoints = saved.GetGroupCurrencyInfo
check(pickKey() == "holy", "C: a failed read is retried on the next build, no event needed")
local before = client.calls
C_Traits.GetGroupCurrencyInfo = function(_, ids)
  local out, pts = {}, { 0, 0, 25 }
  for i, id in ipairs(ids) do out[i] = { traitNodeGroupID = id, currencyInfos = { { spent = pts[id - 100] } } } end
  return out
end
check(pickKey() == "holy" and client.calls == before, "C: a good read is kept, not re-read on every build")

-- ---- E. events -------------------------------------------------------------
local eventFrame
for _, f in ipairs(frames) do
  if type(f.__events) == "table" and f.__events.PLAYER_TALENT_UPDATE then eventFrame = f end
end
check(eventFrame ~= nil, "E: the advisor's event frame registers PLAYER_TALENT_UPDATE")
local ev = eventFrame and eventFrame.__events or {}
check(ev.CHARACTER_POINTS_CHANGED and ev.TRAIT_CONFIG_UPDATED and ev.ACTIVE_TALENT_GROUP_CHANGED,
  "E: CHARACTER_POINTS_CHANGED and TRAIT_CONFIG_UPDATED are registered too")
check(okEnable and ev[REJECTED] == nil, "E: an event the client rejects costs nothing else (Enable still ran)")
local onEvent = eventFrame and eventFrame:GetScript("OnEvent")
check(type(onEvent) == "function", "E: the frame has its OnEvent")
CA._lastInvalidation = nil
if onEvent then pcall(onEvent, eventFrame, "TRAIT_CONFIG_UPDATED", 7) end
check(pickKey() == "ret", "E: TRAIT_CONFIG_UPDATED re-reads the talents (got " .. tostring(pickKey()) .. ")")
check(type(CA._lastInvalidation) == "string" and CA._lastInvalidation:find("talents ret", 1, true) ~= nil,
  "E: and re-judges, because the pick moved (got " .. tostring(CA._lastInvalidation) .. ")")
CA._lastInvalidation = nil
if onEvent then pcall(onEvent, eventFrame, "CHARACTER_POINTS_CHANGED", 1) end
check(CA._lastInvalidation == nil, "E: an event that leaves the pick alone re-judges nothing")
C_Traits.GetGroupCurrencyInfo = holyPoints
if onEvent then
  local okE, errE = pcall(onEvent, eventFrame, "PLAYER_TALENT_UPDATE")
  check(okE, "E: PLAYER_TALENT_UPDATE handled without error: " .. tostring(errE))
end
check(pickKey() == "holy", "E: PLAYER_TALENT_UPDATE re-reads the talents too")
-- (Review round 1) TRAIT_CONFIG_LIST_UPDATED is registered (guarded) and re-reads.
check(ev.TRAIT_CONFIG_LIST_UPDATED, "E: TRAIT_CONFIG_LIST_UPDATED is registered")
local function pointsTo(pts)
  C_Traits.GetGroupCurrencyInfo = function(_, ids)
    local out = {}
    for i, id in ipairs(ids) do out[i] = { traitNodeGroupID = id, currencyInfos = { { spent = pts[id - 100] } } } end
    return out
  end
end
pointsTo({ 0, 0, 25 })
check(pickKey() == "holy", "E: (the good read is still cached)")
if onEvent then pcall(onEvent, eventFrame, "TRAIT_CONFIG_LIST_UPDATED") end
check(pickKey() == "ret", "E: TRAIT_CONFIG_LIST_UPDATED re-reads the talents (got " .. tostring(pickKey()) .. ")")
-- (Review round 1) a 0-point read at login does not stay cached: entering the
-- world re-reads.
pointsTo({ 0, 0, 0 })
if onEvent then pcall(onEvent, eventFrame, "TRAIT_CONFIG_UPDATED", 7) end
check(pickKey() == nil, "E: a 0-point read (the login race) picks nothing")
pointsTo({ 25, 0, 0 })
check(pickKey() == nil, "E: (and that successful read is cached)")
CA._lastInvalidation = nil
if onEvent then
  local okP, errP = pcall(onEvent, eventFrame, "PLAYER_ENTERING_WORLD")
  check(okP, "E: PLAYER_ENTERING_WORLD handled without error: " .. tostring(errP))
end
check(pickKey() == "holy", "E: PLAYER_ENTERING_WORLD re-reads the talents (got " .. tostring(pickKey()) .. ")")
check(type(CA._lastInvalidation) == "string" and CA._lastInvalidation:find("talents holy", 1, true) ~= nil,
  "E: and re-judges, because the pick moved (got " .. tostring(CA._lastInvalidation) .. ")")

-- ---- D. precedence ---------------------------------------------------------
install({ names = EXPECT.PALADIN[2], points = { 25, 0, 0 } })
setDB(nil, nil)
check(build().weightsKey == "holy", "D: Auto: Holy")
setDB("ret", nil)
local chosen = build()
check(chosen.weightsKey == "ret" and chosen.profileSource == "chosen", "D: a Gear-for pick wins over Auto")
setDB(nil, "melee")
local melee = build()
check(melee.weightsKey == nil and melee.recordedRole == "melee" and melee.role == "melee",
  "D: a recorded Melee role wins over Auto (got " .. tostring(melee.weightsKey) .. "/" .. tostring(melee.role) .. ")")
setDB(nil, "spell")
local spell = build()
check(spell.weightsKey == "holy" and spell.recordedRole == "spell" and spell.clientRole == "HEALER",
  "D: a recorded Spell role that agrees with Holy takes the tree's spec")
local slash = SlashCmdList and SlashCmdList.CHESTADVISOR
check(type(slash) == "function", "D: the slash handler is registered")
if type(slash) == "function" then pcall(slash, "role clear") end
check(ChestAdvisorDB.role.PALADIN == nil and build().weightsKey == "holy", "D: Clear is Auto")
check(V.healingContext(build()) == true, "D: Leveling + Auto Holy is a healing evaluation")
check(V.healerRoleHint(build()) == false, "D: and gets no role hint")

-- ---- F. the probe ----------------------------------------------------------
local function snap(t)
  local out = {}
  for k, x in pairs(t) do
    out[k] = type(x) == "table" and tostring(next(x) ~= nil) or tostring(x)
  end
  return out
end
local db0 = snap(ChestAdvisorDB)
local report = call("talentsReport") or ""
print("F. " .. report:gsub("\n", "\nF. "))
check(report:find("Touchstone talents (read-only):", 1, true) == 1, "F: the probe's header")
check(report:find("tree 1: Holy, orderIndex 0, 25 points spent", 1, true)
  and report:find("tree 2: Protection, orderIndex 1, 0 points spent", 1, true)
  and report:find("tree 3: Retribution, orderIndex 2, 0 points spent", 1, true),
  "F: each tree's name, orderIndex and points")
check(report:find("Auto picked: Holy (healer), gear for Holy", 1, true) ~= nil, "F: what Auto picked")
check(report:find("Role setting: Auto", 1, true) ~= nil, "F: the Role setting")
local db1 = snap(ChestAdvisorDB)
local same = true
for k, x in pairs(db0) do if db1[k] ~= x then same = false end end
for k in pairs(db1) do if db0[k] == nil then same = false end end
check(same, "F: the probe writes nothing to ChestAdvisorDB")
setDB("ret", "melee")
local r2 = call("talentsReport") or ""
check(r2:find("Role setting: Melee (overrides Auto)", 1, true) and r2:find("Gear for: Retribution (chosen; overrides Auto)", 1, true),
  "F: an override is named (got " .. r2 .. ")")
setDB(nil, nil)
install({ names = EXPECT.PALADIN[2], points = { 9, 9, 0 } })
local r3 = call("talentsReport") or ""
check(r3:find("Auto picked: nothing (a tie between talent trees); Touchstone works as before", 1, true) ~= nil,
  "F: no pick says why (got " .. r3 .. ")")
uninstall()
local r4 = call("talentsReport") or ""
check(r4:find("no talent trees read (the talent API is not on this client)", 1, true) ~= nil,
  "F: a client without the API says so (got " .. r4 .. ")")
install({ names = EXPECT.PALADIN[2], points = { 25, 0, 0 } })
if type(slash) == "function" then
  local ok, okCmd, out = pcall(slash, "talents")
  check(ok and okCmd == true and type(out) == "string" and out:find("Auto picked: Holy", 1, true) ~= nil,
    "F: /ts talents answers with the probe (got " .. tostring(out) .. ")")
  chat = {}
  pcall(slash, "diag")
  local joined = table.concat(chat, "\n")
  check(joined:find("Touchstone talents (read-only):", 1, true) ~= nil, "F: /up diag prints the talent read")
  chat = {}
  pcall(slash, "help")
  check(table.concat(chat, "\n"):find("/up talents", 1, true) ~= nil, "F: help lists /up talents")
end

-- ---- G. the Settings row ---------------------------------------------------
local COLOR = { accent = { 0.4, 0.9, 0.95 }, textMuted = { 0.6, 0.6, 0.6 } }
local function makeSF()
  local SF = { Colors = COLOR, optionControls = {}, VERSION = "spec" }
  SF.RegisterTab = function(name, render) SF._tab = { name = name, render = render } end
  function SF.UI_CreateLabel(parent, text)
    local fs = parent:CreateFontString()
    fs:SetText(text or "")
    return fs
  end
  function SF.UI_CreateButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 100, h or 24)
    b:SetText(text or "")
    return b
  end
  for _, n in ipairs({ "UI_SetAccent", "RepaintAccent", "SetTheme", "OnAccentRepaint", "SetWindowScale",
    "ShowDiagnosticsPanel", "UpdateMinimapButton" }) do SF[n] = function() end end
  function SF.UI_AccentText(s) return s end
  function SF.Accent(s) return "|cff66e6f2" .. tostring(s) .. "|r" end
  function SF.LogTabState() return {} end
  function SF.UpgradesTabState() return {} end
  function SF.ThemeAccent() return COLOR.accent end
  function SF.GetWindowScale() return 1 end
  function SF.WindowScaleBounds() return 0.5, 1.5 end
  return SF
end
local function settings()
  local sf = makeSF()
  local savedSF = StatForge
  StatForge = sf
  local chunk, err = loadfile(OPTIONS_SRC)
  local ok, e = false, err
  if chunk then ok, e = pcall(chunk, "MightiePack", pkg) end
  StatForge = savedSF
  check(ok, "G: OptionsTab.lua loads: " .. tostring(e))
  if not (ok and sf._tab) then return nil end
  local host = CreateFrame("Frame", nil, UIParent)
  host:SetSize(900, 441)
  local okR, eR = pcall(sf._tab.render, host)
  check(okR, "G: the Settings tab renders: " .. tostring(eR))
  return host
end
setDB(nil, nil)
local host = settings()
local label = host and host.roleClear and host.roleClear.label and host.roleClear.label:GetText()
check(label == "Auto (Holy: healer)", "G: the Auto box names what Auto picked (got " .. tostring(label) .. ")")
check(host and host.roleClear:GetChecked() == true, "G: Auto is the checked box with no recorded role")
local note = host and host.roleNote and host.roleNote:GetText()
check(note == "Role selects the stat order. Auto follows your talents.", "G: the role note (got " .. tostring(note) .. ")")
uninstall()
host = settings()
label = host and host.roleClear and host.roleClear.label and host.roleClear.label:GetText()
check(label == "Auto", "G: no pick: the box says Auto (got " .. tostring(label) .. ")")

-- ---- M. mutations ----------------------------------------------------------
local function runLeg(caPath, optPath)
  local lua = (arg and arg[-1]) or "lua5.1"
  local cmd = ("cd %q && TS_ADVISOR_SRC=%q TS_OPTIONS_SRC=%q %s tests/touchstone_talent_role_spec.lua 2>&1")
    :format(root, caPath, optPath, lua)
  local p = io.popen(cmd)
  local out = p and p:read("*a") or ""
  if p then p:close() end
  local n, k
  for a, b in out:gmatch("(%d+) check%(s%), (%d+) failed") do n, k = tonumber(a), tonumber(b) end
  return n, k, out
end
if not IN_LEG then
  local shippedCA = readFile(TOUCH .. "ChestAdvisor/ChestAdvisor.lua") or ""
  local shippedOpt = readFile(TOUCH .. "OptionsTab.lua") or ""
  local function legFile(text)
    local path = os.tmpname()
    local f = io.open(path, "w"); f:write(text); f:close()
    return path
  end
  local baseCA, baseOpt = legFile(shippedCA), legFile(shippedOpt)
  local bn, bk, bout = runLeg(baseCA, baseOpt)
  print(("M. baseline (unmutated, same command): %s check(s), %s failed"):format(tostring(bn), tostring(bk)))
  check(bn ~= nil and bn > 0 and bk == 0,
    "M: the unmutated files must run through the leg command and report 0 failed. Output:\n" .. bout:sub(-600))
  local MUTANTS = {
    { "the name cross-check dropped", "if j ~= i and (f == foldTree(m.name) or f == foldTree(m.alias)) then", "if false then" },
    { "the trees not sorted by orderIndex",
      "\ttable.sort(trees, function(a, b) return a.orderIndex < b.orderIndex end)\n", "" },
    { "a tie picks the first tree", "\tif tie then return nil, \"a tie between talent trees\" end\n", "" },
    { "no points still picks", "\tif total == 0 then return nil, \"no talent points spent\" end\n", "" },
    { "the tree count not checked", "if type(trees) ~= \"table\" or #trees ~= #map then", "if type(trees) ~= \"table\" then" },
    { "the outer pcall dropped",
      "\tlocal ok, trees, why = pcall(readTrees)\n\tif not ok then return nil, \"the talent read failed\" end\n\treturn trees, why",
      "\treturn readTrees()" },
    { "the config-info route dropped", "if treeID == nil and type(TR.GetConfigInfo) == \"function\" then", "if false then" },
    { "an event does not re-read", "\tcache.dirty = true\n\tlocal pick = ChestAdvisor.autoTalentPick(classToken())",
      "\tlocal pick = ChestAdvisor.autoTalentPick(classToken())" },
    { "a failed read is not retried", "\t\t\tcache.dirty = false\n\t\tend\n\t\tcache.pick",
      "\t\tend\n\t\tcache.dirty = false\n\t\tcache.pick" },
    { "every build re-reads", "\tif cache.dirty or cache.token ~= token then", "\tif true then" },
    { "the new events not registered", "\t\t\tpcall(frame.RegisterEvent, frame, tev)\n", "\t\t\tlocal _ = tev\n" },
    { "the new events unguarded", "\t\t\tpcall(frame.RegisterEvent, frame, tev)\n", "\t\t\tframe:RegisterEvent(tev)\n" },
    { "a talent event does not re-judge",
      "\t\t\t\tor ev == \"TRAIT_CONFIG_LIST_UPDATED\" or ev == \"ACTIVE_COMBAT_CONFIG_CHANGED\" then\n\t\t\t\tChestAdvisor._onTalentsChanged(ev)\n",
      "\t\t\t\tor ev == \"TRAIT_CONFIG_LIST_UPDATED\" or ev == \"ACTIVE_COMBAT_CONFIG_CHANGED\" then\n" },
    { "TRAIT_CONFIG_LIST_UPDATED not registered", "\"TRAIT_CONFIG_LIST_UPDATED\", \"ACTIVE_COMBAT_CONFIG_CHANGED\" }) do",
      "\"ACTIVE_COMBAT_CONFIG_CHANGED\" }) do" },
    { "TRAIT_CONFIG_LIST_UPDATED not handled", "or ev == \"TRAIT_CONFIG_LIST_UPDATED\" or ev == \"ACTIVE_COMBAT_CONFIG_CHANGED\" then",
      "or ev == \"ACTIVE_COMBAT_CONFIG_CHANGED\" then" },
    { "PLAYER_ENTERING_WORLD does not re-read",
      "\t\t\t\tif ev == \"PLAYER_ENTERING_WORLD\" then\n\t\t\t\t\tChestAdvisor._onTalentsChanged(ev)\n",
      "\t\t\t\tif false then\n\t\t\t\t\tChestAdvisor._onTalentsChanged(ev)\n" },
    { "PLAYER_TALENT_UPDATE does not re-read",
      "\t\t\t\tif ev == \"PLAYER_TALENT_UPDATE\" or ev == \"ACTIVE_TALENT_GROUP_CHANGED\" then\n\t\t\t\t\tChestAdvisor._onTalentsChanged(ev)\n",
      "\t\t\t\tif false then\n\t\t\t\t\tChestAdvisor._onTalentsChanged(ev)\n" },
    { "re-judges when nothing moved", "\tif before == after then return false end\n", "" },
    { "Feral reads as Bear", "alias = \"Feral\", key = \"feral_cat\"", "alias = \"Feral\", key = \"feral_bear\"" },
    { "the role word for a healer", "\tif r == \"HEALER\" then return \"healer\" end\n", "" },
    { "the role word for a tank", "\tif r == \"TANK\" then return \"tank\" end\n", "" },
    { "Auto never consulted by buildSpec", "\t\tif talent == nil and auto ~= nil then talent, fromTree = auto.entry, auto.tree end\n", "" },
    { "the talents command missing", "elseif subword == \"talents\" then", "elseif subword == \"talents-off\" then" },
    { "diag without the talent read", "\tchatOut(ChestAdvisor.talentsReport())\n", "" },
    { "help without /up talents", "\t\t.. \"  /up talents    show the talent trees Touchstone reads and what Auto picked (read-only)\\n\"\n", "" },
    { "the probe hides orderIndex", "(\"  tree %d: %s, orderIndex %s, %s points spent\"):format(\n\t\t\t\ti, tostring(t.name), tostring(t.orderIndex), tostring(t.spent))",
      "(\"  tree %d: %s, %s points spent\"):format(\n\t\t\t\ti, tostring(t.name), tostring(t.spent))" },
    { "a missing currency entry counted as read", "\t\tif spentBy[t.groupID] ~= nil then any = true end\n", "\t\tany = true\n" },
    { "a non-number point value accepted", "if type(n) ~= \"number\" or n < 0 then return nil, \"unreadable talent points\" end",
      "n = tonumber(n) or 0" },
  }
  -- One mapping mutant per class: its first two trees' keys swapped.
  local block = shippedCA:find("ChestAdvisor.TALENT_TREES = {", 1, true) or 1
  for _, token in ipairs(ORDER) do
    local e = EXPECT[token]
    local a = ("{ name = %q, key = %q }"):format(e[2][1], e[3][1])
    local at = shippedCA:find("\t" .. token .. " ", block, true)
    local s1 = at and shippedCA:find(a, at, true) or nil
    check(s1 ~= nil and s1 - at < 20, "M: mapping anchor for " .. token)
    MUTANTS[#MUTANTS + 1] = { token .. " tree 1 mapped to tree 2's spec", a,
      ("{ name = %q, key = %q }"):format(e[2][1], e[3][2]), at = s1 }
  end
  local OPT_MUTANTS = {
    { "the Auto box never labelled", "    host.roleClear.label:SetText(autoRoleText(token))\n", "" },
    { "the old role note", "Role selects the stat order. Auto follows your talents.",
      "Role selects the stat order. Leave it clear to use the spec." },
  }
  for _, m in ipairs(OPT_MUTANTS) do m.opt = true; MUTANTS[#MUTANTS + 1] = m end
  for _, m in ipairs(MUTANTS) do
    local srcText = m.opt and shippedOpt or shippedCA
    local s, e
    if m.at then
      s, e = m.at, m.at + #m[2] - 1
      check(srcText:sub(s, e) == m[2], "M: mutation anchor present: " .. m[1])
    else
      s, e = srcText:find(m[2], 1, true)
      check(s ~= nil, "M: mutation anchor present: " .. m[1])
      check(s == nil or srcText:find(m[2], e + 1, true) == nil, "M: mutation anchor is unique: " .. m[1])
    end
    if s ~= nil and bk == 0 then
      local mutated = srcText:sub(1, s - 1) .. m[3] .. srcText:sub(e + 1)
      local caP = m.opt and baseCA or legFile(mutated)
      local opP = m.opt and legFile(mutated) or baseOpt
      local n, k, out = runLeg(caP, opP)
      if m.opt then os.remove(opP) else os.remove(caP) end
      print(("M. mutant %-44s %s"):format(m[1],
        (n == nil) and "NO RESULT LINE" or (k > 0 and ("killed (" .. k .. "/" .. n .. ")") or "SURVIVED")))
      check(n ~= nil, "M: the mutant leg printed its result line: " .. m[1] .. ". Output:\n" .. out:sub(-400))
      check(n ~= nil and k > 0, "M: the spec fails on the mutant: " .. m[1])
    end
  end
  os.remove(baseCA); os.remove(baseOpt)
end

print(("%d check(s), %d failed"):format(checks, failed))
if failed > 0 then os.exit(1) end
