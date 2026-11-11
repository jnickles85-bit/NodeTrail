-- Gear-for-spec: a per-character override picks which spec Touchstone
-- scores and gates for, without inventing provisional weight numbers.
--
-- Wowhead is the sole source: every Forever spec (all 28, including
-- Feral Cat) ships as an order-only, cap-aware profile generated from
-- data/wowhead_stat_priorities.json. Tank defaults are Wowhead's
-- Balanced list (Protection) or Defensive (Feral Bear). Variants are
-- also in the picker. A registry entry with no table would still be
-- silence ("no sourced weights for <spec> yet"), never a guessed pack.
--
-- Run from the repo root:  lua5.1 tests/gear_for_spec.lua

local here = (arg and arg[0] or "tests/gear_for_spec.lua")
  :match("^(.*)[/\\][^/\\]*$") or "."
local root = here:gsub("[/\\]tests$", "")
if root == "tests" then root = "." end
local TOUCH = root .. "/MightiePack/Modules/Touchstone/"

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local function fileExists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

if not fileExists(TOUCH .. "ChestAdvisor/ChestAdvisor.lua") then
  io.stderr:write("FAIL: the vendored Touchstone is absent — nothing to check\n")
  os.exit(1)
end

local chat, frames = {}, {}

local function makeTexture()
  local t = {}
  for _, m in ipairs({ "SetPoint", "SetAllPoints", "SetTexture", "SetColorTexture",
    "SetTexCoord", "SetSize", "Hide", "Show", "SetBlendMode", "SetDesaturated" }) do
    t[m] = function() end
  end
  return t
end

local function makeFontString()
  local fs = { text = "", shown = true }
  fs.SetPoint = function() end
  fs.SetAllPoints = function() end
  fs.SetText = function(_, v) fs.text = v end
  fs.GetText = function() return fs.text end
  fs.SetTextColor = function() end
  fs.SetWidth = function() end
  fs.SetJustifyH = function() end
  fs.SetWordWrap = function() end
  fs.SetNonSpaceWrap = function() end
  fs.Hide = function() fs.shown = false end
  fs.Show = function() fs.shown = true end
  fs.IsShown = function() return fs.shown == true end
  return fs
end

