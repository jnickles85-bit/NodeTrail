-- Host opt-out: a host that vendors these files sets TouchstoneSkip = true before
-- loading them, and every shipped file returns at this line. Unset -- the normal
-- case -- nothing changes. See README.md, "Embedding Touchstone in a host addon".
if TouchstoneSkip then return end
--- Step 3 C5 — the arbitration layer's PURE half: a healer throughput model and nothing else.
---
--- WHAT THIS IS. One function, `Arbitration.judge(candStats, eqStats, spec, totals)`, that
--- answers the question the ordinal comparator cannot: when a pair trades Intellect for
--- +Healing, is the trade actually worth it *for this character, in this situation*? It
--- returns `nil` (no opinion, and today's bytes are untouched) or a verdict table
--- `{ state, reason, driving, margin, band, context, confidence, ... }`.
---
--- WHAT THIS IS NOT, and the absences are load-bearing:
---   * It is WIRED TO NOTHING. There is no call site in this file's diff, and
---     `Arbitration.ENABLED` is false. C6 generates the band envelope and gates the
---     verdict; C7 cuts the seam at Verdict.lua's ordinal trade-off arm. Until then the
---     changed-verdict sweep MUST move zero rows, and the battery asserts the shipped
---     comparator's bytes for the same pairs.
---   * It calls NO client API, reads no global, writes no SavedVariable. Every number it
---     uses arrives in `totals`, which the impure edge reads and caches (doc §2.1, §3).
---     That is what lets the fengari suite drive it with a plain table.
---   * It never arbitrates the ARMOUR-MATERIAL trade-off (doc §1.3). `Verdict.lua` has two
---     TRADE_OFF producers; this layer is for the ordinal one (`dominance` = "trade-off")
---     only. The material-softened pairs keep today's bytes verbatim, by documented
---     exception — the model has no armour-material term and inventing one here would
---     smuggle a second policy change inside this one.
---
--- THE MODEL, exactly as the scoping doc §4.2 states it (nothing here is my invention
--- except the two constants explicitly marked POLICY):
---
---   per-cast heal     H = Heal_base + coef x BonusHealing
---   crit multiplier   m = 1 + crit% x (CritMult - 1)
---   cast time         t = castTimeMs / 1000 / (1 + haste%/100)
---   casts the clock allows   C_time = fightLength / t
---   mana budget              B_mana = pool + regen_casting x fightLength  (+ drink windows)
---   casts the mana allows    C_mana = B_mana / cost
---   output                   M = H x m x min(C_time, C_mana)
---   margin                   = (M(T') - M(T)) / M(T)      <- a FINITE DIFFERENCE, never a slope
---
--- Mana-bound vs time-bound EMERGES from `min()` over the character's own numbers. There
--- is no profile table here and there must never be one. The finite difference is what
--- prices a cap crossing correctly: an item that pushes Int past the 20-point break (§5
--- row 5) changes the marginal mana per Int by 15x, and a local slope would misread it
--- (battery case 3 pins exactly that).
---
--- THE BAND (doc §6.1). There is no simulator, so "model error" cannot mean fidelity to
--- the real game. It means PARAMETER UNCERTAINTY: perturb every (c) input across its
--- plausible range, recompute the margin, take the spread.
---
---   for each p in P:  margin_p = (M_p(T') - M_p(T)) / M_p(T)
---   band = max over p of |margin_p - margin_0|
---   DECISIVE iff |margin_0| > band AND |margin_0| > 0.01
---
--- The 1 % floor is the panel's number and is KEPT (§6.1): no decisive verdict renders
--- inside +/-1 % even when the envelope says it could. It is not a new epsilon in the
--- shipped engine — nothing in the shipped engine reads this file — and it is the only
--- tolerance in here.
---
--- P, verbatim from the doc: coefficients +/-20 %, base heal +/-10 %, Spirit slope +/-30 %,
--- crit multiplier 1.5/1.6, regen +/-20 %, fight length +/-25 %, cost +/-5 %, one extra /
--- fewer drink window, level extrapolation +/-50 % on every level-dependent term when the
--- measurement level differs from the character's level.
---
--- TWO POLICY DECISIONS I HAD TO MAKE, both stated rather than buried:
---
---   1. A "drink window" is ONE POOL of mana added to the budget, with NO clock cost. The
---      clock cost would need a drinking duration nobody has measured, and the model's
---      clock already runs as its own term, so a window is treated as a pure BUDGET
---      perturbation and therefore as an UPPER BOUND on what drinking can change. It is
---      applied only where the context's own declaration leaves room for one: the shipped
---      three contexts fix the drink assumption absolutely (Leveling refills between
---      pulls, Dungeon and Raid declare none), so the "+1" leg is live everywhere and the
---      "-1" leg is meaningless in all three. A context that declares a FINITE window
---      count (a future "one window per two pulls") gets both legs for free — battery
---      case 10 drives that path directly so it cannot rot.
---
---   2. Level extrapolation is not a perturbation of a number, it is a perturbation of
---      EVERY level-dependent term at once: when the record's level differs from the
---      character's level, coefficient AND base heal move +/-50 % together. That is the
---      doc's rule, and it is why Raid-context verdicts are expected to sit inside the
---      band until a level-60 measurement exists (§6.1 measurement-level rule).
---
--- THE MEASURED CONSTANTS come from §5a (level-34 paladin, 2026-11-16, owner-run). They are
--- LEVEL-TAGGED and RANK-TAGGED: one record per { level, spellID, rank, baseMin, baseMax,
--- coef, coefBounds }. A record is only used at its own level; at another level its
--- uncertainty goes into the band. When no record exists the ERA RULE (castTime/3.5,
--- capped at 1.0) is the declared fallback for the coefficient and the spell's own
--- tooltip numbers supply the base heal — and `spell.source` says "era-rule" so the reason
--- data can label it. The era rule is NEVER applied where a measurement exists: 2.5 s
--- gives 0.714 on the era rule and the client measures 0.794, about 11 % higher, so using
--- the rule would under-price every +Healing item by a tenth, invisibly, in the same
--- direction. (§5a.)
---
--- WHY `Arbitration` IS A GLOBAL. The same reason `Calibration` is one: the fengari suite
--- and, later, Verdict.lua have to reach it. It publishes no other name, reads no other
--- global, and touches no SavedVariables.
---
--- Loaded AFTER Verdict.lua and BEFORE ChestAdvisor/ChestAdvisor.lua in Touchstone.toc
--- (the card's order), so the module exists before anything could ever ask it a question.

Arbitration = Arbitration or {}
local A = Arbitration

--- THE FLAG. TRUE since card t_ce1c4a4f — the wire's deliberate act. The model
--- is now reachable from the shipped judgement path, and this boolean is the
--- rollback: set it to false and `Verdict.evaluate` behaves as it did before the
--- seam existed, without reverting a single line of model code. `Verdict.lua`
--- is the ONE shipped reader (a test pins that count, so no second reader can
--- appear unnoticed).
A.ENABLED = true

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 1. THE CONSTANTS — every one carries its class and its source, per the ledger (§5)
-- ═══════════════════════════════════════════════════════════════════════════════════════

--- THE MEASURED CONSTANTS, level 34, 2026-11-16 (§5a). `level` is part of the record, not
--- a comment: the account has no level-60 character, the constants are re-measured as the
--- owner levels, and a measurement used away from its own level carries the
--- level-extrapolation perturbation and a lower confidence word.
---
---   manaPerInt           15.0      (b)/(a): 1 Int delta, 101 -> 100, mana 2060 -> 2045
---   intBreak             20        the client mirror's break (`PaperDollFrameConstants.lua`)
---   critPerInt           0.0288 %  linear, 100 vs 101 Int, API agrees to 4 dp
---   spiritToRegenCasting 0.0375    mana/s per Spirit while casting (0.625 base x 30 %)
---   regenCastingRatio    0.30      casting regen is exactly 30 % of base at both points
---   hpPerStamina         10        UnitHPPerStamina
A.MEASURED = {
	level = 34,
	manaPerInt = 15.0,
	intBreak = 20,
	critPerInt = 0.0288,
	spiritToRegenCasting = 0.0375,
	regenCastingRatio = 0.30,
	hpPerStamina = 10,
	name = "level-34 paladin, two-hover + three swap probes, 2026-11-16 (§5a)",
}

--- THE SPELL RECORDS — one record per { level, spellID, rank }. A record is only exact at
--- its own level. `coefBounds` is the integer-rounding bound on the coefficient, carried
--- so the band can be read against it and so nothing here implies more precision than the
--- two hovers gave.
---
--- Holy Light rank 5, level 34: +36 Healing -> 518-580, +70 Healing -> 545-607, both ends
--- move +27 for +34 Healing => coef 27/34 = 0.794294..., bounded by the +-1 rounding on
--- each end (0.765-0.824). Base heal solves from both hovers: 518 - 0.794x36 = 489.4 and
--- 580 - 0.794x36 = 551.4; the +70 hovers give the same pair.
A.SPELL_RECORDS = {
	{
		spellID = 19939, name = "Holy Light", rank = 5, level = 34,
		baseMin = 489, baseMax = 551,
		coef = 27 / 34, coefBounds = { 0.765, 0.824 },
		source = "two-hover protocol, level-34 paladin, 2026-11-16 (§5a)",
	},
}

--- POLICY (§4.3): fight length and the drink assumption are declared, not measured — which
--- is exactly why they belong in the band's perturbation set. `window` is the number of
--- seconds of casting regen the budget counts; `drink` is the context's declared drink
--- regime: "none" (no window inside the fight), "refill" (the pool is full at the start of
--- every pull), or a positive NUMBER of declared windows (a future partial regime — the
--- only shape for which the "+/- one window" perturbation has two live legs).
---
--- `targets` is carried as DATA and read by nothing in the model: heals do not miss in this
--- era (§4.2, "for healers there are none"), so the target assumption is a naming fact for
--- the reason line, not a term. It is stored so the context the verdict assumes can be
--- named honestly rather than inferred from the fight length.
A.CONTEXTS = {
	leveling = {
		key = "leveling", label = "Leveling",
		fightLength = 12, window = 0, drink = "refill",
		targets = "equal level",
		note = "pool refilled between pulls; mana unbound, floor check inside the pull",
	},
	dungeon = {
		key = "dungeon", label = "Dungeon",
		fightLength = 30, window = 30, drink = "none",
		targets = "+1 to +2",
		note = "pool + 30 s regen; no drinking mid-fight; floor check",
	},
	raid = {
		key = "raid", label = "Raid",
		fightLength = 300, window = 300, drink = "none",
		targets = "boss (+3)",
		note = "pool + 300 s regen; no drink window",
	},
}
A.CONTEXT_ORDER = { "leveling", "dungeon", "raid" }

--- The panel's floor (§6.1), THE OWNER'S PANEL INPUT and the ONE hard-coded tolerance in
--- this module's gate: no decisive verdict renders inside +/-1 %, even when the envelope says
--- it could. Nothing else in the gate is hard-coded — the margin is the measured finite
--- difference and the band is the measured perturbation spread, regenerated by
--- ChestAdvisor/tests/t_step3_band.js into docs/t_step3-band-envelope.txt and held to those
--- bytes by the digest check (card t_ec2e25ab). NOT a new engine epsilon — C5 kept it out of
--- the shipped engine and nothing there reads it.
A.FLOOR = 0.01

--- The perturbation set P (§6.1), as numbers, once.
A.PERTURB = {
	coef = 0.20, base = 0.10, spirit = 0.30, regen = 0.20,
	fight = 0.25, cost = 0.05, level = 0.50,
	critMultOther = 1.6,
}

--- The stat words this model PRICES and the ones it deliberately IGNORES.
---
--- PRICED: Intellect (mana pool through the break, and crit through the slope), Spirit
--- (regen), Healing (the heal term), MP5 (regen — a pure unit conversion, 5 s per point, so
--- it needs no measurement).
---
--- IGNORED, and reported as DATA on the survival axis (§4.4): Stamina (HP), Armor
--- (mitigation). They never enter M. A pair that moves a word THIS LIST DOES NOT NAME is
--- refused, not silently dropped — that is the same "never a fabricated zero" doctrine the
--- comparator applies to an unclassified client key.
A.PRICED_WORDS = { "Intellect", "Spirit", "Healing", "MP5" }
A.SURVIVAL_WORDS = { "Stamina", "Armor" }

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 2. SMALL, TOTAL HELPERS — every one answers for junk input, none raises
-- ═══════════════════════════════════════════════════════════════════════════════════════

local PRICED, SURVIVAL = {}, {}
for _, w in ipairs(A.PRICED_WORDS) do PRICED[w] = true end
for _, w in ipairs(A.SURVIVAL_WORDS) do SURVIVAL[w] = true end

local function num(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function tableOf(v)
	return type(v) == "table" and v or nil
end

--- The client's own Int -> mana mirror (§5, row 5): 1 point of mana per point of Int up to
--- the 20-point break, 15 per point above it. 15x marginal change AT the break — which is
--- why the verdict is a finite difference and not a slope. Measured above the break (1 Int
--- delta, 101 -> 100, 15 mana); the break value itself is the client mirror, and its
--- position is still an unmeasured GAP (§5a, still-unmeasured list).
local function manaFromInt(int)
	local breakAt = A.MEASURED.intBreak
	if int <= breakAt then return int end
	return breakAt + A.MEASURED.manaPerInt * (int - breakAt)
end

--- The era rule, for a spell NOBODY HAS HOVERED, and only then: castTime/3.5, capped at 1.
local function eraCoef(castSeconds)
	local c = castSeconds / 3.5
	if c > 1 then c = 1 end
	return c
end

--- The Spirit -> casting-regen slope, in one place only. Forward-declared here because the
--- refusal ladder below reads it and the assignment lives beside the model it feeds — one
--- definition, two readers, no second copy to drift.
local spiritSlope

--- Resolve one representative spell to its numbers.
---   returns the resolved spell table, or nil + why.
--- Precedence is the discipline: a MEASUREMENT wins at its own level; a measurement from
--- ANOTHER level is used but flagged (its uncertainty goes into the band); only with no
--- record at all does the era rule speak, and then `source` says so.
local function resolveSpell(totals)
	local s = tableOf(totals.spell)
	if s == nil then return nil, "the representative spell cannot be resolved" end
	if not num(s.cost) or s.cost <= 0 then
		return nil, "the representative spell cannot be resolved (no cost)"
	end
	if not num(s.castTimeMs) or s.castTimeMs <= 0 then
		return nil, "the representative spell cannot be resolved (no cast time)"
	end
	local level = totals.level
	local rec = nil
	for _, r in ipairs(A.SPELL_RECORDS) do
		local idMatch = (s.id ~= nil and r.spellID == s.id)
		local nameMatch = (type(s.name) == "string" and r.name == s.name
			and (s.rank == nil or r.rank == s.rank))
		if idMatch or nameMatch then
			-- A record for a DIFFERENT rank is not this spell's measurement: the two-hover
			-- protocol is run per rank, and extrapolating a rank-5 coefficient across a
			-- rank boundary as if it were exact is the thing §5a forbids.
			if s.rank == nil or r.rank == s.rank then rec = r end
		end
	end
	if rec ~= nil then
		local baseMin = num(s.baseMin) and s.baseMin or rec.baseMin
		local baseMax = num(s.baseMax) and s.baseMax or rec.baseMax
		return {
			base = (baseMin + baseMax) / 2,
			coef = rec.coef,
			coefBounds = rec.coefBounds,
			castSeconds = s.castTimeMs / 1000,
			cost = s.cost,
			name = rec.name, rank = rec.rank, spellID = rec.spellID,
			source = "measured",
			measuredLevel = rec.level,
			levelExact = (num(level) and rec.level == level),
			recordSource = rec.source,
		}
	end
	-- No record. The era rule may only speak where there is no measurement — and it needs
	-- the spell's own tooltip numbers to say anything at all about H.
	if not num(s.baseMin) or not num(s.baseMax) then
		return nil, "the representative spell's healing numbers cannot be resolved"
			.. " (no measurement for this level and rank, and no tooltip numbers)"
	end
	local castSeconds = s.castTimeMs / 1000
	return {
		base = (s.baseMin + s.baseMax) / 2,
		coef = eraCoef(castSeconds),
		coefBounds = nil,
		castSeconds = castSeconds,
		cost = s.cost,
		name = (type(s.name) == "string" and s.name or "the representative spell"),
		rank = s.rank, spellID = s.id,
		source = "era-rule",
		measuredLevel = nil,
		levelExact = false,
		recordSource = nil,
	}
end

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 3. REFUSALS — the union of shipped doctrine and the panel (§8). One named line each.
-- ═══════════════════════════════════════════════════════════════════════════════════════

--- The whole refusal ladder, in priority order, as a function that returns the FIRST
--- reason we cannot speak — or nil when we can.
---
--- `judge` and `Arbitration.why` both call this, so a refusal can never drift from its
--- explanation: the battery asserts the named reason, not just the nil.
local function refusal(candStats, eqStats, spec, totals)
	-- §8.9 — totals unavailable or secret, and never "compute on partially-secret totals".
	if type(totals) ~= "table" then return "no totals: the model needs the character's own numbers" end
	if totals.secret == true then return "totals are secret: the client would not hand them over" end
	local stats = tableOf(totals.stats)
	if stats == nil then return "totals are incomplete: no stat block" end
	local required = { "pool", "regenCasting", "crit", "bonusHealing", "level" }
	for _, k in ipairs(required) do
		if not num(totals[k]) then return "totals are incomplete: " .. k .. " is not a number" end
	end
	if totals.spell == nil then return "the representative spell cannot be resolved" end
	if totals.haste ~= nil and not num(totals.haste) then
		return "totals are incomplete: haste is not a number"
	end
	if totals.critMult ~= nil and not num(totals.critMult) then
		return "totals are incomplete: critMult is not a number"
	end
	if not num(stats.Intellect) then return "totals are incomplete: Intellect is not a number" end
	if totals.pool <= 0 then return "the mana pool is not a positive number" end

	-- §8.6 — no role picked. `spec.role` is the ONE role resolution point (ChestAdvisor's
	-- buildSpec); a spec without it is a hybrid the player has not chosen for, and the
	-- arbitration has no idea which model to apply.
	if type(spec) ~= "table" then return "the spec has no role" end
	if type(spec.role) ~= "string" or spec.role:match("%S") == nil then
		return "the spec has no role"
	end

	local spell, spellWhy = resolveSpell(totals)
	if spell == nil then return spellWhy end
	if spell.cost <= 0 then return "the representative spell's cost is not a positive number" end
	if spell.castSeconds <= 0 then return "the representative spell's cast time is not a positive number" end
	if not num(spell.base) or spell.base <= 0 then
		return "the representative spell's base heal is not a positive number"
	end
	-- Level extrapolation is allowed, but it needs a level to extrapolate FROM.
	if spell.source == "measured" and not num(totals.level) then
		return "totals are incomplete: level is not a number"
	end

	-- The pair itself: does it move anything this model can price?
	local cand = tableOf(candStats) or {}
	local eq = tableOf(eqStats) or {}
	local moved, pricedMove, unpriced = false, false, nil
	local seen = {}
	for _, side in ipairs({ cand, eq }) do
		for word in pairs(side) do
			if type(word) == "string" and not seen[word] then
				seen[word] = true
				local c, e = cand[word], eq[word]
				local cv = num(c) and c or 0
				local ev = num(e) and e or 0
				if cv ~= ev then
					moved = true
					if PRICED[word] then
						pricedMove = true
					elseif not SURVIVAL[word] then
						unpriced = unpriced or word
					end
				end
			end
		end
	end
	if not moved then return "the pair moves nothing: there is no trade to arbitrate" end
	if unpriced ~= nil then
		return "the pair moves " .. unpriced .. ", which the healer model does not price"
	end
	if not pricedMove then return "the pair is not a healer-total pair" end

	-- §8.8 — Spirit-dominant with the regen slope unmeasured. Spirit enters M ONLY through
	-- regen; with no measured slope the model would have to guess one, so it refuses
	-- instead of guessing. (Fail-closed, and it degrades to today's words exactly.)
	local dSpirit = (num(cand.Spirit) and cand.Spirit or 0) - (num(eq.Spirit) and eq.Spirit or 0)
	if dSpirit ~= 0 and spiritSlope(totals) == nil then
		return "Spirit moves and the regen slope is unmeasured"
	end

	return nil
end

--- The Spirit -> casting-regen slope, as a number, or nil when it is unmeasured.
--- `totals.spiritSlopeCasting` is the measured value the impure edge carries (C3's
--- `/ts3cal`); the level-tagged record is the declared fallback AT ITS OWN LEVEL ONLY —
--- away from that level the slope is an extrapolation, not a measurement, so it is not
--- used and the refusal stands.
spiritSlope = function(totals)
	if num(totals.spiritSlopeCasting) then return totals.spiritSlopeCasting end
	if totals.regenMeasured == false then return nil end
	local m = A.MEASURED
	if num(totals.level) and totals.level == m.level and totals.regenMeasured == true then
		return m.spiritToRegenCasting
	end
	return nil
end

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 4. THE MODEL — one side of the pair, one context, one perturbation
-- ═══════════════════════════════════════════════════════════════════════════════════════

--- `side` is the pair's MOVEMENT in the words the model prices:
---   { dInt, dSpirit, dHeal, dMP5 }  — all numbers, all defaults 0.
--- `p` is a perturbation (see `perturbations`); nil means "no perturbation".
---
--- Returns: output M, and the parts that made it (for the reason line and for testing),
--- or nil + why when an input cannot produce a positive, finite output.
local function output(totals, ctx, spell, side, p)
	p = p or {}
	local baseInt = totals.stats.Intellect
	local int = baseInt + (side.dInt or 0)
	local pool = totals.pool - manaFromInt(baseInt) + manaFromInt(int)
	if pool <= 0 then return nil, "the mana pool goes to or below zero" end

	local slope = spiritSlope(totals) or 0
	if p.spiritScale ~= nil then slope = slope * p.spiritScale end
	local regen = totals.regenCasting + slope * (side.dSpirit or 0) + (side.dMP5 or 0) / 5
	if p.regenScale ~= nil then regen = regen * p.regenScale end
	if regen < 0 then regen = 0 end

	local fightScale = p.fightScale or 1
	local fightLength = ctx.fightLength * fightScale
	local window = ctx.window * fightScale

	local budget = pool + regen * window
	-- POLICY 1 (header): a drink window is one pool of mana, no clock cost.
	local drinkDelta = p.drinkDelta or 0
	if drinkDelta ~= 0 then
		local live = false
		if ctx.drink == "refill" then
			live = false -- every pull starts full; a window more or fewer changes nothing
		elseif type(ctx.drink) == "number" then
			live = (ctx.drink + drinkDelta) >= 0
		elseif ctx.drink == "none" then
			live = drinkDelta > 0 -- you cannot buy fewer than no windows
		end
		if live then budget = budget + drinkDelta * pool end
	end
	if budget <= 0 then return nil, "the mana budget goes to or below zero" end

	local crit = totals.crit + (side.dCrit or 0)
	local critMult = p.critMult or totals.critMult or 1.5

	local coefScale = (p.coefScale or 1) * (p.levelScale or 1)
	local baseScale = (p.baseScale or 1) * (p.levelScale or 1)
	local healBase = spell.base * baseScale
	local coef = spell.coef * coefScale
	local bonusHeal = totals.bonusHealing + (side.dHeal or 0)
	local H = healBase + coef * bonusHeal
	if not num(H) or H <= 0 then return nil, "the per-cast heal is not a positive number" end

	local m = 1 + (crit / 100) * (critMult - 1)
	if not num(m) or m <= 0 then return nil, "the crit multiplier is not a positive number" end

	local haste = totals.haste or 0
	local t = spell.castSeconds / (1 + haste / 100)
	if not num(t) or t <= 0 then return nil, "the cast time is not a positive number" end
	local cTime = fightLength / t
	local cMana = budget / (spell.cost * (p.costScale or 1))
	if not num(cTime) or not num(cMana) then return nil, "a cast count is not a number" end

	local casts = cTime
	local binding = "time"
	if cMana < cTime then casts, binding = cMana, "mana" end
	local M = H * m * casts
	if not num(M) or M <= 0 then return nil, "the model's output is not a positive number" end
	return M, {
		H = H, m = m, casts = casts, cTime = cTime, cMana = cMana,
		pool = pool, budget = budget, regen = regen, binding = binding,
	}
end

--- The perturbation set P (§6.1). Deterministic order, so the band is reproducible and the
--- battery can pin it. Each entry is { name, p }.
local function perturbations(totals, spell, side)
	local P = A.PERTURB
	local out = {}
	local function add(name, p) out[#out + 1] = { name = name, p = p } end

	-- Each axis is perturbed ALONE: the band is the max over p (§6.1), so combining axes
	-- would report a worst case the doc never asked for and inflate the band past its own
	-- definition.
	add("coefficient +20%", { coefScale = 1 + P.coef })
	add("coefficient -20%", { coefScale = 1 - P.coef })
	add("base heal +10%", { baseScale = 1 + P.base })
	add("base heal -10%", { baseScale = 1 - P.base })

	local critMult = totals.critMult or 1.5
	if critMult ~= P.critMultOther then
		add("crit multiplier " .. tostring(P.critMultOther), { critMult = P.critMultOther })
	elseif critMult ~= 1.5 then
		add("crit multiplier 1.5", { critMult = 1.5 })
	end

	add("regen +20%", { regenScale = 1 + P.regen })
	add("regen -20%", { regenScale = 1 - P.regen })

	add("fight length +25%", { fightScale = 1 + P.fight })
	add("fight length -25%", { fightScale = 1 - P.fight })

	add("cost +5%", { costScale = 1 + P.cost })
	add("cost -5%", { costScale = 1 - P.cost })

	add("one extra drink window", { drinkDelta = 1 })
	add("one fewer drink window", { drinkDelta = -1 })

	-- Level extrapolation, on the level-dependent terms ONLY (coefficient and base heal),
	-- and only when the record was taken at another level (§6.1 measurement-level rule).
	if spell.source == "measured" and spell.levelExact == false then
		add("level extrapolation +50%", { levelScale = 1 + P.level })
		add("level extrapolation -50%", { levelScale = 1 - P.level })
	end

	if (side.dSpirit or 0) ~= 0 then
		add("Spirit slope +30%", { spiritScale = 1 + P.spirit })
		add("Spirit slope -30%", { spiritScale = 1 - P.spirit })
	end
	return out
end

--- One context's whole answer for the pair: the margin, the band, and BOTH sides' parts
--- (the candidate's and the equipped side's), because the driving term is the ratio of the
--- two, factor by factor.
local function evaluateContext(candSide, eqSide, totals, ctx, spell)
	local c0, cp = output(totals, ctx, spell, candSide, nil)
	if c0 == nil then return nil, cp end
	local e0, ep = output(totals, ctx, spell, eqSide, nil)
	if e0 == nil then return nil, ep end
	local margin = (c0 - e0) / e0
	if not num(margin) then return nil, "the margin is not a number" end

	local band, worst = 0, nil
	for _, item in ipairs(perturbations(totals, spell, candSide)) do
		local p = item.p
		local c = output(totals, ctx, spell, candSide, p)
		local e = output(totals, ctx, spell, eqSide, p)
		if c ~= nil and e ~= nil then
			local d = math.abs((c - e) / e - margin)
			if d > band then band, worst = d, item.name end
		end
	end

	local decisive = math.abs(margin) > band and math.abs(margin) > A.FLOOR
	local state = "SIDEGRADE"
	if decisive then
		state = margin > 0 and "UPGRADE" or "NOT_UPGRADE"
	end
	return {
		context = ctx.key, margin = margin, band = band, bandSource = worst,
		state = state, decisive = decisive,
		binding = cp.binding, casts = cp.casts, cTime = cp.cTime, cMana = cp.cMana,
		pool = cp.pool, budget = cp.budget, H = cp.H, m = cp.m,
		H_eq = ep.H, m_eq = ep.m, casts_eq = ep.casts,
	}
end

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 5. SURVIVAL — a separate axis, computed as data, never deciding (§4.4)
-- ═══════════════════════════════════════════════════════════════════════════════════════

local function survivalOf(cand, eq, totals)
	local dSta = (num(cand.Stamina) and cand.Stamina or 0) - (num(eq.Stamina) and eq.Stamina or 0)
	local dArmor = (num(cand.Armor) and cand.Armor or 0) - (num(eq.Armor) and eq.Armor or 0)
	local dHP = nil
	local hpPerSta = totals.hpPerStamina
	if not num(hpPerSta) and totals.level == A.MEASURED.level then hpPerSta = A.MEASURED.hpPerStamina end
	if num(hpPerSta) then dHP = dSta * hpPerSta end
	local dMit = nil
	local mit = totals.mitigation
	local armorTotal = totals.stats and totals.stats.Armor
	if type(mit) == "function" and num(armorTotal) then
		local okA, a = pcall(mit, armorTotal + dArmor)
		local okB, b = pcall(mit, armorTotal)
		if okA and okB and num(a) and num(b) then dMit = a - b end
	end
	if dHP == nil and dMit == nil then return nil end
	-- C5: DATA ONLY. The survival line may decide ONLY when M lands inside the band (§4.4),
	-- and that gate belongs to C6/C7. Stated here so no reader can mistake the field for a
	-- deciding one.
	return { dHP = dHP, dMitigation = dMit, decides = false }
end

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 6. THE ENTRY POINT
-- ═══════════════════════════════════════════════════════════════════════════════════════

local function delta(cand, eq, word)
	return (num(cand[word]) and cand[word] or 0) - (num(eq[word]) and eq[word] or 0)
end

--- The refusal reason, or nil. Diagnostics and tests; C7 may print it.
function A.why(candStats, eqStats, spec, totals)
	return refusal(candStats, eqStats, spec, totals)
end

local function reasonLine(verdict, ctx, extras)
	local label = ctx.label .. " healing"
	local conf = ""
	if extras.confidence == "low" then
		conf = " (confidence low: " .. table.concat(extras.lowWhy, "; ") .. ")"
	end
	local castsN = math.floor(verdict.casts + 0.5)
	if verdict.state == "SIDEGRADE" then
		local flip = ""
		if extras.flip ~= nil then
			flip = " It reads " .. extras.flip.state:lower() .. " for "
				.. A.CONTEXTS[extras.flip.context].label:lower() .. " healing."
		end
		return label .. ": under the band either way — pick the one you like." .. flip .. conf
	end
	if verdict.binding == "mana" then
		if verdict.state == "UPGRADE" then
			return label .. ": an upgrade — the extra healing per cast outruns the smaller pool,"
				.. " and you would run dry after about " .. castsN .. " casts either way." .. conf
		end
		return label .. ": not an upgrade — the mana it costs buys fewer casts than the healing"
			.. " it adds, and you would run dry after about " .. castsN .. " casts." .. conf
	end
	if verdict.state == "UPGRADE" then
		return label .. ": an upgrade — more healing per cast, and the fight ends before your"
			.. " mana does." .. conf
	end
	return label .. ": not an upgrade — less healing per cast, and the clock is what limits"
		.. " the fight." .. conf
end

--- judge(candStats, eqStats, spec, totals) -> nil | verdict table
---
---   candStats, eqStats — the comparator's own parsed stat tables (word -> points). The
---                        SAME two tables Verdict.evaluate hands its own layers, so this
---                        layer needs no second reader and cannot disagree about a line.
---   spec               — the spec buildSpec built: `role` is the ONE role resolution point.
---                        `context` is the situation ("leveling" | "dungeon" | "raid").
---   totals             — the character snapshot the impure edge read (§3). See the shape in
---                        the battery's case file; every field is optional only where the
---                        refusal ladder above says so.
---
--- Returns nil when the model has no opinion, and a table whose REQUIRED fields are the
--- card's seven: state, reason, driving, margin, band, context, confidence. Everything else
--- (byContext, binding, survival, spell, lowWhy, flip) is data for C6/C7 and for the battery.
function A.judge(candStats, eqStats, spec, totals)
	local why = refusal(candStats, eqStats, spec, totals)
	if why ~= nil then return nil end
	local cand, eq = candStats, eqStats
	local spell = resolveSpell(totals)

	-- The context the verdict is FOR. buildSpec always carries one; an absent or unknown
	-- word is read as the default the store itself reads (Leveling), and the result says so
	-- rather than inventing a fourth context.
	local ctxKey = spec.context
	if type(ctxKey) ~= "string" or A.CONTEXTS[ctxKey] == nil then ctxKey = "leveling" end
	local ctx = A.CONTEXTS[ctxKey]

	local candSide = {
		dInt = delta(cand, eq, "Intellect"),
		dSpirit = delta(cand, eq, "Spirit"),
		dHeal = delta(cand, eq, "Healing"),
		dMP5 = delta(cand, eq, "MP5"),
	}
	-- Crit arrives through Intellect and nothing else here: a `Crit` RATING word is refused
	-- by the ladder (its rating -> percent slope is unmeasured), so the only crit movement
	-- this model ever sees is the Intellect slope.
	candSide.dCrit = candSide.dInt * A.MEASURED.critPerInt
	local eqSide = { dInt = 0, dSpirit = 0, dHeal = 0, dMP5 = 0, dCrit = 0 }

	local verdict = evaluateContext(candSide, eqSide, totals, ctx, spell)
	if verdict == nil then return nil end

	-- Every context, because §7 names a flip: the verdict is for the CURRENT context and the
	-- reason may name the context the pair is better for.
	local byContext, flip = {}, nil
	for _, key in ipairs(A.CONTEXT_ORDER) do
		local v = verdict
		if key ~= ctxKey then
			v = evaluateContext(candSide, eqSide, totals, A.CONTEXTS[key], spell)
		end
		if v ~= nil then
			byContext[key] = v
			if flip == nil and v.decisive and verdict.decisive
				and (v.margin > 0) ~= (verdict.margin > 0) then
				flip = { context = key, state = v.state, margin = v.margin }
			end
		end
	end

	-- The driving term (§7: "the single driving term"). The model is a PRODUCT of three
	-- factors, so the log of the candidate's margin ratio decomposes EXACTLY into the three:
	--   log(M'/M) = log(H'/H) + log(m'/m) + log(C'/C)
	-- The largest of the three is the one that carried the pair. It is a measurement of this
	-- pair, not a story about it.
	local driving = "healing"
	do
		local dh = math.abs(math.log(verdict.H / verdict.H_eq))
		local dm = math.abs(math.log(verdict.m / verdict.m_eq))
		local dc = math.abs(math.log(verdict.casts / verdict.casts_eq))
		local best, bestV = "healing", dh
		if dm > bestV then best, bestV = "crit", dm end
		if dc > bestV then best, bestV = "casts", dc end
		if best == "casts" then
			driving = (verdict.binding == "mana") and "mana" or "clock"
		else
			driving = best
		end
	end

	-- The confidence word (§7): a word, not a percentage. Anything unmeasured and load-
	-- bearing makes it "low"; only a fully measured set earns "measured".
	--
	-- TODAY EVERY CALL IS "low", and that is the truthful state: the crit multiplier still
	-- needs one logged crit heal (§5a, still unmeasured), so the `m` term every healer
	-- verdict divides by is a declared default. The word says so instead of pretending.
	local lowWhy = {}
	if spell.source ~= "measured" then
		lowWhy[#lowWhy + 1] = "spell coefficient and base heal from the era rule, not a hover"
	elseif spell.levelExact ~= true then
		lowWhy[#lowWhy + 1] = "measured at level " .. tostring(spell.measuredLevel)
			.. ", used at level " .. tostring(totals.level)
	end
	if not num(totals.critMult) then lowWhy[#lowWhy + 1] = "crit multiplier unmeasured" end
	if (candSide.dSpirit or 0) ~= 0 and not num(totals.spiritSlopeCasting) then
		lowWhy[#lowWhy + 1] = "Spirit slope from the level-tagged record"
	end
	local confidence = (#lowWhy == 0) and "measured" or "low"

	local survival = survivalOf(cand, eq, totals)
	local extras = { confidence = confidence, lowWhy = lowWhy, flip = flip }
	local result = {
		state = verdict.state,
		reason = reasonLine(verdict, ctx, extras),
		driving = driving,
		margin = verdict.margin,
		band = verdict.band,
		context = ctx.key,
		confidence = confidence,
		-- data for C6/C7 and for the battery; none of it decides anything in C5
		marginPercent = verdict.margin * 100,
		bandPercent = verdict.band * 100,
		bandSource = verdict.bandSource,
		binding = verdict.binding,
		casts = verdict.casts,
		cTime = verdict.cTime,
		cMana = verdict.cMana,
		byContext = byContext,
		flip = flip,
		survival = survival,
		spell = { name = spell.name, rank = spell.rank, source = spell.source,
			base = spell.base, coef = spell.coef, castTimeMs = spell.castSeconds * 1000,
			cost = spell.cost },
		buffed = totals.buffed == true,
		lowWhy = lowWhy,
	}
	return result
end

--- Publish into the host table when it is there (Constants.lua creates it). Guarded
--- exactly as StatOrders.lua is: this file also loads standalone in the fengari VMs.
local SF = rawget(_G, "StatForge")
if type(SF) == "table" then
	SF.Arbitration = A
end

return A
