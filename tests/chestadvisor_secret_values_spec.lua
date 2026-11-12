-- chestadvisor_secret_values_spec.lua
--
-- Live crash on Forever 1.60.1 (Mightie, laptop), v0.3.4-beta / 8e2a95a
-- and 0dae750 (same line numbers):
--   Verdict.lua:4484: attempt to perform arithmetic on a secret number value
--   (execution tainted by 'MightiePack')
-- Stack: playerHitPercent (4471) <- orderVerdict (4742) <- evaluate (5560)
--        <- ChestAdvisor.scan (6284) <- _schedulePaperDollRefresh.pass (4230)
--        (character-sheet OnShow, delayed one tick).
--
-- pcallNumber only checked type(...) == "number". A secret number still has
-- type "number", so (bonus or 0) + (mod or 0) raised when GetHitModifier
-- or GetCombatRatingBonus returned a secret (melee branch, line 4484).
-- The same pattern exists on GetSpellHitModifier, GetExpertisePercent,
-- UnitDefense, and UnitAttackBothHands.
--
-- This spec injects a number that a stub issecretvalue flags, and proves
-- evaluate / the client readers do not error and do not use the secret
-- as a cap value. RED on 8e2a95a: playerHitPercent returns the secret
-- sum instead of nil.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

-- A unique "secret" number: type() == "number" (as on the live client)
-- and only issecretvalue may recognise it. Vanilla Lua can still add it,
-- which is why the assertions below require a nil/skip rather than a
-- successful sum — on the Forever client the + at Verdict.lua:4484 raises.
local SECRET_HIT = 42.125001
local SECRET_RATING = 7.125001
local SECRET_EXP = 3.125001
local SECRET_DEF = 200.125001
local SECRET_SKILL = 300.125001
local secrets = {
  [SECRET_HIT] = true,
  [SECRET_RATING] = true,
  [SECRET_EXP] = true,
  [SECRET_DEF] = true,
  [SECRET_SKILL] = true,
}
function issecretvalue(v)
  return secrets[v] == true
end

GetCombatRatingBonus = function() return nil end
GetHitModifier = function() return SECRET_HIT end
GetSpellHitModifier = function() return SECRET_HIT end
GetExpertisePercent = function() return SECRET_EXP end
CR_HIT_MELEE = 6
CR_HIT_SPELL = 8
CR_EXPERTISE = 24
UnitDefense = function() return SECRET_DEF, 0 end
UnitAttackBothHands = function() return SECRET_SKILL, 0, 0, 0 end
OffhandHasWeapon = function() return false end
UnitLevel = function() return 60 end

local chunk, err = loadfile(root .. "/MightiePack/Modules/Touchstone/ChestAdvisor/Verdict.lua")
check(chunk ~= nil, "loadfile Verdict.lua: " .. tostring(err))
local Verdict
if chunk then
  local ok, v = pcall(chunk)
  check(ok, "load Verdict.lua: " .. tostring(v))
  Verdict = (ok and v) or _G.Verdict
end
check(type(Verdict) == "table" and type(Verdict.playerHitPercent) == "function",
  "Verdict.playerHitPercent loaded")
check(type(Verdict.evaluate) == "function", "Verdict.evaluate loaded")

-- ════════════════════════════════════════════════════════════════════
-- 1. playerHitPercent must not add a secret GetHitModifier / bonus
-- ════════════════════════════════════════════════════════════════════
do
  local ok, got = pcall(function() return Verdict.playerHitPercent() end)
  check(ok, "1: playerHitPercent does not error when GetHitModifier is secret: "
    .. tostring(got))
  check(got == nil,
    "1: melee playerHitPercent returns nil rather than using the secret (got "
    .. tostring(got) .. ")")

  local okS, gotS = pcall(function() return Verdict.playerHitPercent("spell") end)
  check(okS, "1: playerHitPercent('spell') does not error when GetSpellHitModifier is secret: "
    .. tostring(gotS))
  check(gotS == nil,
    "1: spell playerHitPercent returns nil rather than using the secret (got "
    .. tostring(gotS) .. ")")
