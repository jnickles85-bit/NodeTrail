# NodeTrail Handoff

## Status
Base A (umbrella shell) is complete on branch `mp/base-a-umbrella` (cut from main `3b904cc`). Date: 2026-11-06.
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
tests/umbrella_spec.lua
```

## How modules load
- One TOC means every file gets the same private table (`pkg`).
- Umbrella code lives on `pkg` (global `MightiePack`).
- NodeTrail lives on the sub-table `pkg.NodeTrail` (global `NodeTrail`).
- Each NodeTrail file starts with `local addonName, pkg = ...` / `pkg.NodeTrail = pkg.NodeTrail or {}` / `local ns = pkg.NodeTrail`.
- Load order (MightiePack.toc): Core.lua, Modules.lua, the 10 NodeTrail files (locale, Config, Data/GM2, Route/Cluster, Route/Build, UI/PathGeom, UI/LineDraw, UI/MapOverlay, UI/MinimapPath, Core), Options.lua.
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

## Tests
Run from repo root with lua5.1:
- `tests/pathgeom_spec.lua`
- `tests/draw_smoke.lua` (NodeTrail drawing, now loads from MightiePack/Modules/NodeTrail and calls ns.Enable())
- `tests/umbrella_spec.lua` (TOC order and files, defaults, slash registration, options checkboxes, untick/cancel/escape/OK reload, disabled-after-reload state, live re-enable, stub never enabled)

## Next: Base B
Base B herb recorder: on herb loot save mapID + x/y + items into SavedVariables, no GM2 needed.

After B: Base C density builder (heat from recorded picks -> smooth white corridor; reuse LineDraw/MapOverlay/MinimapPath; pivot Data/GM2.lua off the default path), Base D live herb tooltip (stub drop % table + personal counts + learned Alchemy uses), Base E slash wiring under the module + smoke notes.
Out for tonight: mining/fishing/skinning, full rare-mat research, arrow/TomTom, folding in the real Touchstone repo, sharing/import.

## Known gaps
- MapOverlay/MinimapPath frames load even when NodeTrail is off.
- Old NodeTrailDB does not migrate.
- In-game test not yet run, nothing deployed.
