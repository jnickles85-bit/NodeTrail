# MightiePack (working name) — NodeTrail and friends

MightiePack is an umbrella addon for WoW Forever Classic (Interface 16001). It currently ships NodeTrail for herb route drawing.

## Install
1. Remove any old standalone `NodeTrail` AddOns folder first, because both define the NodeTrail global and /nt.
2. Copy the `MightiePack` folder into the client's AddOns folder.

## Modules
| Module | Description | Default |
|--------|-------------|---------|
| NodeTrail | Herb routes | On |
| Touchstone | Coming soon | Off (stub) |

## Slash Commands
| Command | Description |
|---------|-------------|
| `/mpack` | Open options panel |
| `/mpack status` | Print module on/off status |
| `/nt start` | Start NodeTrail route |
| `/nt stop` | Stop NodeTrail route |
| `/nt reload` | Rebuild the active route from current data |

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
```

## NodeTrail details
- Herb-only.
- GatherMate2 soft-dep for now — needs herb nodes in GatherMate2.
- GM2 adapter uses `GatherMate2:GetNodesForZone(mapID, "Herb Gathering", true)` and `DecodeLoc`, never scrape GatherMateData2HerbDB or hardcode zone names.
- White polyline pathColor `{1,1,1,0.9}`, pathWidth 2 on world map and minimap.
- `/nt stop` releases both overlays.

## Tests
Run from repo root with lua5.1:
- `tests/pathgeom_spec.lua`
- `tests/draw_smoke.lua`
- `tests/umbrella_spec.lua`

## Handoff
See `HANDOFF.md` for agent handoff details.
