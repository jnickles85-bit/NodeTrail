if MightiePackTouchstoneSkip then return end
-- Weights.lua — per-class/spec stat weights for the upgrade comparator.
-- (card t_984bc8ac)
--
-- WHAT THIS IS. A DATA table, read by the ARMOUR/stat comparator in
-- ChestAdvisor/Verdict.lua (`Verdict.weightsFor`, and the weighted layer above
-- gate 9 of Verdict.evaluate). It is the only thing that file reads out of the
-- environment, and it is read at CALL time — never cached across a scan — so a
-- test VM can install, replace or delete it between two calls.
--
-- THE SHAPE (the card's shape, verbatim):
--
--   StatForge.Weights[CLASS][SPEC] = {
--       STR = <number>, AGI = <number>, STA = <number>, INT = <number>,
--       SPI = <number>, ARMOR = <number>, BLOCK = <number>,
--       HIT = <number>, CRIT = <number>, AP = <number>, RAP = <number>,
--       MP5 = <number>, HP5 = <number>, DEF = <number>, DODGE = <number>,
--       PARRY = <number>, WDN = <number>,
--       FAP = <number>, SPOW = <number>,
--       HEAL = <number>, SPHOLY = <number>, SPFIRE = <number>,
--       SPFROST = <number>, SPSHADOW = <number>, SPNATURE = <number>,
--       SPARCANE = <number>,
--       directional = { <KEY> = true, ... },   -- OPTIONAL, card DD-0
--       source = "<provenance>",
--   }
--
--   CLASS  — the uppercase class token, exactly the key Verdict.ORDERS uses.
--   SPEC   — the role word the order table uses ("melee" | "spell"), or the
--            CLIENT's own role literal lowercased ("tank" | "healer" |
--            "damager"). The literal is the one vocabulary a class's THIRD
--            spec needs: a Protection paladin's role on this client is TANK,
--            and Verdict.ROLE_ALIAS folds that into "spell" for the ORDER —
--            which is a conservative PROXY for a Prot character, not a Prot
--            model. A weight table can carry the real third spec, so a
--            "tank" key wins over the folded role word when the caller
--            supplies the literal (spec.clientRole, ChestAdvisor.lua
--            buildSpec). See Verdict.weightsFor for the resolution order.
--   STR..SPOW — the words this addon reads off a tooltip and prices against
--            the pack the table cites: the original seven (strength, agility,
--            stamina, intellect, spirit, armor, block value), SPOW (spell
--            power — card t_b7cd07e1's ruling "Spell power gets a weight from
--            the packs"), the ten card t_795eee9e added — HIT, CRIT, AP,
--            RAP, MP5, HP5, DEF, DODGE, PARRY, WDN — read from the client
--            keys verified in the client-binary key inventory (item 1 of that
--            card) and priced from the pack each table cites, and FAP
--            (feral-only attack power, card t_3cdbb70a), and the seven
--            card t_4e1e1b1d (DD-2) adds — HEAL (healing power) and one key
--            per school of spell damage (SPHOLY, SPFIRE, SPFROST,
--            SPSHADOW, SPNATURE, SPARCANE). See the HEALING AND SCHOOL POWER
--            note below for where their numbers come from.
--            All of them —
--            the full WEIGHT_KEYS list in Verdict.lua — are REQUIRED in every
--            table, including the ones that are 0: an absent key and a
--            deliberate 0 are different claims and the validator refuses to
--            guess between them (Verdict.weightsFor).
--   source — REQUIRED, a non-empty string, and it MUST carry the verbatim
--            marker "UNVERIFIED — transferred from Classic Era level-60
--            raiding, NOT measured on this build". A table without it is
--            REFUSED WHOLE and the comparator falls back to its ordinal path,
--            so the honest label is load-bearing rather than decorative.
--            ENFORCED, not merely stated (card t_6fda2ec5): the comparator
--            reads SF.WEIGHTS_MARKER — the constant this file publishes just
--            below, spelled ONCE here so the label the validator looks for and
--            the label the tables carry cannot drift — and requires it to be
--            a SUBSTRING of `source`. A marker the environment cannot supply
--            (an older copy of this file, a stripped test VM) refuses every
--            table too, which is the fail-closed direction.
--
-- ── THE DIRECTIONAL MARKER (card DD-0) ──────────────────────────────────────
-- A weight that comes from NO cited pack — a judgement this file makes about
-- THIS build — is declared with the DIRECTIONAL marker instead of being dressed
-- up as sourced. The marker is DATA, not prose, so a test can read it:
--
--   <spec key> = {
--       STR = 1.0,   -- source key: strength 1.0
--       ...
--       source = MARKER .. ". Cite: ...",            -- still REQUIRED, unchanged
--       directional = { STR = true },                -- OPTIONAL; absent = none
--   }
--
-- and the per-key comment records the claim the override rests on:
--
--   -- DIRECTIONAL: <article quote> | <derivation> | review §<n>
--
-- WHY IT EXISTS. The citation diff (ChestAdvisor/tests/weights_citation.js)
-- derives EVERY expected value from the pack a table's own `source` names, so
-- an honest non-pack value would fail it — and would therefore have to be
-- hidden as "sourced", which is the one thing this file must never do. A key
-- listed in `directional` is reported as DIRECTIONAL by that test instead of
-- being diffed against the pack. EVERY other key is still diffed exactly as
-- before, so the marker hides nothing it does not name.
--
-- WHAT IT LOOSENS: NOTHING. Every key in the schema is still REQUIRED in every
-- table (a directional key is one of them, not a replacement for it;
-- the set is Verdict.WEIGHT_KEYS's, which every table is validated against),
-- `source`
-- still carries SF.WEIGHTS_MARKER, and Verdict.weightsFor still refuses a table
-- WHOLE unless both hold. `directional` is OPTIONAL, and when present it is
-- VALIDATED (Verdict.weightsFor): it must be a table whose every entry names
-- one of those keys and is exactly `true` — a list of KEYS, never a place
-- to stash a value. An entry naming a key the table does not carry REFUSES the
-- table rather than being ignored: a marker pointing at nothing is a claim no
-- test could check.
-- ⚠ THE ANCHOR FORM. The format above says `review §<n>`; the review this card
-- cites (docs/research/deep-dive-weights-review-2026-10-17.md) carries NO
-- section-sign anchors — its headings are class subsections and a NUMBERED
-- prioritized change list. So the third field names that list's item instead
-- (`review item 6`), which is this card's own entry, plus the row inside the
-- per-class table the claim is read from. Written down here rather than
-- spelling a § against a document that has none.
--
-- FIRST SHIPPED USERS. Card DD-5 (t_19174d55) is the first: WARRIOR.tank
-- (BLOCK, AP, STR) and PALADIN.tank (HIT). Card DD-4 (t_721a287c) follows
-- with PALADIN.melee (INT), SHAMAN.melee (INT, SPI) and HUNTER.melee (INT,
-- SPI). Card DD-3 (t_6c3f414a) adds WDN on the two FERAL tables, DRUID.melee
-- (cat) and DRUID.tank (bear): a 6.0 placeholder no pack prices, so it is
-- DECLARED DIRECTIONAL and the citation diff reports it instead of diffing
-- it. Every table NOT named here carries no `directional` field and every
-- one of its numbers is still the cited pack's, diffed exactly as before.
--
-- THE RULE DD-5'S FOUR NUMBERS FOLLOW (stated once, so no value below is a
-- bare preference). The articles publish NO numbers, so a value here can
-- only carry the DIRECTION. Each one obeys three things:
--   (a) it moves UP from the shipped value and stays under the pack's own
--       survival primary (Stamina 1.0), so no tank trades Stamina away on
--       the strength of a placeholder;
--   (b) where this file already carries a price for the same stat or an
--       adjacent one, it is set at or just below HALF of it (AP -> the arms
--       pack's 0.45 gives 0.2; Block -> the survival primary 1.0 gives 0.5;
--       Prot HIT -> the ret pack's 0.7 gives 0.3), which is the most a
--       "direction only" reading can defend. WARRIOR.tank's HIT is NOT one of
--       those four: card t_ea260b42 prices it from a pack number — the same
--       spec's own `.dps` block — instead of halving one, so it makes no
--       DIRECTIONAL claim and is DIFFED like every cited key;
--   (c) it is enough for the card's own fixture to resolve, with the value
--       ONE STEP BELOW also measured so the crossing is a number in a test
--       rather than a claim in a comment. Those measurements are reproduced
--       in ChestAdvisor/tests/t_19174d55.js (AC-A/AC-B).
--
-- ── PROVENANCE: THE SUPERSEDE ────────────────────────────────────────────────
-- The owner RULED on 2026-10-04 (recorded in Verdict.lua, Tier C comment):
-- "Read the numbers. Order by prose. No stat weight anywhere." He SUPERSEDED
-- that ruling on 2026-10-13: "Supersede. Ship card 2 to your spec." This file
-- is card 2. The old ruling's three measured objections are NOT refuted by the
-- supersede and are answered here rather than ignored:
--   1. "No reliable stat KEY" — the original note made that call because the
--      UI-SOURCE REFERENCE EXTRACT it was searched on contains none of these
--      spellings. That was a fact about the extract, not about the client: the
--      live client demonstrably returns these keys (the addon's own hybrid
--      read was built on that finding, and the client ground-truth
--      inventory of 2026-10-04 — 133 keys pulled from the binary — enumerates
--      the vocabulary). Card t_795eee9e answers the objection the way that is
--      true: key on the SAME localized words the order table already uses, AND
--      on the client's own ITEM_MOD_* / RESISTANCE0* key spellings taken from
--      that verified inventory, which the hybrid reader (Verdict.apiStats)
--      resolves to the same words. Unverified keys stay unmapped and their
--      lines stay suppressive (AC-C).
--   2. No armor-proficiency API — unchanged, and out of scope: eligibility is
--      the client gate (Verdict.evaluate gate 3), not a weight.
--   3. WRONG REGIME at these levels — answered by the threshold and by the
--      fail-safes: a weighted margin below Verdict.WEIGHT_THRESHOLD leaves the
--      verdict TRADE_OFF, an unreadable line still suppresses, and a table
--      this file does not carry (or cannot validate) leaves the comparator
--      EXACTLY as it was. Weights never widen a verdict on absent data.
--
-- ── WHERE EVERY NUMBER COMES FROM ────────────────────────────────────────────
-- NOT measured on this build, and not invented here either. Every table below
-- is a transcription of one preset pack in the SISTER PROJECT's Classic model:
--
--   statforge-app/src/lib/statWeights.ts — `presets[<specId>][<mode>]`
--
-- ⚠ That model carries NO external citation for its own numbers either: the
-- only provenance note in the whole file is the `weaponDps` rationale at its
-- line 11-13. So this is a transfer of an unmeasured sibling estimate, which is
-- exactly what the per-table marker says. It is not evidence about this build.
--
-- That file ships two modes per spec: `dps` (output) and `survival`
-- (mitigation). This file takes ONE pack per spec —
--
--   * a damage spec ("melee" | "spell") takes that spec's `dps` pack;
--   * a tank spec ("tank") takes that spec's `survival` pack;
--
-- and it carries the keys this addon can read, priced from the pack each
-- table cites. The packs carry a wider vocabulary than the original eight,
-- and card t_795eee9e closes the gap for everything the client's verified key
-- inventory can name. Stated in three buckets, so a reader can see what moved
-- without diffing every table:
--
--   PRICED (the schema's current words): the original seven — strength,
--   agility, stamina, intellect, spirit, armor, blockValue (the BLOCK word —
--   the packs' ONE blockValue term; the client's Block line is that term) —
--   plus SPOW (spellPower, card t_b7cd07e1), the ten card t_795eee9e
--   added: hitRating -> HIT, critRating -> CRIT, attackPower -> AP,
--   rangedAttackPower -> RAP, mp5 -> MP5, hp5 -> HP5, defenseRating -> DEF,
--   dodgeRating -> DODGE, parryRating -> PARRY, weaponDps -> WDN — and FAP
--   (feral attack power, card t_3cdbb70a). Where the
--   pack prices one, the table carries the pack's own number; where it omits
--   one, the table carries the pack's own silence as a 0 — a 0 is the claim
--   "this pack prices the stat at nothing", and that is what the pack says.
--
--   UNIFIED HIT AND CRIT (card t_9d3273cb — replacing the SPLIT that was here):
--   every table carries the pack's hitRating on HIT and its critRating on CRIT,
--   caster and melee alike. There is ONE hit word and ONE crit word.
--
--   WHY THE SPLIT IS GONE. Card t_3cdbb70a (DD-1) split one pack number into
--   two words — one spelling for a caster table, the other for a melee one — on
--   the reasoning that a caster's melee-hit item and a warrior's spell-hit item
--   should be REFUSED rather than priced. The reasoning was sound about the
--   class and wrong about the GAME: on this client spell, melee and ranged hit
--   are one stat, and so are the three crits. The reviewer's ruling on card
--   t_9d3273cb cites the client's own recap, read verbatim:
--
--     "Spell, melee, and ranged hit chance are combined, as are spell, melee,
--      and ranged critical chance."
--
--   So a spell-hit item is not a different stat from a melee-hit item; it is
--   the same stat on a different item, and a caster prices it at the caster's
--   one hit number. A warrior's "+1% spell crit" is the same +1% crit he
--   already prices. The split therefore priced nothing that exists: its cost
--   was a caster's spell crit item pricing 0.6 x 14 = 8.4 through the retired
--   spell-side key while the SAME item read through Crit priced 0 — one stat,
--   the wrong one for every item whose client key was the spell spelling.
--
--   The client keys no longer split either: ITEM_MOD_HIT_MELEE_RATING,
--   ITEM_MOD_HIT_RANGED_RATING, the generic ITEM_MOD_HIT_RATING and
--   ITEM_MOD_HIT_SPELL_RATING all read HIT, and the four crit keys all read
--   CRIT (Verdict.lua). Ranged attack power keeps its own RAP word because the
--   client treats it as a separate stat and one cited pack (hunter-marksman)
--   prices it under that name — that is a different stat, not a different
--   spelling of hit.
--
--   FERAL (card t_3cdbb70a, DD-1 item 1): the client's ITEM_MOD_FERAL_ATTACK_
--   POWER now reads FAP, not AP. The Classic line is "Increases attack power by
--   N in Cat, Bear, Dire Bear, and Moonkin forms only" — worth nothing to a
--   Warrior, Paladin, Shaman, Hunter or Rogue, which is exactly the AP weight
--   t_795eee9e charged them for it. NO pack in the quote prices a feral term, so
--   FAP stays 0 on every table BUT ONE: card t_6c3f414a (DD-3) gives the feral
--   CAT table the pack's own attackPower (0.4), because for the one class that
--   can read a feral-AP line the question the term answers is the same one
--   attackPower answers. The bear keeps 0 (its survival block prices no attack
--   power at all), and no other table moves.
--
--   STILL DROPPED (pack vocabulary the addon has no word for): hasteRating
--   (no client key for a haste line is verified — such a line stays
--   suppressive, AC-E) and blockRating (a different term from the packs'
--   blockValue; the addon's BLOCK word is the blockValue read). The
--   school-specific terms were on this list until card t_4e1e1b1d (DD-2) gave
--   them words — SPHOLY..SPARCANE below — and they are priced where a pack
--   prices them, 0 otherwise; see the HEALING AND SCHOOL POWER note.
--
-- ── HEALING AND SCHOOL POWER (card t_4e1e1b1d, DD-2) ────────────────────────
-- Seven keys, one rule each, and the rule is the same rule the rest of this file
-- uses: a number is either the cited pack's own, or it is 0, or it is declared
-- DIRECTIONAL with its derivation written down. Nothing is inferred silently.
--
-- WHY THE WORDS EXIST. Before this card a healing-only line ("Equip: Increases
-- healing done by spells and effects by up to N.") and every school line
-- ("…damage done by Fire spells and effects…") were UNPLACEABLE in
-- Verdict.parseLine_, so the item suppressed and the player got no verdict at
-- all — the whole first row of review X1 (docs/research/deep-dive-weights-
-- review-2026-10-17.md, "X1. Equip lines Touchstone can't classify. HIGH").
-- The parser reads the seven sentences now and this file prices the words.
--
--   HEAL — healing power. NO PACK IN THE QUOTE PRICES A HEALING TERM (the app
--          has no healing entry in any of the sixteen packs this file cites),
--          so the four tables that serve a HEALER spec bridge it 1:1 from their
--          OWN SPOW value: PALADIN.spell 1.2, PRIEST.healer 0.8, SHAMAN.healer
--          1.0, DRUID.spell 1.0. Quote: none — the derivation is the absence.
--          Why 1:1 and not some fraction: the packs price spellPower as the
--          healer's output stat, and one point of healing power is one point of
--          spell power for a heal — the packs' own framing makes the two the
--          same quantity, so copying the price is the least inventive bridge
--          that can be defended. Review X1 ("add a HEAL word … each with its
--          own weight"). Every other table carries 0, and its row says so.
--          DECLARED: each of the four carries `directional = { HEAL = true }`
--          and its `source` names the override, so the citation diff reports
--          the key instead of pretending the pack gave the number.
--
--   SPHOLY — holy damage. 0 EVERYWHERE: no pack in the quote prices a holy
--          damage term, and review X1 leaves the per-spec call open ("Ret
--          Paladin … Disc/Holy Priest damage"). Card DD-4 owns that call; until
--          it lands, a holy line reads as worth nothing rather than as an
--          invented number.
--
--   SPFIRE / SPFROST / SPSHADOW / SPNATURE — the schools the packs DO price:
--          mage-frostfire spellDamageFire 1.0 and spellDamageFrost 1.0 on
--          MAGE.spell; warlock-destruction spellDamageShadow 1.0 and
--          spellDamageFire 0.8 on WARLOCK.spell; priest-shadow
--          spellDamageShadow 1.0 on PRIEST.spell/.damager; shaman-elemental
--          spellDamageNature 1.0 on SHAMAN.spell. Every other table 0 — the
--          review's own rule ("the pack's school price where one exists …
--          otherwise leave it unpriced").
--
--   SPARCANE — 0 EVERYWHERE. No pack in the quote prices an arcane term; the
--          review asks for the word (Arcane mage) and leaves the number to
--          DD-4, exactly like SPHOLY.
--
-- THE ONE JUDGEMENT CALL, NAMED. DRUID.damager is BRIDGED from priest-shadow
-- (see its entry) and that pack prices spellDamageShadow 1.0. This file prices
-- SPSHADOW 0 there anyway, DECLARED DIRECTIONAL: the shadow
-- term belongs to the PRIEST's spells, and a Balance druid's schools are Nature
-- and Arcane (review X1's own row names "Shadow Priest, Warlock" as the classes
-- a shadow line hurts — not Balance). Copying 1.0 would price a stat the class
-- cannot use at a price it was never measured at.
--
-- THE MAGE HIGHER-OF RULE lives in the comparator, not here (Verdict.lua,
-- `mageSchoolCollapse`): the packs price Fire and Frost separately, but "the
-- Frostfire Bolt always uses the higher of the Mage's spell damage bonuses to
-- Fire or Frost damage" (review X1 and the MAGE section), so the two terms are
-- max()ed for a Mage instead of summed. This file's job is to carry each price
-- truthfully; the class rule is a scoring rule.
--
-- Which pack a class/spec maps to is a judgement, so it is named
-- per class below and every claim about the choice is checkable in that file.
-- Two rules govern the gaps, and they are the only two judgement calls in this
-- file:
--
--   ARMOR, when the chosen pack omits it: the value comes from the SAME
--   spec's `survival` pack. Reason: the physical specs' dps packs do carry an
--   armor term (0.05) while the caster dps packs omit it altogether, and this
--   client prints an Armor line on every armour piece whatever the spec. A 0
--   there would be a substantive claim ("armor is worth nothing to a holy
--   paladin") that no source makes, so the same spec's own survival number is
--   used and the per-key comment says "bridged". No other key is bridged —
--   see BLOCK below.
--
--   BLOCK (and AGI/INT/SPI where absent): 0, from the chosen pack's own
--   silence. These are not universal: the dps packs omit block value because
--   block value is a TANK identity, and bridging it from a survival pack would
--   smuggle a tank model into a damage spec.
--
-- ── COVERAGE: ALL NINE CLASSES ──────────────────────────────────────────────
-- Card t_984bc8ac asked for coverage FIRST: WARRIOR (melee) and PALADIN
-- (spell | melee | tank), plus the hybrid-role picker specs shipped in 0.8.3
-- (SHAMAN melee | spell, DRUID spell). Card t_f823566a added the five classes
-- that were missing — the owner plays alts and was on a Priest for the
-- install-17 playtest, so an advisor that resolves trade-offs for four classes
-- is half a product. Every one of the five is a TRANSCRIPTION of a pack that
-- already existed in the same sister file, not an invention:
--
--   class    key(s)                     source pack (statWeights.ts presets)
--   HUNTER   melee                       hunter-marksman.dps
--   ROGUE    melee                       rogue-combat.dps
--   PRIEST   spell | damager | healer    priest-shadow.dps (spell, damager)
--                                        priest-holy.dps   (healer)
--   MAGE     spell                       mage-frostfire.dps
--   WARLOCK  spell                       warlock-destruction.dps
--
-- HOW A CLASS'S ONE PACK REACHES ITS ONE KEY (stated, not left to be
-- inferred): a class's key here is the word Verdict.ORDERS gives that class —
-- `melee` for HUNTER/ROGUE, `spell` for MAGE/PRIEST/WARLOCK — so
-- Verdict.weightsFor's step 3 (the pure-class fallback) reaches it with no
-- caller input at all. For HUNTER, ROGUE, MAGE and WARLOCK that key is also
-- the WHOLE story: the app lists exactly one spec for each
-- (classSpecs), that spec is the class default (getDefaultSpecForClass), and
-- tabSpecs maps all THREE of their talent tabs onto it — so there is no second
-- pack to reach, and a second key would be the same numbers twice. Those four
-- carry NO "damager" key on purpose; a client DAMAGER literal finds none and
-- folds onto the class's one key, which is the right answer rather than a
-- fallback, because there is no second pack for it to disagree with.
--
-- PRIEST is the exception, and the reason the literal vocabulary exists at all.
-- It is a PURE class — one order word, `spell` — with TWO packs. Its `spell`
-- key is the app's class DEFAULT (getDefaultSpecForClass('PRIEST') is
-- 'priest-shadow': classSpecs lists priest-shadow before priest-holy; note
-- that tabSpecs.PRIEST is ['priest-holy','priest-holy','priest-shadow'], so
-- the default and the first talent tab genuinely differ and the choice is named
-- rather than left to a tab) and it prices the Shadow spec. Holy is reachable
-- ONLY through the client's own HEALER literal, so `healer` carries
-- priest-holy.dps and `damager` carries the same Shadow spec as `spell` — the
-- SAME table object, not a copy: two tables holding the same numbers would be
-- one claim made twice, and could drift apart.
--
-- This is what does NOT, and why — an absent table is more honest than a
-- fabricated one, and the comparator's ordinal path is unchanged without it:
--   * WARRIOR.spell / "healer", PALADIN."damager" — not vocabulary this addon
--     has: a Warrior's order has one role (melee) and a Paladin's third spec
--     is the client TANK literal. Absent keys cost nothing; the resolver falls
--     through to the role word.
--     (DRUID.melee USED to be in this list — card t_03a1196c left it with no
--     order, so no table there could ever be consulted. Card t_6c3f414a (DD-3)
--     gives it the feral order and TWO tables, DRUID.melee for the cat and
--     DRUID.tank for the bear; see the DRUID section below.)
--   * A SPELL POWER weight — IN the schema, by the owner's ruling (card
--     t_b7cd07e1: "Spell power gets a weight from the packs"). It is the SPOW
--     word, the same word parseLine_ already produces and the API
--     reconciliation already names, priced from the pack each table cites:
--     the pack's own spellPower where the pack prices it, and an honest 0
--     where it does not. What the ruling did NOT price: the school-specific
--     terms, below.
--   * The SCHOOL-specific damage terms the caster packs price — spellDamageShadow
--     (priest-shadow, warlock-destruction), spellDamageFrost / spellDamageFire
--     (mage-frostfire), spellDamageNature (shaman-elemental) — USED TO be
--     dropped here for want of a word. Card t_4e1e1b1d (DD-2) adds one key per
--     school (SPHOLY..SPARCANE), prices each pack's own term where it exists and
--     0 elsewhere, and gives the Mage the higher-of rule the class article
--     states. See the HEALING AND SCHOOL POWER note above for the full rule and
--     the one judgement call (the bridged DRUID table's shadow term).
--     A trade-off whose only gain is a school bonus IS resolved by weights now,
--     on the classes whose pack prices that school.
--   * HUNTER.SPI — the pack (hunter-marksman.dps) is silent on spirit and this
--     file bridges ONE key, armor, not a list. The same spec's survival pack
--     does price spirit at 0.2, so the value exists; it is not borrowed,
--     because a survival pack's mana/hp5 shape is a different model. Stated
--     limitation: a Spirit loss on a Hunter item contributes 0 to the sum.
--   * A "damager" key on HUNTER/ROGUE/MAGE/WARLOCK — each has exactly one pack,
--     so the client's DAMAGER literal folds onto that class's one key and a
--     second key would hold the same numbers (see the COVERAGE note above).
--
-- ── SPEC COVERAGE: ALL 28 CLASSIC SPECS (card t_0e5381e1; 28 since DD-3) ─────
-- The card asks for every Classic SPEC, not just every class. That can only be
-- answered the way this addon RESOLVES: Verdict.weightsFor(class, role,
-- clientRole) keys a table by the CLASS plus a ROLE WORD ("melee" | "spell") or
-- the CLIENT's own role literal ("tank" | "healer" | "damager"). The spec NAME
-- is never read — ChestAdvisor.lua's buildSpec passes class + resolved role word
-- + client literal and nothing else. So two talent specs of one class that share
-- both a role word and a literal share ONE table, and the "bridge" for the
-- second spec is that SHARED KEY, not a second table carrying the same numbers:
-- a second key holding the same numbers would be one claim made twice and could
-- drift (the rule the COVERAGE note above and the PRIEST note below both state).
-- Card t_0e5381e1 added DRUID.damager (Balance) — see there. Card t_6c3f414a
-- (DD-3) added the FERAL pair, DRUID.melee (cat) and DRUID.tank (bear): two
-- tables, not a fold, because the two specs price stamina differently (0.4 vs
-- 1.0) and one key could not serve both.
--
-- Dispositions: SRC = the table that serves this spec cites its OWN pack;
-- BRIDGED = the spec has no pack of its own and is served by a sibling's, with
-- the source pack named; FALLBACK = NO TABLE IS CONSULTED on this spec's
-- VERDICT path. ⚠ FALLBACK IS RETIRED as of card t_6c3f414a: its single row
-- (DRUID Feral) now resolves, and no row carries the disposition. The word is
-- kept here because the ledger in ChestAdvisor/tests/weights_spec_coverage.js
-- ASSERTS that the retired list is empty — a disposition nothing can redden is
-- worse than one that no longer applies. Confidence notes are on every BRIDGED
-- row; the least-certain row is flagged.
--
--   ⚠ DIRECTIONAL is a per-KEY marker, not a row disposition — it never appears
--   as a disposition, because it is about a single KEY inside a table, not about
--   which table serves a spec. A key marked DIRECTIONAL deliberately overrides
--   the pack the table cites, and declares that in the table's own `directional`
--   field; see the DIRECTIONAL section at the head of this file. Since DD-3 the
--   two feral rows list the keys they declare: WDN on both.
--
--   spec              class    role mapping                 disposition   served by       source pack
--   -------------------------------------------------------------------------------------------------
--   Arms              WARRIOR  word melee, lit DAMAGER      SRC           WARRIOR.melee   warrior-arms.dps
--   Fury              WARRIOR  word melee, lit DAMAGER      BRIDGED       WARRIOR.melee   warrior-arms.dps
--   Protection        WARRIOR  word melee, lit TANK         SRC           WARRIOR.tank    warrior-prot.survival
--   Retribution       PALADIN  word melee, lit DAMAGER      SRC           PALADIN.melee   paladin-ret.dps
--   Holy              PALADIN  word spell, lit HEALER       SRC           PALADIN.spell   paladin-holy.dps
--   Protection        PALADIN  word spell, lit TANK         SRC           PALADIN.tank    paladin-prot.survival
--   Elemental         SHAMAN   word spell, lit DAMAGER      SRC           SHAMAN.spell    shaman-elemental.dps
--   Enhancement       SHAMAN   word melee, lit DAMAGER      SRC           SHAMAN.melee    shaman-enhancement.dps
--   Restoration       SHAMAN   word spell, lit HEALER       SRC           SHAMAN.healer   shaman-resto.dps
--   Balance           DRUID    word spell, lit DAMAGER      BRIDGED       DRUID.damager   priest-shadow.dps
--   Feral (cat)       DRUID    word melee, lit DAMAGER      SRC           DRUID.melee     druid-feral.dps
--                                                                          DIRECTIONAL: WDN
--   Feral (bear)      DRUID    word melee, lit TANK         SRC           DRUID.tank      druid-feral.survival
--                                                                          DIRECTIONAL: WDN
--   Restoration       DRUID    word spell, lit HEALER       SRC           DRUID.spell     druid-resto.dps
--   Beast Mastery     HUNTER   word melee, lit DAMAGER      BRIDGED       HUNTER.melee    hunter-marksman.dps
--   Marksmanship      HUNTER   word melee, lit DAMAGER      SRC           HUNTER.melee    hunter-marksman.dps
--   Survival          HUNTER   word melee, lit DAMAGER      BRIDGED       HUNTER.melee    hunter-marksman.dps
--   Assassination     ROGUE    word melee, lit DAMAGER      BRIDGED       ROGUE.melee     rogue-combat.dps
--   Combat            ROGUE    word melee, lit DAMAGER      SRC           ROGUE.melee     rogue-combat.dps
--   Subtlety          ROGUE    word melee, lit DAMAGER      BRIDGED       ROGUE.melee     rogue-combat.dps
--   Discipline        PRIEST   word spell, lit HEALER       BRIDGED       PRIEST.healer   priest-holy.dps
--   Holy              PRIEST   word spell, lit HEALER       SRC           PRIEST.healer   priest-holy.dps
--   Shadow            PRIEST   word spell, lit DAMAGER      SRC           PRIEST.damager  priest-shadow.dps
--   Arcane            MAGE     word spell, lit DAMAGER      BRIDGED       MAGE.spell      mage-frostfire.dps
--   Fire              MAGE     word spell, lit DAMAGER      BRIDGED       MAGE.spell      mage-frostfire.dps
--   Frost             MAGE     word spell, lit DAMAGER      SRC           MAGE.spell      mage-frostfire.dps
--   Affliction        WARLOCK  word spell, lit DAMAGER      BRIDGED       WARLOCK.spell   warlock-destruction.dps
--   Demonology        WARLOCK  word spell, lit DAMAGER      BRIDGED       WARLOCK.spell   warlock-destruction.dps
--   Destruction       WARLOCK  word spell, lit DAMAGER      SRC           WARLOCK.spell   warlock-destruction.dps
--
--   Every BRIDGED row above is a FOLD, and every one is the same claim: the key
--   that serves the row holds the numbers its `source` names, and no second pack
--   the client could reach disagrees with them. It comes about in three ways,
--   and they are NOT the same argument:
--     * ONE PACK PER ROLE (Hunter, Rogue, Mage, Warlock): the class has exactly
--       one pack for that role, so there is no second pack a literal could
--       reach, and the shared key IS the sibling's numbers — not a copy.
--       Hunter's three tabs are all 'hunter-marksman' in the app's own
--       tabSpecs.HUNTER, Rogue's all 'rogue-combat', Mage's all
--       'mage-frostfire' (which the app names Frost/Fire), Warlock's all
--       'warlock-destruction'. HIGH confidence: the app lists one pack and maps
--       every tab to it.
--     * A SECOND PACK THAT PROJECTS IDENTICALLY? NO — and card t_795eee9e
--       changes the old claim here, stated plainly: warrior-arms.dps and
--       warrior-fury.dps differ in critRating (1.2 / 1.3), hitRating (0.8 /
--       0.9) and hasteRating (0.4 / 0.5). Before t_795eee9e the addon had no
--       word for all three, so the two packs were indistinguishable to the
--       weights and the arms/fury choice could not move a verdict — that was
--       the basis of the HIGH-confidence call. After t_795eee9e, HIT (arms 0.8,
--       fury 0.9) and CRIT (arms 1.2, fury 1.3) are words the packs price, so
--       the two packs NO LONGER project identically: a Warrior pair whose
--       trade-off carries a point of Hit or Crit is now decided by WHICH pack's
--       numbers the table carries. This file carries warrior-arms (the class
--       default, the documented choice at the table below) — the card t_795eee9e
--       rule is "price from the pack the table cites", not "use the better
--       pack", and switching to fury's numbers would be a different claim
--       nobody ruled. Consequence, not hidden: the changed-verdicts sweep
--       (docs/t_6696b35a-changed-verdicts.txt) is exactly the record of any
--       pinned pair that moves because of it, and that move is REPORTED with
--       this comment, not papered over.
--     * A LITERAL THAT PUBLISHES THE SPEC, no fold needed (Priest): Holy and
--       Discipline are both HEALER roles on the client and reach the one
--       `healer` key. HIGH for Holy; MEDIUM for Discipline — the client's role
--       literal decides it (inferred HEALER for Disc; the spec read is itself
--       UNTESTED BY US, see ChestAdvisor.lua) and a client that reported DAMAGER
--       would reach the Shadow pack instead.
--
--   THE FERAL PAIR (card t_6c3f414a, DD-3) — what replaced the one FALLBACK row.
--   Until DD-3, DRUID Feral was this file's single FALLBACK: classRoleOrder
--   ('DRUID','melee') was nil (NO_ORDER), so ChestAdvisor.lua answered "no stat
--   order resolved for this character" before the comparator was called, and
--   nothing was consulted. DD-3 gives that role the feral order
--   (strength > agility > stamina, from presets['druid-feral'].dps) and prices TWO
--   tables, and the two claims below are the ones the retired row used to deny:
--     * THE ROLE PATH RESOLVES. weightsFor('DRUID','melee',nil) returns
--       DRUID.melee — the CAT — so a feral druid who has picked `melee` in the
--       addon (the only vocabulary that can tell a cat from a Balance druid) is
--       judged, on the pack the feral PLAYER uses.
--     * THE LITERAL TELLS THE TWO PHYSICAL SPECS APART, and only in one
--       direction. A bear's client role is TANK, which ROLE_ALIAS.DRUID folds to
--       `melee` for the ORDER and which weightsFor resolves to DRUID.tank through
--       the literal — the PALADIN.tank pattern exactly. A CAT's client role is
--       DAMAGER, the SAME literal a Balance druid carries, so
--       Verdict.LITERAL_NEEDS_ROLE refuses that literal for a `melee` character:
--       without it a cat would be judged by the BALANCE pack (Intellect 0.8,
--       Strength 0) — the R5 defect in a new costume. Balance still reaches
--       DRUID.damager, because its resolved role IS `spell`.
--   Both halves are asserted by EXECUTION — not by this comment — in
--   ChestAdvisor/tests/weights_spec_coverage.js (the ledger row, the literal
--   matrix, and eight driven mutations) and in
--   ChestAdvisor/tests/t_6c3f414a.js (the card's own AC-A..AC-F battery).
--
--   ⚠ LEAST-CERTAIN ROW, flagged as the owner asked: DRUID Balance. Its table is
--   the one BRIDGE this card ADDS, it is a CROSS-CLASS borrow (no caster-DPS pack
--   exists inside the druid class), and no source measures a moonkin. See the
--   DRUID.damager entry below for the comparison that chose it.
--
--   ✔ CLOSED (card t_c222ff40). The one WRONG PACK row this table used to carry
--   was SHAMAN Restoration: it has its OWN pack (shaman-resto.dps) but no
--   `healer` key reached it, so a Resto shaman (client literal HEALER) fell
--   through the role word `spell` onto the ELEMENTAL pack — a caster DPS shape
--   served to a healer, silently. Card t_0e5381e1 REPORTED that rather than
--   repaired it (its scope was the ten specs it named); card t_c222ff40 adds
--   the one key, and the row above now reads SRC. Two things stated plainly,
--   because an SRC row invites the reader to assume more than it means:
--     * shaman-resto's projection onto this file's current vocabulary is
--       IDENTICAL to shaman-elemental's — the two packs differ only in
--       spellDamageNature 1.0,
--       which this file cannot read (see the SPELL POWER and school-term notes
--       above). So NO player-facing number moves with this fix. What moves is
--       the TABLE: the spec is now served by its own pack, cited truthfully,
--       instead of by a sibling's.
--     * the guard is therefore the resolution IDENTITY, not a moved verdict:
--       weights_spec_coverage.js asserts the table that comes back IS
--       SHAMAN.healer, and its -nonvacuity companion reddens BY NAME when that
--       key is deleted. `spell` is deliberately NOT renamed and NOT aliased to
--       the new table: alias it and the ELEMENTAL pack would be published as the
--       HEALER one, which is the defect rather than the fix (and would take the
--       fail-closed guard off the Elemental/DAMAGER literal — see the entry).
--
-- ── READING THIS FILE AS A CLAIM ─────────────────────────────────────────────
-- It is NOT one. It is a transferred estimate carried into this addon on the
-- owner's instruction, with the transfer labelled on every table. The player
-- must never be shown a number that implies more certainty than the data has —
-- which is why the comparator discloses the deciding stat in words, discloses
-- the loss it accepted, and refuses to run at all when this table is missing.

StatForge = StatForge or {}
local SF = StatForge

-- The verbatim marker every table must carry. Spelled ONCE, here, so the
-- label the validator looks for and the label the tables carry cannot drift.
local MARKER = "UNVERIFIED — transferred from Classic Era level-60 raiding, NOT measured on this build"

SF.WEIGHTS_MARKER = MARKER

-- ── THE ONE TABLE TWO KEYS SHARE ────────────────────────────────────────────
-- PRIEST.spell (the addon's own role word for a priest, and the app's class
-- DEFAULT for the class) and PRIEST.damager (the client's DAMAGER literal) are
-- the SAME spec — presets['priest-shadow'].dps. Declared once here and
-- referenced twice inside SF.Weights below, so the two keys cannot drift
-- apart: a second inline table would be one claim made twice, and the two
-- copies could silently diverge. Every other table in this file is inline.
local PRIEST_SHADOW = {
	STR   = 0,     -- absent from the pack
	AGI   = 0,     -- absent from the pack
	STA   = 0.3,   -- source key: stamina 0.3
	INT   = 0.8,   -- source key: intellect 0.8
	SPI   = 0.6,   -- source key: spirit 0.6
	ARMOR = 0.2,   -- BRIDGED: the dps pack omits armor; the same spec's
	               -- survival pack armor 0.2
	BLOCK = 0,     -- absent from the pack
	-- card t_795eee9e: priced from its own pack (priest-shadow.dps); the
	-- DRUID.damager bridge carries the same ten values — it is the same pack
	HIT   = 0.4,   -- source key: hitRating 0.4 (ONE word since card t_9d3273cb)
	CRIT  = 0.5,   -- source key: critRating 0.5 (ONE word since card t_9d3273cb)
	AP    = 0,     -- absent from the pack
	FAP   = 0,     -- 0: no pack in the quote prices a feral term (card t_3cdbb70a; DD-3 re-prices it)
	RAP   = 0,     -- absent from the pack
	MP5   = 0.6,   -- source key: mp5 0.6
	HP5   = 0,     -- absent from the pack
	DEF   = 0,     -- absent from the pack (a survival term)
	DODGE = 0,     -- absent from the pack (a survival term)
	PARRY = 0,     -- absent from the pack (a survival term)
	WDN   = 0,     -- absent from the pack (no weapon term for a caster spec)
	HEAL    = 0,     -- 0: no pack prices a healing term (card t_4e1e1b1d; the healer tables bridge it)
	SPHOLY  = 0,     -- 0: no pack in the quote prices a holy damage term (card t_4e1e1b1d; DD-4 prices it per spec)
	SPFIRE  = 0,     -- absent from the pack (card t_4e1e1b1d)
	SPFROST = 0,     -- absent from the pack (card t_4e1e1b1d)
	SPSHADOW = 1.0,   -- source key: spellDamageShadow 1.0 (card t_4e1e1b1d)
	SPNATURE = 0,     -- absent from the pack (card t_4e1e1b1d)
	SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
	SPOW  = 1.2,   -- source key: spellPower 1.2 (card t_b7cd07e1)
	source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['priest-shadow'].dps (ARMOR bridged from the same spec's .survival pack).",
}

SF.Weights = {
	-- ── WARRIOR ─────────────────────────────────────────────────────────────
	WARRIOR = {
		-- presets['warrior-arms'].dps — the app's Warrior pack for the class's
		-- FIRST talent tab (statWeights.ts tabSpecs.WARRIOR[0] = 'warrior-arms';
		-- it is also the class default, getDefaultSpecForClass/WARRIOR).
		-- (Its 'warrior-fury' pack differs only in critRating 1.3 vs 1.2,
		-- hitRating 0.9 vs 0.8, hasteRating 0.5 vs 0.4. The old file said the
		-- arms/fury choice could not move a verdict because this addon read
		-- none of the three — card t_795eee9e changed that: HIT and CRIT are
		-- words now, so the choice DOES decide a pair that trades a point of
		-- Hit or Crit. This table carries ARMS, the class default — the
		-- COVERAGE note above states that consequence plainly rather than
		-- hiding it.)
		melee = {
			STR   = 1.0,   -- source key: strength 1.0
			AGI   = 0.6,   -- source key: agility 0.6
			STA   = 0.3,   -- source key: stamina 0.3
			INT   = 0,     -- absent from the pack (no intellect term)
			SPI   = 0,     -- absent from the pack
			ARMOR = 0.05,  -- source key: armor 0.05 (the pack carries it — not bridged)
			BLOCK = 0,     -- absent from the pack (blockValue is a survival term)
			-- card t_795eee9e: priced from its own pack (warrior-arms.dps)
			HIT   = 0.8,   -- source key: hitRating 0.8 (ONE word since card t_9d3273cb)
			CRIT  = 1.2,   -- source key: critRating 1.2 (ONE word since card t_9d3273cb)
			AP    = 0.45,  -- source key: attackPower 0.45
			FAP   = 0,     -- 0: no pack in the quote prices a feral term (card t_3cdbb70a; DD-3 re-prices it)
			RAP   = 0,     -- absent from the pack (no ranged term for a melee spec)
			MP5   = 0,     -- absent from the pack
			HP5   = 0,     -- absent from the pack
			DEF   = 0,     -- absent from the pack (a survival term)
			DODGE = 0,     -- absent from the pack (a survival term)
			PARRY = 0,     -- absent from the pack (a survival term)
			WDN   = 6.0,   -- source key: weaponDps 6.0
			HEAL    = 0,     -- 0: no pack prices a healing term (card t_4e1e1b1d; the healer tables bridge it)
			SPHOLY  = 0,     -- 0: no pack in the quote prices a holy damage term (card t_4e1e1b1d; DD-4 prices it per spec)
			SPFIRE  = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFROST = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPSHADOW = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPNATURE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPOW  = 0,   -- absent from the pack (card t_b7cd07e1)
			source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['warrior-arms'].dps.",
		},
		-- presets['warrior-prot'].survival — a Protection warrior's OWN pack.
		-- Without it a prot warrior would be judged by the arms/fury numbers
		-- above: ROLE_ALIAS maps WARRIOR TANK -> "melee" for the ORDER, and the
		-- wrong-regime objection applies to a weight table exactly as it did to
		-- a raid-tuned one. The ORDER (a melee order) still words the reason;
		-- these numbers decide a tie.
		--
		-- EVERY key below is that ONE pack — with the single DECLARED BRIDGE named
		-- at HIT (card t_ea260b42): the survival block carries no hit term, so HIT
		-- is the same spec's `.dps` hitRating, declared as data in
		-- ChestAdvisor/tests/weights_citation_packs.json and derived there from the
		-- dps block. Nothing else here is blended, and nothing is taken from
		-- warrior-arms.survival (which happens to
		-- share this pack's 0.3 agility but prices strength at 0.4). STR was
		-- 0.4 in this file's first revision and was corrected to the cited 0.5
		-- by card t_6fda2ec5's gate (t_9362815f, F1): 0.4 is a value from a
		-- DIFFERENT pack, and this file's own rules allow no unlabelled
		-- deviation. Measured effect of the correction: three plausible Prot
		-- shield pairs that trade a point of Strength for Stamina and Armor
		-- read UPGRADE where 0.4 read TRADE_OFF — named in
		-- docs/t_984bc8ac-changed-verdicts.txt.
		tank = {
			-- DIRECTIONAL: "Sunder Armor: Threat generated now scales with Attack
			-- Power." / "Thunder Clap: Now gains significant damage scaling from
			-- Attack Power." | 0.5 -> 0.6: the threat half of Strength rises with
			-- the new AP term (Strength is a warrior's AP source); one conservative
			-- step, and still well below the pack's survival primary Stamina 1.0, so
			-- no shield pair trades Stamina away for Strength on this number alone
			-- | review item 6 (WARRIOR / Protection: "AP / STR (threat)")
			STR   = 0.6,
			AGI   = 0.3,   -- source key: agility 0.3
			STA   = 1.0,   -- source key: stamina 1.0
			INT   = 0,     -- absent from the pack
			SPI   = 0,     -- absent from the pack
			ARMOR = 0.35,  -- source key: armor 0.35
			-- DIRECTIONAL: "Shield Slam: Damage scaling from Block Value increased."
			-- | 0.35 -> 0.5: half the survival primary, so one point of Block is
			-- worth at most half a point of Stamina. ⚠ CARD t_ea260b42 RETIRED THE
			-- MEASUREMENT THIS NUMBER WAS RAISED FOR: the old note here said the
			-- card's shield fixture (+19 Block / +5 Strength / equal Armor against
			-- +3 Block / +3 Stamina) "reads TRADE_OFF at the shipped 0.35 and
			-- UPGRADE at 0.40 and above". It no longer does, and it must not: a
			-- PROOF_EXEMPT price is TIEBREAK-ONLY and the weighted layer does not
			-- spend it (see the rule below), so that pair is a TRADE_OFF at every
			-- price. The number stays as DD-5 ruled it and as the coverage record;
			-- what changed is the layer that was reading it.
			-- | review item 6 (WARRIOR / Protection: "BLOCK (block value) 0.35 ->
			-- Up", confidence medium-high on DIRECTION)
			BLOCK = 0.5,
			-- ⚠ THE RULE THE BLOCK PRICE OBEYS (card t_ea260b42). It is the
			-- engine's rule, stated beside the number because this is the table a
			-- reader will ask about: BLOCK is TIEBREAK-ONLY, with Armor and
			-- WeaponDps, in `Verdict.PROOF_EXEMPT`. The dominance proof may not
			-- read it (it cannot overturn a class-order loss), and since
			-- t_ea260b42 the WEIGHTED LAYER may not SPEND it either. The ONE place
			-- it can speak is gate 9's tiebreak: a pair where nothing else moved
			-- and BOTH sides carry the stat. So "+20 Block vs +10 Block" is an
			-- upgrade (a tiebreak deciding a tie, W4c), while "+1 Hit vs +20 Block"
			-- is not a comparison of Block at all — the Hit moves and Block is
			-- silent (W4e), which is exactly what it does on the trade-off pair
			-- W4f. Before this card the weighted layer DID spend it, so the same
			-- 40 Block decided a trade-off pair ("better on Block — the weighted
			-- gain outweighs the Stamina loss") and was invisible on a one-sided
			-- one: one number, two answers. The number above is unchanged; only
			-- the layer that was reading it out of turn is.
			--
			-- card t_795eee9e, RE-PRICED by card t_ea260b42: HIT is BRIDGED from
			-- the SAME SPEC's `.dps` block — hitRating 0.5 in
			-- presets['warrior-prot'].dps. The `.survival` block this table
			-- otherwise transcribes carries NO hit term at all, so the old `0` here
			-- was not the pack's number: it was the absence of one, and a warrior
			-- tank's Hit was therefore never weighed by anything (t_eb6ecf0e's
			-- W4e: "+1 Hit vs +20 Block" read "equal to what's equipped"). The app
			-- prices a Protection warrior's hit at 0.5 in its OWN dps block; that
			-- is the only pack number this spec has for this word, so it is
			-- CARRIED rather than invented — a tank buys hit for the taunt and the
			-- threat it carries, which is the reason PALADIN.tank gives for its
			-- own hit price. The bridge is declared as DATA
			-- (ChestAdvisor/tests/weights_citation_packs.json carries
			-- "bridges": { "HIT": "dps" } on this pack), so the citation diff
			-- DERIVES 0.5 from the dps block instead of being skipped: this is a
			-- sourced number, not a directional judgement, and it is deliberately
			-- NOT listed in `directional` below.
			HIT   = 0.5,
			CRIT  = 0,     -- the pack prices it at nothing (ONE word since card t_9d3273cb)
			-- DIRECTIONAL: "Sunder Armor: Threat generated now scales with Attack
			-- Power." / "Thunder Clap: Now gains significant damage scaling from
			-- Attack Power. Useable in Defensive Stance." | 0 -> 0.2: the pack has
			-- no attackPower term at all, so there is nothing to cite and the value
			-- is set from the ONE AP price this file already carries (warrior-arms
			-- 0.45), taking just under half of it because a tank converts AP into
			-- THREAT, not damage. The card's +40 AP / +5 Strength vs +3 Stamina
			-- fixture reads TRADE_OFF at 0 and at 0.1, UPGRADE at 0.15 and above
			-- | review item 6 (WARRIOR / Protection: "AP up from 0")
			AP    = 0.2,
			FAP   = 0,     -- 0: no pack in the quote prices a feral term (card t_3cdbb70a; DD-3 re-prices it)
			RAP   = 0,     -- absent from the pack
			MP5   = 0,     -- absent from the pack
			HP5   = 0.3,   -- source key: hp5 0.3
			DEF   = 1.3,   -- source key: defenseRating 1.3
			DODGE = 1.1,   -- source key: dodgeRating 1.1
			PARRY = 0.9,   -- source key: parryRating 0.9
			WDN   = 0,     -- absent from the pack (the dps packs price it, not survival)
			HEAL    = 0,     -- 0: no pack prices a healing term (card t_4e1e1b1d; the healer tables bridge it)
			SPHOLY  = 0,     -- 0: no pack in the quote prices a holy damage term (card t_4e1e1b1d; DD-4 prices it per spec)
			SPFIRE  = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFROST = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPSHADOW = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPNATURE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPOW  = 0,   -- absent from the pack (card t_b7cd07e1)
			source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['warrior-prot'].survival; HIT (0.5) is BRIDGED from the same spec's .dps block's hitRating, which the survival block it cites does not carry (card t_ea260b42).",
			-- card DD-5: the three overrides above, DECLARED so the citation diff
			-- reports them as DIRECTIONAL instead of diffing them against the
			-- warrior-prot.survival pack they deliberately leave (every OTHER key in
			-- this table is still that pack's number, and still diffed).
			directional = { BLOCK = true, AP = true, STR = true },
		},
	},
	-- ── PALADIN ─────────────────────────────────────────────────────────────
	PALADIN = {
		-- presets['paladin-ret'].dps — the melee order's spec (str>int>sta).
		-- Ret is the addon's `melee` shape: the app's PALADIN packs are holy
		-- (healer), prot (tank) and ret (dps), and ret is the only physical one.
		melee = {
			STR   = 1.0,   -- source key: strength 1.0
			AGI   = 0.5,   -- source key: agility 0.5
			STA   = 0.3,   -- source key: stamina 0.3
			-- card DD-4 (t_721a287c): Champion of the Light makes Intellect feed
			-- damage for a Retribution paladin, so the mana-pool reading below is
			-- no longer the whole story.
			-- THE QUOTE: "Champion of the Light: Increases your spell damage by
			-- up to 30% of your Intellect." The same paragraph also says "we
			-- reduced that value to 60%", so the article contradicts itself on the
			-- RATE. This table takes the SMALLER reading and records the other
			-- rather than picking one silently.
			-- THE DERIVATION: 30% of one point of Intellect is 0.3 points of spell
			-- damage, and this table prices one point of spell power at 0.3
			-- (presets['paladin-ret'].dps spellPower 0.3, the SPOW word from card
			-- t_b7cd07e1). 0.30 x 0.3 = 0.09. The 60% reading would be 0.18.
			-- UNRESOLVED, and named as unresolved: which rate is live. The
			-- article's own text would settle it if it were internally
			-- consistent, and the client's tooltip for the talent would settle it
			-- outright; neither is available to this repo. A card that owns the
			-- contradiction moves this number, not this one.
			INT   = 0.09,
			SPI   = 0,     -- absent from both paladin-ret packs. card DD-4 prices
			               -- it for the hunter and the shaman and does NOT price it
			               -- here: Reverence ("Grants the Paladin up to 30% of
			               -- their mana regeneration from Spirit while casting")
			               -- buys REGENERATION, not output, and Champion of the
			               -- Light above turns Intellect, not Spirit, into damage.
			               -- Spirit rides along only where the conversion exists
			               -- (review section X4, paladin row).
			ARMOR = 0.05,  -- source key: armor 0.05 (carried — not bridged)
			BLOCK = 0,     -- absent from the pack
			-- card t_795eee9e: priced from its own pack (paladin-ret.dps)
			HIT   = 0.7,   -- source key: hitRating 0.7 (ONE word since card t_9d3273cb)
			CRIT  = 1.0,   -- source key: critRating 1.0 (ONE word since card t_9d3273cb)
			AP    = 0.4,   -- source key: attackPower 0.4
			FAP   = 0,     -- 0: no pack in the quote prices a feral term (card t_3cdbb70a; DD-3 re-prices it)
			RAP   = 0,     -- absent from the pack (no ranged term for a melee spec)
			MP5   = 0,     -- absent from the pack
			HP5   = 0,     -- absent from the pack
			DEF   = 0,     -- absent from the pack (a survival term)
			DODGE = 0,     -- absent from the pack (a survival term)
			PARRY = 0,     -- absent from the pack (a survival term)
			WDN   = 6.0,   -- source key: weaponDps 6.0
			HEAL    = 0,     -- 0: no pack prices a healing term (card t_4e1e1b1d; the healer tables bridge it)
			SPHOLY  = 0,     -- 0: no pack in the quote prices a holy damage term (card t_4e1e1b1d; DD-4 prices it per spec)
			SPFIRE  = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFROST = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPSHADOW = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPNATURE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPOW  = 0.3,   -- source key: spellPower 0.3 (card t_b7cd07e1)
			source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['paladin-ret'].dps. DIRECTIONAL override, NOT sourced: INT (Champion of the Light, card DD-4 t_721a287c).",
			directional = { INT = true },
		},
		-- presets['paladin-holy'].dps — the spell order's spec (int>sta>str).
		-- Holy is the app's FIRST TALENT TAB for a paladin
		-- (tabSpecs.PALADIN[0] = 'paladin-holy'), and the addon's paladin
		-- `spell` order is the caster shape. NOT the class default, though this
		-- comment said so in the file's first revision (audit finding, card
		-- t_6fda2ec5): classSpecs lists paladin-ret FIRST, so
		-- getDefaultSpecForClass('PALADIN') is 'paladin-ret'. The choice does
		-- not rest on the default either way — Ret is the `melee` key above.
		spell = {
			STR   = 0,     -- absent from the pack (no strength term for Holy)
			AGI   = 0,     -- absent from the pack
			STA   = 0.3,   -- source key: stamina 0.3
			INT   = 0.8,   -- source key: intellect 0.8
			SPI   = 0.6,   -- source key: spirit 0.6
			ARMOR = 0.2,   -- BRIDGED: the dps pack omits armor; this is the same
			               -- spec's survival pack armor 0.2 (see the ARMOR rule above)
			BLOCK = 0,     -- absent from the pack
			-- card t_795eee9e: priced from its own pack (paladin-holy.dps)
			HIT   = 0,     -- absent from the pack (ONE word since card t_9d3273cb)
			CRIT  = 0.6,   -- source key: critRating 0.6 (ONE word since card t_9d3273cb)
			AP    = 0,     -- absent from the pack
			FAP   = 0,     -- 0: no pack in the quote prices a feral term (card t_3cdbb70a; DD-3 re-prices it)
			RAP   = 0,     -- absent from the pack
			MP5   = 1.2,   -- source key: mp5 1.2
			HP5   = 0,     -- absent from the pack
			DEF   = 0,     -- absent from the pack (a survival term)
			DODGE = 0,     -- absent from the pack (a survival term)
			PARRY = 0,     -- absent from the pack (a survival term)
			WDN   = 0,     -- absent from the pack (no weapon term for a caster spec)
			HEAL    = 1.2,   -- DIRECTIONAL: no pack prices a healing term; bridged 1:1 from this table's own SPOW (card t_4e1e1b1d; review X1)
			SPHOLY  = 0,     -- 0: no pack in the quote prices a holy damage term (card t_4e1e1b1d; DD-4 prices it per spec)
			SPFIRE  = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFROST = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPSHADOW = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPNATURE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPOW  = 1.2,   -- source key: spellPower 1.2 (card t_b7cd07e1)
			source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['paladin-holy'].dps (ARMOR bridged from the same spec's .survival pack). HEAL is DIRECTIONAL, not from this pack: no pack prices a healing term, so it is bridged 1:1 from this table's own spellPower (card t_4e1e1b1d, DD-2).",
			directional = { HEAL = true },
		},
		-- presets['paladin-prot'].survival — a Protection paladin's OWN pack.
		tank = {
			STR   = 0.5,   -- source key: strength 0.5
			AGI   = 0,     -- absent from the pack (unlike warrior-prot's 0.3)
			STA   = 1.0,   -- source key: stamina 1.0
			INT   = 0,     -- absent from the pack
			SPI   = 0,     -- absent from the pack
			ARMOR = 0.35,  -- source key: armor 0.35
			BLOCK = 0.35,  -- source key: blockValue 0.35 (tiebreak-only — see WARRIOR.tank's BLOCK note, card t_ea260b42)
			-- card t_795eee9e: priced from its own pack (paladin-prot.survival)
			-- DIRECTIONAL: "Precision: Now increases chance for all spells and
			-- attacks to hit ... including the taunt from Seal of Fury's Judgement"
			-- | 0 -> 0.3: the pack is silent on hitRating, so nothing to cite; a
			-- tank buys hit for the taunt and the threat it carries, not for damage,
			-- so this takes less than half the melee price the paladin-ret pack
			-- carries (0.7) and stays below warrior-arms' 0.8.
			-- ⚠ WHAT THIS PRICE BUYS — MEASURED, and the first cut of this card got
			-- it wrong. That cut argued the price could move only the GATE and never
			-- a decision, because Hit was difference-only on the ruled unconfirmed
			-- list (t_d53877b1). Its premise was retired UNDER this card: t_ea404bae
			-- measured the rating unit (10 hit per 1%), converted it at the single
			-- boundary in Verdict.lua and took Hit off both unconfirmed lists. So a
			-- DIFFERING Hit is DECIDED by this number now — nothing intercepts it.
			-- The grid below was read off the classifier, not argued (sweep the
			-- price and watch the verdict move; pins B3/B4 in
			-- ChestAdvisor/tests/t_19174d55.js):
			--   ARMOUR pair, +3% hit vs +5 Stamina. The tooltip's 3% lands as 30
			--   rating points (#54's x10), so g = 30h and l = 5. One threshold
			--   (Verdict.WEIGHT_THRESHOLD 0.5, i.e. g must clear 3l) therefore gives
			--   UNKNOWN at 0, NOT_UPGRADE while h < ~0.056, TRADE_OFF from there to
			--   0.5, and UPGRADE at 0.5 and above. At the shipped 0.3 the row is
			--   TRADE_OFF: g = 9 against l = 5, so the gain IS bigger than the loss
			--   but does not clear the margin that would call it a win.
			--   WEAPON pair, +3% hit and nothing else: l = 0, so it reads UPGRADE at
			--   ANY price above 0 and UNKNOWN at 0.
			-- Both arms agree about the WORD — priced, deciding, UNKNOWN at 0 — and
			-- differ in verdict only because the pairs differ in what they lose.
			-- That is one rule, one price, one threshold. W2 records the weapon
			-- path; this card's first cut claimed neither moved a weapon verdict,
			-- and measurement retired that half too.
			-- | review item 6 (PALADIN / Protection: "HIT ... Up from 0")
			HIT   = 0.3,
			CRIT  = 0,     -- the pack prices it at nothing (ONE word since card t_9d3273cb)
			AP    = 0,     -- absent from the pack
			FAP   = 0,     -- 0: no pack in the quote prices a feral term (card t_3cdbb70a; DD-3 re-prices it)
			RAP   = 0,     -- absent from the pack
			MP5   = 0,     -- absent from the pack
			HP5   = 0.3,   -- source key: hp5 0.3
			DEF   = 1.3,   -- source key: defenseRating 1.3
			DODGE = 1.1,   -- source key: dodgeRating 1.1
			PARRY = 0.9,   -- source key: parryRating 0.9
			WDN   = 0,     -- absent from the pack (the dps packs price it, not survival)
			HEAL    = 0,     -- 0: no pack prices a healing term (card t_4e1e1b1d; the healer tables bridge it)
			SPHOLY  = 0,     -- 0: no pack in the quote prices a holy damage term (card t_4e1e1b1d; DD-4 prices it per spec)
			SPFIRE  = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFROST = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPSHADOW = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPNATURE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPOW  = 0,   -- absent from the pack (card t_b7cd07e1)
			source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['paladin-prot'].survival.",
			-- card DD-5: the one override above, declared for the same reason as the
			-- warrior tank table's three.
			directional = { HIT = true },
		},
	},
	-- ── SHAMAN ──────────────────────────────────────────────────────────────
	SHAMAN = {
		-- presets['shaman-enhancement'].dps — the melee order's spec
		-- (str>int>sta). tabSpecs.SHAMAN[1] = 'shaman-enhancement' (the
		-- Enhancement tab); the app's class default for SHAMAN is elemental,
		-- which is a caster pack and is used for the `spell` role below.
		melee = {
			STR   = 1.0,   -- source key: strength 1.0
			AGI   = 0.7,   -- source key: agility 0.7
			STA   = 0.3,   -- source key: stamina 0.3
			-- card DD-4 (t_721a287c): two talents turn Intellect into output for an
			-- Enhancement shaman. THE QUOTES: "Mental Dexterity: Increases your
			-- Attack Power by a percentage of your Intellect"; "Mental Quickness:
			-- Increases your spell damage and healing by a percentage of your
			-- Intellect"; "Ancestral Knowledge: Now increases Intellect instead
			-- of maximum Mana".
			-- NO PERCENTAGE IS PUBLISHED for either talent, so the RATE is
			-- borrowed and declared as borrowed: 0.30, the only Intellect to
			-- damage rate the review records (Champion of the Light's smaller
			-- reading, quoted on PALADIN.melee).
			-- THE DERIVATION, from THIS table's own cited pack
			-- (presets['shaman-enhancement'].dps): 0.30 x attackPower 0.4 = 0.12
			-- for the Mental Dexterity leg. The Mental Quickness leg converts to
			-- spell damage, which this table prices at SPOW 0 because
			-- shaman-enhancement.dps carries no spellPower term, so on THIS table
			-- that leg adds 0.30 x 0 = 0. The second leg is the reason 0.12 is a
			-- FLOOR and not a measurement, and re-pricing SPOW is outside this
			-- card by its own instruction.
			-- A NOTE ON AN EARLIER CUT (branch wt/t_04e0b9c5, never merged): it
			-- reached the same 0.12 by multiplying 0.30 by the PALADIN table's
			-- attackPower 0.3 and by a SPOW 0.10 it also moved. The number is the
			-- same; the arithmetic was a cross-table transcription and is
			-- corrected here, not copied.
			INT   = 0.12,
			-- card DD-4 (t_721a287c): THE QUOTE: "Improved Stormstrike allows
			-- Enhancement Shamans to regenerate Mana from Spirit". No ratio is
			-- published. 0.06 is a PLACEHOLDER and is declared as one: half this
			-- table's own Intellect 0.12, the same one-to-two relation the hunter
			-- table uses (PALADIN.melee is not a model here, because a Ret
			-- paladin has no Spirit conversion at all).
			-- Both numbers are placeholders, so the ratio between them is a
			-- convention and not a measurement. What the value buys is that Spirit
			-- stays below every other weighted key on this table and so cannot
			-- decide a pair by itself.
			SPI   = 0.06,
			ARMOR = 0.05,  -- source key: armor 0.05 (carried — not bridged)
			BLOCK = 0,     -- absent from the pack
			-- card t_795eee9e: priced from its own pack (shaman-enhancement.dps)
			HIT   = 0.7,   -- source key: hitRating 0.7 (ONE word since card t_9d3273cb)
			CRIT  = 0.9,   -- source key: critRating 0.9 (ONE word since card t_9d3273cb)
			AP    = 0.4,   -- source key: attackPower 0.4
			FAP   = 0,     -- 0: no pack in the quote prices a feral term (card t_3cdbb70a; DD-3 re-prices it)
			RAP   = 0,     -- absent from the pack (no ranged term for a melee spec)
			MP5   = 0,     -- absent from the pack
			HP5   = 0,     -- absent from the pack
			DEF   = 0,     -- absent from the pack (a survival term)
			DODGE = 0,     -- absent from the pack (a survival term)
			PARRY = 0,     -- absent from the pack (a survival term)
			WDN   = 6.0,   -- source key: weaponDps 6.0
			HEAL    = 0,     -- 0: no pack prices a healing term (card t_4e1e1b1d; the healer tables bridge it)
			SPHOLY  = 0,     -- 0: no pack in the quote prices a holy damage term (card t_4e1e1b1d; DD-4 prices it per spec)
			SPFIRE  = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFROST = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPSHADOW = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPNATURE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPOW  = 0,   -- absent from the pack (card t_b7cd07e1)
			source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['shaman-enhancement'].dps. DIRECTIONAL overrides, NOT sourced: INT (Mental Dexterity and Mental Quickness, card DD-4 t_721a287c) and SPI (Improved Stormstrike, card DD-4 t_721a287c).",
			directional = { INT = true, SPI = true },
		},
		-- presets['shaman-elemental'].dps — the spell order's spec.
		spell = {
			STR   = 0,     -- absent from the pack
			AGI   = 0,     -- absent from the pack
			STA   = 0.3,   -- source key: stamina 0.3
			INT   = 0.7,   -- source key: intellect 0.7
			SPI   = 0.8,   -- source key: spirit 0.8
			ARMOR = 0.2,   -- BRIDGED: the dps pack omits armor; the same spec's
			               -- survival pack armor 0.2
			BLOCK = 0,     -- absent from the pack
			-- card t_795eee9e: priced from its own pack (shaman-elemental.dps)
			HIT   = 0,     -- absent from the pack (ONE word since card t_9d3273cb)
			CRIT  = 0.4,   -- source key: critRating 0.4 (ONE word since card t_9d3273cb)
			AP    = 0,     -- absent from the pack
			FAP   = 0,     -- 0: no pack in the quote prices a feral term (card t_3cdbb70a; DD-3 re-prices it)
			RAP   = 0,     -- absent from the pack
			MP5   = 0.8,   -- source key: mp5 0.8
			HP5   = 0,     -- absent from the pack
			DEF   = 0,     -- absent from the pack (a survival term)
			DODGE = 0,     -- absent from the pack (a survival term)
			PARRY = 0,     -- absent from the pack (a survival term)
			WDN   = 0,     -- absent from the pack (no weapon term for a caster spec)
			HEAL    = 0,     -- 0: no pack prices a healing term (card t_4e1e1b1d; the healer tables bridge it)
			SPHOLY  = 0,     -- 0: no pack in the quote prices a holy damage term (card t_4e1e1b1d; DD-4 prices it per spec)
			SPFIRE  = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFROST = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPSHADOW = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPNATURE = 1.0,   -- source key: spellDamageNature 1.0 (card t_4e1e1b1d)
			SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPOW  = 1.0,   -- source key: spellPower 1.0 (card t_b7cd07e1)
			source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['shaman-elemental'].dps (ARMOR bridged from the same spec's .survival pack).",
		},
		-- presets['shaman-resto'].dps — the client's OWN HEALER literal, and the
		-- spec's own pack (card t_c222ff40, closing the defect card t_0e5381e1
		-- REPORTED above). Before this key existed, a Resto shaman (client
		-- literal HEALER) had no `healer` key to reach: the role word `spell`
		-- answered and the row read the ELEMENTAL table instead. One key, the
		-- same pattern PRIEST.healer already uses.
		--
		-- `spell` is deliberately UNCHANGED (still the Elemental table above) and
		-- this is a NEW table object rather than an alias of it. That is not
		-- book-keeping: literalWordsFor(SHAMAN, <the elemental table>) still
		-- returns {}, so an Elemental/DAMAGER literal is NOT caught by the
		-- fail-closed guard in Verdict.weightsFor and keeps resolving by the role
		-- word exactly as it does today. Aliasing would instead PUBLISH the
		-- Elemental pack as the HEALER one, which is the defect this key closes.
		--
		-- The values are shaman-resto.dps projected onto this file's
		-- vocabulary by the same rules as every other table: intellect 0.7,
		-- spirit 0.8, stamina 0.3 and spellPower 1.0 carried (the SPOW word,
		-- card t_b7cd07e1); ARMOR BRIDGED from the same spec's survival pack
		-- (0.2); strength, agility and block value absent from the pack -> 0.
		-- Card t_795eee9e: its critRating 0.4 and mp5 0.8 became words (CRIT,
		-- MP5) and are now carried from the pack; only its hasteRating 0.4 is
		-- still DROPPED, because no haste key is verified on this client.
		-- ⚠ Honest finding, stated because it is easy to over-read this key: that
		-- projection is IDENTICAL to the Elemental table's — the two packs differ
		-- only in spellDamageNature 1.0 — so this fix moves NO player-facing
		-- number. It moves the PROVENANCE: the spec is served by its own pack,
		-- cited as its own, and weights_spec_coverage.js now pins that identity.
		healer = {
			STR   = 0,     -- absent from the pack
			AGI   = 0,     -- absent from the pack, and NOT bridged: the app's
			               -- shaman-resto survival pack has no agility term
			               -- either. Stated limitation for the healer spec.
			STA   = 0.3,   -- source key: stamina 0.3
			INT   = 0.7,   -- source key: intellect 0.7
			SPI   = 0.8,   -- source key: spirit 0.8
			ARMOR = 0.2,   -- BRIDGED: the dps pack omits armor; the same spec's
			               -- survival pack armor 0.2
			BLOCK = 0,     -- absent from the pack
			-- card t_795eee9e: priced from its own pack (shaman-resto.dps)
			HIT   = 0,     -- absent from the pack (ONE word since card t_9d3273cb)
			CRIT  = 0.4,   -- source key: critRating 0.4 (ONE word since card t_9d3273cb)
			AP    = 0,     -- absent from the pack
			FAP   = 0,     -- 0: no pack in the quote prices a feral term (card t_3cdbb70a; DD-3 re-prices it)
			RAP   = 0,     -- absent from the pack
			MP5   = 0.8,   -- source key: mp5 0.8
			HP5   = 0,     -- absent from the pack
			DEF   = 0,     -- absent from the pack (a survival term)
			DODGE = 0,     -- absent from the pack (a survival term)
			PARRY = 0,     -- absent from the pack (a survival term)
			WDN   = 0,     -- absent from the pack (no weapon term for a caster spec)
			HEAL    = 1.0,   -- DIRECTIONAL: no pack prices a healing term; bridged 1:1 from this table's own SPOW (card t_4e1e1b1d; review X1)
			SPHOLY  = 0,     -- 0: no pack in the quote prices a holy damage term (card t_4e1e1b1d; DD-4 prices it per spec)
			SPFIRE  = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFROST = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPSHADOW = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPNATURE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPOW  = 1.0,   -- source key: spellPower 1.0 (card t_b7cd07e1)
			source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['shaman-resto'].dps (ARMOR bridged from the same spec's .survival pack). HEAL is DIRECTIONAL, not from this pack: no pack prices a healing term, so it is bridged 1:1 from this table's own spellPower (card t_4e1e1b1d, DD-2).",
			directional = { HEAL = true },
		},
	},
	-- ── DRUID ───────────────────────────────────────────────────────────────
	DRUID = {
		-- presets['druid-feral'].dps — the FERAL CAT (card t_6c3f414a, DD-3).
		-- WHY `melee` AND NOT A NEW KEY: `melee` is the word Verdict.ORDERS
		-- gives a feral druid (the order DD-3 adds: strength > agility >
		-- stamina), so the role path reaches this table with no client input
		-- at all, and a cat whose addon role is `melee` resolves here through
		-- weightsFor's step 2. The client literal it carries is DAMAGER — the
		-- SAME word a Balance druid carries — which is why
		-- Verdict.LITERAL_NEEDS_ROLE stops that literal from claiming
		-- DRUID.damager (the Balance bridge) for a cat. See that table's note.
		--
		-- ⚠ THE CARD'S BRIEF SAYS "Agility 0.75, Stamina 0.3"; THE PACK SAYS
		-- 0.8 AND 0.4, AND THE PACK WINS (this file's own rule: every number
		-- is transcribed from the pack a table cites, and a disagreement is
		-- corrected in favour of the pack, not quietly copied). The two
		-- differences are named here so the correction is auditable rather
		-- than invisible: agility 0.8 (brief 0.75), stamina 0.4 (brief 0.3).
		-- Strength 1.0 and attackPower 0.4 agree with the brief.
		melee = {
			STR   = 1.0,   -- source key: strength 1.0
			AGI   = 0.8,   -- source key: agility 0.8 (the brief said 0.75; the pack wins)
			STA   = 0.4,   -- source key: stamina 0.4 (the brief said 0.3; the pack wins)
			INT   = 0,     -- absent from the pack (a physical pack: no intellect term)
			SPI   = 0,     -- absent from the pack
			ARMOR = 0.05,  -- source key: armor 0.05 (the pack carries it — not bridged)
			BLOCK = 0,     -- absent from the pack (blockValue is a survival term)
			HIT   = 0.6,   -- source key: hitRating 0.6
			CRIT  = 0.8,   -- source key: critRating 0.8
			AP    = 0.4,   -- source key: attackPower 0.4
			-- DERIVED, not a second pack term: the pack has NO feralAttackPower
			-- key, and for the one class that can read a feral-AP line the
			-- question the term answers is the same one attackPower answers
			-- ("how much damage does a point of attack power add?"). So the
			-- cat prices FAP at the pack's own attackPower 0.4, and the
			-- citation diff derives exactly that (weights_citation.js
			-- `feralAttackPowerFrom`, quoted on this table's entry). Every
			-- other table keeps FAP at 0 — a feral-only line is worth nothing
			-- to a Warrior, Rogue or caster (DD-1's ruling), and the gate never
			-- closes a pair on it (wordUnpriced).
			FAP   = 0.4,   -- DERIVED: same pack term as AP (attackPower 0.4)
			RAP   = 0,     -- absent from the pack (no ranged term)
			MP5   = 0,     -- absent from the pack
			HP5   = 0,     -- absent from the pack (a survival term)
			DEF   = 0,     -- absent from the pack (a survival term)
			DODGE = 0,     -- absent from the pack (a survival term)
			PARRY = 0,     -- absent from the pack (a survival term)
			-- DIRECTIONAL: "While Shapeshifted, the Druid's melee auto attack
			-- DPS (Damage Per Second) while in Bear Form, Cat Form, or Dire
			-- Bear Form is now the same as the DPS of the Druid's equipped
			-- weapon." — the article's OWN quote for this row (review table,
			-- "Feral (cat and bear)"). The pack prices no weaponDps at all, so
			-- the DIRECTIONAL marker declares the override rather than dressing
			-- a judgement up as sourced. VALUE: 6.0, the number every other
			-- melee table in this file uses for the same term (WARRIOR, ROGUE,
			-- HUNTER, SHAMAN, PALADIN melee) — a PLACEHOLDER, not a measurement;
			-- whether a weapon's DPS weight transfers to a shaped druid is
			-- unmeasured on this build, and the article grades the direction
			-- HIGH and the value unknown.
			-- ⚠ STATED LIMITATION: on the two paths that exist today this term
			-- cannot be carried — the weapon's damage lines are stripped as
			-- chrome before the stat parse and compareWeapon passes no
			-- client-stat read, so no pair's stat table ever holds WeaponDps.
			-- It is here so the table states the feral weapon claim in the
			-- same vocabulary as every other melee spec, and so a future DPS
			-- channel has one number to read.
			WDN   = 6.0,   -- DIRECTIONAL placeholder (see above)
			SPOW  = 0,     -- absent from the pack
			HEAL     = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPHOLY   = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFIRE   = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFROST  = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPSHADOW = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPNATURE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
			source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['druid-feral'].dps.",
			directional = { WDN = true },
		},
		-- presets['druid-feral'].survival — the FERAL BEAR (card t_6c3f414a,
		-- DD-3). Resolved only through the client's TANK literal; that literal
		-- comes from the talent-spec read, not from shapeshift form, so on
		-- today's client the bear path is not reachable in real play yet
		-- (reachable only when the spec read says TANK, which has not been
		-- observed for a feral druid). Both share the `melee` ORDER, and the
		-- weights are what tell the two specs apart (stamina 1.0 here, 0.4 in
		-- the cat's table).
		--
		-- THE ONE ROW THIS CARD IS FOR, on the stat side: DEF = 0.6 from the
		-- pack's defenseRating 0.6. The article's quote: Thick Hide "increased
		-- Armor is based on Defense skill bonuses from buffs and equipped
		-- items… This causes Druid tanks to now gain benefit from Defense skill
		-- items similar to other tank classes." Direction HIGH, and the number
		-- is the pack's own — NOT marked up. Marking it up is a separate
		-- DIRECTIONAL decision the card leaves open ("propose a value only with
		-- its derivation"); no measured derivation exists on this build, so
		-- none is proposed and the pack's 0.6 stands.
		--
		-- ⚠ STATED LIMITATION, and it is the comparator's, not this table's: a
		-- pair that differs ONLY in Defense never reaches the weighted layer on
		-- the ARMOUR path, because Defense is in no class order and the
		-- relevance set is the order's words plus Armor and Block — so such a
		-- pair reads "equal to what's equipped". DEF decides where a priced
		-- trade-off is broken (it is the largest term a bear usually has), and
		-- on the bear's WEAPON path, where tankWeaponOrder puts it in the
		-- dominance terms. Both are asserted in
		-- ChestAdvisor/tests/t_6c3f414a.js.
		tank = {
			STR   = 0.5,   -- source key: strength 0.5
			AGI   = 0.6,   -- source key: agility 0.6
			STA   = 1.0,   -- source key: stamina 1.0
			INT   = 0,     -- absent from the pack
			SPI   = 0,     -- absent from the pack
			ARMOR = 0.25,  -- source key: armor 0.25 (the pack carries it — not bridged)
			BLOCK = 0,     -- absent from the pack (no blockValue in the feral survival pack)
			HIT   = 0,     -- absent from the pack
			CRIT  = 0,     -- absent from the pack
			AP    = 0,     -- absent from the survival block
			-- 0 for the BEAR: the card prices FAP for the CAT table only. A bear
			-- does benefit from AP (Maul/Swipe), and the survival block prices
			-- none — so there is no pack number to derive it from here, and
			-- inventing one would be a DIRECTIONAL claim this card does not
			-- make. Stated limitation: a feral-AP line contributes 0 to a
			-- bear's trade-off.
			FAP   = 0,     -- absent from the survival block (and the card prices it for cat only)
			RAP   = 0,     -- absent from the pack
			MP5   = 0,     -- absent from the pack
			HP5   = 0.3,   -- source key: hp5 0.3
			DEF   = 0.6,   -- source key: defenseRating 0.6 (the card's bear DEF)
			DODGE = 0.8,   -- source key: dodgeRating 0.8
			PARRY = 0,     -- absent from the pack
			-- DIRECTIONAL: the same quote and the same placeholder as the cat
			-- table above — "the same as the DPS of the Druid's equipped
			-- weapon" names BEAR FORM explicitly, and the pack prices no
			-- weaponDps, so 6.0 is the stated placeholder every other melee
			-- table uses. Same STATED LIMITATION as the cat's: no reached path
			-- carries a WeaponDps term into a stat table today.
			WDN   = 6.0,   -- DIRECTIONAL placeholder (see the cat table's note)
			SPOW  = 0,     -- absent from the pack
			HEAL     = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPHOLY   = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFIRE   = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFROST  = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPSHADOW = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPNATURE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
			source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['druid-feral'].survival.",
			directional = { WDN = true },
		},
		-- presets['druid-resto'].dps — the spell order's spec (int>agi>sta).
		-- WHY RESTO, when the app's DRUID default is druid-feral: its
		-- tabSpecs.DRUID is ['druid-resto', 'druid-feral', 'druid-resto'] with
		-- the comment "Balance -> caster weights", and this addon's druid
		-- `spell` role is the caster shape (Intellect first). druid-feral is a
		-- PHYSICAL pack (strength 1.0 / agility 0.8, no intellect at all) and
		-- using it for the `spell` role would contradict the class's own order.
		-- The `melee` and `tank` keys above are card t_6c3f414a's (DD-3). Before
		-- it, this class carried `spell` alone and a feral druid had no table at
		-- all: its ORDER was nil (Verdict.ORDERS NO_ORDER, card t_03a1196c), so
		-- the caller's order gate declined a feral row before the comparator
		-- and no table under this class could ever be consulted. DD-3 fills
		-- that order, so the two feral tables are now reachable — see the
		-- COVERAGE and gap notes above.
		spell = {
			STR   = 0,     -- absent from the pack
			AGI   = 0,     -- absent from the pack, and NOT bridged: the app's
			               -- druid-resto survival pack has no agility term
			               -- either. Stated limitation for the spell spec.
			STA   = 0.3,   -- source key: stamina 0.3
			INT   = 0.7,   -- source key: intellect 0.7
			SPI   = 0.8,   -- source key: spirit 0.8
			ARMOR = 0.2,   -- BRIDGED: the dps pack omits armor; the same spec's
			               -- survival pack armor 0.2
			BLOCK = 0,     -- absent from the pack
			-- card t_795eee9e: priced from its own pack (druid-resto.dps)
			HIT   = 0,     -- absent from the pack (ONE word since card t_9d3273cb)
			CRIT  = 0.4,   -- source key: critRating 0.4 (ONE word since card t_9d3273cb)
			AP    = 0,     -- absent from the pack
			FAP   = 0,     -- 0: no pack in the quote prices a feral term (card t_3cdbb70a; DD-3 re-prices it)
			RAP   = 0,     -- absent from the pack
			MP5   = 0.8,   -- source key: mp5 0.8
			HP5   = 0,     -- absent from the pack
			DEF   = 0,     -- absent from the pack (a survival term)
			DODGE = 0,     -- absent from the pack (a survival term)
			PARRY = 0,     -- absent from the pack (a survival term)
			WDN   = 0,     -- absent from the pack (no weapon term for a caster spec)
			HEAL    = 1.0,   -- DIRECTIONAL: no pack prices a healing term; bridged 1:1 from this table's own SPOW (card t_4e1e1b1d; review X1)
			SPHOLY  = 0,     -- 0: no pack in the quote prices a holy damage term (card t_4e1e1b1d; DD-4 prices it per spec)
			SPFIRE  = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFROST = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPSHADOW = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPNATURE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPOW  = 1.0,   -- source key: spellPower 1.0 (card t_b7cd07e1)
			source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['druid-resto'].dps (ARMOR bridged from the same spec's .survival pack). HEAL is DIRECTIONAL, not from this pack: no pack prices a healing term, so it is bridged 1:1 from this table's own spellPower (card t_4e1e1b1d, DD-2).",
			directional = { HEAL = true },
		},
		-- presets['priest-shadow'].dps — BRIDGED, for BALANCE (card t_0e5381e1,
		-- the owner's one exception: "Leave Balance on the order fallback, or
		-- bridge it from a caster DPS pack if one fits better than Resto").
		--
		-- WHY A CROSS-CLASS BORROW, AND WHY THE SHADOW PACK. Balance is a caster
		-- DPS (Intellect primary, Spirit for mana — a moonkin burns mana and
		-- regains it with Spirit), and the druid class has NO caster-DPS pack of
		-- its own: the only two are druid-feral (a PHYSICAL pack — strength 1.0 /
		-- agility 0.8, no Intellect at all) and druid-resto (a HEALER pack whose
		-- spirit 0.8 is priced ABOVE its own intellect 0.7). Judged by the only
		-- key that reaches it today (`spell` = druid-resto) a Balance druid reads
		-- the Spirit-first healer shape, which is not a damage shape at all.
		-- The owner's three candidates, projected onto this addon's vocabulary
		-- (the seven original words the bridge decision was made on):
		--   mage-frostfire       int 0.8  spi 0.4  sta 0.3  armor 0.2
		--   warlock-destruction  int 0.7  spi 0.3  sta 0.3  armor 0.2
		--   priest-shadow        int 0.8  spi 0.6  sta 0.3  armor 0.2   <-- chosen
		-- priest-shadow is the ONLY one that is Intellect-first (matching the
		-- druid `spell` ORDER, int>agi>sta — where druid-resto's spirit-first
		-- shape contradicts it) while still pricing Spirit meaningfully; mage and
		-- warlock price Spirit at 0.4/0.3, too low for a class whose spec is
		-- defined by its mana problems. The values below are that pack verbatim —
		-- the same numbers as PRIEST.spell, which is the point: it is
		-- priest-shadow.dps, labelled as the BRIDGE it is rather than copied
		-- silently, and guarded by a citation entry in
		-- ChestAdvisor/tests/weights_citation_packs.json like every other table.
		--
		-- ⚠ LEAST-CERTAIN ROW IN THIS FILE, flagged as the owner asked. It is a
		-- CLAIM (a Balance druid wants what a Shadow priest wants) that no source
		-- measures; it is the only bridge here that is not a same-class fold.
		-- Reached only by the client's DAMAGER literal: a Balance druid's role is
		-- DAMAGER, and weightsFor consults a literal key FIRST. Resto keeps
		-- `spell`: a Resto druid's literal is HEALER, and DRUID.healer is an
		-- ALIAS of DRUID.spell (the same table OBJECT, assigned at the foot of
		-- this file), so both routes land on druid-resto — unchanged.
		-- Feral's literal is DAMAGER too, and a direct weightsFor call carrying
		-- it does return THIS table — but no feral ROW is ever served by it. The
		-- ORDER is nil (NO_ORDER), so the caller's order gate declines the row
		-- before the comparator; and if the comparator is called anyway it
		-- enters gate 9 only to have `Verdict.dominance` return nil for an empty
		-- order (the weighted layer runs only on a `trade-off`). See the
		-- FALLBACK note in the header.
		damager = {
			STR   = 0,     -- absent from the pack
			AGI   = 0,     -- absent from the pack
			STA   = 0.3,   -- source key: stamina 0.3
			INT   = 0.8,   -- source key: intellect 0.8
			SPI   = 0.6,   -- source key: spirit 0.6
			ARMOR = 0.2,   -- BRIDGED: the dps pack omits armor; the same spec's
			               -- survival pack armor 0.2
			BLOCK = 0,     -- absent from the pack
			-- card t_795eee9e: the pack's own numbers (priest-shadow.dps), the
			-- same ten values PRIEST.spell carries — it is the same pack
			HIT   = 0.4,   -- source key: hitRating 0.4 (ONE word since card t_9d3273cb)
			CRIT  = 0.5,   -- source key: critRating 0.5 (ONE word since card t_9d3273cb)
			AP    = 0,     -- absent from the pack
			FAP   = 0,     -- 0: no pack in the quote prices a feral term (card t_3cdbb70a; DD-3 re-prices it)
			RAP   = 0,     -- absent from the pack
			MP5   = 0.6,   -- source key: mp5 0.6
			HP5   = 0,     -- absent from the pack
			DEF   = 0,     -- absent from the pack (a survival term)
			DODGE = 0,     -- absent from the pack (a survival term)
			PARRY = 0,     -- absent from the pack (a survival term)
			WDN   = 0,     -- absent from the pack (no weapon term for a caster spec)
			HEAL    = 0,     -- 0: no pack prices a healing term (card t_4e1e1b1d; this is the DAMAGER key)
			SPHOLY  = 0,     -- 0: no pack in the quote prices a holy damage term (card t_4e1e1b1d; DD-4 prices it per spec)
			SPFIRE  = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFROST = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPSHADOW = 0,     -- DIRECTIONAL: 0 despite the bridged pack's spellDamageShadow 1.0 — that term is the PRIEST's school and a Balance druid deals Nature/Arcane (review X1: Shadow is the priest/warlock gap)
			SPNATURE = 0,     -- 0: no source prices a Balance Nature term (card t_4e1e1b1d default; DD-4's call)
			SPARCANE = 0,     -- 0: no source prices a Balance Arcane term (card t_4e1e1b1d default; DD-4's call)
			SPOW  = 1.2,   -- source key: spellPower 1.2 (card t_b7cd07e1)
			source = MARKER .. ". BRIDGED from presets['priest-shadow'].dps — Balance is a caster DPS and the druid class has no caster-DPS pack of its own; priest-shadow is the only Intellect-first candidate that still prices Spirit, which a Balance druid's mana needs (ARMOR bridged from the same spec's .survival pack). LEAST-CERTAIN table in this file. SPSHADOW is DIRECTIONAL, priced 0: the bridged pack's spellDamageShadow 1.0 belongs to the PRIEST's spells, and a Balance druid deals Nature and Arcane damage (review X1; card t_4e1e1b1d, DD-2).",
			directional = { SPSHADOW = true },
		},
	},
	-- ── HUNTER ──────────────────────────────────────────────────────────────
	HUNTER = {
		-- presets['hunter-marksman'].dps — the class's ONLY pack, reachable from
		-- every direction in the app: classSpecs lists exactly one HUNTER spec
		-- ('hunter-marksman', role 'dps'), getDefaultSpecForClass('HUNTER') is
		-- that id, and tabSpecs.HUNTER is ['hunter-marksman', 'hunter-marksman',
		-- 'hunter-marksman'] — all three talent tabs. There is no choice to
		-- argue here, and exactly one key.
		--
		-- WHY THE KEY IS `melee` FOR A PACK THE APP CALLS RANGED: the key is
		-- Verdict.ORDERS' own word for this class, not a claim about weapon
		-- range. HUNTER has one order (Agility > Stamina > Intellect,
		-- stat-weights §8.1) and one spec, so it is a PURE class and its single
		-- key is that order's key — the shape WARRIOR.melee and ROGUE.melee
		-- already use, and the word weightsFor's pure-class fallback (step 3)
		-- looks up. The pack AGREES with the order: agility 1.0 > stamina 0.3 >
		-- intellect 0.2.
		--
		-- No `damager` key: a Hunter's client role IS DAMAGER, but there is no
		-- second Hunter pack for a literal to reach, so it folds onto this one
		-- key — which is this table. See the COVERAGE note above.
		melee = {
			STR   = 0,     -- absent from the pack (no strength term)
			AGI   = 1.0,   -- source key: agility 1.0
			STA   = 0.3,   -- source key: stamina 0.3
			-- card DD-4 (t_721a287c): Intellect is OUTPUT for a Marksman hunter,
			-- so this table stops reading the pack's mana-pool 0.2 alone.
			-- THE QUOTE: "Careful Aim: Increases melee and ranged Attack power
			-- by 20/40/60/80/100% of the Hunter's Intellect."
			-- THE DERIVATION, every number from the pack this table cites
			-- (presets['hunter-marksman'].dps): the pack's own intellect 0.2 is
			-- kept as the mana floor, and at 5/5 Careful Aim one point of
			-- Intellect is one point of ranged attack power, which the same pack
			-- prices at rangedAttackPower 0.45. 0.2 + (1.0 x 0.45) = 0.65.
			-- WHY THE MELEE HALF IS NOT ADDED: the same talent grants attackPower
			-- too, and adding the pack's 0.3 as well would read 0.95, which is not
			-- a conversion this table can defend for a spec whose damage is
			-- ranged. The review's own reading of the talent is "Ranged only,
			-- since a hunter's damage is mostly ranged" (review section X3,
			-- hunter row).
			-- THE ASSUMPTION, stated because the number is false without it: 5/5
			-- Careful Aim. It is a Marksmanship talent and this table IS the
			-- marksman pack, so the assumption matches the spec, but a hunter
			-- without the talent reads 0.45 too high here and the comparator
			-- sees no talents at all.
			-- ORDER NOTE, reported and not resolved here: 0.65 sits above stamina
			-- 0.3, while Verdict.ORDERS.HUNTER.melee documents Agility > Stamina
			-- > Intellect. The weighted layer outranks the order by design (the
			-- order words the reason, the resolved pack decides the trade-off),
			-- so the two now disagree on that axis.
			INT   = 0.65,
			-- card DD-4 (t_721a287c): Spirit is not a damage conversion for a
			-- hunter. It buys mana regeneration WHILE CASTING, which the three
			-- quoted talents grant. THE QUOTES: "Bestial Discipline: Now also
			-- grants the Hunter Mana regeneration from Spirit while casting
			-- spells"; "Rapid Recuperation grants Mana regeneration from Spirit
			-- while casting"; "Resourcefulness grants your critical strikes a
			-- chance to allow Mana regeneration from Spirit while casting
			-- spells".
			-- NO PERCENTAGE IS PUBLISHED, so 0.1 is a PLACEHOLDER and is declared
			-- as one: half the PACK's own intellect 0.2, the mana stat Spirit
			-- substitutes for while casting. It is deliberately not half the
			-- directional 0.65 above, which is a damage price.
			-- It is still NOT a bridge: hunter-marksman.survival prices spirit at
			-- 0.2 and armor remains the only bridge this file allows (review
			-- section X4, hunter rows).
			SPI   = 0.1,
			ARMOR = 0.05,  -- source key: armor 0.05 (the pack carries it — not bridged)
			BLOCK = 0,     -- absent from the pack
			-- card t_795eee9e: priced from its own pack (hunter-marksman.dps).
			-- This is the ONE table in the file that carries RAP: the pack
			-- prices rangedAttackPower 0.45 as a term separate from its
			-- attackPower 0.3 — the client's RANGE and MELEE attack-power keys
			-- are different keys, and the pack's own split is kept, not folded.
			HIT   = 0.7,   -- source key: hitRating 0.7 (ONE word since card t_9d3273cb)
			CRIT  = 0.9,   -- source key: critRating 0.9 (ONE word since card t_9d3273cb)
			AP    = 0.3,   -- source key: attackPower 0.3
			FAP   = 0,     -- 0: no pack in the quote prices a feral term (card t_3cdbb70a; DD-3 re-prices it)
			RAP   = 0.45,  -- source key: rangedAttackPower 0.45
			MP5   = 0,     -- absent from the pack
			HP5   = 0,     -- absent from the pack
			DEF   = 0,     -- absent from the pack (a survival term)
			DODGE = 0,     -- absent from the pack (a survival term)
			PARRY = 0,     -- absent from the pack (a survival term)
			WDN   = 6.0,   -- source key: weaponDps 6.0
			HEAL    = 0,     -- 0: no pack prices a healing term (card t_4e1e1b1d; the healer tables bridge it)
			SPHOLY  = 0,     -- 0: no pack in the quote prices a holy damage term (card t_4e1e1b1d; DD-4 prices it per spec)
			SPFIRE  = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFROST = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPSHADOW = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPNATURE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPOW  = 0,   -- absent from the pack (card t_b7cd07e1)
			source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['hunter-marksman'].dps. DIRECTIONAL overrides, NOT sourced: INT (Careful Aim, card DD-4 t_721a287c) and SPI (Spirit regen while casting, card DD-4 t_721a287c).",
			directional = { INT = true, SPI = true },
		},
	},
	-- ── ROGUE ───────────────────────────────────────────────────────────────
	ROGUE = {
		-- presets['rogue-combat'].dps — the class's ONLY pack (classSpecs lists
		-- one ROGUE spec, 'rogue-combat' role 'dps'; it is the class default;
		-- tabSpecs.ROGUE maps all three tabs to it). One key, `melee`, the
		-- class's own order word (Agility > Strength > Stamina, stat-weights
		-- §8.1) — and the pack agrees with it: agility 1.0 > strength 0.5 >
		-- stamina 0.3.
		--
		-- UNLIKE WARRIOR and HUNTER, this pack DOES price strength, so a Rogue's
		-- Strength line is weighed rather than dropped. That is the pack's own
		-- number, transcribed, not a bridge.
		melee = {
			STR   = 0.5,   -- source key: strength 0.5
			AGI   = 1.0,   -- source key: agility 1.0
			STA   = 0.3,   -- source key: stamina 0.3
			INT   = 0,     -- absent from the pack
			SPI   = 0,     -- absent from BOTH rogue-combat packs (dps and survival)
			ARMOR = 0.05,  -- source key: armor 0.05 (the pack carries it — not bridged)
			BLOCK = 0,     -- absent from the pack
			-- card t_795eee9e: priced from its own pack (rogue-combat.dps)
			HIT   = 0.8,   -- source key: hitRating 0.8 (ONE word since card t_9d3273cb)
			CRIT  = 0.9,   -- source key: critRating 0.9 (ONE word since card t_9d3273cb)
			AP    = 0.4,   -- source key: attackPower 0.4 (the pack's own number above)
			FAP   = 0,     -- 0: no pack in the quote prices a feral term (card t_3cdbb70a; DD-3 re-prices it)
			RAP   = 0,     -- absent from the pack (no ranged term for a melee spec)
			MP5   = 0,     -- absent from the pack
			HP5   = 0,     -- absent from the pack
			DEF   = 0,     -- absent from the pack (a survival term)
			DODGE = 0,     -- absent from the pack (a survival term)
			PARRY = 0,     -- absent from the pack (a survival term)
			WDN   = 6.0,   -- source key: weaponDps 6.0
			HEAL    = 0,     -- 0: no pack prices a healing term (card t_4e1e1b1d; the healer tables bridge it)
			SPHOLY  = 0,     -- 0: no pack in the quote prices a holy damage term (card t_4e1e1b1d; DD-4 prices it per spec)
			SPFIRE  = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFROST = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPSHADOW = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPNATURE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPOW  = 0,   -- absent from the pack (card t_b7cd07e1)
			source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['rogue-combat'].dps.",
		},
	},
	-- ── PRIEST ──────────────────────────────────────────────────────────────
	PRIEST = {
		-- presets['priest-shadow'].dps (the local PRIEST_SHADOW table above) —
		-- the addon's own `spell` word for a priest, and the app's class DEFAULT
		-- for the class. A priest is a PURE class (one order, int>spi>sta), so a
		-- priest with no client spec read reaches step 3 of weightsFor and THIS
		-- key is what answers; the pack agrees with the order (intellect 0.8 >
		-- spirit 0.6 > stamina 0.3).
		spell = PRIEST_SHADOW,
		-- The client's own DAMAGER literal — the same Shadow spec as `spell`
		-- above, and deliberately the SAME table object rather than a copy of
		-- it. A Shadow priest's client role is DAMAGER.
		damager = PRIEST_SHADOW,
		-- The client's own HEALER literal -> presets['priest-holy'].dps. This key
		-- is the whole reason a priest needs the literal vocabulary: without it a
		-- Holy priest would be judged by the Shadow numbers above, which price
		-- intellect 0.8 vs 0.7, crit 0.5 vs 0.4 and the same stamina 0.3 —
		-- close, but a different pack, and this file does not blend two.
		healer = {
			STR   = 0,     -- absent from the pack
			AGI   = 0,     -- absent from the pack
			STA   = 0.3,   -- source key: stamina 0.3
			INT   = 0.7,   -- source key: intellect 0.7
			SPI   = 0.6,   -- source key: spirit 0.6
			ARMOR = 0.2,   -- BRIDGED: the dps pack omits armor; the same spec's
			               -- survival pack armor 0.2
			BLOCK = 0,     -- absent from the pack
			-- card t_795eee9e: priced from its own pack (priest-holy.dps)
			HIT   = 0,     -- absent from the pack (ONE word since card t_9d3273cb)
			CRIT  = 0.4,   -- source key: critRating 0.4 (ONE word since card t_9d3273cb)
			AP    = 0,     -- absent from the pack
			FAP   = 0,     -- 0: no pack in the quote prices a feral term (card t_3cdbb70a; DD-3 re-prices it)
			RAP   = 0,     -- absent from the pack
			MP5   = 0.8,   -- source key: mp5 0.8
			HP5   = 0,     -- absent from the pack
			DEF   = 0,     -- absent from the pack (a survival term)
			DODGE = 0,     -- absent from the pack (a survival term)
			PARRY = 0,     -- absent from the pack (a survival term)
			WDN   = 0,     -- absent from the pack (no weapon term for a caster spec)
			HEAL    = 0.8,   -- DIRECTIONAL: no pack prices a healing term; bridged 1:1 from this table's own SPOW (card t_4e1e1b1d; review X1)
			SPHOLY  = 0,     -- 0: no pack in the quote prices a holy damage term (card t_4e1e1b1d; DD-4 prices it per spec)
			SPFIRE  = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPFROST = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPSHADOW = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPNATURE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPOW  = 0.8,   -- source key: spellPower 0.8 (card t_b7cd07e1)
			source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['priest-holy'].dps (ARMOR bridged from the same spec's .survival pack). HEAL is DIRECTIONAL, not from this pack: no pack prices a healing term, so it is bridged 1:1 from this table's own spellPower (card t_4e1e1b1d, DD-2).",
			directional = { HEAL = true },
		},
	},
	-- ── MAGE ────────────────────────────────────────────────────────────────
	MAGE = {
		-- presets['mage-frostfire'].dps — the class's ONLY pack (classSpecs
		-- lists one MAGE spec, 'mage-frostfire'; it is the class default;
		-- tabSpecs.MAGE maps all three tabs to it). One key, `spell`, the
		-- class's own order word (int>spi>sta), which the pack agrees with:
		-- intellect 0.8 > spirit 0.4 > stamina 0.3.
		--
		-- The pack's school terms — spellDamageFrost / spellDamageFire, 1.0
		-- each — ARE in this addon's vocabulary since card t_4e1e1b1d (DD-2):
		-- they are SPFROST / SPFIRE below, priced at the pack's own 1.0, and
		-- the comparator reads them with the class's higher-of rule for a
		-- Mage (Frostfire Bolt uses the higher of the two bonuses, so the two
		-- terms are max()ed, never summed — Verdict.lua's mageSchoolCollapse).
		-- spellPower 1.2 IS carried: the owner ruled a weight for it
		-- (card t_b7cd07e1, the SPOW word above), and card t_795eee9e carried
		-- the pack's hitRating 0.8, critRating 0.6 and mp5 0.4 into HIT,
		-- CRIT and MP5 below. A trade-off whose only gain is a school bonus IS
		-- resolved by weights now (AC-C of DD-2): +20 Fire against a small
		-- Spirit loss reads UPGRADE on Fire Power, and Fire +20 / Frost +0
		-- against Fire +0 / Frost +20 reads LEVEL, because the higher of the
		-- pair is 20 on both sides.
		spell = {
			STR   = 0,     -- absent from the pack
			AGI   = 0,     -- absent from the pack
			STA   = 0.3,   -- source key: stamina 0.3
			INT   = 0.8,   -- source key: intellect 0.8
			SPI   = 0.4,   -- source key: spirit 0.4
			ARMOR = 0.2,   -- BRIDGED: the dps pack omits armor; the same spec's
			               -- survival pack armor 0.2
			BLOCK = 0,     -- absent from the pack
			-- card t_795eee9e: priced from its own pack (mage-frostfire.dps)
			HIT   = 0.8,   -- source key: hitRating 0.8 (ONE word since card t_9d3273cb)
			CRIT  = 0.6,   -- source key: critRating 0.6 (ONE word since card t_9d3273cb)
			AP    = 0,     -- absent from the pack
			FAP   = 0,     -- 0: no pack in the quote prices a feral term (card t_3cdbb70a; DD-3 re-prices it)
			RAP   = 0,     -- absent from the pack
			MP5   = 0.4,   -- source key: mp5 0.4
			HP5   = 0,     -- absent from the pack
			DEF   = 0,     -- absent from the pack (a survival term)
			DODGE = 0,     -- absent from the pack (a survival term)
			PARRY = 0,     -- absent from the pack (a survival term)
			WDN   = 0,     -- absent from the pack (no weapon term for a caster spec)
			HEAL    = 0,     -- 0: no pack prices a healing term (card t_4e1e1b1d; the healer tables bridge it)
			SPHOLY  = 0,     -- 0: no pack in the quote prices a holy damage term (card t_4e1e1b1d; DD-4 prices it per spec)
			SPFIRE  = 1.0,   -- source key: spellDamageFire 1.0 (card t_4e1e1b1d)
			SPFROST = 1.0,   -- source key: spellDamageFrost 1.0 (card t_4e1e1b1d)
			SPSHADOW = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPNATURE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPOW  = 1.2,   -- source key: spellPower 1.2 (card t_b7cd07e1)
			source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['mage-frostfire'].dps (ARMOR bridged from the same spec's .survival pack).",
		},
	},
	-- ── WARLOCK ─────────────────────────────────────────────────────────────
	WARLOCK = {
		-- presets['warlock-destruction'].dps — the class's ONLY pack (classSpecs
		-- lists one WARLOCK spec, 'warlock-destruction'; it is the class default;
		-- tabSpecs.WARLOCK maps all three tabs to it). One key, `spell`, the
		-- class's own order word (int>spi>sta).
		--
		-- THE ONE PLACE THIS PACK AND THE CLASS'S ORDER DO NOT AGREE, stated
		-- rather than smoothed over: the pack prices spirit 0.3 and stamina 0.3
		-- EQUALLY, while the documented order puts Spirit ahead of Stamina. An
		-- equal weighting cannot express that preference, so on a pair that
		-- moves only Spirit against Stamina the weighted layer sees a tie,
		-- declines, and the ordinal order keeps wording the reason. Nothing is
		-- bridged or nudged to "fix" it: the pack's number for spirit IS 0.3.
		spell = {
			STR   = 0,     -- absent from the pack
			AGI   = 0,     -- absent from the pack
			STA   = 0.3,   -- source key: stamina 0.3
			INT   = 0.7,   -- source key: intellect 0.7
			SPI   = 0.3,   -- source key: spirit 0.3 (equal to stamina — see above)
			ARMOR = 0.2,   -- BRIDGED: the dps pack omits armor; the same spec's
			               -- survival pack armor 0.2
			BLOCK = 0,     -- absent from the pack
			-- card t_795eee9e: priced from its own pack (warlock-destruction.dps)
			HIT   = 0.8,   -- source key: hitRating 0.8 (ONE word since card t_9d3273cb)
			CRIT  = 0.7,   -- source key: critRating 0.7 (ONE word since card t_9d3273cb)
			AP    = 0,     -- absent from the pack
			FAP   = 0,     -- 0: no pack in the quote prices a feral term (card t_3cdbb70a; DD-3 re-prices it)
			RAP   = 0,     -- absent from the pack
			MP5   = 0.4,   -- source key: mp5 0.4
			HP5   = 0,     -- absent from the pack
			DEF   = 0,     -- absent from the pack (a survival term)
			DODGE = 0,     -- absent from the pack (a survival term)
			PARRY = 0,     -- absent from the pack (a survival term)
			WDN   = 0,     -- absent from the pack (no weapon term for a caster spec)
			HEAL    = 0,     -- 0: no pack prices a healing term (card t_4e1e1b1d; the healer tables bridge it)
			SPHOLY  = 0,     -- 0: no pack in the quote prices a holy damage term (card t_4e1e1b1d; DD-4 prices it per spec)
			SPFIRE  = 0.8,   -- source key: spellDamageFire 0.8 (card t_4e1e1b1d)
			SPFROST = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPSHADOW = 1.0,   -- source key: spellDamageShadow 1.0 (card t_4e1e1b1d)
			SPNATURE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPARCANE = 0,     -- absent from the pack (card t_4e1e1b1d)
			SPOW  = 1.0,   -- source key: spellPower 1.0 (card t_b7cd07e1)
			source = MARKER .. ". Cite: statforge-app/src/lib/statWeights.ts presets['warlock-destruction'].dps (ARMOR bridged from the same spec's .survival pack).",
		},
	},
}

-- ── Card t_0e5381e1: the DRUID literal keys, and WHY they are aliases ────────
-- DRUID now needs the same two literal keys PRIEST carries, and for the same
-- reason: the class has TWO packs behind two client roles, and the role WORD
-- (`spell`) can only name one of them.
--   * DRUID.damager is the table above — the Balance bridge.
--   * DRUID.healer ALIASES DRUID.spell (the same table OBJECT, never a copy) so
--     that the resto pack is PUBLISHED as the HEALER spec. That is not book-
--     keeping: it is what makes the fail-closed guard in Verdict.weightsFor
--     reach the druid at all. That guard refuses a fall-through pack that is
--     published for a different client word; with `spell` published by nobody,
--     a Balance druid (literal DAMAGER) whose `damager` key were missing or
--     corrupt would fall through the role word onto the RESTO table and read a
--     HEALER's numbers with no error — the exact shape of the Holy-priest hole
--     card t_41697d02 closed for PRIEST. Published, it refuses and the row
--     reads its ordinal verdict instead. No number is added and nothing is
--     renamed: this is the PRIEST spell/damager/healer pattern, which uses one
--     table object for two keys for precisely this reason.
-- A GUARDED alias, and the guard is load-bearing rather than defensive habit:
-- Weights.lua is loaded into test VMs that EMPTY or REPLACE StatForge.Weights —
-- the fail-safe legs and the non-vacuity companions do exactly that — and a bare
-- `SF.Weights.DRUID.healer = ...` would index a nil there and RAISE at load
-- time, turning a deliberate, measured break into a load error (it did: it made
-- weights_scoring-nonvacuity's "the shipped weights are REMOVED" break redden
-- all 77 checks, including the fail-safes that must stay green). Absent weights
-- mean the ordinal path, which is precisely what those legs are measuring.
if SF.Weights and SF.Weights.DRUID then
	SF.Weights.DRUID.healer = SF.Weights.DRUID.spell
end

return SF.Weights
