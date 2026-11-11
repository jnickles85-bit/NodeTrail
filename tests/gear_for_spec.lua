-- Gear-for-spec: a per-character override picks which spec Touchstone
-- scores and gates for, without inventing provisional weight numbers.
--
-- A registry entry can be chosen (slash / options / saved gearFor) even when
-- that spec has no sourced WEIGHTS table yet. In that case profileFor is
-- nil and the verdict is "no sourced weights for <spec> yet" — silence,
-- never a guess into another pack. ForeverDB leveling tables (top = 4)
-- ship for every spec that has one; Feral (Cat) is the one registry
-- entry with no table.
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
  WARRIOR = { "arms", "fury", "prot" },
  PALADIN = { "holy", "prot", "ret" },
  DRUID   = { "balance", "feral_cat", "feral_bear", "resto" },
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
      if class == "PALADIN" and word == "ret" then
        check(pack.kind == "order" and type(pack.tiers) == "table" and #pack.tiers >= 9,
          "Retribution is an order-only profile with the Wowhead tiers")
        check(pack.w == nil, "Retribution does not invent numeric weights")
        check(pack.source:find("wowhead.com/forever/guide/classes/paladin/retribution/stat-priority-pve-dps", 1, true),
          "Retribution source cites the Wowhead stat-priority page")
        check(pack.source:find("updated 2026-10-31", 1, true)
            and pack.source:find("cited 2026-11-11", 1, true),
          "Retribution source records the page date and the citation date")
        check(pack.source:find("shift", 1, true) or pack.source:find("beta", 1, true),
          "Retribution source notes the page is beta-based and will shift")
        check(pack.source:find("Order-only", 1, true),
          "Retribution source says the profile is order-only")
      else
        check(pack.source:find("foreverdb.net/data/bis/", 1, true),
          class .. "." .. tostring(word) .. " source cites ForeverDB")
        check(pack.source:find("ForeverDB hand-set leveling weights, client 1.60.1 build 70862", 1, true),
          class .. "." .. tostring(word) .. " source names the leveling set and client")
        check(type(pack.w) == "table", class .. "." .. tostring(word) .. " has a numeric w table")
      end
      check(pack.tiebreak == nil,
        class .. "." .. tostring(word) .. " has no tiebreak list")
      sourced = sourced + 1
  end
end
local ret = Verdict.WEIGHTS.PALADIN and Verdict.WEIGHTS.PALADIN.ret
check(ret ~= nil and type(ret.source) == "string" and ret.source ~= "",
  "Retribution (PALADIN.ret) has a non-empty source citation")
check(unsourced == 0, "every shipped profile is sourced (no leftover 4/1/0 tables)")
check(sourced == 27, "27 sourced profiles ship (26 ForeverDB numeric + Ret order-only; got "
  .. tostring(sourced) .. ")")

-- Feral (Cat) is the one registry entry with no PvE item-weight file.
check((Verdict.WEIGHTS.DRUID and Verdict.WEIGHTS.DRUID.feral_cat) == nil,
  "no guessed WEIGHTS.DRUID.feral_cat table (sim / order-only lists are not weights)")
check(Verdict.WEIGHTS.DRUID and Verdict.WEIGHTS.DRUID.feral_bear
    and Verdict.WEIGHTS.DRUID.resto,
  "Feral (Bear) and Restoration now have sourced tables")

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
check(Verdict.ratingFromPercent("Expertise", 1) == 10,
  "10 expertise rating = 1%")
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
mustClassify("healing-only sentence",
  { "Cand", "+10 Intellect", "Equip: Increases healing done by spells and effects by up to 20." },
  { "Eq",   "+10 Intellect" })
mustClassify("holy damage sentence",
  { "Cand", "+10 Strength", "Equip: Increases damage done by Holy spells and effects by up to 8." },
  { "Eq",   "+10 Strength" })
mustClassify("wand dps remaps off WeaponDps",
  { "Cand Wand", "Ranged Wand", "(12.5 damage per second)", "+5 Intellect" },
  { "Eq Wand",   "Ranged Wand", "(10.0 damage per second)", "+5 Intellect" })

