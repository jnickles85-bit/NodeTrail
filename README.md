# MightiePack — NodeTrail and Touchstone

MightiePack is an umbrella addon for WoW Forever Classic (Interface 16001). It
ships two modules: **NodeTrail** (herb routes, herb tooltips, Alchemy recipe
uses, and a skinning recorder with farming circles) and **Touchstone** (gear
upgrade advice; formerly StatForge). Tick a module in `/mp` options to turn it
on.

## Install
1. Remove any old standalone `NodeTrail` or `Touchstone` AddOns folder first.
   Both define globals the pack also uses (`NodeTrail`, `/nt`; `StatForge` /
   `StatForgeDB`).
2. Copy the `MightiePack` folder into the client's AddOns folder.
3. GatherMate2 is optional.

## Modules
| Module | Description | Default |
|--------|-------------|---------|
| NodeTrail | Herb routes, tooltips, Alchemy uses, and the skinning recorder / farming circles | On |
| Touchstone (formerly StatForge) | Gear upgrade advice (vendored Touchstone 0.8.3) | Off |

Touchstone's files are generated into `MightiePack/Modules/Touchstone/` by
`tools/sync_touchstone.py` from the pinned StatForge commit, plus anchored
fold edits and post-copy patches under `tools/touchstone-patches/`. Do not
hand-edit the vendored files without adding or updating a patch — a re-sync
would drop an unanchored change (including the ChestAdvisor secret-values
guard). The module refuses to run while the standalone `Touchstone` addon
folder is installed. Remove that folder and reload to use the vendored copy.

## Slash commands

Aliases: `/mp` = `/mpack` = `/mightiepack`. Touchstone (formerly StatForge)
registers `/touchstone`, `/sf`, and `/statforge` on one handler, and `/ts`,
`/up`, `/upgrade`, and `/chestadvice` on the advisor handler. Commands marked
**(diag)** are diagnostics.

| Command | Description |
|---------|-------------|
| `/mp` or `/mp options` or `/mp config` | Open the pack options panel |
| `/mp status` | Print pack version, interface, client build, and module on/off state |
| `/mp bug` | Open the bug report popup (no upload — copy and paste into Discord) |
| `/mp idea [area]` | Open the idea popup (optional area: nodetrail, touchstone, skinning, general) |
| `/mp skindiag` **(diag)** | Toggle the skinning event-capture probe |
| `/mp skindiag dump` **(diag)** | Print the captured skinning steps to chat |
| `/mp skindiag copy` **(diag)** | Open a compact, copyable dump in the bug-report popup |
| `/nt help` | Print NodeTrail help (only while NodeTrail is enabled) |
| `/nt start` | Draw the herb density route for the current zone |
| `/nt stop` | Clear the herb route |
| `/nt reload` | Rebuild the active herb route from current data |
| `/nt status` | Route source, herb counts, tooltip / Alchemy / module state |
| `/nt autorefresh [on\|off\|<picks>]` | Auto re-plan every N gathers (default on, 5); never in combat or with a loot window open |
| `/nt minimap [on\|off]` | The minimap herb line on its own; the world-map route is unaffected |
| `/nt scanrecipes` (alias `/nt recipes`) | Recipe-scan status; scans now if the Alchemy window is open |
| `/nt recipediag [id\|name]` **(diag)** | Raw trade-skill values for one craftable and one non-craftable recipe |
| `/nt mapdiag` **(diag)** | World-map / minimap frame environment, if the route does not appear |
| `/nt mapdiag probe [off]` **(diag)** | Draw a marker, a border, and one diagonal on the map overlay |
| `/nt navdiag` **(diag)** | What this client can tell us about yards (C_Map, HereBeDragons, zone size, arrow) |
| `/nt arrow [on\|off]` | Next-waypoint arrow with the distance counting down |
| `/nt navwalk [start\|mark <label>\|clear]` **(diag)** | Record a walk of player coords and drawn-dot anchors; `clear` drops the recorded stops |
| `/nt skinroute [on\|off\|status]` | Green closed loop through skinned corpses on this zone's map |
| `/nt skin [on\|off\|status]` | Corpse-skinning recorder (on by default); an explicit off survives `/reload` |
| `/nt ttdiag` **(diag)** | Item-name resolver failures (ids that could not be named, and which lookups failed) |
| `/touchstone` (aliases `/sf`, `/statforge`) | Toggle the Touchstone window |
| `/touchstone options` | Open Touchstone on the Settings tab |
| `/touchstone diag` or `diagnostics` **(diag)** | Open the Touchstone diagnostics panel |
| `/touchstone doctor` **(diag)** | Print the diagnostics report and open the panel |
| `/touchstone probe` **(diag)** | Run the deep probe into SavedVariables |
| `/touchstone stats <itemlink>` **(diag)** | Print this client's `C_Item.GetItemStats` pairs for a pasted link |
| `/ts` (aliases `/up`, `/upgrade`, `/chestadvice`) | Open the Touchstone window |
| `/ts help` | Print the advisor command list |
| `/ts scale <0.5-1.5>` | Window scale (also the Settings slider; saved across `/reload`) |
| `/up role <melee\|spell\|clear>` | Record the focus role for a hybrid class |
| `/up spec [key\|name\|auto]` | Which spec Touchstone scores gear for (overrides talents and `/up role`) |
| `/up tooltip <on\|off>` | Item-tooltip verdict line (default on) |
| `/up detail <full\|compact\|upgrades>` | How much the tooltip shows (default full) |
| `/up toast <on\|off>` | "Upgrade found!" toast (default on) |
| `/up toast lifetime <seconds>` | Toast lifetime, 1–30 (default 3.5) |
| `/up toasts` or `/up testtoast` **(diag)** | Raise one "Test Upgrade" toast now |
| `/up toastdebug [on\|off\|dump]` **(diag)** | Trace every toast transition with timestamps |
| `/up glyphs <on\|off>` | Colorblind-safe marker glyphs (default off) |
| `/up reset` | Restore display defaults and clear a chosen Gear-for spec; does not clear `/up role` or the log |
| `/up log` / `/up log clear` | Disagreement log (items you equipped that were not called an upgrade) |
| `/up rescan` | Re-scan bags now |
| `/up probe` **(diag)** | Run the Phase D probes (read-only) |
| `/up diag` **(diag)** | Write a SavedVariables + global diag record; print rows to chat |

