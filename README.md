# NodeTrail

WoW: Forever Classic **herb** gathering routes driven by your [GatherMate2](https://www.curseforge.com/wow/addons/gathermate2) nodes. Zygor-style **white path** on the world map and minimap. Separate from Touchstone.

## MVP scope

- Soft-dep GatherMate2 (`OptionalDeps`)
- Herbalism only (`"Herb Gathering"`)
- One zone at a time: cluster nodes → greedy short loop
- World map + minimap white path overlay
- Arrow / TomTom: **later**
- `## Interface: 16001` (Forever)

## Requirements

1. GatherMate2 loaded (Forever flavor preferred; Classic works if APIs match)
2. Herb nodes in `GatherMate2HerbDB` — gather in-world or import Wowhead Classic data via `/gathermate`

If GM2 is missing or the zone has no herbs, NodeTrail stays quiet / tells you why. No bundled node DB.

## Slash

| Command | Action |
|---------|--------|
| `/nodetrail` or `/nt` | Status / help |
| `/nt start` | Build + show route for current zone (all herbs) |
| `/nt stop` | Clear route overlays |
| `/nt reload` | Rebuild from current GM2 snapshot |

## Layout

```
NodeTrail.toc
Core.lua              # load, slash, route session
Config.lua            # defaults / SavedVariables
Data/GM2.lua          # soft-dep adapter
Route/Cluster.lua     # grid bucketing
Route/Build.lua       # greedy nearest-neighbor loop
UI/PathGeom.lua       # segment clipping (no WoW calls)
UI/LineDraw.lua       # white line segments (CreateLine, else rotated texture)
UI/MapOverlay.lua     # world map white path
UI/MinimapPath.lua    # minimap white path
locale/enUS.lua
```

## GM2 adapter (canonical)

```lua
local mapID = GatherMate2.HBD:GetPlayerZone()
for coord, nodeID in GatherMate2:GetNodesForZone(mapID, "Herb Gathering", true) do
  local x, y = GatherMate2:DecodeLoc(coord)  -- 0..1
end
```

Do **not** scrape `GatherMateData2HerbDB` or hardcode English zone names.

## Path drawing

`/nt start` draws the herb loop as a white polyline (`pathColor` defaults to `{1, 1, 1, 0.9}`, `pathWidth` defaults to `2`).

- **World map:** segments join `route.path` points (map fractions) on that zone's map canvas. The line is hidden when the map is showing a different map, and when the route is cleared.
- **Minimap:** segments that pass near the player are drawn in white. Yard positions use GatherMate2's embedded HereBeDragons when it is loaded. The minimap updates on a short timer, and immediately on movement, zoom, and zone changes.

`/nt stop` releases both overlays.

## Status

Path drawing is implemented. Gather in-game or import herb nodes through GatherMate2, then `/nt start`.
