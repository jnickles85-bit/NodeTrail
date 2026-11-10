if MightiePackTouchstoneSkip then return end
-- Verdict.lua — the t_3c1256ec upgrade verdict.
--
-- Two pure pieces of knowledge, with no UI, no client dependency, and no
-- mutable state: `classRoleOrder` (the documented per-class stat priorities)
-- and `evaluate` (the deterministic comparator). Everything a scanner needs
-- to call them flows in as arguments; nothing is read from the environment,
-- so a unit test can drive every branch on a clean VM without fixtures.
--
-- Invariants (from the task body and the director's corrections on
-- t_97a8ea03):
--   * EQUAL is NOT an upgrade. A strict improvement along the role's stat
--     order is required — "not worse" is not "better".
--   * A stat word neither side can classify is UNKNOWN, never a fabricated 0.
--   * Hard eligibility (C_PlayerInfo.CanUseItem) is the caller's
--     responsibility, but here it is a hard gate: canUse == false is never
--     UPGRADE, and canUse == nil is never UPGRADE either.
--   * Hybrid classes (Paladin, Shaman, and — C1b, t_03a1196c — Druid) carry
--     MORE THAN ONE role and return nil unless a role is explicitly passed.
--     There is no silent default. Druid is the odd one: only its `spell` role
--     is documented, so `melee` is a documented role WITH no order (the
--     NO_ORDER sentinel below), not a missing entry.

local Verdict = {}

-- Tank path (card t_89440dfa): the differential switch used by the AC-C/AC-D
-- harness ONLY. `true` restores the pre-card "the order decides" comparator
-- (orderedCompare + the Armor/Block tiebreak), which is exactly HEAD's
-- behaviour; `false` (the default, and the only value any shipped path sees)
-- uses the three-outcome dominance test over the relevance set. It exists so
-- every fixture can be run through BOTH comparators in one VM and the outcomes
-- diffed — the card's AC-C proof — without a second copy of the file.
-- ⚠ Nothing in ChestAdvisor.lua reads this; no UI path can select the legacy
-- behaviour. It is test instrumentation, declared here so both comparators live
-- in the one frozen module.
Verdict.LEGACY_ORDER_DECIDES = false

-- C1b (t_03a1196c), §9: a documented role with NO recorded stat order.
-- Distinct from a missing entry: `nil` at the ORDERS level means "the class
-- is unknown", and a nil *inside* the role table was already ambiguous with
-- "no entry for this role". NO_ORDER says "the role exists, is a valid
-- picker option, and the player may pick it — but the corpus documents no
-- stat order for it, so it resolves to nil and the rows stay UNKNOWN."
local NO_ORDER = {}

-- The documented order, as shipped in the agent primer block
-- (docs/whisperstone/stat-weights-for-upgrade-advice.md §8.1):
--
--   Warlock/Mage/Priest  int>spi>sta
--   Druid  int>agi>sta
--   Rogue  agi>str>sta
--   Hunter agi>sta>int
--   Paladin  str>int>sta
--   Shaman   str>int>sta
--   Warrior  str>sta>agi
--
-- The hybrids carry one order PER role, and there is no default across them.
-- Paladin and Shaman each have a distinct documented order for their two
-- roles; Druid is the exception (C1b, t_03a1196c): its `melee` role has no
-- documented order, so that role resolves to nil rather than a guessed list.
Verdict.ORDERS = {
	-- Pure classes: role argument is accepted but ignored.
	WARRIOR  = { melee = { "Strength", "Stamina", "Agility" } },
	ROGUE    = { melee = { "Agility", "Strength", "Stamina" } },
	HUNTER   = { melee = { "Agility", "Stamina", "Intellect" } },
	MAGE     = { spell = { "Intellect", "Spirit", "Stamina" } },
	PRIEST   = { spell = { "Intellect", "Spirit", "Stamina" } },
	WARLOCK  = { spell = { "Intellect", "Spirit", "Stamina" } },
	-- Hybrids: two orders, no default.
	DRUID    = {
		-- C1b (t_03a1196c), §9: Druid is a hybrid. Its `spell` role carries
		-- the documented int>agi>sta (stat-weights §8.1). Its `melee` role
		-- (feral) has NO documented order in the corpus — so it is present
		-- as a role (the picker and the "no role picked" reason both see a
		-- second role) but resolves to nil, and a feral Druid's chest rows
		-- stay UNKNOWN instead of reading an Intellect-first arrow (R5).
		melee = NO_ORDER,
		spell = { "Intellect", "Agility", "Stamina" },
	},
	PALADIN  = {
		-- Both docs (stat-weights §8.1 and the t_97a8ea03 scoping card, §5.3)
		-- state Paladin melee as str>int>sta — same shape as Shaman melee,
		-- with the second-order reversal on the primary axis.
		melee = { "Strength", "Intellect", "Stamina" },
		spell = { "Intellect", "Stamina", "Strength" },
	},
	SHAMAN   = {
		melee = { "Strength", "Intellect", "Stamina" },
		spell = { "Intellect", "Strength", "Stamina" },
	},
}

-- A class is HYBRID if it carries more than one order. Pure classes ignore
-- the role argument; hybrid classes REQUIRE it.
local isHybrid = function(token)
	local table_ = Verdict.ORDERS[token]
	if not table_ then return false end
	local n = 0
	for _ in pairs(table_) do n = n + 1 end
	return n > 1
end

-- The stat order for `token` and `role` (role is "melee" | "spell" | nil).
-- Returns nil when the class is unknown or is a hybrid without an explicit
-- role. A pure class returns its documented order regardless of role.
function Verdict.classRoleOrder(token, role)
	if type(token) ~= "string" then return nil end
	local table_ = Verdict.ORDERS[token]
	if not table_ then return nil end
	if isHybrid(token) then
		if type(role) ~= "string" then return nil end
		local order = table_[role]
		-- C1b (t_03a1196c): a documented role whose corpus has no order
		-- (Druid `melee`) resolves to nil — not an empty list, not a guess —
		-- so the caller's `order == nil` branch fires and the rows stay
		-- UNKNOWN with the "no stat order resolved" reason.
		if order == NO_ORDER then return nil end
		return order
	end
	-- A pure class: a single documented order, role argument accepted and ignored.
	for _, v in pairs(table_) do return v end
	return nil
end

