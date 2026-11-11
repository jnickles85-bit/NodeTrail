# Changelog

All notable changes to MightiePack. The format follows Keep a Changelog, and the
project uses semantic-ish versioning: the pack version in `MightiePack.toc` is the
one CurseForge shows, and the bundled modules report the same number.

## [Unreleased]

## [0.3.4-beta] - 2026-11-11

### Changed
- The skinning recorder is on by default: a fresh install records from the first corpse with no setup. A one-time migration switches the previous default on for an existing install, and an explicit off — un-ticking Skinning (experimental) in settings or `/nt skin off` — is stored as the player's own choice (`NodeTrailDB.skinning.skinUserSet`), so it survives `/reload` and later updates and the migration never overrides it. `/nt skin status` reports the current state.

### Fixed
- Skinning counts every skin once again, whichever way the recorder saw it. A successful skin is normally reported as a cast with no corpse pinned to it followed by the skin loot window, and only the pinned path incremented the per-creature total — so the window marked the corpse skinned (its items were recorded and its loot was correct) while the skinned count the beast panel prints stayed behind. Live: 5 Plainstriders skinned, the panel said `kills seen: 18 · skinned: 3`. The window now counts the corpse it marks, and a corpse already counted — by the cast path, by a re-opened window, or by the schema 1 → 2 seeding — is never counted twice. A skin window with no successful cast behind it still marks and counts nothing.
- Skinning now counts a skin even when the corpse had no loot, and the skin loot attaches to the corpse that was actually skinned. A corpse with nothing in it produces a `LOOT_OPENED`/`LOOT_CLOSED` pair in the same instant, and the recorder used to treat that empty window as "the corpse the player just looted" — so the cast was pinned to the empty corpse and the real skin window was filed as ordinary corpse loot. The corpse you skinned was never marked skinned, which also kept it out of the skinning farming circles. A real run that reported `kills=8 corpse-windows=3 skin-windows=1 skin-casts=2 | lost casts=1` now reports `lost casts=0` with the skinned corpse carrying its own skin items.
- The skinning tooltip no longer forgets a creature once 100 newer corpses land behind it. Kills, skinned count and skinning item counts are kept per creature id and never evicted, so a beast you have skinned dozens of times shows its totals instead of `no observations here yet`; the 100-record window is now only the source of the farming-circle positions. An existing save is upgraded in place on the next load — its totals are seeded from the corpses it still holds, every record is kept, and the upgrade happens exactly once.

## [0.3.3-beta] - 2026-11-11

### Added
- Touchstone can score and gate gear for a chosen spec (`/up spec`, and a Gear for picker under Touchstone in settings) even when you are talented into a different one. Auto still follows your current talents. A spec without a sourced profile would stay silent (`no sourced weights for <spec> yet`) rather than guessing another pack.
- Wowhead is the sole source for every shipped Touchstone spec. All 28 Forever specs (including Feral Cat) use the published stat-priority list as an order-only, cap-aware profile: tiers are compared in published order, the first differing tier decides, and there are no invented numeric weights. Per-spec caps come from each page (for example melee hit is 8% for Arms / Rogue / Feral Cat / Enhancement and 9% for Fury / Retribution / Hunter; Rogue then has a second Hit cap at 17% for poisons). When the client can be read, gains past a cap do not count and losses that drop below a cap do; otherwise the verdict says cap status unknown and still ranks the stat. Each profile records its Wowhead URL and the page's updated date (pages fetched 2026-11-11). The lists live in `data/wowhead_stat_priorities.json`; `tools/gen_wowhead_priorities.py` regenerates the Lua tables, so an update is a data change.
- Tank defaults follow Wowhead's published variants: Protection Warrior and Protection Paladin use the Balanced list, and Feral Bear (which has no Balanced list) uses Defensive. The Gear for picker also exposes Defensive and Offensive as `Protection (Balanced)` / `Protection (Defensive)` / `Protection (Offensive)` and `Feral (Bear, Defensive)` / `Feral (Bear, Offensive)`.
- Enhancement keeps Wowhead's published order as written, with no extra tiers. Its verdicts append a caveat — `Wowhead list predates the Nov 10 Mental Dexterity hotfix; Intellect may be overrated. Hit past the listed 8% melee minimum is not scored.` — from a per-profile `caveat` field (`data/wowhead_profile_caveats.json`, citing the official Forever hotfix notes). Remove that entry and regenerate when the Wowhead page is updated.
- Leveling-only tags on a list (Elemental `Strength (Only while leveling)`, Restoration Shaman `Spell Damage (Only while leveling)`) apply only below level 60.