local function makeFrame(kind, name, parent, template)
  local f = { kind = kind, name = name, parent = parent, template = template,
              events = {}, scripts = {}, children = {},
              shown = true, enabled = true, text = nil, points = {} }
  if template == "UICheckButtonTemplate" then
    f.Text = makeFontString()
    f.text = f.Text
    f.checked = false
    f.SetChecked = function(_, v) f.checked = v and true or false end
    f.GetChecked = function() return f.checked end
  end
  f.RegisterEvent = function(_, e) f.events[e] = true end
  f.UnregisterEvent = function(_, e) f.events[e] = nil end
  f.IsEventRegistered = function(_, e) return f.events[e] == true end
  f.SetScript = function(_, k, fn) f.scripts[k] = fn end
  f.GetScript = function(_, k) return f.scripts[k] end
  f.HookScript = function() end
  f.CreateTexture = function() return makeTexture() end
  f.CreateFontString = function() return makeFontString() end
  f.SetPoint = function(_, ...) f.points[#f.points + 1] = { ... } end
  f.ClearAllPoints = function() f.points = {} end
  f.SetSize = function() end
  f.SetWidth = function() end
  f.SetHeight = function() end
  f.SetText = function(_, v) f.text = v end
  f.GetText = function() return f.text end
  f.Hide = function() f.shown = false end
  f.Show = function() f.shown = true end
  f.IsShown = function() return f.shown == true end
  f.Enable = function() f.enabled = true end
  f.Disable = function() f.enabled = false end
  f.IsEnabled = function() return f.enabled end
  frames[#frames + 1] = f
  if name then _G[name] = f end
  setmetatable(f, { __index = function() return function() end end })
  return f
end

local classToken, classDisplay = "PALADIN", "Paladin"
local specIdx, specName, specRole = 3, "Retribution", "DAMAGER"

local function resetEnv()
  chat, frames = {}, {}
  SlashCmdList = setmetatable({}, {
    __newindex = function(t, k, v) rawset(t, k, v) end,
  })
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
  CreateFrame = makeFrame
  UIParent = makeFrame("Frame", "UIParent")
  frames = {}
  MightiePackTouchstoneSkip = nil
  StatForge, StatForgeDB, ChestAdvisor, ChestAdvisorDB = nil, nil, nil, nil
  MightiePackDB = nil
  C_AddOns = { DoesAddOnExist = function() return false end }
  GetAddOnInfo, IsAddOnLoaded = nil, nil
  _G.ChestAdvisor_Frame = nil
  hooksecurefunc = function() end
  TooltipDataProcessor = { AddTooltipPostCall = function() end }
  Enum = { TooltipDataType = { Item = 0 } }
  UnitClass = function() return classDisplay, classToken end
  UnitLevel = function() return 25 end
  C_SpecializationInfo = {
    GetSpecialization = function() return specIdx end,
    GetSpecializationInfo = function(i)
      return i, specName, "desc", 0, specRole
    end,
  }
end

local function loaded(path, ...)
  local chunk, err = loadfile(path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return false end
  local ok, runErr = pcall(chunk, ...)
  check(ok, "load " .. path .. ": " .. tostring(runErr))
  return ok
end

local VENDORED = {
  "Constants.lua", "UI.lua", "OptionsTab.lua", "UpgradesTab.lua", "LogTab.lua",
  "Diagnostics.lua", "Probe.lua", "ChestAdvisor/Verdict.lua",
  "ChestAdvisor/ChestAdvisor.lua", "Integration.lua", "Core.lua",
}

resetEnv()
local pkg = { Print = function(_, msg) chat[#chat + 1] = tostring(msg) end }
loaded(TOUCH .. "Bootstrap.lua", "MightiePack", pkg)
for _, name in ipairs(VENDORED) do
  loaded(TOUCH .. name, "MightiePack", pkg)
end
check(type(ChestAdvisor) == "table", "the vendored ChestAdvisor loaded")
check(type(Verdict) == "table", "Verdict loaded")

ChestAdvisorDB = { role = {} }
local okEnable, enableErr = pcall(ChestAdvisor.Enable, ChestAdvisor)
check(okEnable, "ChestAdvisor.Enable runs: " .. tostring(enableErr))

-- ── Registry completeness ──────────────────────────────────────────
local REQUIRED = {
  WARRIOR = { "arms", "fury", "prot", "prot_defensive", "prot_offensive" },
  PALADIN = { "holy", "prot", "prot_defensive", "prot_offensive", "ret" },
  DRUID   = { "balance", "feral_cat", "feral_bear", "feral_bear_offensive", "resto" },
  SHAMAN  = { "elemental", "enhancement", "resto" },
  PRIEST  = { "holy", "disc", "shadow" },
  MAGE    = { "arcane", "fire", "frost" },
  WARLOCK = { "affliction", "demonology", "destruction" },
  ROGUE   = { "assassination", "combat", "subtlety" },
  HUNTER  = { "beast_mastery", "marksmanship", "survival" },
}

check(type(ChestAdvisor.specsFor) == "function", "ChestAdvisor.specsFor exists")
check(type(ChestAdvisor.lookupSpec) == "function", "ChestAdvisor.lookupSpec exists")
check(type(ChestAdvisor.parseSpecArg) == "function", "ChestAdvisor.parseSpecArg exists")
check(type(ChestAdvisor.gearForKey) == "function", "ChestAdvisor.gearForKey exists")
check(type(ChestAdvisor.setGearFor) == "function", "ChestAdvisor.setGearFor exists")
check(type(ChestAdvisor.buildSpec) == "function", "ChestAdvisor.buildSpec exists")
check(type(ChestAdvisor.readOffHandSpec) == "function", "ChestAdvisor.readOffHandSpec exists")

for class, keys in pairs(REQUIRED) do
  local list = ChestAdvisor.specsFor(class)
  check(type(list) == "table", class .. " has a registry list")
  local seen = {}
  if type(list) == "table" then
    check(#list == #keys, class .. " registry count is " .. tostring(#list)
      .. " expected " .. tostring(#keys))
    for _, e in ipairs(list) do
      check(type(e) == "table" and type(e.key) == "string" and e.key ~= "",
        class .. " entry has a key")
      check(type(e.name) == "string" and e.name ~= "",
        class .. " " .. tostring(e and e.key) .. " has a display name")
      check(e.role == "TANK" or e.role == "HEALER" or e.role == "DAMAGER",
        class .. " " .. tostring(e and e.key) .. " has a client role")
      check(type(e.weightsKey) == "string" and e.weightsKey ~= "",
        class .. " " .. tostring(e and e.key) .. " has a weightsKey")
      check(e.orderWord == "melee" or e.orderWord == "spell",
        class .. " " .. tostring(e and e.key) .. " has an order word")
      seen[e.key] = e
    end
  end
  for _, k in ipairs(keys) do
    check(seen[k] ~= nil, class .. " registry includes " .. k)
  end
end

-- Paladin / Warrior tank and healer roles, Druid cat/bear, Shaman/Priest resto/shadow
local function entry(class, key)
  return ChestAdvisor.lookupSpec(class, key)
end
check(entry("PALADIN", "prot") and entry("PALADIN", "prot").role == "TANK",
  "Paladin Protection is TANK")
check(entry("PALADIN", "holy") and entry("PALADIN", "holy").role == "HEALER",
  "Paladin Holy is HEALER")
check(entry("PALADIN", "ret") and entry("PALADIN", "ret").weightsKey == "ret",
  "Paladin Retribution uses the ret weights key")
check(entry("WARRIOR", "prot") and entry("WARRIOR", "prot").role == "TANK",
  "Warrior Protection is TANK")
check(entry("DRUID", "feral_cat") and entry("DRUID", "feral_cat").role == "DAMAGER",
  "Feral Cat is DAMAGER")
check(entry("DRUID", "feral_bear") and entry("DRUID", "feral_bear").role == "TANK",
  "Feral Bear is TANK")
check(entry("DRUID", "resto") and entry("DRUID", "resto").role == "HEALER",
  "Resto Druid is HEALER")
check(entry("SHAMAN", "resto") and entry("SHAMAN", "resto").role == "HEALER",
  "Resto Shaman is HEALER")
check(entry("PRIEST", "shadow") and entry("PRIEST", "shadow").role == "DAMAGER",
  "Shadow Priest is DAMAGER")

-- ── WEIGHTS source field; no guessed packs ─────────────────────────
check(type(Verdict.WEIGHTS) == "table", "Verdict.WEIGHTS exists")
local unsourced, sourced = 0, 0
for class, byRole in pairs(Verdict.WEIGHTS) do
  check(type(byRole) == "table", "WEIGHTS[" .. tostring(class) .. "] is a table")
  for word, pack in pairs(byRole) do
    check(type(pack) == "table", class .. "." .. tostring(word) .. " is a profile")
    check(type(pack.source) == "string" and pack.source ~= "",
        class .. "." .. tostring(word) .. " source is a non-empty citation")
      check(pack.kind == "order" and type(pack.tiers) == "table" and #pack.tiers > 0,
        class .. "." .. tostring(word) .. " is an order-only Wowhead profile")
      check(pack.w == nil, class .. "." .. tostring(word) .. " does not invent numeric weights")
      check(type(pack.url) == "string" and pack.url:find("wowhead.com/forever/guide/classes/", 1, true),
        class .. "." .. tostring(word) .. " records the Wowhead URL")
      check(type(pack.updated) == "string" and pack.updated:find("^%d%d%d%d%-%d%d%-%d%d$"),
        class .. "." .. tostring(word) .. " records the page updated date")
      check(pack.fetched == "2026-11-11",
        class .. "." .. tostring(word) .. " records fetched 2026-11-11")
      check(pack.source:find("wowhead.com/forever/guide/classes/", 1, true),
        class .. "." .. tostring(word) .. " source cites the Wowhead page")
      check(pack.source:find("updated " .. pack.updated, 1, true)
          and pack.source:find("fetched 2026-11-11", 1, true),
        class .. "." .. tostring(word) .. " source records updated + fetched dates")
      check(pack.source:find("Order-only", 1, true),
        class .. "." .. tostring(word) .. " source says the profile is order-only")
      check(pack.source:find("foreverdb", 1, true) == nil,
        class .. "." .. tostring(word) .. " does not cite ForeverDB")
      check(pack.tiebreak == nil,
        class .. "." .. tostring(word) .. " has no tiebreak list")
      sourced = sourced + 1
  end
end
local ret = Verdict.WEIGHTS.PALADIN and Verdict.WEIGHTS.PALADIN.ret
check(ret ~= nil and type(ret.source) == "string" and ret.source ~= "",
  "Retribution (PALADIN.ret) has a non-empty source citation")
check(ret.source:find("updated 2026-10-31", 1, true)
    and (ret.source:find("shift", 1, true) or ret.source:find("beta", 1, true)),
  "Retribution source notes the page date and that it is beta-based and will shift")
check(unsourced == 0, "every shipped profile is sourced (no leftover 4/1/0 tables)")
check(sourced == 33, "33 sourced Wowhead order-only profiles ship (28 specs + 5 tank variants; got "
  .. tostring(sourced) .. ")")

-- Feral (Cat) now has a sourced Wowhead order-only profile.
check(Verdict.WEIGHTS.DRUID and Verdict.WEIGHTS.DRUID.feral_cat
    and Verdict.WEIGHTS.DRUID.feral_cat.kind == "order",
  "Feral (Cat) has a sourced Wowhead order-only profile")
check(Verdict.WEIGHTS.DRUID and Verdict.WEIGHTS.DRUID.feral_bear
    and Verdict.WEIGHTS.DRUID.feral_bear.variant == "Defensive",
  "Feral (Bear) defaults to Wowhead's Defensive list")
check(Verdict.WEIGHTS.WARRIOR.prot.variant == "Balanced"
    and Verdict.WEIGHTS.PALADIN.prot.variant == "Balanced",
  "Protection Warrior and Paladin default to Wowhead's Balanced list")

-- Auto / no-override Feral melee stays nil (existing contract).
check(Verdict.profileFor({ class = "DRUID", role = "melee" }) == nil,
  "Druid melee without a weightsKey still has no profile")

-- Forever rating conversions: 14 crit rating = 1%, 10 hit rating = 1%.
check(Verdict.ratingFromPercent("Crit", 1) == 14,
  "14 crit rating = 1% (got " .. tostring(Verdict.ratingFromPercent("Crit", 1)) .. ")")
check(Verdict.ratingFromPercent("Hit", 1) == 10,
  "10 hit rating = 1% (got " .. tostring(Verdict.ratingFromPercent("Hit", 1)) .. ")")
check(Verdict.ratingFromPercent("Haste", 1) == 10,
  "10 haste rating = 1%")
check(Verdict.ratingFromPercent("Expertise", 1) == 1,
  "expertise has no sourced rating-per-percent and is not lifted (got "
    .. tostring(Verdict.ratingFromPercent("Expertise", 1)) .. ")")
check(Verdict.EXPERTISE_RATING_PER_PERCENT == nil,
  "EXPERTISE_RATING_PER_PERCENT is not invented")
check(Verdict.ratingFromPercent("Dodge", 1) == 12,
  "12 dodge rating = 1%")
check(Verdict.ratingFromPercent("Parry", 1) == 15,
  "15 parry rating = 1%")
check(Verdict.ratingFromPercent("BlockChance", 1) == 5,
  "5 block-chance rating = 1%")

-- weightedTotal accepts Hit / Crit / Defense / WeaponDps when a pack prices them.
-- The pack below is a test fixture, not a shipped profile.
local probePack = { name = "Probe", w = { Hit = 2, Crit = 3, Defense = 4, WeaponDps = 5 } }
local wt = Verdict.weightedTotal(
  { Hit = 10, Crit = 14, Defense = 8, WeaponDps = 12.5 },
  { Hit = 0,  Crit = 0,  Defense = 0, WeaponDps = 0 },
  probePack)
check(type(wt) == "table" and wt.total == 10*2 + 14*3 + 8*4 + 12.5*5,
  "weightedTotal prices Hit/Crit/Defense/WeaponDps (got " .. tostring(wt and wt.total) .. ")")

-- ── Parser vocabulary: rating-unit and weapon DPS lines ────────────
local function side(lines)
  return { canUse = true, line = lines }
end
local retSpec = { class = "PALADIN", role = "melee", clientRole = "DAMAGER" }

local function mustClassify(label, candLines, eqLines)
  local v, reason = Verdict.evaluate(side(candLines), side(eqLines), retSpec)
  check(type(reason) == "string", label .. " produced a reason")
  check(type(reason) ~= "string" or not reason:find("cannot classify", 1, true),
    label .. " must be placeable, got: " .. tostring(reason))
  return v, reason
end

mustClassify("14 Crit Rating",
  { "Cand", "+10 Strength", "+14 Crit Rating" },
  { "Eq",   "+10 Strength" })
mustClassify("10 Hit Rating",
  { "Cand", "+10 Strength", "+10 Hit Rating" },
  { "Eq",   "+10 Strength" })
mustClassify("critical strike rating spelling",
  { "Cand", "+10 Strength", "+14 Critical Strike Rating" },
  { "Eq",   "+10 Strength" })
mustClassify("defense rating",
  { "Cand", "+10 Strength", "+8 Defense Rating" },
  { "Eq",   "+10 Strength" })
mustClassify("weapon dps parenthetical",
  { "Cand", "+10 Strength", "(12.5 damage per second)" },
  { "Eq",   "+10 Strength" })
mustClassify("increases defense rating sentence",
  { "Cand", "+10 Strength", "Equip: Increases your defense rating by 8." },
  { "Eq",   "+10 Strength" })
mustClassify("percent crit still converts",
  { "Cand", "+10 Strength", "Improves your chance to get a critical strike by 1%." },
  { "Eq",   "+10 Strength" })
mustClassify("haste rating",
  { "Cand", "+10 Strength", "+10 Haste Rating" },
  { "Eq",   "+10 Strength" })
mustClassify("expertise rating",
  { "Cand", "+10 Strength", "+10 Expertise Rating" },
  { "Eq",   "+10 Strength" })
mustClassify("expertise percent text",
  { "Cand", "+10 Strength", "Equip: Increases your expertise by 1%." },
  { "Eq",   "+10 Strength" })
mustClassify("expertise dodge/parry reduction (Forever wording)",
  { "Cand", "+10 Strength", "Equip: Reduces the chance for your attacks to be dodged or parried by 1.0%." },
  { "Eq",   "+10 Strength" })
mustClassify("expertise short dodge/parry wording",
  { "Cand", "+10 Strength", "Equip: Reduces chance to be Dodged or Parried by 1.0%." },
  { "Eq",   "+10 Strength" })
mustClassify("healing-only sentence",
  { "Cand", "+10 Intellect", "Equip: Increases healing done by spells and effects by up to 20." },
  { "Eq",   "+10 Intellect" })
mustClassify("holy damage sentence",
  { "Cand", "+10 Strength", "Equip: Increases damage done by Holy spells and effects by up to 8." },
  { "Eq",   "+10 Strength" })
mustClassify("wand dps remaps off WeaponDps",
  { "Cand Wand", "Ranged Wand", "(12.5 damage per second)", "+5 Intellect" },
  { "Eq Wand",   "Ranged Wand", "(10.0 damage per second)", "+5 Intellect" })

-- Parser unit: a percent sentence lifts to rating (14 crit rating = 1%).
-- On the Arms Wowhead order, Crit is above Strength, so +1% crit still
-- beats +4 Strength — now by tier, not by a numeric 56-vs-16 product.
-- Retribution is checked separately below (Strength outranks Crit there).
local armsSpec = { class = "WARRIOR", weightsKey = "arms", clientRole = "DAMAGER" }
local critItem = { "Crit Charm", "+1 Intellect", "Improves your chance to get a critical strike by 1%." }
local strItem  = { "Str Charm",  "+4 Strength", "+1 Intellect" }
local parsedCrit = Verdict.statTable(critItem, "candidate")
check(type(parsedCrit) == "table" and parsedCrit.Crit == 14,
  "a +1% crit sentence lifts to 14 rating (got " .. tostring(parsedCrit and parsedCrit.Crit) .. ")")
local vCrit, rCrit, wCrit = Verdict.evaluate(
  { canUse = true, line = critItem }, { canUse = true, line = strItem }, armsSpec)
check(vCrit == "UPGRADE",
  "a +1% crit item beats +4 Strength on Arms (got " .. tostring(vCrit) .. " " .. tostring(rCrit) .. ")")
check(type(wCrit) == "table" and wCrit.decidedBy == "Crit",
  "Arms decides that pair by Crit (got " .. tostring(wCrit and wCrit.decidedBy) .. ")")

-- ── Override precedence ────────────────────────────────────────────
local function asClass(token, display, name, role)
  classToken, classDisplay = token, display
  specName, specRole = name, role
  if ChestAdvisor and type(ChestAdvisor._clearClassCache) == "function" then
    ChestAdvisor._clearClassCache()
  end
end

asClass("PALADIN", "Paladin", "Retribution", "DAMAGER")
ChestAdvisorDB = { role = {} }
ChestAdvisor.setGearFor(nil)
check(ChestAdvisor.gearForKey() == nil, "Auto (no override) reads as nil")

-- /up role melee while Auto: existing recorded-role path still works.
ChestAdvisorDB.role = { PALADIN = "melee" }
local autoSpec = ChestAdvisor.buildSpec()
check(autoSpec and autoSpec.role == "melee", "Auto + /up role melee keeps melee order")
check(autoSpec and autoSpec.profileSource ~= "chosen",
  "Auto path does not claim a chosen override")
-- /up role must not win over a valid gearFor.
local okSet, setMsg = ChestAdvisor.setGearFor("prot")
check(okSet ~= false, "setGearFor('prot') accepted on a Paladin: " .. tostring(setMsg))
check(ChestAdvisor.gearForKey() == "prot", "gearForKey is prot after set")
local chosen = ChestAdvisor.buildSpec()
check(chosen and chosen.weightsKey == "prot",
  "chosen Protection uses the prot weights key (got " .. tostring(chosen and chosen.weightsKey) .. ")")
check(chosen and chosen.clientRole == "TANK",
  "chosen Protection sets clientRole TANK (got " .. tostring(chosen and chosen.clientRole) .. ")")
check(chosen and chosen.profileSource == "chosen",
  "chosen Protection is labelled (chosen)")
check(chosen and chosen.profileLabel == "Protection (Balanced)",
  "chosen Protection profileLabel is Protection (Balanced)")
-- /up role spell is still saved, but gearFor wins.
ChestAdvisorDB.role.PALADIN = "spell"
local still = ChestAdvisor.buildSpec()
check(still and still.weightsKey == "prot" and still.profileSource == "chosen",
  "gearFor Protection wins over /up role spell")

-- Invalid override for this class is ignored (talents / recorded role resume).
local before = ChestAdvisor.gearForKey()
local okBad, badMsg = ChestAdvisor.setGearFor("resto")
check(okBad == false, "setGearFor('resto') is rejected on a Paladin: " .. tostring(badMsg))
check(ChestAdvisor.gearForKey() == before,
  "a rejected setGearFor leaves the previous override in place")
ChestAdvisorDB.gearFor = "feral_cat"
check(ChestAdvisor.gearForKey() == nil,
  "a leftover feral_cat key on a Paladin is ignored at read time")
ChestAdvisorDB.gearFor = "prot"
check(ChestAdvisor.gearForKey() == "prot", "valid leftover prot key is honoured")

-- ── Slash matching ─────────────────────────────────────────────────
local function slash(msg)
  chat = {}
  local fn = SlashCmdList.CHESTADVISOR or SlashCmdList.UPGRADE or SlashCmdList.UP
  -- Find the registered handler.
  if type(fn) ~= "function" then
    for k, v in pairs(SlashCmdList) do
      if type(v) == "function" then fn = v break end
    end
  end
  check(type(fn) == "function", "a /up slash handler is registered")
  if type(fn) == "function" then
    local ok, err = pcall(fn, msg)
    check(ok, "/up " .. tostring(msg) .. " ran: " .. tostring(err))
  end
  return table.concat(chat, "\n")
end

asClass("PALADIN", "Paladin", "Retribution", "DAMAGER")
ChestAdvisor.setGearFor(nil)
ChestAdvisorDB.role = {}

local function expectParse(class, arg, key)
  local got = ChestAdvisor.parseSpecArg(class, arg)
  check(got == key, "parseSpecArg(" .. class .. ", '" .. arg .. "') => "
    .. tostring(got) .. " expected " .. tostring(key))
end

expectParse("PALADIN", "auto", "auto")
expectParse("PALADIN", "talents", "auto")
expectParse("PALADIN", "prot", "prot")
expectParse("PALADIN", "protection", "prot")
expectParse("PALADIN", "tank", "prot")
expectParse("PALADIN", "ret", "ret")
expectParse("PALADIN", "retribution", "ret")
expectParse("PALADIN", "holy", "holy")
expectParse("DRUID", "resto", "resto")
expectParse("DRUID", "restoration", "resto")
expectParse("DRUID", "cat", "feral_cat")
expectParse("DRUID", "bear", "feral_bear")
expectParse("DRUID", "balance", "balance")
expectParse("SHAMAN", "resto", "resto")
expectParse("PRIEST", "shadow", "shadow")
expectParse("WARRIOR", "arms", "arms")
expectParse("WARRIOR", "fury", "fury")
expectParse("PRIEST", "disc", "disc")
expectParse("MAGE", "frost", "frost")
expectParse("HUNTER", "bm", "beast_mastery")
-- Ambiguous 'feral' names both cat and bear — no unique match.
local feral = ChestAdvisor.parseSpecArg("DRUID", "feral")
check(feral == nil, "parseSpecArg(DRUID, 'feral') is ambiguous (got " .. tostring(feral) .. ")")
-- A Paladin cannot pick resto.
check(ChestAdvisor.parseSpecArg("PALADIN", "resto") == nil,
  "parseSpecArg(PALADIN, 'resto') is rejected")

local out = slash("spec")
check(out:lower():find("auto", 1, true) or out:lower():find("talent", 1, true),
  "/up spec with no arg mentions Auto / talents: " .. out)
check(out:lower():find("protection", 1, true) or out:find("prot", 1, true),
  "/up spec with no arg lists Protection")

out = slash("spec prot")
check(ChestAdvisor.gearForKey() == "prot", "/up spec prot sets gearFor")
check(out:lower():find("protection", 1, true) or out:lower():find("prot", 1, true),
  "/up spec prot confirms Protection")

out = slash("spec auto")
check(ChestAdvisor.gearForKey() == nil, "/up spec auto clears the override")

out = slash("spec resto")
check(ChestAdvisor.gearForKey() == nil, "/up spec resto is rejected on a Paladin")
check(out:lower():find("reject", 1, true) or out:lower():find("unknown", 1, true)
    or out:lower():find("not a", 1, true) or out:lower():find("no match", 1, true),
  "/up spec resto on a Paladin is rejected honestly: " .. out)

out = slash("help")
check(out:find("/up spec", 1, true) or out:find("/ts spec", 1, true),
  "/up help lists /up spec")

-- ── Prot paladin chosen while Ret-talented: tank scoring + shield ──
asClass("PALADIN", "Paladin", "Retribution", "DAMAGER")
ChestAdvisorDB.role = { PALADIN = "melee" } -- would have been Ret / melee
ChestAdvisor.setGearFor("prot")
local protSpec = ChestAdvisor.buildSpec()
local protOff = ChestAdvisor.readOffHandSpec()
check(protOff and protOff.role == "TANK",
  "off-hand identity is TANK when Protection is chosen (got "
    .. tostring(protOff and protOff.role) .. ")")
check(protOff and protOff.name == "Protection (Balanced)",
  "off-hand name is Protection (Balanced) when chosen (got " .. tostring(protOff and protOff.name) .. ")")
local policy = Verdict.shieldPolicy(protOff)
check(policy == "required",
  "a chosen Protection paladin requires a shield (got " .. tostring(policy) .. ")")

local tankProfile = Verdict.profileFor(protSpec)
check(tankProfile ~= nil and tankProfile == Verdict.WEIGHTS.PALADIN.prot,
  "chosen Protection scores with the sourced Paladin Protection table")
-- A Stamina/Block shield is better on the tank pack than a Strength-heavy one
-- would be for Ret: Stamina is the first Wowhead Balanced tier.
local shieldV, shieldR = Verdict.weightedVerdict(
  { Stamina = 12, BlockChance = 8, Strength = 0 },
  { Stamina = 0,  BlockChance = 0, Strength = 10 },
  protSpec)
check(shieldV == "UPGRADE" and type(shieldR) == "string" and shieldR:find("Stamina", 1, true),
  "a Stamina/Block shield is an upgrade on the Protection tank pack (got "
    .. tostring(shieldV) .. " " .. tostring(shieldR) .. ")")

-- Verdict text carries (chosen) only when profileSource is set.
local wr = Verdict.weightedReason({ total = 4 }, tankProfile, "upgrade")
check(wr == "weighted +4 [" .. tankProfile.name .. "]",
  "weightedReason stays unadorned without a profileSource (got " .. tostring(wr) .. ")")
local wrChosen = Verdict.weightedReason({ total = 4 }, tankProfile, "upgrade", nil, "chosen")
check(type(wrChosen) == "string" and wrChosen:find("[" .. tankProfile.name .. " (chosen)]", 1, true),
  "weightedReason appends (chosen) when the source is passed: " .. tostring(wrChosen))

local vChosen, rChosen, dChosen = Verdict.weightedVerdict(
  { Stamina = 12, Block = 8 }, { Stamina = 0, Block = 0 }, protSpec)
check(vChosen == "UPGRADE", "Protection-chosen Stamina/Block scores an upgrade")
check(type(rChosen) == "string" and rChosen:find("(chosen)", 1, true),
  "Protection-chosen reason mentions (chosen): " .. tostring(rChosen))
check(dChosen and type(dChosen.profile) == "string" and dChosen.profile:find("(chosen)", 1, true),
  "Protection-chosen detail.profile mentions (chosen)")

-- Ret Auto (no gearFor) still scores with the Ret pack and no invented suffix
-- when profileSource is left unset — the existing [Retribution] contract.
ChestAdvisor.setGearFor(nil)
ChestAdvisorDB.role = {}
local retReason = Verdict.weightedReason({ total = -16 }, Verdict.WEIGHTS.PALADIN.ret, "downgrade")
check(retReason == "weighted -16 [Retribution]",
  "existing [Retribution] wording is unchanged without a profileSource")

-- ── Resto / Feral: picker works, no guessed weights ────────────────
asClass("DRUID", "Druid", "Balance", "DAMAGER")
ChestAdvisorDB.role = { DRUID = "spell" } -- would have scored as Balance
local okResto = ChestAdvisor.setGearFor("resto")
check(okResto ~= false, "a Balance-talented Druid can still choose Restoration")
check(ChestAdvisor.gearForKey() == "resto", "gearFor resto is stored")
local restoSpec = ChestAdvisor.buildSpec()
check(restoSpec and restoSpec.profileSource == "chosen"
    and restoSpec.profileLabel == "Restoration"
    and restoSpec.clientRole == "HEALER"
    and restoSpec.weightsKey == "resto",
  "chosen Restoration resolves identity/gates")
local restoPack = Verdict.profileFor(restoSpec)
check(restoPack ~= nil and restoPack == Verdict.WEIGHTS.DRUID.resto,
  "chosen Restoration scores with the sourced resto table, not Balance")
local rv, rr = Verdict.weightedVerdict({ Intellect = 10 }, { Intellect = 0 }, restoSpec)
check(rv == "UPGRADE", "Restoration with sourced weights scores Intellect (got " .. tostring(rv) .. ")")
check(type(rr) == "string" and rr:find("Restoration", 1, true) and rr:find("(chosen)", 1, true),
  "Restoration reason names the chosen pack (got " .. tostring(rr) .. ")")

-- /up role spell must not leak through while resto is chosen.
check(restoSpec.role == "spell" or restoSpec.orderWord == "spell"
    or (entry("DRUID", "resto") and entry("DRUID", "resto").orderWord == "spell"),
  "Restoration keeps the healer order word")
-- And it must not be the Balance profile.
check(restoPack ~= (Verdict.WEIGHTS.DRUID and Verdict.WEIGHTS.DRUID.balance),
  "Restoration is not scored as Balance")

local okCat = ChestAdvisor.setGearFor("feral_cat")
check(okCat ~= false, "Feral (Cat) is selectable")
local catSpec = ChestAdvisor.buildSpec()
check(catSpec and catSpec.profileLabel and catSpec.profileSource == "chosen"
    and catSpec.clientRole == "DAMAGER",
  "Feral (Cat) resolves a registry profile (picker/gates work)")
check(Verdict.profileFor(catSpec) ~= nil
    and Verdict.profileFor(catSpec).kind == "order",
  "Feral (Cat) now has a sourced Wowhead order-only profile")
local cv, cr = Verdict.weightedVerdict({ Agility = 10 }, { Agility = 0 }, catSpec)
check(cv == "UPGRADE", "Feral (Cat) scores Agility on the Wowhead order (got " .. tostring(cv) .. ")")
check(type(cr) == "string" and cr:find("Feral (Cat)", 1, true) and cr:find("(chosen)", 1, true),
  "Feral (Cat) reason names the chosen pack (got " .. tostring(cr) .. ")")

ChestAdvisor.setGearFor("feral_bear")
local bearOff = ChestAdvisor.readOffHandSpec()
check(bearOff and bearOff.role == "TANK",
  "Feral (Bear) sets the off-hand / shield identity to TANK")
local bv, br = Verdict.weightedVerdict({ Stamina = 10 }, { Stamina = 0 }, ChestAdvisor.buildSpec())
check(bv == "UPGRADE", "Feral (Bear) now scores with its sourced tank pack (got " .. tostring(bv) .. ")")
check(type(br) == "string" and br:find("Feral (Bear, Defensive)", 1, true),
  "Feral (Bear) reason names the Defensive pack (got " .. tostring(br) .. ")")

-- Auto Feral (talent name "Feral" + DAMAGER) resolves to Feral (Cat) and
-- now scores with the sourced Wowhead Cat list, not Bear or Balance.
ChestAdvisor.setGearFor(nil)
ChestAdvisorDB.role = {}
asClass("DRUID", "Druid", "Feral", "DAMAGER")
local autoFeral = ChestAdvisor.buildSpec()
check(autoFeral and autoFeral.weightsKey == "feral_cat" and autoFeral.profileLabel == "Feral (Cat)",
  "Auto Feral + DAMAGER resolves to the Cat registry entry")
check(Verdict.profileFor(autoFeral) ~= nil
    and Verdict.profileFor(autoFeral) == Verdict.WEIGHTS.DRUID.feral_cat,
  "Auto Feral (Cat) scores with the Cat Wowhead profile")
local afv, afr = Verdict.weightedVerdict({ Agility = 10 }, { Agility = 0 }, autoFeral)
check(afv == "UPGRADE", "Auto Feral (Cat) scores Agility (got " .. tostring(afv) .. ")")
check(type(afr) == "string" and afr:find("Feral (Cat)", 1, true),
  "Auto Feral (Cat) names the Cat pack (got " .. tostring(afr) .. ")")

-- ── Retribution order-only path (Wowhead priority) ────────────────
local retOrderSpec = { class = "PALADIN", role = "melee", clientRole = "DAMAGER",
  weightsKey = "ret" }
check(Verdict.isOrderProfile(Verdict.profileFor(retOrderSpec)) == true,
  "Retribution resolves to an order-only profile")

-- Tier decision: Hit outranks Strength, so +1% hit beats +20 Strength.
local vHit, rHit, dHit = Verdict.evaluate(
  { canUse = true, line = { "Hit Charm", "Improves your chance to hit by 1%." } },
  { canUse = true, line = { "Str Charm", "+20 Strength" } },
  retOrderSpec)
check(vHit == "UPGRADE", "Hit (tier 3) beats Strength (tier 7) on Ret (got "
  .. tostring(vHit) .. " " .. tostring(rHit) .. ")")
check(type(rHit) == "string" and rHit:find("decided by Hit", 1, true)
    and rHit:find("cap status unknown", 1, true),
  "unknown cap still ranks Hit and says so (got " .. tostring(rHit) .. ")")
check(dHit and dHit.decidedBy and dHit.decidedBy:find("Hit", 1, true),
  "detail.decidedBy names Hit")

-- On Ret, Strength outranks Crit, so +4 Str beats +1% crit (the inverse of Arms).
local vRetStr, rRetStr = Verdict.evaluate(
  { canUse = true, line = strItem }, { canUse = true, line = critItem }, retOrderSpec)
check(vRetStr == "UPGRADE" and type(rRetStr) == "string"
    and rRetStr:find("decided by Strength & Attack Power", 1, true),
  "Ret order: +4 Strength beats +1% crit (got " .. tostring(rRetStr) .. ")")

-- Intra-tier conflict: Strength up, Attack Power down → TRADE_OFF naming them.
-- Equal everything else.
local vConf, rConf = Verdict.evaluate(
  { canUse = true, line = { "A", "+10 Strength", "+4 Attack Power" } },
  { canUse = true, line = { "B", "+6 Strength", "+12 Attack Power" } },
  retOrderSpec)
check(vConf == "TRADE_OFF", "intra-tier Strength/AP conflict is TRADE_OFF (got "
  .. tostring(vConf) .. " " .. tostring(rConf) .. ")")
check(type(rConf) == "string" and rConf:find("Strength", 1, true)
    and rConf:find("Attack Power", 1, true) and rConf:find("conflict", 1, true),
  "TRADE_OFF names the conflicting stats (got " .. tostring(rConf) .. ")")

-- Same-direction intra-tier: both Strength and AP rise → upgrade, no conversion.
local vSame, rSame = Verdict.evaluate(
  { canUse = true, line = { "A", "+10 Strength", "+8 Attack Power" } },
  { canUse = true, line = { "B", "+6 Strength", "+4 Attack Power" } },
  retOrderSpec)
check(vSame == "UPGRADE" and type(rSame) == "string"
    and rSame:find("decided by Strength & Attack Power", 1, true),
  "same-direction Strength and AP is an upgrade (got " .. tostring(rSame) .. ")")

-- Cap clamp: player at 9% hit. A +20 hit-rating gain is entirely past cap
-- and must not decide; equal Strength → no change.
local atCap = { class = "PALADIN", role = "melee", clientRole = "DAMAGER",
  weightsKey = "ret", playerHitPercent = 9 }
local vCapGain, rCapGain = Verdict.evaluate(
  { canUse = true, line = { "A", "+10 Strength", "+20 Hit Rating" } },
  { canUse = true, line = { "B", "+10 Strength" } },
  atCap)
check(vCapGain == "NOT_UPGRADE" and type(rCapGain) == "string"
    and rCapGain:find("no change", 1, true),
  "a hit gain that is already at the 9% cap does not count (got " .. tostring(rCapGain) .. ")")

-- Cap clamp the other way: player at 9%, worn has the +20 hit rating, candidate
-- drops it. The loss falls below cap and decides a downgrade.
local vCapLoss, rCapLoss, dCapLoss = Verdict.evaluate(
  { canUse = true, line = { "A", "+10 Strength" } },
  { canUse = true, line = { "B", "+10 Strength", "+20 Hit Rating" } },
  atCap)
check(vCapLoss == "NOT_UPGRADE", "a hit loss that drops below the 9% cap counts (got "
  .. tostring(vCapLoss) .. " " .. tostring(rCapLoss) .. ")")
check(type(rCapLoss) == "string" and rCapLoss:find("decided by Hit (below 9% cap)", 1, true),
  "hit loss below cap is worded with the cap (got " .. tostring(rCapLoss) .. ")")

-- Below-cap gain still ranks, and the verdict names the cap.
local belowCap = { class = "PALADIN", role = "melee", clientRole = "DAMAGER",
  weightsKey = "ret", playerHitPercent = 7 }
local vBelow, rBelow = Verdict.evaluate(
  { canUse = true, line = { "A", "+10 Strength", "+20 Hit Rating" } },
  { canUse = true, line = { "B", "+10 Strength" } },
  belowCap)
check(vBelow == "UPGRADE" and type(rBelow) == "string"
    and rBelow:find("decided by Hit (below 9% cap)", 1, true),
  "a hit gain while below cap is decided by Hit (got " .. tostring(rBelow) .. ")")

-- Forced unknown cap still ranks the raw delta.
local unknownCap = { class = "PALADIN", role = "melee", clientRole = "DAMAGER",
  weightsKey = "ret", playerHitPercent = false }
local vUnk, rUnk = Verdict.evaluate(
  { canUse = true, line = { "A", "+10 Hit Rating" } },
  { canUse = true, line = { "B", "+10 Strength" } },
  unknownCap)
check(vUnk == "UPGRADE" and type(rUnk) == "string"
    and rUnk:find("cap status unknown", 1, true),
  "unreadable cap still ranks Hit and says unknown (got " .. tostring(rUnk) .. ")")

-- Weapon DPS tier: higher DPS wins even against more Strength (DPS is tier 2).
local vDps, rDps = Verdict.evaluate(
  { canUse = true, line = { "Fast", "Two-Hand Sword", "(20.0 damage per second)", "Speed 2.00", "+2 Strength" } },
  { canUse = true, line = { "Slow", "Two-Hand Sword", "(15.0 damage per second)", "Speed 3.60", "+20 Strength" } },
  retOrderSpec)
check(vDps == "UPGRADE" and type(rDps) == "string" and rDps:find("decided by Weapon DPS", 1, true),
  "higher weapon DPS decides before Strength (got " .. tostring(rDps) .. ")")

-- Equal DPS, different speed, later tier (Strength) decides; speed is not ranked.
local vSpd, rSpd, dSpd = Verdict.evaluate(
  { canUse = true, line = { "Fast", "Two-Hand Sword", "(18.0 damage per second)", "Speed 2.00", "+12 Strength" } },
  { canUse = true, line = { "Slow", "Two-Hand Sword", "(18.0 damage per second)", "Speed 3.60", "+8 Strength" } },
  retOrderSpec)
check(vSpd == "UPGRADE" and type(rSpd) == "string"
    and rSpd:find("decided by Strength & Attack Power", 1, true)
    and not rSpd:find("Weapon DPS", 1, true),
  "equal DPS defers to Strength; speed is not a ranking (got " .. tostring(rSpd) .. ")")
check(dSpd and type(dSpd.speedNote) == "string" and dSpd.speedNote:find("not ranked", 1, true),
  "equal-DPS speed difference is reported, not ranked")

-- Equal DPS, different speed, nothing else differs → no change, speed noted.
local vSpdOnly, rSpdOnly = Verdict.evaluate(
  { canUse = true, line = { "Fast", "Two-Hand Sword", "(18.0 damage per second)", "Speed 2.00", "+8 Strength" } },
  { canUse = true, line = { "Slow", "Two-Hand Sword", "(18.0 damage per second)", "Speed 3.60", "+8 Strength" } },
  retOrderSpec)
check(vSpdOnly == "NOT_UPGRADE" and type(rSpdOnly) == "string"
    and rSpdOnly:find("no change", 1, true)
    and rSpdOnly:find("weapon speed differs", 1, true)
    and rSpdOnly:find("not ranked", 1, true),
  "speed-only difference is no change, reported unranked (got " .. tostring(rSpdOnly) .. ")")

-- Weapon Skill outranks Weapon DPS.
local vSk, rSk = Verdict.evaluate(
  { canUse = true, line = { "Skill", "Two-Hand Sword", "+1 Swords", "(12.0 damage per second)", "Speed 3.60" } },
  { canUse = true, line = { "Dps",   "Two-Hand Sword", "(20.0 damage per second)", "Speed 3.60" } },
  retOrderSpec)
check(vSk == "UPGRADE" and type(rSk) == "string" and rSk:find("decided by Weapon Skill", 1, true),
  "Weapon Skill decides before Weapon DPS (got " .. tostring(rSk) .. ")")

-- ── Options 'Gear for' widget ──────────────────────────────────────
-- Load Options.lua against this already-booted pkg, with a stub Settings
-- surface so the panel is created.
asClass("PALADIN", "Paladin", "Retribution", "DAMAGER")
ChestAdvisor.setGearFor(nil)
ChestAdvisorDB.role = {}

Settings = Settings or {
  RegisterCanvasLayoutCategory = function(frame, name)
    return { frame = frame, name = name, GetID = function() return 1 end }
  end,
  RegisterAddOnCategory = function() end,
  OpenToCategory = function() end,
}
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopup_Show = StaticPopup_Show or function() end
InterfaceOptions_AddCategory = InterfaceOptions_AddCategory or function() end
GameTooltip = GameTooltip or {
  SetOwner = function() end, SetText = function() end,
  AddLine = function() end, Show = function() end, Hide = function() end,
}
pkg.moduleOrder = pkg.moduleOrder or { "Touchstone", "NodeTrail" }
pkg.modules = pkg.modules or {
  Touchstone = { title = "Touchstone", notes = "gear" },
  NodeTrail  = { title = "NodeTrail",  notes = "herbs" },
}
pkg.SetModuleEnabled = pkg.SetModuleEnabled or function() end
pkg.EnableModules = pkg.EnableModules or function() end
local enabledMods = { Touchstone = true, NodeTrail = true }
pkg.IsModuleEnabled = pkg.IsModuleEnabled or function(n) return enabledMods[n] == true end
pkg.optionsBoxes = nil

if not _G.MightiePackOptionsPanel then
  loaded(root .. "/MightiePack/Options.lua", "MightiePack", pkg)
end

local boxes = pkg.optionsBoxes
check(type(boxes) == "table", "optionsBoxes exists after Options.lua")

-- Widgets are created in syncCheckboxes, which runs on panel OnShow.
if _G.MightiePackOptionsPanel and _G.MightiePackOptionsPanel.scripts
    and _G.MightiePackOptionsPanel.scripts.OnShow then
  -- Touchstone on so the Gear-for row is shown and NodeTrail re-anchors.
  if type(pkg.SetModuleEnabled) == "function" then
    pcall(pkg.SetModuleEnabled, "Touchstone", true)
  end
  enabledMods.Touchstone = true
  pcall(_G.MightiePackOptionsPanel.scripts.OnShow, _G.MightiePackOptionsPanel)
end
if boxes and boxes.Touchstone and boxes.Touchstone.SetChecked then
  boxes.Touchstone:SetChecked(true)
end
if type(pkg.relayoutOptions) == "function" then pcall(pkg.relayoutOptions) end

check(boxes and boxes.GearFor ~= nil, "a Gear for widget was created")
if boxes and boxes.GearFor then
  check(boxes.GearForLabel ~= nil or (boxes.GearFor.GetText and boxes.GearFor:GetText()),
    "Gear for has a label or button text")
end

-- After Touchstone is on, NodeTrail sits under the Gear-for row (not overlapping).
if boxes and boxes.GearFor and boxes.NodeTrail then
  if type(boxes.GearFor.Show) == "function" then boxes.GearFor:Show() end
  -- Force a layout refresh if Options exposes one; otherwise click-sync.
  if type(pkg.relayoutOptions) == "function" then pcall(pkg.relayoutOptions) end
  local ntPts = boxes.NodeTrail.points
  if type(ntPts) == "table" and #ntPts > 0 then
    local last = ntPts[#ntPts]
    check(last[2] == boxes.GearFor or last[2] == boxes.GearForLabel
        or last[2] == boxes.GearForRow,
      "NodeTrail is re-anchored under the Gear-for widget when Touchstone is on")
  end
  -- Changing the picker rescans / sets gearFor.
  ChestAdvisor.setGearFor(nil)
  if type(boxes.GearFor.scripts) == "table" and type(boxes.GearFor.scripts.OnClick) == "function" then
    boxes.GearFor.scripts.OnClick(boxes.GearFor)
    check(ChestAdvisor.gearForKey() ~= nil or (boxes.GearFor.GetText and tostring(boxes.GearFor:GetText()):lower():find("auto")),
      "clicking Gear for changes the selection or stays on Auto after a cycle start")
  end
end


-- ── Second-cap Hit, leveling-only tiers, tank defaults ────────────
-- Rogue: Hit until 8%, then Hit to 17% (poison). Gains past 8% and
-- under 17% must not be swallowed by the first cap; they decide the
-- second Hit tier.
local rogueSpec = { class = "ROGUE", weightsKey = "combat", clientRole = "DAMAGER",
  playerHitPercent = 8 }
local vRogue, rRogue, dRogue = Verdict.weightedVerdict(
  { Hit = 20 }, { Hit = 0 }, rogueSpec) -- +2% on a 10-rating-per-percent scale
check(vRogue == "UPGRADE", "Rogue Hit past 8% toward 17% is an upgrade (got "
  .. tostring(vRogue) .. " " .. tostring(rRogue) .. ")")
check(type(rRogue) == "string" and rRogue:find("below 17%", 1, true),
  "the second Hit cap (17% poison) decides (got " .. tostring(rRogue) .. ")")

-- A player already at the 8% floor, gaining more hit, should not be
-- decided by the first Hit tier (delta 0 there) — only the 8–17 window.
local vRogueAt, rRogueAt = Verdict.weightedVerdict({ Hit = 10 }, { Hit = 0 }, rogueSpec)
-- 10 rating = 1%, current 8% -> cand 9%, first window [0,8] delta 0, second [8,17] delta 1
check(vRogueAt == "UPGRADE" and type(rRogueAt) == "string" and rRogueAt:find("17%", 1, true),
  "at the 8% floor, further Hit is decided by the 17% tier (got " .. tostring(rRogueAt) .. ")")

-- Leveling-only: Elemental Strength applies below 60 and is skipped at 60+.
local eleLow  = { class = "SHAMAN", weightsKey = "elemental", clientRole = "DAMAGER", level = 25 }
local eleMax  = { class = "SHAMAN", weightsKey = "elemental", clientRole = "DAMAGER", level = 60 }
local vEleLow, rEleLow = Verdict.weightedVerdict({ Strength = 10 }, { Strength = 0 }, eleLow)
local vEleMax, rEleMax = Verdict.weightedVerdict({ Strength = 10 }, { Strength = 0 }, eleMax)
check(vEleLow == "UPGRADE" and type(rEleLow) == "string" and rEleLow:find("Strength", 1, true),
  "Elemental Strength (Only while leveling) applies below 60 (got " .. tostring(rEleLow) .. ")")
check(vEleMax == "NOT_UPGRADE" and type(rEleMax) == "string" and rEleMax:find("no change", 1, true),
  "Elemental Strength is skipped at 60 (got " .. tostring(rEleMax) .. ")")

-- Feral Bear Offensive typo: Strength appears once, not twice.
local bearOffPack = Verdict.WEIGHTS.DRUID.feral_bear_offensive
local strCount = 0
if type(bearOffPack) == "table" and type(bearOffPack.tiers) == "table" then
  for _, tier in ipairs(bearOffPack.tiers) do
    if tier.name == "Strength" then strCount = strCount + 1 end
  end
end
check(strCount == 1, "Feral Bear Offensive keeps the first Strength and drops the typo duplicate (got "
  .. tostring(strCount) .. ")")

-- Talent name "Protection" still resolves to the Balanced default, not a variant.
asClass("PALADIN", "Paladin", "Protection", "TANK")
ChestAdvisor.setGearFor(nil)
ChestAdvisorDB.role = {}
local autoProt = ChestAdvisor.buildSpec()
check(autoProt and autoProt.weightsKey == "prot"
    and autoProt.profileLabel == "Protection (Balanced)",
  "Auto Protection talents resolve to the Balanced default (got "
    .. tostring(autoProt and autoProt.profileLabel) .. ")")
expectParse("PALADIN", "protection defensive", "prot_defensive")
expectParse("WARRIOR", "prot offensive", "prot_offensive")
expectParse("DRUID", "bear offensive", "feral_bear_offensive")


-- Enhancement keeps the published Wowhead order, but verdicts carry a
-- one-line caveat (profile.caveat) about the Nov 10 Mental Dexterity
-- hotfix. Other specs have no caveat field, so their reasons stay exact.
local enhPack = Verdict.WEIGHTS.SHAMAN.enhancement
check(enhPack and enhPack.kind == "order" and type(enhPack.caveat) == "string"
    and enhPack.caveat == "Wowhead list predates the Nov 10 Mental Dexterity hotfix; Intellect may be overrated. Hit past the listed 8% melee minimum is not scored.",
  "Enhancement has the Mental Dexterity caveat as a profile data field")
local enhNames = {}
if type(enhPack) == "table" and type(enhPack.tiers) == "table" then
  for _, tier in ipairs(enhPack.tiers) do enhNames[#enhNames + 1] = tier.name end
end
check(#enhNames == 11
    and enhNames[1] == "Hit" and enhNames[2] == "Expertise" and enhNames[3] == "Intellect"
    and enhNames[4] == "Spell Damage" and enhNames[5] == "Strength"
    and enhNames[11] == "Stamina",
  "Enhancement keeps the Wowhead numbered list exactly (11 tiers, no extra Hit window)")
local enhSpec = { class = "SHAMAN", weightsKey = "enhancement", clientRole = "DAMAGER" }
local vEnh, rEnh, dEnh = Verdict.weightedVerdict({ Intellect = 10 }, { Intellect = 0 }, enhSpec)
check(vEnh == "UPGRADE", "Enhancement still scores Intellect (got " .. tostring(vEnh) .. ")")
check(type(rEnh) == "string" and rEnh:find("decided by Intellect", 1, true)
    and rEnh:find(enhPack.caveat, 1, true),
  "Enhancement verdicts include the caveat (got " .. tostring(rEnh) .. ")")
check(dEnh and dEnh.caveat == enhPack.caveat, "the verdict detail carries profile.caveat")
local retPack = Verdict.WEIGHTS.PALADIN.ret
check(retPack and retPack.caveat == nil, "Retribution has no caveat field")
local vRetC, rRetC = Verdict.weightedVerdict({ Strength = 10 }, { Strength = 0 },
  { class = "PALADIN", weightsKey = "ret", clientRole = "DAMAGER" })
check(vRetC == "UPGRADE" and type(rRetC) == "string"
    and rRetC:find("Mental Dexterity", 1, true) == nil,
  "other specs do not get the Enhancement caveat (got " .. tostring(rRetC) .. ")")


-- ── Review NO-GO: Defense total, expertise percent, client APIs ────

-- Classic UnitDefense returns base, armorBonus; both are required.
local savedUnitDefense = UnitDefense
UnitDefense = function(unit)
  check(unit == "player", "UnitDefense is called with 'player'")
  return 300, 140
end
local defTotal = Verdict.playerDefenseSkill()
check(defTotal == 440, "UnitDefense(300, 140) is the 440 skill total (got "
  .. tostring(defTotal) .. ")")
UnitDefense = function(unit) return 300 end -- one return only (armorBonus nil)
check(Verdict.playerDefenseSkill() == 300,
  "UnitDefense with a missing modifier still uses the base (got "
    .. tostring(Verdict.playerDefenseSkill()) .. ")")
UnitDefense = savedUnitDefense

-- Prot Balanced: at the 440 Defense cap, +10 Defense is zero in the
-- "Defense until 440" window, so Armor decides. Candidate {Def 30,
-- Armor 0} vs worn {Def 20, Armor 50} is NOT_UPGRADE via Armor.
local protBal = { class = "PALADIN", weightsKey = "prot", clientRole = "TANK",
  playerDefense = 440 }
local vDef, rDef, dDef = Verdict.weightedVerdict(
  { Defense = 30, Armor = 0 }, { Defense = 20, Armor = 50 }, protBal)
check(vDef == "NOT_UPGRADE",
  "Prot Balanced at Defense 440: {Def30,Armor0} vs {Def20,Armor50} is NOT_UPGRADE (got "
    .. tostring(vDef) .. " " .. tostring(rDef) .. ")")
check(dDef and dDef.decidedBy == "Armor",
  "the deciding tier is Armor (got " .. tostring(dDef and dDef.decidedBy) .. ")")

-- Forever Expertise percent text is stored as a percent and compared
-- to Wowhead's 6.5% cap with no invented rating conversion.
local expLine = { "Exp Charm", "+1 Stamina", "Equip: Increases your expertise by 1%." }
local parsedExp = Verdict.statTable(expLine, "candidate")
check(type(parsedExp) == "table" and parsedExp.Expertise == 1,
  "expertise percent text is stored as 1 (percent), not lifted to a rating (got "
    .. tostring(parsedExp and parsedExp.Expertise) .. ")")
do
-- Real Forever item wording (Warden's Signet of Vigilance / T1 4P).
local foreverExpLine = { "Signet", "+18 Stamina",
  "Equip: Reduces the chance for your attacks to be dodged or parried by 1.0%." }
local parsedForever = Verdict.statTable(foreverExpLine)
check(type(parsedForever) == "table" and parsedForever.Expertise == 1
    and parsedForever.ExpertiseRating == nil,
  "Forever dodge/parry wording is Expertise 1% (got "
    .. tostring(parsedForever and parsedForever.Expertise) .. "/"
    .. tostring(parsedForever and parsedForever.ExpertiseRating) .. ")")
local shortForever = { "Signet", "Equip: Reduces chance to be Dodged or Parried by 1.0%." }
local parsedShort = Verdict.statTable(shortForever)
check(type(parsedShort) == "table" and parsedShort.Expertise == 1,
  "short Forever dodge/parry wording is Expertise 1% (got "
    .. tostring(parsedShort and parsedShort.Expertise) .. ")")
local setBonusLine = { "Tier",
  "Reduces the chance for your melee attacks to be Dodged or Parried by 1.2%." }
local parsedSet = Verdict.statTable(setBonusLine)
check(type(parsedSet) == "table" and parsedSet.Expertise == 1.2,
  "T1 set-bonus dodge/parry wording is Expertise 1.2% (got "
    .. tostring(parsedSet and parsedSet.Expertise) .. ")")
local shortRating = { "Ring", "+10 Expertise" }
local parsedShortRating = Verdict.statTable(shortRating)
check(type(parsedShortRating) == "table" and parsedShortRating.ExpertiseRating == 10
    and parsedShortRating.Expertise == nil,
  "+N Expertise short line is ExpertiseRating (got "
    .. tostring(parsedShortRating and parsedShortRating.ExpertiseRating) .. "/"
    .. tostring(parsedShortRating and parsedShortRating.Expertise) .. ")")
-- Percent text wins over ITEM_MOD_EXPERTISE_RATING on the same item.
do
  local lines = { "Signet", "+18 Stamina",
    "Equip: Reduces the chance for your attacks to be dodged or parried by 1.0%." }
  local apiWords = Verdict.apiStats({ ITEM_MOD_EXPERTISE_RATING = 10 })
  local parsedBoth = Verdict.statTable(lines, "candidate", apiWords)
  check(type(parsedBoth) == "table" and parsedBoth.Expertise == 1
      and parsedBoth.ExpertiseRating == nil,
    "percent Expertise wins over ITEM_MOD_EXPERTISE_RATING (got "
      .. tostring(parsedBoth and parsedBoth.Expertise) .. "/"
      .. tostring(parsedBoth and parsedBoth.ExpertiseRating) .. ")")
  local namedLines = { "Charm", "Equip: Increases your expertise by 1%." }
  local parsedNamed = Verdict.statTable(namedLines, "candidate", apiWords)
  check(type(parsedNamed) == "table" and parsedNamed.Expertise == 1
      and parsedNamed.ExpertiseRating == nil,
    "percent Expertise sentence wins over ITEM_MOD_EXPERTISE_RATING (got "
      .. tostring(parsedNamed and parsedNamed.Expertise) .. "/"
      .. tostring(parsedNamed and parsedNamed.ExpertiseRating) .. ")")
end
end
local armsExp = { class = "WARRIOR", weightsKey = "arms", clientRole = "DAMAGER",
  playerExpertisePercent = 5 }
local vExp, rExp, dExp = Verdict.weightedVerdict(
  { Expertise = 2 }, { Expertise = 0 }, armsExp)
-- current 5%, cand 7%, cap 6.5% -> effective +1.5, UPGRADE below cap
check(vExp == "UPGRADE" and type(rExp) == "string" and rExp:find("6.5%", 1, true),
  "expertise percent text is clamped at 6.5% (got " .. tostring(rExp) .. ")")

-- A rating-only Expertise line cannot be converted; cap status unknown.
local ratingLine = { "Exp Rating Charm", "+1 Stamina", "+20 Expertise Rating" }
local parsedRat = Verdict.statTable(ratingLine, "candidate")
check(type(parsedRat) == "table" and parsedRat.ExpertiseRating == 20
    and parsedRat.Expertise == nil,
  "expertise rating is stored as ExpertiseRating, not converted (got "
    .. tostring(parsedRat and parsedRat.ExpertiseRating) .. "/"
    .. tostring(parsedRat and parsedRat.Expertise) .. ")")
local armsUnk = { class = "WARRIOR", weightsKey = "arms", clientRole = "DAMAGER",
  playerExpertisePercent = 5 }
local vRat, rRat, dRat = Verdict.weightedVerdict(
  { ExpertiseRating = 20 }, { ExpertiseRating = 0 }, armsUnk)
check(vRat == "UPGRADE", "rating-only expertise still ranks the raw values (got "
  .. tostring(vRat) .. " " .. tostring(rRat) .. ")")
check(type(rRat) == "string" and rRat:find("unknown", 1, true),
  "rating-only expertise reports cap status unknown (got " .. tostring(rRat) .. ")")

do
-- Mixed percent-vs-rating Expertise: cap unknown / TRADE_OFF, not a
-- fake 0 percent on the rating-only side.
local mixSpec = { class = "WARRIOR", weightsKey = "arms", clientRole = "DAMAGER",
  playerExpertisePercent = false }
local vMix, rMix = Verdict.weightedVerdict(
  { Expertise = 1 }, { ExpertiseRating = 20 }, mixSpec)
check(vMix == "TRADE_OFF",
  "mixed percent-vs-rating Expertise is TRADE_OFF (got " .. tostring(vMix)
    .. " " .. tostring(rMix) .. ")")
check(type(rMix) == "string" and rMix:find("unknown", 1, true),
  "mixed Expertise reports cap status unknown (got " .. tostring(rMix) .. ")")
local vMix2, rMix2 = Verdict.weightedVerdict(
  { ExpertiseRating = 20 }, { Expertise = 1 }, mixSpec)
check(vMix2 == "TRADE_OFF",
  "mixed rating-vs-percent Expertise is TRADE_OFF (got " .. tostring(vMix2)
    .. " " .. tostring(rMix2) .. ")")
end

-- Caster 17% caps use GetSpellHitModifier, not GetHitModifier.
local savedBonus, savedHitMod, savedSpellMod = GetCombatRatingBonus, GetHitModifier, GetSpellHitModifier
GetCombatRatingBonus = function(cr) return 5 end
GetHitModifier = function() return 3 end
GetSpellHitModifier = function() return 8 end
CR_HIT_MELEE = CR_HIT_MELEE or 6
check(Verdict.playerHitPercent() == 8,
  "melee hit is rating + GetHitModifier (got " .. tostring(Verdict.playerHitPercent()) .. ")")
check(Verdict.playerHitPercent("spell") == 13,
  "spell hit is rating + GetSpellHitModifier, not GetHitModifier (got "
    .. tostring(Verdict.playerHitPercent("spell")) .. ")")
do
-- No invented CR_HIT_MELEE index when the global is missing.
local savedCRHit, savedCRSpell, savedCRMelee = CR_HIT, CR_HIT_SPELL, CR_HIT_MELEE
CR_HIT, CR_HIT_SPELL, CR_HIT_MELEE = nil, nil, nil
GetCombatRatingBonus = function(cr)
  error("guessed CR index " .. tostring(cr))
end
GetHitModifier = function() return 3 end
GetSpellHitModifier = function() return 8 end
check(Verdict.playerHitPercent() == 3,
  "melee hit with no CR_* global uses only GetHitModifier (got "
    .. tostring(Verdict.playerHitPercent()) .. ")")
check(Verdict.playerHitPercent("spell") == 8,
  "spell hit with no CR_* global uses only GetSpellHitModifier (got "
    .. tostring(Verdict.playerHitPercent("spell")) .. ")")
CR_HIT, CR_HIT_SPELL, CR_HIT_MELEE = savedCRHit, savedCRSpell, savedCRMelee
GetCombatRatingBonus, GetHitModifier, GetSpellHitModifier = savedBonus, savedHitMod, savedSpellMod
end

-- GetExpertise is not assumed to be a percent.
local savedExp, savedExpPct, savedCRB = GetExpertise, GetExpertisePercent, GetCombatRatingBonus
GetExpertise = function() return 65 end
GetExpertisePercent = nil
GetCombatRatingBonus = nil
CR_EXPERTISE = nil
check(Verdict.playerExpertisePercent() == nil,
  "GetExpertise alone is not treated as a percent (got "
    .. tostring(Verdict.playerExpertisePercent()) .. ")")
GetCombatRatingBonus = function(cr) if cr == 24 then return 6.5 end end
CR_EXPERTISE = 24
check(Verdict.playerExpertisePercent() == 6.5,
  "GetCombatRatingBonus(CR_EXPERTISE) is the client's own percent (got "
    .. tostring(Verdict.playerExpertisePercent()) .. ")")
-- No invented CR_EXPERTISE index of 24 when the global is missing.
CR_EXPERTISE = nil
GetCombatRatingBonus = function(cr)
  error("guessed CR_EXPERTISE index " .. tostring(cr))
end
check(Verdict.playerExpertisePercent() == nil,
  "nil CR_EXPERTISE is not guessed as 24 (got "
    .. tostring(Verdict.playerExpertisePercent()) .. ")")
GetExpertise, GetExpertisePercent, GetCombatRatingBonus = savedExp, savedExpPct, savedCRB

-- Clearing every CR_HIT* / CR_EXPERTISE global, with no modifier API,
-- must leave current hit/expertise nil and cap status unknown. If the
-- guessed `or 6` / `or 24` fallbacks were restored, GetCombatRatingBonus
-- would return 99 and these checks would fail.
do
  local savedBonus, savedHit, savedSpell, savedExpPct =
    GetCombatRatingBonus, GetHitModifier, GetSpellHitModifier, GetExpertisePercent
  local savedCRHit, savedCRSpell, savedCRMelee, savedCRExp =
    CR_HIT, CR_HIT_SPELL, CR_HIT_MELEE, CR_EXPERTISE
  GetCombatRatingBonus = function(cr)
    if cr == 6 or cr == 24 then return 99 end
    return nil
  end
  GetHitModifier, GetSpellHitModifier, GetExpertisePercent = nil, nil, nil
  CR_HIT, CR_HIT_SPELL, CR_HIT_MELEE, CR_EXPERTISE = nil, nil, nil, nil
  check(Verdict.playerHitPercent() == nil,
    "cleared CR_HIT* is nil, not guessed as 6 (got "
      .. tostring(Verdict.playerHitPercent()) .. ")")
  check(Verdict.playerHitPercent("spell") == nil,
    "cleared CR_HIT* spell hit is nil, not guessed as 6 (got "
      .. tostring(Verdict.playerHitPercent("spell")) .. ")")
  check(Verdict.playerExpertisePercent() == nil,
    "cleared CR_EXPERTISE is nil, not guessed as 24 (got "
      .. tostring(Verdict.playerExpertisePercent()) .. ")")
  local vUnk, rUnk = Verdict.weightedVerdict(
    { Hit = 10 }, { Hit = 0 },
    { class = "MAGE", weightsKey = "arcane", clientRole = "DAMAGER" })
  check(type(rUnk) == "string" and rUnk:find("unknown", 1, true),
    "cleared CR_HIT* reports cap status unknown (got " .. tostring(vUnk)
      .. " " .. tostring(rUnk) .. ")")
  GetCombatRatingBonus, GetHitModifier, GetSpellHitModifier, GetExpertisePercent =
    savedBonus, savedHit, savedSpell, savedExpPct
  CR_HIT, CR_HIT_SPELL, CR_HIT_MELEE, CR_EXPERTISE =
    savedCRHit, savedCRSpell, savedCRMelee, savedCRExp
end

-- Weapon skill is a skill total, not GetCombatRating(CR_WEAPON_SKILL).
-- Off-hand is used only when an off-hand weapon is equipped: Classic
-- reports the unarmed skill in the off-hand slots for a 2H or a shield.
do
  local savedUABH, savedGCR = UnitAttackBothHands, GetCombatRating
  local savedOHW, savedInv, savedCItem, savedInstant =
    OffhandHasWeapon, GetInventoryItemLink, C_Item, GetItemInfoInstant
  GetCombatRating = function(cr) return 999 end
  CR_WEAPON_SKILL = CR_WEAPON_SKILL or 1
  OffhandHasWeapon, GetInventoryItemLink, C_Item, GetItemInfoInstant = nil, nil, nil, nil
  UnitAttackBothHands = function(unit)
    check(unit == "player", "UnitAttackBothHands is called with 'player'")
    return 300, 8, 0, 0
  end
  check(Verdict.playerWeaponSkill() == 308,
    "UnitAttackBothHands(300, 8) is the 308 skill total, not a combat rating (got "
      .. tostring(Verdict.playerWeaponSkill()) .. ")")

  -- Review repro: unarmed off-hand skill on a 2H or shield must not
  -- replace the main-hand total.
  OffhandHasWeapon = function() return false end
  UnitAttackBothHands = function() return 300, 8, 150, 0 end
  check(Verdict.playerWeaponSkill() == 308,
    "2H/shield unarmed off-hand (300,8,150,0) is main-hand 308 (got "
      .. tostring(Verdict.playerWeaponSkill()) .. ")")

  -- Dual-wield: the lower total is used when an off-hand weapon is on.
  OffhandHasWeapon = function() return true end
  UnitAttackBothHands = function() return 300, 8, 300, 2 end
  check(Verdict.playerWeaponSkill() == 302,
    "dual-wield (300,8,300,2) uses the lower hand 302 (got "
      .. tostring(Verdict.playerWeaponSkill()) .. ")")
  UnitAttackBothHands = function() return 300, 8, 200, 0 end
  check(Verdict.playerWeaponSkill() == 200,
    "dual-wield uses the lower hand (got " .. tostring(Verdict.playerWeaponSkill()) .. ")")
  UnitAttackBothHands = function() return 300, 8, 305, 5 end
  check(Verdict.playerWeaponSkill() == 308,
    "dual-wield uses main when it is the lower total (got "
      .. tostring(Verdict.playerWeaponSkill()) .. ")")

  -- Fallback: no OffhandHasWeapon; slot 17 + GetItemInfoInstant.
  OffhandHasWeapon = nil
  GetInventoryItemLink = function(unit, slot)
    check(unit == "player" and slot == 17, "off-hand inspect is slot 17")
    return "item:1"
  end
  GetItemInfoInstant = function(link)
    return 1, "Weapon", "Dagger", "INVTYPE_WEAPON", "icon", 2, 15
  end
  UnitAttackBothHands = function() return 300, 8, 300, 2 end
  check(Verdict.playerWeaponSkill() == 302,
    "slot-17 INVTYPE_WEAPON uses the lower hand (got "
      .. tostring(Verdict.playerWeaponSkill()) .. ")")
  GetItemInfoInstant = function(link)
    return 1, "Armor", "Shield", "INVTYPE_SHIELD", "icon", 4, 6
  end
  UnitAttackBothHands = function() return 300, 8, 150, 0 end
  check(Verdict.playerWeaponSkill() == 308,
    "slot-17 INVTYPE_SHIELD ignores unarmed off-hand (got "
      .. tostring(Verdict.playerWeaponSkill()) .. ")")

  UnitAttackBothHands, GetCombatRating = savedUABH, savedGCR
  OffhandHasWeapon, GetInventoryItemLink, C_Item, GetItemInfoInstant =
    savedOHW, savedInv, savedCItem, savedInstant
end

-- Enhancement follows the Wowhead numbered list exactly: one Hit tier
-- (the 8% melee minimum) and no appended 17% window. Hit past 8% is
-- zeroed by that cap and does not decide the verdict.
local enhHitPack = Verdict.WEIGHTS.SHAMAN.enhancement
local hitTiers = 0
local has17 = false
if type(enhHitPack) == "table" and type(enhHitPack.tiers) == "table" then
  for _, tier in ipairs(enhHitPack.tiers) do
    if tier.name == "Hit" then
      hitTiers = hitTiers + 1
      if tier.capPercent == 17 then has17 = true end
    end
  end
end
check(hitTiers == 1 and not has17,
  "Enhancement has only the listed 8% Hit tier (got " .. tostring(hitTiers)
    .. " Hit tiers, 17% window=" .. tostring(has17) .. ")")
local enhHitSpec = { class = "SHAMAN", weightsKey = "enhancement", clientRole = "DAMAGER",
  playerHitPercent = 8 }
local vEnhHit, rEnhHit = Verdict.weightedVerdict({ Hit = 10 }, { Hit = 0 }, enhHitSpec)
check(vEnhHit == "NOT_UPGRADE" and type(rEnhHit) == "string" and rEnhHit:find("no change", 1, true),
  "Enhancement hit past 8% does not score (got " .. tostring(vEnhHit) .. " " .. tostring(rEnhHit) .. ")")

do
-- Spell-profile Hit tiers are hitKind="spell" (Arcane/Fire caps text
-- never says "spell cap"; the family comes from SPEC_KEYS).
local function hitKinds(pack)
  local kinds = {}
  if type(pack) == "table" and type(pack.tiers) == "table" then
    for _, tier in ipairs(pack.tiers) do
      if tier.name == "Hit" then
        kinds[#kinds + 1] = tier.hitKind
      end
    end
  end
  return kinds
end
local arcaneKinds = hitKinds(Verdict.WEIGHTS.MAGE.arcane)
local fireKinds = hitKinds(Verdict.WEIGHTS.MAGE.fire)
check(#arcaneKinds > 0 and arcaneKinds[1] == "spell",
  "WEIGHTS.MAGE.arcane Hit is hitKind=spell (got " .. tostring(arcaneKinds[1]) .. ")")
check(#fireKinds > 0 and fireKinds[1] == "spell",
  "WEIGHTS.MAGE.fire Hit is hitKind=spell (got " .. tostring(fireKinds[1]) .. ")")
local spellPacks = {
  { "MAGE", "arcane" }, { "MAGE", "fire" }, { "MAGE", "frost" },
  { "WARLOCK", "affliction" }, { "WARLOCK", "demonology" }, { "WARLOCK", "destruction" },
  { "PRIEST", "disc" }, { "PRIEST", "holy" }, { "PRIEST", "shadow" },
  { "DRUID", "balance" }, { "DRUID", "resto" },
  { "SHAMAN", "elemental" }, { "SHAMAN", "resto" },
  { "PALADIN", "holy" },
}
for i = 1, #spellPacks do
  local className, key = spellPacks[i][1], spellPacks[i][2]
  local pack = Verdict.WEIGHTS[className] and Verdict.WEIGHTS[className][key]
  local kinds = hitKinds(pack)
  for j = 1, #kinds do
    check(kinds[j] == "spell",
      className .. "." .. key .. " Hit #" .. j .. " must be hitKind=spell (got "
        .. tostring(kinds[j]) .. ")")
  end
end
-- Hybrid melee lists keep their later spell/poison cap as spell, and
-- Enhancement stays melee (numbered list is the 8% minimum only).
local protHit = hitKinds(Verdict.WEIGHTS.PALADIN.prot)
check(#protHit >= 2 and protHit[1] == "melee" and protHit[2] == "spell",
  "Prot Paladin keeps melee then spell Hit kinds (got "
    .. tostring(protHit[1]) .. "/" .. tostring(protHit[2]) .. ")")
local rogHit = hitKinds(Verdict.WEIGHTS.ROGUE.assassination)
check(#rogHit >= 2 and rogHit[1] == "melee" and rogHit[2] == "spell",
  "Rogue keeps melee then poison-cap spell Hit kinds (got "
    .. tostring(rogHit[1]) .. "/" .. tostring(rogHit[2]) .. ")")
local enhKinds = hitKinds(Verdict.WEIGHTS.SHAMAN.enhancement)
check(#enhKinds == 1 and enhKinds[1] == "melee",
  "Enhancement Hit stays melee (got " .. tostring(enhKinds[1]) .. ")")

-- Review repro: rating bonus 11 + GetSpellHitModifier 6 = 17%, so a
-- +1% hit candidate is NOT_UPGRADE for Arcane and Fire. If hitKind
-- were melee, GetHitModifier 0 would leave the player at 11% and the
-- same candidate would incorrectly be an UPGRADE.
local savedBonus2, savedHit2, savedSpell2 = GetCombatRatingBonus, GetHitModifier, GetSpellHitModifier
local savedCRSpell2 = CR_HIT_SPELL
GetCombatRatingBonus = function() return 11 end
GetSpellHitModifier = function() return 6 end
GetHitModifier = function() return 0 end
CR_HIT_SPELL = CR_HIT_SPELL or 8
for _, key in ipairs({ "arcane", "fire" }) do
  local spec = { class = "MAGE", weightsKey = key, clientRole = "DAMAGER" }
  local vHit, rHit = Verdict.weightedVerdict({ Hit = 10 }, { Hit = 0 }, spec)
  check(vHit == "NOT_UPGRADE",
    "MAGE." .. key .. " 17% spell hit (11+6) rejects +1% hit (got "
      .. tostring(vHit) .. " " .. tostring(rHit) .. ")")
end
GetCombatRatingBonus, GetHitModifier, GetSpellHitModifier = savedBonus2, savedHit2, savedSpell2
CR_HIT_SPELL = savedCRSpell2
end

-- /up spec Auto text names a recorded /up role.
asClass("PALADIN", "Paladin", "Retribution", "DAMAGER")
ChestAdvisor.setGearFor(nil)
ChestAdvisorDB.role = { PALADIN = "melee" }
local outRole = slash("spec")
check(outRole:find("/up role melee", 1, true),
  "/up spec Auto names the recorded /up role: " .. outRole)
ChestAdvisor.setGearFor("ret")
local outChosen = slash("reset")
check(ChestAdvisor.gearForKey() == nil, "/up reset clears the chosen Gear-for spec")
check(ChestAdvisorDB.role and ChestAdvisorDB.role.PALADIN == "melee",
  "/up reset does not clear /up role")
check(outChosen:lower():find("auto", 1, true) or outChosen:lower():find("cleared", 1, true),
  "/up reset mentions the Gear-for clear: " .. outChosen)
ChestAdvisorDB.role = {}

-- Direct options-style set still rescans (scan is a function after Enable).
local scans = 0
local realScan = ChestAdvisor.scan
ChestAdvisor.scan = function(...)
  scans = scans + 1
  if type(realScan) == "function" then return realScan(...) end
end
ChestAdvisor.setGearFor("ret")
check(scans >= 1, "setGearFor triggers an immediate rescan")
ChestAdvisor.scan = realScan

if failed > 0 then
  io.stderr:write(failed .. " check(s) failed\n")
  os.exit(1)
end
print("gear_for_spec: ok")
