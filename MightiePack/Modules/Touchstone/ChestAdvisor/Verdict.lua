-- Host opt-out: a host that vendors these files sets TouchstoneSkip = true before
-- loading them, and every shipped file returns at this line. Unset -- the normal
-- case -- nothing changes. See README.md, "Embedding Touchstone in a host addon".
if TouchstoneSkip then return end
-- Verdict.lua — the t_3c1256ec upgrade verdict.
--
-- Two pure pieces of knowledge, with no UI, no client dependency, and no
-- mutable state: `classRoleOrder` (the documented per-class stat priorities)
-- and `evaluate` (the deterministic comparator). Everything a scanner needs
-- to call them flows in as arguments, so a unit test can drive every branch on
-- a clean VM without fixtures.
--
-- ⚠ ONE exception to "nothing is read from the environment", added by card
-- t_984bc8ac: the optional per-class/spec WEIGHT table (Weights.lua,
-- StatForge.Weights), read at CALL time by the weighted resolution layer and
-- by Verdict.weightsFor. It is probed for and degrades to the ordinal path
-- when it is absent, exactly the posture gate 3 already takes toward the
-- client's `issecretvalue`. Nothing else here reads a global.
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
--     There is no silent default. Until card t_6c3f414a (DD-3) the Druid
--     `melee` role was a documented role WITH no order (the NO_ORDER sentinel
--     below); DD-3 gives it the feral order the corpus documents, so no
--     shipped ORDERS entry carries NO_ORDER any more — the sentinel and the
--     branch that reads it are kept as the mechanism that expresses "a
--     documented role, no order", and the tests that exercise it construct
--     their own entry.

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
-- roles. Druid's `melee` role had no recorded corpus order until card
-- t_6c3f414a (DD-3), which gives it the one the feral PLAYER's pack documents
-- (strength > agility > stamina — the shape of druid-feral.dps, whose own
-- first three terms are strength 1.0, agility 0.8, stamina 0.4); the card's
-- brief states the same three words. NO_ORDER remains the way to say "a
-- documented role, no order" and no shipped entry uses it now.
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
		-- the documented int>agi>sta (stat-weights §8.1).
		--
		-- Its `melee` role (feral) carried NO_ORDER until card t_6c3f414a
		-- (DD-3), which gives it the feral order: strength > agility >
		-- stamina. WHY THESE WORDS, and what they are NOT:
		--   * The order is drawn from the feral PLAYER's own pack
		--     (statforge-app presets['druid-feral'].dps: strength 1.0,
		--     agility 0.8, stamina 0.4 — armory AP and crit follow), and the
		--     card's brief names the same three words. It is the CAT's
		--     priority; the BEAR reads the same ORDER (one role word serves
		--     both physical specs) but its own WEIGHT table (DRUID.tank),
		--     which is where stamina-first lives.
		--   * The order is not used to choose the weight table and cannot be
		--     (Druid weights resolve through weightsFor's role/literal
		--     lookup). It words the reason and supplies the dominance terms;
		--     Armor and the shield stat join the relevance set unconditionally.
		--   * Strength first is a FERAL-specific claim (a cat's attack power
		--     comes from strength in this era's feral model), not a
		--     class-wide one: a Balance druid never sees this order, because
		--     its role resolves to `spell`.
		melee = { "Strength", "Agility", "Stamina" },
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
-- DAMAGER (ChestAdvisor.lua readSpecIdentity; review §3). Until this card the two
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
--                      settled here (the maintainer's ruling on t_0b4ddfa9).
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
	-- unchanged (the maintainer: "Adding DAMAGER is NOT needed and would change nothing").
	-- ⚠ The honest limitation: TANK -> "melee" means a Prot Warrior's ORDER is the
	-- same as a Fury Warrior's. That is intended: the order only WORDS the reason
	-- (point 3), the arrow comes from the dominance/trade-off test.
	WARRIOR = { TANK = "melee" },
	-- Feral bear (card t_6c3f414a, DD-3). TANK is mapped so that IF the
	-- client's spec read ever says TANK for a druid, it folds onto the `melee`
	-- order word (both feral shapes are physical) and the weight lookup reaches
	-- Weights.DRUID.tank through the literal. The literal comes from the
	-- talent-spec read (ChestAdvisor.lua: readSpecIdentity ->
	-- C_SpecializationInfo.GetSpecializationInfo's 5th return, consumed in
	-- buildSpec as clientRole = si.role), NOT from the shapeshift form —
	-- nothing reads the form. No spec read on today's client has been observed
	-- returning TANK for a feral druid, so the bear path cannot be reached in
	-- real play yet; it is reachable only through a spec whose role literal is
	-- TANK (tests drive it by passing clientRole = "TANK" directly). This
	-- follows the PALADIN.tank pattern exactly: the ORDER is resolved through
	-- the fold (`melee`), while the WEIGHT table is resolved through the
	-- client's own literal (`tank` -> Weights.DRUID.tank), so the bear reads
	-- the feral order with the bear pack.
	--
	-- ⚠ DAMAGER is deliberately ABSENT, and the reason is the opposite of
	-- Paladin's. A Protection paladin's TANK is a third spec the ORDER
	-- vocabulary has no word for; a druid's DAMAGER is the CLIENT's word for
	-- TWO different specs — Balance (the caster, which the app's own
	-- tabSpecs.DRUID calls "Balance -> caster weights") and Feral cat. Mapping
	-- DAMAGER to `melee` would hand every Balance druid the feral order and
	-- the cat pack. Balance reaches DRUID.damager through the literal instead
	-- (weightsFor's first step), and the cat reaches `melee` through the
	-- addon's own recorded role, which is the only vocabulary that can tell
	-- the two DAMAGER specs apart. HEALER is absent for the same reason Resto
	-- needs no alias: its literal already names DRUID.healer.
	DRUID = { TANK = "melee" },
}

-- ---- The literal's SPECIFIC-ROLE constraint (card t_6c3f414a, DD-3) ----------
-- A client literal normally BEATS the folded role word when both name a table
-- (weightsFor's steps 1 and 2): TANK is a more specific fact about a Protection
-- paladin than the folded "spell" is. ONE literal in the vocabulary is not more
-- specific, and this table names it: the client uses DAMAGER for two different
-- druid specs — Balance and Feral cat — and DRUID.damager is the Balance bridge
-- (a CROSS-CLASS borrow of priest-shadow.dps, card t_0e5381e1). A feral cat is
-- DAMAGER too, so without this constraint a cat whose addon role is `melee`
-- would be judged by the BALANCE pack: Intellect 0.8, Spirit 0.6, Strength 0 —
-- a caster shape served to a physical spec, which is the R5 defect in a new
-- costume.
--
-- So a literal listed here may name a weight table ONLY when the character's
-- resolved role is the one given. The cat keeps its own `melee` table (its
-- DAMAGER literal is consumed by the ROLE step, not the literal step), Balance
-- keeps `damager`, and the bear keeps `tank` (TANK is listed for the melee
-- role). Review round 2 closes three wrong-pack cases: melee+HEALER would get
-- the Resto pack, spell+TANK would get the bear pack, and melee+an unknown
-- word would get the cat pack guessed.
--
-- ⚠ DELIBERATELY NOT PART OF ROLE_ALIAS. clientRoleWord feeds resolvedRole
-- (ChestAdvisor.lua), i.e. the ORDER lookup, and there DAMAGER must stay
-- unmapped for a druid: mapping it would resolve a cat that has picked no role
-- to the CASTER order, and t_03a1196c (C1b, R5) ruled exactly that out. This
-- table is read in ONE place — weightsFor's literal step — and nowhere else.
local LITERAL_NEEDS_ROLE = {
	DRUID = { DAMAGER = "spell", HEALER = "spell", TANK = "melee" },
}

-- ---- The role's SPECIFIC-LITERAL constraint (card t_6c3f414a, DD-3) ----------
-- The mirror of the constraint above. A druid's `melee` role word is shared by
-- TWO packs, the cat (DRUID.melee) and the bear (DRUID.tank), and the only
-- thing that tells them apart is the client literal (DAMAGER -> cat via the
-- role step, TANK -> bear via the literal step). A druid whose role is `melee`
-- but whose client literal is missing or unreadable is therefore UNIDENTIFIED,
-- and guessing the cat pack for it would be a guessed weighting; so a role
-- listed here may name a weight table through the ROLE step only when the
-- client supplied one of the literals listed for that role. With no literal,
-- weightsFor returns nil and the row falls back to the ordinal path (the order
-- still words the reason; only the pack is withheld) — the same fail-closed
-- shape as a missing table everywhere else in this file. Read in ONE place:
-- weightsFor's role step.
local ROLE_NEEDS_LITERAL = {
	DRUID = { melee = { DAMAGER = true, TANK = true } },
}

-- ---- The client's literal vocabulary (card t_41697d02, gate t_35b75690 F2) ---
-- The set of role words the CLIENT can say is DERIVED from ROLE_ALIAS above —
-- never spelled a second time — so the words the weight resolver knows and the
-- words the order alias knows cannot drift apart. Today it is exactly the
-- client's three: TANK, HEALER, DAMAGER, held in the uppercase form the client
-- and ROLE_ALIAS speak (a weight table's KEYS are the lowercased form, so the
-- lookups below lowercase them).
local CLIENT_ROLE_LITERALS = {}
for _, map in pairs(ROLE_ALIAS) do
	for literal in pairs(map) do CLIENT_ROLE_LITERALS[literal] = true end
end

-- Which client word(s) a pack IS. A pack that is also a literal key publishes
-- the client spec it serves: PRIEST.spell and PRIEST.damager are the SAME table
-- object, so `spell` is the DAMAGER pack, and PRIEST.healer is the HEALER pack.
-- Returns {} for a pack no literal key points at — a role-word table's pack
-- (WARRIOR.melee, HUNTER.melee, PALADIN.spell) publishes no client spec, and
-- that is what keeps the fail-closed below off those classes.
local function literalWordsFor(byClass, table_)
	local words = {}
	for literal in pairs(CLIENT_ROLE_LITERALS) do
		if rawget(byClass, literal:lower()) == table_ then words[#words + 1] = literal end
	end
	return words
end

-- True when the pack a FALL-THROUGH would resolve to is published for a
-- DIFFERENT client word than the one the client named — the one case where a
-- sibling pack must not answer: a Holy priest (HEALER) with no `healer` key
-- would otherwise be judged by `spell`, which is the DAMAGER (Shadow) pack.
local function servesAnotherLiteral(byClass, table_, named)
	for _, word in ipairs(literalWordsFor(byClass, table_)) do
		if word ~= named then return true end
	end
	return false
end

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

-- ---- Armor type (install-17 playtest; re-ruled by the owner 2026-11-03) ------
--
-- Armor value only breaks a tie. It does not notice that a cloth belt is the
-- wrong material for a mail-wearing paladin, so a cloth quest reward used to
-- read TRADE_OFF against equipped mail. The install-17 rule compared the
-- CANDIDATE against the best type this class can wear at this level, which
-- blocked a leather drop for a paladin wearing CLOTH: the worn item is what the
-- candidate replaces, so the worn item is what it must be measured against.
-- For the slots that HAVE an armor type, and only when the worn material is
-- readable:
--   * worn material ranked ABOVE the candidate is a real cost, never a veto —
--     an UPGRADE softens to TRADE_OFF, and a TRADE_OFF becomes NOT_UPGRADE;
--   * worn material equal to or below the candidate changes nothing;
--   * an empty slot, or a worn material the tooltip did not yield, falls
--     through UNCHANGED (an unreadable worn item is not a downgrade).
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

-- A reason string when the WORN item's armor type is ABOVE the candidate's —
-- i.e. the player is wearing better material than the item being judged. nil
-- when the rule does not apply (no typed slot on either side, or a worn side
-- that was not read).
--
-- RULED BY THE OWNER 2026-11-03: the comparison is WORN vs CANDIDATE, not
-- candidate vs class-best. `wornLines` is the equipped item's own tooltip lines,
-- which the caller already holds in `eqLines`; when it is absent or carries no
-- armour material the rule falls through UNCHANGED, never as a block.
--
-- THE NOTE NAMES WHAT IS WORN (card t_d88b7f28, items 1 and 2). It used to read
-- "leather: you can wear mail" — the best material the CLASS could wear, which
-- never mentions the item being replaced and so never explains the soft cost it
-- is attached to. It now reads "leather: you're wearing mail": the actual trade.
--
-- That change removed this function's only use of the class and the level, and
-- with them the `bestArmor` gate that sat in front of the whole rule. That gate
-- was a fail-OPEN hole (item 2): with an unknown class or a level the table
-- could not place, `Verdict.bestArmor` returned nil, the function returned nil,
-- and a plate item judged against worn cloth stayed a clean UPGRADE — the one
-- case the rule exists for. The worn-vs-candidate comparison needs neither fact,
-- so it now runs whether or not a class-best is known, and `spec` is no longer
-- a parameter (it had no other reader here). One definition, one call site.
function Verdict.lowerArmorReason(lines, wornLines)
	local mat = Verdict.tooltipArmorMaterial(lines)
	if type(mat) ~= "string" then return nil end
	local worn = Verdict.tooltipArmorMaterial(wornLines)
	if type(worn) ~= "string" then return nil end
	local rank = Verdict.ARMOR_RANK
	if type(rank[mat]) ~= "number" or type(rank[worn]) ~= "number" then return nil end
	if rank[worn] > rank[mat] then
		return mat .. ": you're wearing " .. worn
	end
	return nil
end

-- ── ONE DIRECTION RULE, ONE COPY (card t_da23ec75) ─────────────────────────
-- The direction of ONE term: 1 = the candidate is ahead, -1 = behind, 0 = level.
--
-- Absence is a DIRECTION here, not a zero (the absent-stat rule below states the
-- same thing for the proof): a term present on one side only is that side being
-- ahead, and a term absent on BOTH sides is no information at all. Values are
-- compared directly when both sides carry the word.
--
-- THE TOOLTIP'S RESOLUTION IS HONOURED HERE (card t_645c7ae6, addendum (c)). A
-- Hit or Crit difference smaller than one tooltip step is the tooltip's
-- QUANTISATION, not a stat the player has, so it is LEVEL — `Verdict.
-- levelWithinResolution`, the SAME helper `Verdict.weightedScore` uses, called
-- at this one site rather than a second epsilon invented for the proof. It is a
-- no-op for every word with no factor (the helper returns false when the word
-- has no resolution), so only the two converted words move.
--
-- WHY IT HAS TO BE HERE AND NOT ONLY IN weightedScore. Once Hit and Crit are
-- proof terms this function is a second place that subtracts two of their
-- values, and the two values can arrive from DIFFERENT SURFACES: one side's line
-- placed by the text parser (a tooltip percent, lifted by its factor — 12 rating
-- renders "0.9%" and lifts back to 12.6), the other's explained by the client's
-- own read (the exact integer count). Left unforgiven, that pair is decided by
-- 0.6 of rounding — the exact defect card t_43f8cd6f closed one site away.
--
-- The proof (`Verdict.dominance`, next) and the two naming loops that word its
-- answer (gate 9 of `Verdict.evaluate`) read THIS function. That is the card's
-- point in one line: a pair must never be DECIDED by one rule and WORDED by
-- another, so a dominance outcome can always name the term that produced it.
local function termSign(word, c, e)
	if Verdict.levelWithinResolution(word, c, e) then return 0 end
	if c ~= nil and e ~= nil then
		if c > e then return 1 end
		if c < e then return -1 end
		return 0
	end
	if c ~= nil then return 1 end
	if e ~= nil then return -1 end
	return 0
end

-- The three-outcome dominance test over a list of TERMS.
--
--   dominant  — C >= W on every term, and C > W on at least one  -> UPGRADE
--   dominated — C <= W on every term, and C < W on at least one  -> NOT_UPGRADE
--   trade-off — better on some, worse on others                  -> trade-off
--   equal     — nothing differs                                 -> nil (the
--               caller's existing "equal" tiebreak fall-through)
--
-- ⚠ WHAT `terms` IS (card t_da23ec75 — the supersede of "the role's own order
-- terms"). It is the PROOF's term list, built by `Verdict.proofTerms`: the
-- class/role's documented ORDER first (so every reason is worded in the order's
-- own grammar, exactly as before) and then every word the pair's resolved pack
-- PRICES at a non-zero weight. "Order = wording, priced set = proof."
--
-- WHY. The order is a prose ranking of five core stats; the packs price ten
-- more words — Hit, Crit, AP, MP5, Defense, the survival
-- words. While the proof read only the order, those prices were multiplied into
-- a term the proof could not see: a pair that LOST crit still read a clean
-- "upgrade: better on Agility" at every weight, because nothing in the proof
-- knew crit existed. A price that cannot make a pair a trade-off is not being
-- weighed; it is being asserted. This function is the one place that is fixed,
-- and the order is still what WORDS the answer.
--
-- ⚠ Armor, Block and WeaponDps are NEVER terms of this proof, whatever their
-- price — the reason for each is stated once, on `Verdict.PROOF_EXEMPT`.
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
-- tiebreak (see gate 9 below). The exemption is a LIST, not a paragraph
-- repeated at each call site: `Verdict.PROOF_EXEMPT` carries Armor, Block and
-- WeaponDps with one reason each, and `Verdict.proofTerms` is its only reader.
-- The ruling behind the first two is E2 (t_8bc7d7f2, §4.1a) — "armour is never a
-- win, only a tiebreak", graded AC-E13(b) "armour never overturns a class-order
-- loss": inside the proof a higher-armour/lower-primary pair would read
-- TRADE_OFF and overturn the very loss that gate exists to keep.
--
-- Returns "dominant" | "dominated" | "trade-off" | nil, firstDiff
--   firstDiff — the first term (in term order) where the two sides differ, or
--               nil. Callers use it ONLY to word a reason; it never decides.
function Verdict.dominance(candStats, eqStats, terms)
	local cand = type(candStats) == "table" and candStats or {}
	local eq   = type(eqStats)   == "table" and eqStats   or {}
	local anyGreater, anyLesser = false, false
	local firstDiff = nil
	for _, word in ipairs(terms or {}) do
		local sign = termSign(word, rawget(cand, word), rawget(eq, word))
		if sign > 0 then
			anyGreater = true
		elseif sign < 0 then
			anyLesser = true
		end
		if sign ~= 0 and firstDiff == nil then firstDiff = word end
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
	-- Card t_3cdbb70a (DD-1): the four sentences parseLine_ now reads — the
	-- hit and crit phrasings, melee and spell. All four read ONE hit word and
	-- ONE crit word: the two spellings print the same stat, and the client's
	-- own recap says so verbatim ("Spell, melee, and ranged hit chance are
	-- combined, as are spell, melee, and ranged critical chance." — the ruling
	-- lives in the retirement note under WEIGHT_KEYS). Whether a word PRICES
	-- for a given class is the weight table's answer, never this table's.
	["Hit"]            = true,
	["Crit"]           = true,
	["FeralAttackPower"] = true,
	-- The extended reader's vocabulary: the client prints these words on a
	-- tooltip line of their own ("+12 Defense", "20 Attack Power", "10 MP5",
	-- "12 Weapon Skill"), and every one of them suppressed the item while it
	-- was absent from this table. They are KNOWN so a line naming them is
	-- ACCUMULATED rather than suppressed. Whether a profile PRICES a word is
	-- still the weight/tier table's answer: an unpriced known word is a zero,
	-- never a guess.
	--
	-- ⚠ The healing / spell-damage / school keys are NOT here any more: card
	-- t_4e1e1b1d (DD-2) declares Healing, SpellDamage and the six school
	-- powers itself, and this pack's older spellings (HealingPower,
	-- HolyDamage, …) were dropped with the parse that produced them, so that
	-- one stat has one name in the reader and in the packs. See
	-- ChestAdvisor__Verdict.lua.patch's header for the full list.
	["Defense"]          = true,
	["Dodge"]            = true,
	["Parry"]            = true,
	["AttackPower"]      = true,
	["RangedAttackPower"] = true,
	["WeaponDps"]        = true,
	["MP5"]              = true,
	["HP5"]              = true,
	["Haste"]            = true,
	["Expertise"]        = true,
	["ExpertiseRating"]  = true,
	["BlockChance"]      = true,
	["BonusArmor"]       = true,
	["SpellPenetration"] = true,
	["WandDps"]          = true,
	["WeaponSkill"]      = true,
	["WeaponSpeed"]      = true,
	-- Card t_4e1e1b1d (DD-2): healing-only and SCHOOL-specific spell damage.
	-- Until this card every one of these sentences suppressed the item
	-- ("cannot classify: Equip: Increases healing done by spells and effects by
	-- up to 22."), which is why a healer and a school-focused caster could get
	-- no verdict at all. They are separate words on purpose: +22 healing is not
	-- +22 spell power (it does nothing for a Warlock's Shadow Bolt), and Fire
	-- damage is not Frost damage (a Frost mage's Frostbolt gets nothing from
	-- Fire power). Which of them are worth anything to a given class is the
	-- weight table's answer, never this table's — see the SCHOOL POWER note in
	-- Weights.lua and, for the one class rule the packs imply, the MAGE
	-- max(Fire, Frost) note above weightedScore.
	["Healing"]        = true,
	-- Card t_8575389a: the DAMAGE half of the combined healing+damage sentence
	-- ("…and damage done by up to 14 for all magical spells and effects."), and
	-- the school-less damage-only sentence. It is NOT SpellPower: the sentence
	-- states damage alone, and this client gives it its own key
	-- (ITEM_MOD_SPELL_DAMAGE_DONE_SHORT). KNOWN here so the line classifies; it
	-- has no weight key at all (no 29th key, the owner's ruling), so no table
	-- prices it and it can only ever contribute 0 — the same shape as
	-- FeralAttackPower, and see the exemption note in wordUnpriced.
	["SpellDamage"]    = true,
	["HolyPower"]      = true,
	["FirePower"]      = true,
	["FrostPower"]     = true,
	["ShadowPower"]    = true,
	["NaturePower"]    = true,
	["ArcanePower"]    = true,
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
-- This table is the ONLY place a client key becomes a stat word. It lists the
-- keys VERIFIED on this client, and nothing else — a key that is not verified
-- is ABSENT, so it resolves to nil and its line stays suppressive: the same
-- fail-closed answer as an absent API (AC-C of card t_795eee9e, executed in
-- ChestAdvisor/tests/t_795eee9e.js). Two verifications stand behind it:
--
--   * the owner's own live read (harvested 2026-10-07 from a level-22 character
--     paladin's helm and worn shield): STAMINA / STRENGTH / AGILITY / SPIRIT
--     in the `_SHORT` spelling, RESISTANCE0_NAME (the client's own name for
--     Armor), ITEM_MOD_SPELL_POWER_SHORT;
--   * the client's full key vocabulary (card t_795eee9e), the captured ground-truth
--     inventory "StatForge - ITEM_MOD Key Inventory (client ground truth) -
--     2026-10-04.md" — 133 keys extracted from the client binary (Wow.exe).
--     Every mapping below is spelled out of that inventory, not invented; the
--     inventory's own caveat still stands — the keys were extracted, not
--     measured against this addon, so a key the client names but never returns
--     for a real item stays harmless: it maps to a word the pair does not
--     carry, and the sum is untouched.
--
-- Both the `_SHORT` and the bare form are tolerated, because the client spells
-- the same key with and without the suffix depending on the stat (Stamina ships
-- as `ITEM_MOD_STAMINA_SHORT`; Armor ships as the bare-ish `RESISTANCE0_NAME`).
-- The matcher takes the LONGEST verified key the incoming key begins with, so
-- a specific key wins, and a suffix the client appends can never be mistaken
-- for a different stat: ITEM_MOD_HIT_RANGED_RATING reads from
-- ITEM_MOD_HIT_RANGED_RATING (not from any sibling), and
-- ITEM_MOD_RANGED_ATTACK_POWER reads RangedAttackPower, never the plain
-- AttackPower key (the prefixes differ before the suffix, so that read is not
-- possible). The vs-faction spellings (ITEM_MOD_*_VS_DEMON and the like) do
-- fold onto the base stat with the longest match — they ARE that stat for the
-- fight they name, and the addon prices one term for it.
Verdict.ITEM_STAT_KEYS = {
	ITEM_MOD_STAMINA     = "Stamina",
	ITEM_MOD_STRENGTH    = "Strength",
	ITEM_MOD_AGILITY     = "Agility",
	ITEM_MOD_SPIRIT      = "Spirit",
	-- RESISTANCE0 is the client's own name for the Armor stat. Verified against
	-- the owner's worn shield: 478 Armor on the tooltip == RESISTANCE0_NAME 478.
	RESISTANCE0          = "Armor",
	ITEM_MOD_SPELL_POWER = "SpellPower",
	-- Card t_8575389a: INTELLECT had no verified key until the owner's Hide of
	-- the Wild read (2026-10-20) returned `ITEM_MOD_INTELLECT_SHORT = 10` for the
	-- item's own "+10 Intellect" line. It was the LAST unmapped key on that read
	-- — apiStats reported it through `unmapped` and the pair failed closed as
	-- "cannot classify: ITEM_MOD_INTELLECT_SHORT (a client stat key this addon
	-- has not verified)" — on a caster's primary stat, which is the worst place
	-- in this table to have a hole. Spelled here from the same live read.
	ITEM_MOD_INTELLECT = "Intellect",
	-- ── card t_8575389a: the two halves of the combined sentence ──────────
	-- VERIFIED on the owner's live client (Forever beta, 2026-10-20) against Hide
	-- of the Wild, item:18510 — keys and values verbatim:
	--     ITEM_MOD_SPELL_HEALING_DONE_SHORT = 42
	--     ITEM_MOD_SPELL_DAMAGE_DONE_SHORT  = 14
	-- ONE number each, carried by the CLIENT: nothing is derived from the healing
	-- half (the card's superseded /3 fallback is not implemented anywhere). Before
	-- these two entries both keys were UNVERIFIED, which apiStats reports through
	-- `unmapped` — so an item the client had read perfectly still failed closed as
	-- "cannot classify: ITEM_MOD_SPELL_DAMAGE_DONE_SHORT (a client stat key this
	-- addon has not verified)". That was the last suppression on this path.
	--
	-- The key inventory this table used to cite (2026-10-04, extracted from the
	-- binary) listed no healing or damage key, and the DD-2 note above says so.
	-- The inventory was EXTRACTED, not measured; the owner's live read is the
	-- measurement, and it supersedes that silence for these two keys only.
	ITEM_MOD_SPELL_HEALING_DONE = "Healing",
	ITEM_MOD_SPELL_DAMAGE_DONE  = "SpellDamage",
	-- ── card t_795eee9e: the rest of the vocabulary the cited packs price ────
	-- ── card t_3cdbb70a (DD-1): HIT and CRIT are SPLIT ─────────────────────
	-- t_795eee9e folded melee, ranged and spell hit onto ONE word (and the
	-- same for crit), on the reasoning that the packs price a single
	-- hitRating / critRating. That reasoning was right about the PACK and
	-- wrong about the CLASS: a caster priced a melee-hit item at its spell-hit
	-- value, and a hybrid that uses both read the two halves as one number.
	-- Card t_9d3273cb UNIFIES them, and this time the fold is the CLIENT's own
	-- fact rather than an inference from the packs: on this client spell, melee
	-- and ranged hit are ONE stat, and so are the three crits (the recap
	-- sentence is quoted verbatim under WEIGHT_KEYS). DD-1's split therefore
	-- separated two spellings of one stat, and the cost fell on the caster: his
	-- spell-crit item priced 0.6 x 14 through the spell key while the SAME item
	-- read through the crit key priced 0.
	--
	-- So all eight client keys read the one word each — the generic
	-- `ITEM_MOD_HIT_RATING`, the MELEE and RANGED spellings, and the SPELL
	-- spelling alike. Which class actually pays for the stat is the weight
	-- table's answer: every table carries the pack's hitRating on HIT and its
	-- critRating on CRIT, caster and melee alike (Weights.lua).
	ITEM_MOD_HIT_RATING         = "Hit",
	ITEM_MOD_HIT_MELEE_RATING   = "Hit",
	ITEM_MOD_HIT_RANGED_RATING  = "Hit",
	ITEM_MOD_HIT_SPELL_RATING   = "Hit",
	ITEM_MOD_CRIT_RATING        = "Crit",
	ITEM_MOD_CRIT_MELEE_RATING  = "Crit",
	ITEM_MOD_CRIT_RANGED_RATING = "Crit",
	ITEM_MOD_CRIT_SPELL_RATING  = "Crit",
	-- Attack power: the pack's one attackPower term. The client's melee
	-- spelling folds onto it; its ranged spelling keeps a SEPARATE word,
	-- because the client treats it as a separate stat and one cited pack
	-- (hunter-marksman) prices it under that name.
	--
	-- FERAL is its own word (card t_3cdbb70a, DD-1 item 1). The Classic line
	-- reads "Increases attack power by N in Cat, Bear, Dire Bear, and Moonkin
	-- forms only" — worth ZERO to a Warrior, Paladin, Shaman, Hunter or Rogue,
	-- and t_795eee9e priced it at their AP weight (0.45 / 0.4 / 0.4 / 0.3 /
	-- 0.4). One word, one term: the feral spelling must not fold onto
	-- AttackPower. No pack in the quote prices a feral term, so FAP is 0 on
	-- every table until DD-3 gives Feral a table of its own (out of scope
	-- here), and the gate never closes a pair on it (wordUnpriced).
	ITEM_MOD_ATTACK_POWER        = "AttackPower",
	ITEM_MOD_MELEE_ATTACK_POWER  = "AttackPower",
	ITEM_MOD_FERAL_ATTACK_POWER  = "FeralAttackPower",
	ITEM_MOD_RANGED_ATTACK_POWER = "RangedAttackPower",
	-- Per-5-second regeneration: the client's two separate keys.
	ITEM_MOD_MANA_REGENERATION   = "MP5",
	ITEM_MOD_HEALTH_REGEN        = "HP5",
	-- The survival terms of the tank packs (defense / dodge / parry ratings).
	ITEM_MOD_DEFENSE_SKILL_RATING = "Defense",
	ITEM_MOD_DODGE_RATING         = "Dodge",
	ITEM_MOD_PARRY_RATING         = "Parry",
	-- Block VALUE is the Tier-B "N Block" stat, which the client's API names
	-- ITEM_MOD_BLOCK_VALUE_SHORT. The owner's worn shield shows the API can
	-- also OMIT it (Block 9 on the tooltip, no key in the read) — the text
	-- path stays the reader there (AC-F), and this mapping only adds the API's
	-- shape of the same line when the client does return it.
	ITEM_MOD_BLOCK_VALUE         = "Block",
	-- Weapon DPS, when the client names it (the inventory spells it
	-- ITEM_MOD_DAMAGE_PER_SECOND_SHORT): the packs price it as weaponDps, and
	-- where they do, the table prices it as WDN.
	ITEM_MOD_DAMAGE_PER_SECOND   = "WeaponDps",
	ITEM_MOD_HASTE_RATING        = "Haste",
	ITEM_MOD_HASTE_MELEE_RATING  = "Haste",
	ITEM_MOD_HASTE_RANGED_RATING = "Haste",
	ITEM_MOD_HASTE_SPELL_RATING  = "Haste",
	ITEM_MOD_EXPERTISE_RATING    = "ExpertiseRating",
	ITEM_MOD_BLOCK_RATING        = "BlockChance",
	ITEM_MOD_SPELL_PENETRATION   = "SpellPenetration",
	-- DD-2 maps the healing and the damage half of the combined sentence
	-- itself (…_SPELL_HEALING_DONE -> Healing, …_SPELL_DAMAGE_DONE ->
	-- SpellDamage, both behind the owner's live read), so this pack does not
	-- map them a second time: a duplicate key here would silently win over
	-- DD-2's and split one stat into two words. The SCHOOL keys are still this
	-- pack's, spelled with DD-2's words so the client read and the text parse
	-- land on the same key.
	ITEM_MOD_HOLY_POWER          = "HolyPower",
	ITEM_MOD_FIRE_POWER          = "FirePower",
	ITEM_MOD_FROST_POWER         = "FrostPower",
	ITEM_MOD_SHADOW_POWER        = "ShadowPower",
	ITEM_MOD_NATURE_POWER        = "NaturePower",
	ITEM_MOD_ARCANE_POWER        = "ArcanePower",
	ITEM_MOD_BONUS_ARMOR         = "BonusArmor",
	ITEM_MOD_EXTRA_ARMOR         = "BonusArmor",
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
-- still suppresses — i.e. it fails CLOSED, which is the safe direction.
--
-- ⚠ WHAT THIS TEST IS NOT (card t_195a0e07). This is ONE gate, and the
-- paragraph above used to be read as more than it says. parseLine_ does place
-- digit-bearing chrome structurally — but a tooltip's lines reach parseLine_
-- only through `Verdict.splitForeign`, which runs FIRST and decides WHICH lines
-- the classifier is ever asked about. While that split set lines aside by
-- POSITION (anything numbered after a "Sell Price" line), a "+5 Frost
-- Resistance" the reader could not place was taken out of the set before any
-- classifier saw it, and the pair JUDGED. So "every digit-bearing chrome line
-- is structural-classified before it ever reaches this test" was true and was
-- still not the property that mattered: whether an UNPLACEABLE line reached
-- the judge is splitForeign's property, and since t_195a0e07 it is a property
-- of the LINE (another addon's marker), never of where the line sits.
-- the line sits.
function Verdict.lineCarriesNumber(line)
	if type(line) ~= "string" then return false end
	local low = line:gsub("^%s+", ""):gsub("%s+$", "")
	local plain = deColour_(low:lower())
	return plain:find("%d") ~= nil
end

-- ---- Card t_d8de0090: name the lines, do not only count them ----------------
--
-- The pre-card message was "partial read: 2 cosmetic lines ignored" — a COUNT.
-- A player reading it cannot tell WHICH lines were set aside from his own
-- comparison, so the disclosure satisfied the letter of the honesty rule (say
-- something was skipped) and failed the point (say WHAT). Card t_d8de0090
-- replaces the count with the lines themselves:
--
--   partial read: "You haven't collected this appearance" ignored
--   partial read: "Collected appearance" and "Warbound until equipped" ignored
--
-- The words are the PLAYER'S words: the tooltip line as he reads it, with the
-- client's colour escapes removed by `deColour_` — this module's ONE
-- normaliser, the same one parseLine_, reconciliationSafe and
-- lineCarriesNumber already share (card t_02877bb4 made that literal). Nothing
-- is TRANSLATED here, and that is deliberate:
--
--   * A new table of "cosmetic strings" is exactly what card t_b7a9e7a5
--     forbids. The client appends the next sentence whenever it likes, so a
--     vocabulary that has to grow is a vocabulary that will be wrong.
--   * The verdict-word map (ChestAdvisor's `TOOLTIP_UI.words`) names
--     OUTCOMES, not tooltip prose: quoting the line keeps one map per job
--     rather than overloading the outcome map with an English dictionary.
--
-- Truncation is VISIBLE (an ellipsis), never silent: a line longer than
-- PARTIAL_LINE_MAX is cut and marked, and when more lines were skipped than
-- PARTIAL_NAMES_MAX can be named the sentence states the remainder as a count
-- ("and 2 more") instead of pretending to be complete. THE COUNT IS NOT LOST —
-- the raw surface (`/up diag`) records the count and the untouched raw lines
-- (ChestAdvisor.lua, card t_d8de0090 AC-D); this surface is the player-facing
-- one and its job is to NAME them.
local PARTIAL_LINE_MAX  = 40   -- own text of ONE line, before the ellipsis
local PARTIAL_NAMES_MAX = 2    -- lines named before the rest become "and N more"
local PARTIAL_ELLIPSIS  = "…"

-- The player words of ONE tooltip line: de-coloured, whitespace-collapsed and
-- trimmed, then visibly truncated. Pure; never throws; "" for a non-line (so a
-- caller can skip it rather than print a stray pair of quotes).
function Verdict.lineWords(line)
	if type(line) ~= "string" then return "" end
	local plain = deColour_(line)
	plain = plain:gsub("%s+", " ")
	plain = plain:gsub("^ ", ""):gsub(" $", "")
	if plain == "" then return "" end
	if #plain <= PARTIAL_LINE_MAX then return plain end
	-- Cut on a WORD boundary inside the cap, so the text reads rather than
	-- chops: take the last space of the capped prefix when there is a usable
	-- one (a very short prefix would keep a single stray word and no context).
	local cut = plain:sub(1, PARTIAL_LINE_MAX)
	local spaceAt = cut:match("^.*() ")
	if spaceAt ~= nil and spaceAt >= 12 then cut = plain:sub(1, spaceAt - 1) end
	-- Never split a multi-byte character: bytes 0x80..0xBF are UTF-8
	-- continuation bytes, and half a character renders as a replacement glyph
	-- in the client's font. Back off to the character boundary.
	while #cut > 0 do
		local b = cut:byte(#cut)
		if b < 0x80 or b > 0xBF then break end
		cut = cut:sub(1, #cut - 1)
	end
	return cut .. PARTIAL_ELLIPSIS
end

-- The disclosure (card t_b7a9e7a5, requirement 5; REWORDED by card t_d8de0090).
-- When a cosmetic line was IGNORED rather than suppressing, the verdict still
-- appears — and the fact that something was skipped must be AVAILABLE to a
-- caller, never silently implied away. This renders that fact as a short,
-- deterministic suffix, or "" when nothing was skipped, so a caller can append
-- it (or test it) without owning the wording. It is deliberately NOT part of
-- the headline verdict word: the arrow still means exactly what it meant.
--
-- `ignored` is the array parseSide/statTable/evaluate hand back (raw lines, in
-- the order they were met).
--
-- `foreign` (card t_4ff4ebef, OPTIONAL) is the array of composed-but-not-the-item
-- lines the parse set aside. It is a SEPARATE clause — "1 addon line not read" —
-- because a foreign line is not the item's cosmetic prose and must never be
-- added to the cosmetic count. Omitted (nil) by every caller that has no such
-- list, which keeps the cosmetic-only wording byte-identical to what card
-- t_d8de0090 shipped.
--
-- ⚠ The foreign count applies the SAME honesty rule as the cosmetic remainder
-- (the reviewer's re-review of PR #44, item B, 2026-10-18): an entry that DE-COLOURS
-- TO NOTHING is not a line the player could have read, so it never inflates
-- "N addon lines not read". The commit message of 033a743 claimed such an
-- entry "cannot carry a blank" — that claim was wrong: the foreign array is the
-- raw set-aside list, and a colour-only line ("|cffffffff|r") inside a foreign
-- block is recorded there verbatim. The predicate is Verdict.lineWords, the
-- same normaliser that decides whether a cosmetic entry is real, so a line that
-- de-colours to nothing counts in neither clause.
--
-- Shape of the sentence, and why each arm is what it is:
--   ""                                              nothing was set aside at all
--   partial read: "X" ignored                       one cosmetic line, quoted in full
--   partial read: "X" and "Y" ignored               two, both named (t_d8de0090 AC-A)
--   partial read: "X", "Y" and 2 more ignored       more unnamed REAL lines than
--                                                   can be shown. Blank entries
--                                                   in the array are NOT lines
--                                                   and never inflate this
--                                                   remainder (the owner's n1
--                                                   ruling on PR #44: count
--                                                   what was actually set
--                                                   aside, not empty slots).
--   partial read: 3 cosmetic lines ignored          DEGENERATE input only:
--                                                   nothing can be quoted, so
--                                                   there is no remainder to
--                                                   inflate — the count is the
--                                                   honest fallback (card
--                                                   t_d8de0090 AC-C: a skip
--                                                   that cannot be NAMED still
--                                                   reports; "" would claim a
--                                                   full read).
--   partial read: 1 addon line not read             foreign only, counted (t_4ff4ebef)
--   partial read: "X" ignored, 2 addon lines not read
--                                                   both sides set aside — the
--                                                   cosmetic half NAMES the lines
--                                                   (t_d8de0090), the foreign half
--                                                   keeps its COUNT clause
--                                                   (t_4ff4ebef); a line is
--                                                   never reported as both, and
--                                                   the two clauses stay one
--                                                   sentence so they cannot drift.
function Verdict.partialNote(ignored, foreign)
	local ni = 0        -- REAL lines: entries with player words (the n1 count)
	local slots = 0     -- entries the parse set aside, blank or not
	if type(ignored) == "table" then
		for _, line in ipairs(ignored) do
			slots = slots + 1
			if Verdict.lineWords(line) ~= "" then ni = ni + 1 end
		end
	end
	local nf = 0        -- REAL foreign lines: entries with player words (item B)
	if type(foreign) == "table" then
		for _, line in ipairs(foreign) do
			-- The foreign clause's own n1: an entry that de-colours to nothing
			-- is not a line the player could have read, so it never inflates
			-- the count. A foreign list of NOTHING BUT such entries therefore
			-- says nothing at all (falls through to the "" below).
			if Verdict.lineWords(line) ~= "" then nf = nf + 1 end
		end
	end
	-- `slots > 0` is the cosmetic half's own test: every REAL line is also a
	-- slot, so the separate `ni > 0` it used to carry could never change the
	-- answer (the reviewer's re-review note, PR #44).
	if slots == 0 and nf == 0 then return "" end
	-- The cosmetic half NAMES the lines it set aside, in the player's own words
	-- (card t_d8de0090): up to PARTIAL_NAMES_MAX are quoted, the remainder is
	-- stated as a count, and a list that cannot be named at all falls back to
	-- the count rather than claiming a full read. Two counts, by the ruling:
	-- the remainder ("and N more") counts only unnamed REAL lines — a blank
	-- entry is not a line and never inflates it (the owner's n1 ruling on PR
	-- #44) — while the un-namable fallback counts every entry the parse set
	-- aside, because a skip that cannot be named must still report (card
	-- t_d8de0090 AC-C).
	--
	-- ⚠ A blank slot is NOT unreachable from the rendered path (the reviewer's
	-- re-review of PR #44, item A, 2026-10-18). The readers trim WHITESPACE,
	-- and a colour-only line ("|cffffffff|r") is not whitespace: it survives
	-- the trim, de-colours to nothing, is tagged cosmetic by parseLine_, and
	-- lands in `ignored` like any other entry — measured, 3 real cosmetic
	-- lines + one colour-only blank render `..., "B" and 1 more ignored` on
	-- this module and `and 2 more` on the pre-ruling one. That is why the
	-- ruling is pinned TWICE (a rendered-path fixture in upgrade_test.js and
	-- the module-level one), not once: the module pin alone would leave the
	-- reachability of the shape a claim instead of a measurement.
	--
	-- Card t_4ff4ebef: a foreign line is NOT a cosmetic line, so it gets its own
	-- COUNT clause rather than being added to the cosmetic total or named as the
	-- item's prose. With `foreign` nil there is no foreign clause at all, and
	-- the sentence is byte-identical to what card t_d8de0090 shipped. One call
	-- owns both clauses, so the two can never drift apart.
	local parts = {}
	if slots > 0 then
		local named = {}
		for _, line in ipairs(ignored) do
			if #named < PARTIAL_NAMES_MAX then
				local words = Verdict.lineWords(line)
				if words ~= "" then named[#named + 1] = '"' .. words .. '"' end
			end
		end
		if #named == 0 then
			-- Nothing quotable in ANY entry (card t_d8de0090 AC-C): a skip that
			-- cannot be NAMED still reports. This arm counts the ENTRIES the
			-- parse set aside — blank entries are exactly the input it exists
			-- for — while the n1 rule governs the NAMED remainder below, which
			-- cannot fire here (rest would count the same thing twice).
			parts[#parts + 1] = slots .. " cosmetic line"
				.. ((slots == 1) and "" or "s") .. " ignored"
		else
			local rest = ni - #named
			local list
			if rest > 0 then
				-- Commas, not a second "and": "A" and "B" and 2 more reads as a mistake.
				list = table.concat(named, ", ") .. " and " .. rest .. " more"
			elseif #named == 1 then
				list = named[1]
			else
				list = named[1] .. " and " .. named[2]
			end
			parts[#parts + 1] = list .. " ignored"
		end
	end
	if nf == 1 then
		parts[#parts + 1] = "1 addon line not read"
	elseif nf > 1 then
		parts[#parts + 1] = nf .. " addon lines not read"
	end
	return "partial read: " .. table.concat(parts, ", ")
end

-- ==== PERCENT -> RATING: THE ONE CONVERSION POINT (card t_ea404bae) ========
--
-- THE MEASUREMENT. The owner's in-game read on 2026-10-18, on the live
-- WoW: Forever client, via `/dump C_Item.GetItemStats(link)`:
--
--   Reliquary Mantle (ilvl 33)  ITEM_MOD_HIT_RATING_SHORT  = 4
--                               tooltip "+0.4% hit"        => 10 rating = 1% hit
--   Illusionary Rod  (ilvl 39)  ITEM_MOD_CRIT_RATING_SHORT = 14
--                               tooltip "+1.0% crit"       => 14 rating = 1% crit
--
-- Both match the TBC level-60 rating conversions exactly. Two client facts are
-- part of the read and are not to be re-litigated: plain `GetItemStats` prints
-- NOTHING on this client (`C_Item.GetItemStats` works), and there is no
-- `/touchstone stats` command — do not cite one anywhere.
--
-- WHICH UNIT WINS, AND WHY IT IS THE RATING (the reviewer's ruling on this card,
-- 2026-10-19 — it REVERSES the direction the earlier commits on this branch
-- took, and the reversal is deliberate: normalise to RATING, not to percent).
-- The API key is ALWAYS a rating (`ITEM_MOD_*_RATING_SHORT`); there is no
-- percent-valued key. A rating count is the client's own number for the stat,
-- the one that grows as items get better and the one the game actually adds
-- up. The tooltip's percent is that number RENDERED at a scale of ten or
-- fourteen. So the RATING is the unit of record everywhere in this module, and
-- the only number that ever needs arithmetic is the one the tooltip states: a
-- percent, multiplied UP by its word's rating-per-percent constant.
--
-- SO apiStats DOES NO ARITHMETIC AT ALL (the earlier divisor is GONE). Every
-- number the client's stat read contributes to a comparison crosses
-- Verdict.apiStatWord/apiStats below — the module's single raw-key ->
-- stat-word boundary, which runs BEFORE pricing (parseSide, the gates, the
-- weighted layer, all downstream) — and it crosses UNCHANGED: it is already in
-- the unit of record.
--
-- THE ONE CONVERSION SITE is Verdict.ratingFromPercent, called from exactly
-- one place: the four hit/crit sentences in parseLine_. Nothing else in the
-- addon multiplies or divides a stat value by ten or fourteen. The client path
-- is pass-through and the tooltip path is lifted once, which is the whole
-- discipline: a stat table converted twice is as wrong as one never converted,
-- and a weight table that has been quietly rescaled is indistinguishable from
-- a wrong one. Weights.lua is NOT touched by this card (AC-4/AC-7: the weights
-- stay what the packs say; the numbers arriving at them change unit).
--
-- THE ARITHMETIC CONSEQUENCE IS STATED, NOT HIDDEN. A pack's price is now
-- multiplied against a rating count instead of a percent, so a hit or crit
-- term counts ten or fourteen times what the same pair counted before this
-- card. That is what the ruling asks for and what the changed-verdict sweep
-- measures row by row (docs/t_ea404bae-changed-verdicts.txt names every row
-- that moved and why).
--
-- THE SPELL WORDS GET THE SAME FACTOR BECAUSE THEY ARE THE SAME WORDS (card
-- t_9d3273cb). No separate spell constant exists here and none is invented: all
-- four tooltip sentences — melee hit, spell hit, melee crit, spell crit — lift
-- through this one function, and the two client keys that used to answer to a
-- spell word now answer to HIT and CRIT alike. THE FACT is the client's own
-- recap, read verbatim:
--
--   "Spell, melee, and ranged hit chance are combined, as are spell, melee,
--    and ranged critical chance."
--
-- Card t_ea404bae's withdrawn addendum gave those two words no factor and left
-- them on the unconfirmed lists; this card ends that. With one word and one
-- factor a pair whose SAME true value arrives as a client read (rating) on one
-- side and a tooltip (percent) on the other reads EQUAL — which is what the
-- melee halves already did — instead of failing closed on a difference the
-- units invented. Pinned by the mixed-unit case in
-- ChestAdvisor/tests/t_9d3273cb.js.
--
-- DODGE and PARRY are deliberately NOT in this table: nobody has measured their
-- scale, and inventing a factor for them would be an unmeasured claim wearing
-- the same clothes as a measured one. They stay unconfirmed and their guard
-- still fires (AC-5).
Verdict.HIT_RATING_PER_PERCENT  = 10
Verdict.CRIT_RATING_PER_PERCENT = 14
-- Forever 1.60.1 build 70862 combatratings.txt (same scale ForeverDB uses):
Verdict.HASTE_RATING_PER_PERCENT      = 10
-- Expertise has no sourced rating-per-percent on Forever (combatratings.txt
-- has no expertise entry). Percent tooltip text is stored as a percent and
-- compared directly to Wowhead's 6.5% / 14% caps. A rating-only line is
-- accumulated as ExpertiseRating and cannot be clamped.
Verdict.DODGE_RATING_PER_PERCENT      = 12
Verdict.PARRY_RATING_PER_PERCENT      = 15
Verdict.BLOCK_CHANCE_RATING_PER_PERCENT = 5

-- WORD -> rating points per 1% of that word. A tooltip PERCENT times its entry
-- is the RATING count the client's own read returns for the same stat. The
-- whole table: a word absent from it carries no factor. Hit, crit, haste,
-- dodge, parry and block chance all lift here so a "by 1%" sentence and a
-- "+N Rating" line land on the same raw-rating unit the packs price.
-- Expertise is absent: there is no sourced factor, so a percent sentence
-- stays a percent. Read by ratingFromPercent ONLY.
Verdict.PERCENT_TO_RATING = {
	Hit         = Verdict.HIT_RATING_PER_PERCENT,
	Crit        = Verdict.CRIT_RATING_PER_PERCENT,
	Haste       = Verdict.HASTE_RATING_PER_PERCENT,
	Dodge       = Verdict.DODGE_RATING_PER_PERCENT,
	Parry       = Verdict.PARRY_RATING_PER_PERCENT,
	BlockChance = Verdict.BLOCK_CHANCE_RATING_PER_PERCENT,
}

-- ── CARD t_9d718a77: THE SPELLINGS THE CLIENT PRINTS FOR THOSE WORDS ──────
-- The equal-damage-per-second gate reads Hit and Crit through
-- Verdict.beyondResolution, which compares the keys of PERCENT_TO_RATING. That
-- gate was STARVED: the parser placed exactly ONE spelling of each word — the
-- bare "+12 Crit" / "+10 Hit" the generic clause already read — and every other
-- shape the client prints fell into the unknown bucket, where the weapon path
-- DROPPED it instead of refusing. Measured at c7b7997 on a Retribution paladin,
-- both weapons at 10.00 dps with only the candidate's stat line changing:
--
--     +12 Crit Rating   -> NOT_UPGRADE — equal weapon damage per second (10.00)
--     +1% Crit          -> NOT_UPGRADE — equal weapon damage per second (10.00)
--     +1% Hit           -> NOT_UPGRADE — equal weapon damage per second (10.00)
--     +12 Crit          -> UNKNOWN — cannot judge: Crit (the two weapons tie ...)
--
-- So a confident "the same" went out over lines the parse never understood.
--
-- WHAT IS ACCEPTED, AND WHY EACH ONE. The two WORDS are the scale's own, so the
-- only question this table answers is which tooltip text names them:
--
--   "crit", "hit"                     — already read by the generic "+N Word"
--                                      clause; listed so this table is the WHOLE
--                                      vocabulary of the two words rather than a
--                                      patch beside one spelling.
--   "crit rating", "hit rating"       — the client's own key names (the verified
--                                      ITEM_MOD_HIT_RATING / ITEM_MOD_CRIT_RATING
--                                      and their MELEE/RANGED/SPELL siblings), and
--                                      the rendered lines this repo has captured:
--                                      "4 Hit Rating" / "6 Crit Rating" on the
--                                      owner's Reliquary Mantle read.
--   "critical strike", "critical
--    strike rating"                  — the client's own word for the stat, taken
--                                      from its own sentence ("...get a critical
--                                      strike...") which this file already reads,
--                                      plus the same rating suffix.
--   the melee/ranged/spell prefixes  — the remaining verified key stems
--                                      (ITEM_MOD_HIT_MELEE_RATING, …_RANGED_…,
--                                      …_SPELL_…, and CRIT likewise). They are the
--                                      same stat by the client's own recap, quoted
--                                      verbatim under WEIGHT_KEYS ("Spell, melee,
--                                      and ranged hit chance are combined, as are
--                                      spell, melee, and ranged critical chance"),
--                                      which is also why ITEM_STAT_KEYS folds all
--                                      eight keys onto the two words.
--
-- A PERCENT sign on the line ("+1% Crit") is the same stat in the unit the
-- tooltip prints, and the rating-tip clause lifts it through the ONE
-- conversion (ratingFromPercent) exactly as the four sentences do.
--
-- WHAT IS NOT ACCEPTED, DELIBERATELY: every other spelling — the spell/melee
-- prefixes, "chance to", a school-scoped variant, and "Weapon Skill" above all.
-- The first group has no measured rendering on this tree, and Weapon Skill is a
-- WORD THE SCALE DOES NOT CARRY: pricing it is a vocabulary decision for the
-- owner (card t_9d718a77's question, not its step). An unlisted spelling does
-- not go quiet any more — the rating-tip clause below places nothing, the line
-- stays digit-bearing and unplaceable, and the equal claim REFUSES on it (see
-- the unread-line rule in compareWeapon). Widening this table is therefore
-- always safe; narrowing it can only produce an honest UNKNOWN.
Verdict.STAT_TIP_SPELLINGS = {
	["crit"]                         = "Crit",
	["crit rating"]                  = "Crit",
	["critical strike"]              = "Crit",
	["critical strike rating"]       = "Crit",
	["melee crit rating"]            = "Crit",
	["ranged crit rating"]           = "Crit",
	["spell crit rating"]            = "Crit",
	["spell critical strike rating"] = "Crit",
	["hit"]                          = "Hit",
	["hit rating"]                   = "Hit",
	["melee hit rating"]             = "Hit",
	["ranged hit rating"]            = "Hit",
	["spell hit rating"]             = "Hit",
}

-- THE conversion: a tooltip's percent -> the rating unit of record. ONE
-- definition, ONE multiply, and TWO call sites, both inside parseLine_ (the four
-- sentence clauses and the rating-tip clause card t_9d718a77 added). A
-- word with no entry passes through untouched, which is why this is not a
-- second branch a future reader has to keep in sync with a table.
--
-- Public on purpose: the battery drives the table directly, and the
-- non-vacuity leg can clear PERCENT_TO_RATING or the function and watch the
-- numbers go back to the percent the tooltip printed. rawget, so a cleared
-- table is a real absence rather than a stale copy.
function Verdict.ratingFromPercent(word, pct)
	local scale = rawget(Verdict, "PERCENT_TO_RATING")
	local factor = type(scale) == "table" and rawget(scale, word) or nil
	if type(factor) == "number" then return pct * factor end
	return pct
end

-- ── CARD t_43f8cd6f (item 2): THE TOOLTIP'S RESOLUTION ──────────────────────
-- The client prints these percentages to ONE decimal, so a tooltip percent is
-- the item's rating count rendered at 0.1% resolution — and the inverse above
-- (percent x factor) can therefore land up to HALF A STEP away from the count
-- the client reports for the SAME item. Measured on the owner's scale:
--
--   12 crit rating renders "0.9%" and lifts back to 12.6   (0.6 out)
--   10 crit rating renders "0.7%" and lifts back to  9.8   (0.2 out)
--   14 crit rating renders "1.0%" and lifts back to 14.0   (exact)
--
-- Only multiples of 14 round-trip exactly, which is why the mixed-unit case at
-- 14 (N12) was green while the defect was live: it was the one value where the
-- error was zero. Once HIT and CRIT retired from the unconfirmed lists that
-- error is PRICED, and 0.6 rating x the pack's 0.9 turned a weighted margin of
-- 0.4546 into 0.5033 — TRADE_OFF flipped to UPGRADE for two readings of the
-- SAME item. Two readings of one item must not disagree.
--
-- THE RULE (the reviewer's, card t_43f8cd6f): a HIT or CRIT difference SMALLER than
-- one tooltip step counts as LEVEL. The tolerance swallows the QUANTISATION,
-- never a real gap: a full step or more is still a difference, and the two
-- client-read counts are integers, so a real 12-vs-13 is 1.0 and still counts.
--
-- WHERE IT IS HONOURED — and where it is NOT (card t_645c7ae6 rewrote this
-- paragraph: it named ONE site and claimed Hit and Crit are in no order. BOTH
-- claims were false, and the second one was already false when it was written).
--
--   * Verdict.weightedScore — the weighted layer's own subtraction. It levels
--     the term before multiplying, so a sub-step difference contributes 0.
--   * Verdict.termSign — the proof's single direction rule, read by
--     Verdict.dominance AND by the two gate-9 loops that word its answer. Since
--     card t_da23ec75 the proof decides on the pack's PRICED words, so Hit and
--     Crit are proof terms whenever the pair's own pack prices them; the
--     tolerance has to apply there too, or the proof decides a pair on 0.6 of
--     rounding that the weighted layer forgives one call later.
-- BOTH sites read Verdict.levelWithinResolution. One epsilon, one helper — a
-- second copy is how the two would drift apart.
--
--   * Hit and Crit DO sit in an order, on the WEAPON path. The terms
--     Verdict.tankWeaponOrder builds are the tank pack's priced words, so a
--     Shaman tank weapon pair is compared on [Strength, Agility, Stamina, Hit,
--     Crit, AttackPower, WeaponDps] — measured on this tree, not inferred from
--     Verdict.ORDERS, which is what the old paragraph read. That path reaches
--     Verdict.dominance directly (compareWeapon), and it is the second reason
--     the tolerance lives in termSign rather than at one caller.
--
--   * Dodge and Parry carry no factor, so they introduce no rounding: a word
--     with no resolution is never "levelled" by this helper (it returns false),
--     which leaves their exact comparison — and the fail-closed guard behind
--     them — exactly as it was. Hit and Crit DO carry factors (10 and 14 rating
--     per 1%), so a hit or crit difference is levelled here, on both the melee
--     and the spell sentence, which is the whole point of the tolerance.
--
-- The rule is declared HERE, beside the conversion that creates the
-- uncertainty, and honoured at the two comparisons above through the one
-- helper.
Verdict.TOOLTIP_HALF_STEP_PERCENT = 0.05 -- one decimal place: half of 0.1%

-- word -> the +/- uncertainty, in rating points, of a tooltip-derived value of
-- that word; nil for a word with no factor (a percent that passed through
-- unchanged was never rounded, so there is nothing to forgive).
function Verdict.ratingResolution(word)
	local scale = rawget(Verdict, "PERCENT_TO_RATING")
	local factor = type(scale) == "table" and rawget(scale, word) or nil
	local half = rawget(Verdict, "TOOLTIP_HALF_STEP_PERCENT")
	if type(factor) ~= "number" or type(half) ~= "number" then return nil end
	return factor * half
end

-- Are two values of `word` LEVEL as far as the tooltip's resolution can tell?
-- Absent reads as 0 — the same convention Verdict.unconfirmedDifference and
-- weightedScore already use. A word with no resolution is never "levelled"
-- here: its caller's own exact comparison stands.
function Verdict.levelWithinResolution(word, c, e)
	local eps = Verdict.ratingResolution(word)
	if type(eps) ~= "number" then return false end
	local cn = type(c) == "number" and c or 0
	local en = type(e) == "number" and e or 0
	local d = cn - en
	if d < 0 then d = -d end
	return d < eps
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
-- Returns: words — stat word -> number, for the keys we have verified; number
--                  values only (a verified key with a non-number value names
--                  nothing — the client's silence, never a guess)
--          named — the set of words it named (so a caller can ask "does the API
--                  name a stat the text parse did not capture?")
--          unmapped — (card t_795eee9e, AC-C) the string keys we could NOT
--                  verify, sorted for a repeatable reason, or nil when the
--                  read carries none. House doctrine (module line 20): a stat
--                  word neither side can classify is UNKNOWN, never a
--                  fabricated 0 — this list is how evaluate() refuses to
--                  judge on the stats it does know while the client names a
--                  stat it does not (never a silent drop, never a zero).
-- A non-table (nil, a string, a secret sentinel) returns nil, nil, nil: the
-- caller's byte-identical-to-today path (AC-B).
function Verdict.apiStats(raw)
	if type(raw) ~= "table" then return nil, nil, nil end
	local out, named = {}, {}
	local unmapped = {}
	for key, value in pairs(raw) do
		local word = Verdict.apiStatWord(key)
		if word ~= nil then
			if type(value) == "number" then
				-- Card t_ea404bae (the reviewer's ruling, 2026-10-19): the client's
				-- number for these words is a RATING COUNT, and a rating is the
				-- unit of record — it is passed through UNCHANGED. The one
				-- conversion in this module runs the OTHER way, on the tooltip's
				-- percent (ratingFromPercent above), so there is deliberately no
				-- arithmetic here: a stat converted twice is as wrong as one
				-- never converted.
				out[word] = value
				named[word] = true
			end
		elseif type(key) == "string" then
			-- Card t_795eee9e, AC-C: a key the client returned that this
			-- module has not verified is an UNVERIFIED STAT. It is recorded,
			-- not dropped: the impure edge ships it with the words and
			-- evaluate() turns it into the UNKNOWN answer for the pair.
			unmapped[#unmapped + 1] = key
		end
	end
	table.sort(unmapped)
	if #unmapped == 0 then unmapped = nil end
	return out, named, unmapped
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
--                            suppression (gate C1: the B2 gate must not
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
-- default to unknown (gate C1, "suppress anything unconfirmed"). The
-- item NAME line (free text — no content pattern can enumerate item
-- names) is handled positionally by parseSide, where the scan path's
-- line list starts at the name on a real client.
-- Card t_4e1e1b1d (DD-2): the six schools the packs price a damage term for.
-- A FIXED list, not `(%a+)` acceptance: the sentence's school slot is read into
-- a word only when it is one of these, so "Increases damage done by Undead
-- spells…" (or any future spelling) stays unplaceable and suppresses instead of
-- being guessed at — the card's AC-A near-miss rule.
local SCHOOL_POWER_WORD = {
	holy   = "HolyPower",
	fire   = "FirePower",
	frost  = "FrostPower",
	shadow = "ShadowPower",
	nature = "NaturePower",
	arcane = "ArcanePower",
}

-- ---- The weapon TYPE LINE's grammar (card t_1677cd39) -----------------------
--
-- ONE grammar, spent by TWO readers, because the second one decides a verdict:
--
--   1. `parseLine_` below classifies a weapon's type line as STRUCTURAL CHROME
--      (it is the item's own chrome, not a stat) — the shipped behaviour;
--   2. `Verdict.weaponTypeLine` / `Verdict.weaponFamily` read the SUBTYPE out of
--      the same line, because a spec's weapon policy (added by this card) has to
--      know WHAT KIND of weapon a candidate is before the comparator prices it.
--
-- A second copy of this list is the failure the repo already paid for once (two
-- strip copies drifting, card t_02877bb4): a classifier that stopped recognising
-- a subtype would silently stop the family reader too, and the two would answer
-- different questions about the same line. So the vocabulary lives HERE, once,
-- and both readers spend it. The list is the client's own subtype vocabulary as
-- this repo has proven it (the seven schools aside, the words are the ones the
-- client prints on a weapon type line: "Main Hand  Dagger", "Two-Hand  Sword").
local WEAPON_TYPE_SLOTS = {
	{ plain = "ranged",    pat = "ranged" },
	{ plain = "main hand", pat = "main hand" },
	{ plain = "two-hand",  pat = "two%-hand" },
	{ plain = "one-hand",  pat = "one%-hand" },
	-- The off-hand weapon's own type line ("Off Hand  Dagger"). It is NOT a
	-- Tier C main-hand row (Verdict.WEAPON_TOKENS deliberately excludes the
	-- token), but its line is the same shape and the family reader must be able
	-- to place it: a rogue's off-hand weapon is judged by this card, and its
	-- subtype is the same fact about the same item.
	{ plain = "off hand",  pat = "off hand" },
}

local WEAPON_TYPE_SUBTYPES = {
	"wand", "bow", "gun", "crossbow", "dagger", "sword", "mace",
	"staff", "polearm", "axe", "thrown", "miscellaneous",
	"fist weapon",
	-- (card t_d5c915f2) "Fishing Pole" is the subtype the client prints on a
	-- two-hand fishing pole ("Two-Hand  Fishing Pole"). It was the one weapon
	-- subtype in the owner's vocabulary that this list did not carry, so the
	-- TYPE LINE fell to the cosmetic path and every pole hover disclosed a
	-- "partial read: \"Two-Hand Fishing Pole\" ignored" that was the item's own
	-- chrome. Same clause as the rest, same narrowness: the subtype word plus
	-- the slot word, nothing wider.
	"fishing pole",
}

-- The grammar's ONE matcher. Input is the line as `parseLine_` normalises it
-- (trimmed, lower-cased, NOT de-coloured — the classifier has always matched
-- the raw lower-cased line, and a second input here would let the two readers
-- disagree about the same line).
--   -> slot word ("main hand" | "one-hand" | "two-hand" | "ranged" | "off hand"), subtype word | nil
--   -> nil, nil when the line is not a weapon type line at all
-- A BARE slot word ("Main Hand", the owner's live mace line) returns the slot
-- and a nil subtype: the item is a weapon, its family is genuinely unreadable
-- on this tooltip. The caller must not invent a family for it.
local function weaponTypeLine(low)
	if type(low) ~= "string" then return nil, nil end
	for _, slot in ipairs(WEAPON_TYPE_SLOTS) do
		if low == slot.plain then return slot.plain, nil end
		for _, sub in ipairs(WEAPON_TYPE_SUBTYPES) do
			if low:match("^" .. slot.pat .. "%s+" .. sub .. "$") then
				return slot.plain, sub
			end
		end
	end
	return nil, nil
end
Verdict.weaponTypeLine = weaponTypeLine
-- The subtype vocabulary, exposed the same way weaponDamageSchools is: a test
-- enumerates the SHIPPED list rather than a copy of it (card t_1677cd39).
Verdict.weaponSubtypes = WEAPON_TYPE_SUBTYPES

-- WHAT KIND of weapon is this? Read off the item's own type line, through the
-- SAME grammar the classifier above spends (card t_1677cd39).
--   -> the subtype word ("dagger", "sword", "mace", "fist weapon", …), or
--   -> nil: no weapon type line on this tooltip, OR the line is the BARE slot
--      word ("Main Hand") the client also prints (the owner's live mace line,
--      pinned in this file). Both mean "this tooltip does not tell us the
--      family", and the caller must not guess one.
function Verdict.weaponFamily(lines)
	return select(2, Verdict.weaponType(lines))
end

-- The type line as (slot word, subtype), read off an item's own lines through
-- the SAME grammar (card t_1677cd39). nil, nil when the tooltip carries no
-- weapon type line; a bare slot word returns slot, nil (family unreadable).
function Verdict.weaponType(lines)
	if type(lines) ~= "table" then return nil, nil end
	for _, line in ipairs(lines) do
		if type(line) == "string" then
			local low = line:gsub("^%s+", ""):gsub("%s+$", ""):lower()
			local slot, subtype = weaponTypeLine(low)
			if slot ~= nil then return slot, subtype end
		end
	end
	return nil, nil
end

local function parseLine_(line)
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
	-- structural when the card rule says Set: must suppress (AC-E8, the gate
	-- run-63).
	local plain = deColour_(low)
	-- "+12 Agility" -> num + word. The prefix class is only signs and
	-- whitespace (never digits) so the captured number is the whole value.
	-- A chest's bare armor line ("12 Armor") lands here too and reads as
	-- the known stat Armor — inert in practice, since no order in ORDERS
	-- consumes Armor, and never a suppression trigger.
	local function skillNoun(w)
		if type(w) ~= "string" then return nil end
		local r = w:lower():gsub("%s+$", ""):gsub("%.$", "")
		if r == "swords" or r == "axes" or r == "maces" or r == "daggers"
			or r == "polearms" or r == "staves" or r == "bows" or r == "guns"
			or r == "crossbows" or r == "thrown" or r == "wands" or r == "unarmed"
			or r == "skill" then
			return "WeaponSkill"
		end
		return nil
	end
	local num, word = trimmed:match("^%s*[%+%-%s]*(%d+)%s+(%a+)$")
	if num and word then
		-- "+N Expertise" is a short rating line (same family as
		-- "+N Hit"), not a percent. ratingWordOf below also maps
		-- the multi-word form; this single-word matcher would
		-- otherwise keep the raw word "Expertise".
		local mapped = skillNoun(word)
		if not mapped and word:lower() == "expertise" then
			mapped = "ExpertiseRating"
		end
		return tonumber(num), (mapped or word)
	end
	-- Multi-word rating and weapon-DPS lines the single-word "+N Word"
	-- matcher cannot see. A number already printed in RATING units is
	-- returned as-is — ratingFromPercent is only for the percent
	-- sentences below (14 crit rating = 1%, 10 hit rating = 1%).
	local function ratingWordOf(rest)
		if type(rest) ~= "string" then return nil end
		rest = rest:lower():gsub("%s+$", ""):gsub("%.$", "")
		if rest == "hit rating" or rest == "hit" then return "Hit" end
		if rest == "crit rating" or rest == "critical strike rating"
			or rest == "critical rating" or rest == "crit" then
			return "Crit"
		end
		if rest == "defense rating" or rest == "defence rating"
			or rest == "defense" or rest == "defence" then
			return "Defense"
		end
		if rest == "dodge rating" or rest == "dodge" then return "Dodge" end
		if rest == "parry rating" or rest == "parry" then return "Parry" end
		if rest == "attack power" then return "AttackPower" end
		if rest == "ranged attack power" then return "RangedAttackPower" end
		if rest == "haste rating" or rest == "haste" then return "Haste" end
		if rest == "expertise rating" then return "ExpertiseRating" end
		if rest == "expertise" then return "ExpertiseRating" end
		if rest == "block rating" or rest == "block chance rating"
			or rest == "block chance" then
			return "BlockChance"
		end
		if rest == "bonus armor" then return "BonusArmor" end
		if rest == "spell power" or rest == "spellpower" then return "SpellPower" end
		if rest == "spell damage" or rest == "spell dmg" then return "SpellDamage" end
		-- DD-2's words, not this pack's older spellings: a "+34 Healing" line
		-- and DD-2's "…healing done by up to 34" sentence must land on ONE key,
		-- or the tier that prices it sees only half the item.
		if rest == "healing power" or rest == "healing" then return "Healing" end
		if rest == "spell penetration" then return "SpellPenetration" end
		if rest == "holy spell damage" or rest == "holy damage" then return "HolyPower" end
		if rest == "fire spell damage" or rest == "fire damage" then return "FirePower" end
		if rest == "frost spell damage" or rest == "frost damage" then return "FrostPower" end
		if rest == "shadow spell damage" or rest == "shadow damage" then return "ShadowPower" end
		if rest == "nature spell damage" or rest == "nature damage" then return "NaturePower" end
		if rest == "arcane spell damage" or rest == "arcane damage" then return "ArcanePower" end
		if rest == "weapon skill" or rest == "weapon skill rating" then
			return "WeaponSkill"
		end
		if rest:match("%f[%a]skill%f[%A]") or rest == "swords" or rest == "axes"
			or rest == "maces" or rest == "daggers" or rest == "polearms"
			or rest == "staves" or rest == "fist weapons" or rest == "bows"
			or rest == "guns" or rest == "crossbows" or rest == "thrown"
			or rest == "wands" or rest == "unarmed"
			or rest:match("^two[%-%s]handed%s+%a+") then
			return "WeaponSkill"
		end
		return nil
	end
	local rnum, rrest = trimmed:match("^%s*[%+%-%s]*(%d+%.?%d*)%s+(.+)$")
	if rnum and rrest then
		local rw = ratingWordOf(rrest)
		if rw then return tonumber(rnum), rw end
	end
	-- ── card t_9d718a77: THE RATING-TIP SPELLINGS OF THE TWO SCALE WORDS ────
	-- The generic clause above reads "+12 Crit" / "+10 Hit" and nothing else,
	-- so every OTHER spelling the client prints for the same two words —
	-- "+12 Crit Rating", "+1% Crit", "+10 Hit Rating" — parsed as nothing. On
	-- the armour path that refused the item (the line was digit-bearing and
	-- unplaceable); on the weapon path's equal-DPS branch it did NOT, and the
	-- pair was called "the same" over a number that had never been read (the
	-- measurement is quoted under Verdict.STAT_TIP_SPELLINGS above).
	--
	-- Two shapes, one table. A line that carries a PERCENT is the tooltip's own
	-- unit and lifts through Verdict.ratingFromPercent; a line that carries a
	-- bare count is already the rating the client's read returns. Which words
	-- each shape may name is the table's business, never this clause's — so
	-- the vocabulary is data a card can enumerate, and a spelling the table does
	-- not carry falls through to the unplaceable tail below (fail-closed, and
	-- since this card no longer silent on the weapon path). rawget so a cleared
	-- table is a real absence, the same reason PERCENT_TO_RATING uses it.
	--
	-- READ AGAINST `plain`, NOT `stat_sentence`, AND DELIBERATELY: the "Equip:"
	-- prefix belongs to the PROC channel — "Equip: +3 Crit" is an on-equip effect
	-- the client prints, not a stat line, and the clause below the proc reader is
	-- where this one belongs (t_02877bb4 AC-C and t_ed71a583 AC-C both pin that
	-- reading, and the first cut of this clause broke them by lifting it). A stat
	-- line prints as "+12 Crit Rating", unprefixed.
	local tipSpellings = rawget(Verdict, "STAT_TIP_SPELLINGS")
	if type(tipSpellings) == "table" then
		local tipPct, tipPctTail = plain:match("^%+?%s*(%d+%.?%d*)%%%s+(.+)$")
		if tipPct then
			local tipWord = rawget(tipSpellings, tipPctTail)
			if tipWord ~= nil then
				return Verdict.ratingFromPercent(tipWord, tonumber(tipPct)), tipWord
			end
		end
		local tipNum, tipNumTail = plain:match("^%+?%s*(%d+)%s+(.+)$")
		if tipNum then
			local tipWord = rawget(tipSpellings, tipNumTail)
			if tipWord ~= nil then return tonumber(tipNum), tipWord end
		end
	end
	-- proc line:  "Equip: +X Foo"
	-- Multi-word "Equip: +N Hit Rating" first (a trailing word would
	-- otherwise be captured as the proc form "Equip:Hit").
	local epnum, eprest = trimmed:match("^%s*Equip:%s*%+%s*(%d+%.?%d*)%s+(.+)$")
	if epnum and eprest then
		local ew = ratingWordOf(eprest)
		if ew then return tonumber(epnum), ew end
	end
	-- trailing period is still a Strength/etc. proc, not a suppression).
	local pnum, pword = trimmed:match("^%s*Equip:%s*%+%s*(%d+)%s+(%a+)")
	if pnum and pword then
		return nil, "Equip:" .. pword
	end
	-- "Adds X" style lines, if the client ever uses them here.
	local an, aw = trimmed:match("^%s*Adds%s*(%d+)%s+(%a+)")
	if an and aw then return tonumber(an), aw end
	-- Weapon DPS: "(12.5 damage per second)" or "12.5 Damage Per Second".
	local dps = plain:match("%((%d+%.?%d*)%s+damage per second%)")
		or plain:match("^(%d+%.?%d*)%s+damage per second%.?$")
	if dps then return tonumber(dps), "WeaponDps" end
	local spd = plain:match("^speed%s*:?%s*(%d+%.?%d*)$")
		or plain:match("^(%d+%.?%d*)%s+speed$")
	if spd then
		local v = tonumber(spd)
		-- Parse disambiguator, not a scoring weight: Classic weapon
		-- tooltips print speeds in about 1.00–4.00. Values outside
		-- 0.5–10 are not weapon speeds (a level, a sell price, etc.).
		if v and v >= 0.5 and v <= 10 then return v, "WeaponSpeed" end
	end
	local skillPlain = plain:gsub("^equip:%s*", ""):gsub("%s*%.$", "")
	local skn = skillPlain:match("^increases your skill with [%a%-%s]+ by (%d+)$")
	if skn then return tonumber(skn), "WeaponSkill" end
	-- ── card t_3cdbb70a (DD-1): the HIT and CRIT sentences ────────────────
	-- The client prints these four phrasings, and until this card NOT ONE of
	-- them was placeable: they carry a number, so they suppressed the item
	-- ("cannot classify: Improves your chance to hit with spells by 1%.") and
	-- every caster that read one got no verdict at all until the client's own
	-- stat read happened to name the key — which is exactly the state DD-2
	-- describes for the healing/school lines it owns.
	--
	-- ALL FOUR sentences are ONE stat each, as of card t_9d3273cb: the two
	-- spell spellings and the two bare (melee/ranged) spellings read the SAME
	-- two words, so each of the four states the PERCENT and each is lifted UP
	-- to the rating unit of record by Verdict.ratingFromPercent — THE one
	-- conversion site in this module (card t_ea404bae, the reviewer's ruling of
	-- 2026-10-19). "Improves your chance to hit by 0.4%." is 4 hit rating, the
	-- number the client's own C_Item read returns for the same item, so the two
	-- paths agree and the comparator never has to know which one a value came
	-- from.
	--
	-- THE TWO SPELL SENTENCES USED NOT TO BE CONVERTED (card t_43f8cd6f, item 3
	-- pinned them to MAIN'S OWN SHAPE — `(%d+)`, no decimal, the number returned
	-- as read). That is HISTORY as of card t_9d3273cb: the same two words now
	-- stand behind all four sentences, so the same one conversion lifts all four
	-- (see the block above). The reverted widening that card 43f8cd6f refused
	-- was the split's own unit leaking into the spell half; with the split gone
	-- there is no second unit to leak.
	-- CARD t_9d3273cb NOW WIDENS THEM, deliberately and in the open: the four
	-- sentences read ONE hit word and ONE crit word, so they must share ONE
	-- shape. Leaving the spell halves at `%d+` would let "+0.4% hit" through
	-- while refusing "+0.4% hit with spells" — the same stat, the same number,
	-- refused for the spelling of the sentence it arrived in. Both halves read
	-- `%d+%.?%d*` and both lift through the one conversion above.
	--
	-- SHAPES ARE EXACT AND NARROW (the card's OUT OF SCOPE: "any text-line
	-- shape beyond the hit and crit wordings above"). An unrecognised spelling
	-- — "improves your chance to critically hit with spells", a school-scoped
	-- variant, "chance to hit with your spells" — falls through to the unknown
	-- bucket and still suppresses, which is the fail-closed direction. The
	-- optional "equip:" prefix and the trailing period are the only latitude:
	-- both spellings appear on real tooltips and neither changes the meaning.
	-- CARD t_ea404bae, THE DECIMAL PERCENT. the mixed-unit criterion the reviewer set
	-- on the gate for this head is still load-bearing: the client renders
	-- these sentences with a
	-- DECIMAL percent where the reading is not a whole number — the owner's own
	-- Mantle is "+0.4% hit" — while the client's stat read
	-- for the same item is a RATING. A parser that only accepted `%d+` could not
	-- read the tooltip half at all, so the same true value came out as a
	-- difference — or worse, as unplaceable text that suppressed the pair. The
	-- number is read as `%d+%.?%d*`: a whole number still reads exactly as
	-- before ("by 1%" is 1), and the client's decimal spelling reads as the
	-- number it prints ("by 1.0%" is 1, "by 0.4%" is 0.4) BEFORE the factor
	-- lifts it to 14 or 4. The SHAPE is unchanged — same anchor, same
	-- wordings, same optional "equip:" prefix and trailing period — so every
	-- spelling this clause used to refuse is still refused.
	--
	-- THE DECIMAL IS A QUANTISED READING, and the quantisation is handled ONCE
	-- (card t_43f8cd6f, item 2 — see TOOLTIP_HALF_STEP_PERCENT beside the
	-- conversion above): a one-decimal percent cannot recover the client's
	-- exact rating count, so the comparison treats a difference smaller than
	-- one tooltip step as LEVEL instead of pricing the tooltip's rounding.
	-- (card t_9d718a77: the rating-tip clause above reads `plain`, not this view,
	-- because the "Equip:" prefix belongs to the proc channel — so nothing
	-- outside these four sentences needs the sentence normalisation.)
	local stat_sentence = plain:gsub("^equip:%s*", ""):gsub("%s*%.$", "")
	-- ALL FOUR clauses read `%d+%.?%d*` and all four lift through
	-- Verdict.ratingFromPercent — the ONE conversion site. Card t_9d3273cb: the
	-- two SPELL sentences read the SAME two words as the two melee sentences.
	-- They were never a different stat (the client's recap, quoted under
	-- WEIGHT_KEYS), so they were never a different word; holding them on a
	-- separate key is what let a caster's spell-crit item price against a key
	-- that carried a number while the crit key carried 0.
	--
	-- THE SHAPE IS ONE SHAPE, decimal included (card t_43f8cd6f had deliberately
	-- kept these two clauses at origin/main's `%d+` because their retirement was
	-- out of its scope). Unifying the WORDS without unifying the SHAPE would
	-- leave "+0.4% hit" readable and "+0.4% hit with spells" unplaceable — the
	-- same stat, refused on one spelling. Pinned by W6 of
	-- ChestAdvisor/tests/t_9d3273cb.js.
	local hitp = stat_sentence:match("^improves your chance to hit with spells by (%d+%.?%d*)%%$")
	if hitp then return Verdict.ratingFromPercent("Hit", tonumber(hitp)), "Hit" end
	local critp = stat_sentence:match("^improves your chance to get a critical strike with spells by (%d+%.?%d*)%%$")
	if critp then return Verdict.ratingFromPercent("Crit", tonumber(critp)), "Crit" end
	local meleehitp = stat_sentence:match("^improves your chance to hit by (%d+%.?%d*)%%$")
	if meleehitp then return Verdict.ratingFromPercent("Hit", tonumber(meleehitp)), "Hit" end
	local meleecritp = stat_sentence:match("^improves your chance to get a critical strike by (%d+%.?%d*)%%$")
	if meleecritp then return Verdict.ratingFromPercent("Crit", tonumber(meleecritp)), "Crit" end
	-- Rating-unit sentences (already a rating, not a percent — do not lift).
	local defn = stat_sentence:match("^increases your defense rating by (%d+%.?%d*)$")
		or stat_sentence:match("^increases defense rating by (%d+%.?%d*)$")
	if defn then return tonumber(defn), "Defense" end
	local hitr = stat_sentence:match("^increases your hit rating by (%d+%.?%d*)$")
		or stat_sentence:match("^improves your hit rating by (%d+%.?%d*)$")
	if hitr then return tonumber(hitr), "Hit" end
	-- Lua 5.1 has no alternation groups of unequal length; spell both forms out.
	local critr = stat_sentence:match("^increases your critical strike rating by (%d+%.?%d*)$")
		or stat_sentence:match("^increases your crit rating by (%d+%.?%d*)$")
	if critr then return tonumber(critr), "Crit" end
	local haster = stat_sentence:match("^increases your haste rating by (%d+%.?%d*)$")
		or stat_sentence:match("^improves your haste rating by (%d+%.?%d*)$")
	if haster then return tonumber(haster), "Haste" end
	local expr = stat_sentence:match("^increases your expertise rating by (%d+%.?%d*)$")
		or stat_sentence:match("^improves your expertise rating by (%d+%.?%d*)$")
	if expr then return tonumber(expr), "ExpertiseRating" end
	-- Forever Expertise tooltip text, observed on real items (e.g.
	-- Warden's Signet of Vigilance): "Equip: Reduces the chance for
	-- your attacks to be dodged or parried by 1.0%." The same idea
	-- appears as "Reduces chance to be Dodged or Parried by 1.0%" and
	-- on tank set bonuses as "Reduces the chance for your melee
	-- attacks to be Dodged or Parried by 1.2%." Store the percent
	-- directly (no invented rating factor) so it can be compared to
	-- Wowhead's 6.5% / 14% caps. The short "+N Expertise" line is a
	-- rating (like "+N Hit") and is handled above as ExpertiseRating.
	local expp = stat_sentence:match("^reduces the chance for your attacks to be dodged or parried by (%d+%.?%d*)%%$")
		or stat_sentence:match("^reduces the chance for your melee attacks to be dodged or parried by (%d+%.?%d*)%%$")
		or stat_sentence:match("^reduces chance to be dodged or parried by (%d+%.?%d*)%%$")
		or stat_sentence:match("^increases your expertise by (%d+%.?%d*)%%$")
		or stat_sentence:match("^improves your expertise by (%d+%.?%d*)%%$")
		or stat_sentence:match("^increases expertise by (%d+%.?%d*)%%$")
	if expp then return tonumber(expp), "Expertise" end
	local dodger = stat_sentence:match("^increases your dodge rating by (%d+%.?%d*)$")
	if dodger then return tonumber(dodger), "Dodge" end
	local parryr = stat_sentence:match("^increases your parry rating by (%d+%.?%d*)$")
	if parryr then return tonumber(parryr), "Parry" end
	local blockr = stat_sentence:match("^increases your shield block rating by (%d+%.?%d*)$")
		or stat_sentence:match("^increases your block rating by (%d+%.?%d*)$")
	if blockr then return tonumber(blockr), "BlockChance" end
	-- Percent sentences for the remaining combat ratings, lifted through
	-- ratingFromPercent (dodge 12, parry 15, block chance 5, haste 10).
	-- Expertise percent is handled above and is NOT lifted.
	local dodgep = stat_sentence:match("^increases your chance to dodge by (%d+%.?%d*)%%$")
		or stat_sentence:match("^improves your chance to dodge by (%d+%.?%d*)%%$")
	if dodgep then return Verdict.ratingFromPercent("Dodge", tonumber(dodgep)), "Dodge" end
	local parryp = stat_sentence:match("^increases your chance to parry by (%d+%.?%d*)%%$")
		or stat_sentence:match("^improves your chance to parry an attack by (%d+%.?%d*)%%$")
		or stat_sentence:match("^increases your chance to parry an attack by (%d+%.?%d*)%%$")
	if parryp then return Verdict.ratingFromPercent("Parry", tonumber(parryp)), "Parry" end
	local blockp = stat_sentence:match("^increases your chance to block attacks with a shield by (%d+%.?%d*)%%$")
		or stat_sentence:match("^increases your chance to block by (%d+%.?%d*)%%$")
	if blockp then return Verdict.ratingFromPercent("BlockChance", tonumber(blockp)), "BlockChance" end
	local hastep = stat_sentence:match("^increases your haste by (%d+%.?%d*)%%$")
		or stat_sentence:match("^improves your haste by (%d+%.?%d*)%%$")
	if hastep then return Verdict.ratingFromPercent("Haste", tonumber(hastep)), "Haste" end
	-- Structural tooltip chrome (gate C1). Case-insensitive, anchored.
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
	-- of the maintainer's amendment (comment 58, t_7b8f504a): "the AC-E6 plural
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
	-- NOT captured in this repo (review §11.4 says the same of `Block`). The
	-- accepted set below covers the two forms the two local sources name —
	-- the card's "Off Hand" and the review's "held-in-off-hand" prose — and anything
	-- else falls through to suppression, i.e. it fails closed.
	if low == "off hand" or low:match("^off hand%s+[%a%-']+$") then
		return nil, nil, "structural"
	end
	if low:match("^held in off%-hand$") or low == "held in off hand"
		or low:match("^held in off%-hand%s+[%a%-']+$")
		or low:match("^held in off hand%s+[%a%-']+$") then
		return nil, nil, "structural"
	end
	-- ---- Card t_b91136cb: the WEAPON type line is structural chrome --------
	--
	-- A weapon's type line is the left-column slot word with the right-column
	-- subtype — "Ranged  Wand", "Main Hand  Dagger", "Two-Hand  Sword" — and
	-- on this client a weapon may print the BARE slot word alone: "Main Hand"
	-- is the owner's live mace line and "Ranged" the wand fixture (both
	-- quoted line-for-line from the client's own output in the t_16448f75
	-- fixtures; "Two-Hand" bare is the same shape in the t_a25a6ad6 live
	-- capture). None of these slot words is among the armour slot words
	-- above, and "Off Hand …"/"Held In Off-hand …" (the ONLY off-hand type
	-- lines this module accepts) do not cover a main-hand or two-hand
	-- weapon, so before this card a weapon type line fell through to the
	-- unplaceable tail, read cosmetic (no digit), and EVERY weapon hover
	-- disclosed a "cosmetic line" that was the item's own chrome.
	--
	-- NARROW on purpose, per the card's rule: the bare slot word, or the
	-- slot word plus ONE of the subtype words this client prints. A
	-- stat-shaped or number-bearing line that begins the same words matches
	-- none of these clauses and keeps failing closed — a subtype outside the
	-- list degrades to the cosmetic path (disclosed, never chrome), never to
	-- a wider acceptance. The slot word is matched LITERALLY (the
	-- hyphen is a plain character) for the bare form, and as a pattern
	-- whose `%-` is an escaped hyphen for the composite form, so
	-- "Two-Hand  Sword" and "TwoHand  Sword" do not mix.
	-- ONE grammar, spent twice (card t_1677cd39): this classifier and the
	-- weapon-family reader below. The reader is what a spec's weapon policy
	-- asks, so the two must never be two lists — see WEAPON_TYPE_SLOTS.
	local typeSlot = weaponTypeLine(low)
	local is_weapon_type = typeSlot ~= nil
	if is_weapon_type then return nil, nil, "structural" end
	-- Structural chrome (gate C1, E1, t_7b8f504a). Each of these ships on
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
	-- shipped bug (gate run 63, Blocking 1): it was dead code and
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
	-- The old note here said these stayed unparsed "on purpose: there is no
	-- Healing or FireSpellPower word to put them in". Card t_4e1e1b1d (DD-2)
	-- gave them words (Healing, and one per school), so they are read now —
	-- see the DD-2 clauses below the generic match.
	-- SpellPower is a known word so the line no longer suppresses. It is not
	-- in any class ORDER (see the playtest note on Verdict.ORDERS), so an
	-- ORDINAL verdict is unchanged by it: a melee character is judged on the
	-- item's other stats, and a caster is still judged on the documented
	-- int/spi/sta order, and a pair whose only difference is spell power
	-- stays level on the relevance set. What the owner's later ruling added
	-- (card t_b7cd07e1, "Spell power gets a weight from the packs") is a
	-- WEIGHT: this word now enters the weighted sum of an ordinal trade-off
	-- as the SPOW word of WEIGHT_KEYS below, priced from the pack the table
	-- cites (see the SPELL POWER note in Weights.lua).
	local spn = plain:match(
		"^equip:%s*increases damage and healing done by magical spells and effects by up to (%d+)%.?$")
		or stat_sentence:match(
		"^increases damage and healing done by magical spells and effects by up to (%d+)$")
	if spn then return tonumber(spn), "SpellPower" end
	-- The two sentences this pack reads and DD-2 does not (measured against
	-- 30f3d32: neither shape exists upstream, and neither word is in DD-2's
	-- map), kept verbatim so the words stay priced instead of suppressive:
	--   * spell penetration — "Equip: Increases your spell penetration by 10."
	--   * shield block VALUE — a raw number, distinct from the Block stat.
	-- The healing-only, damage-only and school sentences that used to sit here
	-- are DELETED, not re-worded: DD-2 reads all three, into Healing /
	-- SpellDamage / the six school powers, and a second clause claiming the
	-- same sentence under another name is how the two vocabularies drifted.
	local spenn = stat_sentence:match("^increases your spell penetration by (%d+)$")
		or stat_sentence:match("^increases spell penetration by (%d+)$")
	if spenn then return tonumber(spenn), "SpellPenetration" end
	local bval = stat_sentence:match("^increases the block value of your shield by (%d+)$")
	if bval then return tonumber(bval), "Block" end
	-- ── card t_4e1e1b1d (DD-2): healing-only and school-specific damage ────
	-- The two shapes the note above used to send to the suppression bucket.
	-- They are exact matches, in the same style as the generic clause above:
	-- a lower-cased, de-coloured sentence, an integer N, an optional trailing
	-- period, and NOTHING else. A near miss is still unplaceable and still
	-- suppresses the item, which is the card's AC-A ("…by up to 12 against
	-- Undead" still blocks): the clauses do not widen to a prefix match, and
	-- the school is a FIXED list rather than any word, so no invented school
	-- can be read as damage power.
	--
	-- The number is the magnitude the sentence states, with no conversion.
	-- Whether it is worth anything to the class holding the item — and at what
	-- price — is the weight table's answer (HEAL / SP<SCHOOL> below), and a
	-- class whose pack prices 0 reads the item exactly as if the line were
	-- absent (AC-E; see the SCHOOL POWER exemption in wordUnpriced).
	local hpn = plain:match(
		"^equip:%s*increases healing done by spells and effects by up to (%d+)%.?$")
	if hpn then return tonumber(hpn), "Healing" end
	local school, snum = plain:match(
		"^equip:%s*increases damage done by (%a+) spells and effects by up to (%d+)%.?$")
	if snum then
		local schoolWord = SCHOOL_POWER_WORD[school]
		if schoolWord then return tonumber(snum), schoolWord end
	end
	-- ── card t_8575389a: healing WITH its 1/3 damage, on ONE line ─────────
	-- The owner's live client print, verbatim (C_TooltipInfo.GetItemByID(18510),
	-- a single line, type 0; Forever beta, 2026-10-20):
	--
	--   "Equip: Increases healing done by up to 42 and damage done by up to 14
	--    for all magical spells and effects."
	--
	-- TWO stats on ONE line, so this is the only clause that returns a FOURTH
	-- value: `also`, the second half. The healing half is the ordinary
	-- (num, word) return and the damage half rides beside it, so every caller
	-- that takes three returns is untouched, and an unreadable line still comes
	-- back as a nil with no `also` at all.
	--
	-- NOT A DERIVATION, and this is the card's superseded clause. The client
	-- carries the damage half as its OWN key for this item
	-- (ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 14), so the second number is READ.
	-- The card's "derive damage = healing / 3" fallback is therefore inactive on
	-- this item and is implemented NOWHERE in this module: a /3 folded in here
	-- would double-count the 14 on every item that states both halves (AC-3).
	--
	-- THE CAUTIONARY EXAMPLE, and why that sentence is worth a comment: ForeverGear
	-- — a third-party addon running on this same client — derives
	-- `HealingPower / 3` in TWO places, Stats.lua:803-808 (its normalization pass)
	-- and Stats.lua:1022-1024 (its cache write), the second carrying the note "a
	-- separate derived channel so a healing profile does not automatically
	-- double-count offensive value". Two sites, one derived number, and no reader
	-- can tell which is authoritative. That is the anti-pattern AC-5 names: if a
	-- derivation is ever needed here it gets ONE site, ONE named constant and ONE
	-- comment (Mira's §4 ruling on this card asks for the citation; the owner's own
	-- read means the derivation is not needed at all).
	--
	-- The shape is EXACT, in the same style as the clauses above: the
	-- "for all magical spells and effects" tail is part of the match and the
	-- sentence must be the WHOLE line, so a near miss ("…and damage done by up
	-- to 14 against Undead", a missing tail, a percentage) still suppresses —
	-- the card's AC-A near-miss rule, unchanged.
	local hpn2, spn2 = plain:match(
		"^equip:%s*increases healing done by up to (%d+) and damage done by up to (%d+)"
		.. " for all magical spells and effects%.?$")
	if spn2 then
		-- SpellDamage, not SpellPower: the sentence states a damage bonus, and
		-- folding it onto the spell-power word would price a healer's item on a
		-- term the tooltip never printed (AC-3's "the 14 is not counted as spell
		-- power"). Whether any table PRICES the word is a weights question this
		-- card does not touch — no 29th weight key exists, by the owner's ruling.
		return tonumber(hpn2), "Healing", nil, { SpellDamage = tonumber(spn2) }
	end
	-- ── card t_33dd248c: the SAME phrasing, ONE number ────────────────────────
	-- The two-stat clause above owns the sentence "…by up to 34 and damage done
	-- by up to 11 for all magical spells and effects". Its SINGLE-number siblings
	-- — the same tail, one stat — were still suppressive, so the same item family
	-- read two ways depending on whether the client printed one number or two: a
	-- "+34 Healing" weapon failed closed as an unplaceable line while its
	-- "+34 Healing / +11 damage" twin judged. That inconsistency is what this
	-- card's acceptance names, and these two clauses close it.
	--
	-- Same exactness rules as every clause above: the whole line, integer
	-- magnitudes, an optional trailing period, the "for all magical spells and
	-- effects" tail part of the match. A near miss ("…for all magical spells",
	-- "…by up to eleven", a percentage) still matches nothing and still
	-- suppresses. SpellDamage again, never SpellPower, for the reason stated on
	-- the damage-only clause below.
	local hpnTail = plain:match(
		"^equip:%s*increases healing done by up to (%d+) for all magical spells and effects%.?$")
	if hpnTail then return tonumber(hpnTail), "Healing" end
	local spnTail = plain:match(
		"^equip:%s*increases damage done by up to (%d+) for all magical spells and effects%.?$")
	if spnTail then return tonumber(spnTail), "SpellDamage" end
	-- The DAMAGE-ONLY mirror of DD-2's healing-only clause — a school-less
	-- damage sentence. SECONDARY evidence, and named as such: the owner's Hide
	-- of the Wild does NOT print this wording, and no capture in this repo does.
	-- It is read for three reasons, none of them a guess about this item:
	--   * it is the exact mirror of the healing-only clause DD-2 already ships;
	--   * ForeverGear's parser carves the same sentence out by name (Stats.lua,
	--     "Generic spell-damage wording. Require magical/spell context so normal
	--     weapon damage such as '34 - 51 Damage' can never become Spell Power"),
	--     which is what a damage-only line on a real tooltip looks like;
	--   * leaving it suppressive is precisely the defect this card exists to
	--     kill (one unreadable line turning a decidable item into "cannot
	--     classify"), and it was measured as suppressive before this card.
	-- It maps to SpellDamage, never SpellPower — same reason as above.
	local spnOnly = plain:match(
		"^equip:%s*increases damage done by spells and effects by up to (%d+)%.?$")
	if spnOnly then return tonumber(spnOnly), "SpellDamage" end
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
-- verbatim shape observed in the capture (t_ea70928d ruling — the implementer
-- amendment, the maintainer signed off): "word +num" or "word +num and word +num"
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
	-- DD-2 (below) carries the healing, damage-half and school entries with
	-- SCOPED needles of its own, and narrows nothing else; this pack adds only
	-- the words DD-2 has no entry for, so a sentence cannot be claimed by two
	-- words in the sorted walk.
	SpellPenetration = { "spell penetration" },
	Haste = { "haste" },
	ExpertiseRating = { "expertise rating", "expertise" },
	BlockChance = { "block rating", "chance to block", "block chance" },
	BonusArmor = { "bonus armor" },
	WandDps = { "wand dps" },
	-- card t_795eee9e: the extended reader's own phrasings. The plain one-word
	-- lines (a "N Hit"-style spelling) fall back to the word's lowercased name
	-- in lineNamesWord, so the entries below exist for the shapes the fallback
	-- cannot see — the two-word and sentence spellings — and to say, in the
	-- source, which lines claim which word.
	Hit   = { "hit" },
	Crit  = { "crit" },
	-- card t_9d3273cb: there is no separate spell needle set any more, because
	-- there is no separate spell word. The "hit" and "crit" needles above cover
	-- the spell phrasings too, and that is not a loss of precision — a "hit with
	-- spells" line IS the Hit stat. (Before this card the claim loop had to put
	-- the longer spell needles first, since sorted order would otherwise let the
	-- shorter "hit" win; with one word there is nothing to disambiguate.)
	FeralAttackPower = { "in cat, bear", "feral attack power",
	                     "dire bear", "moonkin" },
	-- card t_4e1e1b1d (DD-2): healing-only and the six schools. The parser now
	-- reads all seven sentences, so a line of these shapes never reaches the
	-- reconciler — these needles exist so that a WORN-side odd spelling of the
	-- same stat still reconciles to its own word, and so that the sentence's
	-- phrasing is written down where the claim loop can find it. They also keep
	-- the claim loop HONEST: SpellPower's needles include "spells and effects",
	-- which every one of these sentences contains, so without an entry of its
	-- own a school line could be claimed by SpellPower (the loop walks the
	-- words in sorted order) and priced as the wrong stat.
	--
	-- The client's own ITEM_MOD vocabulary has no verified key for any of
	-- these seven (the key inventory this file cites lists no healing or
	-- school damage key), and the map is not reachable from the client read
	-- anyway: `explain` only considers stats carried by the CLIENT'S OWN stat
	-- read, and no client key maps to any of these seven, so no client value
	-- can name one of them today. The entries are the recogniser's vocabulary
	-- for a rendered line, not a claim that a read exists.
	--
	-- ⚠ LATENT FALSE POSITIVE, named here rather than left for a review. The
	-- needles are matched by CONTAINMENT against the whole de-coloured line,
	-- so IF a client key were ever mapped to one of these words, the bare
	-- "fire damage" needle would also claim a PROC line — "Chance on hit: 30
	-- Fire damage" — and price a weapon proc as spell damage. A future mapping
	-- must bring a scoped match (the "damage done by <school>" phrasing, or the
	-- Equip: prefix) with it, never the bare school needle.
	Healing     = { "healing done by spells", "healing done", "healing power" },
	-- card t_8575389a: the DAMAGE half. SCOPED needles on purpose — the latent
	-- false positive named above is exactly this word's risk: a bare "damage" or
	-- a bare school word would claim a weapon proc ("Chance on hit: 30 Fire
	-- damage") as spell damage. These two phrases only ever occur inside a
	-- sentence that states the stat, so a proc line cannot carry one.
	--
	-- They matter only for a line the text parser could NOT place: both shapes
	-- this word reads (the combined sentence and the damage-only sentence) now
	-- arrive as stats and never reach the reconciler.
	SpellDamage = { "damage done by spells and effects", "damage done by up to" },
	HolyPower   = { "damage done by holy", "holy spells", "holy damage" },
	FirePower   = { "damage done by fire", "fire spells", "fire damage" },
	FrostPower  = { "damage done by frost", "frost spells", "frost damage" },
	ShadowPower = { "damage done by shadow", "shadow spells", "shadow damage" },
	NaturePower = { "damage done by nature", "nature spells", "nature damage" },
	ArcanePower = { "damage done by arcane", "arcane spells", "arcane damage" },
	Defense = { "defense" },
	Dodge   = { "dodge" },
	Parry   = { "parry" },
	Block   = { "block value", "block" },
	AttackPower       = { "attack power", "attackpower" },
	RangedAttackPower = { "ranged attack power" },
	MP5 = { "mana per 5", "mana regen", "mp5" },
	HP5 = { "health per 5", "health regen", "hp5" },
	WeaponDps = { "weapon dps", "damage per second" },
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
-- ⚠ THIS IS THE FALLBACK, NOT THE RULE (card t_4ff4ebef). The ruling is the
-- structured read: `itemLines` (ChestAdvisor.lua) asks
-- `C_TooltipInfo.GetHyperlink` first, and that read carries the item's own data
-- and nothing another addon appended — measured on the owner's live client by
-- card t_119d120c (9 lines structured vs 14 rendered; the annotation and the F6
-- prompt are ABSENT from the structured side). On a client with the API there is
-- nothing here to do, and a foreign line cannot reach the judge at all.
--
-- What is left here is the client WITHOUT the API, and on that path a line can
-- only be recognised by its own text. Card t_4ff4ebef fixed two defects in how
-- this fallback does that:
--
--   1. THE MARKER WAS A PREFIX. `plain:sub(1, #header) == header` matched a
--      header only at the very START of a line. RestedXP spells its own line
--      "Item used in guide: …", but a wrapper ("RestedXP: Item used in guide:
--      …") put the same annotation out of reach — and the line then fell into
--      the ordinary classifier: the number-free form was counted as a
--      "cosmetic line ignored" (false — it is not the item's prose) and the
--      number-carrying form SUPPRESSED the item ("cannot classify: RestedXP:
--      Item used in guide: 12-14 Silverpine Forest"). The marker is now sought
--      ANYWHERE in the de-coloured line, which is what "this line contains
--      another addon's annotation" actually means.
--   2. THE SET-ASIDE WAS INVISIBLE. Everything from the header onward was thrown
--      away and `parseSide` never heard of it, so the tooltip could report a
--      COMPLETE read of an item whose tooltip it had silently truncated. The
--      split now hands the set-aside lines back (`Verdict.splitForeign`), and
--      they are disclosed as FOREIGN — never as cosmetic, because they are not
--      the item's own prose (the card's requirement 3: what the message reports
--      must match what was actually set aside).
--
-- A header still starts a skip-to-end: the block that follows a header belongs
-- to the addon ("If you replace this item…", "-8 Armor"), and those rows would
-- otherwise parse as real stats. Dropping the tail is the safe direction — it is
-- now a REPORTED drop rather than a silent one.
--
-- ⚠ CARD t_195a0e07 — THE SELL-PRICE TERMINATOR DECIDED BY POSITION, AND THAT
-- FAILED OPEN ON THE ITEM ITSELF. Until this card the rule was: once a
-- "Sell Price" line had been KEPT, every later line carrying a digit was an
-- addon delta and was set aside — and the set-aside opened the DROP, so every
-- line after it went with it. On a real client the sell price IS the item's
-- last line, so the rule looked harmless; its failure mode was silent, and it
-- JUDGED rather than refused. With "Sell Price: 7459" printed BEFORE the
-- item's body, the body's own stat lines were set aside as "addon lines", the
-- parse saw an item with no stats, and the pair was COMPARED. A "+5 Frost
-- Resistance" the reader could not place went with them, on the strength of
-- its POSITION alone, so the pair that must refuse answered NOT_UPGRADE
-- instead. The same line list, with the same chrome last, refused correctly.
-- That is the one thing #93/#96 exist to prevent: a verdict claimed over a
-- line the reader never read.
--
-- THE RULE NOW IS A PROPERTY OF THE LINE, NOT OF ITS POSITION. A line is set
-- aside only when the LINE ITSELF says it is not the item's: another addon's
-- MARKER (FOREIGN_LINE_HEADERS above), which opens the drop block that follows
-- it — an annotation, positively identified by its own text, and the one shape
-- in this corpus that no item tooltip can produce.
--
-- ⚠ THERE IS NO SECOND SHAPE, AND THE TEMPTING ONE WAS CHECKED AND REFUSED.
-- The obvious replacement — "a signed-negative line is another addon's delta
-- (-8 Armor), not a stat" — is FALSE for this repo's own pinned corpus: case 1
-- of ChestAdvisor/tests/verdict_cases.lua is an item whose stat line is
-- "-3 Stamina", and verdict_cases.lua's own sign note records that the parse
-- reads the MAGNITUDE of a "+N Word" / "-N Word" line. A sign is therefore NOT
-- a discriminator between another addon's arithmetic and the item's own stat,
-- and a rule keyed on it would silently set aside a real stat (it did, on this
-- branch, and the pinned case caught it by name). Position was the only
-- discriminator available, and position is the thing that failed open. So:
--   * a MARKER is set aside, and opens the block that follows it;
--   * EVERYTHING ELSE reaches the classifier, wherever it sits — a numbered
--     line the classifier cannot place SUPPRESSES, and one it can place is the
--     item's own, including a "Sell Price:" line (parseLine_ places it as
--     structural chrome) and including a sign-carrying stat line.
-- Fail-closed is a property of the LINE SET, not of encounter order.
--
-- WHAT THIS COSTS, STATED RATHER THAN IMPLIED: on the no-API fallback, a
-- THIRD-PARTY line appended after the sell price is now treated like any other
-- line. If the classifier cannot place it, the pair REFUSES and the reason
-- NAMES it — the fail-closed direction the owner ruled for ("the answer to 'a
-- line was skipped' is to refuse, never to judge more confidently"). If the
-- classifier CAN place it, it is read as the item's own, which is the
-- pre-existing treatment of a sign-led line everywhere else on the tooltip (see
-- the sign note above) and is exactly what the old positional rule was written
-- to prevent; no rule can prevent it without also setting aside the item's own
-- "-3 Stamina". On the structured read none of this arises at all: another
-- addon's lines never reach the judge (t_4ff4ebef: the ruling is
-- C_TooltipInfo; this is the fallback).
-- ⚠ A healing-only Equip line USED to be the second example here and is not one
-- any more: card t_4e1e1b1d (DD-2) reads it as the word Healing, so it is a
-- classified stat now, not an unparsed line. What suppresses a pair carrying it
-- is the priced off-order guard (card t_e2ebb44e), not this list.
local FOREIGN_LINE_HEADERS = {
	"item used in guide",
	"if you replace this item",
	"press f6 to submit",
	"touchstone:",
}

-- Does this de-coloured, lower-cased, trimmed line carry one of the markers?
-- CONTAINMENT, not prefix — see item 1 above. `find(..., true)` is a plain
-- substring search, so a header can never be read as a Lua pattern.
local function foreignMarker(plain)
	for i = 1, #FOREIGN_LINE_HEADERS do
		if plain:find(FOREIGN_LINE_HEADERS[i], 1, true) then return true end
	end
	return false
end



-- Split one side's raw lines into the ITEM's own lines and the lines set aside
-- as foreign. Returns (kept, foreign): two arrays of the raw strings, in the
-- order they were met. A non-table input passes straight through as
-- (input, empty), so "no read" stays "no read".
--
-- This is the ONE definition of "not the item" on the rendered path. No other
-- file keeps a list of foreign strings: ChestAdvisor.lua's disclosure renders
-- what THIS returns rather than naming shapes of its own.
--
-- CARD t_195a0e07: the decision is a property of the LINE — another addon's
-- marker, and nothing else — never of where the line sits relative to the sell
-- price. Everything else stays in the item's own list and is classified, so an
-- unplaceable line suppresses the pair whatever precedes it, whatever follows
-- it, and however many structural or cosmetic lines are interleaved.
function Verdict.splitForeign(lines)
	if type(lines) ~= "table" then return lines, {} end
	local kept, foreign = {}, {}
	local drop = false
	for _, line in ipairs(lines) do
		if type(line) == "string" then
			local plain = deColour_(line:lower())
			plain = plain:gsub("^%s+", ""):gsub("%s+$", "")
			local marker = foreignMarker(plain)
			if drop or marker then
				foreign[#foreign + 1] = line
			else
				kept[#kept + 1] = line
			end
			-- The marker opens the block that follows it; there is no other
			-- set-aside, because any other rule would be a POSITION rule and a
			-- position rule is what let one line decide the line set (t_195a0e07).
			if marker then drop = true end
		end
	end
	return kept, foreign
end

-- The item's own lines, for callers that do not need to disclose the split.
-- The SAME kept table `splitForeign` returns, so there is one rule, not two.
function Verdict.nativeLines(lines)
	local kept = Verdict.splitForeign(lines)
	return kept
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
-- `foreign` (card t_4ff4ebef) is the FIFTH return: the raw lines the side's
-- reader composed and this parse SET ASIDE as not-the-item (another addon's
-- annotation and the block it opens). They are deliberately NOT in `ignored`:
-- `ignored` means "the item's own prose that carried no number", and a foreign
-- line is neither the item's nor cosmetic. Handing them back separately is what
-- keeps the disclosure countable and honest — a reader that truncated the
-- tooltip can say so, in its own words, instead of adding to a cosmetic total it
-- has no business being in. Empty when nothing was set aside (always empty on a
-- client whose structured read is present, because nothing foreign is in it).
--
-- `apiWords` (card t_548f0341, OPTIONAL) is the client's own stat read, already
-- mapped to this module's stat words by Verdict.apiStats at the impure edge.
-- It is used for ONE thing: a line the text parser cannot place is EXPLAINED
-- (and therefore no longer suppresses) when the API names a stat this parse has
-- not captured AND the line's own text talks about that stat. Nothing else about
-- the parse changes, and with `apiWords` nil every branch below is byte-identical
-- to the pre-card behaviour — the fail-closed answer for an absent API.
local parseSide = function(lines, side, apiWords)
	local stats, procWord, unknown, ignored, foreign = {}, nil, nil, {}, {}
	if type(lines) ~= "table" then return stats, procWord, unknown, ignored, foreign end
	-- Card t_4ff4ebef: the foreign split happens HERE, at the parse boundary, and
	-- not as a caller's option. Anything set aside below never reaches the
	-- classifier, so a line another addon composed can never be counted as this
	-- item's "cosmetic" prose (nor suppress it) — while `foreign` is handed back
	-- so the disclosure can say what was set aside instead of implying a
	-- complete read.
	local kept, setAside = Verdict.splitForeign(lines)
	lines = kept or lines
	foreign = type(setAside) == "table" and setAside or {}
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
	-- Name-line rule (gate C1): a real item tooltip's position 1 is the item
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
			local num, word, kind, also = parseLine_(line)
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
					-- Card t_8575389a: ONE line, TWO stats. The combined
					-- healing+damage sentence hands its second half back in
					-- `also`; fold it through this same accumulator so the
					-- second number is read exactly like the first — no second
					-- parser, no second code path. The clause that produces
					-- `also` is fixed (Healing + SpellDamage) and KNOWN gates
					-- both halves, so an unknown word could not be smuggled in
					-- even if a future clause returned one.
					if type(also) == "table" then
						for w, v in pairs(also) do
							if KNOWN[w] and type(v) == "number" then
								stats[w] = (stats[w] or 0) + v
							end
						end
					end
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
				-- (gate C1).
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
	-- ── FOLD THE UNCONFIRMED WORDS NO LINE NAMED (card t_e894c90f) ───────────
	-- THE DEFECT, measured: everything above folds an apiStats word into a side
	-- only when a LINE names it (`explain` -> `fold`). A word the client's read
	-- carries and no tooltip line mentions was therefore never folded, never
	-- suppressed, never reported — it was ABSENT from the pair, and the pair
	-- decided on the words that survived. On the card's own shape (both sides
	-- "+5 Stamina", candidate's client read Dodge 6, worn's Dodge 12, no naming
	-- line) that read NOT_UPGRADE "equal": two measurably different unmeasured
	-- ratings silently excluded. With a priced word in the same position the
	-- pair could read UPGRADE over a stat the item does not have.
	--
	-- THE RULING (the reviewer, owner-delegated, 2026-10-20): OPTION A — fold ONLY the
	-- words in UNCONFIRMED_UNITS that no line named, HERE at the parse boundary.
	-- Final. Option B (fold every verified apiStats word) was rejected — it moved
	-- 30 of 120 sweep rows for nothing this does not buy; C and as-is were
	-- rejected because they leave a confident wrong answer in place.
	--
	-- WHY THE FOLD IS THE WHOLE FIX, and why it is at the BOTTOM of the parse and
	-- not in the comparator: a folded word lands in `stats` exactly where a
	-- naming line's word lands, so the EXISTING gates see it with no second copy
	-- of the rule anywhere — gate 5b/8b (Verdict.unpricedWord) closes a pair on
	-- an UNCONFIRMED_UNITS word by PRESENCE, naming it in the module's own
	-- vocabulary. Dodge and Parry are presence-rule words (the difference-only
	-- set is empty since t_9d3273cb), so this closes on their presence on either
	-- side, equal values included. That bluntness is the ruling's, and it is
	-- disclosed rather than discovered: moving them to UNCONFIRMED_DIFFERENCE_ONLY
	-- would change TEXT behaviour too and is a separate ruling, not this card.
	--
	-- WHAT IT MUST NOT DO (the ruling's explicit bound): do not widen it to
	-- priced words, do not touch Weights.lua, do not change a weight, and do not
	-- fold a word a line DID name — a priced word's naming line is read by the
	-- loop above and stays the primary path, and an unconfirmed word's naming
	-- line is already claimed by `explain` (API_WORD_TEXT carries "dodge" and
	-- "parry"), so `apiUsed[w]`/`rawget(stats, w)` are already set for it.
	--
	-- `type(rawget(api, w)) == "number"` is the same fail-closed bar as everywhere
	-- else in this module: a non-number is not a value and is not folded. The
	-- sorted order is for a repeatable choice when more than one unconfirmed
	-- word is unnamed (pairs() is unordered), the same discipline as `apiOrder`.
	if api then
		local unconfirmed = rawget(Verdict, "UNCONFIRMED_UNITS")
		if type(unconfirmed) == "table" then
			local pending = {}
			for w, flagged in pairs(unconfirmed) do
				if flagged == true and not apiUsed[w] and rawget(stats, w) == nil
					and type(rawget(api, w)) == "number" then
					pending[#pending + 1] = w
				end
			end
			table.sort(pending)
			for i = 1, #pending do fold(pending[i]) end
		end
	end
	-- A wand's parenthesised "damage per second" line parses as WeaponDps.
	-- Caster packs price WandDps, and a melee WeaponDps weight must not
	-- score a wand, so remap after the type line has been seen.
	local isWand = false
	for _, line in ipairs(lines) do
		if type(line) == "string" then
			local low = deColour_(line:lower()):gsub("^%s+", ""):gsub("%s+$", "")
			if low == "wand" or low:match("^ranged%s+wand$") then
				isWand = true
				break
			end
		end
	end
	if isWand and type(stats.WeaponDps) == "number" then
		stats.WandDps = (stats.WandDps or 0) + stats.WeaponDps
		stats.WeaponDps = nil
	end
	-- A percent Expertise reading is the sourced unit. When the same item
	-- also carries ITEM_MOD_EXPERTISE_RATING (or a short "+N Expertise"
	-- rating line), keep the percent only so the two units are not mixed
	-- on one side.
	if type(stats.Expertise) == "number" then
		stats.ExpertiseRating = nil
	end
	return stats, procWord, unknown, ignored, foreign
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

-- PLAYER WORDS, NEVER THE INTERNAL TOKEN (card t_b91b29f9, item 7). A reason
-- is read on screen, so the stat it names must be spelled the way the player
-- reads it on the item. Most words already are (Strength, Armor, SpellPower);
-- the one below is a token DD-1 introduced and is NOT a player's spelling, so
-- a feral trade-off read "better on FeralAttackPower".
-- Only those are mapped: routing every word through STAT_LABEL would print
-- "better on Str" and change wording nobody asked to change. ONE map, read by
-- both the ordinal reasons and the weighted layer's gain/loss clause.
-- (Card t_9d3273cb retires the two spell entries with the two spell words;
-- "Hit" and "Crit" are already a player's spelling.)
local REASON_WORD = {
	FeralAttackPower = "Feral AP",
	-- card t_4e1e1b1d (DD-2): the six school tokens are not a player's
	-- spelling either ("better on FirePower"). Two words, the way a player
	-- says it. Healing is already a word a player reads on the item, so it is
	-- deliberately NOT mapped here (the DD-1 note above: map only the tokens
	-- that are not a player's spelling).
	HolyPower   = "Holy Power",
	FirePower   = "Fire Power",
	FrostPower  = "Frost Power",
	ShadowPower = "Shadow Power",
	NaturePower = "Nature Power",
	ArcanePower = "Arcane Power",
	-- card t_8575389a: the damage half's token is not a player's spelling
	-- either — the item says "damage done by … for all magical spells and
	-- effects", and a player says "spell damage".
	SpellDamage = "Spell Damage",
}

local function playerWord(statWord)
	if type(statWord) ~= "string" then return statWord end
	return REASON_WORD[statWord] or statWord
end

-- The vocabulary, published. The reason builders above are its only shipped
-- consumers; it is exposed so a test can pin what a PLAYER will read (card
-- t_b91b29f9, item 7) without grepping source — the alternative was a test that
-- re-implements the map and therefore proves nothing about the shipped path.
Verdict.playerWord = playerWord

local function winReason(statWord)
	return "upgrade: better on " .. (playerWord(statWord) or "a role stat")
end

-- The MIRROR of winReason, for the DOWNWARD call (card t_4590ab7e, item 1).
-- One vocabulary, not two: the ordinal NOT_UPGRADE reason already words a loss
-- as "worse on <stat> than what's equipped", so the weighted loss is worded with
-- exactly that string rather than with a new one. `nil` statWord keeps the same
-- "a role stat" fallback winReason uses, so neither direction can print a nil.
local function loseReason(statWord)
	return "worse on " .. (playerWord(statWord) or "a role stat") .. " than what's equipped"
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

-- The trade-off reason lives with the ORDERED VERDICT below (card t_0bf5c207),
-- because it needs the pack's priced words as well as the order: the sentence
-- names BOTH SIDES of the trade in the order's own ranking, and the priced words
-- are declared further down this file. The old first-diff-only sentence is gone
-- with the dominance read it served: it named the loss and never the stat that
-- paid for it (the Ret belt read "(Strength absent vs 10)" with the crit that
-- bought the trade nowhere in the sentence).

-- ═══════════════════════════════════════════════════════════════════════════
-- (card t_984bc8ac) THE WEIGHTED RESOLUTION LAYER — the owner's supersede.
--
-- RULED 2026-10-04 (the Tier C note below, and the old gate-9 comment): "Read
-- the numbers. Order by prose. No stat weight anywhere." SUPERSEDED
-- 2026-10-13 by the owner: "Supersede. Ship card 2 to your spec." The history
-- is kept, not deleted — the ruled text is still quoted below.
--
-- WHAT IT IS, and the three properties that make it safe:
--   1. ADDITIVE. It runs ONLY where the ordinal dominance test returned
--      "trade-off" (gate 9). A dominant candidate is UPGRADE and a dominated
--      one NOT_UPGRADE with or without a weight; the Armor/Block tiebreak, the
--      lower-armor material rule (allow()) and every suppression gate (5, 8)
--      keep firing exactly as before, and BEFORE this layer.
--   2. FAIL-SAFE. No table, no table for this class/spec, a table that does
--      not validate, a non-number threshold, or a weighted total that is not
--      clearly positive -> nil, and the caller returns TODAY'S EXACT
--      TRADE_OFF. Weights never widen a verdict on absent data.
--   3. DISCLOSED. A resolved verdict still names the deciding stat in the same
--      player words the ordinal path used ("upgrade: better on Armor") and
--      ALSO names the loss the weights accepted. No bare number, no internal
--      token, no silent trade-off.
--
-- THE ONE ENVIRONMENT READ IN THIS MODULE (see the file header): the table is
-- Weights.lua's StatForge.Weights. It is probed at CALL time and never cached,
-- so a test VM can install, replace or delete it between two calls — which is
-- how the fail-safes above are proven rather than argued.

-- The weighted vocabulary: the stat words this addon can read off a tooltip,
-- in a FIXED order. The order is load-bearing: it is the deterministic tie-break
-- for which stat is named as the decider when two contribute equally.
--
-- SPOW (card t_b7cd07e1 — the owner's ruling "Spell power gets a weight from the
-- packs"). The word is "SpellPower", the SAME word parseLine_ already produces
-- for the classic sentence (Verdict KNOWN, the ITEM_MOD_SPELL_POWER mapping) —
-- the schema reads the parsed table by that word, so the parser does not change.
-- Appending last keeps every existing tie-break naming byte-identical: SPOW loses
-- a naming tie to every word before it, and no pair in the suite names a tie
-- between SPOW and another word, so the ordinal wording is unchanged everywhere.
--
-- The ten words card t_795eee9e added — HIT, CRIT, AP, RAP, MP5, HP5, DEF,
-- DODGE, PARRY, WDN — the rest of the vocabulary the cited packs price
-- (hitRating, critRating, attackPower, rangedAttackPower, mp5, hp5,
-- defenseRating, dodgeRating, parryRating, weaponDps). They sit BEFORE SPOW,
-- for the same non-vacuity reason as SPOW's own position: the companion
-- weights_scoring-nonvacuity.js anchors its break on the SPOW line landing
-- directly above a table's `source` line, so a new row must not come between
-- them. And they sit AFTER Block: every pre-card tie-break names one of the
-- first seven words, so inserting new words after them cannot change which
-- word a pre-card pair names — the ordinal wording of every old pair is
-- untouched, and the new words only ever name a pair that carries them.
-- The word card t_3cdbb70a (DD-1) adds — FAP — also sits BEFORE SPOW and
-- AFTER WDN, for the same two reasons: the non-vacuity anchor on the SPOW
-- line, and "a pre-card pair's naming tie is untouched" (the new row comes
-- after every word a pre-card pair could carry).
--
-- ── CARD t_9d3273cb: THE SPELL HALVES RETIRE — ONE HIT, ONE CRIT ─────────────
-- DD-1 added two further keys here, the spell spellings of the same two pack
-- numbers, and this card removes them. THE FACT is the client's own recap,
-- read verbatim:
--
--   "Spell, melee, and ranged hit chance are combined, as are spell, melee,
--    and ranged critical chance."
--
-- A spell-hit item and a melee-hit item therefore carry ONE stat, and one stat
-- has one price. Two keys meant one item could be priced twice over: a caster's
-- +14 crit rating item priced 0.6 x 14 = 8.4 through the spell key and 0 through
-- the crit key, purely because the client printed the spell spelling of the
-- stat's key. That is not a judgement the weights are entitled to make — the
-- packs price hitRating and critRating once per spec, and every table now
-- carries that one number on HIT and CRIT.
--
-- WHAT THIS MOVES, named rather than left to be discovered: on every CASTER
-- table (spell / healer / damager) HIT and CRIT take the numbers the two spell
-- keys used to carry; on every MELEE / TANK table nothing changes, because the
-- numbers were already there. Two consequences follow, and both are pinned by
-- ChestAdvisor/tests/t_9d3273cb.js: a caster's MELEE-hit item now PRICES at his
-- own hit weight instead of being refused by a zero at HIT, and a warrior's
-- SPELL-hit item prices at his hit weight instead of being refused. Those
-- refusals were the split's whole purpose, and the recap is why they were never
-- the right answer.
--
-- THE ORDER WHERE IT MATTERS IS UNCHANGED: "Hit" and "Crit" keep the exact
-- positions they already held, so every pre-card tie-break names the word it
-- named before and no ordinal verdict moves for a NAMING reason. A pair that
-- moves moves because a number now prices where a zero used to, which is what
-- docs/t_9d3273cb-changed-verdicts.txt measures row by row.
local WEIGHT_KEYS = { "STR", "AGI", "STA", "INT", "SPI", "ARMOR", "BLOCK",
                      "HIT", "CRIT", "AP", "RAP", "MP5", "HP5",
                      "DEF", "DODGE", "PARRY", "WDN", "FAP",
                      -- card t_4e1e1b1d (DD-2): healing power, and one key per
                      -- school of spell damage. They sit BEFORE SPOW so the
                      -- key that has anchored the non-vacuity breaks since
                      -- card t_b7cd07e1 (SPOW last) keeps that position.
                      "HEAL", "SPHOLY", "SPFIRE", "SPFROST",
                      "SPSHADOW", "SPNATURE", "SPARCANE",
                      "SPOW" }
-- The same set, as a lookup, for the two validators that must answer "is this
-- one of the words above?" — derived from the list so the two cannot disagree.
local WEIGHT_KEY_SET = {}
for _, k in ipairs(WEIGHT_KEYS) do WEIGHT_KEY_SET[k] = true end
-- Card t_ee6dec52: the word list is PUBLIC (GearAPI.GetStatKeys hands out
-- copies of it for a settings / other-addon display). The live table stays this
-- file's own — the alias is the same table, so nothing here changes what a
-- verdict sees; GetStatKeys never returns the alias itself, only a copy.
Verdict.WEIGHT_KEYS = WEIGHT_KEYS
local WEIGHT_WORD = {
	STR = "Strength", AGI = "Agility", STA = "Stamina", INT = "Intellect",
	SPI = "Spirit", ARMOR = "Armor", BLOCK = "Block",
	HIT = "Hit", CRIT = "Crit", AP = "AttackPower", RAP = "RangedAttackPower",
	MP5 = "MP5", HP5 = "HP5", DEF = "Defense", DODGE = "Dodge",
	PARRY = "Parry", WDN = "WeaponDps",
	-- card t_3cdbb70a (DD-1): feral-only attack power (see ITEM_STAT_KEYS for
	-- why it is its own word). The two spell words are gone with their two keys
	-- — card t_9d3273cb, see the retirement note above.
	FAP = "FeralAttackPower",
	-- card t_4e1e1b1d (DD-2): healing power and the six schools. One word each,
	-- never folded into SpellPower: a healer's Healing and a mage's FirePower
	-- are different claims about different items, and folding them would price
	-- a Fire item off a Holy priest's pack.
	HEAL = "Healing",
	SPHOLY = "HolyPower", SPFIRE = "FirePower", SPFROST = "FrostPower",
	SPSHADOW = "ShadowPower", SPNATURE = "NaturePower", SPARCANE = "ArcanePower",
	SPOW = "SpellPower",
}

-- ── THE PROOF'S PRICED TERMS (card t_da23ec75) ──────────────────────────────
--
-- "Order = wording, priced set = proof." This is the second half of that
-- sentence, as DATA and one pure function: `Verdict.proofTerms` builds the term
-- list `Verdict.dominance` decides on, and gate 9 of `Verdict.evaluate` hands it
-- the pair's own resolved pack.
--
-- WHAT GOES IN, in this order:
--   1. the class/role's documented ORDER, verbatim, first. That is what keeps
--      every pre-card reason byte-identical: the first differing order term is
--      still the first term the proof meets, so a pair the old proof decided is
--      worded exactly as it was.
--   2. every word this pack prices at a non-zero weight, in WEIGHT_KEYS order
--      (the same order `weightedScore` walks, so a naming tie between two priced
--      words resolves the way the weighted layer resolves it).
-- A word priced at 0 is NOT a term: gate 8b already refuses such a pair rather
-- than pretending the word weighs nothing, so the proof never has to guess.
--
-- WHAT DOES NOT GO IN — `Verdict.PROOF_EXEMPT`, one reason each:
--   * Armor, Block — they are the TIEBREAK, and only that. E2 (t_8bc7d7f2,
--     §4.1a) ruled "armour is never a win, only a tiebreak" and graded
--     AC-E13(b) "armour never overturns a class-order loss": inside the proof a
--     higher-armour/lower-primary pair would read TRADE_OFF and overturn the
--     loss, which is the ruling that gate 9's tiebreak exists to prevent.
--   * WeaponDps — priced on the WEAPON path's own channel (compareDPS and
--     option (b)'s "DPS as a minor term"), never by this proof. A weapon pair
--     consults DPS exactly when its stats are level; making WeaponDps a stat
--     term here would let a pack price outvote that ruled tie-break and would
--     count the same number twice.
--
-- AND THE WEIGHTED LAYER DOES NOT SPEND THEM (card t_ea260b42). "Out of the
-- proof" was only HALF a rule: `Verdict.weightedScore` priced every key, Armor
-- and Block included, so a price for one of these three could still decide the
-- moment dominance returned TRADE_OFF. That is how the same 40 Block decided a
-- trade-off pair ("better on Block — the weighted gain outweighs the Stamina
-- loss", audit fixture W4f) and was invisible on a one-sided one (W4e) — one
-- number, two answers. The rule is now ONE shape: these three words decide a
-- pair ONLY at gate 9's tiebreak — where nothing else moved and BOTH sides carry
-- the stat — and nowhere else. A tiebreak is still a decision ("+20 Block vs
-- +10 Block" is an upgrade, W4c); it just cannot be bought by a price, and a
-- price for one of them can never outweigh a ranked word.
Verdict.PROOF_EXEMPT = {
	Armor = true,
	Block = true,
	WeaponDps = true,
}

-- Returns the proof's term list: the order's words (deduplicated, order kept)
-- followed by this pack's priced words that the order does not already name.
-- Neither input is mutated; a no-table weights argument returns just the order
-- half (an unpriceable pair keeps the ordinal proof it had).
--
-- ⚠ AN ORDER WITH NO WORDS RETURNS NO TERMS AT ALL — not even the priced half.
-- `Verdict.evaluate` normalises a nil spec.order to an empty table before gate
-- 9, so the empty case, not the nil one, is what a shipping call actually hands
-- over. Without an order there is no WORDING for a pair, and a class/role the
-- corpus documents no order for must not be judged by a table either: that is
-- C1b's rule ("stay UNKNOWN instead of reading a guessed arrow"). This is a
-- guard for any FUTURE order-less class/role; since card t_6c3f414a no shipped
-- ORDERS entry is order-less, so no shipping row reaches it today.
function Verdict.proofTerms(order, weights)
	if type(order) ~= "table" or #order == 0 then return {} end
	local terms, seen = {}, {}
	local function add(word)
		if type(word) ~= "string" or seen[word] then return end
		seen[word] = true
		terms[#terms + 1] = word
	end
	for _, word in ipairs(order) do add(word) end
	if type(weights) == "table" then
		for _, key in ipairs(WEIGHT_KEYS) do
			local w = rawget(weights, key)
			if type(w) == "number" and w > 0 then
				local word = WEIGHT_WORD[key]
				if word ~= nil and not rawget(Verdict.PROOF_EXEMPT, word) then
					add(word)
				end
			end
		end
	end
	return terms
end

-- ═══════════════════════════════════════════════════════════════════════════
-- (card t_0bf5c207, Touchstone Step 1) THE ORDERED VERDICT
--
-- ONE cascade, in ONE place, and THE ORDER IS AN INPUT. Nothing below reads
-- Verdict.ORDERS: the caller hands over `spec.order`, so the same pair judged
-- against a leveling order and against an endgame order gets different answers
-- from the same code. That is a requirement of the product, not a nicety: Step 2
-- swaps the list per character, and any code that assumes WHICH list is in force
-- would have to be rewritten for it.
--
-- WHY THE OLD READING HAD TO GO. Gate 9 asked `Verdict.dominance` over
-- `proofTerms` — the order's words, then every word the pack prices. That makes
-- a priced stat the ORDER DOES NOT RANK (Crit on a Retribution paladin) a term of
-- equal standing with the order's first word, so a belt that loses Strength and
-- gains crit came out green whenever the price liked the trade. The owner ruled
-- (2026-11-12, reaffirmed 2026-11-13) that this is a trade-off, not an upgrade:
-- a green arrow must mean "equal or better on every stat this spec ranks".
--
-- THE CASCADE — top to bottom, first match wins:
--
--   0. no order for this class/role            -> UNKNOWN, refuse (never guess)
--   1. nothing moves anywhere                  -> "equal" (the caller then lets
--                                                 the Armor/Block tiebreak speak,
--                                                 and only then)
--   2. MIXED movement — something favourable and something unfavourable, over
--      the order's words (IN) and the pack's priced words the order does not
--      rank (OFF)                              -> TRADE_OFF, both sides named
--   3. uniformly unfavourable (nothing moves for) -> DOWNGRADE, naming the
--                                                 highest ranked IN word that
--                                                 differs, else the OFF word
--   4. uniformly favourable                    -> UPGRADE (the only green)
--
-- GREEN IS PARETO. Rule 4 needs NO priced stat unfavourable and at least one
-- favourable, over both channels. A weight is a SUPPORT SET here (does this spec
-- care about the word at all), never an amount: no margin, no threshold and no
-- weighted total can turn rule 2 into a green arrow. That is the loophole this
-- card closes — +40 crit against -10 Strength used to clear the 0.5 threshold and
-- read green, and the owner ruled it must not (ruling 2026-11-13, clause A).
--
-- MIXED BEFORE DOWNGRADE, and that order is load-bearing: if "worse on the top
-- ranked word" outranked "mixed", the same pair under the same order would read
-- DOWNGRADE or TRADE_OFF depending only on whether the pack prices the word it
-- gains — a price shaping a Step 1 verdict, which clause B forbids in both
-- directions. DOWNGRADE therefore means "uniformly worse", never "mixed".
--
-- STATE, not just verdict. The three player-facing marks are UPGRADE, TRADE_OFF
-- and no-mark; DOWNGRADE and "equal" are both no-mark today, and they are NOT the
-- same answer ("worse than what you wear" and "the same as what you wear" are
-- different things to say). This returns both: the verdict string the rest of the
-- module and the UI already speak, and a `state` word that the tests and any
-- later surface can tell apart. `state` is one of
--   "upgrade" | "downgrade" | "trade_off" | "equal" | "unresolved"
-- and `verdict` is "UNKNOWN" for "unresolved" (the caller refuses).
--
-- DOWNGRADE IS ORDER-RELATIVE. Which words move at all is decided by the list in
-- force, so the same pair flips DOWNGRADE <-> UPGRADE on a different list with
-- no code change — that is what makes the order a parameter (Step 2).
--
-- EPSILON. "level" is `termSign` — `Verdict.levelWithinResolution`, the module's
-- ONE epsilon rule, no second threshold anywhere in this cascade.
--
-- PROOF_EXEMPT words (Armor, Block, WeaponDps) are not IN and not OFF: each has
-- its own two-sided ruler and they form the tiebreak channel, consulted only when
-- nothing else moves. E2's "armour is never a win, only a tiebreak" is what stops
-- armour ever buying or blocking a verdict here.
Verdict.RANKED_STATES = {
	upgrade = true, downgrade = true, trade_off = true, equal = true,
	unresolved = true,
}

-- The order's words as a set. The order is data the caller owns; this never
-- caches it across calls, so a caller that changes list between rows is heard.
local function orderWordSet(order)
	local set = {}
	for _, word in ipairs(type(order) == "table" and order or {}) do
		if type(word) == "string" then set[word] = true end
	end
	return set
end

-- The words a trade-off may name, in PRIORITY order: the order's own words
-- first (a leveling list ranks Crit above Strength if it says so), then the
-- pack's priced words the order does not name, in WEIGHT_KEYS order. Used only
-- to WORD a reason — it never decides anything.
local function priorityWords(order, weights)
	local words, seen = {}, {}
	local function add(word)
		if type(word) ~= "string" or seen[word] then return end
		seen[word] = true
		words[#words + 1] = word
	end
	for _, word in ipairs(type(order) == "table" and order or {}) do add(word) end
	if type(weights) == "table" then
		for _, key in ipairs(WEIGHT_KEYS) do
			local w = rawget(weights, key)
			local word = WEIGHT_WORD[key]
			if type(w) == "number" and w > 0 and word ~= nil
				and not rawget(Verdict.PROOF_EXEMPT, word) then
				add(word)
			end
		end
	end
	return words
end

-- The trade-off reason (card t_0bf5c207). The card asks for BOTH SIDES, in
-- priority order: the stat given up and the stat gained, with the pair's own
-- numbers. Before this card the sentence named only the FIRST differing term,
-- which on the Ret belt read "(Strength absent vs 10)" — the loss, with the crit
-- that paid for it nowhere in the sentence.
--
-- A one-sided term (present on exactly one side) is reported as "absent", never
-- as 0 — the AC-F rule, made visible in the words rather than hidden.
local function tradeOffReason(candStats, eqStats, order, weights)
	local cand = type(candStats) == "table" and candStats or {}
	local eq   = type(eqStats)   == "table" and eqStats   or {}
	local head = "trade-off: better on some stats, worse on others"
	local better, worse = nil, nil
	local betterAt, worseAt = nil, nil
	local words = priorityWords(order, weights)
	for i, word in ipairs(words) do
		local sign = termSign(word, rawget(cand, word), rawget(eq, word))
		if sign > 0 and better == nil then better, betterAt = word, i end
		if sign < 0 and worse == nil then worse, worseAt = word, i end
	end
	local function clause(word, direction)
		local c, e = rawget(cand, word), rawget(eq, word)
		local cs = (c ~= nil) and tostring(c) or "absent"
		local es = (e ~= nil) and tostring(e) or "absent"
		return direction .. " on " .. playerWord(word)
			.. " (" .. cs .. " vs " .. es .. ")"
	end
	local parts = {}
	if better ~= nil then parts[#parts + 1] = { at = betterAt, text = clause(better, "better") } end
	if worse ~= nil then parts[#parts + 1] = { at = worseAt, text = clause(worse, "worse") } end
	if #parts == 2 and parts[2].at < parts[1].at then
		parts[1], parts[2] = parts[2], parts[1]
	end
	local said = {}
	for _, part in ipairs(parts) do said[#said + 1] = part.text end
	if #said > 0 then head = head .. " (" .. table.concat(said, ", ") .. ")" end
	return head
end

-- THE RANKED HALF of the cascade (rules 2-5): the order's own words, walked
-- once. Pure, order-in, no pack consulted TO DECIDE. `weights` is optional and
-- is read for WORDING only (the trade-off sentence may name a priced word the
-- order does not rank), never to change an answer.
--
-- Public because the off-order rule in gate 9 has to ask it "what does the
-- RANKED comparison say about this pair?" before it lets a price speak — that is
-- how a green arrow stays impossible on a pair that gives up a ranked stat.
--
-- Returns verdict, reason, state: "upgrade" | "downgrade" | "trade_off";
-- "equal" (which the caller then resolves through the Armor/Block tiebreak).
function Verdict.rankedCore(candStats, eqStats, order, weights)
	local cand = type(candStats) == "table" and candStats or {}
	local eq   = type(eqStats)   == "table" and eqStats   or {}

	if type(order) ~= "table" or #order == 0 then
		return "UNKNOWN", "not judged: no stat order resolved for this class and role",
			"unresolved"
	end

	-- THE MOVEMENT, in two channels:
	--   IN  — the order's own words, in the order's priority;
	--   OFF — every word the pack PRICES at a non-zero weight that the order does
	--         not rank, EXCEPT the tiebreak channel (PROOF_EXEMPT: Armor, Block,
	--         WeaponDps keep their own two-sided rules, and E2's "armour is never
	--         a win, only a tiebreak" is what stops armour ever buying or blocking
	--         a verdict here).
	-- "Priced" is the pack's SUPPORT SET, not a number: a pack that prices a word
	-- at 0 is saying this spec does not care about it, so that word cannot make a
	-- pair non-green. No margin, no threshold, and no weighted total takes part in
	-- any answer below — that is card t_0bf5c207 clause B, and it is why
	-- `weightedResolution` no longer appears in this path (it stays, public, as the
	-- Step 3 engine).
	local inOrder = orderWordSet(order)
	local offFor, offAgainst = {}, {}
	if type(weights) == "table" then
		for _, key in ipairs(WEIGHT_KEYS) do
			local w = rawget(weights, key)
			local word = WEIGHT_WORD[key]
			if type(w) == "number" and w > 0 and word ~= nil
				and not inOrder[word]
				and not rawget(Verdict.PROOF_EXEMPT, word) then
				local sign = termSign(word, rawget(cand, word), rawget(eq, word))
				if sign > 0 then
					offFor[#offFor + 1] = word
				elseif sign < 0 then
					offAgainst[#offAgainst + 1] = word
				end
			end
		end
	end

	-- `firstDiff` is the HIGHEST-RANKED order word that differs; `gained`/`lost`
	-- are the highest-ranked order word each way.
	local firstDiff = nil
	local gained, lost = nil, nil
	for _, word in ipairs(order) do
		local sign = termSign(word, rawget(cand, word), rawget(eq, word))
		if sign ~= 0 then
			if firstDiff == nil then firstDiff = word end
			if sign > 0 and gained == nil then gained = word end
			if sign < 0 and lost == nil then lost = word end
		end
	end

	local offMoved = (#offFor + #offAgainst) > 0
	local anyFor = (gained ~= nil) or offMoved and #offFor > 0
	local anyAgainst = (lost ~= nil) or offMoved and #offAgainst > 0

	if firstDiff == nil and not offMoved then
		-- Rule 1 — nothing moved at all. The Armor/Block tiebreak is the caller's
		-- (E2: it breaks a remaining tie, and only that).
		return "NOT_UPGRADE", "equal to what's equipped — not a strict improvement",
			"equal"
	end

	-- The two movement rules are read over BOTH channels at once, and the ORDER
	-- OF THESE TWO BRANCHES IS THE CONTRACT:
	--
	--   mixed movement  -> TRADE_OFF     (something for, something against)
	--   uniformly worse -> DOWNGRADE     (nothing for, something against)
	--
	-- Why mixed comes first, in one sentence: if "worse on the top ranked word"
	-- outranked "mixed", then the SAME pair, under the SAME order, would read
	-- DOWNGRADE or TRADE_OFF depending only on whether the pack happens to price
	-- the word it gains — a price shaping a Step 1 verdict, which clause B
	-- forbids in BOTH directions. With mixed first, that pair is a trade-off
	-- either way, and the price cannot move the label. It is also what keeps the
	-- owner's cloak (loses Stamina, gains Strength) an amber chip instead of
	-- silently unmarked. DOWNGRADE is therefore reserved for uniformly-worse
	-- pairs, and it stays order-relative: which words move at all is decided by
	-- the list in force, so the same pair flips DOWNGRADE <-> UPGRADE on a
	-- different list with no code change (AC-8).
	if anyFor and anyAgainst then
		return TRADE_OFF, tradeOffReason(cand, eq, order, weights), "trade_off"
	end

	if anyAgainst then
		-- Uniformly worse. Rule 4's naming rule: the HIGHEST-RANKED word of the
		-- order that differs if one does, otherwise the priced off-order word
		-- that moved against.
		return "NOT_UPGRADE",
			loseReason(firstDiff or offAgainst[1]), "downgrade"
	end

	-- Uniformly favourable — rule 5. The only path to a green arrow, and it names
	-- the word that decided it (the owner's permanent "decided by <stat>" line):
	-- the highest-ranked order word that moved, else the priced off-order word.
	return "UPGRADE", winReason(gained or offFor[1]), "upgrade"
end

-- THE CASCADE ITSELF. Pure: two parsed stat tables, an order, a weights table.
-- Returns verdict, reason, state (see the block comment for the state words).
-- Public because the card's tests drive THIS function, and because Step 2 must be
-- able to hand it a different order without touching this file.
function Verdict.rankedVerdict(candStats, eqStats, order, weights)
	local cand = type(candStats) == "table" and candStats or {}
	local eq   = type(eqStats)   == "table" and eqStats   or {}

	-- Rule 0 — an order that cannot be resolved is not a guess (C1b's rule:
	-- "stay UNKNOWN instead of reading a guessed arrow").
	if type(order) ~= "table" or #order == 0 then
		return "UNKNOWN", "not judged: no stat order resolved for this class and role",
			"unresolved"
	end

	-- NO HAND-OFF. The Oct 19 off-order rule used to stop the ordinal read here
	-- and hand the pair to the weight pack. The owner's ruling of 2026-11-13
	-- supersedes that ON THE VERDICT PATH (declared on the card, not slipped in):
	-- a priced stat off the order is now READ BY THE CASCADE ITSELF — it counts as
	-- movement, so a pair that gains crit and loses Strength is MIXED and reads
	-- TRADE_OFF however the price adds up. The direction of that supersede is
	-- strictly fewer greens, never more, which is the Oct 19 ruling's own intent.
	-- weightedResolution stays reachable and tested (it is the Step 3 engine); it
	-- just cannot decide a Step 1 verdict.
	return Verdict.rankedCore(cand, eq, order, weights)
end

-- ── THE NAMED THRESHOLD ────────────────────────────────────────────────────
-- The smallest weighted MARGIN that may overturn a TRADE_OFF — into an UPGRADE
-- when the candidate is ahead, and into a NOT_UPGRADE when it is behind (card
-- t_4590ab7e, item 1: ONE threshold, both directions).
--
-- THE FORMULA, read out of the code rather than asserted. `weightedScore`
-- returns two numbers:
--   delta    = sum of  w[k] * (cand[k] - eq[k])   — the weighted NET
--   disagree = sum of |w[k] * (cand[k] - eq[k])|  — the TOTAL disagreement, i.e.
--              the weighted gain PLUS the weighted loss
-- so `delta / disagree` is exactly the SIGNED form
--   (gain − loss) / (gain + loss)
-- because `gain` is the sum of the positive terms and `loss` the magnitude of the
-- negative ones, so `delta = gain − loss` and `disagree = gain + loss`. The margin
-- the threshold is actually compared against is that quantity's MAGNITUDE,
--   margin = |delta| / disagree = |gain − loss| / (gain + loss),
-- so a lead and a deficit of the same size are the same distance from the bar and
-- ONE constant governs both.
--
-- The equivalence to the "three times" claim is then algebra, not assertion, and
-- it reads the same in both directions:
--   a GAIN resolves  <=>  (g − l)/(g + l) >= 0.5  <=>  2g − 2l >= g + l  <=>  g >= 3l
--   a LOSS resolves  <=>  (l − g)/(g + l) >= 0.5  <=>  2l − 2g >= g + l  <=>  l >= 3g
-- i.e. the side that wins must outweigh the side that loses by at least three to
-- one, whichever side that is.
--
-- WORKED ON REAL CASES, both directions of the same one-parameter family
-- (WARRIOR.melee = STR 1.0 / STA 0.3, equal Armor, so with a +s Strength candidate
-- against a +w Stamina worn item: gain = s, loss = 0.3w).
--   the near-tie in the case set (`weights_scoring.js`, PAIR_NEARTIE: +3 Strength
--   vs +4 Stamina): g = 3.0, l = 1.2 → margin = (3.0 − 1.2)/(3.0 + 1.2) = 1.8/4.2
--   = 0.4286 < 0.5 and 3.0 >= 3 × 1.2 = 3.6 is FALSE — it stays TRADE_OFF.
--   the clear win (PAIR_CLEARWIN: −1 Strength, +4 Stamina, +70 Armor): delta =
--   −1.0 + 1.2 + 3.5 = 3.7, disagree = 5.7 → margin 0.649 >= 0.5 → UPGRADE, and
--   g = 4.7 >= 3 × 1.0 = 3.0.
--   the DOWNWARD boundary (candidate +3 Strength vs worn +30 Stamina): g = 3.0,
--   l = 9.0 → margin = 6.0/12.0 = 0.5 exactly, and l = 9.0 = 3 × g — the first
--   item that resolves downward, which is what `t_4590ab7e`'s test pins.
--
-- 0.5 is a POLICY choice, not a measurement, and it is the one number this
-- layer adds to the repo. The card requires a threshold that is REAL, so the
-- near-tie case in the case set sits just under it (margin 0.43) and the
-- non-vacuity leg sets this to 0 and requires that case to redden.
--
-- A NON-NUMBER (nil, a string, a boolean) disables the layer entirely: no
-- threshold, no verdict widening in EITHER direction. Public so a test can move
-- it; no shipped path writes it.
Verdict.WEIGHT_THRESHOLD = 0.5

-- The weights table for a class/spec, VALIDATED — or nil. Public: it is the
-- one place the resolution order and the validation can be driven directly.
--
-- The resolution order (the addon's own role vocabulary first, then the
-- client's literal):
--   1. `clientRole` — the client's uppercase literal, lowercased. This is how
--      a class's THIRD spec is reachable: a Protection paladin's client role
--      is TANK, which ROLE_ALIAS folds to "spell" for the ORDER (a
--      conservative proxy — RULING (c) on t_0b4ddfa9), while a weight table
--      can carry the real Prot pack. A "tank" key that could never be
--      consulted would be dead data, so the literal wins over the folded word.
--   2. `role` — the addon's own word ("melee" | "spell"), accepted only when
--      it is a role this class actually documents. ChestAdvisor.lua's
--      buildSpec passes the class TOKEN as `role` for a pure class with no
--      role picked; that label must never be mistaken for a spec key.
--   3. A PURE class falls back to its single documented order's key: a Warrior
--      with no role picked has exactly one spec, and it is "melee". Step 3 is
--      SKIPPED when the pack it resolves to is published for a DIFFERENT client
--      role word than the one the client named — the F2 NOTE below.
-- Anything else returns nil, and the ordinal path owns the row: an unknown
-- class, a class with no table, a hybrid with no resolved role, a client word
-- whose pack belongs to another client word (the F2 fail-closed), or a table
-- that fails validation (below).
--
-- NOTE on step 3 (card t_6fda2ec5 — gate t_9362815f, F3; corrected by card
-- t_41697d02 — gate t_35b75690, F2): that fallback is unconditional for a pure
-- class whose pack is not published for a client role word. It fires whatever
-- `role` was passed, so weightsFor("WARRIOR", "spell") and
-- weightsFor("WARRIOR", nil, "HEALER") both resolve WARRIOR.melee instead of
-- returning nil. That is deliberate — it mirrors classRoleOrder, which ignores
-- `role` for a pure class too — and it is still what the shipped caller needs:
-- a Warrior's only picker word is "melee", the client's DAMAGER literal folds
-- to nil -> the class token -> this step, and no literal key points at
-- WARRIOR.melee (WARRIOR.tank is a different table), so the fail-closed below
-- does not reach it.
--
-- The correction. This NOTE used to say "no shipped caller reaches it". For
-- PRIEST that is false, and has been since card t_f823566a made it a two-key
-- class: a Holy priest's client role IS the literal HEALER, a shipped caller of
-- step 1 — and with its key absent or unreadable, the class token falls through
-- step 2 to step 3 and answers with `spell`, the SHADOW pack (the same table
-- object as `damager`, so the table publishes `spell` as the DAMAGER pack), thus
-- judging a Holy row by Shadow numbers and widening it instead of declining.
-- A client word the table does not carry therefore REFUSES a fall-through pack
-- that is published for another client word: the row reads its ordinal verdict
-- and the reason says why. Executed in ChestAdvisor/tests/weights_scoring.js.
--
-- The table is refused WHOLE unless EVERY one of the schema's keys (WEIGHT_KEYS
-- above — originally seven plus SPOW, extended to eighteen by card t_795eee9e
-- and to nineteen by card t_3cdbb70a's FAP; card t_9d3273cb retired the two
-- spell keys that once made it twenty-one, and card t_4e1e1b1d (DD-2) added
-- HEAL plus one key per school of spell damage on top of that. The count is
-- deliberately NOT spelled out: the set IS WEIGHT_KEYS, and a number written
-- here goes stale the next time a card adds a key (card t_d53877b1 §3).
-- is a finite, non-negative number, `source` is a non-empty string, AND `source`
-- CARRIES
-- the provenance marker the weight file publishes (SF.WEIGHTS_MARKER). A
-- partial table is not a table: a missing key is not a 0, and a stat the table
-- does not price must not be silently dropped out of the sum. The marker check
-- is what makes Weights.lua's honest label load-bearing rather than
-- decorative — an unlabelled table is never used, and neither is one in an
-- environment that cannot say what the marker is (fail-closed).
--
-- The OPTIONAL `directional` field (card DD-0) is ACCEPTED here — it is how a
-- table declares the keys that deliberately override the pack its `source`
-- names, and refusing it would force every honest non-pack value to be hidden
-- as "sourced". Accepting it loosens NOTHING above: every key in WEIGHT_KEYS
-- is still required and `source` still carries the marker. (This comment used
-- to say "eight keys" — the count was true when DD-0 was written and is not
-- any more: the set IS WEIGHT_KEYS, which card t_9d3273cb shortened by retiring
-- DD-1's two spell keys. Naming the list instead of counting it is the only
-- wording that cannot go stale; card t_d53877b1 §3 reports the same drift in
-- the two places it was still written out — Weights.lua's header, which this
-- card DID touch, and the citation diff's refusal message, which derives the
-- number from the key list it prints.) What IS enforced is that the field is a list of
-- KEYS — a table whose every entry names a key in WEIGHT_KEYS and is exactly
-- `true`. An entry naming a key the table does not carry
-- (or carrying a VALUE instead of `true`) refuses the table whole, because a
-- DIRECTIONAL marker pointing at nothing is a claim no test can check, and this
-- file's posture is to decline rather than to ignore. Absent is the normal
-- case and means "no key in this table overrides its citation".
function Verdict.weightsFor(class, role, clientRole)
	if type(class) ~= "string" then return nil end
	local store = (type(_G) == "table") and rawget(_G, "StatForge") or nil
	local all = (type(store) == "table") and rawget(store, "Weights") or nil
	if type(all) ~= "table" then return nil end
	local byClass = rawget(all, class)
	if type(byClass) ~= "table" then return nil end

	local orders = rawget(Verdict.ORDERS, class)
	if type(orders) ~= "table" then return nil end

	-- The client's own word (when it has one) and whether this table carries it.
	local named, carried = nil, false

	local key = nil
	if type(clientRole) == "string" then
		local literal = clientRole:lower()
		named = clientRole:upper()
		-- card t_6c3f414a (DD-3): a literal that names a spec ONLY for one role
		-- (LITERAL_NEEDS_ROLE) claims its table only when that role is this
		-- character's. Everything else — every literal not listed there — is
		-- untouched, so the Protection paladin's TANK still beats its folded
		-- "spell" exactly as before.
		local needs = rawget(LITERAL_NEEDS_ROLE, class)
		local neededRole = (type(needs) == "table")
			and rawget(needs, named) or nil
		if neededRole ~= nil and role ~= neededRole then
			-- The client's word belongs to ANOTHER role's spec for this class:
			-- ignore it and let the role steps answer.
		elseif type(rawget(byClass, literal)) == "table" then
			key = literal
			carried = true
		end
	end
	-- an unidentified druid melee (no literal, or a literal that does not name one of its packs,
	-- e.g. HEALER or a word the client does not have) gets no pack and keeps the ordinal path (review item 11, round 2).
	if type(role) == "string" then
		local needsLiteral = rawget(ROLE_NEEDS_LITERAL, class)
		local allowed = (type(needsLiteral) == "table") and rawget(needsLiteral, role) or nil
		if type(allowed) == "table" and (named == nil or rawget(allowed, named) ~= true) then
			return nil
		end
	end
	if key == nil and type(role) == "string"
		and type(rawget(orders, role)) == "table"
		and Verdict.classRoleOrder(class, role) ~= nil then
		key = role
	end
	if key == nil and not isHybrid(class) then
		for k in pairs(orders) do
			key = k
			break
		end
	end
	if key == nil then return nil end

	local table_ = rawget(byClass, key)
	if type(table_) ~= "table" then return nil end

	-- FAIL-CLOSED (card t_41697d02 — gate t_35b75690, F2). The client named one
	-- of its own role words and this table does not carry it: if the pack the
	-- fall-through resolved to is PUBLISHED for a different client word (see
	-- servesAnotherLiteral), it must not answer this one. A Holy priest is the
	-- case: with `healer` absent or unreadable, steps 2 and 3 used to land on
	-- `spell` — the DAMAGER/Shadow pack, the same table object as `damager` —
	-- and widen a Holy row to UPGRADE instead of declining to the ordinal
	-- trade-off. Refusing hands the row back to the ordinal path, which is what
	-- a missing table means everywhere else in this file. A pack no literal key
	-- publishes (WARRIOR.melee) never trips this: a Fury warrior's DAMAGER
	-- finds no key either, and there the fall-through is the shipped, correct
	-- answer.
	if named ~= nil and not carried and CLIENT_ROLE_LITERALS[named]
		and servesAnotherLiteral(byClass, table_, named) then return nil end

	local source = rawget(table_, "source")
	if type(source) ~= "string" or source == "" then return nil end
	-- The provenance gate. The marker is read OUT of the environment (Weights.lua
	-- publishes it as StatForge.WEIGHTS_MARKER), never spelled here, so the label
	-- the tables carry and the label the validator looks for cannot drift — and
	-- `find` is plain (4th arg true): the marker is text, not a pattern.
	local marker = rawget(store, "WEIGHTS_MARKER")
	if type(marker) ~= "string" or marker == "" then return nil end
	if not string.find(source, marker, 1, true) then return nil end
	for _, k in ipairs(WEIGHT_KEYS) do
		local w = rawget(table_, k)
		-- NaN fails `w ~= w`; +inf fails the equality; -inf fails `w < 0`.
		if type(w) ~= "number" or w ~= w or w < 0 or w == math.huge then
			return nil
		end
	end
	-- DIRECTIONAL (card DD-0): the OPTIONAL list of keys that override the pack
	-- this table cites. This accepts the field and validates its SHAPE only — it
	-- reads no number, moves no weight, and relaxes none of the checks above.
	local directional = rawget(table_, "directional")
	if directional ~= nil then
		if type(directional) ~= "table" then return nil end
		for k, v in pairs(directional) do
			-- Exactly `true`, and a key this table actually carries: `source`
			-- and any other name is not a weight, and a value is not a marker.
			if v ~= true or WEIGHT_KEY_SET[k] ~= true then return nil end
		end
	end
	return table_
end

-- ============================================================================
-- Card t_e2603a9c (PR #34 item 1 — the owner's OPTION 3 ruling; it supersedes
-- the HOLD card's option 2, under which this gate read the class ORDER):
-- the unpriced-stat gate. One section, one word map, one reason shape.
--
-- THE RULING, as implemented: a compared stat closes the pair (UNKNOWN)
-- ONLY if its word is in UNCONFIRMED_UNITS (and not in
-- UNCONFIRMED_DIFFERENCE_ONLY).  A zero or missing weight means the stat is
-- worth 0 to this spec; the weighted layer already yields 0 * delta = 0, so
-- it contributes nothing and does NOT close the pair.  Card C1 (Vibe Check
-- audit), option (a), supersedes the t_e2603a9c OPTION 3 zero-weight half.
--
-- Consequences, each pinned or cited:
--  * SPOW IS PRICED wherever its pack prices it (non-zero: MAGE 1.2,
--    PRIEST 1.2 / 0.8, PALADIN.melee 0.3 ... — and it is not listed): it
--    flows into the weighted layer and this gate does not intercept it —
--    the ruling names it explicitly. The t_b7cd07e1 AC-A pair (a MAGE
--    trade-off whose only weighted gain is SpellPower) still answers its
--    weighted UPGRADE (this card's AC-3 keeps that pin green), and the
--    break-8 mutation — MAGE.spell.SPOW zeroed — re-gates the very pair by
--    name (this card's requirement 3a).
--  * A LISTED word answers UNKNOWN on EVERY row that carries it, in EVERY
--    weight state — present table, zeroed weight, or no table at all. The
--    unit being unconfirmed is a property of the stat, not of any class's
--    weight, and the ruling's "otherwise the verdict is UNKNOWN" holds even
--    where nothing resolves a pack.
--  * A word whose RESOLVED weight is zero is worth 0 to this spec: the
--    weighted layer already yields 0 * delta = 0, so it contributes nothing
--    and does NOT close the pair.  Card C1 (Vibe Check audit), option (a),
--    supersedes the t_e2603a9c OPTION 3 zero-weight half.
--  * the RULING (b) tiebreak terms and WeaponDps are never reported by this gate because they
--    are not on UNCONFIRMED_UNITS; since card C1 no weight state closes a
--    pair, so no per-word exemption exists any more (the X guards in
--    t_acc9fd97 pin that they come back nil). A pair with no resolved weight
--    table is judged the same way — only the list can close it, and the
--    ordinal path owns the rest of the row.
--
-- WHY THE SECTION SITS HERE: it needs WEIGHT_WORD (the single word map)
-- above; every gate call site (gates 5b/8b of evaluate, the two decision
-- points of compareWeapon) sits below and goes through Verdict.unpricedWord
-- — the ONE pricing predicate, so no second copy of the rule can exist.
--
-- UNCONFIRMED_UNITS — the explicit part of the ruling, as DATA (AC-7).
-- SHRINK-ONLY (requirement 1): an entry may leave this list only by a ruling
-- event carrying BOTH (a) the owner's measured in-game read that replaces
-- the entry with a unit statement, and (b) the owner's instruction. An entry
-- that leaves without both is a finding to flag. WHY THIS IS NOT the
-- t_b7a9e7a5 PERMANENT BAN: that ruling's rationale was that the banned stat
-- has no price anywhere. THIS list is DESIGNED TO SHRINK TO EMPTY — empty is
-- the goal: every entry is a unit the owner measures in-game (the item-2
-- probe is that read), and each confirmed unit removes one entry.
--
-- ── CARD t_3cdbb70a (DD-1) TOOK HIT AND CRIT OFF THIS LIST; CARD t_d53877b1
--    (THE OWNER'S OPTION C) PUTS THEM BACK, AS DIFFERENCE-ONLY ENTRIES ──────
-- The two entries DD-1 removed read
--     Hit  = true, -- hit rating vs percent: unconfirmed
--     Crit = true, -- crit rating vs percent: unconfirmed
-- and they are below again. This is NOT a revert of DD-1's split, and not a
-- silent tidy-up in either direction; the sequence matters, so it is recorded.
--
-- WHY DD-1 REMOVED THEM: AC-B/AC-C required a caster's spell-hit item and a
-- warrior's melee-hit item to resolve UPGRADE through their own half's weight.
-- A PRESENCE-based list closes every row carrying the word in every weight
-- state, so while Hit and Crit sat here neither AC could be satisfied and the
-- split would have been inert. DD-1's answer was a per-class 0: the caster
-- pack carried a 0 on the melee word, the melee pack a 0 on the spell word, so
-- the wrong half closed by the zero-weight rule and the right half was priced.
-- (Card t_9d3273cb retired the split, and both zeros with it: one word, one
-- price. See the retirement note under WEIGHT_KEYS.)
--
-- WHY THEY ARE BACK (measured, not argued — card t_5074d195's probe, and the
-- ruling recorded on t_d53877b1 §2): with the words off the list, the pack's
-- number became a price the comparator multiplies into a DECISION, and the
-- unit that number is expressed in has never been measured. The director's
-- probe set the ROGUE's crit price from 0.9 to 1,000,000 on the card's own
-- repro (+5 Agility against a worn +3 Agility, +1% crit): every one of the eight
-- weights answered UPGRADE. That is the failure this guard is for — the tool
-- asserted a win over the crit without reading what the crit was worth, in a
-- unit nobody had measured. A priced word whose unit is unknown is not a price.
--
-- WHY "DIFFERENCE-ONLY" RATHER THAN PRESENCE (the ruling verbatim: "one
-- predicate on the difference, not on the word's presence"). A presence rule
-- would re-close every hit/crit row and make DD-1's split inert again — that
-- is the option the owner did NOT choose. The difference rule is the narrow
-- one: when the two sides carry the SAME value of the word, the unit cancels
-- out of the comparison (0.9 per rating point times an equal number on both
-- sides shifts both sides by the same unknown factor, so it cannot flip the
-- verdict), and the pair is decided normally on the terms that do differ. When
-- the values DIFFER, the unit is load-bearing and unmeasured, so the pair
-- fails closed. The set below is what makes an entry difference-only; a word
-- in this list but NOT in this set keeps the original presence rule (Dodge and
-- Parry, which the ruling HOLDS unchanged).
--
-- ── CARD t_b91b29f9: THE SPLIT'S OWN HALVES JOIN THE SAME DISCIPLINE ────────
-- DD-1 (t_3cdbb70a) added the two spell words and priced them on every caster
-- pack, and put neither on these lists — so the caster's half of the split was
-- priced in a per-rating unit nobody had measured while the melee half was
-- guarded. Measured at the #34 head (docs on card t_b91b29f9): a MAGE pair whose
-- only difference is "+2% spell crit" answered UPGRADE on the retired spell
-- key's 0.6, and an otherwise-equal pair carrying "+1% spell crit"
-- answered NOT_UPGRADE "equal" — the same fail-open the melee ruling closed,
-- still open on the spell side. Same word shape, same ruling, so the same two
-- lists and the same predicate: NOT a third mechanism.
-- Card t_9d3273cb ends the episode: the two words are retired, so the two
-- entries below are gone and their failure mode with them.
--
-- WHAT IS MEASURED, AND WHAT STILL BLOCKS THE DECISION (card t_b91b29f9).
-- DD-1 did not settle the unit and this guard does not settle it either, but the
-- owner's in-game read recorded on card t_b91b29f9 DOES measure the SCALE:
-- these stats arrive as RATINGS at 10 (hit) and 14 (crit) rating points per 1%.
-- A rating count is not a percent, and the weighted layer consumes whatever
-- number the parse hands it — so the conversion is what makes the two units
-- one unit, and card t_ea404bae lands it (as a RATING, on the tooltip path:
-- see PERCENT_TO_RATING above).
--
-- ── CARD t_ea404bae: HIT AND CRIT RETIRE (THE UNIT IS SETTLED AS A RATING) ──
-- The measurement below still stands, and so does the owner's word; what
-- changed on 2026-10-19 is WHICH unit this module records. The reviewer's ruling
-- reverses the direction an earlier commit on this branch took — normalise to
-- RATING, not to percent (see the PERCENT_TO_RATING block above for the
-- argument and for the one conversion site) — and the client's own C_Item
-- number is that rating. The unit question for HIT and CRIT is therefore
-- ANSWERED: the shrink-only rule's two conditions are both satisfied, and both
-- words leave BOTH lists.
--   (a) THE MEASUREMENT — the owner's in-game read, 2026-10-18, live client,
--       `/dump C_Item.GetItemStats(link)`: Reliquary Mantle reports
--       ITEM_MOD_HIT_RATING_SHORT = 4 against a "+0.4% hit" tooltip (10 rating
--       per 1%), Illusionary Rod reports ITEM_MOD_CRIT_RATING_SHORT = 14
--       against a "+1.0% crit" tooltip (14 per 1%). The constants above cite
--       the same read.
--   (b) THE OWNER'S WORD — recorded on card t_ea404bae: "HIT and CRIT come off
--       the unconfirmed-unit list".
-- This is the ONE ruling event the previous note anticipated, and it is NOT a
-- loosening of the ruling: the guard existed because a priced word whose unit
-- is unknown is not a price. The unit is no longer unknown — the client hands
-- over ten and fourteen rating per percent, measured — so the price is a price
-- the tool can spend. A differing pair these two entries used to close now
-- reaches the weighted layer and is decided on the pack's own numbers.
--
-- ── CARD t_9d3273cb: THE LAST TWO ENTRIES RETIRE ───────────────────────────
-- The two spell words leave with their two weight keys (see the retirement note
-- under WEIGHT_KEYS). They were never a different stat from Hit and Crit — the
-- client's own recap, read verbatim:
--
--   "Spell, melee, and ranged hit chance are combined, as are spell, melee,
--    and ranged critical chance."
--
-- — and a word that does not exist needs no entry, no factor and no guard.
-- Dodge and Parry used to remain here (unmeasured scale, presence rule).
-- Forever 1.60.1 build 70862 combatratings.txt measures them (dodge 12,
-- parry 15, block chance 5 per 1%), the same factors the leveling packs
-- price against, so they have left this list. The presence-rule mechanism
-- stays for any future unconfirmed word.
Verdict.UNCONFIRMED_UNITS = {
	-- Empty: every combat rating the packs price now has a measured factor.
	-- Card t_9d3273cb: THE TWO SPELL ENTRIES ARE GONE. They joined this list on
	-- card t_b91b29f9 only because the split gave them a per-rating price with no
	-- factor; with the split retired there is no such word to guard — a spell
	-- crit item is a Crit item and prices at the crit weight, measured at 14
	-- rating per 1%. Nothing else about this list changed.
	--
	-- Dodge and Parry are its remaining members, both by PRESENCE. The
	-- difference-only set below is therefore EMPTY, which is the designed end
	-- state its own note has described since t_d53877b1 — not an accident. The
	-- predicate and its two call sites stay, so a future ruling can populate the
	-- set without re-inventing the mechanism.
}

-- The difference-only half of the list above (card t_d53877b1). A word here is
-- UNCONFIRMED (the unit question above is open) but does NOT close a pair by
-- being PRESENT on one side; it closes it only when the two sides DIFFER. See
-- Verdict.unconfirmedDifference, the one predicate that reads it, and the
-- section note above for why the narrow rule is the ruling.
--
-- Card t_ea404bae removed Hit and Crit from this set together with the list
-- above — one ruling event, both halves, so the two tables never disagree about
-- a word. Card t_9d3273cb removed the two spell halves with their two words,
-- and the set is now EMPTY: every word still guarded is guarded by PRESENCE.
-- The mechanism stays (one predicate, two call sites) for the next ruling that
-- needs it; ChestAdvisor/tests/t_ea404bae.js N8 pins the emptiness (with
-- t_d53877b1.js G9 and t_b91b29f9.js M7 reading the same lists from the other
-- side) so a stray entry cannot reappear unremarked.
Verdict.UNCONFIRMED_DIFFERENCE_ONLY = {
}

-- wordUnpriced(word, _weights): the gate's pricing test for ONE word.
--   _weights — retained for signature compatibility; unused since card C1
--             (Vibe Check audit), option (a), made zero/missing weight a
--             non-event (the weighted layer already yields 0 * delta = 0).
--             Supersedes the t_e2603a9c OPTION 3 zero-weight half.
--
-- The ONLY word that closes the pair is one listed in UNCONFIRMED_UNITS
-- (and not in UNCONFIRMED_DIFFERENCE_ONLY).  A zero or missing weight means
-- the stat is worth 0 to this spec; it contributes nothing and does NOT
-- close the pair.  The former per-word zero-weight exemptions (armour,
-- weapon DPS, feral AP and the like) are now subsumed: a 0 weight is simply 0.
--
-- Card t_d53877b1 (option C): a difference-only entry is NOT closed by its
-- absence-presence alone — Verdict.unconfirmedDifference closes it on the
-- pair.  Falling through here lets the pair-level predicate own the
-- difference.
local function wordUnpriced(word, _weights)
--
-- Card t_4e1e1b1d (DD-2) added seven more priced words (Healing and one per
-- spell-damage school) and needs no entry here for the same reason the other
-- former exemptions are gone: a spec that prices the word lets it decide the
-- pair, and a spec that prices it 0 gets a genuine 0 rather than a closed
-- pair. The exempt-list this file carried for it before card C1 no longer
-- has a job.
	local list = rawget(Verdict, "UNCONFIRMED_UNITS")
	local only = rawget(Verdict, "UNCONFIRMED_DIFFERENCE_ONLY")
	if type(list) == "table" and list[word] == true
		and not (type(only) == "table" and only[word] == true) then
		return true
	end
	return false
end

-- Public: Verdict.unpricedWord(stats, weights) — the first (sorted) word of
-- `stats` on the unconfirmed-unit list (UNCONFIRMED_UNITS), or nil when no
-- word qualifies. `weights` is accepted for compatibility and ignored since
-- card C1. An empty stats table carries no word and answers nil. Every gate
-- call site — the candidate side (evaluate gate 5b) and the equipped side
-- (evaluate gate 8b; the same two decision points in compareWeapon) — asks
-- through this one predicate.
function Verdict.unpricedWord(stats, weights)
	if type(stats) ~= "table" then return nil end
	local words, seen = {}, {}
	for w in pairs(stats) do
		if type(w) == "string" and not seen[w] then
			seen[w] = true
			words[#words + 1] = w
		end
	end
	table.sort(words)
	for _, w in ipairs(words) do
		if wordUnpriced(w, weights) then return w end
	end
	return nil
end

-- Public: Verdict.unpricedWordReason(word) — the gate's ONE reason shape: the
-- word in the module's own vocabulary (never the client key the read came
-- from), in player-facing wording.  Since card C1 (Vibe Check audit),
-- option (a), the gate closes a pair only for a listed word whose unit is
-- unconfirmed; a zero or missing weight is worth 0 and does not close the
-- pair.  The phrase "no confirmed value for this stat for this class" is
-- true of the one remaining cause.
function Verdict.unpricedWordReason(word)
	return "cannot judge: " .. word
		.. " (no confirmed value for this stat for this class)"
end

-- ── SUPERSEDED: THE PRICED OFF-ORDER GUARD (card t_e2ebb44e) ────────────────
-- This file used to carry `Verdict.offOrderPricedWord` and
-- `Verdict.offOrderReason`, and `evaluate` called them above the dominance call:
-- a word the resolved pack PRICED but the class ORDER did not rank closed the
-- pair as UNKNOWN, naming that word ("cannot judge: Spirit ...").
--
-- WHY IT WAS RIGHT WHEN IT WAS WRITTEN. At the tree the card was cut from
-- (`2ff0926`, PR #55's base) the ordinal proof read the ORDER's terms alone, so
-- a priced word outside the order was genuinely unweighable: a Holy priest's
-- "+22 Healing" counted for nothing and the pair answered "equal" — or, mirror-
-- wise, told a healer to drop 22 Healing for 2 Intellect. Closing the pair was
-- the honest interim answer, and the card said so: "the interim answer: fail
-- closed; widening dominance is a separate owner decision".
--
-- WHY IT IS GONE (owner ruling 2026-11-05; RECORDED, not deleted quietly). Card
-- t_da23ec75 — "order = wording, priced set = proof" — landed on main as PR #69
-- and gave the dominance proof `Verdict.proofTerms(order, weights)`: the order's
-- words PLUS every word this pair's pack prices. The proof now weighs exactly
-- the words the guard claimed it could not, and it words the win or loss with
-- the term that decided it — "upgrade: better on SpellPower — the weighted gain
-- outweighs the Spirit loss".
--
-- Measured on this tree before removal: the guard turned the owner's own AC-1
-- fixture (a priest mace against the equipped staff) from NOT_UPGRADE into
-- "cannot judge: SpellPower", and closed every caster pair carrying SpellPower —
-- the commonest caster weapon stat — while the proof underneath was already
-- deciding those pairs correctly. A cost with no remaining protection.
--
-- WHAT THIS MEANS FOR THE LEDGERS. Any sweep that owned rows by "the guard
-- closed it" owns nothing by that rule now; its rows are re-derived from the
-- proof's own reasons. OPTION 2 (card t_468dd94a) asked the weighted layer to
-- decide these pairs instead of closing them — which is what the weighted layer
-- does now, so that card is superseded rather than waiting.


-- Public: Verdict.unconfirmedDifference(candStats, eqStats) — THE PAIR-LEVEL
-- PREDICATE the owner's option C rules for (card t_d53877b1 §2):
--
--   "Differing crit or hit => UNKNOWN while HIT/CRIT is on the unconfirmed
--    list. One predicate on the difference, not on the word's presence."
--
-- Returns the first difference-only word (see UNCONFIRMED_DIFFERENCE_ONLY, in
-- the unconfirmed list's own fixed order — `table.sort`ed, so the answer is
-- repeatable) whose value is not equal on the two sides, or nil when every such
-- word is level. That set has been EMPTY since card t_9d3273cb retired its last
-- two words, so on the shipped tree this answers nil on every pair.
--
-- CARD t_9d3273cb EMPTIED this set: its last two members were DD-1's spell
-- halves, retired together with the two weight keys they belonged to. So on the
-- shipped tree the loop below has nothing to walk and this function answers nil
-- on every pair — not because the comparison found a word LEVEL, but because
-- there is no word left in the set to read. Hit and Crit had already left it on
-- card t_ea404bae, with their unit measured at 10 and 14 rating per 1%.
--
-- THE EMPTINESS IS NOT ASSERTED HERE — it is pinned by execution, in the
-- batteries that own each half: ChestAdvisor/tests/t_ea404bae.js N8 asserts the
-- difference-only set is EMPTY (its designed end state since t_d53877b1),
-- t_d53877b1.js G9 asserts the same pair readings for the same lists, and
-- t_b91b29f9.js M7 asserts the spell words read nil on both. (An earlier
-- version of this note credited t_9d3273cb.js, which pins the WORDS and their
-- PRICES — not the set's emptiness — so a reader following it found nothing.)
-- The predicate itself stays, with its two call sites (evaluate's gate 8c and
-- compareWeapon's decision point), so a future ruling can populate the set
-- without re-inventing the mechanism.
--
-- ONE PREDICATE, ONE PLACE. Every pair call site asks here — evaluate's gate 8c
-- (armour rows) and compareWeapon's own decision point (weapon rows) — so no
-- second copy of the rule can exist, which is the same discipline the
-- unpriced-stat gate already holds.
--
-- EQUAL MEANS EQUAL AFTER THE ABSENCE RULE, and this is the whole point of the
-- difference form. The comparator treats a stat absent from one side as that
-- side carrying none of it (`weightedScore` subtracts `(c or 0) - (e or 0)`;
-- dominance reads a one-sided term as a gain or a loss). So "absent" and a
-- literal 0 are the SAME value to every consumer downstream, and a pair with
-- Hit 0 against no Hit cannot be moved by the unit either — treating them as a
-- difference would close a row on a distinction the verdict could not see.
-- Anything not a number is read as 0 for the same reason (the stats tables are
-- built by the parser and are numbers in every shipped path; this is the
-- fail-safe, not a second parser).
--
-- The REASON is the unpriced-stat gate's own shape, deliberately: from the
-- player's seat the cause is the same one sentence — the advisor has no value
-- it can trust for that stat for this class — and a second wording would be a
-- second thing to keep true. The WORD is the module's vocabulary (Dodge and
-- Parry on the shipped tree), never the client key the read came from.
function Verdict.unconfirmedDifference(candStats, eqStats)
	local list = rawget(Verdict, "UNCONFIRMED_UNITS")
	local only = rawget(Verdict, "UNCONFIRMED_DIFFERENCE_ONLY")
	if type(list) ~= "table" or type(only) ~= "table" then return nil end
	local words = {}
	for word, flagged in pairs(list) do
		if flagged == true and only[word] == true then words[#words + 1] = word end
	end
	table.sort(words)
	local cand = type(candStats) == "table" and candStats or {}
	local eq   = type(eqStats)   == "table" and eqStats   or {}
	for _, word in ipairs(words) do
		local c, e = rawget(cand, word), rawget(eq, word)
		if type(c) ~= "number" then c = 0 end
		if type(e) ~= "number" then e = 0 end
		if c ~= e then return word end
	end
	return nil
end

-- ───────────────────────────────────────────────────────────────────────────
-- (card t_ee04ad6d) THE EQUAL CLAIM ON THE WEAPON PATH, AND WHAT IT MUST NOT HIDE
--
-- THE DEFECT (the reviewer, on the owner's Shaman tank, 2026-10-20). Two main-hand
-- maces, +20 Crit against +12 Crit, the SAME printed weapon damage per second:
--
--     NOT_UPGRADE, reason "equal weapon damage per second (5.50)"
--
-- Both counts ARE parsed, and Verdict.weaponStatLed answers false for a melee
-- role and for a role that did not resolve, so Verdict.compareDPS decides alone
-- on that branch and nothing on it reads the pair's Hit or Crit. A real, priced,
-- tooltip-separable crit difference was hidden behind a confident "equal": not a
-- missing answer, a WRONG CONFIDENT one, which is the fail-open shape this file
-- keeps removing. Measured pre-state, both spellings, and the near-equal control
-- that must survive: ChestAdvisor/tests/t_ee04ad6d.js.
--
-- WHAT THIS IS NOT. Not a new order, not a new weight, not a re-basing of the
-- melee weapon onto its stats: the ruling that a melee weapon is judged on its
-- damage per second (card t_16448f75, option (b)) stands on every pair whose
-- stats are level. It closes exactly the one thing the DPS basis cannot say:
-- that two weapons are THE SAME when their Hit or Crit is not.
--
-- THE MEASUREMENT is the tooltip's own, through Verdict.levelWithinResolution
-- (strict `d < eps`, over the 10 and 14 rating-per-percent factors this file's
-- PERCENT_TO_RATING table carries, half a printed step each): ONE helper, ONE
-- epsilon, no second threshold anywhere. A difference the tooltip cannot resolve
-- a client count against a one-decimal percent, say 12 against a lifted 12.6,
-- is LEVEL and the "equal" claim stands. That is the control the card demands,
-- and it is what keeps this gate from turning every weapon comparison into a
-- non-answer.
-- ───────────────────────────────────────────────────────────────────────────

-- Public: Verdict.beyondResolution(candStats, eqStats): the first word, in a
-- fixed order, whose two values differ by MORE than the tooltip's own step can
-- resolve; nil when every such word is level (or when there is no scale to
-- honour).
--
-- The words are exactly the ones a resolution is MEASURED for, the keys of
-- PERCENT_TO_RATING (Hit and Crit on this tree), SORTED so the answer is
-- repeatable, so the vocabulary cannot drift from the scale it spends, and a
-- word with no factor (a percent that passed through unrounded) is never claimed
-- as a gap here.
--
-- absent == 0 and a non-number == that side's silence, exactly as
-- Verdict.unconfirmedDifference reads them: both are conventions every consumer
-- downstream already uses, and a pair whose difference is only representational
-- must not be closed by this predicate. It returns a WORD, never a verdict:
-- what the caller does with it is the caller's rule.
--
-- THE ABSENT-SCALE DIRECTION, stated because it is a choice and not an accident:
-- a tree with no scale table (or an empty one) gets nil, so the pre-card DPS
-- claim stands. Naming a gap requires a MEASUREMENT, and the scale IS the only
-- thing that can measure one; inventing a step for a tree that lost its scale
-- would be the second epsilon this card forbids. That state cannot exist on a
-- shipped tree (the scale is published above and its two values are pinned by
-- t_ea404bae's battery, whose non-vacuity leg clears it to prove the pin bites),
-- so the fail-open is bounded to a tree that is already red elsewhere.
function Verdict.beyondResolution(candStats, eqStats)
	local scale = rawget(Verdict, "PERCENT_TO_RATING")
	if type(scale) ~= "table" then return nil end
	local words = {}
	for word in pairs(scale) do words[#words + 1] = word end
	if #words == 0 then return nil end
	table.sort(words)
	local cand = type(candStats) == "table" and candStats or {}
	local eq   = type(eqStats)   == "table" and eqStats   or {}
	for _, word in ipairs(words) do
		local c, e = rawget(cand, word), rawget(eq, word)
		if type(c) ~= "number" then c = 0 end
		if type(e) ~= "number" then e = 0 end
		if c ~= e and not Verdict.levelWithinResolution(word, c, e) then
			return word
		end
	end
	return nil
end

-- The refusal's player words, in the unpriced-stat gate's own shape: name the
-- WORD, then say why the answer is not available. It states both halves of what
-- the tool actually knows: the tie on damage per second, and the gap it cannot
-- place, because "cannot judge" on its own reads as a failed read rather than
-- as a comparison this path declines to make.
function Verdict.equalClaimReason(word)
	return "cannot judge: " .. word
		.. " (the weapons tie on damage per second, but their " .. word
		.. " differs by more than the tooltip's step)"
end

-- Public: Verdict.gateCloses(words, class, role, clientRole) — the gate's
-- OWN decision for the COMPARED words of a row: the word it would name, or
-- nil when the pair is not gate-owned. The changed-verdicts sweep calls it
-- to separate the gate's legitimate closures from real ordinal drift (its
-- AC-F) — the SAME code path the verdict uses, not a second copy of the rule
-- in the harness. Only a word on the unconfirmed-unit list closes a row,
-- whatever the weight state (card C1); class/role/clientRole are kept for
-- the callers' signature and are unused.
function Verdict.gateCloses(words, _class, _role, _clientRole)
	if type(words) ~= "table" then return nil end
	local list, seen = {}, {}
	for i = 1, #words do
		local w = words[i]
		if type(w) == "string" and not seen[w] then
			seen[w] = true
			list[#list + 1] = w
		end
	end
	table.sort(list)
	for _, w in ipairs(list) do
		if wordUnpriced(w) then return w end
	end
	return nil
end

-- ── Card t_4e1e1b1d (DD-2): the MAGE higher-of rule ────────────────────────
-- Verbatim from the class article this card cites:
--   "Frostfire Bolt always uses the higher of the Mage's spell damage bonuses
--    to Fire or Frost damage."
-- So on a Mage an item's Fire power and its Frost power are NOT two bonuses
-- added together: the effective bonus is whichever is HIGHER. Scoring them as a
-- sum would double-count (+20 Fire / +20 Frost would read as 40 — AC-C's "scores
-- as 20, not 40"), and scoring them as two independent terms would price a
-- school that cast never uses (AC-C's "Fire +20 / Frost +0 versus Fire +0 /
-- Frost +20 scores LEVEL").
--
-- WHY A PRE-PASS RATHER THAN A TERM INSIDE THE LOOP. max() is not distributive
-- over the per-word sum: the pair's delta is max(c_f, c_fr) - max(e_f, e_fr),
-- which no per-word sum can recover. The pass rewrites BOTH sides onto ONE
-- canonical word — the school carrying the largest of the four numbers, Fire on
-- a tie — carrying that side's max, and nils the other. weightedScore then sums
-- exactly one term for the pair, and the reason names a school the item
-- actually has (a Frost-only item is never called "Fire Power").
--
-- THE PASS IS INERT UNLESS ALL THREE HOLD: the class is MAGE, the two school
-- weights are equal and positive, and at least one side carries a school value.
-- It therefore cannot move a non-Mage row, and a table whose Fire and Frost
-- prices differ is left alone rather than silently using one of the two
-- numbers. When inert it returns the ORIGINAL tables — no copy, no new object —
-- so nothing downstream can observe a different table.
local function mageSchoolCollapse(candStats, eqStats, weights, spec)
	if type(spec) ~= "table" or spec.class ~= "MAGE" then return candStats, eqStats end
	local wf, wfr = rawget(weights, "SPFIRE"), rawget(weights, "SPFROST")
	if type(wf) ~= "number" or type(wfr) ~= "number" then return candStats, eqStats end
	if wf <= 0 or wf ~= wfr then return candStats, eqStats end
	local cand = type(candStats) == "table" and candStats or nil
	local eq   = type(eqStats)   == "table" and eqStats   or nil
	local function num(side, word)
		local v = side and rawget(side, word)
		return type(v) == "number" and v or 0
	end
	local fire, frost = math.max(num(cand, "FirePower"), num(eq, "FirePower")),
		math.max(num(cand, "FrostPower"), num(eq, "FrostPower"))
	if fire == 0 and frost == 0 then return candStats, eqStats end
	local keep = (frost > fire) and "FrostPower" or "FirePower"
	local drop = (keep == "FirePower") and "FrostPower" or "FirePower"
	local function rewrite(side)
		if type(side) ~= "table" then return side end
		local out = {}
		for k, v in pairs(side) do out[k] = v end
		out[keep] = math.max(num(side, "FirePower"), num(side, "FrostPower"))
		out[drop] = nil
		return out
	end
	return rewrite(cand or {}), rewrite(eq or {})
end

-- Score one pair against a validated weights table.
--   returns delta (weighted gain minus weighted loss; > 0 = candidate ahead),
--           disagree (the sum of the ABSOLUTE weighted terms), and the player
--           WORD of the largest weighted gain and of the largest weighted loss
--           (nil when there is none).
-- A term level on both sides — or absent on both — contributes nothing and
-- cannot be named. nil when nothing in the vocabulary moved at all.
-- `spec` is OPTIONAL and read ONLY by the MAGE higher-of pass above (card
-- t_4e1e1b1d); with no spec the sum is exactly what it was before the card.
local function weightedScore(candStats, eqStats, weights, spec)
	local cs, es = mageSchoolCollapse(candStats, eqStats, weights, spec)
	local cand = type(cs) == "table" and cs or {}
	local eq   = type(es) == "table" and es or {}
	local delta, disagree = 0, 0
	local gainWord, lossWord, gainValue, lossValue = nil, nil, 0, 0
	for _, k in ipairs(WEIGHT_KEYS) do
		local word = WEIGHT_WORD[k]
		-- CARD t_ea260b42: A PROOF_EXEMPT WORD IS TIEBREAK-ONLY HERE TOO, so its
		-- price is NOT spent by this subtraction. Armor, Block and WeaponDps are
		-- exempt from the dominance proof (see `Verdict.PROOF_EXEMPT`), and until
		-- this card the weighted layer read their prices anyway — which is how the
		-- same 40 Block came to decide a TRADE-OFF pair ("better on Block — the
		-- weighted gain outweighs the Stamina loss", fixture W4f) while being
		-- invisible on a one-sided one (fixture W4e), and how a WeaponDps price
		-- could be counted twice on the weapon path. The tiebreak at gate 9 is the
		-- ONE place these words may decide a pair; every other decision, including
		-- this one, is made on the priced RANKED words only.
		if not rawget(Verdict.PROOF_EXEMPT, word) then
			local c, e = rawget(cand, word), rawget(eq, word)
			if c ~= nil or e ~= nil then
				-- CARD t_43f8cd6f: a hit/crit difference under one tooltip step is
				-- the tooltip's own rounding, not a stat the player has — see
				-- Verdict.TOOLTIP_HALF_STEP_PERCENT. Level it here, at the one
				-- subtraction that prices those two words; every other word's
				-- comparison is untouched (its resolution is nil).
				local d = (c or 0) - (e or 0)
				if Verdict.levelWithinResolution(word, c, e) then d = 0 end
				local term = weights[k] * d
				delta  = delta + term
				disagree = disagree + (term < 0 and -term or term)
				if term > gainValue then gainValue, gainWord = term, word end
				if term < lossValue then lossValue, lossWord = term, word end
			end
		end
	end
	if disagree == 0 then return nil end
	return delta, disagree, gainWord, lossWord
end

-- The largest RAW loss on a relevance-set term, when the weights priced no
-- loss at all. Used for the reason ONLY (never for the verdict): a pair whose
-- weighted terms are all gains or level can still be an ordinal trade-off —
-- two stats down, one up, with the down ones priced at 0 for this spec — and
-- the player must not be told a clean win over an item that drops 8 Intellect.
--
-- A term the candidate does not carry AT ALL is still a loss when the worn item
-- carries it: that is the same absence the dominance test reads as "lesser",
-- and the reason names it as a word (the "absent, never 0" wording rule is
-- about the reason's own printed deltas, not about ranking a loss here).
local function largestRawLossWord(candStats, eqStats, order)
	local cand = type(candStats) == "table" and candStats or {}
	local eq   = type(eqStats)   == "table" and eqStats   or {}
	local worst, worstBy = nil, 0
	for _, word in ipairs(Verdict.relevanceSet(order)) do
		local c, e = rawget(cand, word), rawget(eq, word)
		local lost = nil
		if type(e) == "number" then
			if type(c) == "number" then
				if c < e then lost = e - c end
			else
				lost = e
			end
		end
		if lost ~= nil and lost > worstBy then worstBy, worst = lost, word end
	end
	return worst
end

-- The MIRROR of largestRawLossWord, for the DOWNWARD call (card t_4590ab7e,
-- item 1). The same asymmetry it exists to fix applies to the other side: a
-- weighted loss can be decided by a term the table prices while the OTHER,
-- outweighed term is priced at 0 — a tank losing Stamina on a +7 Strength swap
-- has a weighted loss AND a raw gain the weights never priced. Naming only the
-- loss would print a clean loss over an item that adds 7 Strength, exactly the
-- dishonest wording largestRawLossWord prevents in the other direction.
--
-- The same absence rule: a term the WORN item does not carry AT ALL is still a
-- gain when the candidate carries it. Used for the reason ONLY, never for the
-- verdict.
local function largestRawGainWord(candStats, eqStats, order)
	local cand = type(candStats) == "table" and candStats or {}
	local eq   = type(eqStats)   == "table" and eqStats   or {}
	local best, bestBy = nil, 0
	for _, word in ipairs(Verdict.relevanceSet(order)) do
		local c, e = rawget(cand, word), rawget(eq, word)
		local gained = nil
		if type(c) == "number" then
			if type(e) == "number" then
				if c > e then gained = c - e end
			else
				gained = c
			end
		end
		if gained ~= nil and gained > bestBy then bestBy, best = gained, word end
	end
	return best
end

-- The layer's whole answer, in BOTH directions (card t_4590ab7e, item 1):
--   * the weighted margin CLEARS the threshold in the candidate's favour ->
--     "UPGRADE" + reason;
--   * the weighted margin clears it AGAINST the candidate -> "NOT_UPGRADE" +
--     reason — the symmetric downward call. Before this, a net LOSS of the same
--     magnitude returned nil and the caller kept TRADE_OFF, so the same player
--     saw a clear win called "Upgrade" and an equally clear loss called
--     "Trade-off";
--   * anything else — no move, an exact tie, a margin under the threshold -> nil,
--     and the caller keeps today's TRADE_OFF.
-- ONE threshold constant governs both directions; nothing here adds a second.
local function weightedResolution(candStats, eqStats, spec)
	local threshold = Verdict.WEIGHT_THRESHOLD
	if type(threshold) ~= "number" or threshold ~= threshold then return nil end
	local weights = Verdict.weightsFor(spec and spec.class, spec and spec.role,
		spec and spec.clientRole)
	if weights == nil then return nil end
	local delta, disagree, gainWord, lossWord =
		weightedScore(candStats, eqStats, weights, spec)
	-- A tie (delta == 0), or no move at all (delta == nil), is NOT a widened
	-- verdict in EITHER direction: the two sides are weighted level, and the
	-- caller's TRADE_OFF is the honest reading.
	if delta == nil or delta == 0 then return nil end
	-- The margin is dimensionless (the net divided by the total disagreement), so
	-- the SAME threshold governs a gain and a loss: one number, both directions.
	local margin = (delta < 0 and -delta or delta) / disagree
	if margin < threshold then return nil end
	if delta > 0 then
		-- The why. The deciding GAIN is always named in the same player words the
		-- ordinal reason used. The loss is named too — the largest weighted one
		-- where the table prices one, and otherwise the largest RAW one (see
		-- largestRawLossWord), so a resolved trade-off is never worded as a clean
		-- win. Bare numbers and internal tokens never appear here.
		local reason = winReason(gainWord)
		local loss = lossWord or largestRawLossWord(candStats, eqStats, spec and spec.order)
		if loss ~= nil and loss ~= gainWord then
			reason = reason .. " — the weighted gain outweighs the " .. playerWord(loss) .. " loss"
		end
		return "UPGRADE", reason
	end
	-- The DOWNWARD call (card t_4590ab7e, item 1). The deciding LOSS is named in
	-- the ordinal NOT_UPGRADE vocabulary (loseReason), and the outweighed gain is
	-- named too — the largest weighted one where the table prices one, and
	-- otherwise the largest RAW one (largestRawGainWord) — so a resolved loss is
	-- never worded as a clean loss over an item that clearly adds something.
	local reason = loseReason(lossWord)
	local gain = gainWord or largestRawGainWord(candStats, eqStats, spec and spec.order)
	if gain ~= nil and gain ~= lossWord then
		reason = reason .. " — the weighted loss outweighs the " .. playerWord(gain) .. " gain"
	end
	return "NOT_UPGRADE", reason
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
-- <wowhead-priorities-start>
-- THE WEIGHTS. One order-only profile per class AND talent spec, keyed
-- by the same short keys the Gear-for picker uses (ret, arms, fury, …).
-- Wowhead is the SOLE source for every shipped profile (Mightie,
-- 2026-11-11). ForeverDB numeric tables are not shipped.
--
-- Generated by tools/gen_wowhead_priorities.py from
-- data/wowhead_stat_priorities.json (28 Wowhead Forever pages, fetched
-- 2026-11-11) and optional data/wowhead_profile_caveats.json. Re-run
-- the generator after updating either file; do not hand-edit this
-- region. A profile.caveat is a one-line note appended to verdicts;
-- it does not change the published order. Remove the entry when the
-- Wowhead page catches up.
--
-- Each profile is kind = "order": walk the published tiers
-- lexicographically, first differing tier decides. Intra-tier bundles
-- use the source-free rule (same direction decides, a conflict is
-- TRADE_OFF, no unit conversion). Caps come from the page itself
-- (melee hit is 8% or 9% depending on the list; several specs have a
-- second cap on the same stat). Leveling-only tagged tiers apply only
-- when the player is below 60. Tanks default to Wowhead's Balanced
-- list (Protection) or Defensive (Feral Bear; that page has no
-- Balanced list). Variants are also in the picker.
--
-- Feral Bear Offensive lists Strength twice (verbatim items 6 and 8);
-- that is a typo, and only the first occurrence is used.
Verdict.WEIGHTS = {
	WARRIOR = {
		arms = {
			name = "Arms",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/warrior/arms/stat-priority-pve-dps",
			updated = "2026-11-04",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Hit", stats = { "Hit" }, capPercent = 8, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 6.5, valueUnit = "percent" },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Strength", stats = { "Strength" } },
				{ name = "Agility", stats = { "Agility" } },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Hit", stats = { "Hit" }, afterPercent = 8, hitKind = "melee", ratingPerPercent = 10 },
			},
			source = "https://www.wowhead.com/forever/guide/classes/warrior/arms/stat-priority-pve-dps (updated 2026-11-04, fetched 2026-11-11). Wowhead Arms Warrior Stat Priority in WoW Forever, by shoop. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
		fury = {
			name = "Fury",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/warrior/fury/stat-priority-pve-dps",
			updated = "2026-10-29",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Weapon Skill", stats = { "WeaponSkill" }, capValue = 305, capUnit = "raw" },
				{ name = "Hit", stats = { "Hit" }, capPercent = 9, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Strength", stats = { "Strength" } },
				{ name = "Agility", stats = { "Agility" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/warrior/fury/stat-priority-pve-dps (updated 2026-10-29, fetched 2026-11-11). Wowhead Fury Warrior Stat Priority in WoW Forever, by Babyhoof. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
		prot_defensive = {
			name = "Protection (Defensive)",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/warrior/protection/stat-priority-pve-tank",
			updated = "2026-11-03",
			fetched = "2026-11-11",
			variant = "Defensive",
			tiers = {
				{ name = "Stamina", stats = { "Stamina" } },
				{ name = "Defense", stats = { "Defense" }, capValue = 440, capUnit = "raw" },
				{ name = "Armor", stats = { "Armor" } },
				{ name = "Agility", stats = { "Agility" } },
				{ name = "Defense", stats = { "Defense" }, afterValue = 440, capUnit = "raw" },
				{ name = "Parry", stats = { "Parry" } },
				{ name = "Dodge", stats = { "Dodge" } },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 6.5, valueUnit = "percent" },
				{ name = "Block Chance", stats = { "BlockChance" } },
				{ name = "Strength & Attack Power", stats = { "AttackPower", "Strength" } },
				{ name = "Hit", stats = { "Hit" }, capPercent = 8, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 14, afterPercent = 6.5, valueUnit = "percent" },
				{ name = "Haste", stats = { "Haste" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/warrior/protection/stat-priority-pve-tank (updated 2026-11-03, fetched 2026-11-11). Wowhead Protection Warrior Stat Priority in WoW Forever — Defensive Priority, by Riyani. Order-only; no invented numeric weights.",
		},
		prot = {
			name = "Protection (Balanced)",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/warrior/protection/stat-priority-pve-tank",
			updated = "2026-11-03",
			fetched = "2026-11-11",
			variant = "Balanced",
			tiers = {
				{ name = "Stamina", stats = { "Stamina" } },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 6.5, valueUnit = "percent" },
				{ name = "Hit", stats = { "Hit" }, capPercent = 8, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Defense", stats = { "Defense" }, capValue = 440, capUnit = "raw" },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 14, afterPercent = 6.5, valueUnit = "percent" },
				{ name = "Armor", stats = { "Armor" } },
				{ name = "Strength & Attack Power", stats = { "AttackPower", "Strength" } },
				{ name = "Agility", stats = { "Agility" } },
				{ name = "Defense", stats = { "Defense" }, afterValue = 440, capUnit = "raw" },
				{ name = "Parry", stats = { "Parry" } },
				{ name = "Dodge", stats = { "Dodge" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Block Chance", stats = { "BlockChance" } },
				{ name = "Haste", stats = { "Haste" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/warrior/protection/stat-priority-pve-tank (updated 2026-11-03, fetched 2026-11-11). Wowhead Protection Warrior Stat Priority in WoW Forever — Balanced Priority, by Riyani. Order-only; no invented numeric weights.",
		},
		prot_offensive = {
			name = "Protection (Offensive)",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/warrior/protection/stat-priority-pve-tank",
			updated = "2026-11-03",
			fetched = "2026-11-11",
			variant = "Offensive",
			tiers = {
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 6.5, valueUnit = "percent" },
				{ name = "Hit", stats = { "Hit" }, capPercent = 8, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 14, afterPercent = 6.5, valueUnit = "percent" },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Strength & Attack Power", stats = { "AttackPower", "Strength" } },
				{ name = "Stamina", stats = { "Stamina" } },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Agility", stats = { "Agility" } },
				{ name = "Defense", stats = { "Defense" }, capValue = 440, capUnit = "raw" },
				{ name = "Armor", stats = { "Armor" } },
				{ name = "Defense", stats = { "Defense" }, afterValue = 440, capUnit = "raw" },
				{ name = "Parry", stats = { "Parry" } },
				{ name = "Dodge", stats = { "Dodge" } },
				{ name = "Block Chance", stats = { "BlockChance" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/warrior/protection/stat-priority-pve-tank (updated 2026-11-03, fetched 2026-11-11). Wowhead Protection Warrior Stat Priority in WoW Forever — Offensive Priority, by Riyani. Order-only; no invented numeric weights.",
		},
	},
	PALADIN = {
		holy = {
			name = "Holy",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/paladin/holy/stat-priority-pve-healer",
			updated = "2026-10-29",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Healing Power", stats = { "Healing" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Spirit", stats = { "Spirit" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/paladin/holy/stat-priority-pve-healer (updated 2026-10-29, fetched 2026-11-11). Wowhead Holy Paladin Stat Priority in WoW Forever, by Harreks. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
		prot_defensive = {
			name = "Protection (Defensive)",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/paladin/protection/stat-priority-pve-tank",
			updated = "2026-10-28",
			fetched = "2026-11-11",
			variant = "Defensive",
			tiers = {
				{ name = "Stamina", stats = { "Stamina" } },
				{ name = "Defense", stats = { "Defense" }, capValue = 440, capUnit = "raw" },
				{ name = "Armor", stats = { "Armor" } },
				{ name = "Agility", stats = { "Agility" } },
				{ name = "Block Chance", stats = { "BlockChance" } },
				{ name = "Defense", stats = { "Defense" }, afterValue = 440, capUnit = "raw" },
				{ name = "Spell Damage", stats = { "SpellPower", "SpellDamage", "HolyPower" } },
				{ name = "Parry", stats = { "Parry" } },
				{ name = "Dodge", stats = { "Dodge" } },
				{ name = "Strength", stats = { "Strength" } },
				{ name = "Hit", stats = { "Hit" }, capPercent = 8, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 6.5, valueUnit = "percent" },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Hit", stats = { "Hit" }, capPercent = 17, afterPercent = 8, hitKind = "spell", ratingPerPercent = 10 },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 14, afterPercent = 6.5, valueUnit = "percent" },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Intellect", stats = { "Intellect" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/paladin/protection/stat-priority-pve-tank (updated 2026-10-28, fetched 2026-11-11). Wowhead Protection Paladin Stat Priority in WoW Forever — Defensive Priority, by Riyani. Order-only; no invented numeric weights.",
		},
		prot = {
			name = "Protection (Balanced)",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/paladin/protection/stat-priority-pve-tank",
			updated = "2026-10-28",
			fetched = "2026-11-11",
			variant = "Balanced",
			tiers = {
				{ name = "Stamina", stats = { "Stamina" } },
				{ name = "Spell Damage", stats = { "SpellPower", "SpellDamage", "HolyPower" } },
				{ name = "Hit", stats = { "Hit" }, capPercent = 8, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Defense", stats = { "Defense" }, capValue = 440, capUnit = "raw" },
				{ name = "Armor", stats = { "Armor" } },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 6.5, valueUnit = "percent" },
				{ name = "Agility", stats = { "Agility" } },
				{ name = "Block Chance", stats = { "BlockChance" } },
				{ name = "Defense", stats = { "Defense" }, afterValue = 440, capUnit = "raw" },
				{ name = "Parry", stats = { "Parry" } },
				{ name = "Dodge", stats = { "Dodge" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Hit", stats = { "Hit" }, capPercent = 17, afterPercent = 8, hitKind = "spell", ratingPerPercent = 10 },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 14, afterPercent = 6.5, valueUnit = "percent" },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Strength", stats = { "Strength" } },
				{ name = "Intellect", stats = { "Intellect" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/paladin/protection/stat-priority-pve-tank (updated 2026-10-28, fetched 2026-11-11). Wowhead Protection Paladin Stat Priority in WoW Forever — Balanced Priority, by Riyani. Order-only; no invented numeric weights.",
		},
		prot_offensive = {
			name = "Protection (Offensive)",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/paladin/protection/stat-priority-pve-tank",
			updated = "2026-10-28",
			fetched = "2026-11-11",
			variant = "Offensive",
			tiers = {
				{ name = "Spell Damage", stats = { "SpellPower", "SpellDamage", "HolyPower" } },
				{ name = "Hit", stats = { "Hit" }, capPercent = 8, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 6.5, valueUnit = "percent" },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Stamina", stats = { "Stamina" } },
				{ name = "Hit", stats = { "Hit" }, capPercent = 17, afterPercent = 8, hitKind = "spell", ratingPerPercent = 10 },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 14, afterPercent = 6.5, valueUnit = "percent" },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Strength", stats = { "Strength" } },
				{ name = "Agility", stats = { "Agility" } },
				{ name = "Defense", stats = { "Defense" }, capValue = 440, capUnit = "raw" },
				{ name = "Armor", stats = { "Armor" } },
				{ name = "Block Chance", stats = { "BlockChance" } },
				{ name = "Defense", stats = { "Defense" }, afterValue = 440, capUnit = "raw" },
				{ name = "Parry", stats = { "Parry" } },
				{ name = "Dodge", stats = { "Dodge" } },
				{ name = "Intellect", stats = { "Intellect" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/paladin/protection/stat-priority-pve-tank (updated 2026-10-28, fetched 2026-11-11). Wowhead Protection Paladin Stat Priority in WoW Forever — Offensive Priority, by Riyani. Order-only; no invented numeric weights.",
		},
		ret = {
			name = "Retribution",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/paladin/retribution/stat-priority-pve-dps",
			updated = "2026-10-31",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Weapon Skill", stats = { "WeaponSkill" } },
				{ name = "Weapon DPS & Speed", stats = { "WeaponDps", "WeaponSpeed" }, special = "dps_then_speed" },
				{ name = "Hit", stats = { "Hit" }, capPercent = 9, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 6.5, valueUnit = "percent" },
				{ name = "Spell Damage", stats = { "SpellDamage", "SpellPower", "HolyPower" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Strength & Attack Power", stats = { "Strength", "AttackPower" } },
				{ name = "Agility & Critical Strike Chance", stats = { "Agility", "Crit" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/paladin/retribution/stat-priority-pve-dps (updated 2026-10-31, fetched 2026-11-11). Wowhead Retribution Paladin Stat Priority in WoW Forever, by Surveillant. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
	},
	DRUID = {
		balance = {
			name = "Balance",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/druid/balance/stat-priority-pve-dps",
			updated = "2026-10-30",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Hit", stats = { "Hit" }, capPercent = 17, hitKind = "spell", ratingPerPercent = 10 }, -- page states a from-gear hit target (talents cover the rest); clamp the player's total hit, which already includes talents, at the 17% cap stated on the page
				{ name = "Spell Damage", stats = { "SpellDamage", "SpellPower" } },
				{ name = "Spell Penetration", stats = { "SpellPenetration" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Spirit", stats = { "Spirit" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/druid/balance/stat-priority-pve-dps (updated 2026-10-30, fetched 2026-11-11). Wowhead Balance Druid Stat Priority in WoW Forever, by DrWonder. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
		feral_cat = {
			name = "Feral (Cat)",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/druid/feral/stat-priority-pve-dps",
			updated = "2026-10-29",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Hit", stats = { "Hit" }, capPercent = 8, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 6.5, valueUnit = "percent" },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Weapon DPS", stats = { "WeaponDps" } },
				{ name = "Agility & Strength", stats = { "Agility", "Strength" } },
				{ name = "Attack Power", stats = { "AttackPower" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Spirit", stats = { "Spirit" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/druid/feral/stat-priority-pve-dps (updated 2026-10-29, fetched 2026-11-11). Wowhead Feral Druid Stat Priority in WoW Forever, by Lexolas. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
		feral_bear = {
			name = "Feral (Bear, Defensive)",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/druid/feral/stat-priority-pve-tank",
			updated = "2026-11-03",
			fetched = "2026-11-11",
			variant = "Defensive",
			-- The page body cites an Armor cap of 17265, but the numbered list is just 'Armor' with no 'until' wording, so no armor cap is applied.
			tiers = {
				{ name = "Stamina", stats = { "Stamina" } },
				{ name = "Defense", stats = { "Defense" }, capValue = 440, capUnit = "raw" },
				{ name = "Armor", stats = { "Armor" } },
				{ name = "Agility", stats = { "Agility" } },
				{ name = "Avoidance", stats = { "Dodge", "Parry" } },
				{ name = "Defense", stats = { "Defense" }, afterValue = 440, capUnit = "raw" },
			},
			source = "https://www.wowhead.com/forever/guide/classes/druid/feral/stat-priority-pve-tank (updated 2026-11-03, fetched 2026-11-11). Wowhead Feral Druid Tank Stat Priority in WoW Forever — Defensive Priority, by L0uki. Order-only; no invented numeric weights.",
		},
		feral_bear_offensive = {
			name = "Feral (Bear, Offensive)",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/druid/feral/stat-priority-pve-tank",
			updated = "2026-11-03",
			fetched = "2026-11-11",
			variant = "Offensive",
			-- Wowhead typo: the Offensive list prints Strength as both item 6 and item 8. The second occurrence is dropped; the first is kept.
			tiers = {
				{ name = "Hit", stats = { "Hit" }, capPercent = 8, hitKind = "melee", ratingPerPercent = 10 }, -- numbered list omits the cap wording; the same page states this cap (8%)
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 6.5, valueUnit = "percent" },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Weapon DPS", stats = { "WeaponDps" } },
				{ name = "Strength", stats = { "Strength" } },
				{ name = "Agility", stats = { "Agility" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/druid/feral/stat-priority-pve-tank (updated 2026-11-03, fetched 2026-11-11). Wowhead Feral Druid Tank Stat Priority in WoW Forever — Offensive Priority, by L0uki. Order-only; no invented numeric weights.",
		},
		resto = {
			name = "Restoration",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/druid/restoration/stat-priority-pve-healer",
			updated = "2026-11-01",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Healing Power", stats = { "Healing" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Spirit", stats = { "Spirit" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "MP5", stats = { "MP5" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/druid/restoration/stat-priority-pve-healer (updated 2026-11-01, fetched 2026-11-11). Wowhead Restoration Druid Stat Priority in WoW Forever, by Frankensteak. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
	},
	SHAMAN = {
		elemental = {
			name = "Elemental",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/shaman/elemental/stat-priority-pve-dps",
			updated = "2026-11-04",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Spell Penetration", stats = { "SpellPenetration" } },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Hit", stats = { "Hit" }, capPercent = 17, hitKind = "spell", ratingPerPercent = 10 }, -- page states a from-gear hit target (talents cover the rest); clamp the player's total hit, which already includes talents, at the 17% cap stated on the page
				{ name = "Spell Damage", stats = { "SpellDamage", "SpellPower" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Nature Damage & Fire Damage", stats = { "NaturePower", "FirePower" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Spirit", stats = { "Spirit" } },
				{ name = "Strength", stats = { "Strength" }, levelingOnly = true },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/shaman/elemental/stat-priority-pve-dps (updated 2026-11-04, fetched 2026-11-11). Wowhead Elemental Shaman Stat Priority in WoW Forever, by Lucenia. Order-only; no invented numeric weights.",
		},
		enhancement = {
			name = "Enhancement",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/shaman/enhancement/stat-priority-pve-dps",
			updated = "2026-11-03",
			fetched = "2026-11-11",
			caveat = "Wowhead list predates the Nov 10 Mental Dexterity hotfix; Intellect may be overrated. Hit past the listed 8% melee minimum is not scored.",
			-- caveat source: https://news.blizzard.com/en-us/article/24315281/wow-forever-hotfixes-november-10-2026
			tiers = {
				{ name = "Hit", stats = { "Hit" }, capPercent = 8, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 6.5, valueUnit = "percent" },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Spell Damage", stats = { "SpellDamage", "SpellPower" } },
				{ name = "Strength", stats = { "Strength" } },
				{ name = "Spell Penetration", stats = { "SpellPenetration" } },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Agility", stats = { "Agility" } },
				{ name = "Spirit", stats = { "Spirit" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/shaman/enhancement/stat-priority-pve-dps (updated 2026-11-03, fetched 2026-11-11). Wowhead Enhancement Shaman Stat Priority in WoW Forever, by Yebb. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
		resto = {
			name = "Restoration",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/shaman/restoration/stat-priority-pve-healer",
			updated = "2026-11-01",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Healing Power", stats = { "Healing" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Spirit", stats = { "Spirit" } },
				{ name = "MP5", stats = { "MP5" } },
				{ name = "Spell Damage", stats = { "SpellDamage", "SpellPower" }, levelingOnly = true },
			},
			source = "https://www.wowhead.com/forever/guide/classes/shaman/restoration/stat-priority-pve-healer (updated 2026-11-01, fetched 2026-11-11). Wowhead Restoration Shaman Stat Priority in WoW Forever, by Woah. Order-only; no invented numeric weights.",
		},
	},
	PRIEST = {
		disc = {
			name = "Discipline",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/priest/discipline/stat-priority-pve-healer",
			updated = "2026-10-30",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Healing Power", stats = { "Healing" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Spirit", stats = { "Spirit" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Spell Damage", stats = { "SpellDamage", "SpellPower" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/priest/discipline/stat-priority-pve-healer (updated 2026-10-30, fetched 2026-11-11). Wowhead Discipline Priest Stat Priority in WoW Forever, by Voulk. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
		holy = {
			name = "Holy",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/priest/holy/stat-priority-pve-healer",
			updated = "2026-10-31",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Healing Power", stats = { "Healing" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "MP5", stats = { "MP5" } },
				{ name = "Spirit", stats = { "Spirit" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/priest/holy/stat-priority-pve-healer (updated 2026-10-31, fetched 2026-11-11). Wowhead Holy Priest Stat Priority in WoW Forever, by Spanklord. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
		shadow = {
			name = "Shadow",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/priest/shadow/stat-priority-pve-dps",
			updated = "2026-10-30",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Hit", stats = { "Hit" }, capPercent = 17, hitKind = "spell", ratingPerPercent = 10 }, -- page states a from-gear hit target (talents cover the rest); clamp the player's total hit, which already includes talents, at the 17% cap stated on the page
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Spell Damage & Shadow Damage", stats = { "SpellDamage", "SpellPower", "ShadowPower" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Spirit", stats = { "Spirit" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/priest/shadow/stat-priority-pve-dps (updated 2026-10-30, fetched 2026-11-11). Wowhead Shadow Priest Stat Priority in WoW Forever, by Jereico. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
	},
	MAGE = {
		arcane = {
			name = "Arcane",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/mage/arcane/stat-priority-pve-dps",
			updated = "2026-10-28",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Hit", stats = { "Hit" }, capPercent = 17, hitKind = "spell", ratingPerPercent = 10 },
				{ name = "Spell Damage & Arcane Damage", stats = { "SpellDamage", "SpellPower", "ArcanePower" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Spell Penetration", stats = { "SpellPenetration" } },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Spirit", stats = { "Spirit" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/mage/arcane/stat-priority-pve-dps (updated 2026-10-28, fetched 2026-11-11). Wowhead Arcane Mage Stat Priority in WoW Forever, by Foolipe. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
		fire = {
			name = "Fire",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/mage/fire/stat-priority-pve-dps",
			updated = "2026-11-03",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Hit", stats = { "Hit" }, capPercent = 17, hitKind = "spell", ratingPerPercent = 10 },
				{ name = "Spell Damage & Fire Damage", stats = { "SpellDamage", "SpellPower", "FirePower" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Spell Penetration", stats = { "SpellPenetration" } },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Spirit", stats = { "Spirit" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/mage/fire/stat-priority-pve-dps (updated 2026-11-03, fetched 2026-11-11). Wowhead Fire Mage Stat Priority in WoW Forever, by Foolipe. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
		frost = {
			name = "Frost",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/mage/frost/stat-priority-pve-dps",
			updated = "2026-10-29",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Hit", stats = { "Hit" }, capPercent = 17, hitKind = "spell", ratingPerPercent = 10 }, -- page states a from-gear hit target (talents cover the rest); clamp the player's total hit, which already includes talents, at the 17% cap stated on the page
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Spell Damage, Frost Damage & Arcane Damage", stats = { "SpellDamage", "SpellPower", "FrostPower", "ArcanePower" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Spirit", stats = { "Spirit" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/mage/frost/stat-priority-pve-dps (updated 2026-10-29, fetched 2026-11-11). Wowhead Frost Mage Stat Priority in WoW Forever, by Porom. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
	},
	WARLOCK = {
		affliction = {
			name = "Affliction",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/warlock/affliction/stat-priority-pve-dps",
			updated = "2026-11-11",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Spell Damage & Shadow Damage", stats = { "SpellPower", "SpellDamage", "ShadowPower" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Hit", stats = { "Hit" }, capPercent = 17, hitKind = "spell", ratingPerPercent = 10 }, -- page states a from-gear hit target (talents cover the rest); clamp the player's total hit, which already includes talents, at the 17% cap stated on the page
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Spell Penetration", stats = { "SpellPenetration" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Spirit", stats = { "Spirit" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/warlock/affliction/stat-priority-pve-dps (updated 2026-11-11, fetched 2026-11-11). Wowhead Affliction Warlock Stat Priority in WoW: Forever, by Zephan. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
		demonology = {
			name = "Demonology",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/warlock/demonology/stat-priority-pve-dps",
			updated = "2026-11-03",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Spell Damage, Fire Damage & Shadow Damage", stats = { "SpellPower", "SpellDamage", "FirePower", "ShadowPower" } },
				{ name = "Hit", stats = { "Hit" }, capPercent = 17, hitKind = "spell", ratingPerPercent = 10 }, -- page states a from-gear hit target (talents cover the rest); clamp the player's total hit, which already includes talents, at the 17% cap stated on the page
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Spell Penetration", stats = { "SpellPenetration" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Spirit", stats = { "Spirit" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/warlock/demonology/stat-priority-pve-dps (updated 2026-11-03, fetched 2026-11-11). Wowhead Demonology Warlock Stat Priority in WoW: Forever, by Zephan. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
		destruction = {
			name = "Destruction",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/warlock/destruction/stat-priority-pve-dps",
			updated = "2026-11-03",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Spell Damage & Fire Damage", stats = { "SpellPower", "SpellDamage", "FirePower" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Hit", stats = { "Hit" }, capPercent = 17, hitKind = "spell", ratingPerPercent = 10 }, -- page states a from-gear hit target (talents cover the rest); clamp the player's total hit, which already includes talents, at the 17% cap stated on the page
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Spell Penetration", stats = { "SpellPenetration" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Spirit", stats = { "Spirit" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/warlock/destruction/stat-priority-pve-dps (updated 2026-11-03, fetched 2026-11-11). Wowhead Destruction Warlock Stat Priority in WoW: Forever, by Zephan. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
	},
	ROGUE = {
		assassination = {
			name = "Assassination",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/rogue/assassination/stat-priority-pve-dps",
			updated = "2026-11-09",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Hit", stats = { "Hit" }, capPercent = 8, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 6.5, valueUnit = "percent" },
				{ name = "Weapon Skill", stats = { "WeaponSkill" }, capValue = 308, capUnit = "raw" },
				{ name = "Hit", stats = { "Hit" }, capPercent = 17, afterPercent = 8, hitKind = "spell", ratingPerPercent = 10 },
				{ name = "Agility", stats = { "Agility" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Strength", stats = { "Strength" } },
				{ name = "Attack Power", stats = { "AttackPower" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/rogue/assassination/stat-priority-pve-dps (updated 2026-11-09, fetched 2026-11-11). Wowhead Assassination Rogue Stat Priority in WoW Forever, by warstry. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
		combat = {
			name = "Combat",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/rogue/combat/stat-priority-pve-dps",
			updated = "2026-10-30",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Hit", stats = { "Hit" }, capPercent = 8, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 6.5, valueUnit = "percent" },
				{ name = "Weapon Skill", stats = { "WeaponSkill" }, capValue = 308, capUnit = "raw" },
				{ name = "Hit", stats = { "Hit" }, capPercent = 17, afterPercent = 8, hitKind = "spell", ratingPerPercent = 10 },
				{ name = "Agility", stats = { "Agility" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Strength", stats = { "Strength" } },
				{ name = "Attack Power", stats = { "AttackPower" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/rogue/combat/stat-priority-pve-dps (updated 2026-10-30, fetched 2026-11-11). Wowhead Combat Rogue Stat Priority in WoW Forever, by warstry. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
		subtlety = {
			name = "Subtlety",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/rogue/subtlety/stat-priority-pve-dps",
			updated = "2026-10-30",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Hit", stats = { "Hit" }, capPercent = 8, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Expertise", stats = { "Expertise" }, capPercent = 6.5, valueUnit = "percent" },
				{ name = "Weapon Skill", stats = { "WeaponSkill" }, capValue = 308, capUnit = "raw" },
				{ name = "Hit", stats = { "Hit" }, capPercent = 17, afterPercent = 8, hitKind = "spell", ratingPerPercent = 10 },
				{ name = "Agility", stats = { "Agility" } },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Haste", stats = { "Haste" } },
				{ name = "Strength", stats = { "Strength" } },
				{ name = "Attack Power", stats = { "AttackPower" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/rogue/subtlety/stat-priority-pve-dps (updated 2026-10-30, fetched 2026-11-11). Wowhead Subtlety Rogue Stat Priority in WoW Forever, by warstry. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
	},
	HUNTER = {
		beast_mastery = {
			name = "Beast Mastery",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/hunter/beast-mastery/stat-priority-pve-dps",
			updated = "2026-11-04",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Hit", stats = { "Hit" }, capPercent = 9, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Agility", stats = { "Agility" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Ranged Attack Power", stats = { "RangedAttackPower" } },
				{ name = "Spirit", stats = { "Spirit" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/hunter/beast-mastery/stat-priority-pve-dps (updated 2026-11-04, fetched 2026-11-11). Wowhead Beast Mastery Hunter Stat Priority in WoW Forever, by Docoda. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
		marksmanship = {
			name = "Marksmanship",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/hunter/marksmanship/stat-priority-pve-dps",
			updated = "2026-11-04",
			fetched = "2026-11-11",
			tiers = {
				{ name = "Hit", stats = { "Hit" }, capPercent = 9, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Agility", stats = { "Agility" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Ranged Attack Power", stats = { "RangedAttackPower" } },
				{ name = "Spirit", stats = { "Spirit" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/hunter/marksmanship/stat-priority-pve-dps (updated 2026-11-04, fetched 2026-11-11). Wowhead Marksmanship Hunter Stat Priority in WoW Forever, by Docoda. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
		survival = {
			name = "Survival",
			kind = "order",
			url = "https://www.wowhead.com/forever/guide/classes/hunter/survival/stat-priority-pve-dps",
			updated = "2026-11-04",
			fetched = "2026-11-11",
			-- The numbered list is '% Hit Chance' with no 'until 9%'; the same page states the 9% yellow-hit cap in the body, and that cap is applied.
			tiers = {
				{ name = "Hit", stats = { "Hit" }, capPercent = 9, hitKind = "melee", ratingPerPercent = 10 },
				{ name = "Crit", stats = { "Crit" } },
				{ name = "Agility", stats = { "Agility" } },
				{ name = "Strength", stats = { "Strength" } },
				{ name = "Ranged Attack Power", stats = { "AttackPower", "RangedAttackPower" } },
				{ name = "Intellect", stats = { "Intellect" } },
				{ name = "Spirit", stats = { "Spirit" } },
				{ name = "Stamina", stats = { "Stamina" } },
			},
			source = "https://www.wowhead.com/forever/guide/classes/hunter/survival/stat-priority-pve-dps (updated 2026-11-04, fetched 2026-11-11). Wowhead Survival Hunter Stat Priority in WoW Forever, by Docoda. The page is built from beta data and says the priority will shift once level 60 dungeon and raid gear is available. Order-only; no invented numeric weights.",
		},
	},
}
-- <wowhead-priorities-end>

-- The noise floor for any leftover numeric fixture pack (shipped profiles
-- are order-only and do not use it). 0.005 sits well under a one-point
-- armor gain and well above ordinary floating-point dust.
Verdict.WEIGHT_EPSILON = 0.005

-- ONE epsilon rule for every "do these two numbers rank the same" question
-- (card t_a5de2f16). The ranked comparator, the capped-window check and
-- tiebreakTotal all ask this function. The two copies that existed before
-- this card spelled the comparison out twice, and a crumb smaller than the
-- floor could answer differently depending on which entry point a tooltip
-- reached.
--
-- It reads Verdict.WEIGHT_EPSILON on every call, never a captured copy, so a
-- fixture pack that changes the floor changes it everywhere.
function Verdict.ranksAsDifferent(delta)
	delta = tonumber(delta) or 0
	local eps = Verdict.WEIGHT_EPSILON or 0
	return delta > eps or delta < -eps
end

-- The client's three-word role vocabulary (TANK / HEALER / DAMAGER) to a
-- weights key, used only when that role maps to exactly one sourced pack.
-- A class/role with two packs (Warrior DAMAGER is Arms or Fury; Priest
-- HEALER is Holy or Discipline) is ABSENT: Auto must see a talent name or
-- a gearFor override, never guess.
Verdict.PROFILE_ROLE = {
	PALADIN = { TANK = "prot", HEALER = "holy", DAMAGER = "ret" },
	WARRIOR = { TANK = "prot" },
	DRUID   = { TANK = "feral_bear", HEALER = "resto" },
	SHAMAN  = { HEALER = "resto" },
	PRIEST  = { DAMAGER = "shadow" },
}

-- Folded order words (melee|spell) and the historical "tank" word, used by
-- tests and by `/up role`, onto a unique sourced pack when one exists.
Verdict.ROLE_WEIGHT_ALIAS = {
	PALADIN = { melee = "ret", spell = "holy", tank = "prot" },
	WARRIOR = { tank = "prot" },
	DRUID   = { spell = "balance", tank = "feral_bear" },
	SHAMAN  = { melee = "enhancement", spell = "elemental" },
}

-- The active profile for a spec, or nil.
--
--   spec — { class = <CLASS token>, role = <melee|spell|nil>,
--            clientRole = <TANK|HEALER|DAMAGER|nil> (optional),
--            weightsKey = <registry key> (optional) }
--
-- Resolution order: a named weightsKey (chosen / talent-matched) when a
-- table exists — a key with no table is silence, never a fallback into
-- another pack (Feral Cat must not score as Bear or Balance). Then the
-- CLIENT's role word when this class uniquely maps it, then a folded
-- melee/spell/tank alias when that alias is unique, then a direct key
-- match on spec.role. There is no "pure class, pick the only pack"
-- fallback: Mage/Rogue/Hunter/Warlock now have three packs each, and
-- guessing one would be a guessed weight.
function Verdict.profileFor(spec)
	if type(spec) ~= "table" then return nil end
	local class = spec.class
	local byRole = (type(class) == "string") and Verdict.WEIGHTS[class] or nil
	if type(byRole) ~= "table" then return nil end
	if type(spec.weightsKey) == "string" then
		local pack = byRole[spec.weightsKey]
		if type(pack) == "table" then return pack end
		return nil
	end
	local alias = (type(class) == "string") and Verdict.PROFILE_ROLE[class] or nil
	local client = type(spec.clientRole) == "string" and spec.clientRole or nil
	if client ~= nil and type(alias) == "table" then
		local word = alias[client]
		if type(word) == "string" and type(byRole[word]) == "table" then
			return byRole[word]
		end
	end
	local folded = (type(class) == "string") and Verdict.ROLE_WEIGHT_ALIAS[class] or nil
	if type(spec.role) == "string" and type(folded) == "table" then
		local word = folded[spec.role]
		if type(word) == "string" and type(byRole[word]) == "table" then
			return byRole[word]
		end
	end
	if type(spec.role) == "string" and type(byRole[spec.role]) == "table" then
		return byRole[spec.role]
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

-- ── ORDER-ONLY PROFILES ─────────────────────────────────────────────────────
--
-- A profile with `kind = "order"` (and a `tiers` list) has no invented
-- numeric weights. Every shipped Wowhead profile uses this path. The
-- comparator walks the published priority in order and the first tier
-- whose sides differ decides.
--
-- Intra-tier rule (source-free, no unit conversion): if every differing
-- stat in the tier moves the same way, that direction decides; if two
-- stats in the tier conflict, the verdict is TRADE_OFF and names them.
--
-- Caps come from each Wowhead page (Hit is 8% or 9% depending on the
-- list; several specs then have a later cap on the same stat, e.g.
-- Rogue Hit 8% then 17% poison). The player's current value is read
-- from the 1.60.1 client — GetCombatRatingBonus + GetHitModifier for
-- Hit, GetExpertise() (a percent on forever + 1.60.1) or
-- GetCombatRatingBonus(CR_EXPERTISE) for Expertise, UnitDefense for
-- Defense skill, and a pcall'd weapon-skill read — each call pcall'd.
-- Tests inject spec.playerHitPercent / playerExpertisePercent /
-- playerDefense / playerWeaponSkill; the value `false` forces
-- "cap status unknown". If the read fails, the raw delta still ranks
-- the tier. A stat already at/over cap counts only up to the cap:
-- gains past cap do not count, losses that drop below cap do. A
-- later "after X" / second-cap tier only counts the window between
-- the previous cap and the new cap (or with no upper bound).
-- Defense 440 and Weapon Skill 305/308 are raw totals, not percents.
--
-- Leveling-only tagged tiers (Elemental Strength, Resto Shaman Spell
-- Damage) apply only when the player level is below 60. If the level
-- is unknown, the tier is included (we do not invent a level).
--
-- Weapon DPS & Speed: compare DPS first (higher is better). Speed alone
-- is only considered when DPS is equal, and is REPORTED but not ranked
-- (the Ret source prefers slow weapons for Twist and fast for Shockadin,
-- and does not pick one).

function Verdict.isOrderProfile(profile)
	return type(profile) == "table"
		and (profile.kind == "order" or type(profile.tiers) == "table")
		and type(profile.tiers) == "table" and #profile.tiers > 0
end

-- Secret numbers still have type() == "number". Arithmetic or comparison
-- on one raises ("attempt to perform arithmetic on a secret number value
-- (execution tainted by 'MightiePack')") — the live crash at
-- Verdict.playerHitPercent (GetHitModifier / GetCombatRatingBonus) when
-- ChestAdvisor.scan ran from the character-sheet refresh. pcall of the
-- API does not help: the call succeeds and returns the secret. The
-- client's issecretvalue (and canaccessvalue, when present) is the only
-- safe test; a missing predicate is treated as "not secret" so older
-- clients still work.
local function isSecretNumber(v)
	if type(issecretvalue) == "function" then
		local ok, r = pcall(issecretvalue, v)
		if ok and r then return true end
	end
	if type(canaccessvalue) == "function" then
		local ok, r = pcall(canaccessvalue, v)
		if ok and r == false then return true end
	end
	return false
end

local function usableNumber(v)
	if type(v) ~= "number" or isSecretNumber(v) then return nil end
	return v
end

-- Second return is true when the client handed back a secret, so a
-- caller that would add this to another number can refuse the whole
-- sum instead of silently dropping the secret half.
local function pcallNumber(fn, ...)
	if type(fn) ~= "function" then return nil, false end
	local ok, a = pcall(fn, ...)
	if not ok then return nil, false end
	if isSecretNumber(a) then return nil, true end
	if type(a) ~= "number" then return nil, false end
	return a, false
end

-- Combat-rating bonus for a named CR_* global. The index is only used
-- when the client actually exposes it; we do not invent 6, 24, or any
-- other fallback index.
local function combatRatingBonus(crName)
	local idx = rawget(_G, crName)
	if idx == nil then return nil, false end
	return pcallNumber(GetCombatRatingBonus, idx)
end

-- First readable named combat-rating bonus. A secret result stops the
-- search: we must not substitute a different CR_* for one the client
-- hid, and we must not add a later readable modifier to a secret rating.
local function firstRatingBonus(...)
	for i = 1, select("#", ...) do
		local n, secret = combatRatingBonus((select(i, ...)))
		if secret then return nil, true end
		if n ~= nil then return n, false end
	end
	return nil, false
end

-- The player's current Hit chance, in percent, or nil when unreadable.
-- `kind` is "spell" for a spell (or poison) 17% cap, or "melee" (default)
-- for an 8% / 9% ability cap. Spell caps use GetSpellHitModifier, never
-- GetHitModifier. The rating half prefers CR_HIT_SPELL, then the unified
-- CR_HIT, then (on clients that only expose one hit rating) CR_HIT_MELEE,
-- and only when that global is present.
function Verdict.playerHitPercent(kind)
	if kind == "spell" then
		local bonus, bSec = firstRatingBonus("CR_HIT_SPELL", "CR_HIT", "CR_HIT_MELEE")
		local mod, mSec = pcallNumber(GetSpellHitModifier)
		if bSec or mSec then return nil end
		if bonus == nil and mod == nil then return nil end
		return (bonus or 0) + (mod or 0)
	end
	local bonus, bSec = firstRatingBonus("CR_HIT_MELEE", "CR_HIT")
	local mod, mSec = pcallNumber(GetHitModifier)
	if bSec or mSec then return nil end
	if bonus == nil and mod == nil then return nil end
	return (bonus or 0) + (mod or 0)
end

-- The player's current Expertise, in percent, or nil when unreadable.
-- Only APIs that are documented to return a percent are trusted:
-- GetExpertisePercent, then GetCombatRatingBonus(CR_EXPERTISE) (the
-- client's own percent bonus) when CR_EXPERTISE is present. GetExpertise
-- is not used: its unit is not verified on Forever, and assuming it is
-- a percent would invent a conversion.
function Verdict.playerExpertisePercent()
	if type(GetExpertisePercent) == "function" then
		local ok, mh = pcall(GetExpertisePercent)
		if ok then
			local n = usableNumber(mh)
			if n ~= nil then return n end
			if isSecretNumber(mh) then return nil end
		end
	end
	local idx = rawget(_G, "CR_EXPERTISE")
	if idx == nil then return nil end
	return pcallNumber(GetCombatRatingBonus, idx)
end

-- Defense skill total, or nil when unreadable. Classic UnitDefense
-- returns base, armorBonus; both are required (Wowhead's cap is 440
-- skill, not a rating). pcallNumber would keep only the first return.
function Verdict.playerDefenseSkill()
	local ok, base, mod = pcall(UnitDefense, "player")
	if not ok then return nil end
	if isSecretNumber(base) or isSecretNumber(mod) then return nil end
	if type(base) ~= "number" then return nil end
	return base + (usableNumber(mod) or 0)
end

-- True when the player has an off-hand weapon equipped. Classic
-- UnitAttackBothHands returns the UNARMED skill in the off-hand slots
-- when the character is not dual-wielding (a 2H or a shield), so a
-- positive off-hand total is not enough to decide. Prefer
-- OffhandHasWeapon when the client exposes it; otherwise inspect slot
-- 17 with GetInventoryItemLink and C_Item.GetItemInfoInstant (or
-- GetItemInfoInstant) and accept only INVTYPE_WEAPON /
-- INVTYPE_WEAPONOFFHAND. A shield, held-in-off-hand, or empty slot is
-- not a weapon, and the main-hand total is used.
local function offhandWeaponEquipped()
	if type(OffhandHasWeapon) == "function" then
		local ok, has = pcall(OffhandHasWeapon)
		if ok then return has and true or false end
	end
	if type(GetInventoryItemLink) ~= "function" then return false end
	local okLink, link = pcall(GetInventoryItemLink, "player", 17)
	if not okLink or type(link) ~= "string" or link == "" then return false end
	local loc
	if type(C_Item) == "table" and type(C_Item.GetItemInfoInstant) == "function" then
		local ok, _, _, _, equipLoc = pcall(C_Item.GetItemInfoInstant, link)
		if ok then loc = equipLoc end
	end
	if loc == nil and type(GetItemInfoInstant) == "function" then
		local ok, _, _, _, equipLoc = pcall(GetItemInfoInstant, link)
		if ok then loc = equipLoc end
	end
	return loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONOFFHAND"
end

-- Weapon skill total, or nil when unreadable. UnitAttackBothHands
-- returns main-hand base, main-hand modifier, off-hand base, off-hand
-- modifier — skill totals, not a combat rating. GetCombatRating
-- (CR_WEAPON_SKILL) is a rating and must not be compared to the 305 /
-- 308 skill caps. When an off-hand weapon is equipped, the lower of
-- the two totals is used, because a cap of 305/308 is only met when
-- the weaker hand reaches it. The unarmed skill Classic reports in
-- the off-hand slots for a 2H or a shield is ignored. Tests inject
-- spec.playerWeaponSkill.
function Verdict.playerWeaponSkill()
	if type(UnitAttackBothHands) == "function" then
		local ok, mainBase, mainMod, offBase, offMod = pcall(UnitAttackBothHands, "player")
		if not ok then return nil end
		if isSecretNumber(mainBase) or isSecretNumber(mainMod)
			or isSecretNumber(offBase) or isSecretNumber(offMod) then
			return nil
		end
		if type(mainBase) == "number" then
			local main = mainBase + (usableNumber(mainMod) or 0)
			if offhandWeaponEquipped() and type(offBase) == "number" then
				local off = offBase + (usableNumber(offMod) or 0)
				if off < main then return off end
			end
			return main
		end
	end
	return nil
end

function Verdict.playerLevel(spec)
	if type(spec) == "table" and type(spec.level) == "number" then
		return spec.level
	end
	return pcallNumber(UnitLevel, "player")
end

-- Resolve the current percent for a capped stat. `spec.playerHitPercent`
-- / `spec.playerExpertisePercent` override the client read so a test can
-- inject a value; the value `false` forces "cap status unknown".
function Verdict.currentCapPercent(word, spec, hitKind)
	if type(spec) == "table" then
		if word == "Hit" then
			if hitKind == "spell" then
				if spec.playerSpellHitPercent == false then return nil end
				if type(spec.playerSpellHitPercent) == "number" then
					return spec.playerSpellHitPercent
				end
				-- Fall back to a generic injected hit percent when the
				-- test (or a unified-rating client) supplies only one.
				if spec.playerHitPercent == false then return nil end
				if type(spec.playerHitPercent) == "number" then return spec.playerHitPercent end
			else
				if spec.playerHitPercent == false then return nil end
				if type(spec.playerHitPercent) == "number" then return spec.playerHitPercent end
			end
		elseif word == "Expertise" then
			if spec.playerExpertisePercent == false then return nil end
			if type(spec.playerExpertisePercent) == "number" then return spec.playerExpertisePercent end
		end
	end
	if word == "Hit" then return Verdict.playerHitPercent(hitKind) end
	if word == "Expertise" then return Verdict.playerExpertisePercent() end
	return nil
end

-- Current value in the cap's unit ("percent" or "raw").
function Verdict.currentCapValue(word, spec, unit)
	if unit == "raw" then
		if type(spec) == "table" then
			if word == "Defense" then
				if spec.playerDefense == false then return nil end
				if type(spec.playerDefense) == "number" then return spec.playerDefense end
			elseif word == "WeaponSkill" then
				if spec.playerWeaponSkill == false then return nil end
				if type(spec.playerWeaponSkill) == "number" then return spec.playerWeaponSkill end
			end
		end
		if word == "Defense" then return Verdict.playerDefenseSkill() end
		if word == "WeaponSkill" then return Verdict.playerWeaponSkill() end
		return nil
	end
	return Verdict.currentCapPercent(word, spec)
end

-- Clamp a contribution into the window [after, cap] (either bound
-- optional). `current` is the player's total INCLUDING the worn item,
-- in the same unit as cap/after (percent, or raw skill/rating).
-- When unit is "percent", cand/worn values are ratings and are divided
-- by ratingPerPercent. When ratingPerPercent is 1 (or valueUnit is
-- "percent"), the stored values are already percent and are used as-is.
-- When unit is "raw", cand/worn are used as-is. A missing or zero
-- ratingPerPercent is not invented: the raw values are ranked and cap
-- status is "unknown".
-- Returns (effective_delta, capStatus) where capStatus is "unknown",
-- "below", or "at".
function Verdict.clampedWindowDelta(candRating, wornRating, current, cap, after, ratingPerPercent, unit)
	local candVal, wornVal
	local scaleUnknown = false
	if unit == "raw" then
		candVal = tonumber(candRating) or 0
		wornVal = tonumber(wornRating) or 0
	else
		local scale = tonumber(ratingPerPercent)
		if type(scale) ~= "number" or scale == 0 then
			-- No sourced conversion. Rank the raw values and report
			-- cap status unknown; do not invent a factor.
			candVal = tonumber(candRating) or 0
			wornVal = tonumber(wornRating) or 0
			scaleUnknown = true
		else
			candVal = (tonumber(candRating) or 0) / scale
			wornVal = (tonumber(wornRating) or 0) / scale
		end
	end
	if scaleUnknown or type(current) ~= "number" then
		return candVal - wornVal, "unknown"
	end
	local wornTotal = current
	local candTotal = current - wornVal + candVal
	local lo = (type(after) == "number") and after or 0
	local hi = (type(cap) == "number") and cap or math.huge
	local function effective(x)
		if x > hi then x = hi end
		if x < lo then x = lo end
		return x
	end
	local status
	if type(cap) == "number" then
		status = (current >= cap and "at") or "below"
		if effective(candTotal) < cap or effective(wornTotal) < cap then
			status = "below"
		end
	else
		-- After-only window (e.g. Hit after 8% with no upper cap).
		status = "below"
	end
	return effective(candTotal) - effective(wornTotal), status
end

-- Back-compat wrapper used by existing Ret cap tests: one upper percent
-- cap, no floor, rating-to-percent conversion.
function Verdict.clampedPercentDelta(candRating, wornRating, current, cap, ratingPerPercent)
	return Verdict.clampedWindowDelta(candRating, wornRating, current, cap, 0, ratingPerPercent, "percent")
end

local function orderProfileLabel(profile, src)
	local pname = type(profile) == "table" and profile.name or "no profile"
	if src == "chosen" or src == "talents" then
		pname = tostring(pname) .. " (" .. src .. ")"
	end
	return pname
end

-- A one-line caveat from profile.caveat, or nil. Easy to drop when
-- the Wowhead page is updated: remove the data entry and regenerate.
function Verdict.profileCaveat(profile)
	if type(profile) == "table" and type(profile.caveat) == "string" and profile.caveat ~= "" then
		return profile.caveat
	end
	return nil
end

function Verdict.appendCaveat(profile, text)
	local c = Verdict.profileCaveat(profile)
	if c and type(text) == "string" then
		return text .. " — " .. c
	end
	return text
end

function Verdict.orderReason(profile, kind, decidedBy, profileSource, extra)
	local pname = orderProfileLabel(profile, profileSource)
	local text
	if kind == "trade-off" then
		local named = type(decidedBy) == "string" and decidedBy or "stats in the same tier"
		text = "decided by " .. named .. " [" .. pname .. "] — " .. (extra or "those stats conflict")
	elseif kind == "no change" then
		local head = "no change [" .. pname .. "]"
		if type(extra) == "string" and extra ~= "" then
			text = head .. " — " .. extra
		else
			text = head
		end
	elseif type(decidedBy) == "string" and decidedBy ~= "" then
		text = "decided by " .. decidedBy .. " [" .. pname .. "]"
	else
		text = "[" .. pname .. "]"
	end
	return Verdict.appendCaveat(profile, text)
end

local function formatBound(value, unit)
	if type(value) ~= "number" then return nil end
	local isPct = (unit ~= "raw")
	if value == math.floor(value) then
		if isPct then return string.format("%d%%", value) end
		return string.format("%d", value)
	end
	if isPct then return tostring(value) .. "%" end
	return tostring(value)
end

-- Display labels for order-only Trade-off clauses. Tokens that are already
-- player-facing (Strength, Hit, Crit, …) pass through playerWord unchanged.
local ORDER_STAT_LABEL = {
	WeaponDps = "Weapon DPS",
	WeaponSpeed = "Weapon Speed",
	WeaponSkill = "Weapon Skill",
	AttackPower = "Attack Power",
	SpellDamage = "Spell Damage",
	SpellPower = "Spell Power",
	SpellPenetration = "Spell Penetration",
	BlockChance = "Block Chance",
	ExpertiseRating = "Expertise Rating",
}

-- U+2212 MINUS SIGN, so a screenshot can tell a loss from a hyphenated name.
local TRADE_OFF_MINUS = "\226\136\146"

function Verdict.orderStatLabel(word)
	if type(word) ~= "string" then return word end
	return ORDER_STAT_LABEL[word] or playerWord(word) or word
end

-- "Trade-off: +Intellect vs −Strength, −Stamina". Gains and losses are
-- already in published-tier order.
function Verdict.tradeOffText(gains, losses)
	local function listed(words, sign)
		local bits = {}
		for _, word in ipairs(words or {}) do
			bits[#bits + 1] = sign .. tostring(Verdict.orderStatLabel(word))
		end
		return table.concat(bits, ", ")
	end
	return "Trade-off: " .. listed(gains, "+") .. " vs " .. listed(losses, TRADE_OFF_MINUS)
end

-- Walk one order-only profile. Returns the same (verdict, reason, detail)
-- contract as weightedVerdict.
--
-- Conservative Pareto (Mightie, 2026-11-12): an Upgrade requires the
-- candidate to be equal or better on every ranked stat and better on at
-- least one. A loss on the first differing ranked tier is a Downgrade,
-- even if later ranked stats improve (the Ret cloak ruling). A gain on
-- the first differing tier with a later ranked loss is a Trade-off.
-- Unranked stats (Spirit, Armor on non-tank specs) still do not decide.
-- Ranked equality is |signedDelta| <= WEIGHT_EPSILON, so float noise
-- cannot mint an Upgrade. Intra-tier bundles and cap clamps are
-- unchanged; only the early return that ignored later ranked losses
-- is gone.
function Verdict.orderVerdict(candStats, eqStats, spec, allow, profile)
	if type(allow) ~= "function" then
		allow = function(verdict, reason) return verdict, reason end
	end
	profile = profile or (type(spec) == "table" and Verdict.profileFor(spec) or nil)
	if not Verdict.isOrderProfile(profile) then
		return "UNKNOWN", "verdict unavailable: the profile is not an order-only pack"
	end
	local cand = (type(candStats) == "table") and candStats or {}
	local eq   = (type(eqStats)   == "table") and eqStats   or {}
	local src  = type(spec) == "table" and spec.profileSource or nil
	local pname = orderProfileLabel(profile, src)
	local speedNote = nil
	local level = Verdict.playerLevel(spec)

	local function finish(verdict, reason, decidedBy, kind, tradeOffText)
		local detail = {
			profile = pname,
			decidedBy = decidedBy,
			orderOutcome = kind,
			speedNote = speedNote,
			caveat = Verdict.profileCaveat(profile),
			tradeOffText = tradeOffText,
		}
		if verdict == "UPGRADE" then
			local v, r = allow(verdict, reason)
			if v ~= "UPGRADE" then return v, r end
			return v, r, detail
		end
		if verdict == "TRADE_OFF" or verdict == TRADE_OFF then
			local v, r = allow(TRADE_OFF, reason)
			if v ~= TRADE_OFF then return v, r end
			return v, r, detail
		end
		return verdict, reason, detail
	end

	local function capLabel(tier, status)
		if status == "unknown" then
			return tier.name .. " (cap status unknown)"
		end
		local unit = tier.capUnit
		local cap = tier.capPercent or tier.capValue
		local after = tier.afterPercent or tier.afterValue
		local capText = formatBound(cap, unit)
		if capText == nil then
			local afterText = formatBound(after, unit)
			if afterText then
				return tier.name .. " (after " .. afterText .. ")"
			end
			return tier.name
		end
		if status == "at" then
			return tier.name .. " (at " .. capText .. " cap)"
		end
		return tier.name .. " (below " .. capText .. " cap)"
	end

	local function signedDelta(word)
		return (tonumber(cand[word]) or 0) - (tonumber(eq[word]) or 0)
	end

	-- A ranked pair is equal when the difference is inside the same
	-- named noise floor the weighted path uses. Exact ~= 0 would
	-- treat float crumbs as a first-tier gain and print Upgrade.
-- The comparison itself lives in Verdict.ranksAsDifferent since card
-- t_a5de2f16: this is a call-through, not a second copy of the rule.
	local function ranksAsDifferent(delta)
		return Verdict.ranksAsDifferent(delta)
	end

	local function isCapped(tier)
		return type(tier.capPercent) == "number"
			or type(tier.afterPercent) == "number"
			or type(tier.capValue) == "number"
			or type(tier.afterValue) == "number"
	end

	local firstKind, firstLabel = nil, nil
	local gains, losses = {}, {}
	local unitConflictExtra = nil

	local function note(kind, label, upWords, downWords)
		for _, word in ipairs(upWords or {}) do
			gains[#gains + 1] = word
		end
		for _, word in ipairs(downWords or {}) do
			losses[#losses + 1] = word
		end
		if firstKind == nil then
			firstKind = kind
			firstLabel = label
		end
	end

	for _, tier in ipairs(profile.tiers) do
		if type(tier) == "table" and type(tier.stats) == "table" then
			-- Leveling-only tags apply below 60 only. Unknown level
			-- includes the tier; we do not invent a level.
			if tier.levelingOnly and type(level) == "number" and level >= 60 then
				-- skip
			elseif tier.special == "dps_then_speed" then
				local dpsDelta = signedDelta("WeaponDps")
				if ranksAsDifferent(dpsDelta) then
					if dpsDelta > 0 then
						note("upgrade", "Weapon DPS", { "WeaponDps" }, nil)
					else
						note("downgrade", "Weapon DPS", nil, { "WeaponDps" })
					end
				end
				local spdDelta = signedDelta("WeaponSpeed")
				if ranksAsDifferent(spdDelta) then
					-- DPS is equal (or already noted); speed differs. The
					-- source does not say whether fast or slow is better,
					-- so do not rank it. Remember the note and continue.
					speedNote = "weapon speed differs (not ranked; the source does not prefer fast or slow)"
				end
			elseif isCapped(tier) then
				-- One capped rating or raw total. Use the first stat.
				-- A second occurrence of the same stat (Hit 8% then 17%)
				-- only counts the window after the previous cap.
				local word = tier.stats[1]
				local unit = (tier.capUnit == "raw") and "raw" or "percent"
				local cap = (unit == "raw") and tier.capValue or tier.capPercent
				local after = (unit == "raw") and tier.afterValue or tier.afterPercent
				local candStat, wornStat = cand[word], eq[word]
				local scale = tonumber(tier.ratingPerPercent)
				if type(scale) ~= "number" or scale == 0 then
					if tier.valueUnit == "percent" then
						scale = 1
					else
						scale = nil
					end
				end
				-- Expertise percent text is stored on Expertise and
				-- compared directly (scale 1). A rating-only line lives
				-- on ExpertiseRating and cannot be converted, so cap
				-- status is unknown and the raw rating is ranked.
				-- Mixed units (percent on one side, rating-only on the
				-- other) cannot be compared: record a Trade-off conflict.
				local mixedUnits = false
				if word == "Expertise" then
					local candUnit, wornUnit
					if cand.Expertise ~= nil then
						candUnit = "percent"
					elseif cand.ExpertiseRating ~= nil then
						candUnit = "rating"
					end
					if eq.Expertise ~= nil then
						wornUnit = "percent"
					elseif eq.ExpertiseRating ~= nil then
						wornUnit = "rating"
					end
					if candUnit and wornUnit and candUnit ~= wornUnit then
						mixedUnits = true
						local label = "Expertise (cap status unknown)"
						if unitConflictExtra == nil then
							unitConflictExtra = "percent and rating cannot be compared"
						end
						note("trade-off", label, nil, nil)
					elseif candUnit == "rating" or wornUnit == "rating" then
						candStat = cand.ExpertiseRating
						wornStat = eq.ExpertiseRating
						scale = nil
					else
						if type(scale) ~= "number" or scale == 0 then
							scale = 1
						end
					end
				end
				if not mixedUnits then
					local current
					if word == "Hit" and unit ~= "raw" then
						current = Verdict.currentCapPercent("Hit", spec, tier.hitKind)
					else
						current = Verdict.currentCapValue(word, spec, unit)
					end
					local delta, status = Verdict.clampedWindowDelta(
						candStat, wornStat, current, cap, after,
						scale, unit)
					if ranksAsDifferent(delta) then
						local label = capLabel(tier, status)
						if delta > 0 then
							note("upgrade", label, { word }, nil)
						else
							note("downgrade", label, nil, { word })
						end
					end
				end
			else
				-- Ordinary or bundled tier. Collect signed deltas; do not
				-- convert units or invent a combined score.
				local up, down = {}, {}
				for _, word in ipairs(tier.stats) do
					local delta = signedDelta(word)
					if ranksAsDifferent(delta) then
						if delta > 0 then
							up[#up + 1] = word
						else
							down[#down + 1] = word
						end
					end
				end
				if #up > 0 and #down > 0 then
					note("trade-off", tier.name, up, down)
				elseif #up > 0 then
					note("upgrade", tier.name, up, nil)
				elseif #down > 0 then
					note("downgrade", tier.name, nil, down)
				end
			end
		end
	end

	if firstKind == nil then
		-- No ranked tier decided. An unranked speed difference is reported
		-- but does not become an upgrade or a downgrade.
		return finish("NOT_UPGRADE",
			Verdict.orderReason(profile, "no change", nil, src, speedNote),
			nil, "no change")
	end

	-- A loss on the first differing ranked tier is a Downgrade, even if
	-- later ranked stats improve.
	if firstKind == "downgrade" then
		return finish("NOT_UPGRADE",
			Verdict.orderReason(profile, "downgrade", firstLabel, src),
			firstLabel, "downgrade")
	end

	-- A first-tier gain with no later ranked loss, and no intra-tier
	-- conflict, is a Pareto Upgrade.
	if firstKind == "upgrade" and #losses == 0 then
		return finish("UPGRADE",
			Verdict.orderReason(profile, "upgrade", firstLabel, src),
			firstLabel, "upgrade")
	end

	-- First differing tier is a gain (or an intra-tier conflict) and a
	-- ranked loss exists, or mixed Expertise units could not be compared.
	local extra
	if #gains > 0 and #losses > 0 then
		extra = Verdict.tradeOffText(gains, losses)
	else
		extra = unitConflictExtra or "those stats conflict"
	end
	return finish(TRADE_OFF,
		Verdict.orderReason(profile, "trade-off", firstLabel, src, extra),
		firstLabel, "trade-off", extra)
end

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
		-- One rule, not a second copy of the comparison (card t_a5de2f16):
		-- the ranked comparator and this tiebreaker must agree about a crumb
		-- smaller than WEIGHT_EPSILON.
		if Verdict.ranksAsDifferent(delta) then
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
function Verdict.weightedReason(w, profile, kind, tiebreakText, profileSource)
	local pname = type(profile) == "table" and profile.name or "no profile"
	-- Existing "[Retribution]" tests stay byte-identical when the source
	-- is absent. "(chosen)" / "(talents)" are appended only when set.
	if profileSource == "chosen" or profileSource == "talents" then
		pname = tostring(pname) .. " (" .. profileSource .. ")"
	end
	local head = "weighted " .. Verdict.numText(w.total)
		.. " [" .. tostring(pname) .. "]"
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
		-- A named spec with no sourced table must not be guessed as another
		-- pack. The verdict names the spec and stays silent (UNKNOWN).
		local label = type(spec) == "table" and (spec.profileLabel or spec.weightsKey) or nil
		if type(label) == "string" and label ~= "" then
			return "UNKNOWN", "no sourced weights for " .. label .. " yet"
		end
		-- Requirement 5: NO WEIGHTS IS NOT A TRADE-OFF. Fall through to direction
		-- counting and the player gets an amber "your call" for a pair nothing
		-- weighed — the exact silence-with-an-answer this card removes.
		local class = type(spec) == "table" and spec.class or nil
		local role = type(spec) == "table" and spec.role or nil
		return "UNKNOWN", "verdict unavailable: no stat weights for this character (class "
			.. tostring(class or "unknown") .. ", role " .. tostring(role or "unresolved") .. ")"
	end
	-- Order-only packs (Retribution today; other specs later) never invent
	-- a numeric total. They share this entry point so evaluate(), the
	-- tooltip, and the tests stay on one call.
	if Verdict.isOrderProfile(profile) then
		return Verdict.orderVerdict(candStats, eqStats, spec, allow, profile)
	end
	local w = Verdict.weightedTotal(candStats, eqStats, profile)
	if w == nil then
		return "UNKNOWN", "verdict unavailable: the " .. tostring(profile.name)
			.. " profile carries no weights"
	end
	local src = type(spec) == "table" and spec.profileSource or nil
	local pname = profile.name
	if src == "chosen" or src == "talents" then
		pname = tostring(pname) .. " (" .. src .. ")"
	end
	local detail = { total = w.total, profile = pname }
	local eps = Verdict.WEIGHT_EPSILON
	if w.total >= eps then
		local verdict, reason = allow("UPGRADE", Verdict.weightedReason(w, profile, "upgrade", nil, src))
		if verdict ~= "UPGRADE" then return verdict, reason end
		return verdict, reason, detail
	end
	if w.total <= -eps then
		return "NOT_UPGRADE", Verdict.weightedReason(w, profile, "downgrade", nil, src), detail
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
		local reason = Verdict.weightedReason(w, profile, kind, tb.text, src)
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
		local verdict, reason = allow(TRADE_OFF, Verdict.weightedReason(w, profile, "trade-off", nil, src))
		if verdict ~= TRADE_OFF then return verdict, reason end
		return verdict, reason, detail
	end
	return "NOT_UPGRADE", Verdict.weightedReason(w, profile, "no change", nil, src), detail
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
--      ⚠ SUPERSEDED IN PART (card t_984bc8ac, owner's ruling 2026-10-13): the
--      trade-off arm now FIRST offers the pair to the weighted layer
--      (weightedResolution above), which may resolve it to UPGRADE when the
--      weights clearly favour the candidate. Every other arm is unchanged, and
--      with no weights table the trade-off arm returns exactly what it always
--      did. (The 2026-10-04 "no stat weight anywhere" text that used to sit
--      here is quoted, dated, in the layer's own section.)
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
-- One side of `apiBySide`, resolved into (word table, unverified-key list).
-- Two shapes cross from the impure edge (card t_548f0341 introduced the read;
-- card t_795eee9e added the key list): the legacy plain words table — the
-- Defect-2 suites and direct test drivers still hand these in — and the
-- wrapper the live edge now ships: { words = <word table>,
-- unmapped = <sorted array of keys|nil> }. Both resolve the same way, so a
-- caller that prints the read (Verdict.statTable) and the verdict (evaluate)
-- never diverge on it. A non-table side is "no data", exactly like a nil side.
local function apiSideResolve(side)
	if type(side) ~= "table" then return nil, nil end
	local words = rawget(side, "words")
	if type(words) == "table" then
		local unmapped = rawget(side, "unmapped")
		return words, (type(unmapped) == "table" and unmapped or nil)
	end
	return side, nil
end

-- ---- Refusal wording (card t_fc11dd1c) --------------------------------------
-- "cannot classify: <line>" is the reason this module gives when a suppression
-- gate stops a pair, and that gate always fires for ONE side. Until this card
-- the string threw that knowledge away, and the owner read the consequence off
-- his first live hover: a Fishing Pole (no enchant of its own) compared against
-- a permanently-enchanted Wolfsbane refused
--
--     cannot classify: Enchanted: Weapon Damage +5
--
-- which points at the item in the player's bag when the unreadable line is on
-- the weapon being WORN. That is not cosmetic: "try another item" and "take the
-- enchant off what you are wearing" are different instructions.
--
-- ONE spelling, ONE place. Every suppression gate that names a line calls this
-- helper — gates 5 and 5a (candidate) and 8 and 8a (equipped) on the armour
-- path, and the two unmapped-key gates on the weapon path — so the two sides
-- cannot drift apart, and a gate added later inherits the wording instead of
-- inventing a sixth dialect.
--
-- The vocabulary is the PLAYER's, not this module's: `candidate`/`worn` are
-- parseSide's internal labels; what the player is looking at is the HOVERED item
-- and the EQUIPPED one. "item" rather than "weapon" because this helper serves
-- both comparators, and a weapon is an item.
local REFUSAL_SIDE_WORD = { candidate = "hovered", worn = "equipped" }
local function cannotClassify(side, line, qualifier)
	local which = REFUSAL_SIDE_WORD[side] or tostring(side)
	local reason = "cannot classify: " .. tostring(line)
	if qualifier ~= nil then
		return "UNKNOWN", reason .. " (" .. qualifier .. "; on the " .. which .. " item)"
	end
	return "UNKNOWN", reason .. " (on the " .. which .. " item)"
end

-- ── CARD t_9d718a77: SILENCE IS NOT "NOTHING THERE" ───────────────────────
-- The equal-damage-per-second claim is a claim ABOUT THE READ: "these two
-- weapons are the same" is only sayable over two tooltips that were both
-- understood. A digit-bearing line the parser could not place is not a line
-- with nothing in it — it is a line nobody read — and a confident "equal" over
-- one of those is the same fail-open shape the Sell Price rule closed (a claim
-- may never rest on a line you did not read).
--
-- So the weapon path's equal branch asks THIS question before it claims
-- sameness, and names the line it could not place. The sentence is
-- cannotClassify's — ONE refusal grammar in this file, so a reader who has seen
-- "cannot classify: <line>" elsewhere already knows what it means — with a
-- qualifier that states both halves of what the tool really knows: the tie on
-- damage per second (which IS true), and the line that stopped the pair from
-- being called the same. The side is named because a player looking at the
-- tooltip needs to know which item carried the line.
function Verdict.unreadEqualReason(line, side)
	-- ONE value out of cannotClassify: the sentence, not its (verdict, sentence)
	-- pair — a two-value return here would expand into the caller's return list
	-- and hand the verdict slot the word "UNKNOWN" as the reason.
	local _, reason = cannotClassify(side, line,
		"the weapons tie on damage per second, but that line could not be placed")
	return reason
end

-- ---- A DEFINITE NO is not a CANNOT-JUDGE (card t_8d3af71d) ------------------
-- The client's eligibility answer has two failure shapes, and until this card
-- they were reported as one:
--
--   * `false` — a DECISION the game has already made. This character cannot use
--     the item. That is a cannot-EQUIP: the requirement the item states, no
--     gain (there is none to give), no pretence of a comparison.
--   * nil / the secret sentinel / any non-boolean — an ABSENCE of information.
--     That stays exactly what it was: "eligibility unconfirmed (fail-closed)",
--     naming what was unconfirmed. The doctrine does not move.
--
-- The audit measured the defect on origin/main (ec947b3, fixture S6b): a Rogue
-- 20 holding a "Requires Level 40" item read
--     UNKNOWN — eligibility unconfirmed (fail-closed): client returned false …
-- where the spec's §15 case 6 asks for the requirement with no gain. The player
-- was told the addon did not know something the client had in fact settled.
--
-- WHAT MAY BE NAMED. Only a requirement the ITEM'S OWN LINES state and that the
-- character is demonstrably on the wrong side of — the level line against the
-- player's level, a class list that does not contain the player's class, an
-- armour material above the best this class can wear at this level. Anything
-- else is the generic sentence below: the client said no and we will not invent
-- a reason for it. An ambiguous answer never reaches this function at all —
-- gate 3 only calls it for `false`.
--
-- WHY THE TOKEN STAYS UNKNOWN. The four-token vocabulary is the comparator's
-- contract (the row's `verdict`, the arrow, GearAPI.IsUpgrade/GetGain). A
-- definite no offers no gain and no comparison, so it must answer exactly like
-- every other non-answer to those consumers — nil from GetGain, nil from
-- IsUpgrade, no arrow. Only the WORDS change, which is what the card asks for,
-- and it is why a fifth token would be a wider change for a worse contract.
Verdict.CANNOT_EQUIP = "cannot equip"
local CANNOT_EQUIP_LEAD = Verdict.CANNOT_EQUIP .. " — "

-- The four armour materials, worst to best — the module's ONE ranking
-- (Verdict.ARMOR_RANK, above). This section adds no second table: it compares an
-- item's own material against the best its class can wear (Verdict.bestArmor)
-- and never prices anything.

-- One line, de-coloured (an unmet requirement ships red on this client),
-- trimmed and lower-cased. The ONE normaliser every reader here uses.
local function requirementLine(line)
	if type(line) ~= "string" then return nil end
	local plain = deColour_(line):gsub("^%s+", ""):gsub("%s+$", "")
	if plain == "" then return nil end
	return plain
end

-- "Requires Level 40" -> 40. Anchored to the whole line: a requirement quoted
-- inside a longer sentence is not the item's requirement line.
local function requiredLevelOf(lines)
	if type(lines) ~= "table" then return nil end
	for i = 1, #lines do
		local plain = requirementLine(lines[i])
		if plain then
			local n = plain:lower():match("^requires%s+level%s+(%d+)$")
			if n then
				local level = tonumber(n)
				if level and level > 0 then return level end
			end
		end
	end
	return nil
end

-- "Classes: Priest, Mage" -> <display list>, <lower-cased set>. Both nil when
-- the item states no class restriction. The list is the CLIENT's own words, so
-- the named requirement is the item's, not ours.
local function classListOf(lines)
	if type(lines) ~= "table" then return nil, nil end
	for i = 1, #lines do
		local plain = requirementLine(lines[i])
		if plain then
			local rest = plain:match("^[Cc]lasses%s*:%s*(.+)$")
			if rest then
				local shown, seen, any = {}, {}, false
				for name in rest:gmatch("[^,]+") do
					local w = name:gsub("^%s+", ""):gsub("%s+$", "")
					if w ~= "" then
						any = true
						seen[w:lower()] = true
						shown[#shown + 1] = w
					end
				end
				if any then return table.concat(shown, ", "), seen end
				return nil, nil
			end
		end
	end
	return nil, nil
end

--- The reason for a DEFINITE ineligibility: the requirement the item states,
--- with no gain. Always prefixed with Verdict.CANNOT_EQUIP, which is the family
--- marker the tooltip surface keys on (ChestAdvisor.lua's cannotEquipTail).
---
--- Grounded facts first (level, then the class list the item carries, then the
--- material the class cannot wear); the generic sentence when the item states no
--- requirement we can check. It never returns a refusal word — "unconfirmed" is
--- the other family's word and the two must not merge. A race restriction is NOT
--- named: this module is handed no race read, and a race line we cannot check
--- against the character would be a guess wearing the item's words.
function Verdict.cannotEquipReason(lines, spec)
	local s = type(spec) == "table" and spec or {}
	local playerLevel = type(s.level) == "number" and s.level or nil

	local level = requiredLevelOf(lines)
	if level ~= nil and playerLevel ~= nil and playerLevel < level then
		return CANNOT_EQUIP_LEAD .. "requires level " .. tostring(level)
	end

	local classText, classSet = classListOf(lines)
	if classText ~= nil and type(s.classDisplay) == "string" then
		local mine = s.classDisplay:gsub("^%s+", ""):gsub("%s+$", ""):lower()
		if mine ~= "" and classSet[mine] ~= true then
			return CANNOT_EQUIP_LEAD .. classText .. " only"
		end
	end

	local material = Verdict.tooltipArmorMaterial(lines)
	if material ~= nil and type(s.class) == "string" and playerLevel ~= nil then
		local best = Verdict.bestArmor(s.class, playerLevel)
		local rank = Verdict.ARMOR_RANK or {}
		if type(best) == "string"
			and (rank[material] or 0) > (rank[best] or 0) then
			return CANNOT_EQUIP_LEAD .. "requires " .. material
		end
	end

	return CANNOT_EQUIP_LEAD .. "this character cannot use it"
end

-- `slotWord` (card t_d88b7f28, item 3) is OPTIONAL and is the display word for
-- the worn slot this pair is judged in ("chest", "legs", "finger"). It is used by
-- ONE branch — the empty-slot shortcut, gate 6 — so that the reason names the
-- slot the player is actually looking at. It is a plain word and not a slot
-- table on purpose: ChestAdvisor's SLOT_WORD (which agrees with WoWAI's
-- EQUIP_SLOT and StatForge's SLOT_NAMES) stays the ONLY slot vocabulary, and a
-- caller that cannot name its slot passes nothing rather than inventing one.
-- ---- Step 3 C7 (card t_8e171c28): THE SEAM ----------------------------------
--
-- WHAT THIS IS. The one place the arbitration layer may speak: it narrows
-- exactly one of the comparator's outcomes — TRADE_OFF — and only when the
-- caller supplied the character's own totals.
--
-- WHERE IT SITS, and how that moved. The scoping doc (§2.1) cut this seam at
-- `weightedResolution`'s decline, in an `outcome == "trade-off"` arm that no
-- longer exists: card t_3319dc9d (C1) replaced that layer with
-- `Verdict.rankedVerdict`, and the shipped path reaches the trade-off wording
-- through `state == "trade_off"`. The INTENT is identical and is what this hook
-- preserves — the cascade has its say first, the arbitration is consulted
-- second, the trade-off wording is the fall-through — so the seam lives at that
-- one point in `Verdict.evaluate` (search TRADE_OFF_SEAM).
--
-- THE CONTRACT, in three parts:
--   1. `totals` is an ARGUMENT, never a read. This module stays pure (see the
--      module header): the impure edge is ChestAdvisor.lua's snapshot, handed
--      down the path `apiBySide` already travels.
--   2. A nil from the judge changes NOTHING — absent module, no judge, a raise,
--      or a refusal all return nil here and the caller falls through to the
--      bytes the player sees today. Asserted against a pre-card tree by
--      t_8e171c28-nonvacuity.js, not claimed.
--   3. The ARMOUR-MATERIAL trade-off is not served (§1.3). Those pairs reach
--      TRADE_OFF through the `allow()` softening, which runs AFTER this hook —
--      so a material pair cannot be overturned by the model, and if the model
--      DID answer, `allow` would soften its answer by the same rule.
--
-- THE TOKENS. The judge's SIDEGRADE ("inside the band") maps to this module's
-- TRADE_OFF token, not to a fifth token: every consumer of the four-token
-- vocabulary (the arrow, the chip, GearAPI.IsUpgrade/GetGain, the row's own
-- `verdict`) then agrees without a second switch. The player-facing word
-- "Sidegrade" is a RENDERED word (ChestAdvisor.lua's TOOLTIP_UI), exactly as
-- UPGRADE renders as "Upgrade".
local ARBITRATION_STATE_TOKEN = {
	UPGRADE     = "UPGRADE",
	NOT_UPGRADE = "NOT_UPGRADE",
	SIDEGRADE   = "TRADE_OFF",
}
Verdict.ARBITRATION_STATE_TOKEN = ARBITRATION_STATE_TOKEN

-- The buff warning the doc's §3 names, verbatim. Appended by `Verdict.arbitrate`
-- (one place) so every surface that reads the reason carries it. No number: it
-- is a statement about the reading, not a finding about the pair.
Verdict.BUFF_WARNING = "judged with buffs on — a buff can fake a cap and inflate a pool"

--- The arbitration's answer for a trade-off pair, or nil.
---
--- Returns (token, reason, detail): token is UPGRADE / NOT_UPGRADE / TRADE_OFF,
--- nil when the layer has no opinion. `detail` is the judge's own table
--- (state, driving, margin, band, context, confidence, bandSource, binding,
--- survival, flip, buffed, lowWhy, byContext) — data for the surface, never a
--- second decision.
---
--- A DECLINE is (nil, why, { declined = true, why = <the refusal>, cause = <key> })
--- (card t_eff0caec). The model was ASKED and turned the pair away; its sentence and
--- its stable cause key are returned instead of deleted, so the surface can say which
--- judgement did not happen. `cause` is a machine key, never prose the renderer
--- matches on. Silent nil stays for the absences that are not answers: no totals, an
--- absent module, a raise, a state this table cannot map.
---
--- `Arbitration` is resolved at CALL time through the global (the toc loads
--- Verdict.lua before it, and the fengari VMs load the two separately). A
--- module that is absent, has no judge, or raises is SILENCE: this function
--- must never be able to change a row by failing.
--
--- SURVIVAL (§4.4) is applied HERE, not in the renderer, because it is a
--- decision: survival is its own axis, it may decide ONLY when the throughput
--- model lands inside the band, and when it does the reason line says so. The
--- model itself never sets `decides` — its survival block is data — so the gate
--- has exactly one owner and a decisive throughput answer can never be
--- overridden by hit points. A pair that ties on survival as well keeps the
--- model's own sentence ("under the band either way — pick the one you like"),
--- which is the tie the doc asks for.
local TIE_SENTENCE = "under the band either way — pick the one you like."
local SURVIVAL_SENTENCE = {
	candidate = "under the band on throughput — survival decides for the hovered item,"
		.. " which keeps you standing.",
	equipped = "under the band on throughput — survival decides for the equipped item,"
		.. " which keeps you standing.",
}

--- "candidate" | "equipped" | nil, from the model's survival block.
---
--- A survival call needs BOTH axes pointing the same way. More health with worse
--- mitigation (the crossing case) is a genuine tie, and a tie is never invented
--- into a winner: the player gets the model's "pick the one you like" instead.
local function survivalVerdict(s)
	if type(s) ~= "table" then return nil end
	local hp, mit = tonumber(s.dHP), tonumber(s.dMitigation)
	if hp == nil or mit == nil then return nil end
	if hp >= 0 and mit >= 0 and (hp > 0 or mit > 0) then return "candidate" end
	if hp <= 0 and mit <= 0 and (hp < 0 or mit < 0) then return "equipped" end
	return nil
end

function Verdict.arbitrate(candStats, eqStats, spec, totals)
	if type(totals) ~= "table" then return nil end
	local A = rawget(_G, "Arbitration")
	if type(A) ~= "table" or type(A.judge) ~= "function" then return nil end
	local ok, v, why, cause = pcall(A.judge, candStats, eqStats, spec, totals)
	if not ok then return nil end
	if type(v) ~= "table" then
		-- THE DECLINE, DISCLOSED (card t_eff0caec). The judge answers `nil, why, cause`
		-- when the model has no opinion; before this card the why was dropped on the
		-- floor here and the player could not tell "no opinion" from "never called".
		-- The refusal rides out in the detail slot the callers already pass through,
		-- marked `declined = true` so nothing can read it as a judgement. THE VERDICT
		-- WORD DOES NOT MOVE: this is a disclosure, and the caller keeps its own token.
		-- A raise, an absent module or an unmappable state stay plain silence — those are
		-- failures of the layer, not answers of the model, and a sentence about them
		-- would be this module guessing.
		if type(why) ~= "string" or why == "" then return nil end
		return nil, why, { declined = true, why = why, cause = cause }
	end
	local token = ARBITRATION_STATE_TOKEN[v.state]
	if token == nil then return nil end
	local reason = type(v.reason) == "string" and v.reason or ""
	-- §4.4, in ONE place: the survival axis may only speak inside the band.
	if v.state == "SIDEGRADE" then
		local sv = survivalVerdict(v.survival)
		v.survivalVerdict = sv
		if sv ~= nil then
			local pos = reason:find(TIE_SENTENCE, 1, true)
			if pos ~= nil then
				reason = reason:sub(1, pos - 1) .. SURVIVAL_SENTENCE[sv]
					.. reason:sub(pos + #TIE_SENTENCE)
			end
			-- No anchor found means the model reworded its tie sentence. Then
			-- NO survival claim is made at all (the reason and the survival
			-- line would otherwise contradict each other) — the battery pins
			-- the anchor so the reword is caught in CI, not in a hover.
		end
	end
	if v.buffed == true then
		reason = reason .. " " .. Verdict.BUFF_WARNING .. "."
	end
	return token, reason, v
end

function Verdict.evaluate(candidate, equipped, spec, apiBySide, slotWord, totals)
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
	local candWords, candUnmapped = apiSideResolve(api and rawget(api, "candidate"))
	local wornWords, wornUnmapped = apiSideResolve(api and rawget(api, "worn"))
	local candStats, candProc, candUnknown =
		parseSide(candLines, "candidate", candWords)
	local eqStats,   eqProc,   eqUnknown   =
		parseSide(eqLines,   "worn",      wornWords)

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
	--     other non-boolean return returns UNKNOWN whether the chest slot is
	--     empty or filled.
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
	--
	--     CARD t_8d3af71d: the gate answers UNKNOWN either way, but the TWO
	--     KINDS of "not true" are no longer reported as one. A plain `false`
	--     is the client's DECISION — this character cannot use the item — and
	--     reads the requirement with no gain (Verdict.cannotEquipReason). Every
	--     other shape is an ABSENCE of information and keeps the fail-closed
	--     "eligibility unconfirmed" wording, byte for byte. The secret check
	--     comes FIRST: a secret value that compares equal to `false` is not a
	--     decision we are allowed to read, so it stays unconfirmed.
	if candExplicit and candCanUse ~= true then
		if type(issecretvalue) == "function" and issecretvalue(candCanUse) then
			return "UNKNOWN", "eligibility unconfirmed (fail-closed): client returned the secret-value sentinel"
				.. " — the client did not affirmatively confirm this character can use this item"
		elseif candCanUse == false then
			-- A definite no: not a cannot-judge.
			return "UNKNOWN", Verdict.cannotEquipReason(candLines, spec_)
		end
		local detail
		if candCanUse == nil then
			detail = "client returned nil (Could Not Classify)"
		else
			detail = "client returned a non-boolean value of type " .. type(candCanUse)
		end
		return "UNKNOWN", "eligibility unconfirmed (fail-closed): " .. detail
		.. " — the client did not affirmatively confirm this character can use this item"
	end

	-- Gate (5a) — the client's own stat read for the CANDIDATE returns a key
	--     this module has not verified (card t_795eee9e, AC-C): the item
	--     carries a stat the comparison cannot classify. House doctrine
	--     (module line 20) — never a fabricated 0, never a silent drop — so
	--     the answer is UNKNOWN, naming the key the client itself returned,
	--     not a decision on the subset of stats it does know. Runs before
	--     the empty-slot shortcut (gate 6) and the gate-5 text suppress
	--     alike: an unclassified stat on the candidate wins in both slot
	--     states, the same AC-E13(a) placement gate 5 itself has.
	if type(candUnmapped) == "table" and #candUnmapped > 0 then
		return cannotClassify("candidate", candUnmapped[1],
			"a client stat key this addon has not verified")
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
		return cannotClassify("candidate", which)
	end

	-- Gate (5b) — a mapped word whose unit is UNCONFIRMED, on the
	--     CANDIDATE (card t_e2603a9c, item 1 — the owner's OPTION 3 ruling):
	--     the word closes the pair only when its unit is on the ruled
	--     UNCONFIRMED_UNITS list (Dodge and Parry by PRESENCE, the rule still
	--     live); a zero or missing weight is worth 0 since card C1 and does
	--     not close it. The difference-only set that gate 8c reads is EMPTY
	--     since card t_9d3273cb retired its last two words, so every word
	--     reaching this gate now either prices or closes right here. Hit and
	--     Crit left the list on card t_ea404bae and are priced like any other
	--     word. Without this gate the pair would be decided on the priced
	--     words alone, the unpriced stat silently dropped.
	--     (The card's repro: +5 Agility against a worn +3 Agility, +1% crit,
	--     answered UPGRADE on the Agility half. That is what it answers again
	--     since card t_ea404bae retired Crit from the list with its unit
	--     measured — and the reason it is acceptable is written on that card's
	--     HONESTY REQUIREMENT: on this pair the crit is a PASSENGER on the
	--     dominance walk, not a deciding term, until card t_da23ec75 makes
	--     hit/crit terms of the dominance proof. "It decides" and "the crit
	--     decided it" are different claims and only the first one is true
	--     here.) The answer is UNKNOWN, the word in the module's
	--     own vocabulary, never the client key the read came from. Runs after
	--     the gate-5 suppress (a line the pair cannot even classify wins that
	--     reason) and before the empty-slot shortcut (gate 6) — the same
	--     AC-E13(a) placement as gates 5a/5: a stat the spec does not price
	--     cannot be waved in to fill a slot.
	-- specWeights is not read by the gate (card C1); it is resolved here
	-- because the dominance proof below takes its terms from it (proofTerms).
	local specWeights =
		Verdict.weightsFor(spec_.class, spec_.role, spec_.clientRole)
	local candUnpriced = Verdict.unpricedWord(candStats)
	if candUnpriced ~= nil then
		return "UNKNOWN", Verdict.unpricedWordReason(candUnpriced)
	end

	-- Gate (6) — genuinely empty slot (the caller sent nil).
	--     Only reachable when candCanUse == true (gate 3 above already
	--     failed every other case) and the candidate carries no suppress
	--     (gate 5 above).
	-- Lower armor is a SOFT cost against the WORN item, never a veto (owner
	-- ruling 2026-11-03 — card t_c1b7f815; the rule used to compare the
	-- candidate against the class's best and hard-blocked upgrades the player
	-- could actually wear). A worn material ranked above the candidate turns an
	-- UPGRADE into TRADE_OFF and, exactly as before, a TRADE_OFF into
	-- NOT_UPGRADE. `emptySlot` short-circuits the rule where nothing is worn.
	-- Unknown lines have already returned, so this does not hide a stat we
	-- failed to read, and an unreadable WORN material falls through unchanged.
	-- The slot the reason names (card t_d88b7f28, item 3): the word the caller
	-- supplied, or — for a caller that has no slot identity to give — a phrase
	-- true of every slot. The reason used to be the constant "no chest equipped;
	-- this item would fill the slot" for every row, head to ring, and each
	-- display caller had to string-match that sentence and rewrite it. One such
	-- rewrite still exists in the git history of ChestAdvisor.lua; this is the
	-- contract that replaces it.
	local slotName = nil
	if type(slotWord) == "string" and slotWord:match("%S") ~= nil then
		slotName = slotWord
	end
	local function allow(verdict, reason, emptySlot)
		if verdict ~= "UPGRADE" and verdict ~= TRADE_OFF then
			return verdict, reason
		end
		if emptySlot then return verdict, reason end
		local why = Verdict.lowerArmorReason(candLines, eqLines)
		if why ~= nil then
			if verdict == "UPGRADE" then
				return TRADE_OFF, reason .. "; " .. why
			end
			return "NOT_UPGRADE", why
		end
		return verdict, reason
	end

	if eqLines == nil and candExplicit and candCanUse == true then
		if slotName ~= nil then
			return allow("UPGRADE",
				"no " .. slotName .. " equipped; this item would fill the slot", true)
		end
		return allow("UPGRADE",
			"nothing equipped in that slot; this item would fill it", true)
	end

	-- Gate (7) — a slot FILLED by an item whose stats we could not read.
	--     Not an empty slot: the shortcut above is long past, and a strictly
	--     weaker candidate must not read as UPGRADE against the fabricated
	--     zeros a failed read would give. (gate defect 4: a missing read is
	--     not a zero.) A line list that is empty, or that yielded no stat
	--     word and no unrecognised word either, is the "un-readable" state —
	--     and so is one whose non-blank lines could not be classified at all
	--     (B2: they suppress rather than silently reading as zero).
	if next(eqStats) == nil and eqProc == nil and eqUnknown == nil then
		return "UNKNOWN", "the equipped item's stats could not be read; cannot judge"
	end

	-- Gate (8a) — the same shape on the EQUIPPED side (card t_795eee9e, AC-C):
	--     an unverified key in the client's read of the worn item suppresses
	--     too — the player is not compared against a half-read item, and the
	--     unknown stat is never priced as the zero it is not.
	if type(wornUnmapped) == "table" and #wornUnmapped > 0 then
		return cannotClassify("worn", wornUnmapped[1],
			"a client stat key this addon has not verified")
	end

	-- Gate (8) — a suppressing line on the EQUIPPED side: the same proc /
	--     unknown-word / unplaceable shapes as gate 5, on the worn item.
	--     Suppression, not fabrication — an unknown line on either side is
	--     UNKNOWN (unchanged from the old combined Gate 7).
	if eqProc ~= nil or eqUnknown ~= nil then
		local which = eqProc or eqUnknown
		return cannotClassify("worn", which)
	end

	-- Gate (8b) — THE SAME gate on the EQUIPPED side (card t_e2603a9c, item
	--     1): the card's repro carries the unpriced word here — a +5 Agility
	--     candidate against a worn +3 Agility, +1% crit, which only this gate
	--     sees. One side of the pair is enough to fail it closed; the word
	--     and the reason grammar are the candidate side's (one map, one shape).
	--     Both sides are asked through the same predicate.
	local wornUnpriced = Verdict.unpricedWord(eqStats)
	if wornUnpriced ~= nil then
		return "UNKNOWN", Verdict.unpricedWordReason(wornUnpriced)
	end

	-- Gate (8c) — THE DIFFERENCE-BASED UNCONFIRMED-UNIT GUARD (card t_d53877b1,
	-- the owner's OPTION C; the rule and its reasoning sit on
	-- Verdict.unconfirmedDifference above, ONE predicate, no second copy).
	-- The set this gate reads is EMPTY as of card t_9d3273cb: its last two
	-- members were the two spell words, retired with their two weight keys (the
	-- client's recap is quoted verbatim under WEIGHT_KEYS — spell, melee and
	-- ranged hit are one stat, and so are the three crits). Hit and Crit left
	-- earlier, on card t_ea404bae, with their unit measured at 10 and 14 rating
	-- per 1%. So no pair fails closed here today, and every hit/crit pair
	-- reaches gate 9 and the weighted layer with the rating the unit of record
	-- on both paths. THE GATE ITSELF STAYS, with its one predicate and its two
	-- call sites: it is the mechanism a future unmeasured word re-enters
	-- through, and deleting it would only mean inventing it again later.
	-- While the two sides carry the SAME value the unit cancels and the pair is
	-- decided normally; the moment they DIFFER the price
	-- is load-bearing and unmeasured, and the pair fails closed instead of
	-- asserting a win (or a loss) over a number the tool cannot read.
	-- PLACEMENT: after gates 8/8b — both stats tables are known here, and the
	-- unreadable/suppressed shapes have already answered with their own reasons
	-- — and BEFORE gate 9, so no dominance outcome is ever computed on a pair
	-- this guard owns. It sits BELOW the empty-slot shortcut (gate 6) on
	-- purpose: filling an empty slot carries no comparison, so there is no
	-- difference for the unit to contaminate.
	local unconfirmedDiff = Verdict.unconfirmedDifference(candStats, eqStats)
	if unconfirmedDiff ~= nil then
		return "UNKNOWN", Verdict.unpricedWordReason(unconfirmedDiff)
	end

	-- Gate (9) — the verdict.
	--
	-- The answer comes from ONE ordered cascade, Verdict.rankedVerdict above:
	-- the class/role's order in force, then the words the pair's own pack prices
	-- and the order does not rank. A weight is a SUPPORT SET there — "does this
	-- spec care about the word at all" — never an amount: no threshold, no
	-- margin, no weighted total can turn a mixed pair green. `dominance` /
	-- `proofTerms` are no longer consulted on this path (they still describe the
	-- weapon path and the Step 3 engine; card t_0bf5c207 clauses A/B).
	--
	--   UPGRADE   (green arrow)  nothing priced moves against, something moves for
	--   TRADE_OFF (amber chip)   movement both ways, both sides named
	--   downgrade (no mark)      uniformly worse; the highest ranked word names it
	--   equal     (no mark)      nothing moves; the Armor/Block tiebreak may speak
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
					return "NOT_UPGRADE", loseReason(word)
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

	-- (card t_da23ec75) THE PROOF'S TERM LIST — order first (wording), then
	-- every word this pair's own pack prices (proof). One list, built by one
	-- function, read by the proof AND by the two loops that word its answer
	-- below, so the term that decided a pair is always the term the reason
	-- names. `specWeights` is gate 5b's resolution: the same table both sides
	-- of this comparison were already priced against.
	local terms = Verdict.proofTerms(order, specWeights)
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
	-- ⚠ THE TRADE-OFF SEAM (upstream cards t_8e171c28 / t_ce1c4a4f; this cut,
	-- card t_58762500). The arbitration call belongs in THIS region: a trade-off
	-- pair is the only thing this engine ever offers the model, and this is the
	-- only place the shipped path hands one back.
	--
	-- WHY IT WAS MISSING, named so the next re-cut can look for it: the region
	-- was replaced WHOLE by the weighted layer (card t_3a744b4a), and the
	-- replacement did not carry the call across with it. The old side of that
	-- hunk ended `return allowedV, allowedR`; the new side ended without it. It
	-- was an OMISSION IN THE REPLACEMENT REGION, not anchor drift — so nothing
	-- complained: the patch applied cleanly, the digest matched, the suite ran,
	-- and the definition of `Verdict.arbitrate` stayed in the file with no
	-- caller. A later re-pin then brought `Arbitration.ENABLED = true` in a
	-- pristine file, which is the shape that looks wired and answers nothing.
	-- The gate below is upstream's, reproduced: only a TRADE_OFF, only when the
	-- caller passed totals, only while the flag is on — read through the global
	-- at CALL time, exactly as `Verdict.arbitrate` resolves the module.
	-- `allow` runs on the model's answer for the same reason it runs above: the
	-- lower-material rule outranks both answers, and a pair it softened was
	-- already answered before `weightedVerdict` returned a TRADE_OFF here.
	if v == TRADE_OFF and type(totals) == "table" then
		local Arb = rawget(_G, "Arbitration")
		if type(Arb) == "table" and Arb.ENABLED == true then
			local av, aReason, aDetail = Verdict.arbitrate(candStats, eqStats, spec_, totals)
			if av ~= nil then
				local fv, fr = allow(av, aReason)
				-- The model's table RIDES the row's detail, never in place of it:
				-- the weighted total and the profile name are this path's own
				-- answer and the window quotes them off the row. `d.arbitration`
				-- is what ChestAdvisor's row builder publishes as `row.arbitration`.
				d = (type(d) == "table") and d or {}
				d.arbitration = aDetail
				return fv, fr, d
			end
			-- THE DECLINE, THROUGH THE GATE (card t_eff0caec, carried into the
			-- client by card t_18eb91e6). The model was ASKED and turned the pair
			-- away: arbitrate answers (nil, why, { declined = true, why, cause }).
			-- Upstream returns it through this gate so the surface can name the
			-- judgement that did not happen, and this region is a REPLACEMENT — a
			-- re-pin that moved the pin without carrying these lines would ship a
			-- clause map nothing hands a cause to, with --verify-shipped still green
			-- (it compares the vendored copy to the pin and never asks whether the
			-- overlay took). THE WORD DOES NOT MOVE: the row keeps its own TRADE_OFF
			-- answer (`v, r`), and only the detail rides out, set exactly as the
			-- answered case above sets it, so ChestAdvisor publishes it as
			-- `row.arbitration` and `TOOLTIP_UI.declineClause` can read `cause`.
			if type(aDetail) == "table" and aDetail.declined == true then
				d = (type(d) == "table") and d or {}
				d.arbitration = aDetail
				return v, r, d
			end
		end
	end
	if v ~= nil then return v, r, d end
end

if Verdict.LEGACY_DOMINANCE_DECIDES then
	local outcome, firstDiff = Verdict.dominance(candStats, eqStats, terms)

	-- Gate 8d (card t_e2ebb44e) is deliberately ABSENT here — see the SUPERSEDED
	-- record above: card t_da23ec75's proofTerms already weighs every priced
	-- word, so closing these pairs was a cost with no remaining protection.

	if outcome == "dominant" then
		-- Word the win with the SAME grammar the legacy path used: the first
		-- term of the proof on which the candidate is strictly better. Order
		-- words come first, so every pre-card win names the order term it named
		-- before; a win that only a PRICED word establishes (nothing in the
		-- order differs) now names that word instead of the bare fallback.
		for _, word in ipairs(terms) do
			if termSign(word, rawget(candStats, word), rawget(eqStats, word)) > 0 then
				return allow("UPGRADE", winReason(word))
			end
		end
		return allow("UPGRADE", winReason())
	end

	if outcome == "dominated" then
		-- The mirror: the first term the candidate is strictly worse on.
		for _, word in ipairs(terms) do
			if termSign(word, rawget(candStats, word), rawget(eqStats, word)) < 0 then
				return "NOT_UPGRADE", loseReason(word)
			end
		end
		return "NOT_UPGRADE", "not better than what's equipped"
	end

	if outcome == "trade-off" then
		-- (card t_984bc8ac) The weighted layer gets the FIRST word here and the
		-- ordinal answer the last: it returns nil unless a weights table for
		-- this class/spec validates AND the weighted margin clears
		-- Verdict.WEIGHT_THRESHOLD. With no table it is a pure pass-through, so
		-- the line below is byte-for-byte today's behaviour. `allow` still
		-- wraps both answers, so the lower-armor material rule outranks them.
		local wv, wReason = weightedResolution(candStats, eqStats, spec_)
		if wv ~= nil then return allow(wv, wReason) end
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
	--     pair would read TRADE_OFF and overturn the loss. The maintainer: "E2 … stands".
	--   * Their semantics are a two-sided value comparison, absence NEUTRAL
	--     (never a fabricated 0), a literal 0 a VALUE. rawget keeps absence
	--     distinguishable from zero (AC-E13(c)/(d)).
	--   * Card t_ea260b42 makes this the ONLY place their prices can decide:
	--     `weightedScore` no longer spends a PROOF_EXEMPT word, so the same 40
	--     Block is silent on a trade-off pair (W4f) exactly as it is on a
	--     one-sided one (W4e) — and still decides an otherwise-equal two-sided
	--     pair (W4c), which is the tiebreak doing its one job.
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
-- client itself groups them (review §2: `isEquippedInOffhand` = SHIELD |
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

-- §2, narrowed (card t_1677cd39): the ONE token that IS the dual-wielder's off
-- hand. A shield and a held-in-off-hand frill are not weapons; an off-hand weapon
-- is the item the rogue's slot exists for, and the audit's I3b showed the gate
-- refusing it ("the off hand is out of scope for ROGUE"). This set is what the
-- gate consults so a slot whose real content is a weapon is JUDGED rather than
-- declined — still like-for-like (G4 untouched), still closed by a two-hander in
-- the main hand (G0 untouched), still a class fact rather than a spec policy
-- (Verdict.offHandHoldsWeapon).
Verdict.OFF_HAND_WEAPON_TOKENS = {
	["INVTYPE_WEAPONOFFHAND"] = true,
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
-- capture `SavedVariables/Touchstone.lua` is exactly that row:
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
-- (INVSLOT_RANGED). INVTYPE_WEAPON is positional (review §2) — the client resolves
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

-- Shield-capable classes, as our own statement of the era ruleset (review §3:
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
-- reference addon's localised ones (review §9). Every decline the gate can return
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
-- `role` is the client's own TANK/HEALER/DAMAGER word (review §3). Where a class
-- had two specs of the SAME role (review §4 note about Warrior and Paladin) the
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
		-- review §4: the shaman row is CONTESTED in our corpus. Marked, not
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
	-- ROGUE's row carries ANOTHER fact beside the shield policy (card
	-- t_1677cd39): `offHandWeapon = true` says the slot the rogue's off hand
	-- actually holds is a WEAPON. That is what made the shipped G2 wrong for an
	-- off-hand weapon candidate — the audit's I3b: "a rogue off-hand is refused:
	-- the off hand is out of scope for ROGUE" — and it is the fact the gate now
	-- reads instead of declining the one item the slot exists for. A SHIELD is
	-- still out of scope for a rogue (G1 fires: the class cannot wear one).
	ROGUE   = { roles = { shield = "irrelevant", offHandWeapon = true } },
	HUNTER  = { roles = { shield = "irrelevant" } },  -- no off-hand item in this era
	-- Everything else (a class token we do not know) is genuinely absent ->
	-- no bucket -> G3, which is the correct reason for an unresolved identity.
}

-- ---- Defect 1 (card t_548f0341): is this spec read a REAL specialization? ----
--
-- The client's C_SpecializationInfo returns, for a character with no
-- specialization yet (a live level-22 character, verbatim probe):
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
-- diag record (review §6: the bucket survives as (a) the reason string and (b) the
-- diag record). Returns "required" | "allowed" | "irrelevant" | nil, where nil
-- means "the policy could not be resolved for this character" (an unknown
-- class, a role word we do not cover, no readable role, or a same-role collision
-- whose name we could not disambiguate) — the caller turns that into G3.
--
-- The classification is CLASS-INDEPENDENT on purpose (the implementer's build note #2,
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
	-- At level 22 a character has no specialization, so the client
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

-- ---- A weapon the SPEC cannot use (card t_1677cd39) -------------------------
--
-- THE MEASUREMENT THIS TABLE ANSWERS. Slice 2's audit (fixtures S3a/S3b) asked
-- whether the dagger lock is per-CLASS or per-SPEC. The answer was measured, not
-- chosen:
--
--   * the spec/role/clientRole triple cannot say it. All three rogue specs read
--     class = ROGUE, role = "melee", clientRole = "DAMAGER": nothing in that
--     triple separates Assassination from Combat.
--   * Verdict.ORDERS agrees — ROGUE is a PURE class there (ONE `melee` order,
--     the role argument ignored, so the order cannot carry a spec either).
--   * Weights.lua agrees twice: ROGUE carries ONE key (`melee`) and the
--     corpus's only rogue pack is rogue-combat.dps, with tabSpecs.ROGUE mapping
--     all three tabs to it. So a per-CLASS "rogues use daggers" rule would
--     contradict the very pack the weights layer is built on — and the card's
--     own premise, that a Combat rogue genuinely uses swords.
--   * the ONE vocabulary in this module that can speak about a spec BY NAME is
--     `Verdict.substantiated` + `bucket.byName` in OFF_HAND_BUCKETS (§3, the
--     warrior Arms/Fury same-role collision). This table uses EXACTLY that —
--     same class-token + role-word key, same `byName` disambiguator, same
--     classDisplay guard, same fail-closed rule. No second taxonomy.
--
-- So the rule is PER-SPEC, and only where the corpus has RULED it:
--
--   Assassination  ROGUE  daggers. Sources: docs/research/deep-dive-weights-
--                  review-2026-10-17.md ("Mutilate needs two daggers";
--                  "Daggers in both hands are required for Mutilate. A
--                  non-dagger off-hand 'upgrade' is a loss for Mutilate
--                  builds"), and the audit's own fixture S3a, which IS a Rogue
--                  Assassination.
--   Combat         NO ROW. The class's only pack (rogue-combat.dps) is the
--                  sword-and-dagger build and this card has no ruling that
--                  narrows it: a dagger that loses to a sword on DPS still
--                  loses for a Combat rogue. That absence is what makes the rule
--                  per-spec rather than per-class, and the battery pins it as a
--                  contrast case.
--   Subtlety       NO ROW. The corpus carries no ruling for it and inventing one
--                  would be the same second-taxonomy defect wearing a different
--                  hat — a claim no source makes. Called out as a known
--                  limitation in the card's report rather than guessed at.
--
-- FAIL-CLOSED, exactly like shieldPolicy: an unsubstantiated read (a levelling
-- rogue whose client returns the class name, or no name at all) resolves NO
-- policy, so no wieldability claim is made and the row keeps the basis it
-- already had.
Verdict.WEAPON_FAMILY_POLICY = {
	ROGUE = {
		-- THE KEY IS THE FOLDED ROLE WORD, not the client literal: on the WEAPON
		-- path `spec.role` is the word the ORDERS table and the WEIGHTS layer both
		-- key this class on ("melee" — Weights.lua's ROGUE.melee is the class's
		-- only pack), and `spec.clientRole` is the separate client literal
		-- ("DAMAGER"). Using the same word the weight pack uses keeps ONE
		-- vocabulary for "which rogue build is this" instead of a third one.
		-- (OFF_HAND_BUCKETS is keyed on the client literal because its caller,
		-- readOffHandSpec, hands over `si.role`; the two tables answer different
		-- questions and each is keyed by the word its own caller carries.)
		melee = { byName = {
			-- The client's own localized spec name, matched as a substring,
			-- case-insensitively — the §3 rule, borrowed whole.
			assassination = { dagger = true },
		} },
	},
}

-- The family set a resolved spec uses, or nil when no policy applies.
-- nil is the ORDINARY answer for every class except the ruled rogue spec, so
-- every unruled row keeps its shipped basis byte-for-byte.
function Verdict.weaponFamilies(spec)
	if type(spec) ~= "table" then return nil end
	local token, role = spec.class, spec.role
	if type(token) ~= "string" or type(role) ~= "string" then return nil end
	local entry = Verdict.WEAPON_FAMILY_POLICY[token]
	local bucket = type(entry) == "table" and entry[role] or nil
	if type(bucket) ~= "table" then return nil end
	-- A spec-specific row is authoritative only when the read IS a real spec
	-- (defect 1, t_548f0341: at level 22 the client returns the class name).
	if not Verdict.substantiated(spec) then return nil end
	if bucket.byName then
		local name = type(spec.name) == "string" and spec.name:lower() or nil
		if name == nil then return nil end
		for needle, set in pairs(bucket.byName) do
			if name:find(needle, 1, true) then return set end
		end
		return nil
	end
	return bucket
end

-- Is this weapon family one the resolved spec uses?
--   true  — yes.
--   false — no: the fact that decides the pair BEFORE the comparator.
--   nil   — no policy resolved, or no family readable: the caller makes NO
--           claim either way (an absent policy must never widen or narrow a row
--           it does not govern).
function Verdict.weaponUsableBySpec(family, spec)
	local set = Verdict.weaponFamilies(spec)
	if set == nil then return nil end
	if type(family) ~= "string" then return nil end
	return set[family] == true
end

-- The two rulings in the PLAYER's words. ONE place, so the ledger and the tests
-- read the same sentence the tip shows. `spec.name` is the client's own
-- localized string, never a hardcoded English spec name.
function Verdict.weaponWieldReason(kind, family, wornFamily, spec)
	local name = "this spec"
	if type(spec) == "table" and type(spec.name) == "string" and spec.name ~= "" then
		name = spec.name
	end
	if kind == "refuse" then
		return "not judged: a " .. tostring(family) .. " is not a weapon " .. name .. " uses"
	end
	return "upgrade: " .. name .. " uses a " .. tostring(family)
		.. ", and your " .. tostring(wornFamily) .. " cannot serve this spec"
end

-- Does this character's OFF HAND hold a WEAPON (a dual-wielder's slot)?
--
-- A CLASS capability, like shieldCapable, not a spec policy — and deliberately
-- WITHOUT a substantiated guard: a level-22 rogue with no spec still dual-wields,
-- and the sentence this answers ("the off hand holds an off-hand weapon", the
-- rogue's own comment in OFF_HAND_BUCKETS since Tier B) was always a class fact.
function Verdict.offHandHoldsWeapon(spec)
	if type(spec) ~= "table" or type(spec.class) ~= "string" then return false end
	local entry = Verdict.OFF_HAND_BUCKETS[spec.class]
	if type(entry) ~= "table" or type(entry.roles) ~= "table" then return false end
	return entry.roles.offHandWeapon == true
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
--     mage and the rogue exactly as it holds for the warrior (the implementer's build
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
	-- era (review §3: there is no proficiency API to ask, so the class table IS
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
	-- must be present: a nil spec (the client read failed — review §3 fail-closed)
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
	--
	-- CARD t_1677cd39 AMENDS THAT REASON for the one candidate the sentence
	-- contradicts. "The off hand is out of scope for ROGUE" is right about a
	-- SHIELD and wrong about an OFF-HAND WEAPON: the rogue's slot is a weapon
	-- slot, and refusing the item the slot exists for is the audit's I3b. So G2
	-- keeps its meaning for every candidate except the class's actual off-hand
	-- content, which is then judged on the weapon comparator like-for-like. The
	-- §7 guarantee is untouched: G0 (a two-hander in the main hand) still closes
	-- the slot first, G1 still refuses a shield the class cannot wear, G4 still
	-- refuses a worn item of a different off-hand class, and no path here can
	-- emit UPGRADE on its own — it only declines to decline.
	if bucket == "irrelevant" then
		local slotWeapon = Verdict.OFF_HAND_WEAPON_TOKENS[candLoc] == true
			and Verdict.offHandHoldsWeapon(spec)
		if not slotWeapon then return REASON.G2 end
	end

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
-- ⚠ THE RULING BELOW WAS SUPERSEDED ON 2026-10-13 (card t_984bc8ac). Kept,
-- not deleted, so the history stays legible:
--
--   RULED (2026-10-04), the owner: "Read the numbers. Order by prose. No stat
--   weight anywhere. … No per-stat multiplier is used, invented, hard-coded or
--   imported (AC-G)." He SUPERSEDED it on 2026-10-13: "Supersede. Ship card 2
--   to your spec." Per-class/spec weights now ship (Weights.lua), and the
--   ARMOUR/stat comparator consults them in its trade-off arm — see the
--   weighted resolution layer above.
--
-- WHAT THE SUPERSEDE DOES NOT CHANGE, which is why the ruling is quoted here
-- inside the WEAPON block: a weapon is still judged on the DPS the CLIENT
-- PRINTS. The damage range, the speed and the DPS are values the CLIENT
-- PRINTS on the item's own tooltip — read them, do the arithmetic the client
-- already shows, and compare. The weighted layer is reached from
-- Verdict.evaluate's STAT arm only: no weapon verdict passes through it, and
-- no per-stat weight is applied to a weapon (AC-G). The one place a
-- class-specific rule appears is W1, and it is a boolean MANDATE (this spec is
-- built around a shield), not a weight.
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

-- ═══════════════════════════════════════════════════════════════════════════
-- THE DAMAGE-RANGE GRAMMAR — one definition, two spellings (card t_d5c915f2)
--
-- A weapon's printed damage line is
--     <min> - <max> [<school>] Damage
-- ("12 - 22 Arcane Damage", "19 - 36 Damage") and the school word is OPTIONAL:
-- a physical weapon prints none, a wand or a staff prints the school of its
-- damage. The owner's own hover (a Lesser Magic Wand over a Novice's Practice
-- Wand) showed why the two halves of this reader have to agree: parseWeaponLine
-- read the range and the speed out of "12 - 22 Arcane Damage  Speed 1.50"
-- correctly, but isWeaponChrome — the ONE test that may drop a line — knew only
-- the school-LESS spelling, so the line stayed in the stat list, nothing could
-- classify it, and the pair read UNKNOWN with the numbers already in hand.
--
-- So the grammar is declared HERE, once, in the two spellings the Lua pattern
-- engine needs: `read` captures the two numbers, `bare` is the same shape
-- without captures for stripping. The SCHOOLS are DATA: a new school is one
-- line in the table below, never a second pattern somewhere else.
-- parseWeaponLine READS through `read`; stripWeaponChrome STRIPS through `bare`
-- and WEAPON_DAMAGE_SCHOOLS. The reader and the stripper cannot drift apart
-- again, because there is one grammar and one school list between them.
-- ═══════════════════════════════════════════════════════════════════════════
local WEAPON_RANGE = {
	read = "(%d+)%s*%-%s*(%d+)",   -- low, high
	bare = "%d+%s*%-%s*%d+",       -- the same shape, no captures
}

-- The schools a damage range — or the parenthesised damage-per-second line — can
-- name, lower-case because every strip runs on a lower-cased line. "physical"
-- is in the list for the spelling that names the physical school explicitly
-- instead of printing none. An UNKNOWN school word is deliberately NOT chrome:
-- the line then stays in the stat list and the pair fails closed, which is the
-- honest answer for a school this reader has never been shown.
local WEAPON_DAMAGE_SCHOOLS = {
	"arcane", "fire", "frost", "shadow", "nature", "holy", "physical",
}

-- The parenthesised damage-per-second shape ,  the school-less spelling every
-- client prints ("(11.3 damage per second)") and the school-named variant some
-- clients print ("(11.3 Arcane damage per second)"). `capture` selects the
-- READER's spelling (the number in a capture) or the STRIPPER's (no capture), so
-- ONE builder produces both halves and they cannot disagree about which DPS lines
-- exist. `school == ""` is the school-less spelling, with the looser `%s*` the
-- older pattern used before the word "damage".
local function weaponDpsPattern(school, capture)
	local num = capture and "([%d]+[%.%,]?%d*)" or "[%d]+[%.%,]?%d*"
	local mid = school == "" and "%s*damage" or "%s+" .. school .. "%s+damage"
	return "%(" .. num .. mid .. "%s+per%s+second%)"
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ON-HIT PROCS — a shape that is neither chrome nor a stat (card t_d5c915f2,
-- from the operator's own live test of a Fishing Pole)
--
--     Chance on hit: Sear the target with a vortex of blazing wind, dealing
--     39 to 59 Holystorm damage.
--
-- Three separate questions, and the answers are deliberately different:
--
--   1. Is it CHROME? No. It is not the weapon's own damage arithmetic, so the
--      total strip must keep it — dropping it would hide the very fact the
--      answer has to disclose.
--   2. Is it the weapon's DAMAGE? No, and this is a real defect the exclusion
--      below closes: a proc's damage range is a second range on the same
--      tooltip, and the reader used to take whichever range it saw first. The
--      dash spelling ("dealing 5 - 10 Fire damage") was read as the weapon's own
--      5-10 range, and with a "Speed" line present weaponDPS invented a 3.75 dps
--      the client never printed. The "to" spelling ("39 to 59") is invisible to
--      the reader for the same reason it is invisible to the strip: the range
--      grammar is a dash, and a proc range must never become the weapon's dps,
--      whichever way it is spelled. So a proc line is REFUSED by parseWeaponLine
--      outright, in both spellings — the fix is the refusal, not a second range
--      pattern.
--   3. Does it SUPPRESS the pair? That is the verdict-philosophy call, and it is
--      made on the weapon path only (compareWeapon): an on-hit effect carries no
--      comparable stat and no comparable arithmetic, so it cannot be priced, and
--      refusing the whole weapon for it makes the advisor silent on every proc
--      weapon in the game. The pair is therefore judged on what IS comparable —
--      the printed damage arithmetic and the stat lines — and the proc is NAMED
--      as unpriced on the answer, which is the honest form of "we read it and
--      cannot price it". Armour rows keep today's doctrine untouched: this card
--      is the weapon pass.
--
-- The recogniser is the PREFIX, not the sentence: the wording after "Chance on
-- hit:" varies per item ("Sear the target ...", "to heal you", "to gain 20 attack
-- power") and no list of effect sentences survives contact with real data. An
-- optional "Equip:" lead-in is accepted because some clients print it that way.
local function weaponOnHitLine(line)
	if type(line) ~= "string" then return false end
	-- Colour escapes first: the tooltip's own read can carry them, and a
	-- coloured prefix must classify the same as a plain one.
	local low = line:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	low = low:gsub("^%s+", "")
	local rest = low:match("^equip:%s*(.*)$")
	if rest ~= nil then low = rest end
	return low:match("^chance on hit") ~= nil
end

-- ENCHANTS — named, never a blocker, never priced (card t_c65cc350)
--
--     Enchanted: Weapon Damage +5
--
-- The owner's weapon carries this line, and card t_fc11dd1c measured what it is
-- worth in the printed arithmetic: NOTHING. The live tooltip of that Wolfsbane
-- prints 69-105 / 25.6 with the enchant and the template's own 69-105 / 25.6
-- without it, and 25.6 is exactly (69+105)/2/3.40 — so the printed range EXCLUDES
-- the enchant, and the +5 is not stated by the client as a comparable number.
--
-- t_fc11dd1c therefore refused the pair and named the side. That measurement
-- STANDS; what the owner overturned on 2026-11-15 is its consequence:
--
--   "an enchant line is never a classification blocker and never priced. Judge
--    the items; name the enchant as present-but-unpriced, with the side that
--    carries it — the proc doctrine, applied to enchants. It comes out of the
--    stat list like chrome and into the disclosure like a proc."
--
-- The enchant sat on the owner's EQUIPPED weapon, so failing closed meant every
-- main-hand comparison on that character refused and the advisor went silent on
-- its primary slot. So, exactly as for an on-hit proc:
--
--   1. Is it CHROME? No — `isWeaponChrome` is NOT widened, and its totality rule
--      is untouched. This is its OWN recogniser; the enchant is removed from the
--      stat side by weaponDisclosureLines below, beside the proc, not by the
--      chrome strip.
--   2. Is it the weapon's ARITHMETIC? No. `+5 / speed` is computable, and that is
--      precisely why it is refused: the ruling is that an enchant is never
--      priced, because the printed range excludes it and adding a contribution
--      the client did not print would invent a comparable number. parseWeaponLine
--      refuses the line outright, so a payload spelled like a range
--      ("Enchanted: 5 - 10 Damage") can never become the weapon's range or dps.
--   3. Is it a STAT? No. The worn side's additive enchant fold (t_ea70928d) is
--      the ARMOUR rule and stays where it is; on the weapon path the line is out
--      of the side the parse judges, so it can neither be folded into the score
--      nor reach the suppression channel.
--   4. Does it SUPPRESS the pair? No. It is NAMED on the answer, with the side
--      that carries it — "present but unpriced", the honest form of "we read it
--      and cannot price it", and the same shape as the on-hit clause.
--
-- The recogniser is the PREFIX, like the proc's: what follows "Enchanted:" varies
-- per enchant (a stat, a weapon damage, a spell power) and no list of payloads
-- survives contact with real data. Only the prefix is contractual; the payload is
-- never read, which is what "never priced" means in one line of code.
local function weaponEnchantLine(line)
	if type(line) ~= "string" then return false end
	-- Colour escapes and case are transparent, exactly as in the proc recogniser:
	-- the tooltip's own read can carry "|cff00ff00Enchanted: ...|r".
	local low = line:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	low = low:gsub("^%s+", "")
	return low:match("^enchanted%s*:") ~= nil
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
	-- An ON-HIT PROC line is never the weapon's own damage arithmetic, in either
	-- range spelling (see the block above): refusing it here is what stops a
	-- proc's "dealing 5 - 10 Fire damage" from becoming the weapon's dps.
	if weaponOnHitLine(line) then return nil end
	-- An ENCHANT line never is either (card t_c65cc350): "+5 / speed" would be
	-- computable, and that is exactly why the ruling forbids it — the printed
	-- range excludes the enchant, so a contribution added here would be a number
	-- the client never stated. Refusing the line also means a payload spelled
	-- like a range ("Enchanted: 5 - 10 Damage") cannot arm a weapon with a range
	-- and a dps it does not have.
	if weaponEnchantLine(line) then return nil end
	-- Normalise the dash characters to the ASCII hyphen BEFORE matching.
	-- patterns match BYTES, so a character class cannot hold the multi-byte
	-- UTF-8 en-dash (E2 80 93) / em-dash (E2 80 94) as a single element — the
	-- class would match one byte at a time and the range match would fail.
	-- Rewriting the two sequences explicitly is what makes AC-B's "three dash
	-- characters" fixture pass on all three.
	local trimmed = line:gsub("\226\128\147", "-"):gsub("\226\128\148", "-")
		:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" then return nil end
	local out = nil

	-- Damage RANGE: "1 - 3 Damage", "12 - 22 Arcane Damage" (dashes now
	-- normalised to '-'). Read through the ONE grammar declared above: the
	-- pattern anchors on the two numbers and a dash, so the optional school
	-- word between them and the word "damage" changes nothing here — and it is
	-- the same shape stripWeaponChrome removes from the stat side, which is what
	-- keeps the reader and the stripper from drifting apart (card t_d5c915f2).
	local lo, hi = trimmed:match(WEAPON_RANGE.read)
	if lo and hi then
		local a, b = tonumber(lo), tonumber(hi)
		if a and b then
			if a > b then a, b = b, a end   -- low<->high, tolerate reversed input
			out = out or {}
			out.minDamage, out.maxDamage = a, b
		end
	end

	-- SPEED: "Speed 1.90". The 0.5–10 window is a parse disambiguator,
	-- not a scoring weight: Classic weapon tooltips print 1.00–4.00, and
	-- a number outside that window is not a weapon speed. Read the number
	-- after the word "speed"; if the line is the "Speed" word on the left
	-- column with the value on the right (the reader joins columns), the
	-- search still finds it.
	local sp = trimmed:lower():match("speed%s*:?%s*([%d]+[%.%,]?%d*)")
	if sp then
		local v = tonumber((sp:gsub(",", ".")))
		if v and v >= 0.5 and v <= 10 then
			out = out or {}
			out.speed = v
		end
	end

	-- Parenthesised DPS: "(1.05 damage per second)", and the school-named
	-- spelling through the same builder the strip uses (card t_d5c915f2).
	local lowTrim = trimmed:lower()
	local dps = lowTrim:match(weaponDpsPattern("", true))
	if not dps then
		for _, school in ipairs(WEAPON_DAMAGE_SCHOOLS) do
			dps = lowTrim:match(weaponDpsPattern(school, true))
			if dps then break end
		end
	end
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
-- rule, EQUAL is never an upgrade). Returns verdict, reason, tie, where `tie`
-- is the branch it took ("more" | "less" | "equal" | "fills" |
-- "unknown-candidate" | "unknown-worn"). `tie` exists so a caller can react to
-- WHICH claim was made without matching on the player-facing sentence: the
-- weapon path's equal-claim gate (card t_ee04ad6d) is the one caller that does,
-- and a reason string is for the player, not a control-flow token.
--
-- `wornSlotFilled` (the gate round 1, defect D1) disambiguates the two causes of
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
-- `_spec` (card t_ce1c4a4f, A4) is the row's spec, and it is NOT read here: this
-- comparator decides on two sets of printed numbers, and a situation cannot
-- change what 25.6 vs 24.1 dps means. It rides along so the weapon-dps path does
-- not LOSE the spec at its last seam — the same rule that keeps `cmpSpec` whole
-- above — and so a future arbitration on this path receives a spec that already
-- carries the context instead of one that silently defaults. The leading
-- underscore is the luacheck-visible statement that it is deliberately unread.
local function compareDPS(candNumbers, wornNumbers, wornSlotFilled, _spec)
	local c = weaponDPS(candNumbers)
	local w = weaponDPS(wornNumbers)
	if c == nil then
		return "UNKNOWN", "cannot read the weapon's damage-per-second", "unknown-candidate"
	end
	if w == nil then
		if wornSlotFilled or (type(wornNumbers) == "table" and next(wornNumbers) ~= nil) then
			return "UNKNOWN", "cannot read the worn weapon's damage-per-second", "unknown-worn"
		end
		return "UPGRADE", "upgrade: fills the weapon slot", "fills"
	end
	if c > w then
		return "UPGRADE", ("upgrade: more weapon damage per second (%.2f vs %.2f)"):format(c, w), "more"
	elseif c < w then
		return "NOT_UPGRADE", ("less weapon damage per second (%.2f vs %.2f)"):format(c, w), "less"
	end
	return "NOT_UPGRADE", ("equal weapon damage per second (%.2f)"):format(c), "equal"
end

-- (card t_d5c915f2) THE EQUAL CLAIM ON THE SPELL-LED FALL-THROUGHS.
--
-- The melee branch of compareWeapon has refused to claim "equal weapon damage per
-- second" across a measurable Hit or Crit gap since card t_ee04ad6d, through
-- Verdict.beyondResolution. The two SPELL-led fall-throughs did not: when the
-- stats are level on the role's own order (or the worn weapon carries no stat at
-- all) and the candidate's only remaining difference is a word that order does
-- not carry, compareDPS answered alone — and its "equal" branch is a confident
-- claim about two weapons, one of which can be measurably better on Hit or Crit.
-- Card t_7ddbb60a found it on PR #75; it is absorbed here because it is the same
-- question the wand defect asked: what does a weapon's tooltip actually let you
-- compare?
--
-- SAME ONE EPSILON, NO SECOND THRESHOLD: this spends Verdict.beyondResolution and
-- Verdict.equalClaimReason — the predicate and the sentence the melee branch
-- already uses — so the step is still levelWithinResolution's 0.7 / 0.5 rating
-- and a sub-step difference still reads equal. It takes the parsed stat tables
-- the caller already has (they are parsed on every stat-led row), so it adds no
-- parse to the hover path.
--
-- The melee branch keeps its own inline block: card t_ee04ad6d's mutation leg
-- pins that block's exact source, and it spends the same two public functions,
-- so the rule has one definition and two call sites rather than two rules.
local function equalClaimOnStats(verdict, reason, tie, candStats, eqStats, spec)
	if tie ~= "equal" then return verdict, reason end
	local hidden = Verdict.beyondResolution(candStats, eqStats)
	if hidden ~= nil then return "UNKNOWN", Verdict.equalClaimReason(hidden) end
	-- ── AND THEN THE PRICED WORDS (card t_33dd248c, the DD-2 re-cut) ──────────
	-- The refusal above is card t_d5c915f2's, and it keeps PRIORITY exactly as
	-- merged: a gap the tooltip can measure but the basis in force cannot PLACE
	-- (Hit, Crit) still declines and names the word. It is not widened here.
	--
	-- What it does not cover is a word the pair's OWN PACK PRICES. DD-2
	-- (card t_4e1e1b1d) gave Healing and the six school powers words, and
	-- t_8575389a gave the damage half of the combined sentence its own word, so
	-- an "of Healing" weapon now parses to Healing 34 + SpellDamage 11 instead of
	-- suppressing the item. Those words are outside every class ORDER, so the
	-- dominance walk above could not see them and the row fell through to the
	-- DPS tie-break — where two weapons that tie on damage per second were
	-- called "equal weapon damage per second" while one of them carried +34
	-- Healing. That equality is FALSE, and it is the same defect class
	-- t_d5c915f2 closed for Hit/Crit, one word family further along.
	--
	-- So the pair goes to the ONE weighted layer `Verdict.evaluate` already
	-- spends (weightedResolution): the pack decides, or nothing does. No second
	-- threshold, no second price table, no new word list — a word no table
	-- prices (SpellDamage has no weight key by the owner's ruling) contributes 0
	-- and leaves the equal claim standing, which is what AC-E of t_8575389a
	-- already requires of a pack that prices a word at 0.
	local pv, pr = weightedResolution(candStats, eqStats, spec)
	if pv ~= nil then return pv, pr end
	return verdict, reason
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
-- (The role-aware side of Tier C — Verdict.weaponStatLed / compareWeapon and the
-- stat-side view Verdict.weaponStatLines — is defined below, beside the rule it
-- implements. Those two are set as function FIELDS on the table at their own
-- definition site; nothing here reads a local declared later in this chunk.)
-- ───────────────────────────────────────────────────────────────────────────
--
-- THE DEFECT (found by the owner on his live priest, 2026-10-13). His hover:
--
--   Touchstone: UPGRADE — more weapon damage per second (5.90 vs 5.80)
--   -2 Int, -4 Spell Power, +1 Str vs Makeshift Stormcaller
--
-- A main-hand mace carrying no caster stat was called an UPGRADE over a staff
-- with +2 Intellect and +4 spell damage, on 0.10 weapon DPS. `compareDPS` above
-- takes no role and no stats and cannot: it reads two DPS numbers and nothing
-- else. The stats were PARSED (they are in the delta line) and did not
-- participate in the verdict. For a caster the weapon is a STAT STICK and
-- tooltip DPS is close to irrelevant, so the verdict was simply decided on the
-- wrong basis.
--
-- THE RULE (the card's, and why it is not a weighted sum):
--   * a MELEE role keeps DPS as the basis — what a warrior is told does not
--     change, byte-for-byte, reason string included (AC-B);
--   * a SPELL role is judged on the CASTER STATS by the SAME stat comparison
--     the armour path already uses (dominance over the relevance set, then the
--     weighted layer), so "DPS must not outvote a real caster-stat difference"
--     holds absolutely — DPS is not an input at all;
--   * DPS is kept ONLY as the TIE-BREAK: when the two weapons' stats are level
--     on every term (or neither weapon carries one), the stats cannot decide and
--     today's DPS comparator answers, with today's exact reason string.
--
-- Option (b) of the card — "DPS kept as a minor term that cannot overturn a
-- caster-stat advantage" — is what this is, implemented as an exact
-- fall-through rather than a weighted sum. Why not a weighted sum: it would
-- need a DPS<->stat EXCHANGE RATE and a second threshold constant, and there is
-- no sourced rate between one point of weapon DPS and one point of Intellect on
-- this build. AC-H forbids adding a second threshold constant without reporting
-- first; a fall-through adds none, invents no rate, and leaves every DPS-worded
-- reason a melee row (or a stats-level spell row) sees exactly as it is today.
--
-- SPELL POWER WAS NOT A TERM when this card shipped — deliberately. The card
-- names "Intellect / Spirit / spell power" as the caster's stats and then
-- requires "the same stat comparison the armour path already uses (and
-- therefore the weights)". That vocabulary was then the seven words
-- Weights.lua prices (WEIGHT_KEYS: STR, AGI, STA, INT, SPI, ARMOR, BLOCK);
-- spell power was NOT one of them, and parseLine_'s own ruling above said it
-- in terms: "Spell power does not decide." A pair whose only difference is
-- spell power therefore had no stat term to decide on and fell through to the
-- DPS tie-break. Making spell power a NEW deciding term would have changed the
-- shared stat comparator, which that card may not do (AC-G).
-- REPORTED rather than hidden: the card's changed-verdict doc carries it.
--
-- ⚠ SUPERSEDED LATER by the owner's ruling card t_b7cd07e1 ("Spell power gets
-- a weight from the packs"): SPOW then became the eighth word of WEIGHT_KEYS
-- (the card t_795eee9e extension that moved it to last — behind the ten words
-- that card added — does not change what this paragraph reports: on THIS
-- weapon path spell power is STILL in no class order, so it still never names
-- the ordinal terms, and the fall-through to the DPS tie-break is intact).
-- What that does, and does not change, on THIS weapon path: a pair whose only
-- difference is spell power is STILL level on the role's order words (spell
-- power is in no class order) and still falls through to the DPS tie-break;
-- a pair that is an ordinal trade-off now carries the SPOW term in the
-- weighted layer, because this branch ends in Verdict.evaluate. The
-- t_b7cd07e1 sweep (shape 17 of weights_changed_verdicts.js) measures that
-- movement, and its owner's pinned pair above is a DOMINATED row — worse on
-- Intellect, never better on any relevance word — so it stays NOT_UPGRADE
-- regardless of the new word.
--
-- WHERE THE ROLE COMES FROM. `spec.role` is the ONE role resolution point
-- (ChestAdvisor.lua `resolvedRole` -> `buildSpec`): the folded order word
-- ("melee" | "spell") for a hybrid that resolved, the CLASS TOKEN for a pure
-- class (a pure class ignores the role argument), and nil for a hybrid that
-- resolved nothing. `Verdict.weaponStatLed` reads the ORDERS table by the same
-- rule `classRoleOrder` applies, so a pure caster class (MAGE / PRIEST /
-- WARLOCK, whose single order is keyed `spell`) is stat-led with no player
-- input, and a hybrid is stat-led only when its role RESOLVED to `spell`. An
-- unresolved role is today's behaviour (AC-E): a missing role never widens a
-- verdict, it only leaves the row on the basis it already had.
--
-- THE W0 MIRROR (reported in the doc, NOT ruled here). The owner's candidate is
-- 1H against a worn 2H, so wearing it FREES slot 17 — the mirror of W0
-- (candidate 2H, off-hand occupied -> UNKNOWN). NOTHING in this file or in
-- ChestAdvisor.lua accounts for the freed slot in either role: the comparison is
-- candidate versus worn main hand, and the off-hand's contribution is not an
-- input. The scoping doc this file cites (t_97a8ea03 §5.1) is NOT present in
-- docs/ and no other doc rules this direction. So the mirror stays as it is,
-- unchanged by this card, and is written down rather than invented.

-- Remove every damage-chrome shape from an already lower-cased and
-- dash-normalised line, leaving whatever else the line carried. This is the ONLY
-- stripper: isWeaponChrome decides on its answer, and it strips through the same
-- WEAPON_RANGE / WEAPON_DAMAGE_SCHOOLS grammar parseWeaponLine reads through.
--
-- The school loop is the card's fix (t_d5c915f2). One gsub per school entry is
-- deliberate: Lua's `|` alternates WHOLE patterns, not sub-expressions, so a
-- single pattern cannot ask "one of these seven words" — and spelling the seven
-- schools inline would be a second, silent copy of the list above. The loop
-- spends the list itself, so adding a school is still one line, in one place.
local function stripWeaponChrome(low)
	local rest = low:gsub(WEAPON_RANGE.bare .. "%s+damage", " ")
	for _, school in ipairs(WEAPON_DAMAGE_SCHOOLS) do
		rest = rest:gsub(WEAPON_RANGE.bare .. "%s+" .. school .. "%s+damage", " ")
		-- The parenthesised DPS line can print the school too:
		-- "(11.3 Arcane damage per second)". Same builder as the reader's.
		rest = rest:gsub(weaponDpsPattern(school, false), " ")
	end
	rest = rest:gsub(weaponDpsPattern("", false), " ")
	rest = rest:gsub("speed%s*:?%s*[%d]+[%.%,]?%d*", " ")
	return rest:gsub("^%s+", ""):gsub("%s+$", "")
end

-- Is this ONE tooltip line nothing but the weapon's own damage arithmetic
-- ("19 - 36 Damage", "19 - 36 Damage  Speed 2.50", "12 - 22 Arcane Damage
-- Speed 1.50", "(11.0 damage per second)", "Speed 2.50")? This is the ONLY test
-- that authorises dropping a line before the stat parse, and it is TOTAL: the
-- damage / speed / DPS shapes are removed from the whole line and the line is
-- chrome only when nothing but whitespace is left. A line that also carries a
-- stat (the hypothetical column join "19 - 36 Damage  Speed 2.50  +5 Intellect")
-- leaves "+5 intellect" behind, so it is NOT chrome — it stays in the list and
-- suppresses exactly as it does today. The strip therefore cannot hide a stat:
-- an unplaceable line that is not chrome still reads as UNKNOWN (fail-closed,
-- unchanged).
--
-- A SCHOOL word is chrome, not a stat (card t_d5c915f2): "12 - 22 Arcane Damage"
-- is the same arithmetic as "12 - 22 Damage" with the school named, so it is
-- stripped — it is added to the STRIP, never to a blocklist of whole lines. A
-- school this module has not been shown is left in place on purpose, which keeps
-- the line unclassifiable and the pair fail-closed.
local function isWeaponChrome(line)
	if type(line) ~= "string" then return false end
	-- The dashes are normalised exactly as parseWeaponLine above does: Lua
	-- patterns match BYTES, so the multi-byte UTF-8 en/em dash cannot sit in a
	-- character class as a single element.
	local low = line:gsub("\226\128\147", "-"):gsub("\226\128\148", "-")
	low = low:lower():gsub("^%s+", ""):gsub("%s+$", "")
	if low == "" then return false end
	return stripWeaponChrome(low) == ""
end

-- The stat-side view of a weapon's line list: the same list minus its own
-- damage chrome. A COPY — the caller's table is the tooltip's own read and is
-- never mutated (the row stores it, and the tooltip's delta line parses it
-- again). A non-table (nil, a string, a failed read) passes straight through, so
-- "no read" stays "no read".
local function weaponStatLines(lines)
	if type(lines) ~= "table" then return lines end
	local kept = {}
	for _, line in ipairs(lines) do
		if not isWeaponChrome(line) then kept[#kept + 1] = line end
	end
	return kept
end
-- Exposed for the same reason weaponNumbers/weaponDPS above are: the tests drive
-- the shipped strip rather than a re-implementation of it (and can therefore pin
-- that a line carrying a stat is never dropped).
Verdict.weaponStatLines = weaponStatLines
-- The school list the strip spends is DATA; a test that enumerates it enumerates
-- the SHIPPED table rather than a copy of it, so a new school cannot pass a
-- fixture that never asked the module about it (card t_d5c915f2).
Verdict.weaponDamageSchools = WEAPON_DAMAGE_SCHOOLS
-- The on-hit recogniser, exposed so the fixture table drives the shipped
-- predicate rather than a copy of the prefix (card t_d5c915f2).
Verdict.weaponOnHit = weaponOnHitLine
-- The enchant recogniser, exposed for the same reason (card t_c65cc350).
Verdict.weaponEnchant = weaponEnchantLine

-- The stat-side view with the NAMED-NOT-PRICED lines removed — the on-hit proc
-- (card t_d5c915f2) and the enchant (card t_c65cc350). The weapon path judges on
-- what is comparable and NAMES what it cannot price, so neither line may reach the
-- parse's suppression channel; on the WORN side an enchant would otherwise be
-- FOLDED INTO THE SCORE by the armour rule below, which is the one thing the
-- owner's ruling forbids outright. A COPY, like weaponStatLines above, and the
-- same non-table passthrough.
--
-- One function, two recognisers: the two shapes share the one property that
-- matters here (named on the answer, never spent on it), and a second parallel
-- strip would be a second place for a caller to forget one of them. Which
-- recogniser matched is decided by the clause builder in compareWeapon, not here.
local function weaponDisclosureLines(lines)
	if type(lines) ~= "table" then return lines end
	local kept = {}
	for _, line in ipairs(lines) do
		if not weaponOnHitLine(line) and not weaponEnchantLine(line) then
			kept[#kept + 1] = line
		end
	end
	return kept
end
Verdict.weaponDisclosureLines = weaponDisclosureLines

-- Is this character's weapon judged as a STAT item, or on its DPS?
--
-- Answered from the ORDERS table by the same rule classRoleOrder applies (a pure
-- class ignores the role argument; a hybrid requires a resolved one), and from
-- the resolved role word alone:
--   * CLASS unknown, or not in ORDERS -> false (today's DPS basis);
--   * a HYBRID (more than one order)  -> stat-led iff role == "spell", so
--     PALADIN / SHAMAN / DRUID only when the folded role resolved to `spell`,
--     and their melee rows — and their role-less rows — keep DPS;
--   * a HYBRID whose client literal is TANK and which HAS a tank weight pack
--     (card t_6c3f414a, DD-3) -> ALSO stat-led, because that row is judged on
--     the TANK role's terms (tankWeaponOrder below) instead of on DPS. This is
--     the feral BEAR: a druid's TANK folds to `melee` for the ORDER (so
--     Druid can reach DRUID.tank at all), and without this clause the bear's
--     weapon would be compared on DPS alone while its own pack prices
--     Strength, Agility, Stamina, Defense, Dodge and health-regen. Every other
--     class is unchanged: a PURE class never reaches this clause (its role
--     argument is ignored), a PALADIN tank is already stat-led through
--     `spell`, and a class with no TANK alias and no tank pack (SHAMAN) stays
--     on DPS — the clause is `tankWeaponOrder(...) ~= nil`, not `TANK == role`.
--     The third argument is OPTIONAL: called with two arguments the function
--     answers exactly what it answered before DD-3, which is what keeps every
--     existing caller and assertion byte-identical.
--   * a PURE class (exactly one order) -> stat-led iff its own order is the
--     `spell` one: MAGE, PRIEST, WARLOCK. A recorded role cannot override it,
--     exactly as it cannot change a pure class's order.
-- No class token is spelled here and no second table is introduced: this reads
-- the SAME Verdict.ORDERS the orders come from, so a class added there can never
-- be silently missing from this rule.
function Verdict.weaponStatLed(class, role, clientRole)
	if type(class) ~= "string" then return false end
	local orders = Verdict.ORDERS[class]
	if type(orders) ~= "table" then return false end
	local count, only = 0, nil
	for key in pairs(orders) do
		count = count + 1
		only = key
	end
	if count == 0 then return false end
	if count > 1 then
		if role == "spell" then return true end
		-- card t_6c3f414a: the TANK literal, and only where the class has
		-- DECLARED a tank path (a TANK alias folding to this very role) and a
		-- tank pack resolves for it. Both conditions matter: without the alias
		-- test a SHAMAN — hybrid, no ROLE_ALIAS entry, no tank pack — would go
		-- stat-led the moment the client said TANK, and tankWeaponOrder would
		-- hand it its own MELEE pack's words. Without the pack test the alias
		-- would be a promise no table keeps.
		if type(clientRole) ~= "string" or clientRole:upper() ~= "TANK" then
			return false
		end
		if Verdict.clientRoleWord(class, "TANK") ~= role then return false end
		return Verdict.tankWeaponOrder(class, role, clientRole) ~= nil
	end
	return only == "spell"
end

-- ---- The TANK role's terms on the WEAPON path (card t_4590ab7e, item 2) -----
-- WHY THIS EXISTS. `ROLE_ALIAS` folds the client's TANK word onto the caster word
-- `"spell"` so the ORDER lookup has a word to resolve: PALADIN has no `tank` key in
-- ORDERS, and retargeting the alias to "tank" would send that lookup to a key that
-- does not exist — a nil order, i.e. UNKNOWN for every Prot row. That fold is
-- correct for the ORDER and it is left EXACTLY as it is.
--
-- It is wrong for the WEAPON path. `compareWeapon`'s stat-led branch compares the
-- weapon on the ORDER's terms, so a Prot paladin's weapon was compared on the
-- CASTER order (Intellect > Stamina > Strength): a main hand carrying nothing but
-- +2 Intellect read "UPGRADE — upgrade: better on Intellect" for a Protection
-- paladin and NOT_UPGRADE for a Protection warrior. That is a caster's stat stick,
-- not a tank's weapon.
--
-- So the weapon path asks a different question and this function answers it: what
-- are the TERMS of the tank role? They are not invented — they are the stats the
-- character's OWN tank weight pack prices above zero, in the fixed WEIGHT_KEYS
-- order, with Armor and Block left OUT because those two are the tiebreak
-- everywhere and are never a term of the dominance proof (E2 / §4.1a). For the
-- shipped PALADIN.tank pack (STR 0.5, STA 1.0, ARMOR 0.35, BLOCK 0.35 —
-- paladin-prot.survival) that is exactly "Strength" then "Stamina". The pack is
-- DATA: if Intellect should ever count for a Prot paladin, the pack is edited and
-- this follows it. No second order table is spelled here.
--
-- After card t_795eee9e the tank vocabulary can also carry DEFENSE, DODGE and
-- PARRY (client keys ITEM_MOD_DEFENSE_SKILL_RATING, ITEM_MOD_DODGE_RATING and
-- ITEM_MOD_PARRY_RATING, all verified in the client inventory), and a pack that
-- prices them prices them BEHIND Block and AHEAD of SPOW in the WEIGHT_KEYS
-- order — so a prot warrior pack edited to price defenseRating would read
-- "Strength, Stamina, Defense", and this function already reports that term in
-- the right place with no further change.
--
-- nil — the caller keeps today's order, byte for byte — when the client named no
-- role, named one that is not TANK, the class is not a hybrid (a PURE class ignores
-- the role argument, exactly as classRoleOrder and weaponStatLed do, so a Warrior
-- tank is untouched), no tank pack resolves, or the pack prices no term at all.
-- Every one of those is a "the weights cannot speak" answer, and the ordinal path
-- keeps the row — the same fail-closed shape as a missing weights table (AC-E).
function Verdict.tankWeaponOrder(class, role, clientRole)
	if type(class) ~= "string" then return nil end
	if type(clientRole) ~= "string" or clientRole:upper() ~= "TANK" then return nil end
	if not isHybrid(class) then return nil end
	local weights = Verdict.weightsFor(class, role, clientRole)
	if weights == nil then return nil end
	local words = {}
	for _, k in ipairs(WEIGHT_KEYS) do
		if k ~= "ARMOR" and k ~= "BLOCK" then
			local w = rawget(weights, k)
			if type(w) == "number" and w > 0 then words[#words + 1] = WEIGHT_WORD[k] end
		end
	end
	if #words == 0 then return nil end
	return words
end

-- THE TIER C ENTRY POINT — one function for BOTH callers (the bag walk and the
-- quest-reward judgement), so the role-aware rule cannot exist on one surface
-- and not the other.
--
--   candLines / wornLines — the raw lines the caller already read (nil worn on
--                           an EMPTY slot);
--   wornSlotFilled        — the caller's own fact about the worn slot (D1);
--   spec                  — the character's resolved spec (class/role/order);
--   canUse                — the caller's eligibility answer. `true` by the time
--                           the shipped paths call this (they return first on
--                           anything else), and passed through rather than
--                           assumed: the eligibility gate is a HARD gate
--                           everywhere else in this file.
--   apiBySide             — OPTIONAL. The same { candidate = ..., worn = ... }
--                           client-read table Verdict.evaluate takes. nil (what
--                           both shipped callers pass today) leaves every branch
--                           byte-identical; when present, the stat-led branch
--                           reads the client's own stat words through
--                           apiSideResolve exactly as evaluate does, which is
--                           the only way a Dodge/Parry read (words the text
--                           reader cannot place on a weapon line) reaches the
--                           weapon path's two gates.
-- Returns verdict, reason — the same contract as compareDPS.
--
-- WEAPON_JUDGED (card t_fc11dd1c) — the verdict words this path emits as a
-- DECISION. Spelled ONCE, here, and read by `answer` below: an UNKNOWN is the one
-- word this path emits as a REFUSAL, and a refusal must not inherit a clause that
-- says "and here is what I judged it on". A new verdict word has to be added here
-- deliberately rather than getting the clause by default. TRADE_OFF is keyed by
-- its own value (spelled ONCE, at its definition above) so a re-spelling of that
-- literal cannot silently drop it from the set.
local WEAPON_JUDGED = { UPGRADE = true, NOT_UPGRADE = true, [TRADE_OFF] = true }

function Verdict.compareWeapon(candLines, wornLines, wornSlotFilled, spec, canUse, apiBySide, ctx, totals)
	local candNumbers = weaponNumbers(candLines)
	local wornNumbers = weaponNumbers(wornLines)

	-- (card t_d5c915f2, the operator's Fishing Pole) AN ON-HIT PROC IS NAMED, NOT
	-- REFUSED. A "Chance on hit:" effect is not comparable arithmetic and not a
	-- stat, so nothing on this path can price it — but refusing the weapon for it
	-- would make the advisor silent on every proc weapon in the game. The pair is
	-- judged on what IS comparable and the answer carries this clause, so the
	-- player is told the effect exists and was not priced. `answer` is the ONE
	-- place the clause is added: with no proc on either side it returns the
	-- verdict and reason untouched, which is why every existing weapon reason is
	-- byte-identical.
	--
	-- (card t_c65cc350) AN ENCHANT IS NAMED THE SAME WAY, and with its SIDE. The
	-- owner's ruling of 2026-11-15 supersedes t_fc11dd1c's fail-closed treatment
	-- for exactly this shape: an enchant is never a classification blocker and
	-- never priced, so it comes out of the stat side (weaponDisclosureLines) and
	-- into the disclosure like a proc — "present but unpriced, on the weapon that
	-- carries it". The SIDE is the one thing the enchant adds to the proc's
	-- clause, because an enchant belongs to one item and the player's next move
	-- depends on which: the weapon they are wearing, or the one under the cursor.
	--
	-- ONE CLAUSE, NEVER TWO. Both facts arrive in the same parenthetical, proc
	-- first and then the enchant, because the two are always about the same
	-- answer ("here is what I could not price") and two parentheticals on one
	-- sentence read as two separate remarks. Wording decided once, here, and
	-- pinned as an exact string in ChestAdvisor/tests/t_c65cc350.js.
	local seen = { onHit = false, enchant = { candidate = false, worn = false } }
	for _, side in ipairs({ { candLines, "candidate" }, { wornLines, "worn" } }) do
		local lines, which = side[1], side[2]
		if type(lines) == "table" then
			for _, line in ipairs(lines) do
				if weaponOnHitLine(line) then seen.onHit = true end
				if weaponEnchantLine(line) then seen.enchant[which] = true end
			end
		end
	end
	local disclosure = ""
	do
		local parts = {}
		if seen.onHit then parts[#parts + 1] = "an unpriced on-hit effect" end
		local e = seen.enchant
		if e.candidate and e.worn then
			parts[#parts + 1] = "an unpriced enchant on both items"
		elseif e.worn then
			parts[#parts + 1] = "an unpriced enchant on the equipped weapon"
		elseif e.candidate then
			parts[#parts + 1] = "an unpriced enchant on the hovered item"
		end
		if #parts > 0 then
			disclosure = " (judged, with " .. table.concat(parts, " and ") .. ")"
		end
	end
	-- (card t_1677cd39) The off-hand promotion note, filled in below (before any
	-- comparison is made) and spent by `answer` — declared HERE because `answer`
	-- is the ONE place a reason is finalised and Lua closures see only locals
	-- declared above them.
	local promotionNote = ""

	local function answer(v, r, d)
		-- (card t_fc11dd1c) ONLY A JUDGED VERDICT CARRIES THE CLAUSE. The note means
		-- "and here is what I judged it on", which is true of a decision and false
		-- of a refusal: the owner's first live hover printed
		--   cannot classify: Enchanted: Weapon Damage +5 (judged, with an unpriced
		--   on-hit effect)
		-- , a sentence that says "I could not judge this" and "here is what I
		-- judged it on" at once. The proc came from the worn weapon's own line and
		-- the refusal from the next unreadable one; the note must not survive the
		-- refusal. A judged pair is byte-identical to before this card.
		--
		-- (card t_1677cd39) The SAME rule governs the off-hand pair note, and it
		-- rides ahead of the proc clause because it is the more consequential
		-- fact: only a judged UPGRADE can carry it, and with no promotion in play
		-- the string is "" — the two lines below are then byte-for-byte the
		-- pre-card ones, which is what card t_fc11dd1c's mutation leg anchors on.
		--
		-- (card t_c65cc350) BOTH CLAUSES READ THE ONE VARIABLE. The proc-only
		-- note became `disclosure` (proc and/or enchant, ONE parenthetical), so
		-- the promotion line concatenates that instead of the removed local; with
		-- neither fact present it is "" and the bytes are the pre-card ones.
		if promotionNote ~= "" and tostring(v) == "UPGRADE" then
			return v, tostring(r or "") .. promotionNote .. disclosure, d
		end
		-- (card t_c65cc350) UNCHANGED RULE, ONE MORE CLAUSE IN IT: a refusal that
		-- carries an enchant — or both facts — still gets no clause at all.
		if disclosure == "" or not WEAPON_JUDGED[tostring(v)] then return v, r, d end
		return v, tostring(r or "") .. disclosure, d
	end

	-- ---- CARD t_1677cd39: A WEAPON THE SPEC CANNOT USE ----------------------
	--
	-- THE DECISION IS WIELDABILITY, AND IT COMES BEFORE THE COMPARATOR. The
	-- audit's S3a is the reason: a worn SWORD at 13.0 dps against a DAGGER at 7.2
	-- on a Rogue Assassination. No stat weighting can ever reach that verdict —
	-- the sword wins the DPS channel and the dagger is the weapon the spec
	-- actually uses — so the fact has to be settled before any number is
	-- compared, exactly as the card's §1 says.
	--
	-- Three answers, and no fourth:
	--   * no policy resolved (the ordinary case for every class but the ruled
	--     rogue spec) -> nothing here fires and the pair takes the basis it
	--     already had, byte-for-byte;
	--   * the candidate is not a weapon this spec uses -> REFUSE, naming the
	--     fact. Never "silently equal": the doctrine is that this addon does not
	--     claim a verdict over a comparison it did not make;
	--   * the candidate IS the spec's weapon and the WORN one is not -> the
	--     candidate wins AS THE SPEC'S WEAPON, and the reason says so in the
	--     player's own words (the spec name is the client's own localized
	--     string). Comparing the dagger's 7.2 dps to a sword the spec cannot use
	--     is not a comparison — it is the audit's defect.
	--
	-- An unreadable candidate family inside a resolved policy fails CLOSED: the
	-- spec's requirement is a claim about WHAT KIND of weapon this is, and a
	-- tooltip that does not say cannot support it. The worn side's family is
	-- only ever read to make the "your sword cannot serve this spec" claim, so an
	-- unreadable WORN family simply drops that claim and leaves the comparator's
	-- own answer in place.
	local candSlot, candFamily = Verdict.weaponType(candLines)
	local _, wornFamily = Verdict.weaponType(wornLines)
	local familySet = Verdict.weaponFamilies(spec)
	if familySet ~= nil then
		if candFamily == nil then
			return answer("UNKNOWN",
				"not judged: cannot tell what kind of weapon this is (its tooltip names no weapon type)")
		end
		if familySet[candFamily] ~= true then
			return answer("UNKNOWN",
				Verdict.weaponWieldReason("refuse", candFamily, wornFamily, spec))
		end
		if wornFamily ~= nil and familySet[wornFamily] ~= true then
			return answer("UPGRADE",
				Verdict.weaponWieldReason("serve", candFamily, wornFamily, spec))
		end
	end

	-- ---- CARD t_1677cd39: THE OFF-HAND PROMOTION ----------------------------
	--
	-- WHAT WAS WRONG. A one-hander candidate was compared to the worn MAIN HAND
	-- and nothing else, so the pair the player would actually end up wearing was
	-- never judged: equipping the candidate displaces the worn main hand into the
	-- off hand, which is a SECOND hand changing (audit fixture S3c).
	--
	-- WHAT IS JUDGED NOW. `ctx` (the caller's off-hand context) says whether slot
	-- 17 is filled and what it holds. When the candidate is a one-hander this spec
	-- can wear in either hand, the worn main hand is promoted into the off hand —
	-- and the pair is judged as a SET, on two channels that are never mixed:
	--   * the main channel is the comparison this function already makes;
	--   * the off channel is the PROMOTED WEAPON'S OWN numbers against the worn
	--     off-hand's own numbers (compareDPS on each weapon's own parse — never
	--     the main hand's dps borrowed for the off hand, which is the audit's I3b
	--     defect in its other form).
	-- The note is only added to a judged UPGRADE (the candidate has to win the
	-- main hand for anything to move), and the promotion is only claimed when the
	-- off channel does not LOSE: if the worn off hand is better than the worn main
	-- hand, nothing is displaced — the player keeps that off-hand weapon and the
	-- candidate is a plain main-hand swap, which is what the comparator already
	-- says. The engine must not name a pair it did not judge.
	--
	-- No `ctx` (every caller before this card) -> no promotion, no note, no
	-- change of any kind.
	local offHandRow = type(ctx) == "table" and ctx.offHand == true
	promotionNote = ""
	if type(ctx) == "table" and not offHandRow
		and (candSlot == "main hand" or candSlot == "one-hand")
		and Verdict.offHandHoldsWeapon(spec)
		and type(wornLines) == "table" then
		-- The weapon that would be promoted has to be one this spec uses: a dagger
		-- spec does not move a sword into its off hand.
		local promotedOk = (familySet == nil) or (wornFamily ~= nil and familySet[wornFamily] == true)
		-- AN EMPTY OFF HAND IS NOT A PROMOTION, and the note says nothing about it:
		-- nothing is displaced, the worn weapon simply stays equipped one slot
		-- over, and the comparator's own answer already covers it. The note's
		-- whole content is "a SECOND hand changes" — which is only true when the
		-- off hand is filled and the promoted weapon outranks what is in it. That
		-- is also what keeps every pre-card weapon row byte-identical (AC-B of
		-- card t_16448f75 pins exactly that class of row).
		if promotedOk and ctx.offFilled == true then
			local offNumbers = weaponNumbers(ctx.offLines)
			local offDpsRead = weaponDPS(offNumbers)
			local _, _, tie = compareDPS(wornNumbers, offNumbers, true, spec)
			if offDpsRead ~= nil and (tie == "more" or tie == "equal") then
				promotionNote = (" (judged as a pair: your equipped weapon moves to your "
					.. "off hand, ahead of the %.2f dps there)"):format(offDpsRead)
			end
		end
	end

	-- ── AN ORDER-ONLY PACK JUDGES A WEAPON ON ITS PUBLISHED TIERS ───────────
	-- (card t_24a4c8ea; re-cut twice, last for the 740f7d5 pin, where the anchor
	-- moved from `answer`'s tail — `onHitNote` became `disclosure` — to
	-- `local statLed`, so the branch still runs after the wieldability refusal.) A
	-- profile with `kind = "order"` and a `tiers` list — Retribution today —
	-- has no invented numeric weights: the published priority IS the source.
	-- It walks Weapon Skill, then Weapon DPS & Speed, then the rest, and the
	-- first tier whose sides differ decides. The DPS comparator below cannot
	-- see that: two weapons that tie on damage per second while one carries
	-- +12 Weapon Skill are called "equal weapon damage per second (10.00)",
	-- and Weapon Skill is the FIRST tier Wowhead publishes for the spec.
	--
	-- WHY THE GATES ARE REPEATED HERE. A non-stat-led class never reaches the
	-- stat-led branch below, so this branch must fail closed on its own terms.
	-- It spends the SAME predicates that branch spends, in the same order: the
	-- parse's unknown/proc words refuse BY NAME, an unpriced word refuses
	-- through Verdict.unpricedWord, and a difference on an unconfirmed unit
	-- refuses through Verdict.unconfirmedDifference. Nothing here is a second
	-- rule — this is the one place a weapon pair for an order-only pack is
	-- decided, so it carries the same refusals instead of skipping them.
	--
	-- The parse is upstream's own (chrome stripped by weaponStatLines, on-hit
	-- lines set aside by weaponDisclosureLines), and every answer travels through
	-- `answer` above, so a proc weapon keeps its clause here too. The DPS and
	-- speed the tooltip PRINTS are folded back in, because the tiers rank them
	-- (the printed number is the arithmetic; the parse keeps only stats).
	local orderProfile = type(spec) == "table" and Verdict.profileFor(spec) or nil
	if Verdict.isOrderProfile(orderProfile) then
		local api = type(apiBySide) == "table" and apiBySide or nil
		local candWords = api and select(1, apiSideResolve(rawget(api, "candidate"))) or nil
		local wornWords = api and select(1, apiSideResolve(rawget(api, "worn"))) or nil
		if wornLines == nil then
			-- The slot is empty: filling it is an upgrade, and a candidate the
			-- parse cannot place must not be waved in.
			local fillStats, fillProc, fillUnknown =
				parseSide(weaponDisclosureLines(weaponStatLines(candLines)), "candidate", candWords)
			local bad = fillUnknown or fillProc
			if bad ~= nil then
				return answer(cannotClassify("candidate", tostring(bad)))
			end
			local unpricedFill = Verdict.unpricedWord(fillStats)
			if unpricedFill ~= nil then
				return answer("UNKNOWN", Verdict.unpricedWordReason(unpricedFill))
			end
			return answer("UPGRADE", "upgrade: fills the weapon slot")
		end
		local tierCand, tierProc, tierUnknown =
			parseSide(weaponDisclosureLines(weaponStatLines(candLines)), "candidate", candWords)
		local tierEq, tierEqProc, tierEqUnknown =
			parseSide(weaponDisclosureLines(weaponStatLines(wornLines)), "worn", wornWords)
		local badCand = tierUnknown or tierProc
		local badEq = tierEqUnknown or tierEqProc
		if badCand ~= nil then
			return answer(cannotClassify("candidate", tostring(badCand)))
		end
		if badEq ~= nil then
			return answer(cannotClassify("worn", tostring(badEq)))
		end
		local unpriced = Verdict.unpricedWord(tierCand) or Verdict.unpricedWord(tierEq)
		if unpriced ~= nil then
			return answer("UNKNOWN", Verdict.unpricedWordReason(unpriced))
		end
		local unconfirmed = Verdict.unconfirmedDifference(tierCand, tierEq)
		if unconfirmed ~= nil then
			return answer("UNKNOWN", Verdict.unpricedWordReason(unconfirmed))
		end
		if type(candNumbers) == "table" then
			if candNumbers.dps then tierCand.WeaponDps = candNumbers.dps end
			if candNumbers.speed then tierCand.WeaponSpeed = candNumbers.speed end
		end
		if type(wornNumbers) == "table" then
			if wornNumbers.dps then tierEq.WeaponDps = wornNumbers.dps end
			if wornNumbers.speed then tierEq.WeaponSpeed = wornNumbers.speed end
		end
		local tv, tr, td = Verdict.orderVerdict(tierCand, tierEq, spec, nil, orderProfile)
		local av, ar = answer(tv, tr)
		return av, ar, td
	end
	local statLed = type(spec) == "table"
		and Verdict.weaponStatLed(spec.class, spec.role, spec.clientRole)
		and type(spec.order) == "table"
	if not statLed then
		-- EVERY other case — a melee role, a hybrid with no resolved role, an
		-- unknown class, a stat-led class whose order did not resolve, no spec at
		-- all — is today's comparator, byte-for-byte, reason string included.
		local verdict, reason, tie = compareDPS(candNumbers, wornNumbers, wornSlotFilled, spec)
		-- (card t_ee04ad6d) THE ONE EXCEPTION, and it is the claim this path
		-- cannot support: an "equal" on damage per second while the two sides
		-- differ MORE than the tooltip's own step on a word it can measure (Hit,
		-- Crit). The DPS numbers are level; the pair is not the same, and the
		-- basis in force cannot place the difference, so the row declines and
		-- NAMES the word instead of asserting sameness. The more/less branches
		-- are deliberately NOT gated: they claim an ordering on the DPS channel,
		-- which stays true, and widening this into "a melee weapon is judged on
		-- its stats" is the re-basing card t_16448f75 ruled out. The parse runs
		-- only on the equal branch, so every other weapon row costs exactly what
		-- it cost before this card.
		if tie == "equal" then
			-- (card t_c65cc350) the same view the judgement used: an enchant is not
			-- a word this pair can be equal on, so it must not reach this parse.
			-- (card t_9d718a77) AND THE PARSE'S SILENCE IS NOW HEARD. Until this
			-- card only the FIRST return was kept, so a digit-bearing line the
			-- parser could not place vanished from this branch entirely: both
			-- sides parsed to an empty table, beyondResolution found no gap
			-- between two empties, and a confident "equal weapon damage per
			-- second" went out over a stat line nothing had read (the measured
			-- matrix is under Verdict.STAT_TIP_SPELLINGS). The unread line is now
			-- the FIRST question asked, because the gap question rests on the
			-- read being complete: a pair with an unplaced line declines and
			-- names it, before any claim about what the placed lines say.
			local candStats, _, candUnknown =
				parseSide(weaponDisclosureLines(weaponStatLines(candLines)), "candidate", nil)
			local eqStats,   _, eqUnknown   =
				parseSide(weaponDisclosureLines(weaponStatLines(wornLines)), "worn",      nil)
			if candUnknown ~= nil then
				return "UNKNOWN", Verdict.unreadEqualReason(candUnknown, "candidate")
			end
			if eqUnknown ~= nil then
				return "UNKNOWN", Verdict.unreadEqualReason(eqUnknown, "worn")
			end
			local hidden = Verdict.beyondResolution(candStats, eqStats)
			if hidden ~= nil then
				return "UNKNOWN", Verdict.equalClaimReason(hidden)
			end
		end
		return answer(verdict, reason)
	end

	-- (card t_4590ab7e, item 2) WHICH ROLE REACHES THE WEAPON PATH. Where the
	-- client named TANK, the terms are the TANK role's own (tankWeaponOrder): the
	-- stats its tank weight pack prices. Everywhere else `order` IS spec.order, so
	-- the melee/spell rows — and every row on a class with no tank pack — are
	-- byte-identical to today. The ORDER itself is untouched: spec.order still
	-- resolved through the ROLE_ALIAS fold (`spell`), which is what keeps a Prot
	-- paladin's rows out of the UNKNOWN branch.
	local order = Verdict.tankWeaponOrder(spec.class, spec.role, spec.clientRole)
		or spec.order
	-- A4 (card t_ce1c4a4f): COPY the spec, then replace ONLY the order. The
	-- hand-built table this replaces dropped `context` (and every other field a
	-- later spec grows), so a TANK weapon reached Verdict.evaluate — and with it
	-- the arbitration — with no situation at all: the model would price the pair
	-- for the default context while the player had set another. A spec that
	-- loses a field at a seam is a wrong answer waiting for someone to build it.
	local cmpSpec = spec
	if order ~= spec.order then
		cmpSpec = {}
		for k, v in pairs(spec) do cmpSpec[k] = v end
		cmpSpec.order = order
	end

	local api = type(apiBySide) == "table" and apiBySide or nil
	local candWords, candUnmapped = apiSideResolve(api and rawget(api, "candidate"))
	local wornWords, wornUnmapped = apiSideResolve(api and rawget(api, "worn"))
	if type(candUnmapped) == "table" and #candUnmapped > 0 then
		return cannotClassify("candidate", candUnmapped[1],
			"a client stat key this addon has not verified")
	end
	if type(wornUnmapped) == "table" and #wornUnmapped > 0 then
		return cannotClassify("worn", wornUnmapped[1],
			"a client stat key this addon has not verified")
	end

	-- An EMPTY slot keeps today's exact answer AND reason: filling the main hand
	-- with a caster weapon is still an upgrade. Deliberately NOT routed through
	-- evaluate(): its gate 6 words this with the chest sentinel its callers
	-- rewrite per slot, and there is no such rewrite on the weapon branch.
	if wornLines == nil then
		-- (card t_e2603a9c, item 1 — the R6 placement rule on the weapon
		-- path: a candidate carrying a word whose unit is unconfirmed (the
		-- UNCONFIRMED_UNITS list) cannot be waved in to fill the slot,
		-- whatever its DPS; since card C1 only a ruled unconfirmed unit
		-- closes the pair, and on the weapon path it can arrive only through
		-- apiBySide.) The parse must succeed for the gate to speak; a
		-- side that does not parse keeps the pre-card shortcut, so a
		-- suppression never changes answer or reason (the byte-identical rule
		-- holds for such rows).
		-- (card t_c65cc350) ... and by the same rule the enchant is out of it, so
		-- an enchant can never wave a weapon into an empty slot either.
		local fillSide = weaponDisclosureLines(weaponStatLines(candLines))
		local fillStats, fillProc, fillUnknown = parseSide(fillSide, "candidate", candWords)
		if fillProc == nil and fillUnknown == nil then
			local unpricedFill = Verdict.unpricedWord(fillStats)
			if unpricedFill ~= nil then
				return "UNKNOWN", Verdict.unpricedWordReason(unpricedFill)
			end
		end
		return answer("UPGRADE", "upgrade: fills the weapon slot")
	end

	local candSide, eqSide = weaponStatLines(candLines), weaponStatLines(wornLines)
	-- (card t_d5c915f2) The on-hit proc is set aside from the STAT parse — it is
	-- named on the answer instead (the `answer` clause above) — so it cannot
	-- suppress a weapon the way an unplaceable line must. Nothing else about the
	-- parse changes, and a pair with no proc is byte-identical.
	-- (card t_c65cc350) The enchant goes with it, from BOTH sides: that is what
	-- keeps it out of the score as well as out of the suppression channel (the
	-- worn side would otherwise FOLD a placeable payload into its stats, the
	-- armour rule), and it is what makes the owner's own pair judge instead of
	-- refusing.
	candSide, eqSide = weaponDisclosureLines(candSide), weaponDisclosureLines(eqSide)
	-- WHY THIS PARSES THE SIDES *AND* evaluate() PARSES THEM AGAIN. Gate 7 of
	-- evaluate() reads "a filled slot whose stats yielded nothing" as
	-- UNREADABLE. For ARMOUR that is right — every armour piece prints Armor, so
	-- nothing readable means the read failed. For a WEAPON it is wrong: a
	-- stat-less weapon is a real, common item and its tooltip was read
	-- completely. So the no-stat-content WORN side is decided HERE, where the
	-- parse can tell "carries no stats" from "could not be read", and evaluate()
	-- keeps doing what it has always done for every pair with stats on the worn
	-- side. The cost is one extra parse of ~10 short lines on the hover path;
	-- there is no client call and no state.
	local candStats, candProc, candUnknown = parseSide(candSide, "candidate", candWords)
	local eqStats,   eqProc,   eqUnknown   = parseSide(eqSide,   "worn",      wornWords)
	local suppressed = candProc ~= nil or candUnknown ~= nil
		or eqProc ~= nil or eqUnknown ~= nil
	-- (card t_e2603a9c, item 1 — the unpriced-stat gate, applied at the
	-- WEAPON's decision points per the #39 seam: ChestAdvisor.
	-- _twoHandCombinedWorn hands the COMBINED side to THIS function as
	-- plain lines, and the seam names the compareWeapon calls as the
	-- application place. So ONE correction — the Verdict.unpricedWord
	-- vocabulary, one word map, no second parser — reaches the two-hander
	-- judgement exactly as it reaches the stat-led armour pair.) Either side
	-- carrying a word whose unit is unconfirmed (the UNCONFIRMED_UNITS list)
	-- fails the pair closed BEFORE the weapon's early decisions — the
	-- statless-worn UPGRADE and the level-stats DPS call — none of which
	-- reaches the matching gate inside Verdict.evaluate. Since card C1 only
	-- a ruled unconfirmed unit closes the pair, and on the weapon path it
	-- can arrive only through apiBySide. The `statLed == nil` guard ABOVE
	-- owns the scope: a class without a resolved order stays on the plain
	-- DPS call, and the DPS-only answer otherwise stands, untouched.
	if not suppressed then
		local unpriced = Verdict.unpricedWord(candStats)
			or Verdict.unpricedWord(eqStats)
		if unpriced ~= nil then
			return "UNKNOWN", Verdict.unpricedWordReason(unpriced)
		end
		-- Gate 8c on the WEAPON path (card t_d53877b1, option C): the same
		-- difference-based unconfirmed-unit guard through the same ONE predicate
		-- — a weapon can carry a hit/crit line as readily as a chest piece, and
		-- a pair left unguarded here would answer on the DPS channel a question
		-- the armour path refuses. Same reason shape, same words.
		local unconfirmedDiff = Verdict.unconfirmedDifference(candStats, eqStats)
		if unconfirmedDiff ~= nil then
			return "UNKNOWN", Verdict.unpricedWordReason(unconfirmedDiff)
		end
	end
	local outcome = nil
	if not suppressed then
		outcome = Verdict.dominance(candStats, eqStats, order)
	end


	if not suppressed and next(eqStats) == nil then
		-- The worn weapon carries NO stat at all: a KNOWN absence (every line on
		-- it parsed cleanly, so nothing suppressed and no stat is hidden), not a
		-- failed read.
		if outcome == "dominant" then
			-- The candidate carries something the worn item does not. Dominance's
			-- own one-sided rule counts that as a gain, and the reason is worded
			-- with the same winReason() grammar evaluate() uses, so the tooltip's
			-- reason-word parsing cannot tell the two apart.
			-- (No `allow` wrapper is needed here: a weapon tooltip names no typed
			-- armour slot, so lowerArmorReason is nil for every weapon pair.)
			for _, word in ipairs(order) do
				if (candStats[word] or 0) > 0 then return answer("UPGRADE", winReason(word)) end
			end
			return answer("UPGRADE", winReason())
		end
		-- Nothing the stats can decide on: both weapons carry no stat, or the
		-- candidate's only stat is outside the role's order (spell power — see
		-- this section's note). The DPS tie-break is today's answer — but its
		-- EQUAL claim is checked against what the pair's stats can measure first
		-- (card t_d5c915f2): a candidate that is measurably ahead on Hit or Crit
		-- must not be called "the same" just because the order does not carry
		-- the word. The gate is the melee branch's own rule, one helper away.
		local dv, dr, tie = compareDPS(candNumbers, wornNumbers, wornSlotFilled, cmpSpec)
		local v, r = equalClaimOnStats(dv, dr, tie, candStats, eqStats, cmpSpec)
		return answer(v, r)
	end

	if not suppressed and outcome == nil then
		-- The stats are LEVEL on every term of the role's own order (or absent on
		-- both sides): there is no caster-stat difference for DPS to outvote, so
		-- DPS decides — today's comparator, today's strings. This is the whole of
		-- option (b)'s "DPS as a minor term": level stats are the only case in
		-- which DPS is consulted at all. The equal claim is gated exactly as it
		-- is on the melee branch and on the worn-side-empty branch above (card
		-- t_d5c915f2): level on the ORDER is not the same fact as level on the
		-- pair.
		local dv2, dr2, tie2 = compareDPS(candNumbers, wornNumbers, wornSlotFilled, cmpSpec)
		local v2, r2 = equalClaimOnStats(dv2, dr2, tie2, candStats, eqStats, cmpSpec)
		return answer(v2, r2)
	end

	-- The stats decide — or a line suppressed somewhere, which is fail-closed
	-- exactly as on the armour path. This IS the armour comparator, called with
	-- the same spec the armour rows are judged by: one dominance walk, one
	-- weighted layer, one set of reason strings. `cmpSpec` differs from `spec`
	-- ONLY in its `order` — and only where the client named TANK (card
	-- t_4590ab7e, item 2); the weights the layer consults are reached through
	-- class/role/clientRole, which are carried across unchanged.
	--
	-- (card t_8e171c28) `totals` rides through to the same TRADE_OFF_SEAM the
	-- armour path uses, so a weapon trade-off is arbitrated by the same model,
	-- in the same place, with the same nil-means-today's-bytes rule. The third
	-- return is the judge's detail; `answer` passes it out without reading it.
	local ev, er, ed = Verdict.evaluate({ canUse = canUse, line = candSide },
		{ line = eqSide }, cmpSpec, api, nil, totals)
	return answer(ev, er, ed)
end

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
--          foreign — (card t_4ff4ebef) an array of the lines the reader composed
--                  but the item did not: another addon's annotation and the
--                  block it opens. Optional FOURTH return, kept out of
--                  `ignored` on purpose — a foreign line is not the item's
--                  cosmetic prose. Render Verdict.partialNote(ignored, foreign)
--                  to disclose both truthfully.
-- `lines` is never mutated; the input table is only read.
-- `apiWords` (card t_548f0341, OPTIONAL) is the client's own stat read for this
-- side, mapped by Verdict.apiStats at the impure edge. Since card t_795eee9e
-- the live edge ships the wrapper shape { words = ..., unmapped = ... }; the
-- resolution is apiSideResolve, the SAME function evaluate() uses, so the
-- numbers a caller prints are the numbers the verdict was decided on. It
-- resolves an unplaceable line exactly as the comparator's own parse does.
function Verdict.statTable(lines, side, apiWords)
	-- Both sides keep their own half of this call (merge of origin/main into
	-- card t_795eee9e): the api read still crosses apiSideResolve — the live
	-- edge ships { words = ..., unmapped = ... }, so handing the wrapper to
	-- parseSide would feed it a table with no words — while main's foreign
	-- channel is handed straight back to the caller, which is what the
	-- disclosure reads as the FOURTH return.
	local words = apiSideResolve(apiWords)
	local stats, proc, unknown, ignored, foreign =
		parseSide(lines, side == "worn" and "worn" or "candidate", words)
	return stats, (proc or unknown), ignored, foreign
end

-- Both sides' skipped lines as ONE list (card t_d8de0090). The disclosure has
-- to name the lines set aside on EITHER side — the EQUIPPED item's cosmetic
-- chrome is the other half of the comparison the verdict describes — and the
-- tooltip and the scan's raw record must agree about WHICH lines those are.
--
-- Before this card that combination lived in the UI file (partialReadSuffix in
-- ChestAdvisor.lua), which meant the player-facing surface and any raw record
-- would each have needed their own copy of it: exactly the second definition
-- two surfaces drift apart on. One function, called by both.
--
-- `apiBySide` is the SAME { candidate = ..., worn = ... } table Verdict.evaluate
-- took, so a line the client's own stat read EXPLAINS is not reported as
-- skipped (card t_548f0341's agreement rule). nil leaves both sides on the
-- unexplained path — the fail-closed answer.
--
-- Returns a new array (candidate lines first, then worn); inputs are never
-- mutated.
function Verdict.ignoredLines(candLines, wornLines, apiBySide)
	local api = type(apiBySide) == "table" and apiBySide or nil
	local out = {}
	local _, _, candIgnored =
		Verdict.statTable(candLines, "candidate", api and api.candidate or nil)
	for _, line in ipairs(candIgnored or {}) do out[#out + 1] = line end
	if type(wornLines) == "table" then
		local _, _, wornIgnored =
			Verdict.statTable(wornLines, "worn", api and api.worn or nil)
		for _, line in ipairs(wornIgnored or {}) do out[#out + 1] = line end
	end
	return out
end

-- Both sides' FOREIGN lines as ONE list (card t_b8c890e6). The disclosure has
-- to count the lines set aside on EITHER side — the EQUIPPED item's addon
-- annotation is the other half of the comparison the verdict describes — and
-- the player-facing tooltip and /up diag's raw record must agree about WHICH
-- lines those are. This mirrors Verdict.ignoredLines for the foreign half:
-- ONE function the raw record calls, so the two surfaces name the same lines
-- (the tooltip's partialReadSuffix composes the same splitForeign over both
-- sides and is byte-identical to this on the same strings).
--
-- splitForeign reads no client state, so this takes no apiBySide — the
-- strings the caller passes ARE the read the verdict was decided on, and a
-- non-table side contributes nothing. Candidate first, then worn, the same
-- order ignoredLines uses. Returns a new array; inputs are never mutated.
function Verdict.foreignLines(candLines, wornLines)
	local out = {}
	local _, foreign = Verdict.splitForeign(candLines)
	for _, line in ipairs(foreign or {}) do out[#out + 1] = line end
	if type(wornLines) == "table" then
		local _, wornForeign = Verdict.splitForeign(wornLines)
		for _, line in ipairs(wornForeign or {}) do out[#out + 1] = line end
	end
	return out
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
	-- card t_3cdbb70a (DD-1): the feral word needs a player-facing label or a
	-- delta reads "FeralAttackPower" on screen. (Card t_9d3273cb retired the two
	-- spell labels with their two words; "Hit" and "Crit" already read as
	-- themselves.)
	FeralAttackPower = "Feral AP",
	-- card t_4e1e1b1d (DD-2): a delta reads "+22 Healing", "+20 Fire". The
	-- school labels drop the "Power" the token carries — a player says "Fire
	-- damage", never "FirePower" — and stay one word so a tooltip row keeps
	-- its width.
	Healing   = "Healing",
	HolyPower = "Holy",
	FirePower = "Fire",
	FrostPower = "Frost",
	ShadowPower = "Shadow",
	NaturePower = "Nature",
	ArcanePower = "Arcane",
	-- card t_8575389a: the damage half. Two words because "SpellDmg" is not a
	-- thing a player reads; the tooltip row stays inside its width ("+14 Spell
	-- Damage").
	SpellDamage = "Spell Damage",
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
