# Changelog

All notable changes to MightiePack. The format follows Keep a Changelog, and the
project uses semantic-ish versioning: the pack version in `MightiePack.toc`
(substituted from the git tag by the packager) is the one CurseForge shows.
Touchstone still carries its own upstream module version, which may appear in
About and diagnostic lines; the Touchstone window header shows the pack version.

## [Unreleased]

### Added
- Skinning farming circles survive ring turnover: unskinned kills are evicted from the 100-corpse ring first, and a skinned record with a map position is folded into a durable per-map hotspot grid (2% map-width cells, the same cell size and `{n, nodes, last}` shape as the herb-history grid, plus stored positions for the circle) before it leaves the ring. Guid idempotency lives in `cell.seen` (one entry per counted fold, not trimmed by the 32-point sample cap), so a re-fold of a guid that missed the `pts` cap cannot increment `n`; only the position samples are capped, and the circle reads at most those 32 points per cell. A fold is committed before the record is removed from the ring, so a crash mid-eviction can retry without losing the position. A skinned record evicted with no map position cannot be folded and is counted per map in `unpositionedEvicted`. The circle is built from that store plus the ring, so `MIN_SKINS` counts both. A one-time migration folds the current ring's skinned positions into the store and never discards data. A load backfills `cell.seen` from existing `pts` even when `hotspotsSeeded` is already set, so a save written before `seen` existed cannot be double-counted. `seen` is stamped after `n` is incremented. `cell.seen` and `unpositionedEvictedGuids` grow without a bound, at about 38 bytes per unique skinned corpse.