### Fixed
- Defense skill is the Classic `UnitDefense` total (`base + armorBonus`), so a 440-cap window can close and a later tier such as Armor can decide.
- Expertise is no longer converted with an unsourced rating-per-percent of 10. Forever percent tooltip text is compared directly to Wowhead's 6.5% / 14% caps; a rating-only line reports cap status unknown.
- Caster 17% spell-hit caps read `GetSpellHitModifier` (and spell hit rating), not melee hit chance. Expertise current is only taken from APIs that return a percent (`GetExpertisePercent` or `GetCombatRatingBonus`). Weapon skill is read as a skill total (`UnitAttackBothHands`), not `GetCombatRating(CR_WEAPON_SKILL)`.
- Enhancement follows Wowhead's numbered list exactly: hit past the listed 8% melee minimum is not scored, and that is noted in the caveat. The Mental Dexterity caveat cites the official Forever hotfix notes (`https://news.blizzard.com/en-us/article/24315281/wow-forever-hotfixes-november-10-2026`).
- `/up spec` with no argument names a recorded `/up role` when Auto is in effect (precedence is chosen spec > `/up role` > talents). `/up reset` also clears a chosen Gear-for spec (back to Auto) and does not clear `/up role` or the log.
- Arcane and Fire Mage Hit caps are scored as spell hit. `hitKind` is taken from the spec profile family (every Hit tier on a spell profile is spell), not from caps-map keywords, so a 17% cap that mentions Arcane Focus or Precision uses `GetSpellHitModifier`.
- Combat-rating reads no longer invent a `CR_*` index when the client does not expose one (`CR_EXPERTISE`, `CR_HIT_MELEE`, and any other guessed `CR_*` fallback).
- Mixed percent-vs-rating Expertise is a trade-off with cap status unknown, not a comparison that treats the missing percent as 0.
- Dual-wield weapon skill uses the lower of the two hands from `UnitAttackBothHands` only when an off-hand weapon is equipped (`OffhandHasWeapon`, or slot 17 as `INVTYPE_WEAPON` / `INVTYPE_WEAPONOFFHAND`). The unarmed skill Classic reports in the off-hand slots for a two-hander or a shield is ignored.
- An item that has both percent Expertise text and `ITEM_MOD_EXPERTISE_RATING` uses the percent only.
- Expertise percent text matches Forever item wording (`Reduces the chance for your attacks to be dodged or parried by N%`).

## [0.3.2-beta] - 2026-11-11

### Added
- `/mp idea` (also `/mpack idea`, and a Suggest an idea button next to Report a bug) opens a movable popup with a pre-filled, already-selected idea to copy into #mightiepack-ideas. Addon version, client version, and an Area line (NodeTrail / Touchstone / Skinning / General, or a single area if given as `/mp idea nodetrail`; only the first word after `idea` is used) are filled in; character names, realms, class, level, zone, and Lua errors are left out. WoW cannot write the clipboard, so the player presses Ctrl+C.

### Fixed
- The Report a bug / Suggest an idea popup now shows the pre-filled text in a typable, selectable EditBox (a font is applied, the box has a real size, and the frame is toplevel above the Options window) and has a single Close button.
- The MightiePack options page uses a vertical flow so the skinning-circle status no longer overlaps its checkbox, Alchemy's Scan now sits under its status, and Feedback has Report a bug and Suggest an idea side by side.
- The skinning tooltip no longer hides known skin/leather details when the unit is not a Beast (for example Cursed Darkhound, a Demon). Known records are shown regardless of creature type; the empty "no observations" hint stays Beast-only when we have no data for that NPC.

## [0.3.1] - 2026-11-11

### Added
- `/mp bug` (also `/mpack bug`, and a Report a bug button) opens a movable popup with a pre-filled, already-selected report to copy into #mightiepack-bugs. Addon version, client version, enabled modules, class and level, zone/map, and the last MightiePack Lua error are filled in; character names and realms are left out. WoW cannot write the clipboard, so the player presses Ctrl+C.

## [0.3.0]

### Added
- Skinning farming circles: closed routes built from the character's own recorded
  skins, per zone, drawn on the world map and the minimap, shown only once a zone
  has skinning data and only to a character with Skinning.
- Herb tooltip drop rates and pick counts per node.
- Touchstone gear advice inside the pack: a two-tier verdict where Strength,
  Spell Power, Agility and Intellect decide, and Armor and Stamina break ties only.

### Changed
- The world-map route is parented to `WorldMapFrame` and projected onto the visible
  map rect; children of the map canvas are not composited on this client, which is
  why the route used to be invisible.
- The minimap route is drawn from the zone's real yard scale (measured at three
  points in the Barrens) instead of a fixed map fraction.
- The waypoint arrow is off by default and a stored "on" from an earlier build is
  migrated off once.
- Auto-refresh re-plans every 5 gathers.

### Fixed
- Tooltip panels no longer advertise Alchemy recipes the character cannot make; the
  recipe-uses line is parked behind a default-off switch until the client's recipe
  API can be trusted again.
- Beast tooltip shows skinning yields only.
- Toasts no longer outlive their intended lifetime.

## [0.2.0]
- NodeTrail herb routing, map and minimap overlays, recorder.
