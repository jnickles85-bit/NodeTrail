-- Host opt-out: a host that vendors these files sets TouchstoneSkip = true before
-- loading them, and every shipped file returns at this line. Unset -- the normal
-- case -- nothing changes. See README.md, "Embedding Touchstone in a host addon".
if TouchstoneSkip then return end
-- StatOrders.lua — the published stat-priority orders, keyed by the CONTEXT IN FORCE.
-- (card t_45b88d9c; the sourcing and its citation register live in
--  docs/step2-forever-stat-priority-sourcing-2026-11-13.md, §3, §4 and §9)
--
-- WHAT THIS IS. A DATA table. It answers one question for the engine:
--
--     "for this context, this class and this spec, WHICH published stat order is
--      in force, and WHO published it?"
--
-- It is the Step 2 sourcing map turned into something a verdict can read. It
-- contains no weight, no ratio, no coefficient and no arithmetic: entries are
-- the published SEQUENCE of stat words, in the source's own wording, with the
-- source's own qualifier attached where it had one ("Hit Chance until 8%",
-- "Defense until 440", "Only while leveling"). A qualifier is part of the
-- claim — dropping it to store a bare stat word would silently change what the
-- source said — so nothing here is normalised into the addon's stat vocabulary.
-- Mapping these entries onto Verdict's stat words (and onto cap VALUES) is a
-- later, separate decision; the hit-cap value is a Step 3 GAP, not this file's
-- call.
--
-- THE SHAPE (the card's shape, verbatim):
--
--   StatOrders.get(context, class, spec) -> order, source
--   StatOrders.row(context, class, spec) -> { context, phase, class, spec,
--                                             order, source, variant, note } | nil
--   StatOrders.CONTEXTS                  -> { "Leveling", "Dungeon", "Raid" }
--   StatOrders.CONTEXT_REGIME            -> context -> "leveling" | "endgame"
--   StatOrders.CLAIMS                    -> the 37 published claims, one table
--                                           each (28 endgame + 9 leveling)
--
--   `order`  is an ARRAY of published entries, highest priority first. It is
--            always the ONE stored table object for that claim — never a copy —
--            so two lookups that resolve to the same claim are rawequal, and a
--            caller that mutates what it is handed is mutating the shipped data
--            (do not; treat it as read-only).
--   `source` is the provenance id: a `WH-*` page for an endgame claim, an
--            `MO-*-lvl` page for a leveling claim. Every id appears in the
--            document's citation register (§8). The endgame ids name pages
--            that state, in their own words, that their order is a published
--            ESTIMATE for a level-30-locked beta (§2 caveat 1) — the flag
--            travels with the id, it is not re-litigated here.
--   `row`    returns a fresh small view table per call (cheap, immutable in
--            effect); the ORDER inside it is the shared object.
--
-- THE THREE RULINGS THIS FILE ENCODES (director, 2026-11-16; written up in the
-- document's §6 "Rulings" and §9):
--
--   D1 — LEVELING IS PER CLASS, NOT PER SPEC. No Forever source publishes a
--        spec-level leveling order (the document's F2), so Leveling rows carry
--        NO spec. `row("Leveling", class, spec)` ACCEPTS a spec and ignores it,
--        exactly as a pure class ignores the role argument in Verdict.ORDERS,
--        and the row it returns reports `spec = nil`. No spec-level leveling
--        list is invented to fill the shape. The three spec-level leveling
--        orders that do exist (document §4a) are NOT encoded: two stop at five
--        entries or change by level band, and the third has an uncaptured date.
--
--   D2 — THE DEFENSIVE ORDER IS THE DEFAULT FOR THE TANK ROLE. Warrior
--        Protection and Paladin Protection each publish THREE orders
--        (Defensive / Balanced / Offensive); only Defensive is encoded.
--        Feral (bear) publishes two (Defensive / Offensive) and follows the
--        same rule — its author writes that "definite stat priorities cannot
--        be established", and that warning travels with the row. Every other
--        published variant is named in `variant.not_encoded` so the stored list
--        cannot be mistaken for the only published one. A tank spec is refused
--        by Step 3's model anyway; this order serves the strict layer, never a
--        tank weighting.
--
--   D3 — ONE ROGUE ORDER, THREE SPEC ROWS. Wowhead publishes the identical
--        sequence on its three rogue pages, so the list exists ONCE
--        (ROGUE_ENDGAME below) and the three rows point at it. Their provenance
--        ids stay per-page (WH-assa / WH-combat / WH-sub) because they are
--        three separately published pages with three dates — one claim, three
--        citations. Hunter is deliberately NOT shared: BM and MM happen to
--        print the same sequence today, but they are two separate pages, and a
--        shared object would move both if one page is revised later.
--
-- WHAT IS NOT HERE, and why (document §9.5): the Balanced/Offensive tank
-- variants; the §4a spec-level leveling exceptions; the Classic-era `WT-*`
-- lists (adjacent evidence, never a stand-in — F7); the `MO-C-*` community
-- lists (conflicts, and three of the five were read through a search index).
--
-- DEPENDENCIES: none. This file reads no global and mutates none; it publishes
-- itself to `_G.StatOrders` (the pattern Verdict.lua uses) and, when the host
-- core is loaded, as `StatForge.StatOrders`. It may be loaded standalone in a
-- test VM with no Constants.lua and no host present.

local StatOrders = {}

StatOrders.SOURCE_DOC = "docs/step2-forever-stat-priority-sourcing-2026-11-13.md"

-- ---- the contexts -----------------------------------------------------------
-- A context does not only pick a mana regime (Step 3 §4.3); it picks the PHASE,
-- and the phase picks the list. Two phases, three contexts, on purpose: the
-- sources publish on the phase axis, and Dungeon and Raid read the same
-- published claim — they differ in the arithmetic done with it, not in the
-- order. Storing the 28 endgame claims twice (once per context) would be one
-- claim made twice.
local CONTEXT_REGIME = {
	Leveling = "leveling",
	Dungeon = "endgame",
	Raid = "endgame",
}

StatOrders.CONTEXT_REGIME = CONTEXT_REGIME
StatOrders.CONTEXTS = { "Leveling", "Dungeon", "Raid" }

-- ---- the published orders ---------------------------------------------------
-- ONE table per publication, keyed by its provenance id. Every entry below is
-- the source's own sequence and wording (document §3 endgame, §4 leveling).
-- Read-only: the array objects are handed out by reference.
local ORDERS = {}

-- ENDGAME — one published claim per spec, 28 of them (document §3).
ORDERS["WH-arms"] = {
	"Hit Chance until 8%", "Expertise until 6.5%", "Critical Strike Chance",
	"Strength", "Agility", "Haste", "Hit Chance after 8%",
}
ORDERS["WH-fury"] = {
	"Weapon Skill until 305", "Hit Chance until 9%", "Critical Strike Chance",
	"Strength", "Agility", "Stamina",
}
-- D2: Warrior Protection's DEFENSIVE list. Balanced and Offensive exist on the
-- same page and are not encoded (see `variant` on the row below). The three
-- lists all begin Stamina; the second/third terms are what separate them.
ORDERS["WH-prot-war"] = {
	"Stamina", "Defense until 440", "Armor", "Agility", "Defense after 440",
	"Parry", "Dodge", "Expertise (6.5%) soft cap", "Block Chance",
	"Attack Power/Strength", "Hit (8%) melee cap", "Crit",
	"Expertise (14%) hard cap", "Haste",
}
ORDERS["WH-holy-pal"] = {
	"Healing Power", "Intellect", "Critical Strike", "Spirit",
}
-- D2: Paladin Protection's DEFENSIVE list; Balanced and Offensive not encoded.
ORDERS["WH-prot-pal"] = {
	"Stamina", "Defense until 440", "Armor", "Agility", "Block Chance",
	"Defense after 440", "Spell Power (still need some threat)", "Parry",
	"Dodge", "Strength", "Hit (8%) melee cap", "Expertise (6.5%)", "Crit",
	"Hit (17%) spell cap", "Expertise (14%)", "Haste", "Intellect",
}
ORDERS["WH-ret"] = {
	"Weapon Skill", "Weapon DPS & Speed", "Hit Chance (9%)",
	"Expertise (6.5%)", "Spell Damage", "Intellect",
	"Strength & Attack Power", "Agility & Critical Strike Chance", "Stamina",
}
ORDERS["WH-bm"] = {
	"% Hit Chance until 9%", "% Critical Strike Chance", "Agility",
	"Intellect", "(Ranged) Attack Power", "Spirit", "Stamina",
}
-- BM and MM print the same sequence today and are STILL two rows with two
-- orders (see the D3 note above): two separate pages, two separate claims.
ORDERS["WH-mm"] = {
	"% Hit Chance until 9%", "% Critical Strike Chance", "Agility",
	"Intellect", "(Ranged) Attack Power", "Spirit", "Stamina",
}
ORDERS["WH-sv"] = {
	"% Hit Chance", "% Critical Strike Chance", "Agility", "Strength",
	"Attack Power", "Intellect", "Spirit", "Stamina",
}
-- D3: ONE published sequence, three rogue pages. The three rows below point at
-- THIS object; it is the only copy in the file.
local ROGUE_ENDGAME = {
	"Hit Chance until 8% (Ability cap)", "Expertise to 6.5%",
	"Weapon skill to 308", "Hit to 17% (Poison cap)", "Agility",
	"Critical Strike Chance", "Haste Rating", "Strength", "Attack Power",
	"Stamina",
}
ORDERS["WH-disc"] = {
	"Healing Power", "Intellect", "Spirit", "Critical Strike Chance",
	"Spell Damage", "Stamina",
}
ORDERS["WH-holy-pr"] = {
	"Healing Power", "Intellect", "Mana per 5 seconds", "Spirit",
	"Spell Critical Strike Chance", "Stamina",
}
ORDERS["WH-shadow"] = {
	"Hit Chance until 17%", "Spell Critical Strike Chance",
	"Spell Damage (Shadow Damage)", "Intellect", "Spirit", "Stamina",
}
ORDERS["WH-elem"] = {
	"Spell Piercing", "Haste / Cast Speed", "Hit Chance until 17%",
	"Spell Damage", "Critical Strike Chance",
	"Nature Damage / Fire Damage", "Intellect", "Spirit",
	"Strength (Only while leveling)", "Stamina",
}
ORDERS["WH-enh"] = {
	"Hit Chance to minimum 8%", "Expertise to 6.5%", "Intellect",
	"Spell Damage", "Strength", "Spell Piercing", "Haste",
	"Critical Strike Chance", "Agility", "Spirit", "Stamina",
}
ORDERS["WH-resto-sh"] = {
	"Spell Healing", "Critical Strike Chance", "Haste / Cast Speed",
	"Intellect", "Spirit", "Mp5", "Spell Damage (Only while leveling)",
	"Hit Chance until 17% (Only while leveling)",
	"Spell Piercing (Only while leveling)",
	"Strength (Only while leveling)", "Stamina",
}
ORDERS["WH-arcane"] = {
	"Hit Chance until 17%", "Spell Damage (+ Arcane Damage)",
	"Critical Strike Chance", "Spell Piercing", "Haste", "Intellect",
	"Spirit", "Stamina",
}
ORDERS["WH-fire"] = {
	"Hit Chance until 17%", "Spell Damage (+ Fire Damage)",
	"Critical Strike Chance", "Spell Piercing", "Haste", "Intellect",
	"Spirit", "Stamina",
}
ORDERS["WH-frost"] = {
	"Hit Chance until 11-12% (you'll get 5-6 from talents)",
	"Critical Strike Chance", "Spell Damage (+Frost and Arcane Damage)",
	"Intellect", "Spirit", "Stamina",
}
ORDERS["WH-affl"] = {
	"Spell Power / + Shadow Damage", "Crit Chance",
	"Hit Chance (up to 12% from gear with 5/5 Suppression)", "Haste",
	"Spell Pierce", "Intellect", "Spirit",
}
ORDERS["WH-demo"] = {
	"Spell Power / + Fire Damage or + Shadow Damage (matching your build)",
	"Hit Chance (17% from gear, minus 1% per point in Suppression)",
	"Crit Chance", "Haste", "Spell Pierce", "Intellect", "Spirit",
}
ORDERS["WH-destro"] = {
	"Spell Power / + Fire Damage", "Crit Chance",
	"Hit Chance (up to 12% from gear with 5/5 Suppression)", "Haste",
	"Spell Pierce", "Intellect", "Spirit",
}
ORDERS["WH-bal"] = {
	"Hit Chance until 17%", "Spell Damage", "Spell Penetration",
	"Critical Strike Chance", "Haste", "Intellect", "Spirit", "Stamina",
}
ORDERS["WH-feral-cat"] = {
	"1% Critical Strike Chance", "1% Hit Chance (8% cap)",
	"1% Reduced Dodge/Parry Chance (6.5% cap)", "1% Haste", "Weapon DPS",
	"Agility = Strength", "Attack Power", "Intellect", "Spirit", "Stamina",
}
-- D2: Feral (bear) publishes Defensive / Offensive; only Defensive is encoded.
-- The author's own warning stays with the row (see `note`).
ORDERS["WH-feral-bear"] = {
	"Stamina", "Defense until 440", "Armor", "Agility", "Avoidance",
	"Defense after 440",
}
ORDERS["WH-resto-dr"] = {
	"Spell Healing", "Critical Strike Chance", "Spell Haste", "Spirit",
	"Intellect", "MP5", "Stamina",
}

-- LEVELING — one published claim per class, 9 of them (document §4). These are
-- CLASS-scoped by construction; `spec` on the row is nil, not "every spec".
ORDERS["MO-war-lvl"] = {
	"Spirit", "Strength", "Agility", "Stamina", "Intellect",
}
ORDERS["MO-pal-lvl"] = {
	"Weapon Damage", "Stamina and Spirit", "Intellect (Level 40+)",
	"Strength and Spell Power", "Healing Power and Agility",
}
ORDERS["MO-hun-lvl"] = {
	"Agility", "Attack Power", "Stamina", "Spirit", "Intellect",
}
ORDERS["MO-rog-lvl"] = {
	"Agility", "Strength", "Attack Power", "Stamina",
}
ORDERS["MO-pri-lvl"] = {
	"Spellpower", "Spirit", "Intellect", "Stamina", "Crit", "Hit", "Haste",
	"MP5",
}
ORDERS["MO-sha-lvl"] = {
	"Strength = Attack Power", "Intellect", "Spellpower = Agility", "Spirit",
}
ORDERS["MO-mag-lvl"] = {
	"Spell Hit Chance up to (17%) when available",
	"Spell Power or the spell damage of your spec",
	"Spell Critical Strike Chance", "Spell Haste", "Intellect", "Spirit",
	"Stamina",
}
ORDERS["MO-wlk-lvl"] = {
	"Spell Power", "Hit Chance", "Intellect", "Stamina",
	"Critical Strike Chance", "Spirit", "Haste",
}
ORDERS["MO-dru-lvl"] = {
	"Weapon Damage", "Strength, Agility and Attack Power",
	"Stamina & Spirit", "Intellect, Spell Power and Healing Power",
}

-- ---- the claims -------------------------------------------------------------
-- One row per PUBLISHED claim: 28 endgame (one per spec) + 9 leveling (one per
-- class). `phase` is the publication axis, not the context: Dungeon and Raid
-- both resolve through `endgame` (see CONTEXT_REGIME above).
--
-- A leveling row has NO `spec` field at all — that absence is the D1 ruling,
-- expressed in data rather than in a comment.
StatOrders.CLAIMS = {}

local function claim(entry)
	StatOrders.CLAIMS[#StatOrders.CLAIMS + 1] = entry
end

-- ENDGAME — 28 spec rows. Provenance is per row: three rogue rows share one
-- ORDER but keep three separate citations (D3).
claim({ phase = "endgame", class = "WARRIOR", spec = "Arms",
	source = "WH-arms", order = ORDERS["WH-arms"] })
claim({ phase = "endgame", class = "WARRIOR", spec = "Fury",
	source = "WH-fury", order = ORDERS["WH-fury"] })
claim({ phase = "endgame", class = "WARRIOR", spec = "Protection",
	source = "WH-prot-war", order = ORDERS["WH-prot-war"],
	variant = { encoded = "Defensive", not_encoded = { "Balanced", "Offensive" } } })
claim({ phase = "endgame", class = "PALADIN", spec = "Holy",
	source = "WH-holy-pal", order = ORDERS["WH-holy-pal"] })
claim({ phase = "endgame", class = "PALADIN", spec = "Protection",
	source = "WH-prot-pal", order = ORDERS["WH-prot-pal"],
	variant = { encoded = "Defensive", not_encoded = { "Balanced", "Offensive" } } })
claim({ phase = "endgame", class = "PALADIN", spec = "Retribution",
	source = "WH-ret", order = ORDERS["WH-ret"] })
claim({ phase = "endgame", class = "HUNTER", spec = "Beast Mastery",
	source = "WH-bm", order = ORDERS["WH-bm"] })
claim({ phase = "endgame", class = "HUNTER", spec = "Marksmanship",
	source = "WH-mm", order = ORDERS["WH-mm"] })
claim({ phase = "endgame", class = "HUNTER", spec = "Survival",
	source = "WH-sv", order = ORDERS["WH-sv"] })
claim({ phase = "endgame", class = "ROGUE", spec = "Assassination",
	source = "WH-assa", order = ROGUE_ENDGAME, shared = "rogue-endgame" })
claim({ phase = "endgame", class = "ROGUE", spec = "Combat",
	source = "WH-combat", order = ROGUE_ENDGAME, shared = "rogue-endgame" })
claim({ phase = "endgame", class = "ROGUE", spec = "Subtlety",
	source = "WH-sub", order = ROGUE_ENDGAME, shared = "rogue-endgame" })
claim({ phase = "endgame", class = "PRIEST", spec = "Discipline",
	source = "WH-disc", order = ORDERS["WH-disc"] })
claim({ phase = "endgame", class = "PRIEST", spec = "Holy",
	source = "WH-holy-pr", order = ORDERS["WH-holy-pr"] })
claim({ phase = "endgame", class = "PRIEST", spec = "Shadow",
	source = "WH-shadow", order = ORDERS["WH-shadow"] })
claim({ phase = "endgame", class = "SHAMAN", spec = "Elemental",
	source = "WH-elem", order = ORDERS["WH-elem"] })
claim({ phase = "endgame", class = "SHAMAN", spec = "Enhancement",
	source = "WH-enh", order = ORDERS["WH-enh"] })
claim({ phase = "endgame", class = "SHAMAN", spec = "Restoration",
	source = "WH-resto-sh", order = ORDERS["WH-resto-sh"] })
claim({ phase = "endgame", class = "MAGE", spec = "Arcane",
	source = "WH-arcane", order = ORDERS["WH-arcane"] })
claim({ phase = "endgame", class = "MAGE", spec = "Fire",
	source = "WH-fire", order = ORDERS["WH-fire"] })
claim({ phase = "endgame", class = "MAGE", spec = "Frost",
	source = "WH-frost", order = ORDERS["WH-frost"] })
claim({ phase = "endgame", class = "WARLOCK", spec = "Affliction",
	source = "WH-affl", order = ORDERS["WH-affl"] })
claim({ phase = "endgame", class = "WARLOCK", spec = "Demonology",
	source = "WH-demo", order = ORDERS["WH-demo"] })
claim({ phase = "endgame", class = "WARLOCK", spec = "Destruction",
	source = "WH-destro", order = ORDERS["WH-destro"] })
claim({ phase = "endgame", class = "DRUID", spec = "Balance",
	source = "WH-bal", order = ORDERS["WH-bal"] })
claim({ phase = "endgame", class = "DRUID", spec = "Feral (cat)",
	source = "WH-feral-cat", order = ORDERS["WH-feral-cat"] })
claim({ phase = "endgame", class = "DRUID", spec = "Feral (bear)",
	source = "WH-feral-bear", order = ORDERS["WH-feral-bear"],
	variant = { encoded = "Defensive", not_encoded = { "Offensive" } },
	note = "source: \"definite stat priorities cannot be established\"" })
claim({ phase = "endgame", class = "DRUID", spec = "Restoration",
	source = "WH-resto-dr", order = ORDERS["WH-resto-dr"] })

-- LEVELING — 9 CLASS rows (D1). No `spec` key on any of them.
claim({ phase = "leveling", class = "WARRIOR", source = "MO-war-lvl",
	order = ORDERS["MO-war-lvl"],
	note = "secondary, source's own: Hit until soft-hit cap (8%) -> Expertise -> Critical strike -> Haste; \"Drops below Stamina in dungeons\"" })
claim({ phase = "leveling", class = "PALADIN", source = "MO-pal-lvl",
	order = ORDERS["MO-pal-lvl"],
	note = "Crit/Hit/Mp5 are \"rare until the end game... not included in the normal stat priority\"" })
claim({ phase = "leveling", class = "HUNTER", source = "MO-hun-lvl",
	order = ORDERS["MO-hun-lvl"],
	note = "Crit/Hit \"very rare early... raw stats typically outshine these\"" })
claim({ phase = "leveling", class = "ROGUE", source = "MO-rog-lvl",
	order = ORDERS["MO-rog-lvl"],
	note = "secondary, source's own: Hit Chance -> Reduced Chance to Dodge/Parry (Expertise) -> Critical Strike" })
claim({ phase = "leveling", class = "PRIEST", source = "MO-pri-lvl",
	order = ORDERS["MO-pri-lvl"] })
claim({ phase = "leveling", class = "SHAMAN", source = "MO-sha-lvl",
	order = ORDERS["MO-sha-lvl"],
	note = "Crit \"very important for Flurry\"; the page carries per-spec variants and this is its default (Enhancement-flavoured) order" })
claim({ phase = "leveling", class = "MAGE", source = "MO-mag-lvl",
	order = ORDERS["MO-mag-lvl"],
	note = "\"while leveling I would focus on Spell power and intellect\"" })
claim({ phase = "leveling", class = "WARLOCK", source = "MO-wlk-lvl",
	order = ORDERS["MO-wlk-lvl"],
	note = "\"Stat priority is different when Leveling and transitioning into the end game\"" })
claim({ phase = "leveling", class = "DRUID", source = "MO-dru-lvl",
	order = ORDERS["MO-dru-lvl"],
	note = "Crit/Hit/Mp5 \"very rare... not included in the normal stat priority\"" })

-- ---- the lookup -------------------------------------------------------------
-- phase -> class -> (spec | "" for the class-scoped leveling row) -> claim.
-- Built once at load. A duplicate (class, spec) is a hard error: this table is
-- a fixed roster of 37 sourced claims, so a second row for the same key can
-- only come from a bad edit, and failing at load is louder than letting one row
-- quietly shadow another.
local BY_KEY = {}

for _, entry in ipairs(StatOrders.CLAIMS) do
	local byClass = BY_KEY[entry.phase]
	if not byClass then
		byClass = {}
		BY_KEY[entry.phase] = byClass
	end
	local bySpec = byClass[entry.class]
	if not bySpec then
		bySpec = {}
		byClass[entry.class] = bySpec
	end
	local key = entry.spec or ""
	if bySpec[key] then
		error("StatOrders: duplicate claim for " .. tostring(entry.phase) .. "/"
			.. tostring(entry.class) .. "/" .. tostring(entry.spec))
	end
	bySpec[key] = entry
end

-- The phase a context puts in force, or nil for an unknown context.
function StatOrders.phaseFor(context)
	if type(context) ~= "string" then return nil end
	return CONTEXT_REGIME[context]
end

-- Resolve { context, class, spec } to a view of the claim in force, or nil.
--
--   * Leveling is PER CLASS (D1): `spec` is accepted and IGNORED, and the view
--     reports `spec = nil` — the class-scoped order is what is in force.
--   * Dungeon and Raid resolve through the same `endgame` claims; `spec` is
--     required there, because the endgame sources publish per spec.
--   * An unknown context, class or spec returns nil. There is no silent
--     fallback to another spec or another class: a caller that cannot be given
--     an order must decide what to say, not be handed a neighbouring list.
function StatOrders.row(context, class, spec)
	local phase = StatOrders.phaseFor(context)
	if not phase then return nil end
	local byClass = BY_KEY[phase]
	if not byClass then return nil end
	local bySpec = type(class) == "string" and byClass[class] or nil
	if not bySpec then return nil end
	local entry
	if phase == "leveling" then
		entry = bySpec[""]
	else
		if type(spec) ~= "string" then return nil end
		entry = bySpec[spec]
	end
	if not entry then return nil end
	return {
		context = context,
		phase = phase,
		class = entry.class,
		spec = entry.spec,   -- nil for a leveling claim: per-class, by ruling
		order = entry.order,
		source = entry.source,
		variant = entry.variant,
		note = entry.note,
		shared = entry.shared,
	}
end

-- `order, source` — the two things a verdict needs: what to rank by, and what
-- to name when it says where that ranking came from.
function StatOrders.get(context, class, spec)
	local entry = StatOrders.row(context, class, spec)
	if not entry then return nil end
	return entry.order, entry.source
end

_G.StatOrders = StatOrders

-- The host core exposes its modules through the `StatForge` table when it is
-- loaded (Constants.lua creates it). Guarded: this file is loaded standalone in
-- test VMs with no host present, and an index on nil there would be a load
-- error rather than the absent-host no-op it must be. Same shape as the
-- read-side guard at Verdict.weightsFor (`type(_G) == "table" and rawget(_G,
-- "StatForge")`), for the same reason.
local SF = rawget(_G, "StatForge")
if type(SF) == "table" then
	SF.StatOrders = StatOrders
end

return StatOrders
