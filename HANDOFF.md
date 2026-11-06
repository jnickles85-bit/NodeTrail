# NodeTrail Handoff

## Status
Base A (umbrella shell) was squash-merged to main as 852c15f (PR #2).
Base B (own herb recorder) was squash-merged to main as f1606d3 (PR #3).
Base C (density white path from our own herb data) was squash-merged to main as 3c0b012 (PR #4).
Base D (live herb tooltip) is on branch `mp/base-d-tooltip` @ b7d682b, PR #5 targets main (main merged in, no rebase), MERGEABLE/CLEAN.
Base E (slash polish) is on branch `mp/base-e-slash`, stacked on `mp/base-d-tooltip` (targets it; merge #5 first, then retarget #6 to main or merge main in; never rebase/force-push), PR #6.
Date: 2026-11-06.
The repo now ships one installable addon folder: `MightiePack/`.
Evening slice (Bases A-E) is code-complete. Next step is Mightie's in-game test on Forever; nothing has been deployed.

## Rules
- Locally (orchestrator) + local Qwen write code.
- Tinker leads the addon.
- Ask Mightie via Finkle before deploys, merge freezes, or renaming the umbrella.
- NO deploy to the Forever client (no deploy script, no copying into any AddOns folder) until Mightie says so.
- No force-push.
- Design source of truth: Mightie's vault note "Umbrella Gather Addon - Layout and Guidelines - 2026-11-06.md" (WoW Forever folder).

## Layout
```
MightiePack
MightiePack/Core.lua
MightiePack/MightiePack.toc
MightiePack/Modules
MightiePack/Modules.lua
MightiePack/Modules/NodeTrail
MightiePack/Modules/NodeTrail/Config.lua
MightiePack/Modules/NodeTrail/Core.lua
MightiePack/Modules/NodeTrail/Data
MightiePack/Modules/NodeTrail/Data/GM2.lua
MightiePack/Modules/NodeTrail/Data/Recorder.lua
MightiePack/Modules/NodeTrail/Data/Density.lua
MightiePack/Modules/NodeTrail/Data/HerbData.lua
MightiePack/Modules/NodeTrail/Data/Recipes.lua
MightiePack/Modules/NodeTrail/Route
MightiePack/Modules/NodeTrail/Route/Build.lua
MightiePack/Modules/NodeTrail/Route/Cluster.lua
MightiePack/Modules/NodeTrail/UI
MightiePack/Modules/NodeTrail/UI/LineDraw.lua
MightiePack/Modules/NodeTrail/UI/MapOverlay.lua
MightiePack/Modules/NodeTrail/UI/MinimapPath.lua
MightiePack/Modules/NodeTrail/UI/PathGeom.lua
MightiePack/Modules/NodeTrail/UI/Tooltip.lua
MightiePack/Modules/NodeTrail/locale
MightiePack/Modules/NodeTrail/locale/enUS.lua
MightiePack/Options.lua
README.md
tests
tests/draw_smoke.lua
tests/pathgeom_spec.lua
tests/recorder_spec.lua
tests/umbrella_spec.lua
tests/density_spec.lua
tests/tooltip_spec.lua
tests/slash_spec.lua
```

## How modules load
- One TOC means every file gets the same private table (`pkg`).
- Umbrella code lives on `pkg` (global `MightiePack`).
- NodeTrail lives on the sub-table `pkg.NodeTrail` (global `NodeTrail`).
- Each NodeTrail file starts with `local addonName, pkg = ...` / `pkg.NodeTrail = pkg.NodeTrail or {}` / `local ns = pkg.NodeTrail`.
- Load order (MightiePack.toc): Core.lua, Modules.lua, the 15 NodeTrail files (locale, Config, Data/GM2, Data/Recorder, Data/Density, Data/HerbData, Data/Recipes, Route/Cluster, Route/Build, UI/PathGeom, UI/LineDraw, UI/MapOverlay, UI/MinimapPath, UI/Tooltip, Core), Options.lua.
- Module registry (Modules.lua): `pkg.RegisterModule(name, {title, notes, stub, Enable})`, `pkg.IsModuleEnabled`, `pkg.SetModuleEnabled`, `pkg.EnableModules` (runs each enabled module's Enable once, pcall-wrapped, on ADDON_LOADED of MightiePack).
- Touchstone is registered as a stub (always off, checkbox greyed out, label "Touchstone (coming soon)").
- Adding a module: create `Modules/<Name>/` files, add them to the TOC before Options.lua, call `pkg.RegisterModule` with an Enable function, add a default to `pkg.moduleDefaults` in Core.lua.
- NodeTrail as a module: its slash commands (`/nt`, `/nodetrail`: start | stop | reload | help) are registered inside `ns.Enable()`, so a disabled module registers no slash command and does not touch NodeTrailDB.
- MapOverlay/MinimapPath still create their idle event frames at file load (they do nothing without a route).

## Options and reload confirm
- Interface Options / Settings panel "MightiePack" (uses Settings.RegisterCanvasLayoutCategory when present, else InterfaceOptions_AddCategory).
- Open with `/mpack` or `/mightiepack` (also `/mpack options`).
- `/mpack status` prints each module on/off.
- Tick a module: turns on immediately, no reload.
- Untick: confirm popup "Turn off <module>? This needs a UI reload." OK saves it off and runs ReloadUI(); Cancel (or Escape) keeps it on and re-ticks the box. The setting is not changed until OK.

## SavedVariables
- `MightiePackDB` (umbrella: `MightiePackDB.modules[name] = true/false`, defaults NodeTrail on, Touchstone off).
- `NodeTrailDB` (unchanged NodeTrail profile).
- Chosen approach: separate SVs, not nested, so NodeTrail's DB code did not change.
- Note: SavedVariables files are per addon folder, so settings saved under the old standalone NodeTrail addon do not carry over; NodeTrail starts from defaults.
- `NodeTrailDB` now also has `herbs` (Base A/Config `profile` keys are never touched; GetHerbDB only creates missing keys):
  ```lua
  NodeTrailDB.herbs = {
    schema = 1,
    total = <number of recorded gathers>,
    maps = {
      [uiMapID] = {
        { x = 0.1235, y = 0.6543,   -- map fractions rounded to 4 decimals
          t = 1700000000,           -- time() unix seconds
          node = 1617,              -- game object id, optional
          items = { { id = 2447, name = "Peacebloom", count = 2 }, ... } },
        ...
      },
    },
  }
  ```
  API: `ns.GetHerbDB()` returns `NodeTrailDB.herbs`; `ns.RecordHerb(mapID, x, y, items, nodeID)` appends one entry.
- `NodeTrailDB` now also has `recipes` (Base D; other keys untouched):
  ```lua
  NodeTrailDB.recipes = {
    alchemy = {
      [reagentItemID] = { "Recipe A", "Recipe B" },
      ...
    },
    alchemyScanned = <time() of last scan>,
  }
  ```
  API: `ns.GetRecipeDB()`, `ns.Recipes:GetUses(itemID)`, `ns.Recipes:Scan()`, `ns.HerbData.GetDropLines(name)`, `ns.Tooltip.BuildLines(name)`.

## Tests
Run from repo root with lua5.1:
- `tests/pathgeom_spec.lua`
- `tests/draw_smoke.lua` (NodeTrail drawing, now loads from MightiePack/Modules/NodeTrail and calls ns.Enable())
- `tests/umbrella_spec.lua` (TOC order and files, defaults, slash registration, options checkboxes, untick/cancel/escape/OK reload, disabled-after-reload state, live re-enable, stub never enabled)
- `tests/recorder_spec.lua` (SV preserved, record shape, rounding, node id, LOOT_READY+LOOT_OPENED dedupe, custom spell id by name, non-herb/other unit/too late/fishing/no position/no cast ignored, empty loot still recorded, fresh DB)
- `tests/density_spec.lua` (empty/one-spot/two-spot/three-spot data, dense ring with cold outliers, no self-crossing, 2-opt crossing removal, anchor count scaling, maxStops cap, determinism, map wiring and errors, routeSource switch, old profile without new keys)
- `tests/tooltip_spec.lua` (nothing hooked at load, idempotent Enable, non-herb and unit tooltips ignored, baseline lines, header once per tooltip, secondary order, personal below/at the 10-gather threshold, non-Alchemy scan ignored, Alchemy scan + uses lines, rescan replaces, other SV keys untouched)
- `tests/slash_spec.lua` (module gating (no /nt before Enable), slash names, help content, empty/unknown = help, reload without route, status lines (source density/gm2, counts per map and total, unknown map, route none/active, tooltip on, Alchemy scanned/not, module on/off), start/reload/stop round trip from recorded herbs, case and whitespace)
All seven specs pass with lua5.1.

## Herb recorder (Base B)
- No GatherMate2 needed. GM2 stays an optional soft-dep only for the current route builder (Route/Build.lua still reads GM2 until Base C).
- Only runs when the NodeTrail module is enabled: `ns.Enable()` calls `ns.Recorder:Enable()`, which creates the event frame. Loading the file registers nothing.
- Detection: UNIT_SPELLCAST_SUCCEEDED for unit "player" with a Herb Gathering spell (IDs 2366, 2368, 3570, 11993, or any spell whose localized name equals GetSpellInfo(2366), for custom server IDs) stores a pending gather with the player position at that moment (C_Map.GetBestMapForUnit("player") + C_Map.GetPlayerMapPosition(mapID, "player"):GetXY(), same 0..1 map fractions as the route code). The next LOOT_READY or LOOT_OPENED within 5 seconds records it once (pending is cleared on the first loot event). Items come from GetNumLootItems / GetLootSlotLink (item id) / GetLootSlotInfo (name, quantity). Node object id comes from GetLootSourceInfo GUID ("GameObject-...-<objectID>-...") when available.
- Skipped: casts by other units, non-herb spells, loot more than 5 s after the cast, fishing loot (IsFishingLoot), unknown position (nil or 0,0, e.g. instances). A gather whose loot list is empty still records the position.
- Limitations (best-effort): relies on the client firing UNIT_SPELLCAST_SUCCEEDED for Herb Gathering and on the spell name if Forever uses custom IDs; the position is the player's, not the node's (the player stands next to the node, within a few yards); a loot window opened from another source within 5 s of an interrupted-then-succeeded herb cast could be attributed to the herb; not yet verified in-game on Forever.

## Density path (Base C)
- `/nt start` and `/nt reload` now build from OUR recorded herbs by default (`ns.BuildRouteForMap` -> `ns.BuildDensityRouteForMap(mapID)` reading `NodeTrailDB.herbs.maps[mapID]`).
- GatherMate2 is no longer needed for routes. The old GM2 builder (Route/Build.lua, Route/Cluster.lua, Data/GM2.lua) is kept as an optional fallback: set `NodeTrailDB.profile.routeSource = "gm2"` (default "density"; a missing key also means density).
- GM2 is still an OptionalDeps soft-dep and is used, if loaded, only for HereBeDragons yard positions on the minimap and for the player zone id.
- Algorithm (`ns.Density.Build(points, opts)`):
  1. Heat grid with cells of 0.02 map width (`densityCell`). Each pick adds a 3x3 kernel: 1.0 own cell, 0.5 edge neighbours, 0.25 diagonals, so nearby picks stack into heat belts.
  2. Warm threshold = 0.4 (`densityWarm`) x the hottest cell. A pick counts only if its own cell is at least that warm, so isolated cold picks drop out once belts exist.
  3. Warm picks are grouped on a coarser 0.06 grid (`densityAnchorCell`); each group becomes one anchor at the heat-weighted centroid. The heaviest `maxStops` (default 40) anchors are kept. This is why the path does not connect every pick.
  4. Anchors are ordered into a loop: nearest-neighbour from the heaviest, then 2-opt until no improvement (removes crossings so the loop follows belts instead of zigzagging).
  5. Two passes of Chaikin corner cutting (`densitySmooth`) on the closed loop give the smooth corridor; the last point repeats the first (close = true), the same shape the drawing code already used.
- The route (`{ mapID, path, anchors, stops = #anchors, picks, source = "density" }`) is drawn by the unchanged MapOverlay/MinimapPath/LineDraw/PathGeom.
- Sparse data behaviour: 0 picks in the zone -> chat "NodeTrail: no herbs recorded in this zone yet. Gather a few herbs here, then /nt start." (no error). Picks that all fall in one 0.06 spot -> one anchor -> "not enough herb nodes to build a loop" (gather somewhere else in the zone). 2 spots -> a thin out-and-back line. 3+ spots -> a smoothed loop through all of them (with little data every pick has the same heat, so nothing is dropped). As data grows, belts get hotter and lone picks stop pulling the path.
- Tunables in `NodeTrailDB.profile` (new defaults; existing profiles without them fall back to the same defaults): `routeSource`, `densityCell`, `densityWarm`, `densityAnchorCell`, `densitySmooth`; `maxStops` (existing) caps anchors.
- Chat on start: "NodeTrail: route started (<belt points> belt points from <picks> herb picks)."

## Herb tooltip (Base D)
- New files: `MightiePack/Modules/NodeTrail/Data/HerbData.lua`, `Data/Recipes.lua`, `UI/Tooltip.lua`.
- `ns.Enable()` now also calls `ns.Recipes:Enable()` and `ns.Tooltip:Enable()`. Loading the files hooks nothing and registers no events; a disabled module adds no tooltip lines.
- Hover detection: hooks GameTooltip OnShow. Only when no unit is moused over, the tooltip owner is UIParent/WorldFrame (world object), and tooltip line 1 is a known herb node name from the HerbData table (English names). OnTooltipCleared resets a flag so lines are added once per tooltip.
- Lines added (light blue): header "NodeTrail"; one row per drop "<item> <pct>%" (suffix "(base)" when from the baseline stub); "Your picks: N" or "Your picks: none yet"; "Alchemy: <recipe>, <recipe>, ..." (first 4, then "+N more"), or "Open Alchemy once to list recipe uses" if Alchemy was never scanned.
- Drop % source: baseline stub table in HerbData.lua (primary herb 100% for the 28 Classic herb nodes Peacebloom..Black Lotus; rough placeholder secondaries: Swiftthistle 10% from Mageroyal and Briarthorn, Wildvine 5% from Purple Lotus; NOT researched Forever data). Personal data from NodeTrailDB.herbs: a gather of a herb = any recorded gather whose items include that herb's item id. Once there are 10 or more gathers (H.PERSONAL_MIN) the personal % replaces the baseline (each item counted once per gather). Items you looted that are not in the stub are shown from personal data.
- Alchemy recipe uses: best-effort Classic API. When the Alchemy trade skill window is open (TRADE_SKILL_SHOW / TRADE_SKILL_UPDATE and GetTradeSkillLine() equals the localized Alchemy name), it scans learned recipes (GetNumTradeSkills, GetTradeSkillInfo, skipping headers, GetTradeSkillReagentItemLink) and stores itemID -> sorted recipe names. Each scan replaces the old map. The player has to open the Alchemy window once (per character) before uses show.
- Limitations: herb node names are matched in English only (non-English clients show no lines until localized names are added); Forever custom herbs/rare mats are not in the stub; recipe list is per character and only after opening Alchemy; tooltip not yet seen in-game on Forever (assumes the client puts the node name on line 1 of GameTooltip).

## Slash commands (Base E)
- `/nt` or `/nt help` prints a multi-line help (start, stop, reload, status, plus a note that herbs are recorded automatically, hovering a herb shows drop % and Alchemy uses, module on/off is in /mpack).
- `/nt status` prints: route source (density = your recorded herbs, or gm2), herbs recorded on the current map and on all maps, active route (points + source, or none), herb tooltip on/off, Alchemy recipes scanned or "open your Alchemy window once", module on/off.
- `/nt reload` with no active route now says "no active route. Use /nt start first." instead of the help.
- Unknown words print the help.
- `/mpack` with an unknown word prints "/mpack [options|status]" and, when NodeTrail is on, "NodeTrail: /nt help".
- The /nt slash commands are still registered only inside ns.Enable(), so they do not exist while the module is off.
- Module notes text updated.

## Install (when Mightie says so)
- Install only the `MightiePack/` folder into the client's AddOns folder.
- Remove (or disable) the old standalone `NodeTrail` addon folder first so the two do not both load.
- GatherMate2 is optional.
- Old NodeTrailDB settings do not carry over (SavedVariables are per addon folder).
- Do not do this without Mightie's say-so.

## In-game smoke test (from the vault test script)
1. Install (only after say-so; see Install).
2. `/reload`, `/mpack` opens options; confirm both checkboxes (NodeTrail on, Touchstone greyed "coming soon"); untick NodeTrail -> OK reloads -> `/nt` does nothing -> tick it back on.
3. `/mpack status` shows NodeTrail on.
4. Gather 5-10 herbs in one starter zone; `/nt status` count goes up (after logout/`/reload`, SavedVariables NodeTrailDB.herbs grew).
5. `/nt start` -> white density corridor on world map and minimap (rough OK); `/nt reload` after more picks; `/nt stop` clears.
6. Hover a herb node -> NodeTrail block with drop % (base), Your picks, and Alchemy uses after opening the Alchemy window once (`/nt status` then shows "scanned").
7. Note bugs (with `/nt status` output) for the morning pass.

## Next
Morning pass: fix bugs from Mightie's in-game test.
Out for tonight: mining/fishing/skinning, full rare-mat research, arrow/TomTom, folding in the real Touchstone repo, sharing/import.

## Known gaps
- MapOverlay/MinimapPath frames load even when NodeTrail is off.
- Old NodeTrailDB does not migrate.
- In-game test not yet run, nothing deployed.
- Recorder not yet verified in-game on Forever (spell IDs/names, loot events).
- Without GatherMate2 loaded the minimap path has no HereBeDragons yard data, so it falls back to C_Map player position with an approximate fixed view radius (fraction of the map); scale on the minimap may be off until a yard source is added. The world map path is unaffected.
- Density path not yet seen in-game; tunables may need adjusting after the first real run.
- Herb tooltip node names are matched in English only; non-English clients show no lines until localized names are added.
- Herb tooltip recipe uses require the Alchemy window to be opened once per character.
- Herb tooltip not yet seen in-game on Forever.