Retired Touchstone words (`/touchstone export`, `/touchstone gear`) print that
those features are retired; they are not silently ignored.

## Options
- Open with `/mp`, `/mpack`, or `/mightiepack`.
- Tick a module: turns on immediately, no reload.
- Untick: confirm popup "Turn off <module>? This needs a UI reload." OK saves it off and runs ReloadUI(); Cancel (or Escape) keeps it on and re-ticks the box.

## Layout
Shipping addon (the CurseForge zip contains this folder only):

```
MightiePack/MightiePack.toc
MightiePack/Core.lua
MightiePack/Modules.lua
MightiePack/Options.lua
MightiePack/BugReport.lua
MightiePack/ErrorHandler.lua
MightiePack/Modules/NodeTrail/Config.lua
MightiePack/Modules/NodeTrail/Core.lua
MightiePack/Modules/NodeTrail/Data/Density.lua
MightiePack/Modules/NodeTrail/Data/GM2.lua
MightiePack/Modules/NodeTrail/Data/HerbData.lua
MightiePack/Modules/NodeTrail/Data/ItemNames.lua
MightiePack/Modules/NodeTrail/Data/Profession.lua
MightiePack/Modules/NodeTrail/Data/Recipes.lua
MightiePack/Modules/NodeTrail/Data/Recorder.lua
MightiePack/Modules/NodeTrail/Data/SkinHints.lua
MightiePack/Modules/NodeTrail/Nav/Arrow.lua
MightiePack/Modules/NodeTrail/Nav/Source.lua
MightiePack/Modules/NodeTrail/Nav/Target.lua
MightiePack/Modules/NodeTrail/Route/Auto.lua
MightiePack/Modules/NodeTrail/Route/Build.lua
MightiePack/Modules/NodeTrail/Route/Cluster.lua
MightiePack/Modules/NodeTrail/Route/SkinRoute.lua
MightiePack/Modules/NodeTrail/UI/LineDraw.lua
MightiePack/Modules/NodeTrail/UI/MapOverlay.lua
MightiePack/Modules/NodeTrail/UI/MinimapPath.lua
MightiePack/Modules/NodeTrail/UI/PathGeom.lua
MightiePack/Modules/NodeTrail/UI/Tooltip.lua
MightiePack/Modules/NodeTrail/UI/TooltipPanel.lua
MightiePack/Modules/NodeTrail/locale/enUS.lua
MightiePack/Modules/Skinning/Core.lua
MightiePack/Modules/Skinning/Probe.lua
MightiePack/Modules/Skinning/Record.lua
MightiePack/Modules/Touchstone/Bootstrap.lua
MightiePack/Modules/Touchstone/Constants.lua
MightiePack/Modules/Touchstone/UI.lua
MightiePack/Modules/Touchstone/OptionsTab.lua
MightiePack/Modules/Touchstone/UpgradesTab.lua
MightiePack/Modules/Touchstone/LogTab.lua
MightiePack/Modules/Touchstone/Diagnostics.lua
MightiePack/Modules/Touchstone/Probe.lua
MightiePack/Modules/Touchstone/Integration.lua
MightiePack/Modules/Touchstone/Core.lua
MightiePack/Modules/Touchstone/ChestAdvisor/Verdict.lua
MightiePack/Modules/Touchstone/ChestAdvisor/ChestAdvisor.lua
MightiePack/Modules/Touchstone/ChestAdvisor/marker.tga
```

