# Changelog

All notable changes to MightiePack. The format follows Keep a Changelog, and the
project uses semantic-ish versioning: the pack version in `MightiePack.toc` is the
one CurseForge shows, and the bundled modules report the same number.

## [Unreleased]

### Added
- Touchstone can score and gate gear for a chosen spec (`/up spec`, and a Gear for picker under Touchstone in settings) even when you are talented into a different one. Auto still follows your current talents. A spec without sourced weight numbers is silent (`no sourced weights for <spec> yet`) rather than guessing another pack.
- Touchstone now ships ForeverDB hand-set leveling stat weights (already rescaled so the top non-weapon stat is 4; client 1.60.1 build 70862) for every Forever spec that has a PvE item-weight file — 26 numeric profiles. Feral (Cat) still has no item weights (sim / order-only lists only) and stays silent.
- Retribution is an exception by ruling: it follows Wowhead's published *Retribution Paladin Stat Priority in WoW Forever* (https://www.wowhead.com/forever/guide/classes/paladin/retribution/stat-priority-pve-dps, updated 2026-10-31) as an order-only profile, with no invented numeric weights. Tiers are compared in published order; the first differing tier decides. Hit is capped at 9% and Expertise at 6.5% when the client can be read (otherwise the verdict says cap status unknown and still ranks the stat). The page is beta-based and says the priority will shift once level 60 dungeon and raid gear is available. The order-only path is general, so other specs can switch to a Wowhead order later without a second engine.

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
