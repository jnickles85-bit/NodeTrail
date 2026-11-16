-- touchstone_universal_tiebreak_spec.lua — card t_a4124aed.
--
-- THE DIVERGENCE THIS PINS. Measured on the pack's own vendored bytes by the
-- v0.3.9-beta batch probe (evidence/t_40a96835-batch-measured.txt), and again
-- here:
--
--   two-sided Block tie, +20 Block vs +10 Block, Protection paladin
--     upstream (StatForge 740f7d5)  -> UPGRADE   "upgrade: more Block (20 vs 10)
--                                               on an otherwise equal item"
--     this pack's vendored tree     -> NOT_UPGRADE "no change [Protection (Balanced)]"
--
-- It reproduces identically on the pre-cut tree, so the re-vendor did not
-- introduce it; it is a property of the pack's own layer.
--
-- WHY IT HAPPENS (measured, not inferred). Every shipped profile is order-only
-- (`kind = "order"`, generated from the Wowhead Forever priority pages), and
-- `Verdict.evaluate` asks that layer FIRST — `Verdict.weightedVerdict` returns a
-- definitive answer, so gate 9's ordinal tail never runs. The Protection
-- (Balanced) order names `BlockChance`, a DIFFERENT tooltip word from `Block`:
-- nothing in any shipped order ranks block VALUE at all. So the order walk finds
-- no ranked difference, and the layer answers "no change" for a pair it never
-- looked at. The same mechanism hides Armor on the damage specs (Armor is not in
-- the Retribution or Holy order), where a chestpiece with 20 more Armor and the
-- same ranked stats reads "no change" here and "upgrade: more Armor (120 vs
-- 100) on an otherwise equal item" upstream.
--
-- THE RULE (owner's ruling, 2026-11-15): a tiebreak-only price must not decide a
-- pair, but a two-sided tiebreak decides a tie. Armor and Block are the two
-- words upstream keeps for exactly that second job (RULING (b): they join the
-- relevance set UNCONDITIONALLY, Armor then Block, after the order's own words).
-- +20 Block vs +10 Block is an otherwise-equal item with both sides carrying the
-- word: the tiebreak decides. So upstream is right and the pack was wrong.
--
-- THE FIX. One definition — `Verdict.universalTiebreak` — called by BOTH the
-- ordinal tail (upstream's own loop, extracted) and the order path when no
-- ranked tier decided. Two callers of one rule; the two trees cannot answer a
-- two-sided Armor/Block tie differently.
--
-- WHAT MUST NOT MOVE. The owner's own pair, +1 Hit vs +20 Block on a Protection
-- warrior, is decided by Hit and must stay exactly as he saw it.
--
-- Run from the repo root:  lua5.1 tests/touchstone_universal_tiebreak_spec.lua

local here = (arg and arg[0] or "tests/touchstone_universal_tiebreak_spec.lua")
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

local function judge(cand, worn, spec)
  return V.evaluate({ canUse = true, line = cand }, { line = worn }, spec, nil, nil)
end

-- The specs buildSpec resolves for /up: the class, the role the order came from,
-- and the CLIENT's own role word.
local PROT_SPEC = {
  class = "PALADIN", role = "spell", clientRole = "TANK", level = 60,
  order = V.classRoleOrder("PALADIN", "spell"),
}
local RET_SPEC = {
  class = "PALADIN", role = "melee", clientRole = "DAMAGER", level = 60,
  order = V.classRoleOrder("PALADIN", "melee"),
}
local WAR_TANK_SPEC = {
  class = "WARRIOR", role = "spell", clientRole = "TANK", level = 60,
  order = V.classRoleOrder("WARRIOR", "spell"),
}

-- The pair the two trees disagree about, as the batch probe rendered it.
local CAND_BLOCK = { "Tower Shield", "Off Hand", "+20 Block" }
local WORN_BLOCK = { "Aegis of the Just", "Off Hand", "+10 Block" }

-- ===========================================================================
-- 1. BOTH TREES' ANSWERS, PINNED. Upstream's answer is a literal here — the
--    number recorded from StatForge 740f7d5 — and the pack must produce the
--    SAME VERDICT AND THE SAME SENTENCE. If either tree moves, this fails.
-- ===========================================================================
local UPSTREAM_BLOCK_VERDICT = "UPGRADE"
local UPSTREAM_BLOCK_SENTENCE = "upgrade: more Block (20 vs 10) on an otherwise equal item"

local vBlock, rBlock = judge(CAND_BLOCK, WORN_BLOCK, PROT_SPEC)
print("block pair: " .. tostring(vBlock) .. " | " .. tostring(rBlock))
check(vBlock == UPSTREAM_BLOCK_VERDICT,
  "the +20/+10 Block tie answers what upstream answers (" .. UPSTREAM_BLOCK_VERDICT
    .. "), got " .. tostring(vBlock))
check(rBlock == UPSTREAM_BLOCK_SENTENCE,
  "and in upstream's own words (" .. UPSTREAM_BLOCK_SENTENCE .. "), got " .. tostring(rBlock))

-- The item's own row must still name the word and both numbers, so the player
-- reads WHICH tie broke rather than a bare verdict.
local _, _, dBlock = judge(CAND_BLOCK, WORN_BLOCK, PROT_SPEC)
check(type(dBlock) == "table" and type(dBlock.decidedBy) == "string"
    and dBlock.decidedBy:find("Block", 1, true) and dBlock.decidedBy:find("20", 1, true)
    and dBlock.decidedBy:find("10", 1, true),
  "the row says the tiebreak word and both numbers (got "
    .. tostring(dBlock and dBlock.decidedBy) .. ")")

-- ===========================================================================
-- 2. THE OWNER'S PAIR DOES NOT MOVE. +1 Hit vs +20 Block on a Protection
--    warrior is decided by Hit, exactly as the batch probe recorded it.
-- ===========================================================================
local vHit, rHit = judge({ "A", "+1 Hit" }, { "B", "+20 Block" }, WAR_TANK_SPEC)
print("owner's pair: " .. tostring(vHit) .. " | " .. tostring(rHit))
check(vHit == "UPGRADE", "the owner's +1 Hit vs +20 Block is still an upgrade (got "
  .. tostring(vHit) .. ")")
check(type(rHit) == "string" and rHit:find("Hit", 1, true) ~= nil,
  "and Hit still decides it (got " .. tostring(rHit) .. ")")
check(type(rHit) == "string" and not rHit:find("Armor", 1, true)
    and not rHit:find("more Block", 1, true),
  "the tiebreak did not take the decision away from Hit (got " .. tostring(rHit) .. ")")

-- ===========================================================================
-- 3. ONE RULE, TWO CALLERS. The tiebreak is a named function, and BOTH the
--    order path and the ordinal tail go through it. Replacing it changes what
--    both decide — an inline copy in either place cannot be steered like this.
-- ===========================================================================
check(type(V.universalTiebreak) == "function",
  "the universal tiebreak is one named function, Verdict.universalTiebreak")

if type(V.universalTiebreak) == "function" then
  local real = V.universalTiebreak
  local calls, words = 0, {}
  V.universalTiebreak = function(candStats, eqStats, order)
    calls = calls + 1
    words[#words + 1] = order
    return "UPGRADE", "spy: the named rule answered"
  end

  local sv, sr = judge(CAND_BLOCK, WORN_BLOCK, PROT_SPEC)
  check(calls >= 1 and sv == "UPGRADE" and sr == "spy: the named rule answered",
    "the ORDER path asks the named rule (spy called " .. calls .. "x, answer "
      .. tostring(sv) .. " | " .. tostring(sr) .. ")")

  -- ...and the ordinal tail it was extracted from asks the same one.
  calls = 0
  V.LEGACY_DOMINANCE_DECIDES = true
  local lv, lr = judge(CAND_BLOCK, WORN_BLOCK, PROT_SPEC)
  V.LEGACY_DOMINANCE_DECIDES = false
  check(calls >= 1 and lv == "UPGRADE" and lr == "spy: the named rule answered",
    "the ORDINAL tail asks the same named rule (spy called " .. calls .. "x, answer "
      .. tostring(lv) .. " | " .. tostring(lr) .. ")")

  V.universalTiebreak = real
end

-- ===========================================================================
-- 4. TWO-SIDED ONLY. A word one side carries and the other does not is a known
--    absence, not a win — this is the "a tiebreak-only price must not decide a
--    pair" half of the owner's rule, and it is why this is not a licence to call
--    every armour difference an upgrade.
-- ===========================================================================
local vOneBlock, rOneBlock = judge(
  { "Shield", "Off Hand", "+5 Stamina", "+20 Block" },
  { "Plain Shield", "Off Hand", "+5 Stamina" }, PROT_SPEC)
check(vOneBlock == "NOT_UPGRADE",
  "a one-sided Block is not a decision (got " .. tostring(vOneBlock) .. ")")
check(type(rOneBlock) == "string" and rOneBlock:find("no change", 1, true) ~= nil,
  "a one-sided Block still reads no change (got " .. tostring(rOneBlock) .. ")")

local vOneArmor = judge(
  { "Chest", "Chest", "+10 Strength", "+120 Armor" },
  { "Old Chest", "Chest", "+10 Strength" }, RET_SPEC)
check(vOneArmor == "NOT_UPGRADE",
  "a one-sided Armor is not a decision (got " .. tostring(vOneArmor) .. ")")

-- ===========================================================================
-- 5. THE SAME RULE, THE OTHER TIEBREAK WORD. Armor is unranked on the damage
--    specs, so the same pre-emption hid it there: a chestpiece with more Armor
--    and the same ranked stats reads "no change" today and "more Armor" up
--    stream. Pinned to upstream's sentence, like Block above.
-- ===========================================================================
local UPSTREAM_ARMOR_SENTENCE = "upgrade: more Armor (120 vs 100) on an otherwise equal item"
local vArmor, rArmor = judge(
  { "Chest", "Chest", "+10 Strength", "120 Armor" },
  { "Old Chest", "Chest", "+10 Strength", "100 Armor" }, RET_SPEC)
print("armor pair: " .. tostring(vArmor) .. " | " .. tostring(rArmor))
check(vArmor == "UPGRADE", "the +120/+100 Armor tie on Retribution is an upgrade (got "
  .. tostring(vArmor) .. ")")
check(rArmor == UPSTREAM_ARMOR_SENTENCE,
  "in upstream's own words (" .. UPSTREAM_ARMOR_SENTENCE .. "), got " .. tostring(rArmor))

-- ===========================================================================
-- 6. AND IT NEVER OVER TURNS A TRADE-OFF. The tiebreak decides TIES only: a
--    ranked loss stays a trade-off even when the tiebreak word rises (the
--    "must not decide a pair" half, unchanged by this card).
-- ===========================================================================
-- Strength and Attack Power share one Wowhead tier for Retribution: a gain on
-- one and a loss on the other is an intra-tier conflict, so the pair is a
-- Trade-off and must stay one even though the candidate also carries more Armor.
local vTrade, rTrade = judge(
  { "Chest", "Chest", "+12 Strength", "+8 Attack Power", "120 Armor" },
  { "Old Chest", "Chest", "+11 Strength", "+12 Attack Power", "100 Armor" }, RET_SPEC)
print("trade-off pair: " .. tostring(vTrade) .. " | " .. tostring(rTrade))
check(vTrade == "TRADE_OFF",
  "a ranked loss plus a tiebreak gain is still a trade-off (got "
    .. tostring(vTrade) .. " | " .. tostring(rTrade) .. ")")
check(type(rTrade) == "string" and not rTrade:find("more Armor", 1, true),
  "the tiebreak did not over turn the trade-off (got " .. tostring(rTrade) .. ")")

-- ===========================================================================
if failed > 0 then
  io.stderr:write(("touchstone_universal_tiebreak_spec: %d failure(s)\n"):format(failed))
  os.exit(1)
end
print("touchstone_universal_tiebreak_spec: ok")
