# MightiePack (working name) — NodeTrail and friends

MightiePack is an umbrella addon for WoW Forever Classic (Interface 16001). It currently ships NodeTrail for herb route drawing.

## Install
1. Remove any old standalone `NodeTrail` AddOns folder first, because both define the NodeTrail global and /nt.
2. Copy the `MightiePack` folder into the client's AddOns folder.
3. GatherMate2 is optional.

## Modules
| Module | Description | Default |
|--------|-------------|---------|
| NodeTrail | Herb routes | On |
| Touchstone | Gear upgrade advice (vendored Touchstone 0.8.3) | Off |

Touchstone's files are generated into `MightiePack/Modules/Touchstone/` by
`tools/sync_touchstone.py`; do not hand-edit them. The module refuses to run
while the standalone `Touchstone` addon folder is installed — two copies must
never write `StatForgeDB`. Remove that folder and reload to use the vendored
copy.

## Slash Commands
| Command | Description |
|---------|-------------|
| `/mpack` | Open options panel |
| `/mpack options` | Open options panel |
| `/mpack status` | Print module on/off status |
| `/nt help` | Print NodeTrail help (only while NodeTrail is enabled) |
| `/nt start` | Build the density path for the current zone from your recorded herbs (only while NodeTrail is enabled) |
| `/nt stop` | Stop NodeTrail route (only while NodeTrail is enabled) |
| `/nt reload` | Rebuild the active route from current data (only while NodeTrail is enabled) |
| `/nt status` | Print route source, herb counts, active route, tooltip state, Alchemy state, module state (only while NodeTrail is enabled) |

## Options
- Open with `/mpack` or `/mightiepack`.
- Tick a module: turns on immediately, no reload.
- Untick: confirm popup "Turn off <module>? This needs a UI reload." OK saves it off and runs ReloadUI(); Cancel (or Escape) keeps it on and re-ticks the box.

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

## NodeTrail details
- Herb-only.
- Routes come from your own recorded herb gathers (Base B recorder) drawn as a density corridor.
- GatherMate2 optional (routeSource = "gm2" fallback).
- White polyline pathColor `{1,1,1,0.9}`, pathWidth 2 on world map and minimap.
- `/nt stop` releases both overlays.

### Optional GatherMate2 fallback
- GM2 adapter uses `GatherMate2:GetNodesForZone(mapID, "Herb Gathering", true)` and `DecodeLoc`, never scrape GatherMateData2HerbDB or hardcode zone names.

### Herb tooltip
- Hover an in-world herb node to see drop percentages and your personal pick counts.
- Baseline drop rates are shown for the 28 Classic herb nodes.
- After 10 or more recorded gathers of a herb, your personal drop rates replace the baseline.
- Open the Alchemy trade skill window once to see which learned recipes use the herb.

## Tests
Run from repo root with lua5.1:
- `tests/pathgeom_spec.lua`
- `tests/draw_smoke.lua`
- `tests/umbrella_spec.lua`
- `tests/recorder_spec.lua`
- `tests/density_spec.lua`
- `tests/tooltip_spec.lua`
- `tests/slash_spec.lua`

## Handoff
See `HANDOFF.md` for agent handoff details.
