-- touchstone_tiebreak_single_rule_spec.lua — t_a5de2f16, review item 3.
--
-- The ranked comparator has ONE named floor for "these two numbers are the same
-- rank": WEIGHT_EPSILON, read through `ranksAsDifferent`. `tiebreakTotal` used
-- to spell the same comparison out inline
-- (`delta > (Verdict.WEIGHT_EPSILON or 0) or delta < -(Verdict.WEIGHT_EPSILON or 0)`),
-- so there were two copies of the rule and a future change to one would leave
-- the other answering by the old floor. Two verdicts of the same item would
-- then disagree about a crumb smaller than the floor.
--
-- This spec proves the rule is single-sourced, and proves it BEHAVIOURALLY:
-- replacing `Verdict.ranksAsDifferent` must change what `tiebreakTotal` and
-- `orderVerdict` decide. A copy of the comparison in either path cannot be
-- steered that way, so it fails.
--
-- RED on e9aaeb1d: `Verdict.ranksAsDifferent` does not exist (the function is a
-- local inside the comparator), so the sharing checks fail while the boundary
-- checks below already pass. GREEN after the vendored patch
-- (tools/touchstone-patches/ChestAdvisor__Verdict.lua.patch).
--
-- Run from the repo root:  lua5.1 tests/touchstone_tiebreak_single_rule_spec.lua

local here = (arg and arg[0] or "tests/touchstone_tiebreak_single_rule_spec.lua")
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

local f = io.open(TOUCH .. "ChestAdvisor/Verdict.lua", "r")
if not f then
  io.stderr:write("FAIL: the vendored Touchstone is absent — nothing to check\n")
  os.exit(1)
end
f:close()

local V = assert(loadfile(TOUCH .. "ChestAdvisor/Verdict.lua"))()
check(type(V) == "table", "Verdict.lua loads and returns the module")
local eps = V.WEIGHT_EPSILON
check(type(eps) == "number" and eps > 0, "WEIGHT_EPSILON is still a named constant")

-- A profile with a ranked tiebreak list: shipped profiles carry none, so the
-- fixture names the same two survivability stats the Ret tier list ranks.
local TB_PROFILE = { name = "TiebreakFixture", tiebreak = { "Armor", "Stamina" } }
local RET_SPEC = {
  class = "PALADIN", role = "melee", clientRole = "DAMAGER",
  order = V.classRoleOrder("PALADIN", "melee"), level = 20,
}

local inside = eps * 0.5   -- a crumb inside the floor
local outside = eps * 2    -- a real difference outside it

-- ── The boundary itself (passes before and after; documents the values) ───
local tbIn = V.tiebreakTotal({ Armor = 100 + inside, Stamina = 10 },
  { Armor = 100, Stamina = 10 }, TB_PROFILE)
check(tbIn == nil,
  "a tiebreak delta inside WEIGHT_EPSILON is not a decision (got " .. tostring(tbIn) .. ")")
local tbOut = V.tiebreakTotal({ Armor = 100 + outside, Stamina = 10 },
  { Armor = 100, Stamina = 10 }, TB_PROFILE)
check(type(tbOut) == "table" and tbOut.stat == "Armor" and tbOut.dir == 1,
  "a tiebreak delta outside WEIGHT_EPSILON decides (got " .. tostring(tbOut and tbOut.stat) .. ")")
-- ...and the same pair at the same boundary through the ranked comparator.
local vIn = V.orderVerdict({ Strength = 5 + inside, Stamina = 2, Armor = 100 },
  { Strength = 5, Stamina = 2, Armor = 100 }, RET_SPEC)
check(vIn == "NOT_UPGRADE",
  "a ranked delta inside WEIGHT_EPSILON is no change (got " .. tostring(vIn) .. ")")

-- ── One rule, consulted by both paths ─────────────────────────────────────
check(type(V.ranksAsDifferent) == "function",
  "the epsilon rule is one named function, Verdict.ranksAsDifferent")

if type(V.ranksAsDifferent) ~= "function" then
  -- The rest of the spec cannot mean anything without the shared hook, and the
  -- RED reason above is already recorded.
  print("touchstone_tiebreak_single_rule_spec: " .. tostring(failed) .. " failure(s)")
  os.exit(1)
end

check(V.ranksAsDifferent(outside) == true, "the shared rule calls a real delta different")
check(V.ranksAsDifferent(inside) == false, "the shared rule calls a crumb the same")
check(V.ranksAsDifferent(-outside) == true, "the shared rule is two-sided")

-- A permissive rule must make tiebreakTotal decide the crumb pair: it can only
-- do that by asking the shared function. Only non-zero crumbs are promoted, so
-- zero deltas stay equal and the first ranked stat is not read as a change.
local real = V.ranksAsDifferent
V.ranksAsDifferent = function(d)
  return real(d) or (d ~= 0 and math.abs(d) < eps)
end
local tbForced = V.tiebreakTotal({ Armor = 100 + inside, Stamina = 10 },
  { Armor = 100, Stamina = 10 }, TB_PROFILE)
check(type(tbForced) == "table" and tbForced.stat == "Armor",
  "tiebreakTotal consults the shared rule (got " .. tostring(tbForced and tbForced.stat) .. ")")
local vForced, rForced = V.orderVerdict({ Strength = 5 + inside, Stamina = 2, Armor = 100 },
  { Strength = 5, Stamina = 2, Armor = 100 }, RET_SPEC)
check(vForced == "UPGRADE",
  "the ranked comparator consults the same shared rule (got " .. tostring(vForced) ..
  " " .. tostring(rForced) .. ")")

-- ...and a strict rule must make tiebreakTotal ignore a real difference. If
-- tiebreakTotal kept its own copy of the comparison this would still decide.
V.ranksAsDifferent = function() return false end
local tbMuted = V.tiebreakTotal({ Armor = 100 + outside, Stamina = 10 },
  { Armor = 100, Stamina = 10 }, TB_PROFILE)
check(tbMuted == nil,
  "tiebreakTotal has no second copy of the comparison (got " .. tostring(tbMuted) .. ")")
V.ranksAsDifferent = real

-- Restoring the shared rule restores both answers: the override above changed a
-- function, not a captured constant.
check(V.tiebreakTotal({ Armor = 100 + outside, Stamina = 10 },
    { Armor = 100, Stamina = 10 }, TB_PROFILE) ~= nil,
  "the shared rule is restored and the real delta decides again")
check(V.tiebreakTotal({ Armor = 100 + inside, Stamina = 10 },
    { Armor = 100, Stamina = 10 }, TB_PROFILE) == nil,
  "the shared rule is restored and the crumb is still no decision")

if failed == 0 then
  print("touchstone_tiebreak_single_rule_spec: ok")
else
  print(("touchstone_tiebreak_single_rule_spec: %d failure(s)"):format(failed))
  os.exit(1)
end