-- Parser unit: a percent sentence lifts to rating; a rating-unit line stays raw.
-- Arms (a numeric ForeverDB pack) prices Crit and Strength at 4 per point, so
-- +1% crit is 14 * 4 = 56 and beats +4 Strength (4 * 4 = 16). If the parser
-- left the percent as 1, Strength would wrongly win (4 vs 16). Retribution is
-- order-only and is checked separately below (Strength outranks Crit there).
local armsSpec = { class = "WARRIOR", weightsKey = "arms", clientRole = "DAMAGER" }
local critItem = { "Crit Charm", "+1 Intellect", "Improves your chance to get a critical strike by 1%." }
local strItem  = { "Str Charm",  "+4 Strength", "+1 Intellect" }
local vCrit, rCrit, wCrit = Verdict.evaluate(
  { canUse = true, line = critItem }, { canUse = true, line = strItem }, armsSpec)
check(vCrit == "UPGRADE",
  "a +1% crit item beats +4 Strength on Arms (got " .. tostring(vCrit) .. " " .. tostring(rCrit) .. ")")
check(type(wCrit) == "table" and wCrit.total == 14*4 - 4*4,
  "Arms +1% crit vs +4 Str is 56 - 16 = 40 (got " .. tostring(wCrit and wCrit.total) .. ")")

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
check(chosen and chosen.profileLabel == "Protection",
  "chosen Protection profileLabel is Protection")
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
check(protOff and protOff.name == "Protection",
  "off-hand name is Protection when chosen (got " .. tostring(protOff and protOff.name) .. ")")
local policy = Verdict.shieldPolicy(protOff)
check(policy == "required",
  "a chosen Protection paladin requires a shield (got " .. tostring(policy) .. ")")

local tankProfile = Verdict.profileFor(protSpec)
check(tankProfile ~= nil and tankProfile == Verdict.WEIGHTS.PALADIN.prot,
  "chosen Protection scores with the sourced Paladin Protection table")
-- A Stamina/Block shield is better on the tank pack than a Strength-heavy one
-- would be for Ret: the tank table prices Stamina 4 and Block (if present).
local shieldW = Verdict.weightedTotal(
  { Stamina = 12, Block = 8, Strength = 0 },
  { Stamina = 0,  Block = 0, Strength = 10 },
  tankProfile)
check(type(shieldW) == "table" and shieldW.total > 0,
  "a Stamina/Block shield is an upgrade on the Protection tank pack (total="
    .. tostring(shieldW and shieldW.total) .. ")")

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
check(Verdict.profileFor(catSpec) == nil, "Feral (Cat) has no sourced weights yet")
local cv, cr = Verdict.weightedVerdict({ Agility = 10 }, { Agility = 0 }, catSpec)
check(cv == "UNKNOWN" and type(cr) == "string"
    and cr == "no sourced weights for " .. tostring(catSpec.profileLabel) .. " yet",
  "Feral (Cat) verdict is silence with an honest reason (got " .. tostring(cr) .. ")")

ChestAdvisor.setGearFor("feral_bear")
local bearOff = ChestAdvisor.readOffHandSpec()
check(bearOff and bearOff.role == "TANK",
  "Feral (Bear) sets the off-hand / shield identity to TANK")
local bv, br = Verdict.weightedVerdict({ Stamina = 10 }, { Stamina = 0 }, ChestAdvisor.buildSpec())
check(bv == "UPGRADE", "Feral (Bear) now scores with its sourced tank pack (got " .. tostring(bv) .. ")")
check(type(br) == "string" and br:find("Feral (Bear)", 1, true),
  "Feral (Bear) reason names the bear pack (got " .. tostring(br) .. ")")

-- Auto Feral (talent name "Feral" + DAMAGER) resolves to Feral (Cat) and
-- stays silent: there is still no item-weight table, so the verdict names
-- the unsourced cat spec rather than guessing Bear or Balance.
ChestAdvisor.setGearFor(nil)
ChestAdvisorDB.role = {}
asClass("DRUID", "Druid", "Feral", "DAMAGER")
local autoFeral = ChestAdvisor.buildSpec()
check(autoFeral and autoFeral.weightsKey == "feral_cat" and autoFeral.profileLabel == "Feral (Cat)",
  "Auto Feral + DAMAGER resolves to the Cat registry entry")
check(Verdict.profileFor(autoFeral) == nil,
  "Auto Feral (Cat) still has no sourced weights")
local afv, afr = Verdict.weightedVerdict({ Agility = 10 }, { Agility = 0 }, autoFeral)
check(afv == "UNKNOWN", "Auto Feral (Cat) is UNKNOWN")
check(type(afr) == "string" and afr == "no sourced weights for Feral (Cat) yet",
  "Auto Feral (Cat) names the unsourced spec (got " .. tostring(afr) .. ")")

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