Also shipped in the zip (not listed above): `CHANGELOG.md` and `LICENSE`.

Repo-only (not shipped): `README.md`, `tests/`,
`tools/` (`sync_touchstone.py`, `touchstone-patches/`, `gen_wowhead_priorities.py`),
`data/`, `evidence/`, `docs/archive/HANDOFF.md`, `.github/`, `.luacheckrc`,
`.pkgmeta`.

## NodeTrail details
- Herb routes come from your own recorded herb gathers, drawn as a density corridor.
- GatherMate2 is optional (`routeSource = "gm2"` fallback).
- Teal polyline for herb routes (Touchstone accent, pathColor `{0.400, 0.988, 0.945, 0.85}`), rust for skinning; dark outline, direction chevrons, and start/end or loop markers. pathWidth 2 on world map and minimap.
- `/nt stop` releases both overlays.
- `/nt skinroute` draws the skinning farming circle once a zone has enough skinned corpses and the character has Skinning. `/nt skin` toggles the recorder.

### Optional GatherMate2 fallback
- GM2 adapter uses `GatherMate2:GetNodesForZone(mapID, "Herb Gathering", true)` and `DecodeLoc`, never scrape GatherMateData2HerbDB or hardcode zone names.

### Herb tooltip
- Hover an in-world herb node to see drop percentages and your personal pick counts.
- Baseline drop rates are shown for the 28 Classic herb nodes.
- After 10 or more recorded gathers of a herb, your personal drop rates replace the baseline.
- Open the Alchemy trade skill window once to see which learned recipes use the herb.
- The Alchemy line lists only the recipes this character can craft now: the scan records
  `C_TradeSkillUI.GetCraftableCount`, `IsRecipeProfessionLearned` and `requiredSkillRank`
  (plus the legacy count/learnable returns when present), and the rest are counted in a
  `+N more you can't make yet` tail.
- A client that exposes none of those signals draws NO Alchemy line at all — an unfiltered
  list of crafts the character cannot make is worse than silence. The options panel says
  "Alchemy scan isn't available on this client yet"; `/nt recipediag [id|name]` prints the
  raw per-recipe values.
- A drop's NAME is stored with its id at loot time, copied out of the loot slot's own item
  link (`|h[Frilled Lichen]|h`) — this client's `GetItemInfo` cannot name a custom id, so the
  id alone is not enough. One resolver order, for herbs, skinned items and corpse drops:
  stored name -> our own table -> `GetItemInfo` -> `item <id> (name unavailable)`. Never a
  bare id. `/nt ttdiag` lists any id that could not be named and the lookups that failed.

## Skinning recorder (NodeTrail sub-option)
On by default (`NodeTrailDB.skinning.enabled`): a fresh install records from the
first corpse with no setup. A one-time migration turns the old default on for an
existing install. An explicit off — un-ticking the Options box or `/nt skin off`
(`/nt skin status` reads it back) — is written as the player's own choice
(`skinUserSet`) on 0.3.4 and later, so it survives `/reload` and later updates.
The migration cannot distinguish an off set under 0.3.3 or earlier (the flag did
not exist) from a player who never touched the setting, so those older offs are
turned back on once.

When on, the addon records one entry per corpse, keyed by the corpse GUID, in
`NodeTrailDB.skinning.chars["Name-Realm"]`: mob GUID/name/entry, zone/subzone/map
+ position at death, the ordinary corpse loot (items from `LOOT_OPENED`), whether
a Skinning cast succeeded, the skinning loot, and the gap between the corpse loot
closing and the skin window opening. The two item lists are separate fields —
never merged. Only counts of what was actually seen are stored; no drop rate is
computed from such a small sample.