### Changed
- Herb gathering history is now capped per map without wiping a player's totals. `NodeTrailDB.herbs.maps` still stores raw picks (position, time, items) in the same shape, but only the newest 2,000 per map are kept — the bound the audit recommended, and well above the 40 stops a density route already uses. Lifetime pick counts (`total` and per-map) and the personal drop-rate stats the tooltip shows are stored in aggregates and are never evicted. When a raw pick is trimmed it is folded into a compact, never-evicted per-map hotspot grid (`herbs.hotspots[mapID][cell] = {n, nodes, last}`, 2% map-width cells, bounded to 50×50 cells and 32 node keys per cell) so a later "Find a resource" feature can query `NT.Hotspots(mapID, nodeFilter)`. Density routes still see only the newest 2,000 raw picks; they do not yet read the hotspot cells. An existing schema 1 save is migrated in place once: aggregates are computed from every raw record still in the file, trimmed picks seed the hotspot grid, a per-map folded marker (`aggT` / `hsT` / `n`) is written so a downgrade that re-attaches raw picks cannot double-count or drop history on the next upgrade, the schema marker is stamped, and only then are oversized lists replaced. A crash before the stamp retries from the intact raw lists; a second load does not re-seed from the trimmed ones. A newer numeric schema is never downgraded. A non-numeric schema is treated as unknown and left alone.
- Touchstone order-only verdicts are more cautious: an item is an Upgrade only when it is equal or better on every ranked Wowhead stat and better on at least one. A gain on a higher-ranked stat with a loss on a later ranked stat is now a Trade-off (for example Trophy Belt +5 Intellect vs Stormbringer Belt +5 Strength / +2 Stamina). A loss on the first differing ranked stat is still a Downgrade. Unranked stats such as Spirit, or Armor on non-tank specs, still do not decide. Ranked equality uses the named WEIGHT_EPSILON floor so float noise cannot mint an Upgrade. The tooltip keeps the deciding tier and names both sides of a Trade-off.
- Herb and skinning routes are drawn as a continuous stroke with a dark outline, direction chevrons, and start/end (or loop) markers, instead of a dotted stair-step. Defaults are teal for herbs (the pack's Touchstone accent) and rust for skinning; a steel colour is reserved for mining if that route type is added later. Smoothing is light and keeps every stop on its node. An existing save still holding the old white default is migrated to teal once; any other stored path colour is left alone. The options panel notes the colour legend next to the route toggles.

### Fixed
- A herb pick recorded after the clock goes backwards (`t` older than the per-map `aggT` watermark) is now folded into `mapTotals` and the personal drop-rate stats. Historical picks below the watermark are still skipped, a second load does not double-count, and `hsFolded` / `aggFolded` idempotency is unchanged. `RecordHerb` already counted those picks in the session; the load path now catches appends that had not yet reached the totals. For the `t == aggT` / `aggTN` gate, only marks on records with `t >= aggT` (or untimed) count toward `anyMarked`, so a leftover stamp on a trailing rollback pick cannot disable the skip and double-count history at the watermark. The same reached-watermark rule is used when backfilling a pre-#29 or `noTN`-only save, so a trailing uncounted `t < aggT` pick is not stamped and still reaches the totals.
- The capped-window check in Touchstone's order-only verdict (Hit, Expertise, and other cap tiers) uses the same `ranksAsDifferent` WEIGHT_EPSILON floor as the other ranked tiers, so a rating crumb cannot mint an Upgrade. `tiebreakTotal` uses that same floor instead of an exact `~= 0` comparison.
- Route-line leftovers after PR #27: the contain clip tests now drive `decorClip` itself (including the SQUARE and CORNER insets); decoration clip pads are per kind, and a start/end or loop marker uses half of (`core` + `DECOR_RIM`) so it is not dropped by the larger chevron-arm pad; `_viewAuxHooked` is set only after the canvas OnSizeChanged hook is installed successfully, so a nil or failed canvas can be retried; `numberMethod` drops a value `canaccessvalue` rejects, matching `readPoint`.
- Herb aggregate and hotspot folds no longer drop a second pick from the same second. Aggregates key off `aggT` / `aggTN` for kept records (a mid-loop crash stamp `aggFolded` is cleared once the pass finishes, so a full map does not keep a mark on every raw pick, about 30 KB or 15 bytes per record for 2,000 records). Historical picks with `t < aggT` are skipped; `anyMarked` only gates the `t == aggT` `aggTN` skip, so a same-second sibling is not swallowed after a crash and an unmarked older pick is not re-counted. Only marks on records with `t >= aggT` (or untimed) count toward that gate. A trailing clock-rollback append that is not yet in `mapTotals` is still applied. A schema-2 save from before this change (`aggT` set, no `aggTN` or marks, or a `noTN`-only marker with `aggT` still 0) is backfilled without re-applying totals and without stamping a trailing uncounted rollback pick. A downgrade that re-attaches unmarked picks still skips timestamps below the watermark; at the watermark only the stored `aggTN` / `hsTN` count is treated as already folded.
- `NT.Hotspots` returns a copy of each cell's `nodes` table, so a caller cannot mutate the store. A pick folded into the herb hotspot grid is marked `hsFolded` on the record itself, so a crash mid-loop, a second live trim of new untimed picks, or two evicted picks that share a timestamp cannot skip or double-count (idempotency does not use `noTN` or compare `t` to `hsT` on the first pass). `hsT` remains only as a fallback for a downgrade that re-attaches the trimmed prefix without the mark. `HerbCellKey` recognises a client SECRET coordinate and reaches `tonumber` only through `pcall`.
- A mid-seed crash during the skinning schema 1→2 upgrade could leave `skinContribution` stamps on records and under-count per-item totals on retry. Seeding now clears those stamps first, then rebuilds the totals, so a retry cannot under-seed.
- Chevrons and start/end markers are hidden when a route cannot be drawn (the same `MarkIdle` path the stroke drawer already used), instead of remaining on the map. The minimap no longer draws decorations across an unprojected vertex, including a missing first or last point (those ends are never treated as a closed loop, and start/end markers sit on the first and last usable vertices). Decorations and leftover pool regions are clipped to the minimap, so they cannot paint over the rest of the UI. It skips rebuilding a projection when the route, zoom, rotation, position, minimap shape, instance, colour, and width have not changed, and rebuilds when any of those change. The world-map overlay redraws when the canvas scale or pan changes, so a zoom or scroll cannot leave the route stuck to the window. A diagonal stroke prefers a proved SetRotation primitive as the confirmed default (texcoord is only used when `/nt linetest use texcoord` pins it), and otherwise uses a heavier-overlapping dot chain; `/nt linetest` measures which method this client keeps. Chevrons and start/end/loop markers use the same `Interface/Buttons/WHITE8X8` + SetVertexColor path and the same OVERLAY sublevels (rim 6, core 7) as the rotate stroke, because a core at sublevel 8 is outside the client's -8..7 range and was dropped under the black rim. Chevrons are a rust V of two short ticks with no rim; start/end/loop markers are a light cream square at half the previous size (3.5 screen px, loop 4.5) with a 1-screen-px dark rim (at least one pixel larger than the core after snap). A saved path colour of `{1,1,1}` with no alpha is treated as the old white default and migrated to teal; leftover green fallbacks for the skinning route now use rust.
- Route-line follow-ups after PR #26: the cream marker rim is 1 screen px so it stays visible after pixel snap; ClipItems and the world-map window clip test a chevron by its arm extent, not only its centre; SetClipsChildren on the minimap host is used only when the client exposes it; LineProof only marks CreateLine as taken when the PROBE_SPAN endpoints round-trip; `/nt linetest` invalidates the style drawers as well as the stroke drawers; `_viewHooked` is set only after the ScrollContainer hooks are actually installed; `numberMethod` drops a result `issecretvalue` flags. Minimap decorations use a containing clip (a chevron whose arm would cross the ROUND inset is dropped) so they cannot paint into the square host's corners.
- README Layout now lists `CHANGELOG.md` and `LICENSE` as shipping in the zip (they were wrongly called repo-only). `/nt help` documents `/nt ttdiag` and `/nt navwalk ...|clear`. The skinning default-on comment in `Config.lua` matches the 0.3.4 changelog: offs set before 0.3.4 are turned back on once. `pkg.PackVersion()`'s comment matches GetAddOnMeta (the C_AddOns path returns `dev` for a source token; the legacy path returns the raw token). Touchstone sync patches require a unique context match per hunk and fail if a patch applies zero hunks.

### Changed
- The Touchstone window header shows the pack version from the TOC, not Touchstone's upstream module version. The module version remains on the Settings About line and in diagnostic output.
- Pack options no longer show a raw Alchemy scan error under Alchemy Recipes. The line now reads "Alchemy scan isn't available on this client yet"; `/nt recipediag` and the Scan-now chat line still carry the technical text.
- README slash table covers `/mp` (including `bug`, `idea`, and `skindiag` / `skindiag copy`), the `/nt` family, and the Touchstone family (`/touchstone`, `/ts`, `/sf`, `/up`, and aliases). Diagnostic commands are marked as such. Layout and Tests are regenerated from the tree. `HANDOFF.md` is archived under `docs/archive/`.
- CI pins Lua 5.1 and LuaRocks (leafo actions by SHA), caches luacheck, and times out a stalled toolchain install separately from lint.

### Fixed
- The vendored Touchstone secret-values guard (and other NodeTrail-local Touchstone edits) is reproduced by an anchored post-copy patch in `tools/sync_touchstone.py`, so a re-sync cannot silently drop the ChestAdvisor crash fix.
- `pkg.version` is no longer a hardcoded `"0.3.0"`. The pack version is read from the TOC via `pkg.PackVersion()` (nil-safe).
- The Touchstone Settings "Reset to defaults" description wraps within the frame instead of running off the right edge.

## [0.3.5-beta] - 2026-11-11

### Fixed
- Skinning a pack more than 10 seconds after the kills, when the skin loot window has no loot-source GUID (common on this client — corpse windows already fell back to `UNIT_DIED`), now marks those corpses skinned. A GUID-less window may be attributed to the dead target only within a short bound after `UNIT_SPELLCAST_SUCCEEDED` (`TARGET_ATTRIB_WINDOW`, 3s starting value, to be live-measured), and only while that target is still the cast's corpse if known. The pending pin's GUID is never invented onto a GUID-less window, and target-change or an unclaimed `LOOT_CLOSED` clears that attribution, so a later herb, chest, or fishing window cannot be filed as skin loot. Live on v0.3.4-beta: 11 beasts killed and skinned on a map, the tooltip said `kills seen: 11 · skinned: 0` with no materials, and `/nt skinroute` said `0 of 8 skinned corpses` because no ring record had `skinned = true`.
- Skinning spell detection includes classic ranks `8613`, `8617`, `8618`, `10768` and Forever 1.60.1.70532 IDs `1240952`, `1240963`, `1240974`, `1240987`. The 4th `UNIT_SPELLCAST_*` argument on this client is a CastBar frame name and is not required to contain "skin".
- ChestAdvisor no longer errors when the Forever client returns a secret number from combat-stat APIs (`GetHitModifier`, `GetSpellHitModifier`, `GetCombatRatingBonus`, `GetExpertisePercent`, `UnitDefense`, `UnitAttackBothHands`). Those values still have type `number`, so adding them in `Verdict.playerHitPercent` raised `attempt to perform arithmetic on a secret number value (execution tainted by 'MightiePack')` — live, while opening the character sheet (`ChestAdvisor.scan` from the paper-doll refresh). Secret returns are now skipped (the cap is treated as unreadable) and a scan requested in combat is deferred until `PLAYER_REGEN_ENABLED`, checking `UnitAffectingCombat` as well as `InCombatLockdown`.

### Changed
- The beast tooltip no longer prints `kills seen`. It shows `skinned: N` and the top 4 skin materials for that creature as `Name xN`, using the name stored at loot time, with fallback `item <id>`. Kills remain in `/mp skindiag` and the saved totals.

### Added
- `/mp skindiag copy` and a **Copy skinning diagnostics** button next to Skinning (experimental) open a compact dump (header, counts/accounting, last ~20 steps) in the same copyable popup as the bug report, so it can be Ctrl+A / Ctrl+C pasted into Discord. The popup path does not print the dump to chat. It still opens when the collector is off and says so in the text.

## [0.3.4-beta] - 2026-11-11

### Changed
- The skinning recorder is on by default: a fresh install records from the first corpse with no setup. A one-time migration switches the previous default on for an existing install, and an explicit off — un-ticking Skinning (experimental) in settings or `/nt skin off` — is stored as the player's own choice (`NodeTrailDB.skinning.skinUserSet`), so it survives `/reload` and later updates and the migration never overrides it. `/nt skin status` reports the current state. Correction: that last claim is only true for offs recorded on 0.3.4 or later, when `skinUserSet` exists. An explicit off set under 0.3.3 or earlier is indistinguishable from a player who never touched the setting, so the one-time migration turns those older offs back on once.

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

## [0.3.1-beta] - 2026-11-11

### Added
- `/mp bug` (also `/mpack bug`, and a Report a bug button) opens a movable popup with a pre-filled, already-selected report to copy into #mightiepack-bugs. Addon version, client version, enabled modules, class and level, zone/map, and the last MightiePack Lua error are filled in; character names and realms are left out. WoW cannot write the clipboard, so the player presses Ctrl+C.

## [0.3.0-beta]

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
