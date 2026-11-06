# NodeTrail Handoff

## Status
Base A (umbrella shell) is on branch `mp/base-a-umbrella` (PR #2).
Base B (own herb recorder) is on branch `mp/base-b-recorder`, stacked on `mp/base-a-umbrella` (its PR targets `mp/base-a-umbrella`; merge #2 first).
Date: 2026-11-06.
The repo now ships one installable addon folder: `MightiePack/`.

## Rules
- Locally (orchestrator) + local Qwen write code.
- Tinker leads the addon.
- Ask Mightie via Finkle before deploys, merge freezes, or renaming the umbrella.
- NO deploy to the Forever client until Mightie says so.
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
MightiePack/Modules/NodeTrail/Route
MightiePack/Modules/NodeTrail/Route/Build.lua
MightiePack/Modules/NodeTrail/Route/Cluster.lua
MightiePack/Modules/NodeTrail/UI
MightiePack/Modules/NodeTrail/UI/LineDraw.lua
MightiePack/Modules/NodeTrail/UI/MapOverlay.lua
MightiePack/Modules/NodeTrail/UI/MinimapPath.lua
MightiePack/Modules/NodeTrail/UI/PathGeom.lua
MightiePack/Modules/NodeTrail/locale
MightiePack/Modules/NodeTrail/locale/enUS.lua
MightiePack/Options.lua
README.md
tests
tests/draw_smoke.lua
tests/pathgeom_spec.lua
tests/recorder_spec.lua
tests/umbrella_spec.lua
```

## How modules load
- One TOC means every file gets the same private table (`pkg`).
- Umbrella code lives on `pkg` (global `MightiePack`).
- NodeTrail lives on the sub-table `pkg.NodeTrail` (global `NodeTrail`).
- Each NodeTrail file starts with `local addonName, pkg = ...` / `pkg.NodeTrail = pkg.NodeTrail or {}` / `local ns = pkg.NodeTrail`.
- Load order (MightiePack.toc): Core.lua, Modules.lua, the 11 NodeTrail files (locale, Config, Data/GM2, Data/Recorder, Route/Cluster, Route/Build, UI/PathGeom, UI/LineDraw, UI/MapOverlay, UI/MinimapPath, Core), Options.lua.
- Module registry (Modules.lua): `pkg.RegisterModule(name, {title, notes, stub, Enable})`, `pkg.IsModuleEnabled`, `pkg.SetModuleEnabled`, `pkg.EnableModules` (runs each enabled module's Enable once, pcall-wrapped, on ADDON_LOADED of MightiePack).
- Touchstone is registered as a stub (always off, checkbox greyed out, label "Touchstone (coming soon)").
- Adding a module: create `Modules/<Name>/` files, add them to the TOC before Options.lua, call `pkg.RegisterModule` with an Enable function, add a default to `pkg.moduleDefaults` in Core.lua.
- NodeTrail as a module: its slash commands (`/nt`, `/nodetrail`: start | stop | reload | help) are registered inside `ns.Enable()`, so a disabled module registers no slash command and does not touch NodeTrailDB.
- MapOverlay/MinimapPath still create their idle event frames at file load (they do nothing without a route).
- Route data is still GatherMate2-backed in Base A.

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

## Tests
Run from repo root with lua5.1:
- `tests/pathgeom_spec.lua`
- `tests/draw_smoke.lua` (NodeTrail drawing, now loads from MightiePack/Modules/NodeTrail and calls ns.Enable())
- `tests/umbrella_spec.lua` (TOC order and files, defaults, slash registration, options checkboxes, untick/cancel/escape/OK reload, disabled-after-reload state, live re-enable, stub never enabled)
- `tests/recorder_spec.lua` (SV preserved, record shape, rounding, node id, LOOT_READY+LOOT_OPENED dedupe, custom spell id by name, non-herb/other unit/too late/fishing/no position/no cast ignored, empty loot still recorded, fresh DB)
All four specs pass with lua5.1.

## Herb recorder (Base B)
- No GatherMate2 needed. GM2 stays an optional soft-dep only for the current route builder (Route/Build.lua still reads GM2 until Base C).
- Only runs when the NodeTrail module is enabled: `ns.Enable()` calls `ns.Recorder:Enable()`, which creates the event frame. Loading the file registers nothing.
- Detection: UNIT_SPELLCAST_SUCCEEDED for unit "player" with a Herb Gathering spell (IDs 2366, 2368, 3570, 11993, or any spell whose localized name equals GetSpellInfo(2366), for custom server IDs) stores a pending gather with the player position at that moment (C_Map.GetBestMapForUnit("player") + C_Map.GetPlayerMapPosition(mapID, "player"):GetXY(), same 0..1 map fractions as the route code). The next LOOT_READY or LOOT_OPENED within 5 seconds records it once (pending is cleared on the first loot event). Items come from GetNumLootItems / GetLootSlotLink (item id) / GetLootSlotInfo (name, quantity). Node object id comes from GetLootSourceInfo GUID ("GameObject-...-<objectID>-...") when available.
- Skipped: casts by other units, non-herb spells, loot more than 5 s after the cast, fishing loot (IsFishingLoot), unknown position (nil or 0,0, e.g. instances). A gather whose loot list is empty still records the position.
- Limitations (best-effort): relies on the client firing UNIT_SPELLCAST_SUCCEEDED for Herb Gathering and on the spell name if Forever uses custom IDs; the position is the player's, not the node's (the player stands next to the node, within a few yards); a loot window opened from another source within 5 s of an interrupted-then-succeeded herb cast could be attributed to the herb; not yet verified in-game on Forever.

## Next
Base C density builder is next: read NodeTrailDB.herbs.maps[mapID], weight map cells, trace a smooth white corridor through warm belts (not connect-every-dot), feed it to MapOverlay/MinimapPath, and switch /nt start to our DB by default (GM2 path off the default). Then Base D tooltip and Base E slash/smoke notes.
Out for tonight: mining/fishing/skinning, full rare-mat research, arrow/TomTom, folding in the real Touchstone repo, sharing/import.

## Known gaps
- MapOverlay/MinimapPath frames load even when NodeTrail is off.
- Old NodeTrailDB does not migrate.
- In-game test not yet run, nothing deployed.
- Recorder not yet verified in-game on Forever (spell IDs/names, loot events).