end

do
  -- Secret rating bonus, readable modifier: still skip (a partial sum would
  -- be a lie, and adding the secret raises on the live client).
  GetCombatRatingBonus = function() return SECRET_RATING end
  GetHitModifier = function() return 3 end
  GetSpellHitModifier = function() return 8 end
  local ok, got = pcall(function() return Verdict.playerHitPercent() end)
  check(ok, "1b: playerHitPercent does not error when GetCombatRatingBonus is secret: "
    .. tostring(got))
  check(got == nil,
    "1b: a secret combat-rating bonus is not added to GetHitModifier (got "
    .. tostring(got) .. ")")
  GetCombatRatingBonus = function() return nil end
  GetHitModifier = function() return SECRET_HIT end
  GetSpellHitModifier = function() return SECRET_HIT end
end

-- ════════════════════════════════════════════════════════════════════
-- 2. The same APIs used for Expertise / Defense / weapon skill
-- ════════════════════════════════════════════════════════════════════
do
  local ok, got = pcall(function() return Verdict.playerExpertisePercent() end)
  check(ok, "2: playerExpertisePercent does not error on a secret percent: "
    .. tostring(got))
  check(got == nil,
    "2: playerExpertisePercent returns nil for a secret GetExpertisePercent (got "
    .. tostring(got) .. ")")

  local okD, gotD = pcall(function() return Verdict.playerDefenseSkill() end)
  check(okD, "2: playerDefenseSkill does not error on a secret UnitDefense: "
    .. tostring(gotD))
  check(gotD == nil,
    "2: playerDefenseSkill returns nil for a secret UnitDefense (got "
    .. tostring(gotD) .. ")")

  local okW, gotW = pcall(function() return Verdict.playerWeaponSkill() end)
  check(okW, "2: playerWeaponSkill does not error on a secret UnitAttackBothHands: "
    .. tostring(gotW))
  check(gotW == nil,
    "2: playerWeaponSkill returns nil for a secret skill total (got "
    .. tostring(gotW) .. ")")
end

-- ════════════════════════════════════════════════════════════════════
-- 3. evaluate (the live stack's caller) does not error, and does not
--    treat the secret hit as a usable current cap.
-- ════════════════════════════════════════════════════════════════════
do
  local spec = { class = "WARRIOR", weightsKey = "arms", clientRole = "DAMAGER" }
  local ok, v, r = pcall(Verdict.evaluate, { "+10 Hit" }, { "+0 Hit" }, spec)
  check(ok, "3: evaluate does not error when GetHitModifier is a secret: "
    .. tostring(v))
  -- If the secret 42.12% were used as current hit, a +10 rating (~1%)
  -- candidate could be rejected as already past an 8% cap. With the
  -- secret skipped, cap status is unknown and evaluate still returns
  -- a verdict without raising.
  if ok then
    check(v ~= nil,
      "3: evaluate still returns a verdict when hit is unreadable (got "
      .. tostring(v) .. " " .. tostring(r) .. ")")
  end
end

-- Readable values still add, so the existing contract is unchanged.
do
  issecretvalue = function() return false end
  GetCombatRatingBonus = function() return 5 end
  GetHitModifier = function() return 3 end
  GetSpellHitModifier = function() return 8 end
  check(Verdict.playerHitPercent() == 8,
    "4: readable melee hit is still rating + GetHitModifier (got "
    .. tostring(Verdict.playerHitPercent()) .. ")")
  check(Verdict.playerHitPercent("spell") == 13,
    "4: readable spell hit is still rating + GetSpellHitModifier (got "
    .. tostring(Verdict.playerHitPercent("spell")) .. ")")
end

if failed > 0 then
  io.stderr:write(failed .. " failed\n")
  os.exit(1)
end
print("ok")