-- ---- Role vocabulary aliasing (card t_0b4ddfa9) -----------------------------
-- The order tables above are keyed on the addon's OWN two role words
-- (melee | spell). The CLIENT speaks a different three-word vocabulary: its
-- C_SpecializationInfo spec role is the uppercase literal TANK / HEALER /
-- DAMAGER (ChestAdvisor.lua readSpecIdentity; Lena §3). Until this card the two
-- vocabularies never met — readSpecIdentity() was read and then consumed ONLY by
-- the off-hand/shield gate, so a Protection character, whose spec is TANK, could
-- not reach a stat order at all and every row read UNKNOWN with a reason telling
-- the player to type a word the picker rejects.
--
-- This table is the mapping. It is an ADDITIVE interpretation of the order the
-- corpus ALREADY documents — not a new order, and not a weight table:
--   TANK    -> spell  (Intellect>Stamina>Strength). A CONSERVATIVE PROXY for a
--                      Protection character, not a true Prot weighting. A real
--                      Prot model (stamina/defense/block-first) is a separate
--                      design question that needs corpus sourcing; it is NOT
--                      settled here (Mira's ruling on t_0b4ddfa9).
--   HEALER  -> spell  (the Holy order — the only healing order documented).
--   DAMAGER -> melee  (Retribution's str>int>sta, the physical-damage order).
--
-- ONLY hybrid classes may alias. A PURE class has no entry here on purpose: it
-- ignores the role argument and carries a single documented default that a
-- client-derived guess must never replace — and a second key would make
-- isHybrid() true and start demanding a role it never needed
-- (guarded by upgrade_test.js 'a pure class (WARRIOR) needs no explicit role').
local ROLE_ALIAS = {
	PALADIN = { TANK = "spell", HEALER = "spell", DAMAGER = "melee" },
	-- Tank path (card t_89440dfa), RULING (c): a Warrior's TANK role reaches the
	-- tank relevance set too. WARRIOR stays a PURE class (its ORDERS entry keeps
	-- its single `melee` key, so isHybrid stays false and a Warrior with no role
	-- picked still resolves Strength>Stamina>Agility — the landmine the ruling
	-- names). Only TANK is mapped: `melee` is already the Warrior's own word, so
	-- the alias is the identity for the stat order and a no-op for every existing
	-- assertion. HEALER / DAMAGER are deliberately absent — they stay nil and
	-- unchanged (Mira: "Adding DAMAGER is NOT needed and would change nothing").
	-- ⚠ The honest limitation: TANK -> "melee" means a Prot Warrior's ORDER is the
	-- same as a Fury Warrior's. That is intended: the order only WORDS the reason
	-- (point 3), the arrow comes from the dominance/trade-off test.
	WARRIOR = { TANK = "melee" },
}

-- ---- Tank path (card t_89440dfa): the stat RELEVANCE set ---------------------
--
-- Points 1 and 3 of the owner's order: the arrow comes from a three-outcome
-- dominance test over a SET of stats, and the existing order's SEQUENCE stops
-- deciding. The set is not invented — it is exactly the terms already present in
-- that class/role's documented order (so a Warrior's never mentions Spirit), plus
-- Armor and Block, which RULING (b) makes unconditional (they are real stats for
-- every class, not tank-only knowledge).
--
-- The order survives ONLY to word the reason (reasonWord below).
--
-- Returns an array of the order's words with duplicates removed, Armor and Block
-- appended when absent. The order's own array is never mutated.
function Verdict.relevanceSet(order)
	local set, seen = {}, {}
	local function add(word)
		if type(word) ~= "string" or seen[word] then return end
		seen[word] = true
		set[#set + 1] = word
	end
	if type(order) == "table" then
		for _, word in ipairs(order) do add(word) end
	end
	-- Armor and Block join UNCONDITIONALLY (RULING (b)) — after the order's own
	-- words, matching their tiebreak position (Armor then Block).
	add("Armor")
	add("Block")
	return set
end

-- ---- Armor type (install-17 playtest) ---------------------------------------
--
-- Armor value only breaks a tie. It does not notice that a cloth belt is the
-- wrong material for a mail-wearing paladin, so a cloth quest reward used to
-- read TRADE_OFF against equipped mail. For the slots that HAVE an armor type,
-- a material below the best type this class can wear at this level is never
-- an upgrade and never a trade-off.
--
-- ASSUMPTION (WoW: Forever classic beta). This client is Classic-era (1.12
-- rules, no GetTalentInfo). Nothing in this repo or in the Forever UI extracts
-- it vendors shows a different armor-proficiency breakpoint, so the table is
-- the vanilla one: warriors and paladins wear mail until 40 and plate after;
-- hunters and shamans wear leather until 40 and mail after; rogues and druids
-- stay leather; mages, priests and warlocks stay cloth. If Forever trains the
-- next armor type at a different level, only this table changes.
--
-- Fail safe: an unknown class or a non-number level returns nil and the caller
-- does not apply the rule. Cloaks, jewelry, shields, off-hands and weapons
-- have no armor-type rank here and are never downgraded by this rule.
Verdict.ARMOR_RANK = { cloth = 1, leather = 2, mail = 3, plate = 4 }

-- Highest threshold whose level is <= the character's level wins.
Verdict.ARMOR_BEST = {
	WARRIOR = { { level = 40, armor = "plate" }, { level = 1, armor = "mail" } },
	PALADIN = { { level = 40, armor = "plate" }, { level = 1, armor = "mail" } },
	HUNTER  = { { level = 40, armor = "mail" }, { level = 1, armor = "leather" } },
	SHAMAN  = { { level = 40, armor = "mail" }, { level = 1, armor = "leather" } },
	ROGUE   = { { level = 1, armor = "leather" } },
	DRUID   = { { level = 1, armor = "leather" } },
	MAGE    = { { level = 1, armor = "cloth" } },
	PRIEST  = { { level = 1, armor = "cloth" } },
	WARLOCK = { { level = 1, armor = "cloth" } },
}

local ARMOR_TYPE_SLOTS = {
	head = true, shoulders = true, shoulder = true, chest = true, robe = true,
	wrists = true, wrist = true, hands = true, hand = true,
	waist = true, legs = true, feet = true, foot = true,
}

function Verdict.bestArmor(classToken, level)
	if type(classToken) ~= "string" or type(level) ~= "number" then return nil end
	local rows = Verdict.ARMOR_BEST[classToken]
	if type(rows) ~= "table" then return nil end
	local best, bestLevel = nil, -1
	for _, row in ipairs(rows) do
		if type(row) == "table" and type(row.level) == "number"
			and type(row.armor) == "string"
			and level >= row.level and row.level >= bestLevel then
			best = row.armor
			bestLevel = row.level
		end
	end
	return best
end

-- The material word on a typed armor slot line ("Waist  Cloth", "Legs Leather").
-- Nil when the lines do not name one of those slots — a cloak's "Back", a ring's
-- "Finger", a weapon — so the caller leaves the verdict alone.
function Verdict.tooltipArmorMaterial(lines)
	if type(lines) ~= "table" then return nil end
	local materials = { "cloth", "leather", "mail", "plate" }
	for _, line in ipairs(lines) do
		if type(line) == "string" then
			local low = line:lower():gsub("^%s+", ""):gsub("%s+$", "")
			for _, mat in ipairs(materials) do
				local slot = low:match("^([%a]+)%s+" .. mat .. "$")
				if slot and ARMOR_TYPE_SLOTS[slot] then return mat end
			end
		end
	end
	return nil
end

-- true, reason when the candidate's armor type is below the class's best.
-- nil when the rule does not apply (unknown class/level, no typed slot).
function Verdict.lowerArmorReason(lines, spec)
	if type(spec) ~= "table" then return nil end
	local best = Verdict.bestArmor(spec.class, spec.level)
	if type(best) ~= "string" then return nil end
	local mat = Verdict.tooltipArmorMaterial(lines)
	if type(mat) ~= "string" then return nil end
	local rank = Verdict.ARMOR_RANK
	if type(rank[mat]) ~= "number" or type(rank[best]) ~= "number" then return nil end
	if rank[mat] < rank[best] then
		return true, mat .. ": you can wear " .. best
	end
	return nil
end

-- The three-outcome dominance test over the role's own order terms.
--
--   dominant  — C >= W on every term, and C > W on at least one  -> UPGRADE
--   dominated — C <= W on every term, and C < W on at least one  -> NOT_UPGRADE
--   trade-off — better on some, worse on others                  -> trade-off
--   equal     — nothing differs                                 -> nil (the
--               caller's existing "equal" tiebreak fall-through)
--
-- ⚠ THE ABSENT-STAT RULE (AC-F), and the reading chosen.
--
-- A stat present on ONE side only is NOT "unknown" by the time we are here.
-- Gates 5 and 8 (above) return UNKNOWN the moment a non-blank line on EITHER
-- side cannot be classified — so a pair reaches a verdict ONLY when every
-- line on both sides parsed cleanly. A stat with no line on a side therefore
-- means the item genuinely HAS none of it: it is a KNOWN absence, i.e. 0 of
-- that stat — not a fabricated value standing in for a read we could not make.
--
-- The convention below is therefore the card's option (a) read strictly, with
-- the one-sided term handled as its own DIRECTION rather than dropped:
--   * present on the CANDIDATE only -> the candidate is strictly GREATER there
--     (a gain);
--   * present on the WORN only      -> strictly LESSER (a loss);
--   * absent on BOTH sides          -> no information, ignored.
-- A pair is trade-off only when it has BOTH a gain and a loss — which is the
-- card's own definition ("better on SOME, worse on OTHERS"); a gain with no
-- loss is dominance, a loss with no gain is dominated. This is what keeps
-- AC-B (the Barkeeper pair: gain Stamina, gain Armor, lose Strength -> both)
-- and the live capture (gain Agility and Armor, lose nothing -> dominance)
-- correct at the same time. The one-sided term is NEVER printed as a 0: the
-- reason says "absent" (tradeOffReason below).
--
-- ⚠ Armor and Block are deliberately NOT terms of this proof — they are the
-- tiebreak (see gate 9 below). E2 (t_8bc7d7f2, §4.1a) ruled "armour is never a
-- win, only a tiebreak" and graded AC-E13(b) "armour never overturns a
-- class-order loss"; a higher-armour/lower-primary pair must stay
-- NOT_UPGRADE, not become a trade-off.
--
-- Returns "dominant" | "dominated" | "trade-off" | nil, firstDiff
--   firstDiff — the first term (in order) where the two sides differ, or nil.
--               Callers use it ONLY to word a reason; it never decides.
function Verdict.dominance(candStats, eqStats, order)
	local cand = type(candStats) == "table" and candStats or {}
	local eq   = type(eqStats)   == "table" and eqStats   or {}
	local anyGreater, anyLesser = false, false
	local firstDiff = nil
	for _, word in ipairs(order or {}) do
		local c = rawget(cand, word)
		local e = rawget(eq,   word)
		if c ~= nil and e ~= nil then
			if c > e then anyGreater = true elseif c < e then anyLesser = true end
		elseif c ~= nil then
			anyGreater = true
		elseif e ~= nil then
			anyLesser = true
		end
		if firstDiff == nil then
			if not (c == nil and e == nil) and c ~= e then
				-- nil vs a value counts as a difference (the absence rule above);
				-- value vs value compares directly.
				if c == nil or e == nil or c ~= e then firstDiff = word end
			end
		end
	end
	if anyGreater and anyLesser then return "trade-off", firstDiff end
	if anyGreater then return "dominant", firstDiff end
	if anyLesser then return "dominated", firstDiff end
	return nil, nil
end

-- Map the CLIENT's role literal onto this table's own role word, or nil when
-- there is no mapping (a pure class, an unmapped hybrid, a malformed value).
-- nil is the honest "no role resolved" — the caller's `order == nil` branch
-- stays UNKNOWN rather than guessing an order.
function Verdict.clientRoleWord(token, clientRole)
	if type(token) ~= "string" or type(clientRole) ~= "string" then return nil end
	local map = ROLE_ALIAS[token]
	if not map then return nil end
	return map[clientRole:upper()]
end

-- The documented, conservative vocabulary of Classic Era low-level items
-- (five words plus Armor). A word outside this list is UNKNOWN — never a
-- fabricated 0, and never dropped silently.
local KNOWN = {
	["Strength"]   = true,
	["Agility"]    = true,
	["Stamina"]    = true,
	["Intellect"]  = true,
	["Spirit"]     = true,
	["Armor"]      = true,
	-- Tier B (t_73e20edb), §8.2: `Block` is a real shield stat the client
	-- prints ("6 Block"), and it was suppressing because it was absent from
	-- this table — a shield failing closed on its own most shield-shaped
	-- line. Adding it here is necessary but not sufficient: an unconsumed
	-- word is ignored by orderedCompare, so `Block` ALSO joins the tiebreak
	-- as a second term after `Armor` (see gate 9). Not a weight, not a
	-- coefficient — a tiebreak term, the same shape E2 ruled for Armor.
	["Block"]      = true,
	-- Defect 2 (card t_548f0341): the client's own `ITEM_MOD_SPELL_POWER` key.
	-- The tooltip spells this stat as the sentence "Equip: Increases damage and
	-- healing done by magical spells and effects by up to 11."; no content
	-- pattern in this parser can read a number out of that sentence, so the line
	-- suppresses. It is KNOWN here so that the ONE value the client's own stat
	-- read hands us (11) can be folded in when it resolves that line — and so
	-- that nothing else has to change for it to be a real word.
	["SpellPower"] = true,
}

-- ---- Defect 2 (card t_548f0341): the client's own stat read -----------------
--
-- `C_Item.GetItemStats(itemLink)` returns the item's stats as a key -> value
-- table on this client. It is NOT a superset of the tooltip: the owner's worn
-- shield reads Armor 478 / Block 9 / Sta 4 / Spi 2 on the tooltip and
-- Armor 478 / Sta 4 / Spi 2 from the API — **Block is absent from it**. So the
-- API never REPLACES the text parse (replacing it would drop the very stat the
-- Tier-B shield card added on purpose). It only RESOLVES a line the text parser
-- could not place, in parseSide's reconciliation below.
--
-- This table is the ONLY place a client key becomes a stat word, and it lists
-- ONLY the keys OBSERVED on the owner's own client (harvested 2026-10-07 from his
-- level-22 paladin's helm and worn shield). A key that is not verified is
-- ABSENT, so it resolves to nil and its line stays suppressive — the same
-- fail-closed answer as an absent API. That is deliberate: inventing a spelling
-- for Defense / Dodge / Parry / Block-rating / Hit / Crit (which are on none of
-- his 19 slots at level 22, so their client spellings are unharvested) is a
-- separate card that begins with its own harvest probe.
--
-- Both the `_SHORT` and the bare form are tolerated, because the client spells
-- the same key with and without the suffix depending on the stat (Stamina ships
-- as `ITEM_MOD_STAMINA_SHORT`; Armor ships as the bare-ish `RESISTANCE0_NAME`).
Verdict.ITEM_STAT_KEYS = {
	ITEM_MOD_STAMINA     = "Stamina",
	ITEM_MOD_STRENGTH    = "Strength",
	ITEM_MOD_AGILITY     = "Agility",
	ITEM_MOD_SPIRIT      = "Spirit",
	-- RESISTANCE0 is the client's own name for the Armor stat. Verified against
	-- the owner's worn shield: 478 Armor on the tooltip == RESISTANCE0_NAME 478.
	RESISTANCE0          = "Armor",
	ITEM_MOD_SPELL_POWER = "SpellPower",
}

-- May the client's own stat read EXPLAIN this tooltip line?
--
-- Card t_548f0341 (Defect 2) widens what is readable, so it must not overturn a
-- line that is suppressive BY DESIGN. The design (t_97a8ea03 scoping / E1 AC-E8)
-- keeps exactly ONE shape suppressive with no exception, including when
-- color-coded: "Set: <name>" — a set bonus, and this client has no set API.
--
-- The guard is not cosmetic. A set NAME is free text a player picks from, and it
-- can contain a stat word: "Set: Spirit of the Bear" while the client's read also
-- names Spirit would otherwise be claimed by the reconciler, the line would stop
-- suppressing, and the item would become UPGRADE-reachable — precisely the
-- outcome AC-E8 forbids. Measured before the guard existed: with an injected
-- { Spirit = 5 } the pair read UPGRADE / "better on Agility".
--
-- ---- The module's ONE de-colour normaliser (card t_02877bb4) ----------------
--
-- Every consumer of "the surviving content after the colour escapes" goes
-- through this function: parseLine_, Verdict.reconciliationSafe and
-- Verdict.lineCarriesNumber. Before this card each of the three carried its OWN
-- copy of the strip, so the module's claim to "one shared test" was false in the
-- one way that mattered — the three could (and did) drift.
--
-- WHAT IT REMOVES, and in the order it must:
--   1. the colour code — `|c` + EIGHT hex digits (AARRGGBB). Eight is the
--      client's fixed width and is what parseLine_ already keyed on; a
--      greedy `%x+` would EAT THE FIRST DIGIT OF THE CONTENT of a coloured
--      line ("|cffffffff2 Sturdy Tunic"), turning a number-bearing line into a
--      number-free one and silently changing a verdict. Width 8 is the safe
--      and correct form.
--   2. the `|r` reset. This must run BEFORE step 3, or step 3 strips the
--      introducer and leaves a bare `r` glued to the content ("Soulbound|r"
--      -> "soulboundr", which matches no clause).
--      ⚠ It removes a reset only where the `r` is NOT the first letter of the
--      following word (`%A`), plus the end-of-string form. A bare `gsub("%|r",
--      "")` also eats the leading "r" of a following WORD, and that is a real
--      defect, measured: de-colouring "|cff1eff00|Requires Level 21" gave
--      "equires level 21", the requires-level clause stopped matching, and a
--      STRUCTURAL line began suppressing — a verdict changed purely by adding a
--      colour prefix. The guard is only reachable when a colour code is
--      immediately followed by another escape (`…|cff1eff00|…`), which is the
--      same shape family as this card's own defect; both are pinned by
--      AC-B-invariant in the tests.
--   3. any surviving `|` — the RESIDUAL INTRODUCER. This is the defect this
--      card exists for. A colour code that is immediately followed by another
--      escape keeps its introducer after steps 1-2:
--          "|cff1eff00|Set: Defias Leather|r"  ->  "|set: defias leather"
--      and the carve-out's `^set%s*:` anchor — which keys on the SURVIVING
--      content rather than on a shape prefix — never fires, so the line stops
--      suppressing and the item becomes UPGRADE-reachable. Measured at the
--      pre-card base: UNKNOWN; measured before this fix: UPGRADE.
--
-- Why a lone `|` can be removed unconditionally: in this client's tooltip text
-- a single `|` ALWAYS opens an escape sequence — a literal pipe ships doubled
-- ("||"). So a `|` still standing after steps 1-2 is escape residue by
-- construction, never content.
--
-- HONEST SCOPE, unchanged from the pre-card note: steps 1-3 do not model every
-- escape. The `|H…|h` hyperlink wrapper and the `|A:…|a` texture markup lose
-- only their introducers, so their payloads survive verbatim; a payload that
-- carries digits therefore still reads as number-carrying and still suppresses
-- — i.e. it fails CLOSED, which is the safe direction.
local function deColour_(s)
	return s:gsub("%|c%x%x%x%x%x%x%x%x", "")  -- 1. colour open: |c + AARRGGBB
		:gsub("%|r(%A)", "%1")                 -- 2. reset, only when NOT followed by a letter
		:gsub("%|r$", "")                      -- 2b. and the same at end-of-string
		:gsub("%|", "")                        -- 3. any orphaned introducer
end

-- Keys on the SURVIVING content after the de-colour normaliser (`deColour_`,
-- the SAME one parseLine_ and lineCarriesNumber use), never on the shape prefix.
function Verdict.reconciliationSafe(line)
	if type(line) ~= "string" then return false end
	local low = line:gsub("^%s+", ""):gsub("%s+$", "")
	local plain = deColour_(low:lower())
	if plain:match("^set%s*:") then return false end
	return true
end

-- ---- Card t_b7a9e7a5: cosmetics never change a verdict, only stats do -------
--
-- The owner's ruling, quoted: "lets make it to where it doesnt matter the
-- cosmetics, just stats." The rule this card implements:
--
--   A tooltip line carrying NO number can NEVER suppress a verdict.
--   A line that carries a number and cannot be read STILL suppresses.
--
-- The caution belongs on unreadable NUMBERS — that is a stat we may have
-- mis-read — never on PROSE we did not recognise. The defect this fixes is
-- visible and self-contradictory: the client appends wardrobe chrome to the
-- QUEST-GIVER tooltip ("You haven't collected this appearance") and not to the
-- BAG tooltip, so ONE item with IDENTICAL stats (61 Armor / +5 Str / +5 Sta)
-- read UNKNOWN on the quest reward and UPGRADE in the bags. Enumerating English
-- chrome can never deliver that invariant — the client will add the next string
-- — so the rule is keyed on the line's own SHAPE, not on a vocabulary.
--
-- ⚠ The test runs on the DE-COLOURED form, for a load-bearing reason: a colour
-- escape ("|cff00ff00") is itself EIGHT HEX DIGITS. Testing the raw text would
-- read every colour-coded cosmetic line as number-carrying, the rule would
-- never fire on the very screenshots this card exists for, and it would look
-- correct while doing nothing. The strip is `deColour_` — the module's ONE
-- normaliser, the SAME one parseLine_ and `reconciliationSafe` use (card
-- t_02877bb4 made that literal: three call sites shared one definition).
--
-- HONEST SCOPE: `deColour_` removes the `|c…`/`|r` escapes and the residual
-- introducer, but it does not model every escape. Another escape form whose
-- payload carries digits (the client's `|A:coin-silver:14:14:2:0|a` texture
-- markup) keeps its digits, so such a line still reads as number-carrying and
-- still suppresses — i.e. it fails CLOSED, which is the safe direction. Every
-- digit-bearing chrome line in this repo's corpus is structural-classified
-- before it ever reaches this test (Sell Price / Durability / Requires Level),
-- so the limitation is not reachable from captured shapes.
function Verdict.lineCarriesNumber(line)
	if type(line) ~= "string" then return false end
	local low = line:gsub("^%s+", ""):gsub("%s+$", "")
	local plain = deColour_(low:lower())
	return plain:find("%d") ~= nil
end

-- The disclosure (card t_b7a9e7a5, requirement 5). When a cosmetic line was
-- IGNORED rather than suppressing, the verdict still appears — and the fact
-- that something was skipped must be AVAILABLE to a caller, never silently
-- implied away. This renders that fact as a short, deterministic suffix, or ""
-- when nothing was skipped, so a caller can append it (or test it) without
-- owning the wording. It is deliberately NOT part of the headline verdict word:
-- the arrow still means exactly what it meant.
--
-- `ignored` is the array parseSide/statTable/evaluate hand back (raw lines, in
-- the order they were met).
function Verdict.partialNote(ignored)
	local n = 0
	if type(ignored) == "table" then
		for _ in ipairs(ignored) do n = n + 1 end
	end
	if n == 0 then return "" end
	if n == 1 then return "partial read: 1 cosmetic line ignored" end
	return "partial read: " .. n .. " cosmetic lines ignored"
end

-- A client stat key -> this module's stat word, or nil for a key we have not
-- verified. Pure: the table above is the whole vocabulary, no client call.
--
-- The longest verified key wins, so a shorter key can never shadow a longer one
-- that shares its prefix.
function Verdict.apiStatWord(key)
	if type(key) ~= "string" then return nil end
	local bestKey, bestWord = nil, nil
	for k, word in pairs(Verdict.ITEM_STAT_KEYS) do
		if key == k or key:sub(1, #k + 1) == k .. "_" then
			if bestKey == nil or #k > #bestKey then bestKey, bestWord = k, word end
		end
	end
	return bestWord
end

-- The client's raw stat table, mapped into this module's stat words. `raw` is
-- whatever `C_Item.GetItemStats` returned — READ AT THE IMPURE EDGE, in
-- ChestAdvisor.lua. This module never calls a client API, so the JS harness can
-- drive every branch below with an injected table.
--
-- Returns: words — stat word -> number, for the keys we have verified only
--          named — the set of words it named (so a caller can ask "does the API
--                  name a stat the text parse did not capture?")
-- A non-table (nil, a string, a secret sentinel) returns nil, nil: the caller's
-- byte-identical-to-today path.
function Verdict.apiStats(raw)
	if type(raw) ~= "table" then return nil, nil end
	local out, named = {}, {}
	for key, value in pairs(raw) do
		local word = Verdict.apiStatWord(key)
		if word ~= nil and type(value) == "number" then
			out[word] = value
			named[word] = true
		end
	end
	return out, named
end

-- The three role words the CLIENT speaks (readSpecIdentity). Used to tell a
-- real role word from a malformed one: an unrecognised word is not a role the
-- class-level fallback below may answer for.
local CLIENT_ROLES = { TANK = true, HEALER = true, DAMAGER = true }

-- Classify a single tooltip line. Buckets:
--   stat       num + word   — a single-word stat line ("+12 Agility",
--                            "12 Armor", "Adds 12 Haste"); KNOWN[word]
--                            decides stat vs. proc below.
--   proc       "Equip:X"    — a proc line ("Equip: +5 Crit").
--   structural (nil, nil, "structural") — a known NON-stat line of a real
--                            item tooltip: "Durability 45 / 45",
--                            "Requires Level 10", "Sell Price: 2s 10c",
--                            "Chest <material>". Ignored — never a
--                            suppression (Vera C1: the B2 gate must not
--                            swallow real tooltip chrome).
--   unknown    (nil, "Unknown", "unknown") — a non-blank line we could NOT
--                            place ("+15 Frost Resistance"): not a
--                            fabricated zero, not silently dropped.
--   blank      (nil, nil)   — nothing here, nothing to judge.
--
-- Structural vocabulary: the shapes verified by this repo's in-game-proven
-- tooltip fixture (tests/addon_test.js:886 — item name, type line,
-- "Requires Level 14") and the scoping card's P1 probe. Anything NOT in
-- this list and NOT stat-shaped still suppresses: unconfirmed lines
-- default to unknown (Vera C1, "suppress anything unconfirmed"). The
-- item NAME line (free text — no content pattern can enumerate item
-- names) is handled positionally by parseSide, where the scan path's
-- line list starts at the name on a real client.
local parseLine_ = function(line)
	if type(line) ~= "string" then return nil, nil end
	local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" then return nil, nil end
	local low = trimmed:lower()
	-- `plain` is `low` with the colour escapes, the `|r` reset and any residual
	-- escape introducer removed, so structural pattern matching keys on
	-- CONTENT rather than shape. It is produced by `deColour_` — the module's
	-- ONE normaliser (card t_02877bb4), the SAME one `reconciliationSafe` and
	-- `lineCarriesNumber` call. Before that card each of the three carried its
	-- own copy of the strip; the copies drifted, and parseLine_'s copy left a
	-- stray `|` behind on "|cff1eff00|Set: …|r" — the defect the card fixes.
	--
	-- The capture's crafter line ships as "|cff00ff00<Made by …>|r"; the strip
	-- leaves "<made by …>" which matches a narrow clause below (patch 3).
	-- Without this, a broad shape rule ("^%|c") accepts a colored "Set: …" as
	-- structural when the card rule says Set: must suppress (AC-E8, Vera
	-- run-63).
	local plain = deColour_(low)
	-- "+12 Agility" -> num + word. The prefix class is only signs and
	-- whitespace (never digits) so the captured number is the whole value.
	-- A chest's bare armor line ("12 Armor") lands here too and reads as
	-- the known stat Armor — inert in practice, since no order in ORDERS
	-- consumes Armor, and never a suppression trigger.
	local num, word = trimmed:match("^%s*[%+%-%s]*(%d+)%s+(%a+)$")
	if num and word then
		return tonumber(num), word
	end
	-- proc line:  "Equip: +X Foo"
	local pnum, pword = trimmed:match("^%s*Equip:%s*%+%s*(%d+)%s+(%a+)")
	if pnum and pword then
		return nil, "Equip:" .. pword
	end
	-- "Adds X" style lines, if the client ever uses them here.
	local an, aw = trimmed:match("^%s*Adds%s*(%d+)%s+(%a+)")
	if an and aw then return tonumber(an), aw end
	-- Structural tooltip chrome (Vera C1). Case-insensitive, anchored.
	-- Matched against `plain` (color/|r stripped) so a colored stat line
	-- (e.g. "|cff9d9d9d+12 agility|r") still classifies as a stat below,
	-- never as chrome.
	if plain:match("^durability%s+%d") then return nil, nil, "structural" end
	if plain:match("^requires level%s+%d") then return nil, nil, "structural" end
	if plain:match("^reqs%.%s*level%s+%d") then return nil, nil, "structural" end
	if plain:match("^sell%s*price%s*:") then return nil, nil, "structural" end
	if plain:match("^sells for%s*$") then return nil, nil, "structural" end
	-- The type line: "<slot word> <material>" for every in-scope armour
	-- slot. Phase D (chest-only) enumerated only "Chest <material>"; Phase E
	-- (E1, t_7b8f504a) generalises to all nine armour slots so that widening
	-- the scan (E3) does not suppress every item's own type line.
	--
	-- Slot words: the client's tooltip type line spells these as they appear
	-- in-scoring:
	--   Head Shoulders Chest Back Wrists Hands Waist Legs Feet
	-- The AC-E6 spec (scoping §6, t_970229ce doc) uses the plural forms for
	-- Shoulder(s) and Wrist(s). The repo's own in-game-proven vocabulary
	-- (WoWAI.lua:1034-1036, :1083-084) spells them singular. AC-E8 point 1
	-- of mira's amendment (comment 58, t_7b8f504a): "the AC-E6 plural
	-- spellings are NOT evidence." We accept both forms — the vocabulary is
	-- a spelling-acceptance list and an unrecognised form degrades to
	-- unknown (suppress), never to a wrong classification.
	--
	-- Materials: Cloth Leather Mail Plate (the four armour material words the
	-- client uses on type lines; verified by captures, scoping §4.2).
	--
	-- Lua 5.1 note: no alternation group with unequal-length alternatives
	-- (fengari enforces this), so each material is its own `or` clause.
	local SLOT_WORDS = { "head", "shoulders", "shoulder", "chest", "back",
	                     "wrists", "wrist", "hands", "waist", "legs", "feet" }
	local MATERIALS  = { "cloth", "leather", "mail", "plate" }
	local is_type_line = false
	for _, slot in ipairs(SLOT_WORDS) do
		if low:match("^" .. slot .. "%s+") then
			for _, mat in ipairs(MATERIALS) do
				if low:match("^" .. slot .. "%s+" .. mat .. "$") then
					is_type_line = true
					break
				end
			end
			break
		end
	end
	if is_type_line then return nil, nil, "structural" end
	-- Back is the ONE in-scope armour slot whose client type line carries no
	-- material word: the client emits a bare "Back". The composite matcher
	-- above requires `%s+<material>`, so a bare "Back" never matched, fell
	-- through to the unplaceable tail below, and suppressed the whole item —
	-- every cloak, every class, unconditionally (live bug 2, t_daa20c6f).
	-- Proven from the client's own SavedVariables: a Feral Cloak candidate
	-- and a Feral Cloak worn item both carrying the type line "Back" read
	-- UNKNOWN / "cannot classify: Back" on install #9's deployed bytes.
	--
	-- Exact equality, deliberately: this accepts the bare slot word and
	-- nothing else, so "Backpack" and "Back  of the Bear" still suppress via
	-- the unplaceable tail. Note the composite matcher's `%s+` already
	-- prevented "Backpack" from matching earlier, and that is preserved.
	-- The evidence covers Back only — no other slot is known to emit a bare
	-- type line, so this is not generalised to a bare slot word for all
	-- nine (that would be a behaviour change beyond the measurement).
	if low == "back" then return nil, nil, "structural" end
	-- Rings, necks and trinkets print a BARE slot word (no material column).
	-- A Horn Ring's type line is exactly "Finger"; that used to fall through
	-- to the unplaceable tail and the whole ring read "cannot classify: Finger".
	-- Same exact-equality rule as "Back": "Fingerprint" still suppresses.
	-- Shirt and tabard are the same shape on this client and are chrome.
	if low == "finger" or low == "neck" or low == "trinket"
		or low == "shirt" or low == "tabard" then
		return nil, nil, "structural"
	end
	-- Tier B (t_73e20edb), §8.1 — the off-hand type line. A shield's type
	-- line reads left column "Off Hand" with the subtype in the right column,
	-- so the reader joins it to "Off Hand  Shield"; a held-in-off-hand item
	-- reads "Held In Off-hand"; an off-hand weapon reads "Off Hand  <subtype>".
	-- None matched the composite `<slot>%s+<material>` matcher above (there is
	-- no "off hand" slot word and no "shield" material word), so every one of
	-- them fell to the unplaceable tail and suppressed the whole item — the
	-- same shape as the cloak/`Back` defect (Live-bug-2, t_daa20c6f).
	--
	-- Accepted EXACTLY: the bare token, or the token plus ONE subtype word.
	-- Deliberately narrow, for the same reason the `Back` rule is exact:
	-- "Off Handed" and free text beginning "Off Hand ..." must still suppress
	-- via the unplaceable tail rather than ride in on a loose prefix. The
	-- subtype word is unconstrained because the client's subtype vocabulary
	-- ("Shield", "Dagger", "Held In Off-hand", …) is not enumerated in this
	-- repo's proven corpus; an unenumerated subtype must classify the LINE as
	-- chrome, not decide anything — the §2 token/class buckets do the deciding,
	-- and they are taken from the candidate's equip location, never from this
	-- line.
	--
	-- NOTE (honest scope): the exact live spelling of the holdable line is
	-- NOT captured in this repo (Lena §11.4 says the same of `Block`). The
	-- accepted set below covers the two forms the two local sources name —
	-- the card's "Off Hand" and Lena's "held-in-off-hand" prose — and anything
	-- else falls through to suppression, i.e. it fails closed.
	if low == "off hand" or low:match("^off hand%s+[%a%-']+$") then
		return nil, nil, "structural"
	end
	if low:match("^held in off%-hand$") or low == "held in off hand"
		or low:match("^held in off%-hand%s+[%a%-']+$")
		or low:match("^held in off hand%s+[%a%-']+$") then
		return nil, nil, "structural"
	end
	-- Structural chrome (Vera C1, E1, t_7b8f504a). Each of these ships on
	-- real items in this era (captured in the repo; see the card's WHY
	-- section and probe output at t_970229ce). Classifying as structural
	-- rather than unknown is the right choice: they carry no stat delta
	-- the comparator can use, and treating them as unknown (suppression)
	-- was the live defect the player reported.
	--
	-- Line-by-line decision:
	--   "Soulbound"            — binding, no stat content  -> structural
	--   "Binds when equipped"  — binding, no stat content  -> structural
	--   "Binds when picked up" — binding, no stat content  -> structural
	--   "Binds when used"      — binding, no stat content  -> structural
	--   "Unique"               — uniqueness, no stat content -> structural
	--   "Unique-Equipped"      — uniqueness, no stat content -> structural
	--   "Item Level N"         — item level, no stat content  -> structural
	--   "Classes: …"           — class restriction, no stat content  -> structural
	--   "Enchanted: …"         — enchant bonus, applied at RUNTIME (players
	--                           re-apply enchants); a budget-derived base
	--                           cannot already contain the bonus. parseSide
	--                           folds BOTH halves additively into the WORN
	--                           side's stats (so 55 + enchant-8 = 63 worn
	--                           armor, not 55). The CANDIDATE side still
	--                           drops the line: counting it would only
	--                           understate the candidate (weaker than the
	--                           player is wearing), and the shape is n=1 —
	--                           fail-closed.
	--   "<Made by …>" (stripped from "|cff…<Made by …>|r") / "Made by …" —
	--                           crafter name; pure chrome -> structural
	--
	-- Lines KEPT SUPPRESSIVE (could carry meaning we cannot verify):
	--   "Set: …" — set bonus; no set API on this client. Suppressive by
	--              the design's own rule (t_97a8ea03 scoping, in-set ->
	--              UNKNOWN). NOT made structural in E1. The card's AC-E8
	--              explicitly forbids this line becoming UPGRADE-reachable,
	--              including when color-coded ("|cff…Set: …|r"), so we key
	--              the structural clause on the SURVIVING content after the
	--              color strip, never on the shape prefix.
	--   The item name line — free text no content pattern can enumerate.
	--              Handled positionally by parseSide (i == 1, letter-first
	--              shape), where the scan path's line list starts at the
	--              name on a real client. The capture proves position 1 is
	--              the plain name ("Handstitched Leather Vest" —
	--              sv-longhairs-2-reload.lua:27,53,166,192); the
	--              "|cnIQ2:…|h[…]…|h|r" hyperlink that appears in the same
	--              file is the VERDICTS MAP KEY, not a parsed line, and so
	--              never reaches parseLine_ via the scan path.
	if plain:match("^soulbound$") then return nil, nil, "structural" end
	if plain:match("^binds when%s+equipped$")
		or plain:match("^binds when%s+picked up$")
		or plain:match("^binds when%s+used$") then
		return nil, nil, "structural"
	end
	if plain:match("^unique$") then return nil, nil, "structural" end
	-- `%-` is the escaped (literal) hyphen. A bare "-" following a character
	-- is a Lua pattern *quantifier* (the lazy/zero-or-one modifier), NOT a
	-- literal hyphen — so "^unique-equipped$" matches "uniqueequipped" /
	-- "uniqueeequipped" but never "unique-equipped". This clause was the
	-- shipped bug (Vera run 63, Blocking 1): it was dead code and
	-- "Unique-Equipped" still suppressed. The `%-` escape is the fix.
	if plain:match("^unique%-equipped$") then return nil, nil, "structural" end
	if plain:match("^item level%s+%d") then return nil, nil, "structural" end
	if plain:match("^classes:%s*") then return nil, nil, "structural" end
	if plain:match("^enchanted%s*:") then return nil, "Enchanted", "enchant" end
	-- Crafter line: the capture ships it as "|cff00ff00<Made by …>|r"
	-- (sv-longhairs-2-reload.lua:34,58,:173,:199) — the color strip above
	-- leaves "<made by …>", which this content clause matches. The
	-- un-colored "Made by …" form is included for completeness (the
	-- client's shape is not fixed across versions). No shape-prefix
	-- catch-all: a "|c…" line whose surviving content is NOT one of the
	-- structural clauses above falls through to unknown and suppresses
	-- — which is exactly AC-E8's "colored Set: → suppress".
	if plain:match("^%s*<made by") then return nil, nil, "structural" end
	if plain:match("^made by%s+") then return nil, nil, "structural" end
	-- Classic generic spell power. The tooltip spells it as a sentence, not
	-- "Equip: +N Word", and C_Item.GetItemStats is often empty until the item
	-- is cached — so the API reconciler never sees it and the line used to
	-- suppress the whole item ("cannot classify: Equip: Increases damage and
	-- healing..."). The number is read from the sentence itself.
	--
	-- Healing-only ("Increases healing done by spells...") and school-specific
	-- ("Increases damage done by Fire spells...") are NOT this stat. They stay
	-- unparsed on purpose: there is no Healing or FireSpellPower word to put
	-- them in, and folding them into generic SpellPower would lie.
	-- SpellPower is a known word so the line no longer suppresses. It is not
	-- in any class order (see the playtest note on Verdict.ORDERS): a melee
	-- character is judged on the item's other stats, and a caster is still
	-- judged on the documented int/spi/sta order. Spell power does not decide.
	local spn = plain:match(
		"^equip:%s*increases damage and healing done by magical spells and effects by up to (%d+)%.?$")
	if spn then return tonumber(spn), "SpellPower" end
	-- A non-blank line we cannot place. Returning "Unknown" (a word) rather
	-- than nil keeps it in the same channel as procs, so parseSide routes
	-- it to the suppression bucket exactly like any other unknown word.
	--
	-- Card t_b7a9e7a5: the THIRD return tells the caller which of the two
	-- unplaceable shapes this is, because parseSide treats them differently
	-- now — "unknown" suppresses (a number we may have mis-read), "cosmetic"
	-- is ignored and DISCLOSED. The discriminator is the de-coloured text,
	-- via the module's one shared test (Verdict.lineCarriesNumber).
	--
	-- ⚠ THE CARVE-OUT, and it is load-bearing (the card makes it mandatory):
	-- a line that is suppressive BY DESIGN is never re-labelled cosmetic,
	-- digits or not. `Verdict.reconciliationSafe` is that predicate, and it
	-- answers false for exactly one shape — "Set: <name>" (plain OR colour-
	-- coded), a real effect this client has no API to measure. A set NAME is
	-- free text a player picks from and usually carries no digits, so a naive
	-- "no number -> ignore" would silently lift it — the outcome AC-E8
	-- forbids and the t_548f0341 test pins. Asking the SAME predicate the
	-- reconciliation already asks keeps one definition of "by design".
	if not Verdict.lineCarriesNumber(line) and Verdict.reconciliationSafe(line) then
		return nil, "Unknown", "cosmetic"
	end
	return nil, "Unknown", "unknown"
end

-- Parse an enchant payload line into a (partial) stats table, using only the
-- verbatim shape observed in the capture (t_ea70928d ruling — jia-clean
-- amendment, Mightie signed off): "word +num" or "word +num and word +num"
-- (1-2 pairs, case-insensitive, word-then-number, "+" attached to the number).
-- The evidence base is n=1 (the Handstitched Leather Vest is the only
-- enchanted fixture in phase-d-evidence/), so anything outside that shape
-- declines to nil — parseSide folds that nil into the UNKNOWN bucket with
-- the raw payload in the reason string (AC-J).
--
-- Returns statsTable, nil  on success.
-- Returns nil, rawLine     on failure (for the fail-closed reason).
local function parseEnchantPayload(rawLine)
    local low = rawLine:lower()
        :gsub("^[ \t]+", "")
        :gsub("[ \t]+$", "")
    local payload = low:match("^enchanted%s*:%s*(.+)$")
    if not payload then return nil, rawLine end
    payload = payload:gsub("[ \t]+$", ""):gsub("^[ \t]+", "")
    if payload == "" then return nil, rawLine end
    local function cap(w) return w:sub(1, 1):upper() .. w:sub(2) end
    -- Two pairs: "word +num and word +num"
    local w1, n1, w2, n2 = payload:match(
        "^(%a+)%s+%+%s*(%d+)%s+and%s+(%a+)%s+%+%s*(%d+)$")
    if w1 and w2 then
        return { [cap(w1)] = tonumber(n1), [cap(w2)] = tonumber(n2) }, nil
    end
    -- One pair: "word +num"
    local w, n = payload:match("^(%a+)%s+%+%s*(%d+)$")
    if w then
        return { [cap(w)] = tonumber(n) }, nil
    end
    return nil, rawLine
end

-- ---- Defect 2 (card t_548f0341): how an API stat word reads in tooltip text --
--
-- The API names a stat in ITS vocabulary ("SpellPower"); the tooltip spells the
-- same stat in ITS own words. To decide "is this unplaceable line ABOUT this
-- API-named stat?", each word is matched against the phrasings the client is
-- observed to print. This is a RECOGNISER, not a parser: it reads no number. The
-- number folded in is always the API's own, and it is folded in only for a line
-- the text parser could NOT place, so the text parse stays primary for every
-- line it can read.
--
-- Evidence is the owner's own helm line, verbatim:
--   "Equip: Increases damage and healing done by magical spells and effects by
--    up to 11."  with the client's own ITEM_MOD_SPELL_POWER_SHORT = 11.
-- The other entries are the plain English names of stats the tooltip already
-- prints as "+N <Word>" (a stat the text parse handles anyway — these exist so
-- that a WORN-side unplaceable phrasing of the same stat reconciles too).
local API_WORD_TEXT = {
	Stamina    = { "stamina" },
	Strength   = { "strength" },
	Agility    = { "agility" },
	Intellect  = { "intellect" },
	Spirit     = { "spirit" },
	Armor      = { "armor" },
	SpellPower = { "spell power", "spellpower", "spell damage", "spell healing",
	               "magical spells", "damage and healing", "spells and effects" },
}

-- Does this tooltip line talk about `word`? Pure string work; no number is read
-- from the line. An unlisted word falls back to its own lowercased spelling, so
-- a future key degrades to a plain name match rather than to a silent yes.
local function lineNamesWord(lowerLine, word)
	local needles = API_WORD_TEXT[word]
	if type(needles) ~= "table" then
		return lowerLine:find(word:lower(), 1, true) ~= nil
	end
	for _, needle in ipairs(needles) do
		if lowerLine:find(needle, 1, true) then return true end
	end
	return false
end

-- Lines another addon appends to the RENDERED tooltip are not the item.
-- RestedXP adds "Item used in guide:" and a comparison block
-- "If you replace this item, the following stat changes will occur:" whose
-- "-N Stat" rows would parse as real stats. A bug-reporter line ("Press F6…")
-- and our own "Touchstone:" line land on the same composed tooltip. On this
-- classic client C_TooltipInfo is often absent, so the rendered tooltip is
-- the reader, and those lines used to suppress the item
-- ("cannot classify: Item used in guide: …").
--
-- A header starts a skip-to-end: the block and everything after it is foreign.
-- Sell price is the item's own terminator. A later line that carries a number
-- is an addon delta ("-8 Armor") and is foreign; a number-free line is
-- wardrobe chrome and stays, so the cosmetic path can ignore it and say so.
-- A genuine unparsed stat ("+15 Frost Resistance", a healing-only Equip line)
-- sits in the item body, before that terminator, and still suppresses.
local FOREIGN_LINE_HEADERS = {
	"item used in guide",
	"if you replace this item",
	"press f6 to submit",
	"touchstone:",
}

function Verdict.nativeLines(lines)
	if type(lines) ~= "table" then return lines end
	local out = {}
	local drop = false
	local seenSell = false
	for _, line in ipairs(lines) do
		if not drop and type(line) == "string" then
			local plain = deColour_(line:lower())
			plain = plain:gsub("^%s+", ""):gsub("%s+$", "")
			local foreign = false
			for _, header in ipairs(FOREIGN_LINE_HEADERS) do
				if plain:sub(1, #header) == header then
					foreign = true
					break
				end
			end
			if not foreign and seenSell then
				local epilogue = plain:match('^".*"$')
					or plain:match("^<made by")
					or plain:match("^made by%s+")
				-- A numbered line after the sell price is an addon delta
				-- ("-8 Armor"). A number-free line is wardrobe chrome; leave
				-- it so the cosmetic path can ignore it and say so.
				if not epilogue and plain:find("%d") then foreign = true end
			end
			if foreign then
				drop = true
			else
				out[#out + 1] = line
				if plain:match("^sell%s*price") or plain:match("^sells for") then
					seenSell = true
				end
			end
		end
	end
	return out
end

-- Parse a whole side (a list of raw tooltip lines) into:
--   stats    — a table  statWord -> number       (only KNOWN words)
--   procWord — the first proc word ("Equip:..."), if any
--   unknown  — the first non-blank line that is neither structural,
--              an Equip: proc, nor a KNOWN stat, if any (B2 + C1: lines
--              the parser cannot place suppress instead of vanishing)
--
-- `ignored` (card t_b7a9e7a5) is the FOURTH return: an array of the raw lines
-- that were IGNORED under this card's rule — unplaceable lines carrying NO
-- number (wardrobe chrome such as "You haven't collected this appearance").
-- They are not stat content and cannot make the comparison wrong, so they no
-- longer suppress — but the fact that they were skipped is handed back rather
-- than dropped, which is what lets the tooltip disclose a partial read
-- (requirement 5). Empty when nothing was skipped.
--
-- A line carrying a NUMBER that cannot be read still lands in `unknown` and
-- still suppresses, unchanged (requirement 2 — the guard's whole point).
--
-- `apiWords` (card t_548f0341, OPTIONAL) is the client's own stat read, already
-- mapped to this module's stat words by Verdict.apiStats at the impure edge.
-- It is used for ONE thing: a line the text parser cannot place is EXPLAINED
-- (and therefore no longer suppresses) when the API names a stat this parse has
-- not captured AND the line's own text talks about that stat. Nothing else about
-- the parse changes, and with `apiWords` nil every branch below is byte-identical
-- to the pre-card behaviour — the fail-closed answer for an absent API.
local parseSide = function(lines, side, apiWords)
	local stats, procWord, unknown, ignored = {}, nil, nil, {}
	if type(lines) ~= "table" then return stats, procWord, unknown, ignored end
	lines = Verdict.nativeLines(lines) or lines
	local nonblank = function(l)
		return type(l) == "string" and l:gsub("^%s+", ""):gsub("%s+$", "") ~= ""
	end
	-- The API words, in a stable order so which word claims a line cannot vary
	-- between runs (pairs() is unordered).
	local api = type(apiWords) == "table" and apiWords or nil
	local apiOrder = {}
	if api then
		for word in pairs(api) do apiOrder[#apiOrder + 1] = word end
		table.sort(apiOrder)
	end
	local apiUsed = {}
	-- Reconciliation (card t_548f0341, Defect 2): may the client's own stat read
	-- EXPLAIN this line — i.e. name a stat this parse has not captured that the
	-- line's own text talks about? Returns the claimed stat word, or nil (the
	-- line keeps suppressing, exactly as before this card).
	--
	-- Both suppression channels below call it, because the owner's own helm line
	-- arrives through the SECOND one: "Equip: Increases damage and healing … 11."
	-- does not match parseLine_'s `Equip: +N <Word>` shape, so it comes back as
	-- the "Unknown" sentinel, not as a proc word. Handling only the proc channel
	-- would have left the defect in place.
	--
	-- `rawget(stats, w) == nil` is what stops a stat the text parse ALREADY read
	-- from being claimed a second time: the text parse stays primary for every
	-- line it can read, and the API only fills what is missing.
	local function explain(line)
		if not api then return nil end
		-- A line that is suppressive BY DESIGN is never explained away.
		if type(Verdict.reconciliationSafe) == "function"
			and not Verdict.reconciliationSafe(line) then
			return nil
		end
		local low = line:lower()
		for _, w in ipairs(apiOrder) do
			if not apiUsed[w] and rawget(stats, w) == nil
				and lineNamesWord(low, w) then
				return w
			end
		end
		return nil
	end
	local function fold(word)
		apiUsed[word] = true
		stats[word] = api[word]
	end
	-- Name-line rule (Vera C1): a real item tooltip's position 1 is the item
	-- NAME — free text no content pattern can enumerate, and a chest's name
	-- may itself start with "Chest "+material. A name-shape is a letter-first
	-- line ("Trailblazer Vest", "Chest of Frost Mail"); a stat-shape always
	-- leads with a sign or digit, so it still classifies normally even at
	-- position 1 (bare-list comparator tests keep their first stat). The
	-- "Unknown" sentinel is ours, never a real line.
	for i, line in ipairs(lines) do
		local isNameShape = nonblank(line) and i == 1
			and line:match("^%s*[%a]") ~= nil
			and line ~= "Unknown"
		if isNameShape then
			-- The name line: exempt, never a suppression.
		else
			local num, word, kind = parseLine_(line)
			if word == "Enchanted" then
				-- Anchant line on the WORN side (t_ea70928d): fold BOTH halves
				-- of the enchant payload into this side's stats — the bonus is
				-- additive to base (an enchant budget is not part of the item
				-- budget). The CANDIDATE side still drops the line (unchanged,
				-- non-suppressive): counting the candidate's own enchant would
				-- only understate it, and the evidence base is n=1 (AC-C).
				if side == "worn" then
					local encStats = parseEnchantPayload(line)
					if encStats == nil then
						-- Fail-closed (AC-J): an unrecognised shape names the
						-- raw payload — no partial parse, no silent drop.
						-- Case-insensitive: the capture ships "Enchanted:" (cap E);
						-- parseLine_ already matched it via a lower-cased form, so
						-- this must too, or the payload match returns nil and the
						-- reason string concatenates against it below (AC-J crash).
						local payload = line:match("^%s*[eE]nchanted%s*:%s*(.+)$")
						unknown = unknown or ("Enchanted: " .. (payload or line))
					else
						for w, v in pairs(encStats) do
							stats[w] = (stats[w] or 0) + v
						end
					end
				end
				-- side ~= "worn": the enchant line is dropped (not counted,
				-- not suppressed) — the AC-C candidate behaviour.
			elseif type(word) == "string" then
				if word:match("^Equip:") then
					-- Reconciliation: a proc line the client's own stat read can
					-- name is not a proc — it is a stat we could not phrase.
					local claimed = explain(line)
					if claimed ~= nil then
						fold(claimed)
					else
						procWord = procWord or word
					end
				elseif KNOWN[word] then
					-- Accumulate (t_ea70928d): the worn side merges a folded enchant
					-- bonus into the same stat word (armor: 55 base + 8 enchant).
					stats[word] = (stats[word] or 0) + num
				else
					-- An Unknown word (or the "Unknown" sentinel for an
					-- unplaceable line): keep the raw line for the reason
					-- string where we have one — UNLESS the client's own stat
					-- read explains it (the owner's helm line arrives HERE, not
					-- through the proc channel: "Equip: Increases damage and
					-- healing … 11." matches no `Equip: +N <Word>` shape).
					local claimed = explain(line)
					if claimed ~= nil then
						fold(claimed)
					elseif kind == "cosmetic" then
						-- Card t_b7a9e7a5: THE LIVE PATH for an unplaceable
						-- line. parseLine_ returns its sentinel as a WORD
						-- ("Unknown"), so an unplaceable line arrives HERE
						-- (the `type(word) == "string"` channel) rather
						-- than at the tail below — verified by instrumenting
						-- the tail to throw and finding no fixture reaches
						-- it. Without this arm the cosmetic line would still
						-- suppress through `unknown` and the rule would be
						-- dead for exactly the lines it exists for.
						ignored[#ignored + 1] = line
					else
						unknown = unknown or (word == "Unknown" and line or word)
					end
				end
			elseif kind == "structural" then
				-- Legitimate tooltip chrome (durability, requires-level,
				-- sell price, type line): ignorable, NOT a suppression
				-- (Vera C1).
			elseif nonblank(line) then
				-- A non-blank line we could not place. Card t_b7a9e7a5
				-- splits this tail in two, and ORDER MATTERS:
				--
				--   1. The client's own stat read may EXPLAIN it (card
				--      t_548f0341, AC-C). This is the ONE place the API
				--      widens what is readable, and it is reachable only
				--      for a line the text parser already failed. It runs
				--      FIRST so a number-bearing line the API can name
				--      (the owner's own helm sentence) is FOLDED rather
				--      than disclosed as skipped — an explained line is
				--      understood, not ignored.
				--   2. Otherwise: a line with NO number is cosmetic —
				--      ignored, and recorded so the caller can disclose a
				--      partial read. A line WITH a number still suppresses
				--      (a stat we may have mis-read), unchanged.
				--
				-- REACHABILITY, measured rather than assumed: today this
				-- tail is NOT reached for an unplaceable line, because
				-- parseLine_ returns the sentinel as its WORD ("Unknown"),
				-- so control goes to the `type(word) == "string"` channel
				-- above. Instrumenting this branch to throw and running the
				-- whole suite leaves every test green — i.e. zero fixtures
				-- reach it. It is kept correct anyway: it is the branch that
				-- the day parseLine_ starts returning a bare `nil, nil` for
				-- an unplaceable line, and leaving the old suppress-everything
				-- body there would silently re-introduce this card's defect.
				local claimed = explain(line)
				if claimed ~= nil then
					fold(claimed)
				elseif kind == "cosmetic" then
					ignored[#ignored + 1] = line
				else
					unknown = unknown or line
				end
			end
		end
	end
	return stats, procWord, unknown, ignored
end

-- Compare two sides along an ordered list of stat names.
--   "wins"     — the candidate is strictly better at the first differing stat
--   "loses"    — the candidate is strictly worse  at the first differing stat
--   "equal"    — every shared stat is exactly equal
-- A missing stat (word not in the table) is treated as 0 for purposes of the
-- ordering — the item simply doesn't have that stat.
local orderedCompare = function(candidate, equipped, order)
	for _, word in ipairs(order) do
		local c = candidate[word] or 0
		local e = equipped[word]  or 0
		if c > e then return "wins"  end
		if c < e then return "loses" end
	end
	return "equal"
end

local function winReason(statWord)
	return "upgrade: better on " .. (statWord or "a role stat")
end

-- Tank path (card t_89440dfa): the third verdict. A pair that is better on some
-- stats and worse on others gets its own verdict and its own non-green mark —
-- neither the arrow (a confident yes) nor silence (a confident no).
--
-- ⚠ THE LITERAL. The card, the marker plumbing and the tooltip all reference one
-- word. Spell it ONCE here and read it everywhere through Verdict.TRADE_OFF, so
-- the comparator's return value cannot drift from the string the UI tests.
local TRADE_OFF = "TRADE_OFF"
Verdict.TRADE_OFF = TRADE_OFF

-- The trade-off reason: the card asks for "the exact deltas in the tooltip".
-- The deltas themselves are computed by the UI (Verdict.statDeltas/deltaText —
-- the additive helpers shipped by t_ed71a583), which reads the SAME parsed
-- tables. This builds the comparator-side line: the first (in relevance-set
-- order) term on which the sides differ, named by the ORDER's own wording
-- grammar, plus the two-sided terms that moved so a caller without the UI layer
-- still has the arithmetic.
--
-- A one-sided term (present on exactly one side) is reported as "absent", never
-- as 0 — the AC-F rule, made visible in the words rather than hidden.
local function tradeOffReason(candStats, eqStats, firstDiff)
	local cand = type(candStats) == "table" and candStats or {}
	local eq   = type(eqStats)   == "table" and eqStats   or {}
	local head = "trade-off: better on some stats, worse on others"
	if type(firstDiff) == "string" then
		local c, e = rawget(cand, firstDiff), rawget(eq, firstDiff)
		local cs = (c ~= nil) and tostring(c) or "absent"
		local es = (e ~= nil) and tostring(e) or "absent"
		head = head .. " (" .. firstDiff .. " " .. cs .. " vs " .. es .. ")"
	end
	return head
end

-- ---- The stat weights (card t_3a744b4a): the ONE scoring path --------------
--
-- WHY THIS EXISTS. The verdict used to be decided by DIRECTION: the dominance
-- test over the relevance set answered "better on some, worse on others" for any
-- pair with one stat up and one stat down, however lopsided. The live case
-- (Retribution paladin, Mightie):
--
--     equipped  Lambent Scale Cloak   19 Armor  +4 Str  +2 Spi
--     hovered   Barkeeper's Cloak     16 Armor  +3 Sta
--     printed   "Trade-off — better on some stats, worse on others"
--
-- -4 Str and -3 Armor for +3 Sta is not a sidegrade on a damage profile. The
-- owner's ruling: a gain in any secondary stat must never, on its own, force a
-- trade-off; weigh the difference and show the secondary as supporting detail.
--
-- WHAT DECIDES NOW. One number:
--
--     weighted = sum over every stat that DIFFERS of (delta x weight(profile, stat))
--
-- and one named noise floor, Verdict.WEIGHT_EPSILON. In order:
--
--     weighted >= +epsilon                         -> UPGRADE
--     weighted <= -epsilon                         -> NOT_UPGRADE (a downgrade)
--     |weighted| < epsilon                          -> damage is TIED, so a
--                                                     profile with ranked
--                                                     tiebreakers answers next
--     ... tied, no tiebreaker decides, mixed signs  -> TRADE_OFF
--     ... tied, no tiebreaker decides, one-way      -> NOT_UPGRADE (no change)
--
-- The tiebreaker tier (card t_c4911603) is an ORDER, not another number: the
-- profile's `tiebreak` list is walked in rank order and the first stat whose two
-- sides differ decides, so no survivability delta can ever outweigh a damage
-- point. When it decides, the verdict keeps its ordinary token and gains the
-- word "tiebreaker" plus the signed deltas — a visibly different answer from a
-- damage upgrade because the gain is not damage.
--
-- "No change" and "downgrade" are the same TOKEN — NOT_UPGRADE, the closed token
-- vocabulary is untouched — and differ only in the player WORD the renderer
-- chooses from the sign of `weighted` (ChestAdvisor.lua, TOOLTIP_UI.weighted).
--
-- THIS IS THE ONLY SCORING PATH. There is no second table, no per-item score and
-- no separate "upgrade score" function anywhere in the addon: a number printed
-- beside a verdict is this number. The documented ORDERS above keep their two
-- jobs (they word a reason, and relevanceSet seeds the tiebreak set) and no
-- longer decide anything.
--
-- THE WEIGHTS. One profile per class AND role. The values come from the stat
-- order the corpus already documents for that class/role (stat-weights §8.1):
-- the first term scores 4 points per point of stat, the second 1, the third 0.
-- A stat the order does not name — Spirit on a warrior, Armor on a damage
-- profile — scores 0, which is the whole point: a zero-weight stat is SUPPORTING
-- DETAIL. It still appears in the delta list; it can never move the verdict.
-- The two tank profiles are the exception the owner asked for explicitly: they
-- put Stamina (and Armor/Block) on top, so the SAME item pair legitimately reads
-- as an upgrade for a Protection character. That is the proof the weights drive
-- the verdict — see tests/touchstone_weights_spec.lua.
--
-- `w` is points per point of the stat. A word absent from `w` is weight 0.
--
-- TWO TIERS, RETRIBUTION ONLY (card t_c4911603). A profile may carry
-- `tiebreak = { <stat>, ... }`: an ORDERED list consulted ONLY when the damage
-- total is exactly zero. Damage stats decide first and always; a tiebreaker can
-- never outweigh one point of Strength or Agility. The entries are ranked, not
-- weighted — the first ranked stat whose two sides differ decides, so a large
-- number on a lower-ranked stat cannot outvote a higher-ranked one. This is
-- Mightie's rule, and it is what keeps the -16 cloak case a downgrade while
-- letting `+64 Armor / +2 Sta` at equal Strength read as a (flagged) upgrade.
-- The Ret table's numbers are the ones researched for WoW: Forever in card
-- t_f758a377 (vault: wiki/addons/touchstone-ret-stat-weights.md §2):
--   Strength 4, SpellPower 4 (= 1.00 x Str against a sourced 1.04 median),
--   Agility 2.5 (= 0.625 x Str for a 0.64 median), Intellect 2,
--   Armor > Stamina as ranked tiebreakers (25 Armor ~= 1 Sta of effective HP).
-- Holy and Protection keep their own rows: the same research card says their
-- numbers need separate evidence, and none of it is used here.
Verdict.WEIGHTS = {
	WARRIOR = {
		melee = { name = "Arms/Fury", w = { Strength = 4, Stamina = 1 } },
		tank  = { name = "Protection", w = { Stamina = 4, Armor = 2, Strength = 1, Block = 1 } },
	},
	PALADIN = {
		-- DAMAGER -> melee. Card t_c4911603 (research t_f758a377): the damage
		-- tier is Strength + SpellPower (the Forever sim's top Ret stat, 1.04 x
		-- Strength) + Agility (0.64 x Strength, carried as 2.5) + Intellect; the
		-- ranked tiebreakers are Armor then Stamina. Stamina and Armor appear
		-- ONLY in `tiebreak`, never in `w` — see the block above.
		melee = {
			name = "Retribution",
			w = { Strength = 4, SpellPower = 4, Agility = 2.5, Intellect = 2 },
			tiebreak = { "Armor", "Stamina" },
		},
		spell = { name = "Holy", w = { Intellect = 4, Stamina = 1 } },
		tank  = { name = "Protection", w = { Stamina = 4, Armor = 2, Intellect = 1, Strength = 1, Block = 1 } },
	},
	ROGUE = {
		melee = { name = "Combat", w = { Agility = 4, Strength = 1 } },
	},
	HUNTER = {
		melee = { name = "Hunter", w = { Agility = 4, Stamina = 1 } },
	},
	MAGE = {
		spell = { name = "Mage", w = { Intellect = 4, Spirit = 1 } },
	},
	PRIEST = {
		spell = { name = "Priest", w = { Intellect = 4, Spirit = 1 } },
	},
	WARLOCK = {
		spell = { name = "Warlock", w = { Intellect = 4, Spirit = 1 } },
	},
	-- C1b (t_03a1196c): a feral Druid has no documented order, so it also has no
	-- weights. Its rows already stop at "no stat order resolved" before the
	-- comparator, and a caller that reaches the comparator gets the unavailable
	-- verdict below — never a guessed feral model.
	DRUID = {
		spell = { name = "Balance", w = { Intellect = 4, Agility = 1 } },
	},
	SHAMAN = {
		melee = { name = "Enhancement", w = { Strength = 4, Intellect = 1 } },
		spell = { name = "Elemental", w = { Intellect = 4, Strength = 1 } },
	},
}

-- The noise floor. Weights are points per point of stat; the Ret table
-- (t_c4911603) carries the fractional 2.5, so the band must be smaller than the
-- smallest NON-zero total that table can produce. Every weight is a multiple of
-- 0.5 (4, 2.5, 2), so 0.25 sits strictly between a true zero and the smallest
-- real difference and no genuine 0.5 gain is swallowed — the reason
-- t_f758a377 pinned epsilon <= 0.25. With the old whole-point `1` a pair such as
-- +1 Agility / -1 Intellect would net 0.5 and read "no change".
-- The constant exists so the band has ONE definition that only the totals table
-- can move. The tiebreaker tier below is gated on this same band, which is safe
-- for exactly the reason above: no total these tables can produce lands inside
-- it, so "inside the band" IS a true tie.
Verdict.WEIGHT_EPSILON = 0.25

-- The client's three-word role vocabulary (TANK / HEALER / DAMAGER) to a weights
-- role key. This is NOT ROLE_ALIAS (the stat-order alias, whose conservative
-- TANK -> spell proxy for a paladin is a separate ruling): here it only picks
-- which weight table scores the row. A class absent from this table resolves
-- from its own role word alone, so a pure class is unaffected.
Verdict.PROFILE_ROLE = {
	PALADIN = { TANK = "tank", HEALER = "spell", DAMAGER = "melee" },
	WARRIOR = { TANK = "tank", DAMAGER = "melee" },
}

-- The active profile for a spec, or nil.
--
--   spec — { class = <CLASS token>, role = <melee|spell|nil>,
--            clientRole = <TANK|HEALER|DAMAGER|nil> (optional) }
--
-- Resolution order: the CLIENT's role word when this class maps it, then the
-- addon's own role word, then — for a class with exactly ONE profile — that
-- profile (a pure class ignores the role argument, exactly as classRoleOrder
-- does). A hybrid with no resolved role returns nil: no profile, no guess.
function Verdict.profileFor(spec)
	if type(spec) ~= "table" then return nil end
	local class = spec.class
	local byRole = (type(class) == "string") and Verdict.WEIGHTS[class] or nil
	if type(byRole) ~= "table" then return nil end
	local alias = (type(class) == "string") and Verdict.PROFILE_ROLE[class] or nil
	local client = type(spec.clientRole) == "string" and spec.clientRole or nil
	if client ~= nil and type(alias) == "table" then
		local word = alias[client]
		if type(word) == "string" and type(byRole[word]) == "table" then
			return byRole[word]
		end
	end
	if type(spec.role) == "string" and type(byRole[spec.role]) == "table" then
		return byRole[spec.role]
	end
	-- A PURE class ignores the role argument (exactly as classRoleOrder does) and
	-- resolves the profile keyed by its one documented order word. A HYBRID must
	-- name a role: "no role resolved" is nil here too, never a default profile —
	-- which is why a feral Druid (a documented role with no documented order, and
	-- therefore no weights) resolves to nothing instead of silently scoring as
	-- Balance.
	if not isHybrid(class) then
		local orders = Verdict.ORDERS[class]
		if type(orders) == "table" then
			for word in pairs(orders) do
				if type(byRole[word]) == "table" then return byRole[word] end
			end
		end
	end
	return nil
end

-- A signed number as the tooltip and the reason print it: "+16", "-16", "0",
-- "1.5". Only the sign is added; the value is the arithmetic itself.
function Verdict.numText(n)
	if type(n) ~= "number" then return tostring(n) end
	local text
	if n == math.floor(n) then
		text = string.format("%d", n)
	else
		text = string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", "")
	end
	if n > 0 and text:sub(1, 1) ~= "+" then text = "+" .. text end
	return text
end

-- The weighted total for one pair under one profile.
--
--   returns { total = <number>,        the verdict's number
--             parts = { { word, delta, weight, contribution }, ... },
--             scored = <n>,           differing stats with a NON-ZERO weight
--             up = <n>, down = <n> }  differing stats that rose / fell
--
-- A stat neither side carries is absent from both tables and contributes
-- nothing; a stat one side carries is a KNOWN absence (the parse zero-fills it,
-- gates 5 and 8 having already refused anything unclassifiable), so it weighs in
-- at its full delta.
function Verdict.weightedTotal(candStats, eqStats, profile)
	local weights = (type(profile) == "table") and profile.w or nil
	if type(weights) ~= "table" then return nil end
	local cand = (type(candStats) == "table") and candStats or {}
	local eq = (type(eqStats) == "table") and eqStats or {}
	local words, seen = {}, {}
	for word in pairs(cand) do
		if not seen[word] then seen[word] = true; words[#words + 1] = word end
	end
	for word in pairs(eq) do
		if not seen[word] then seen[word] = true; words[#words + 1] = word end
	end
	table.sort(words)
	local total, parts, scored, up, down = 0, {}, 0, 0, 0
	for _, word in ipairs(words) do
		local delta = (tonumber(cand[word]) or 0) - (tonumber(eq[word]) or 0)
		if delta ~= 0 then
			local weight = tonumber(weights[word]) or 0
			local contribution = delta * weight
			total = total + contribution
			parts[#parts + 1] = {
				word = word, delta = delta, weight = weight, contribution = contribution,
			}
			if weight ~= 0 then scored = scored + 1 end
			if delta > 0 then up = up + 1 else down = down + 1 end
		end
	end
	return { total = total, parts = parts, scored = scored, up = up, down = down }
end

-- The ranked tiebreakers a profile declares, or nil.
--
-- The list is ORDER, not arithmetic: entries are consulted in the order the
-- profile wrote them, and the first one whose two sides differ decides. This is
-- why a big Armor number cannot outvote a higher-ranked stat, and why the
-- profile is the only place the ranking lives (the research card ranks Armor
-- above Stamina for Ret; swapping them is a one-line change here, not a new
-- weight table).
function Verdict.tiebreakStats(profile)
	local ranked = (type(profile) == "table") and profile.tiebreak or nil
	if type(ranked) ~= "table" or #ranked == 0 then return nil end
	return ranked
end

-- The tiebreaker comparison for one pair under one profile.
--
--   returns nil when the profile declares no tiebreakers, when the parse is not
--   two tables, or when every ranked stat is equal on both sides (nothing to
--   break — the caller keeps the ordinary words);
--   otherwise { stat = <deciding word>, dir = 1|-1,
--               parts = { { word, delta }, ... },   -- NON-ZERO deltas, ranked
--               text = "+64 Armor, +2 Stamina" }    -- candidate - equipped
--
-- A stat absent on one side is a KNOWN absence and weighs in at its full delta,
-- exactly as weightedTotal treats it. The deltas are signed from the candidate's
-- side, so the printed text says which way the tie broke without a second word.
function Verdict.tiebreakTotal(candStats, eqStats, profile)
	local ranked = Verdict.tiebreakStats(profile)
	if ranked == nil then return nil end
	local cand = (type(candStats) == "table") and candStats or {}
	local eq   = (type(eqStats)   == "table") and eqStats   or {}
	local parts, deciding, dir = {}, nil, nil
	for _, word in ipairs(ranked) do
		local delta = (tonumber(cand[word]) or 0) - (tonumber(eq[word]) or 0)
		if delta ~= 0 then
			parts[#parts + 1] = { word = word, delta = delta }
			if deciding == nil then
				deciding = word
				dir = (delta > 0) and 1 or -1
			end
		end
	end
	if deciding == nil then return nil end
	local bits = {}
	for _, p in ipairs(parts) do
		bits[#bits + 1] = Verdict.numText(p.delta) .. " " .. p.word
	end
	return { stat = deciding, dir = dir, parts = parts, text = table.concat(bits, ", ") }
end

-- The stored reason: the number the verdict came from, and the profile it came
-- from, so a wrong profile is visible in the Upgrades tab and in /up diag
-- instead of silent. `kind` adds the words for the two non-obvious outcomes.
function Verdict.weightedReason(w, profile, kind, tiebreakText)
	local head = "weighted " .. Verdict.numText(w.total)
		.. " [" .. tostring(type(profile) == "table" and profile.name or "no profile") .. "]"
	if kind == "trade-off" then
		return head .. " — better on some stats, worse on others"
	elseif kind == "no change" then
		return head .. " — no change"
	elseif (kind == "tiebreaker upgrade" or kind == "tiebreaker downgrade")
		and type(tiebreakText) == "string" then
		-- Damage was tied; the flag and the ranked deltas ARE the reason. The
		-- sign of each delta says which side the tie broke for.
		return head .. " — tiebreaker (" .. tiebreakText .. ")"
	end
	return head
end

-- The verdict from the weights. Returns the same (verdict, reason) pair
-- Verdict.evaluate returns, plus a THIRD value — { total, profile } — for a row
-- that wants to render the number, or nil when the outcome did not come from
-- the weights (an unavailable profile, or the armour-material veto below, which
-- is a different reason entirely and must not be dressed as a weighted line).
-- When the ranked tiebreaker decided, that third value also carries
-- { tiebreak = "<signed deltas>", tiebreakDir = 1|-1 } so the renderer can flag
-- the answer without re-deriving it from the reason text.
--
-- `allow` is evaluate's own armour-material veto (a cloth item on a plate wearer
-- is never an upgrade, however the weights add up); a caller outside evaluate
-- passes nil and gets the raw weighted verdict.
function Verdict.weightedVerdict(candStats, eqStats, spec, allow)
	if type(allow) ~= "function" then
		allow = function(verdict, reason) return verdict, reason end
	end
	local profile = Verdict.profileFor(spec)
	if profile == nil then
		-- Requirement 5: NO WEIGHTS IS NOT A TRADE-OFF. Fall through to direction
		-- counting and the player gets an amber "your call" for a pair nothing
		-- weighed — the exact silence-with-an-answer this card removes.
		local class = type(spec) == "table" and spec.class or nil
		local role = type(spec) == "table" and spec.role or nil
		return "UNKNOWN", "verdict unavailable: no stat weights for this character (class "
			.. tostring(class or "unknown") .. ", role " .. tostring(role or "unresolved") .. ")"
	end
	local w = Verdict.weightedTotal(candStats, eqStats, profile)
	if w == nil then
		return "UNKNOWN", "verdict unavailable: the " .. tostring(profile.name)
			.. " profile carries no weights"
	end
	local detail = { total = w.total, profile = profile.name }
	local eps = Verdict.WEIGHT_EPSILON
	if w.total >= eps then
		local verdict, reason = allow("UPGRADE", Verdict.weightedReason(w, profile, "upgrade"))
		if verdict ~= "UPGRADE" then return verdict, reason end
		return verdict, reason, detail
	end
	if w.total <= -eps then
		return "NOT_UPGRADE", Verdict.weightedReason(w, profile, "downgrade"), detail
	end
	-- DAMAGE IS TIED. Only now may the profile's ranked tiebreakers speak (card
	-- t_c4911603): a profile without a `tiebreak` list — every profile but Ret —
	-- falls straight through to the words below, byte-identically to before.
	-- The tier is a flag on the answer, not a second number: the verdict is the
	-- ordinary UPGRADE / NOT_UPGRADE token and the reason says "tiebreaker", so
	-- a survivability gain can never be mistaken for damage.
	local tb = Verdict.tiebreakTotal(candStats, eqStats, profile)
	if tb ~= nil then
		local kind = (tb.dir > 0) and "tiebreaker upgrade" or "tiebreaker downgrade"
		local reason = Verdict.weightedReason(w, profile, kind, tb.text)
		detail.tiebreak = tb.text
		detail.tiebreakDir = tb.dir
		if tb.dir > 0 then
			-- The armour-material veto still applies to a tiebreaker upgrade: a
			-- cloth piece on a mail wearer is never an upgrade, however the tie
			-- broke (the same call the damage tier makes).
			local verdict, why = allow("UPGRADE", reason)
			if verdict ~= "UPGRADE" then return verdict, why end
			return verdict, why, detail
		end
		return "NOT_UPGRADE", reason, detail
	end
	if w.up > 0 and w.down > 0 then
		local verdict, reason = allow(TRADE_OFF, Verdict.weightedReason(w, profile, "trade-off"))
		if verdict ~= TRADE_OFF then return verdict, reason end
		return verdict, reason, detail
	end
	return "NOT_UPGRADE", Verdict.weightedReason(w, profile, "no change"), detail
end

-- ⚠ TEST INSTRUMENTATION ONLY, exactly like Verdict.LEGACY_ORDER_DECIDES above.
-- `true` restores the pre-card direction count so a fixture can be run through
-- both comparators in one VM and diffed. No shipped path sets it.
Verdict.LEGACY_DOMINANCE_DECIDES = false

-- The tri-state comparator.
--   candidate  — table { canUse = [nil|true|false], line = [raw lines or nil] }
--                (a bag item; an empty slot is the caller's choice to send)
--   equipped   — table { line = [raw lines or nil] }  or nil (empty slot)
--   spec       — table { order = [stat words in priority order], role = [string for display] }
--   returns    — "UPGRADE" | "NOT_UPGRADE" | "UNKNOWN", reason (string)
--
-- Hard gates, in priority order:
--   1. both sides unreadable                          -> UNKNOWN  (nothing to compare)
--   2. candidate unreadable                            -> UNKNOWN  (unreadable candidate)
--   3. client gate false  (canUse == false, explicit)  -> UNKNOWN  (armour/proficiency gate;
--                                                           PRECEDES the empty-slot shortcut)
--   4. client gate absent (canUse == nil, explicit)    -> UNKNOWN  (client could not classify)
--   5. a suppressing line (proc / unknown word / unplaceable) on the CANDIDATE
--                                                          -> UNKNOWN  (preceding BOTH the
--                                                           empty-slot shortcut and the
--                                                           armour tiebreak — AC-E13(a):
--                                                           "in both slot states")
--   6. genuinely empty slot (equipped == nil)          -> UPGRADE  (filling the slot beats
--                                                           having nothing)
--   7. equipped side present but not readable          -> UNKNOWN  (a filled slot whose
--                                                           stats we could not read is NOT an
--                                                           empty slot; no fabricated zeros)
--   8. a suppressing line on the EQUIPPED side         -> UNKNOWN  (suppression, not fabrication)
--   9. dominance over the relevance SET (t_89440dfa): dominant -> UPGRADE |
--                                                  dominated -> NOT_UPGRADE |
--                                                  trade-off -> TRADE_OFF |
--                                                  all-equal -> NOT_UPGRADE.
--      The role's stat ORDER no longer decides; it words the reason only.
--      Armor/Block keep their ruled two-sided tiebreak wording when they are
--      the only term that moved, and a one-sided term is never a 0 (AC-F).
--
-- Bare line tables (a list of strings, no "line" key) are accepted so a unit
-- can drive the comparator directly. A bare side carries no client gate, so
--  * bare line-list candidate, no canUse (comparator tests) -- the nil-canUse
--    and canUse=false gates above do not apply to it; the real scan path
--    always passes the { canUse = ..., line = ... } form for the candidate.
--   apiBySide — (card t_548f0341, OPTIONAL) { candidate = <API words|nil>,
--               worn = <API words|nil> } as resolved by Verdict.apiStats at the
--               impure edge. Purely additive: read only by parseSide's
--               reconciliation, and nil leaves every branch byte-identical.
function Verdict.evaluate(candidate, equipped, spec, apiBySide)
	local function norm(side)
		-- Returns: explicit (bool), canUse (nil|true|false), lines (nil|table)
		-- Three distinct shapes:
		--   nil                       -> no side at all
		--   { "+8 Agility", ... }      -> bare line list (comparator tests)
		--   { canUse = ..., line = L } -> wrapper; L may be nil (slot empty or
		--                                a failed tooltip read), a table, or a
		--                                string. Distinguishing the second from
		--                                the first: the first entry of a bare
		--                                list is a string, a wrapper has no
		--                                string key in it (a table or nothing).
		if side == nil or type(side) ~= "table" then return false, nil, nil end
		local line = rawget(side, "line")
		if type(line) == "table" then
			return true, rawget(side, "canUse"), line
		end
		local _, first = next(side)
		if type(first) == "string" then
			-- A real line list.
			return false, nil, side
		end
		-- A wrapper with a non-table line. nil line == "nothing to read here"
		-- (slot empty, or the tooltip read failed) -- the caller knows which;
		-- the verdict logic does not, and it must not invent zeros.
		return true, rawget(side, "canUse"), nil
	end
	local candExplicit, candCanUse, candLines = norm(candidate)
	local _, _, eqLines = norm(equipped)
	local spec_ = spec or { order = {} }
	local order = spec_.order or {}

	local function isReadable(lines)
		-- A line list is usable only if it is a NON-EMPTY table. nil, {},
		-- and "" all read as "no data" — and no-data must not be a zero.
		return type(lines) == "table" and #lines > 0
	end

	-- Parse both sides up-front. Unknown words and unplaceable lines are
	-- captured, not dropped (B2). The `side` argument (t_ea70928d): the
	-- enchant bonus folds additively into the WORN side's stats; the
	-- CANDIDATE side still drops it (unchanged AC-C behaviour). Without
	-- these labels the worn fold is unreachable dead code — the defect
	-- this card exists for.
	local api = type(apiBySide) == "table" and apiBySide or nil
	local candStats, candProc, candUnknown =
		parseSide(candLines, "candidate", api and api.candidate or nil)
	local eqStats,   eqProc,   eqUnknown   =
		parseSide(eqLines,   "worn",      api and api.worn or nil)

	-- Gate (1) — nothing on either side to compare.
	if not isReadable(candLines) and not isReadable(eqLines) then
		return "UNKNOWN", "no stats on either side to compare"
	end

	-- Gate (2) — the candidate's tooltip could not be read. We cannot claim
	--     an upgrade for an item we have not read, and a nil candidate side
	--     through the comparator would fabricate zeros. Either way: UNKNOWN.
	if not isReadable(candLines) then
		return "UNKNOWN", "the candidate's stats could not be read; cannot judge"
	end

	-- Gate (3) — hard eligibility, FAIL CLOSED (blocker A, t_b9c4291e).
	--     Only a definitive `true` from C_PlayerInfo.CanUseItem may proceed
	--     to the stat comparison. A nil, false, secret-sentinel, or any
	--     other non-boolean return reads as "eligibility unconfirmed" and
	--     returns UNKNOWN whether the chest slot is empty or filled.
	--     This single gate precedes the empty-slot shortcut and the
	--     occupied-slot comparator alike: a strictly-better candidate must
	--     not read UPGRADE on uncertain eligibility. The previous gate
	--     fired only on `== false`; the "nil does not block" note let a
	--     nil fall through to the comparator, which could read UPGRADE on
	--     an occupied slot. issecretvalue (where the client provides it)
	--     tells us whether a specific value is the client's sentinel form,
	--     so the reason can be honest rather than a guess; the `~= true`
	--     check covers nil / false / secret / non-boolean uniformly.
	--     If issecretvalue is missing (older client), we skip it and let
	--     the `~= true` branch describe the reason with the value's type
	--     — normal boolean behavior, no false secret claim.
	if candExplicit and candCanUse ~= true then
		local detail
		if type(issecretvalue) == "function" and issecretvalue(candCanUse) then
			detail = "client returned the secret-value sentinel"
		elseif candCanUse == nil then
			detail = "client returned nil (Could Not Classify)"
		elseif candCanUse == false then
			detail = "client returned false (this character cannot use this item)"
		else
			detail = "client returned a non-boolean value of type " .. type(candCanUse)
		end
		return "UNKNOWN", "eligibility unconfirmed (fail-closed): " .. detail
			.. " — the client did not affirmatively confirm this character can use this item"
	end

	-- Gate (5) — a suppressing line on the CANDIDATE: a proc line
	--     ("Equip: +5 Crit"), an out-of-vocabulary word ("Haste"), or a
	--     line the parser could not place at all ("+15 Frost Resistance").
	--     Runs BEFORE the empty-slot shortcut (gate 6) — AC-E13(a): the
	--     suppress must win "in both slot states" — and before the armour
	--     tiebreak (gate 9), so a strictly-higher-armour item carrying an
	--     unclassifiable line can never read UPGRADE off the armour term.
	--     (The §4.1a placement ruling: armour is reachable only on the
	--     comparator's `equal` fall-through, after every suppression gate.)
	if candProc ~= nil or candUnknown ~= nil then
		local which = candProc or candUnknown
		return "UNKNOWN", "cannot classify: " .. which
	end

	-- Gate (6) — genuinely empty slot (the caller sent nil).
	--     Only reachable when candCanUse == true (gate 3 above already
	--     failed every other case) and the candidate carries no suppress
	--     (gate 5 above).
	-- Lower armor is never an upgrade and never a trade-off. Unknown lines have
	-- already returned, so this does not hide a stat we failed to read.
	local function allow(verdict, reason)
		if verdict ~= "UPGRADE" and verdict ~= TRADE_OFF then
			return verdict, reason
		end
		local blocked, why = Verdict.lowerArmorReason(candLines, spec_)
		if blocked then return "NOT_UPGRADE", why end
		return verdict, reason
	end

	if eqLines == nil and candExplicit and candCanUse == true then
		return allow("UPGRADE", "no chest equipped; this item would fill the slot")
	end

	-- Gate (7) — a slot FILLED by an item whose stats we could not read.
	--     Not an empty slot: the shortcut above is long past, and a strictly
	--     weaker candidate must not read as UPGRADE against the fabricated
	--     zeros a failed read would give. (Vera defect 4: a missing read is
	--     not a zero.) A line list that is empty, or that yielded no stat
	--     word and no unrecognised word either, is the "un-readable" state —
	--     and so is one whose non-blank lines could not be classified at all
	--     (B2: they suppress rather than silently reading as zero).
	if next(eqStats) == nil and eqProc == nil and eqUnknown == nil then
		return "UNKNOWN", "the equipped item's stats could not be read; cannot judge"
	end

	-- Gate (8) — a suppressing line on the EQUIPPED side: the same proc /
	--     unknown-word / unplaceable shapes as gate 5, on the worn item.
	--     Suppression, not fabrication — an unknown line on either side is
	--     UNKNOWN (unchanged from the old combined Gate 7).
	if eqProc ~= nil or eqUnknown ~= nil then
		local which = eqProc or eqUnknown
		return "UNKNOWN", "cannot classify: " .. which
	end

	-- Gate (9) — the verdict.
	--
	-- Tank path (card t_89440dfa): the ORDER no longer decides. The verdict comes
	-- from the three-outcome dominance test (Verdict.dominance) over the
	-- relevance SET (Verdict.relevanceSet) — the order's own words plus Armor and
	-- Block. The order is then used ONLY to word the reason, via the first term
	-- on which the two sides differ (dominance's second return).
	--
	--   dominant  -> UPGRADE              (>= everywhere, > somewhere; green arrow)
	--   trade-off -> TRADE_OFF            (its own non-green mark + deltas)
	--   dominated -> NOT_UPGRADE          (no mark)
	--   equal     -> NOT_UPGRADE          (unchanged "equal" fall-through)
	--
	-- ⚠ THE LEGACY SWITCH (Verdict.LEGACY_ORDER_DECIDES): `true` restores HEAD's
	-- exact behaviour, byte-for-byte, so the AC-C/AC-D harness can run every
	-- fixture through both comparators in ONE VM and diff the outcomes. It is
	-- read here and nowhere else; no shipped path sets it.
	if Verdict.LEGACY_ORDER_DECIDES then
		local result = orderedCompare(candStats, eqStats, order)
		if result == "wins" then
			for _, word in ipairs(order) do
				if (candStats[word] or 0) > (eqStats[word] or 0) then
					return "UPGRADE", winReason(word)
				end
			end
			return "UPGRADE", winReason()
		end
		if result == "loses" then
			for _, word in ipairs(order) do
				if (candStats[word] or 0) < (eqStats[word] or 0) then
					return "NOT_UPGRADE", "worse on " .. word .. " than what's equipped"
				end
			end
			return "NOT_UPGRADE", "not better than what's equipped"
		end
		-- The E2 armour tiebreak (legacy path).
		local cArmor = rawget(candStats, "Armor")
		local eArmor = rawget(eqStats, "Armor")
		if cArmor ~= nil and eArmor ~= nil and cArmor ~= eArmor then
			if cArmor > eArmor then
				return "UPGRADE", "upgrade: more Armor (" .. cArmor .. " vs "
					.. eArmor .. ") on an otherwise equal item"
			end
			return "NOT_UPGRADE", "less Armor (" .. cArmor .. " vs "
				.. eArmor .. ") on an otherwise equal item"
		end
		local cBlock = rawget(candStats, "Block")
		local eBlock = rawget(eqStats, "Block")
		if cBlock ~= nil and eBlock ~= nil and cBlock ~= eBlock then
			if cBlock > eBlock then
				return "UPGRADE", "upgrade: more Block (" .. cBlock .. " vs "
					.. eBlock .. ") on an otherwise equal item"
			end
			return "NOT_UPGRADE", "less Block (" .. cBlock .. " vs "
				.. eBlock .. ") on an otherwise equal item"
		end
		return "NOT_UPGRADE", "equal to what's equipped — not a strict improvement"
	end

-- ⚠ THE WEIGHTED VERDICT (card t_3a744b4a). This is the shipped decision:
-- the profile's weighted total, in the threshold order the card spells out. The
-- number (and the profile's own name) travel back to the caller as the third
-- return value so a rendered line can quote them.
--
-- The direction count below is reachable ONLY through LEGACY_DOMINANCE_DECIDES,
-- which is test instrumentation (it exists so a fixture can be run through both
-- comparators in one VM and diffed). It is read here, so the switch really does
-- switch: with it set, the weighted path is skipped and the old block runs.
if not Verdict.LEGACY_DOMINANCE_DECIDES then
	local v, r, d = Verdict.weightedVerdict(candStats, eqStats, spec_, allow)
	if v ~= nil then return v, r, d end
end

if Verdict.LEGACY_DOMINANCE_DECIDES then
	local outcome, firstDiff = Verdict.dominance(candStats, eqStats, order)

	if outcome == "dominant" then
		-- Word the win with the SAME grammar the legacy path used: the first
		-- term of the role's own order on which the candidate is strictly
		-- better. (Every role term is two-sided in this branch, so `or 0` is
		-- only reachable for a term absent on BOTH sides, which is 0 vs 0.)
		for _, word in ipairs(order) do
			if (candStats[word] or 0) > (eqStats[word] or 0) then
				return allow("UPGRADE", winReason(word))
			end
		end
		return allow("UPGRADE", winReason())
	end

	if outcome == "dominated" then
		for _, word in ipairs(order) do
			if (candStats[word] or 0) < (eqStats[word] or 0) then
				return "NOT_UPGRADE", "worse on " .. word .. " than what's equipped"
			end
		end
		return "NOT_UPGRADE", "not better than what's equipped"
	end

	if outcome == "trade-off" then
		return allow(TRADE_OFF, tradeOffReason(candStats, eqStats, firstDiff))
	end

	-- outcome == nil: the role's own terms are all EQUAL (or absent on both
	-- sides). Only now are the two UNIVERSAL terms consulted — in their set
	-- order, Armor first then Block — exactly as E2 (t_8bc7d7f2, §4.1a) and
	-- Tier B (t_73e20edb) ruled: "Armor and Block break a remaining tie, and
	-- only that" (the Tier B/AC-E comment, verbatim).
	--
	-- ⚠ WHY Armor/Block are members of the relevance SET (relevanceSet, above:
	-- unconditional per RULING (b)) but NOT terms of the dominance proof:
	--   * E2 ruled "armour is never a win, only a tiebreak" and graded
	--     AC-E13(b) "armour never overturns a class-order loss — worse primary
	--     + higher armor is NOT_UPGRADE". If Armor sat inside the proof, that
	--     pair would read TRADE_OFF and overturn the loss. Mira: "E2 … stands".
	--   * Their semantics are a two-sided value comparison, absence NEUTRAL
	--     (never a fabricated 0), a literal 0 a VALUE. rawget keeps absence
	--     distinguishable from zero (AC-E13(c)/(d)).
	-- The universal terms are read from the SAME relevanceSet the set is built
	-- from, so the tiebreak order (Armor, Block) has one definition. Iterating
	-- it after the order's own words have already been proven equal (outcome
	-- == nil) reaches exactly the Armor/Block tail.
	for _, word in ipairs(Verdict.relevanceSet(order)) do
		local c = rawget(candStats, word)
		local e = rawget(eqStats, word)
		if c ~= nil and e ~= nil and c ~= e then
			if c > e then
				return allow("UPGRADE", "upgrade: more " .. word .. " (" .. c .. " vs "
					.. e .. ") on an otherwise equal item")
			end
			return "NOT_UPGRADE", "less " .. word .. " (" .. c .. " vs "
				.. e .. ") on an otherwise equal item"
		end
	end
	return "NOT_UPGRADE", "equal to what's equipped — not a strict improvement"
	end
end

-- ---- Tier B (t_73e20edb): the off-hand slot ----------------------------------
--
-- The off-hand slot is special: a shield, a held-in-off-hand item and an
-- off-hand weapon are three different things that share one wear slot. The
-- client itself groups them (Lena §2: `isEquippedInOffhand` = SHIELD |
-- WEAPONOFFHAND | HOLDABLE), so the ONLY comparison this addon ever allows in
-- slot 17 is LIKE-FOR-LIKE — candidate and worn item in the same off-hand
-- class. Every other case declines with a named reason. The failure mode of
-- this policy is SILENCE, and silence is a correct answer: a protection
-- warrior must never see an arrow in front of a non-shield.
--
-- This whole section is data + one pure function: no client call, no order
-- lookup, no UI. The caller supplies the tokens it read from
-- C_Item.GetItemInfoInstant and the spec it resolved; a nil (unresolved) spec
-- is itself a decline (§3 fail-closed). That keeps every branch drivable from
-- a unit test on a clean VM.

-- §2 OFF_HAND class — the only tokens Tier B may judge, and the only worn
-- items it may compare against.
Verdict.OFF_HAND_TOKENS = {
	["INVTYPE_SHIELD"]       = true,
	["INVTYPE_WEAPONOFFHAND"] = true,
	["INVTYPE_HOLDABLE"]      = true,
}

-- §2 TWO_HAND class — never an off-hand candidate; a worn MAIN HAND item in
-- this class closes slot 17 (G0), because a two-hander means slot 17 reads nil
-- and a nil worn item is NOT an empty slot.
Verdict.TWO_HAND_TOKENS = {
	["INVTYPE_2HWEAPON"]    = true,
	["INVTYPE_RANGED"]      = true,
	["INVTYPE_RANGEDRIGHT"] = true,
	["INVTYPE_THROWN"]      = true,
}

-- §2 OFF-HAND CLOSING class (card t_e6103123, defect B1) — the tokens that
-- close slot 17 *when worn in the MAIN HAND*, and ONLY those.
--
-- WHY THIS SET EXISTS AS WELL AS THE ONE ABOVE. `TWO_HAND_TOKENS` answers a
-- DIFFERENT question from the one Tier C's `weaponGate` asked it: "does a worn
-- main-hand item in this class leave slot 17 structurally closed?" — the G0
-- test at `offHandGate`. On this client a bow, gun, crossbow or thrown weapon
-- worn in the MAIN HAND genuinely does preclude a normal off-hand (G0's ruling,
-- unchanged), which is why the four-token set above is right for G0.
--
-- But a ranged weapon as a CANDIDATE lands in slot 18, and slot 18 never
-- displaces slot 17. `weaponGate` had reused `TWO_HAND_TOKENS` for that
-- candidate test, so every bow/gun/crossbow/thrown candidate against a
-- character with anything in the off-hand was refused with W0 — "a two-handed
-- weapon takes your off-hand" — a reason that is not true of the item. The live
-- capture `70/Phat-Angus/SavedVariables/Touchstone.lua` is exactly that row:
-- item:3742 [Bow of Plunder], slot 18, W0.
--
-- The two sets therefore differ by design and must not be collapsed:
--   * `TWO_HAND_TOKENS`      — G0's worn-main-hand question. FOUR tokens.
--   * `OFFHAND_CLOSING_TOKENS` — Tier C's candidate question. ONE token.
-- Narrowing `TWO_HAND_TOKENS` in place would silently reopen G0 for a bow/gun/
-- thrown worn in the main hand — a ruled behaviour. Both directions are pinned
-- by permanent tests (card t_e6103123 AC-B and AC-D).
Verdict.OFFHAND_CLOSING_TOKENS = {
	["INVTYPE_2HWEAPON"] = true,
}

-- Tier C (t_b058b5df, RULED 2026-10-04) — the WEAPON family the scan now judges
-- on tooltip-read DPS. The DPS path handles the MAIN-HAND and RANGED weapons:
-- the one-handers worn in the main hand, the two-handers, and the ranged family.
--
-- The reference's own `weaponEquipLocations` (ForeverGear Weapon.lua:7-10) lists
-- seven tokens and includes INVTYPE_WEAPONOFFHAND. That one is deliberately NOT
-- here: Tier B already owns worn slot 17 and its like-for-like guarantee, and the
-- card's AC-D is explicit that off-hand interactions follow the Tier B policy
-- "rather than inventing a second policy". An off-hand weapon is therefore still
-- judged on Tier B's path (and Tier B's own G6 already says the off hand holds a
-- WEAPON — Tier C's slot). The six tokens below are the ones that leave perSkip.
--
-- The `worn` slot each one answers to is the client's own constants
-- (Blizzard_FrameXMLBase/Constants.lua:151-153): main hand 16, ranged 18
-- (INVSLOT_RANGED). INVTYPE_WEAPON is positional (Lena §2) — the client resolves
-- it by the slot it is WORN in; as a bag candidate the reference's `forceMainhand`
-- (ProfileRules.lua:313-316) is the shape we follow: a generic one-hander is
-- evaluated as a MAIN-HAND item, never as a shield/frill replacement.
Verdict.WEAPON_TOKENS = {
	["INVTYPE_WEAPON"]         = true,  -- positional; evaluated as main-hand
	["INVTYPE_2HWEAPON"]       = true,
	["INVTYPE_WEAPONMAINHAND"] = true,
	["INVTYPE_RANGED"]         = true,
	["INVTYPE_RANGEDRIGHT"]    = true,
	["INVTYPE_THROWN"]         = true,
}
-- (The token -> worn-slot mapping (16 main hand / 18 ranged) lives in exactly
-- one place: ChestAdvisor.lua's EQUIP_SLOTS, which the walk already consults to
-- compute the row's invSlot. A second copy here would be a second source of
-- truth for the same client constants, so there is deliberately none.)

-- Shield-capable classes, as our own statement of the era ruleset (Lena §3:
-- there is NO proficiency API on this client — `canUseShields` / `UseShields` /
-- `shieldProficiency` are 0 hits in the pinned tree, re-confirmed independently).
-- This table, not a client call, is what G1 reads: a shield candidate on a
-- class absent from it is declined with the §5 G1 reason, by name, before the
-- eligibility gate is ever consulted. Classes absent from it (Hunter, Rogue,
-- Mage, Priest, Warlock, Druid) cannot wear a shield in this era.
--
-- NOTE the separation of concerns (§2/§4): this table answers "can this class
-- wear a shield". It does NOT answer "is a shield this spec's business" — that
-- is OFF_HAND_BUCKETS below, and the two are deliberately independent so the
-- class gate can never silently stand in for the policy.
Verdict.SHIELD_CLASSES = {
	WARRIOR = true,
	PALADIN = true,
	SHAMAN  = true,
}

-- The reason strings of §5. Ours, newly written — not translations of the
-- reference addon's localised ones (Lena §9). Every decline the gate can return
-- is named here: if a decline has no string, it cannot be audited.
local REASON = {
	G0 = "not judged: a two-handed weapon occupies both hands",
	G1 = "not judged: this character cannot use shields",
	G2 = "not judged: the off hand is out of scope for this spec",
	G3 = "not judged: no specialization resolved",
	G4 = "not judged: shield, off-hand weapon and held-in-off-hand are not comparable",
	G5 = "not judged: not an off-hand item",
	G6 = "not judged: the off hand holds a weapon",
	-- Tier C (t_b058b5df): the weapon family's own declines. The scoping doc's
	-- slice-1 table (t_97a8ea03 §5.1) rules a two-hander against an occupied
	-- off-hand UNKNOWN; the shield-mandated shape is the reference's own
	-- `profileRequiresShield` block (ForeverGear ProfileRules.lua:313-316).
	-- Both are named here so the ledger can say which rule fired.
	W0 = "not judged: a two-handed weapon takes your off-hand",
	W1 = "not judged: this spec is built around a shield; a two-hander cannot be worn",
}
Verdict.REASON = REASON

-- §4 per-spec shield classification, keyed CLASS token + role. Values:
--   "required"    — the spec is built around 1H + shield; a shield is mandated.
--                   A holdable / off-hand weapon into this spec's slot is
--                   declined by the class rule (G4).
--   "allowed"     — a shield is viable but not mandated. Same off-hand class on
--                   both sides -> judged normally.
--   "irrelevant"  — the spec has no business in this slot at all (the rogue's
--                   off hand holds an off-hand *weapon*; the hunter has no
--                   off-hand item in this era). All three off-hand tokens are
--                   declined with the §5 G2 reason.
--
-- `role` is the client's own TANK/HEALER/DAMAGER word (Lena §3). Where a class
-- had two specs of the SAME role (Lena's §4 note about Warrior and Paladin) the
-- disambiguation would need the spec NAME; on this client's three role words
-- that collision is only Warrior Arms-vs-Fury, and BOTH of those land in the
-- same `allowed` bucket, so no name is needed for either. `contested` is a
-- MARKER (the corpus is uncertain about that row) and is deliberately NOT a
-- decline: it is recorded in the diag record so a reader can see which rows
-- rest on our own ruleset statement rather than on a source.
--
-- ROLES. A class with a single row for every role is spelled `roles = { ... }`
-- and answers for any of the three role words; this is what makes the table
-- class-independent, so G2 has an answer for a resolved rogue/hunter and §4's
-- `allowed` rows exist for mage/priest/warlock/druid. An entry that requires a
-- specific role (WARRIOR/PALADIN) is keyed by role directly and answers only
-- that word — the same class at another role has no bucket and is G3.
--
-- SAME-ROLE COLLISION (§3). One class has two specs sharing a role word: a
-- warrior's Arms (irrelevant — a two-hand commitment) and Fury (allowed —
-- shield + one-hander is legal) are both `DAMAGER`, and the role word alone
-- cannot tell them apart. §3 rules that the spec NAME is the disambiguator, and
-- that when it is unavailable the slot is OUT OF SCOPE (fail-closed), never a
-- default bucket. That is `byName` below; an unresolvable name returns nil,
-- which the caller turns into G3's silence.
Verdict.OFF_HAND_BUCKETS = {
	WARRIOR = {
		-- Protection is the era's only warrior TANK spec, so the role word
		-- alone identifies it: no name lookup, no guess.
		TANK    = { shield = "required" },
		-- §4: Arms = irrelevant (two-hand commitment; the off hand is not a
		-- free slot), Fury = allowed (legal, never required). Keyed by the
		-- spec name because the role word is identical for both.
		DAMAGER = { byName = { arms = "irrelevant", fury = "allowed" } },
	},
	PALADIN = {
		TANK    = { shield = "required" },  -- Protection
		HEALER  = { shield = "allowed", contested = true },  -- Holy (contested in corpus; settled to allowed, §4.2)
		-- §4: retribution is a two-hand commitment, exactly like warrior Arms.
		-- The role word is unambiguous here (ret is the only paladin DAMAGER
		-- spec), so no name lookup is needed.
		DAMAGER = { shield = "irrelevant" },
	},
	SHAMAN = {
		-- Lena §4: the shaman row is CONTESTED in our corpus. Marked, not
		-- hidden. A shield is a legitimate off-hand for every shaman role,
		-- so this is `allowed` for all three and the marker never changes a
		-- verdict; `roles` covers all three words at once.
		roles = { shield = "allowed", contested = true },
	},
	-- §4 rows 134-137, the classes with NO shield story of their own. These are
	-- NOT absences: §4 assigns them a bucket, and G2 is what expresses it.
	-- `allowed — holdables only` means an off-hand frill is legal and judged
	-- like-for-like (a shield is refused separately by G1).
	MAGE    = { roles = { shield = "allowed" } },   -- off-hand frills legal; shields refused by G1
	PRIEST  = { roles = { shield = "allowed" } },
	WARLOCK = { roles = { shield = "allowed" } },
	DRUID   = { roles = { shield = "allowed" } },   -- cannot wear a shield at all (G1)
	-- `irrelevant` — the off hand is out of scope for these two specs entirely.
	ROGUE   = { roles = { shield = "irrelevant" } },  -- the off hand holds an off-hand weapon: Tier C's slot
	HUNTER  = { roles = { shield = "irrelevant" } },  -- no off-hand item in this era
	-- Everything else (a class token we do not know) is genuinely absent ->
	-- no bucket -> G3, which is the correct reason for an unresolved identity.
}

-- ---- Defect 1 (card t_548f0341): is this spec read a REAL specialization? ----
--
-- The client's C_SpecializationInfo returns, for a character with no
-- specialization yet (the owner's level-22 paladin, verbatim probe):
--     idx=1  name=Paladin  ROLE=DAMAGER
-- i.e. the spec NAME is the CLASS's own display name and the role is the
-- class's default. That is not a specialization, and treating it as one is the
-- defect: it resolved `PALADIN/DAMAGER = irrelevant` and refused the owner's
-- shield. This predicate is what tells the two apart.
--
-- UNSUBSTANTIATED when the returned name equals the player's own class display
-- name (case-insensitive, trimmed), or when the name is absent or empty.
-- SUBSTANTIATED otherwise — the client returned a real spec name.
--
-- The comparison is against UnitClass("player")'s LOCALIZED first return, passed
-- in by the caller (`classDisplay`), because the name the client hands back is
-- localized too. No English spec name is hardcoded here: a spec named
-- "Retribution" does not equal "Paladin" and is substantiated on every locale.
--
-- A spec whose name is a DIFFERENT real name ("Protection", "Arms", "Fury",
-- "Holy") is substantiated everywhere, including where those words are
-- untranslated from English.
function Verdict.substantiated(spec)
	if type(spec) ~= "table" then return false end
	local name = spec.name
	if type(name) ~= "string" then return false end
	name = name:gsub("^%s+", ""):gsub("%s+$", ""):lower()
	if name == "" then return false end
	local cls = spec.classDisplay
	if type(cls) ~= "string" then
		-- With no class display name to compare against we cannot tell a
		-- class-as-spec read from a real one. Fail closed: treat it as a real
		-- spec name, which keeps today's behaviour (the safe direction — it
		-- cannot newly widen what is judged).
		return true
	end
	cls = cls:gsub("^%s+", ""):gsub("%s+$", ""):lower()
	if cls == "" then return true end
	return name ~= cls
end

-- The spec's shield classification, as one lookup shared by the gate and the
-- diag record (Lena §6: the bucket survives as (a) the reason string and (b) the
-- diag record). Returns "required" | "allowed" | "irrelevant" | nil, where nil
-- means "the policy could not be resolved for this character" (an unknown
-- class, a role word we do not cover, no readable role, or a same-role collision
-- whose name we could not disambiguate) — the caller turns that into G3.
--
-- The classification is CLASS-INDEPENDENT on purpose (jia-clean's build note #2,
-- policy §7): it consults the table and nothing else — no SHIELD_CLASSES, no
-- client API — so a wrong or missing class table cannot change what G4 and G2
-- do. `shield` is a class capability, `bucket` is a spec policy; they are
-- deliberately independent answers.
function Verdict.shieldPolicy(spec)
	if type(spec) ~= "table" then return nil end
	local token, role = spec.class, spec.role
	if type(token) ~= "string" or type(role) ~= "string" then return nil end
	local entry = Verdict.OFF_HAND_BUCKETS[token]
	if type(entry) ~= "table" then return nil end
	local bucket = entry[role] or entry.roles

	-- ---- Defect 1 (card t_548f0341): a CLASS-AS-SPEC read is not authoritative
	--
	-- At level 22 the owner's paladin has no specialization, so the client
	-- returns the CLASS as the spec name and the class's default role:
	--     idx=1  name=Paladin  ROLE=DAMAGER
	-- Read literally that DAMAGER resolves the PALADIN/DAMAGER bucket
	-- (`shield = "irrelevant"`), and a levelling paladin can then never get a
	-- shield judged — the live defect. An unsubstantiated identity is not a
	-- specialization, so its spec-specific row is not authoritative: the policy
	-- falls back to the CLASS level, where a shield-capable class is `allowed`
	-- (Verdict.shieldCapable — the same class answer G1 uses; no second table).
	--
	-- A SUBSTANTIATED read keeps today's behaviour exactly, including §4's
	-- `DAMAGER = irrelevant` ruling for a real Retribution paladin and the §3
	-- Arms/Fury byName collision (which needs a real name to disambiguate).
	local unsubstantiated = not Verdict.substantiated(spec)
	if unsubstantiated then
		-- A malformed role word is still no role at all -> nil -> G3. The
		-- fallback answers for the three words the CLIENT speaks, nothing else.
		if not CLIENT_ROLES[role] then return nil end
		-- The CLASS-level row when the table carries one (§4 gives MAGE /
		-- PRIEST / WARLOCK / DRUID / SHAMAN / ROGUE / HUNTER a `roles` row that
		-- answers for all three role words). Those rows are class-level already,
		-- so they ARE the fallback — consulting them first is what keeps a
		-- mage's holdable `allowed` and a rogue's off hand `irrelevant` exactly
		-- as before.
		local classRow = entry.roles
		if type(classRow) == "table" then return classRow.shield end
		-- WARRIOR / PALADIN key their rows by role and have no class-level row.
		-- Their spec-specific rows are the ones this card rules not authoritative
		-- for an unsubstantiated read, so the answer comes from the CLASS
		-- CAPABILITY: a class that can wear a shield is `allowed`.
		if Verdict.shieldCapable(spec) then return "allowed" end
		-- The class cannot wear a shield at all; a shield candidate is already
		-- G1 and every other off-hand class is out of scope for a class with no
		-- spec (the rogue's held weapon, the hunter's absent off-hand item).
		return "irrelevant"
	end

	if type(bucket) ~= "table" then return nil end
	-- The one same-role collision (§3): a warrior DAMAGER is either Arms or
	-- Fury, and only the spec name separates them. The name is the client's
	-- own localized string, so it is matched case-insensitively as a substring
	-- ("Arms" inside "Arms Warrior", etc.) — never translated or guessed at.
	-- No name -> nil -> G3 silence, the §3 fail-closed rule.
	if bucket.byName then
		local name = type(spec.name) == "string" and spec.name:lower() or nil
		if name == nil then return nil end
		for needle, cls in pairs(bucket.byName) do
			if name:find(needle, 1, true) then return cls end
		end
		return nil
	end
	return bucket.shield
end

-- Can this class equip a shield at all? A CLASS capability, not a spec policy.
-- Absent from SHIELD_CLASSES -> false -> G1. This is a separate question from
-- shieldPolicy (which answers what the SPEC should be told), and the gate below
-- asks both, in the §5 order.
function Verdict.shieldCapable(spec)
	if type(spec) ~= "table" or type(spec.class) ~= "string" then return false end
	return Verdict.SHIELD_CLASSES[spec.class] == true
end

-- The off-hand gate. Pure: every input is an argument, nothing is read from
-- the environment. Returns nil (judge this row normally) or a decline reason
-- string (the row is UNKNOWN with that reason, no marker, no tip).
--
--   candLoc  — the CANDIDATE's equip-location token (INVTYPE_*, or nil)
--   wornLoc  — the WORN slot-17 item's equip-location token (or nil: empty)
--   mainLoc  — the WORN main-hand (slot 16) item's token (or nil)
--   spec     — { class = token, role = "TANK"|"HEALER"|"DAMAGER"|nil,
--                name = the spec name or nil } — nil means "not resolved"
--
-- Order is the §5 table's, top to bottom: G0 (structural, the slot is closed)
-- -> G5/G6 (not an off-hand candidate — token rules, no spec needed) -> G1 (the
-- class cannot wear a shield) -> G3 (no spec could be resolved) -> G4 (the two
-- sides are different off-hand classes) -> G2 (the spec says the slot is out of
-- scope) -> the required-shield declines -> nil.
--
-- Two properties are load-bearing and must survive any future edit:
--   * G4 (§7) fires on TOKEN INEQUALITY ALONE. It consults neither the spec
--     bucket nor any client API, and it is deliberately NOT gated behind the
--     class-capability check: the guarantee "the off-hand slot never receives
--     UPGRADE against a worn item of a different off-hand class" holds for the
--     mage and the rogue exactly as it holds for the warrior (jia-clean's build
--     note #2). A wrong bucket or a missing class table cannot weaken it.
--   * Every decline returns a NAMED string from REASON, so the diag ledger can
--     say which rule fired. A decline with no name is not auditable.
function Verdict.offHandGate(candLoc, wornLoc, mainLoc, spec)
	if type(candLoc) ~= "string" then return nil end
	if not Verdict.OFF_HAND_TOKENS[candLoc] then
		-- Not an off-hand candidate at all (a two-hander, a ranged weapon,
		-- armour, trade goods): not this function's business. The caller's own
		-- scope split decides. The two exceptions are the weapon-shaped tokens
		-- the §5 table DOES name:
		--   G5 — statically main-hand-only.
		--   G6 — positionally undetermined: a one-hander worn in the off hand
		--        is a WEAPON, which is Tier C's slot, not a shield replacement.
		if candLoc == "INVTYPE_WEAPONMAINHAND" then return REASON.G5 end
		if candLoc == "INVTYPE_WEAPON" then return REASON.G6 end
		return nil
	end

	-- G0 — the worn MAIN HAND holds a two-hander: slot 17 is structurally
	-- closed. Checked before the spec gate so the reason is structural.
	if type(mainLoc) == "string" and Verdict.TWO_HAND_TOKENS[mainLoc] then
		return REASON.G0
	end

	-- G1 — the candidate is a shield and this class cannot equip one in this
	-- era (Lena §3: there is no proficiency API to ask, so the class table IS
	-- the answer). Named here rather than left to the eligibility gate, so the
	-- ledger records WHY the shield was declined instead of relying on an
	-- untested CanUseItem to suppress it silently.
	--
	-- The guard on a readable class token matters: G1 asserts something about
	-- the CLASS, so with no class to read we know nothing and must fall through
	-- to G3's silence (§3 fail-closed), not name a reason we cannot justify.
	-- In production `class` always comes from UnitClass and survives a failed
	-- spec read, so this only excludes the wholly-unresolved shape.
	if candLoc == "INVTYPE_SHIELD" and type(spec) == "table"
		and type(spec.class) == "string"
		and not Verdict.shieldCapable(spec) then
		return REASON.G1
	end

	-- G3 — the spec gate. The bucket key is class token + role word, and BOTH
	-- must be present: a nil spec (the client read failed — Lena §3 fail-closed)
	-- or a missing role word declines. Never a default bucket.
	local bucket = Verdict.shieldPolicy(spec)
	if bucket == nil then return REASON.G3 end

	-- G2 — the spec says the off hand is out of scope for it (the rogue's off
	-- hand holds an off-hand *weapon*; the hunter has no off-hand item in this
	-- era). Design §5 puts G2 ahead of G4, and that ordering is the honest one:
	-- for a rogue the slot is a weapon slot, so "out of scope for this spec" is
	-- a more accurate answer than "these two off-hand classes are incomparable",
	-- even when the worn slot happens to be filled. The §7 no-UPGRADE guarantee
	-- is satisfied either way — G2 declines unconditionally.
	if bucket == "irrelevant" then return REASON.G2 end

	-- G4 — worn slot 17 is FILLED with an item of a different off-hand class
	-- than the candidate. THE GUARANTEE (§7). Token inequality alone; no
	-- bucket, no API, no class table. Note the order: this runs BEFORE the
	-- bucket-specific required-shield rule below and is NOT gated behind the
	-- class-capability check, so it fires for every class — a mage's worn
	-- off-hand weapon against a bag holdable is declined the same way a
	-- warrior's worn shield against a bag holdable is.
	if type(wornLoc) == "string" and Verdict.OFF_HAND_TOKENS[wornLoc]
		and wornLoc ~= candLoc then
		return REASON.G4
	end

	-- G6 (second half) — the worn slot 17 holds a positional one-hander: the
	-- client resolved it as an off-hand weapon, which is Tier C's slot, not a
	-- shield replacement.
	if type(wornLoc) == "string" and wornLoc == "INVTYPE_WEAPON" then
		return REASON.G6
	end

	-- The required-shield declines. Only meaningful when a shield is MANDATED:
	-- then a candidate that is not a shield — the holdable or the off-hand
	-- weapon (a two-hander is already G0/G5 above) — is declined with the same
	-- §5 G4 string, because the player's own words for it are the three-way
	-- incomparability, not a fourth invented sentence. This is what stops a
	-- protection warrior being told to drop his shield for a +Strength frill
	-- into an EMPTY off-hand slot (the generic "slot is empty, so this fills it"
	-- UPGRADE would otherwise fire).
	if bucket == "required" then
		if candLoc == "INVTYPE_HOLDABLE" or candLoc == "INVTYPE_WEAPONOFFHAND" then
			return REASON.G4
		end
	end

	return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Tier C (t_b058b5df) — WEAPONS, judged on tooltip-read DPS.
--
-- RULED (2026-10-04): "Read the numbers. Order by prose. No stat weight
-- anywhere." The damage range, the speed and the DPS are values the CLIENT
-- PRINTS on the item's own tooltip — read them, do the arithmetic the client
-- already shows, and compare. No per-stat multiplier is used, invented,
-- hard-coded or imported (AC-G). The one place a class-specific rule appears
-- is W1, and it is a boolean MANDATE (this spec is built around a shield), not
-- a weight.
--
-- Why a weapon needs its own reader (AC-B): the armour/stat comparator reads
-- lines shaped `+12 Agility`. A weapon's tooltip carries three shapes the
-- existing parser cannot see, all confirmed on the sister project
-- (statforge-app/src/lib/itemParser.ts:388) and the reference's own reader
-- (ForeverGear Weapon.lua:125-206):
--     "1 - 3 Damage"            the damage RANGE
--     "Speed 1.90"              the decimal SPEED
--     "(1.05 damage per second)" the parenthesised DPS
-- and the dashes come in three characters (- – —). `Verdict.lua:174`'s
-- integers-only pattern (`^%s*[%+%-%s]*(%d+)%s+(%a+)$`) matches none of them.
-- ═══════════════════════════════════════════════════════════════════════════

-- A secret value must never be read, compared, or arithmetic'd on (the
-- addon-disarmament regime; Forever inherits secrets and an operation on one
-- RAISES). This is the exact guard the card asks to be named (evidence item 6)
-- and the shape the project already uses (Verdict.lua:617, and the reference's
-- `safeIsSecret`, ForeverGear Weapon.lua:11-18): pcall the client predicate,
-- and treat "it raised" or "no predicate" as NOT secret so an older client
-- still works. Kept local to the weapon reader — it is the only place here
-- that touches a freshly-parsed number.
local function isSecretValue(v)
	if type(issecretvalue) == "function" then
		local ok, r = pcall(issecretvalue, v)
		if ok and r then return true end
	end
	return false
end

-- Parse one tooltip line for weapon numbers. Returns a table of whichever of
-- {minDamage, maxDamage, speed, dps} the line carries, or nil if it carries
-- none. `line` may be a plain string; a `nil`/secret/non-string reads as no
-- values (never a fabricated 0 — AC-C).
--
-- The dashes: the range match accepts hyphen-minus, en-dash and em-dash
-- explicitly (-, –, —). `%s*%-%s*` covers the ASCII hyphen; the en/em dash are
-- matched by literal too. One pattern, three characters — the fixture proves
-- all three (AC-B).
local function parseWeaponLine(line)
	if type(line) ~= "string" or isSecretValue(line) then return nil end
	-- Normalise the dash characters to the ASCII hyphen BEFORE matching. Lua
	-- patterns match BYTES, so a character class cannot hold the multi-byte
	-- UTF-8 en-dash (E2 80 93) / em-dash (E2 80 94) as a single element — the
	-- class would match one byte at a time and the range match would fail.
	-- Rewriting the two sequences explicitly is what makes AC-B's "three dash
	-- characters" fixture pass on all three.
	local trimmed = line:gsub("\226\128\147", "-"):gsub("\226\128\148", "-")
		:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" then return nil end
	local out = nil

	-- Damage RANGE: "1 - 3 Damage" (dashes now normalised to '-').
	local lo, hi = trimmed:match("(%d+)%s*%-%s*(%d+)")
	if lo and hi then
		local a, b = tonumber(lo), tonumber(hi)
		if a and b then
			if a > b then a, b = b, a end   -- low<->high, tolerate reversed input
			out = out or {}
			out.minDamage, out.maxDamage = a, b
		end
	end

	-- SPEED: "Speed 1.90" — a decimal in 0.5..10 (the reference's own window,
	-- Weapon.lua:161). Read the number after the word "speed"; if the line is
	-- the "Speed" word on the left column with the value on the right (the
	-- reader joins columns), the search still finds it.
	local sp = trimmed:lower():match("speed%s*:?%s*([%d]+[%.%,]?%d*)")
	if sp then
		local v = tonumber((sp:gsub(",", ".")))
		if v and v >= 0.5 and v <= 10 then
			out = out or {}
			out.speed = v
		end
	end

	-- Parenthesised DPS: "(1.05 damage per second)".
	local dps = trimmed:lower():match("%(([%d]+[%.%,]?%d*)%s*damage%s+per%s+second%)")
	if dps then
		local v = tonumber((dps:gsub(",", ".")))
		if v then
			out = out or {}
			out.dps = v
		end
	end

	return out
end

-- Read a whole weapon side (a list of raw lines) into a single numbers table.
--   { minDamage, maxDamage, speed, dps }  — only the fields the tooltip carried
-- Any secret/unreadable line contributes nothing; missing stays missing.
local function weaponNumbers(lines)
	if type(lines) ~= "table" then return nil end
	local acc = {}
	for _, line in ipairs(lines) do
		local one = parseWeaponLine(line)
		if one then
			if one.minDamage and acc.minDamage == nil then
				acc.minDamage, acc.maxDamage = one.minDamage, one.maxDamage
			end
			if one.speed and acc.speed == nil then acc.speed = one.speed end
			if one.dps   and acc.dps   == nil then acc.dps   = one.dps   end
		end
	end
	if next(acc) == nil then return nil end
	return acc
end

-- Compute a comparable DPS from a numbers table. Prefer the value the CLIENT
-- PRINTS (the parenthesised "damage per second"); fall back to (min+max)/2 /
-- speed — arithmetic on what the client prints, not a weight. Returns nil when
-- the inputs are not all known (never a fabricated 0 — AC-C).
local function weaponDPS(numbers)
	if type(numbers) ~= "table" then return nil end
	if numbers.dps ~= nil then return numbers.dps end
	if numbers.minDamage ~= nil and numbers.maxDamage ~= nil and numbers.speed ~= nil
		and numbers.speed > 0 then
		return ((numbers.minDamage + numbers.maxDamage) / 2) / numbers.speed
	end
	return nil
end

-- The DPS comparator. Strictly-greater on the candidate side is UPGRADE;
-- strictly-less is NOT_UPGRADE; equal is NOT_UPGRADE (the armour comparator's
-- rule — EQUAL is never an upgrade). Returns verdict, reason.
--
-- `wornSlotFilled` (Vera round 1, defect D1) disambiguates the two causes of
-- "no readable numbers on the worn side":
--   * false/nil — the row's slot holds NOTHING, an EMPTY slot: a legitimate
--     free fill.
--   * true — the slot HOLDS something whose tooltip yielded no parseable
--     numbers (a secret value, an unparseable shape, an API that returned
--     nothing). That is a comparison we cannot make: UNKNOWN, never a
--     fabricated UPGRADE (AC-C: "a missing value must read as missing").
-- The pre-fix code inferred this from `next(wornNumbers)`, but `wornNumbers`
-- is nil in BOTH cases, so the guard could never fire and an unreadable WORN
-- item read "UPGRADE — fills the weapon slot". The caller owns `wornLink` and
-- therefore owns this fact; the comparator takes it as an argument rather than
-- re-deriving it (no client read here — this module stays pure).
local function compareDPS(candNumbers, wornNumbers, wornSlotFilled)
	local c = weaponDPS(candNumbers)
	local w = weaponDPS(wornNumbers)
	if c == nil then
		return "UNKNOWN", "cannot read the weapon's damage-per-second"
	end
	if w == nil then
		if wornSlotFilled or (type(wornNumbers) == "table" and next(wornNumbers) ~= nil) then
			return "UNKNOWN", "cannot read the worn weapon's damage-per-second"
		end
		return "UPGRADE", "upgrade: fills the weapon slot"
	end
	if c > w then
		return "UPGRADE", ("upgrade: more weapon damage per second (%.2f vs %.2f)"):format(c, w)
	elseif c < w then
		return "NOT_UPGRADE", ("less weapon damage per second (%.2f vs %.2f)"):format(c, w)
	end
	return "NOT_UPGRADE", ("equal weapon damage per second (%.2f)"):format(c)
end

-- The weapon gate (§5.1 shape rules) — the ONLY class-specific rule in Tier C,
-- and it is a boolean mandate, not a weight. Returns a named REASON for a
-- decline, or nil to judge normally.
--   candLoc — the candidate's equip token (must be a WEAPON_TOKEN)
--   offLoc  — the WORN off-hand (slot 17) item's equip token, if any
--   spec    — { class = <token> } (class always available; role may be nil)
--
-- W0 — the candidate is a two-hander and slot 17 is OCCUPIED. Wearing it
--      displaces the off-hand item too, so the true delta is not cand vs main;
--      the scoping doc (t_97a8ea03 §5.1) rules that case UNKNOWN: "UPGRADE is
--      wrong. The 2H displaces the off-hand too ... For slice 1: UNKNOWN."
-- W1 — the spec is built around a shield (the shared §4 `required` bucket) and
--      the candidate is a two-hander: the reference's own `profileRequiresShield`
--      block (ForeverGear ProfileRules.lua:313-316), mirrored — this is the
--      "forceMainhand" shape the card's AC-D points at, applied to the weapon
--      family rather than a second off-hand policy.
function Verdict.weaponGate(candLoc, offLoc, spec)
	if type(candLoc) ~= "string" or not Verdict.WEAPON_TOKENS[candLoc] then
		return nil
	end
	-- The CANDIDATE question: does wearing THIS item close the off-hand?
	-- `OFFHAND_CLOSING_TOKENS` — one token, INVTYPE_2HWEAPON (card t_e6103123).
	-- NOT `TWO_HAND_TOKENS`: that four-token set answers G0's WORN-MAIN-HAND
	-- question (a bow/gun/thrown in the main hand really does close slot 17)
	-- and reusing it here is exactly defect B1 — a ranged candidate in slot 18
	-- was refused with W0 for displacing an off-hand it never touches.
	local isTwoHand = Verdict.OFFHAND_CLOSING_TOKENS[candLoc] == true
	if not isTwoHand then return nil end

	-- W0 — the off-hand is occupied (by any off-hand item: a shield, a holdable
	-- or an off-hand weapon), so a two-hander takes it too. Checked FIRST: the
	-- displacement is a structural fact about the item, independent of the
	-- class, and it is the case §5.1's table rules explicitly.
	if type(offLoc) == "string" and offLoc ~= "" then
		return REASON.W0
	end

	-- W1 — the off-hand is FREE, but the spec is built around a shield, so a
	-- two-hander has no business here. The test is the SHARED spec policy
	-- (Verdict.shieldPolicy == "required", the same bucket Tier B's gate reads),
	-- NOT the bare class: a Fury warrior is `allowed`, not `required`, so a 2H
	-- into his empty off-hand is judged normally — only a protection warrior /
	-- paladin (TANK) declines here. A missing/unresolvable spec is NOT a
	-- mandate: fall through and judge (the DPS comparator still runs), which is
	-- the fail-open side of "silence is not harmful" for a two-hander.
	if Verdict.shieldPolicy(spec) == "required" then
		return REASON.W1
	end

	return nil
end

-- Read a weapon side end-to-end from raw tooltip lines and produce the verdict
-- the scan stores. `wornNumbers` nil (or an empty table) is an EMPTY slot.
-- Exposed so the scan AND the tests drive the same comparison logic.
Verdict.weaponNumbers = weaponNumbers
Verdict.weaponDPS = weaponDPS
Verdict.compareDPS = compareDPS

-- Tank path (card t_89440dfa): the relevance-set and dominance helpers are
-- exposed beside the additive tooltip helpers above, for the same reason — the
-- tooltip surface and the tests read through THESE functions rather than
-- re-implementing the vocabulary, so a second, divergent copy of the
-- dominance rule cannot exist.
-- (Verdict.relevanceSet and Verdict.dominance are defined above; these
-- assignments are the explicit export list the module's own tests read.)

-- ---- Additive tooltip helpers (card t_ed71a583) -----------------------------
--
-- The card asks the player to SEE the verdict and the read numbers on the item
-- tooltip. That needs two pieces of knowledge this module already owns, and
-- NOTHING else:
--
--   1. what the two items' stat tables are  -> parseSide/parseLine_ (above);
--   2. what the per-stat difference is      -> arithmetic on those tables.
--
-- Both are exposed here as ADDITIVE, READ-ONLY helpers beside `evaluate`, the
-- same precedent `classRoleOrder` and `clientRoleWord` set. `evaluate` itself is
-- byte-unchanged: the card forbids a second parser in the UI file (two parsers
-- diverge, and a divergent parser is a silent wrong answer), so the tooltip
-- surface reads through THESE functions and never re-implements the vocabulary.
--
-- No weight, no coefficient, no estimate appears below. Every number a caller
-- prints comes from the client's own tooltip text, parsed by the comparator's
-- own parser and subtracted from the other side's own number.

-- The stat words of one item's raw tooltip lines, through the comparator's own
-- parser. `side` is "candidate" | "worn" (default "candidate") and selects the
-- exact parseSide behaviour the comparator applies to that side — including the
-- worn side's additive enchant fold (t_ea70928d), so the numbers a caller prints
-- for the equipped item are the numbers the verdict was decided on.
--
-- Returns: stats — word -> number (KNOWN words only)
--          note  — the first unplaceable line / proc word, or nil. The
--                  comparator's suppression channel, returned so a caller can
--                  say WHY an item cannot be judged instead of guessing.
--          ignored — (card t_b7a9e7a5) an array of the cosmetic lines this
--                  parse SKIPPED: unplaceable, carrying no number. Optional
--                  third return, so every existing `local s, note = ...` call
--                  site is untouched. The comparator ignores them by design;
--                  a caller that wants to disclose a partial read renders
--                  Verdict.partialNote(ignored) — the verdict is unaffected
--                  either way, which is the whole point of the rule.
-- `lines` is never mutated; the input table is only read.
-- `apiWords` (card t_548f0341, OPTIONAL) is the client's own stat read for this
-- side, already mapped by Verdict.apiStats at the impure edge. It resolves an
-- unplaceable line exactly as the comparator's own parse does, so the numbers a
-- caller prints are the numbers the verdict was decided on.
function Verdict.statTable(lines, side, apiWords)
	local stats, proc, unknown, ignored =
		parseSide(lines, side == "worn" and "worn" or "candidate", apiWords)
	return stats, (proc or unknown), ignored
end

-- Display labels for the stat words. A LABEL, not a weight: it only shortens a
-- word for a tooltip row ("+2 Str"). An unknown word falls through verbatim, so
-- a future stat is never mislabelled.
local STAT_LABEL = {
	Strength  = "Str",
	Agility   = "Agi",
	Stamina   = "Sta",
	Intellect = "Int",
	Spirit    = "Spi",
	Armor     = "Armor",
	Block     = "Block",
	SpellPower = "Spell Power",
}

function Verdict.statLabel(word)
	if type(word) ~= "string" then return tostring(word) end
	return STAT_LABEL[word] or word
end

-- The read delta between two stat tables along the caller's own stat order
-- (candidate - equipped; a word absent on a side is 0 there — the same
-- convention orderedCompare uses). Words the order does not name still appear,
-- after the ordered ones, in a stable word-sorted tail so a printed line is
-- repeatable. Only a NON-ZERO difference is reported: a list of zeroes is
-- noise, not information.
--
-- Returns an array of { word = <stat word>, delta = <candidate - equipped> }.
-- Neither input table is mutated.
function Verdict.statDeltas(candStats, eqStats, order)
	local out, seen = {}, {}
	local cand = (type(candStats) == "table") and candStats or nil
	local eq   = (type(eqStats)   == "table") and eqStats   or nil

	local function consider(word)
		if type(word) ~= "string" or seen[word] then return end
		seen[word] = true
		local c = (cand and cand[word]) or 0
		local e = (eq   and eq[word])   or 0
		if c ~= e then out[#out + 1] = { word = word, delta = c - e } end
	end

	if type(order) == "table" then
		for _, word in ipairs(order) do consider(word) end
	end
	-- Every other word either side carries (a secondary stat the role's order
	-- does not name). Collected first, then sorted, so the tail is stable.
	local rest = {}
	for word in pairs(cand or {}) do
		if not seen[word] then rest[#rest + 1] = word end
	end
	for word in pairs(eq or {}) do
		if not seen[word] then rest[#rest + 1] = word end
	end
	table.sort(rest)
	for _, word in ipairs(rest) do consider(word) end

	return out
end

-- Render a statDeltas() list as the tooltip's arithmetic: "+2 Str, -1 Sta",
-- capped at `limit` entries (the tail is marked with an ellipsis, never silently
-- dropped). Returns "" for no deltas so a caller can skip the parenthesis.
function Verdict.deltaText(deltas, limit)
	if type(deltas) ~= "table" or #deltas == 0 then return "" end
	local cap = tonumber(limit) or 4
	local parts = {}
	for i = 1, math.min(#deltas, cap) do
		local d = deltas[i]
		parts[#parts + 1] = ((d.delta > 0) and "+" or "") .. tostring(d.delta)
			.. " " .. Verdict.statLabel(d.word)
	end
	local text = table.concat(parts, ", ")
	if #deltas > cap then text = text .. ", …" end
	return text
end

-- Make the module globally visible to any consumer in this file's scope.
-- In game, WoW addons share the global namespace, so this is the standard
-- pattern for addon-to-addon exposure. The test harness, which drives the
-- file with loadstring, gets the same visibility.
_G.Verdict = Verdict

return Verdict