That per-corpse window is the newest 100 corpses per character (`R.MAX_RECORDS`),
and the positions in it are what the skinning farming circle is drawn from. The
numbers the beast tooltip prints are NOT aggregated from it: they are kept per
creature id in
`NodeTrailDB.skinning.chars["Name-Realm"].creatures[creatureID]` (corpses, kills,
skinned, skin windows and the skinning item counts), which accumulate for as long
as the character exists and are never evicted. The beast tooltip shows `skinned: N`
and the top skin materials; kills stay in `/mp skindiag`. A store written before
that table existed (schema 1) is upgraded in place on the next load.

`COMBAT_LOG_EVENT_UNFILTERED` is a protected event on Forever 16001 and is never
registered — kills come from `UNIT_DIED` (whose argument is the creature GUID).
`LOOT_CLOSED` and `LOOT_SLOT_CLEARED` both fire twice per event on this client and
are de-duplicated before recording. `/mp skindiag` toggles the capture,
`/mp skindiag dump` prints the captured steps, and `/mp skindiag copy` opens a
compact dump in a copyable popup.

## Tests
Run from repo root with lua5.1 (`lua5.1 tests/<name>.lua`). 70 specs:

- `tests/alchemy_skill_gate_spec.lua`
- `tests/beast_profession_gate_spec.lua`
- `tests/bugreport_spec.lua`
- `tests/chestadvisor_diag_spec.lua`
- `tests/chestadvisor_secret_values_spec.lua`
- `tests/density_spec.lua`
- `tests/diag_truthful_spec.lua`
- `tests/draw_smoke.lua`
- `tests/event_gate_spec.lua`
- `tests/gear_for_spec.lua`
- `tests/idea_spec.lua`
- `tests/item_name_capture_spec.lua`
- `tests/mapdiag_spec.lua`
- `tests/mapdiag_visible_spec.lua`
- `tests/mapdiag_zorder_spec.lua`
- `tests/mapdot_capacity_spec.lua`
- `tests/mapdot_scale_spec.lua`
- `tests/mapdraw_primitive_spec.lua`
- `tests/mapframe_projection_spec.lua`
- `tests/maplegibility_spec.lua`
- `tests/mapoverlay_spec.lua`
- `tests/minimap_diag_spec.lua`
- `tests/minimap_hbd_spec.lua`
- `tests/minimap_units_spec.lua`
- `tests/minimap_walk_spec.lua`
- `tests/nav_arrow_spec.lua`
- `tests/nav_target_spec.lua`
- `tests/options_spec.lua`
- `tests/pathcolor_migration_spec.lua`
- `tests/pathgeom_spec.lua`
- `tests/profession_gate_spec.lua`
- `tests/recipe_diag_spec.lua`
- `tests/recorder_spec.lua`
- `tests/route_auto_spec.lua`
- `tests/route_stability_spec.lua`
- `tests/route_style_spec.lua`
- `tests/skin_tooltip_skinned_spec.lua`
- `tests/skin_tooltip_spec.lua`
- `tests/skindiag_copy_spec.lua`
- `tests/skindiag_secret_spec.lua`
- `tests/skindiag_spec.lua`
- `tests/skinning_default_on_spec.lua`
- `tests/skinning_dump_spec.lua`
- `tests/skinning_empty_window_spec.lua`
- `tests/skinning_guardless_spec.lua`
- `tests/skinning_items_spec.lua`
- `tests/skinning_migration_spec.lua`
- `tests/skinning_pending_attrib_spec.lua`
- `tests/skinning_recorder_spec.lua`
- `tests/skinning_totals_spec.lua`
- `tests/skinning_totals_window_spec.lua`
- `tests/skinroute_spec.lua`
- `tests/slash_spec.lua`
- `tests/status_meta_spec.lua`
- `tests/sync_touchstone_patch_spec.lua`
- `tests/toast_test_spec.lua`
- `tests/toast_trace_spec.lua`
- `tests/tooltip_no_gametooltip_writes_spec.lua`
- `tests/tooltip_panel_spec.lua`
- `tests/tooltip_refresh_spec.lua`
- `tests/tooltip_spec.lua`
- `tests/touchstone_assets_spec.lua`
- `tests/touchstone_fold_spec.lua`
- `tests/touchstone_loadorder_spec.lua`
- `tests/touchstone_secret_guard_spec.lua`
- `tests/touchstone_tiebreak_spec.lua`
- `tests/touchstone_tooltip_line_spec.lua`
- `tests/touchstone_weights_spec.lua`
- `tests/ttdiag_minimal_spec.lua`
- `tests/umbrella_spec.lua`
