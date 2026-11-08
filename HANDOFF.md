# NodeTrail Handoff

## Status
Bases A–E are on `main` (`c96bf91`, PR #2–#7).

**2026-11-08 — branch `fix/tooltip-refresh`, unmerged, unpushed, undeployed.**

- **The skinning dump no longer dies on a SECRET string** (t_1ed3b421). Live on build `c220ec7`
  the whole dump was lost at the end of a run — `Probe.lua:908: attempt to get length of local
  'line' (a secret string value, while execution tainted by 'MightiePack')` — because the client
  hands back SECRET strings for creature names and the dump measured (`#`), sliced (`:sub`) and
  formatted them. Rule now enforced in `Modules/Skinning/Probe.lua` and `Record.lua`: only text the
  addon built itself is measured and capped; a client value travels in its own slot (a step's
  `name`/`nameLabel`, or `{ pre, name, post }` from `R.Describe`) and is appended at the print site,
  where the finished line goes straight to `AddMessage`. `issecretvalue` is checked before any read,
  every remaining read is `pcall`'d, and one unprintable step line can no longer take the dump down.
  `?x0` is gone too: the coin slot (no itemID) is never an item — it is shown as `money`.
- **The dump's first line states the truth**: `capture on; sub-option off (NodeTrail); records:
  session buffer only, nothing saved; steps=120/120` (or `sub-option ON ... NodeTrailDB.skinning,
  saved`). The old `/mp skindiag` line "skinning is off ... nothing recorded" is gone: the
  sub-option governs persistence, not capture, and a live run recorded 9 kills behind it.
- **Audited the rest of the tree for the same read**: `Modules/NodeTrail/Data/Recorder.lua`
  (loot links + loot-source GUID, and a secret item name is never written into the herb DB) and
  `BugReport.lua` (unit name/zone/GUID chain). Touchstone already had the guard.
- New spec `tests/skindiag_secret_spec.lua` models a secret faithfully (every read raises the
  client's message) and pushes one through every dump path: kill step, record header, loot-source
  name, cast name, item name, a secret GUID, a secret zone, a secret error object, and a 100+ step
  run. Green at HEAD; **23 FAILs** on `c220ec7`.

- **A GUID-less loot window no longer breaks the chain** (t_4b4e9f8d). Live at Razor Hill the client
  opened the corpse window with **no loot-source GUID and no items** (`k=unattributed i=-`), which
  left the 8613 cast with nothing to pin to and the real skin window classified `k=unclassified`.
  Three rules now: (1) a GUID-less window is attributed to the most recent `UNIT_DIED` inside
  `P.DEATH_FALLBACK_WINDOW` (10s) and the line says which rule fired —
  `g=..EF7D0D (from UNIT_DIED)`; (2) the open window is re-read on `LOOT_SLOT_CLEARED` and once more
  just before `LOOT_CLOSED`, so a late-filled window is recorded instead of `none seen` (the record
  shows `(late read)`); (3) skin attribution comes from the cast, never from the corpse window having
  been attributed. Items are kept per window open and merged, so a re-read replaces that window's
  list and never doubles a quantity. The cast's pin is bounded by `SKIN_WINDOW` too — it used to
  re-pin to any old corpse and file the next player's skin window as corpse loot.
- **Names and counts** (t_4b4e9f8d): `record unknown` / `last kill: unknown` replace the `record ?`
  fallback, and a GUID is never printed in a name field — this client can answer `UnitName` with the
  GUID, which is where `last kill: <guid> g=..EF7D0D` came from. The dump now prints an **accounting**
  line under the counts: `accounting: kills=15 corpse-windows=4 skin-windows=5 casts=11 | lost
  kills=11 windows=0 casts=6`, so 15 kills with 4 windows is stated instead of 11 corpses silently
  vanishing. New spec `tests/skinning_guardless_spec.lua` replays this exact sequence — green at
  HEAD, **42 FAILs** on `dc94343`. `skinning_recorder_spec`'s section G changed with it: a window
  after a successful cast on a known GUID is now skin loot on its own record (`killObserved=false`,
  no kill counted) where it used to be `unclassified` — that is the card's rule 3. **Not yet re-run
  in game.**

- **The route comes back by itself, and follows the picks** (t_2bc15917). Mightie: "yes it needs to be
  automated for sure, at least on /reloads". `ns.StartRoute()` used to run only from `/nt start` and
  `/nt reload`, so a started route was gone after any reload and never reflected the herbs gathered
  since. Now `NodeTrailDB.route = { active, mapID, startedAt, autoRefresh }` holds the **intent only**
  — no path, no anchors, no points (the spec asserts all three stay nil) — and `Modules/NodeTrail/
  Route/Auto.lua` (new, `ns.RouteAuto`, loaded right after `Route/Build.lua`) owns every automatic
  path:
  1. `Enable()` (a login and a `/reload` both run it) rebuilds and draws the saved route for its map
     — no command — and says `route restored (13 points from 12 herb picks on map 1429)`
     (trigger `login`). Off-map, the intent is kept and nothing is drawn until the player is back
     there; a `PLAYER_ENTERING_WORLD` handler rebuilds on arrival (and only redraws when the route is
     already in memory). A nil/unknown map at `ADDON_LOADED` is not "another map" and is not logged —
     the world event right after login is the answer.
  2. `ns.RecordHerb` now only **moves a due time** (`SchedulePick`: `GetTime() + 5`, pushed out by
     each pick). The frame's `OnUpdate` calls `Pump`, which rebuilds once, a few seconds after the
     last pick (trigger `pick`). Nothing is ever rebuilt inside the loot/gather event.
  3. `/nt stop` clears the live route **and** the intent; `/nt start` and `/nt reload` record it
     (trigger `manual`). A start that builds nothing leaves no false intent behind.
  - **Never regress a drawn route**: a rebuild whose result has fewer than two path points, or fewer
    than two anchors when the builder reports anchors, is refused — `ns.activeRoute`, the overlay and
    the minimap keep what they have, and the reason is printed. The generation code (heat cells,
    threshold, anchors, greedy NN, 2-opt, `maxStops`) is untouched.
  - **No silent resurrection**: a `startedAt` older than `profile.routeMaxAgeHours` (default 24) is not
    rebuilt — `route not rebuilt — it was started 25h ago, older than the 24h limit. Use /nt start.`
  - `/nt status` gains `Route state: active yes, map 1429, auto-refresh on` and
    `Last rebuild: 12:34:56, trigger login, 13 points`. The options panel gains an indented
    **"Auto-refresh route"** checkbox under the skinning one (persisted at
    `NodeTrailDB.route.autoRefresh`, **on by default**, greyed out while NodeTrail is off).
  - New spec `tests/route_auto_spec.lua` (9 sections) drives the real files: restore-without-a-command,
    stop-then-reload stays quiet, five picks → exactly **one** debounced rebuild with trigger `pick`,
    a zero-anchor/one-anchor rebuild keeps the good route, another mapID draws nothing until the map
    changes, stale intent refuses + a raised ceiling restores it, `/nt status` lines, auto-refresh off,
    and `/nt start` → intent → reload. **Green at HEAD, 41 FAILs on `6254920`.** All 32 `tests/*.lua`
    pass under lua5.1. **Not yet run in game.**

**2026-11-07 — branch `fix/tooltip-refresh`, unmerged, unpushed, undeployed.**
The herb smoke-test bugs are fixed and confirmed in game by Mightie: tooltip persistence, backdrop
sizing, on-screen clamping, and Alchemy recipe uses (196 recipes read through `C_TradeSkillUI`).
On top of that branch:

- **Touchstone is folded in** as a module (`Modules/Touchstone/`, vendored 0.8.3, generated by
  `tools/sync_touchstone.py`). Off by default; stays inert while a standalone `Touchstone` folder
  exists; keeps `StatForgeDB` / `ChestAdvisorDB` names so settings carry over. **Not yet tested in
  game.**
- **Skinning probe** (`Modules/Skinning/`) — **nested under NodeTrail** (t_5507a0ba): there is no
  `Skinning` module row. The options panel shows an indented "Skinning (experimental)" sub-option
  under the NodeTrail checkbox, greyed out while NodeTrail is off, persisted at
  `NodeTrailDB.skinning.enabled` (default false; the old `MightiePackDB.modules.Skinning` key is
  inert, never read). Turning it off is immediate — no UI reload, no popup. `/mp skindiag` /
  `/mp skindiag dump` capture the kill → loot → skin → skin-loot chain and still run while the
  sub-option is off (the line says so; nothing is recorded then).
- **Skinning recorder** (`Modules/Skinning/Record.lua`, t_80ffe952) — the model the probe feeds,
  built on the **live dump from build `5455eea`** (49 steps, character Bowdecia Arrowroot, map
  1411). One record per corpse keyed by the corpse GUID, written to
  `NodeTrailDB.skinning.chars["Name-Realm"].records` and ONLY while
  `NodeTrailDB.skinning.enabled` is on (with it off the recorder still builds the same record in a
  session buffer, which is what the dump prints — "diagnostics run, nothing recorded" stays true).
  Each record keeps the mob GUID/name/npc entry, zone/subzone/map + position at death, the ordinary
  corpse loot, whether an 8613 cast succeeded, the skinning loot in a **separate** list, and the gap
  between the corpse loot closing and the skin window opening. Personal counts only — no rate.
  Recording starts with the sub-option (not with `/mp skindiag`).
- **Skinning event surface, now measured** (t_80ffe952), from that same dump:
  `UNIT_DIED` fires for ordinary mobs and its **argument is the creature GUID**; Skinning is spell
  **8613** and on this client the 4th `UNIT_SPELLCAST_*` argument is the cast bar name
  (`n=CastBar-1B595C..`), not the spell name — the old name-matching detector never fired, which is
  why the skin window was dumped as `k=corpse`. The skin window is a **second `LOOT_OPENED` on the
  same corpse GUID** (hypothesis confirmed). `LOOT_CLOSED` fires twice per close and
  `LOOT_SLOT_CLEARED` can repeat for the same slot in the same instant; both are de-duplicated
  before recording. `TARGET_DEAD` is now strictly a fallback: a GUID `UNIT_DIED` already reported
  produces no step, it only fills in the mob's name. **Not yet re-run in game** — the dump now also
  prints the stored record so one run verifies the model.
- **Recipe scan in the options panel**, `/nt scanrecipes`, rescan on every Alchemy window open.
- **`/mpack status`** prints version, Interface, client build, locale, GatherMate2 and module states
  (`NodeTrail: on (loaded) - skinning off`). TOC metadata is read through
  `pkg.GetAddOnMeta`: `C_AddOns.GetAddOnMetadata` first, then the legacy global (t_5507a0ba — the
  Forever client has no global `GetAddOnMetadata`, which printed "version unknown"). The bug-report
  header uses the same chain.
- **World-map overlay** (t_0f65b0b9): `/nt mapdiag` prints one labelled line per frame fact
  (WorldMapFrame / canvas / mapIDs / legacy frames / the parent MapOverlay picked / the last
  redraw) and works before any route exists (`route: none`). The overlay now measures whatever
  the client exposes — canvas, else WorldMapDetailFrame, else WorldMapButton — and converts map
  fractions through the measured map rectangle (`PathGeom.MapRect` / `FractionToPixel`), including
  the legacy inset (WorldMapButton inside WorldMapDetailFrame). Script hooks (`OnShow`,
  `hooksecurefunc` on `OnMapChanged` / `OnCanvasScaleChanged`, the canvas `OnSizeChanged`) are
  installed whether or not a data provider exists, so a map opened after `/nt start` still draws;
  no OnUpdate polling. **Still unproven in game** — run `/nt start`, open the map, `/nt mapdiag`.
- **Draw order + colour, measured** (t_c0a68ed2): the report `queued=2 segment(s)` with nothing on
  screen was taken apart by measurement, not assumption. On every redraw the overlay now measures
  the frames that cover the map — the legacy art frames (`WorldMapDetailFrame` / `WorldMapButton`,
  which the 1.2x-derived clients reparent INTO the canvas) and any shown canvas child covering at
  least half the canvas (the canvas detail-layer pool) — and raises its host above the highest of
  them (`top + 5`, adopting the art's strata when the art orders above it) instead of the old
  fixed `canvas level + 10`. The raise is sticky for the diag and never ratchets on its own host.
  `LineDraw` records the exact colour/thickness/space a draw applied, and `Describe()` reads a live
  line's shown/alpha/thickness/start/end back through the real region contract. `/nt mapdiag` now
  also prints: host level/strata/shown/size/alpha, the parent chain by name, the z-order audit with
  every candidate and whether the raise happened **on this redraw** or on an earlier one, the
  applied colour, both line objects, **every projected path point with its pixel coordinates**,
  every segment's length and skip reason, and one `verdict:` line naming the NEXT candidate — draw
  order (with the level it was raised from), draw order still broken (the client refused the
  raise), colour (alpha 0), geometry (a dot), or "cause unknown, next measurement". A raise is
  history, not a verdict: `raisedNow` vs `raisedEarlier` keeps the geometry/colour verdicts
  reachable, and `EnsureHost` never drops a raised host back to `canvas + 10`. **A raise is
  whatever the frame reads back after the call, never the call we attempted**: `SetFrameLevel`
  and `SetFrameStrata` are pcall'd and then `GetFrameLevel`/`GetFrameStrata` are read again, so a
  client that accepts the call and ignores it is reported as `raise attempted; the frame still
  reads level=… strata=…` / `NOT above the art` and the verdict says
  `DRAW ORDER (still below after the raise attempt) — … the client did not accept a higher
  level|strata`, instead of claiming a fix. Every per-redraw
  measurement (`points`/`segments`/`colour`) is cleared on entry, so a redraw that early-returns
  prints `not measured on the last redraw (<why>)` instead of the previous route's numbers.
  The minimap half prints the sample it actually used (mode, radius, unit), the player position,
  every point's pixel/`dist=x-radius inside|OUTSIDE`, every segment's clip decision, and its own
  verdict; the fraction fallback now follows the minimap zoom instead of drawing the same size at
  every zoom step. **The z-order fix is not yet confirmed in game** — `/nt mapdiag` with the map
  open is the proof (it must print `host_level` > `top`).
- **World-map line: the primitive, measured** (t_a08cb3e0). The live `/nt mapdiag` from `c220ec7`
  (Barrens 1413, 12 segments, 326.1px) settled it: `queued=12`, `z-order … above the art`,
  `colour … a=0.90`, and every line object `shown=true thickness=2.88 size=0x0` with
  `start=TOPLEFT(0.0,absent) end=TOPLEFT(0.0,absent)`. The frame, strata, alpha, colour and
  thickness were all correct — **the client accepted `SetStartPoint`/`SetEndPoint` and kept no
  geometry**, so the region had no line to draw and nothing raised an error.
  `LineDraw` no longer picks `mode="line"` on the existence of `Frame:CreateLine`: `detect` sets a
  known 64px diagonal on the new region and requires the endpoints (or the size) to read back
  (`D.LineProof`). When they do not, it falls back to **`mode="dots"`**: a chain of 2.5px quads
  anchored by two corners (`BOTTOMLEFT`/`TOPRIGHT`), spaced 3px, with **no `SetWidth`,
  `SetHeight`, `SetSize`, `SetRotation` or `SetTexCoord` call at all** — the primitive with the
  fewest setters left to be a silent no-op. `D.DotPlan`/`D.PlanDots` are pure and unit-tested
  (coverage, both endpoints, the 1200-object cap, size/spacing scaled together). `rotate` and
  `texcoord` stay as legacy fallbacks behind `disableDots`/`disableLine`.
  `/nt mapdiag` now prints `primitive: chose mode=… ; line proof: object=… GetNumPoints=…
  start=… end=… size=… -> KEPT|DROPPED; texture proof: SetPoint/SetWidth/SetHeight/SetSize/
  SetRotation/SetTexCoord presence, size setters -> WxH, two corner anchors -> WxH points=N`,
  plus an `anchor probe:` that repeats the two-corner experiment live and every held object's
  `object=` (GetObjectType), `numpoints=` and `points=[1:BOTTOMLEFT(...) 2:TOPRIGHT(...)]` and
  `methods=`. The verdict gained `verdict: PRIMITIVE` (names the dropped endpoints and says the
  route is now N anchored dots) instead of falling through to "no cause found".
  **A zero size on a Line is no longer reported as the cause** — a Line's extent comes from its
  endpoints, and `line 1 measures 0x0 (zero-size)` was the false accusation that hid the real
  defect for four rounds; `objectDefects` now judges each primitive by its own contract
  (endpoints for a line, two anchors for a dot, SetWidth for the rest).
  **`/nt mapdiag probe`** draws a solid 40x40 marker at the first route point, a 4px border around
  the full canvas, and one diagonal `(0,0)->(w,h)` through the same `LineDraw.Draw` the route uses,
  printing the coordinates and measured sizes of all three. It is **off by default**; `probe off`
  removes them. `/nt mapdiag primitive <auto|line|dots|rotate>` pins a primitive for one redraw and
  reports the mode the client's measurement ended up choosing — an in-game A/B with no code edit.
  **Not yet confirmed visible in game**: the probe is in place for that run.
- **The herb block has its own panel now** (t_f4ff9ea6) — `Modules/NodeTrail/UI/TooltipPanel.lua`.
  The addon no longer writes into `GameTooltip` at all: three append-based fixes (widen the frame,
  measure-and-`SetWidth` it, wrap our lines to the client's width) each lost to the client's own
  layout, and the third failed as "the backdrop stops covering our lines as I play". The block is
  now drawn in a frame NodeTrail owns — a `CreateTexture` background plus four 1px border textures
  (`SetBackdrop` is measured, never used), width taken from OUR lines only (measured with the
  tooltip's own font, padded, capped at 45% of the screen, long lines wrapped at `, ` / space /
  `: `, a percentage never split from its item name), and positioned READ-ONLY from the tooltip's
  rect: left edge on the tooltip's left, top edge just under `GetBottom()`, flipped above the
  tooltip when there is no room, clamped into the screen. Rows are rebuilt from scratch on every
  update, so a repeated hover cannot duplicate the block.
  **The font rule (review round 1, the defect this file had):** a font string created with no font
  object reports no width and no height on this client, and the first update used to adopt the
  tooltip's font *before* the rows existed — so hover 1 sized the panel from two fontless rows
  (72.0 px against the 150.6 px the text needs) and the text then grew outside its own background;
  a row added while the panel was already up had the same hole. Rows are now born with
  `CreateFontString(nil, "ARTWORK", "GameFontNormal")` **and** with the tooltip's font applied at
  creation (`_ApplyFont`), `Update` re-adopts after layout, and only then measures: the font it
  sizes with is the font it draws with, in the same update.
  **ttdiag's coverage verdict is built from measured TEXT (review round 2):** `covers its widest line=`
  compares the panel's width against `widestTextPx` — each row's own columns, `lw + rw`, with no 12 px
  column gap and no padding — and a second figure from the private meter font string at the adopted
  font. It reports NO when any text-bearing row measured 0. That matters because a herb block always
  has a value column: a verdict built from the full row width reports `text 12, covered` on a client
  that measures no glyphs at all (12 px being only the gap, 72 px being `MIN_WIDTH`), so the live
  six-hover report would prove nothing. Both figures are printed, and a blind update is named for
  what it is (`a text-bearing row measured 0`, drawn rows report the gap).
  Visibility comes from the existing poll clock only — no `HookScript`, no replaced method, no
  `Show()` on the tooltip. `/nt ttdiag` prints `panel: SHOWN … rect …`, the width budget, the widest
  of our lines, whether the width covers it, the adopted font and the backdrop measurement.
  **Not yet run in game**: the six-hover check and its `ttdiag` numbers are the next live step.
  *Grep scope:* zero `GameTooltip.<field> =` assignments anywhere in the pack and **no** tooltip
  write in `Modules/NodeTrail`; the one `GameTooltip:HookScript` left in the tree is Touchstone's
  read-only `OnTooltipSetItem` fallback (`Modules/Touchstone/ChestAdvisor/ChestAdvisor.lua:1388`),
  outside this addon's NodeTrail path and kept on purpose.
- **Tooltip flicker instrumentation + fix** (t_c0a68ed2): `Refresh` takes a `source`
  (`show`/`setunit`/`setitem`/`poll`) and keeps a ring of the last **8** evaluations — hovered name,
  NumLines before/after, whether `blockIntact` matched, whether the block was appended, whether
  Show/Clamp ran, and the decision — printed by `/nt ttdiag`. A **poll tick never shows the frame**:
  an append on a tick clamps the position only and defers the backdrop re-layout to the next real
  client show, because a Show from a tick re-runs the client's own show path under a tooltip it may
  be rewriting (the minimap herb flash). Every ttdiag read is pcall-guarded so the command works on
  a client that exposes almost nothing.
- **`/mpack bug`** — in-game report form; technical header auto-filled, `Copy report` for Ctrl+C, then
  paste into `#mightiepack-bugs`. The client cannot POST, so nothing uploads itself.

## Rules
- Serious work (vendoring, large writes, ports) → `d4cloud` (cloud model, high effort); routine edits →
  `d4` (local Qwen, medium effort). While Mightie is gaming the GPU is busy: everything goes to
  `d4cloud`. Local Qwen misbehaves above medium effort.
- Ask Mightie before deploys, merges, CurseForge uploads, or renaming the umbrella.
- NO deploy to the Forever client (no deploy script, no copying into any AddOns folder) until Mightie
  says so.
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
MightiePack/Modules/NodeTrail/UI/TooltipPanel.lua
MightiePack/Modules/NodeTrail/locale
MightiePack/Modules/NodeTrail/locale/enUS.lua
MightiePack/Options.lua
README.md
tests
tests/draw_smoke.lua
tests/pathgeom_spec.lua
tests/mapoverlay_spec.lua
tests/mapdiag_spec.lua
tests/recorder_spec.lua
tests/umbrella_spec.lua
tests/density_spec.lua
tests/tooltip_spec.lua
tests/tooltip_refresh_spec.lua
tests/tooltip_panel_spec.lua
tests/tooltip_no_gametooltip_writes_spec.lua
tests/support/fakeui.lua
tests/slash_spec.lua
```

## How modules load
- One TOC means every file gets the same private table (`pkg`).
- Umbrella code lives on `pkg` (global `MightiePack`).
- NodeTrail lives on the sub-table `pkg.NodeTrail` (global `NodeTrail`).
- Each NodeTrail file starts with `local addonName, pkg = ...` / `pkg.NodeTrail = pkg.NodeTrail or {}` / `local ns = pkg.NodeTrail`.
- Load order (MightiePack.toc): Core.lua, Modules.lua, the 16 NodeTrail files (locale, Config, Data/GM2, Data/Recorder, Data/Density, Data/HerbData, Data/Recipes, Route/Cluster, Route/Build, UI/PathGeom, UI/LineDraw, UI/MapOverlay, UI/MinimapPath, UI/TooltipPanel, UI/Tooltip, Core), Options.lua. `UI/TooltipPanel.lua` must load BEFORE `UI/Tooltip.lua`: the poller reads `ns.TooltipPanel` at call time, and the panel needs nothing from Tooltip.
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
- `tests/mapoverlay_spec.lua` (t_0f65b0b9: geometry with a Classic-era stub — WorldMapFrame WITHOUT GetCanvas, WorldMapDetailFrame 1002x1002 with the 986x986 WorldMapButton inset by 8: a known fraction lands at the expected pixel with and without the inset, an oversized inner frame is clamped, a zero-sized frame converts to nil with no division, the overlay parents to WorldMapDetailFrame, zero size queues nothing and asks for a retry, mismatched mapID and showWorldMap=off hide it, and mapdiag prints every line on that client)
- `tests/mapdiag_spec.lua` (t_0f65b0b9: `/nt mapdiag` on a client missing WorldMapFrame, canvas, legacy frames, Minimap, GetCVar, GetCurrentMapAreaID, C_Timer, hooksecurefunc and the canvas mixin prints every labelled line with no error; throwing GetCanvas/GetMapID/GetWidth still print `absent`; no chat frame falls back to print; `/nt status` is unchanged)
- `tests/mapdiag_zorder_spec.lua` (t_c0a68ed2: a canvas whose map art is a SIBLING frame at level 40 — the host must be measured above it, the level must not ratchet across redraws, the line must carry pathColor's alpha and the projected pixels, and mapdiag must print the host facts, the parent chain, the z-order audit with `RAISED from … on this redraw`, the applied colour, both line objects, every point's pixels, the segment lengths, the `verdict: DRAW ORDER` line on the raising redraw and — once the host is above the art — a verdict that names the NEXT candidate instead, with the raise carried as history)
- `tests/diag_truthful_spec.lua` (t_c0a68ed2 round 2: a later redraw never raises again and the verdict stops claiming draw order; a host the client refuses to raise is reported as `DRAW ORDER (still below after the raise attempt)` with the two levels; and after a redraw that early-returns because another map is open, `points:`/`segments:`/`colour:` all read `not measured on the last redraw (<why>)` instead of printing the previous route's numbers. Round 3 adds the two shapes the raise used to lie about: `SetFrameLevel` present but silently ignored (art at 80 → `raise attempted; the frame still reads level=45`, `raisedNow=false`, `stillBelow=true`, `the client did not accept a higher level`, and no `RAISED from 45 to 45`) and `SetFrameStrata` present but ignored (art HIGH at level 40 → audit keeps the MEASURED `MEDIUM`, the z-order line reads `NOT above the art`, and the verdict says `the client did not accept a higher strata`))
- `tests/minimap_diag_spec.lua` (t_c0a68ed2: with no redraw yet the minimap verdict says `no redraw on a usable minimap sample yet`; a route inside the view is drawn and the diag prints mode/radius/unit + per-point `inside`; a route 0.4 map away queues nothing and the diag names the OUTSIDE points and the per-segment clip reason; the fraction fallback follows the zoom (`dist` grows when zoomed in) and `/nt mapdiag` carries the minimap half)
- `tests/ttdiag_minimal_spec.lua` (t_c0a68ed2: `/nt ttdiag` with no GameTooltip, a bare tooltip table, a shown-but-unreadable tooltip, readers that RAISE, a ring entry recorded from an empty tooltip, and a chat frame that raises — every read prints `absent`/`?`, nothing errors, and the ring is always printed)
- `tests/tooltip_refresh_spec.lua` (t_f4ff9ea6 rewrite: the poll clock is the only driver — Enable
  installs NO GameTooltip script and replaces no method, a hidden tooltip hides the panel and spends
  no evaluation, a herb shows the block, a non-herb and a unit tooltip hide it, six hovers of the same
  herb render the same rows with one frame, the clock is throttled to ~5/s, the diag prints the panel
  rect/budget/widest, and a full hover cycle writes nothing into a write-hostile tooltip proxy)
- `tests/tooltip_panel_spec.lua` (t_f4ff9ea6: the panel is built and positioned from a fake tooltip —
  below, flipped above near the bottom edge, clamped at both side edges; six hovers plus a font change
  and a scale change always leave the width >= the widest line; a long line wraps at `, ` under the
  45% cap while "100% (base)" stays whole; a scaled UI does not double the panel's scale; an
  unreadable tooltip rect builds the block but never places it blind; nothing is written to the
  tooltip. T2b pins review round 1's defect: every row carries a font in the very update that set the
  width, and the width covers an INDEPENDENT meter measurement. RED at `007b919` with `T2: panel width
  72.0 >= widest line 150.6` and `T2b: … (got 4 fontless)` — the first hover sized the panel from
  zero-width rows. **T8b pins review round 2's defect:** a client whose font strings all report 0
  (`F.blindMeasure`, font intact) must produce `covers=false`, `info.covers=false`, `widestTextPx=0`
  and a ttdiag line `covers its widest line=NO (panel 72 vs text 0 + padding 20 = 20 …; a text-bearing
  row measured 0; drawn rows report 12)`, then cover again once the client measures. RED at `157f4da`
  with 6 FAILs, the first being `T8b: an update that measured no text reports covers=false (got
  true)`. RED on the installed build too, where `UI/TooltipPanel.lua` does not exist)
- `tests/tooltip_no_gametooltip_writes_spec.lua` (t_f4ff9ea6: the grep gate — no field is assigned on
  GameTooltip anywhere in the addon, exactly one `GameTooltip:HookScript` exists in the whole tree and
  it is Touchstone's read-only `OnTooltipSetItem` fallback, zero tooltip method calls in
  `Modules/NodeTrail`, and neither tooltip file calls `:HookScript(`, `C_EventUtils` or registers
  `COMBAT_LOG_EVENT_UNFILTERED`. RED on the installed build with 3 hooks)
- `tests/slash_spec.lua` (module gating (no /nt before Enable), slash names, help content, empty/unknown = help, reload without route, status lines (source density/gm2, counts per map and total, unknown map, route none/active, tooltip on, Alchemy scanned/not, module on/off), start/reload/stop round trip from recorded herbs, case and whitespace)
- `tests/status_meta_spec.lua` (t_5507a0ba: /mpack status TOC metadata — C_AddOns-only, global-only, neither, precedence, nil/empty/raise/non-string fallbacks, no cached provider)
- `tests/touchstone_fold_spec.lua` (Touchstone fold: TOC block order and Assets line, skip guard on every generated file, disabled module registers no slash/creates no frame, Enable calls SF.Enable once and preserves StatForgeDB, duplicate-load detection by DoesAddOnExist/GetAddOnInfo/unknown, full enable brings up the real slash set and ChestAdvisor frame)
- `tests/mapdraw_primitive_spec.lua` (t_a08cb3e0: the LIVE client shape — a `CreateLine` region whose `SetStartPoint`/`SetEndPoint` return and whose getters keep reading `TOPLEFT(0.0,absent)` at `size=0x0`, and a texture with no `SetWidth`/`SetHeight`/`SetRotation`. Pins: the line primitive is refused by measurement and the overlay falls back to `mode="dots"`; the dots are two-corner-anchored 2.5px quads every 3px that cover the segment end to end and reach both endpoints; the diag prints `primitive:` with both proofs, `anchor probe … two corner anchors -> 64x8 points=2`, and the held object's `object=`/`numpoints=`/`points=`/`methods=`; `verdict: PRIMITIVE` names the dropped endpoints instead of blaming a zero size; `mapdiag probe` draws the marker/border/diagonal with printed coordinates and is off by default; `mapdiag primitive <auto|line|dots|rotate>` reports the mode the measurement chose, not the one requested; and a client whose line region DOES keep its endpoints still uses `mode="line"`. Also unit-tests the pure `DotPlan`/`PlanDots` (coverage, both endpoints, the 1200-object cap, size/spacing scaled together). RED on `c220ec7` with 40 FAILs)
All spec files and `tests/draw_smoke.lua` pass with lua5.1 at `t_f4ff9ea6` HEAD
(the panel fixes in review rounds 1 and 2 leave the whole suite green; the passing
numbers are unchanged — 177.2 px after six hovers, 274.0 px at font 20, cap 864 px).
On `c220ec7` the four specs this card touched are RED with **51 FAILs**
(`mapdraw_primitive_spec` 40, `diag_truthful_spec` 6, `draw_smoke` 3, `minimap_diag_spec` 2);
the other 23 stay green.

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
- New files: `MightiePack/Modules/NodeTrail/Data/HerbData.lua`, `Data/Recipes.lua`, `UI/Tooltip.lua`,
  and (t_f4ff9ea6) `UI/TooltipPanel.lua` — loaded BEFORE `UI/Tooltip.lua` in the TOC.
- `ns.Enable()` now also calls `ns.Recipes:Enable()` and `ns.Tooltip:Enable()`. Loading the files hooks nothing and registers no events; a disabled module adds no tooltip lines.
- Hover detection (t_f4ff9ea6): the private poll clock (5x/second) asks whether the tooltip is shown,
  whether no unit is moused over, whether the tooltip owner is UIParent/WorldFrame (world object),
  and whether tooltip line 1 is a known herb node name from the HerbData table (English names). The
  tooltip is never hooked and never written to; the block is drawn in NodeTrail's own panel
  (`UI/TooltipPanel.lua`, see the Status section). A hidden tooltip hides the panel without spending
  an evaluation.
- Panel rows: one row per drop "<item> <pct>%" (suffix "(base)" when from the baseline stub); "Your picks: N" or "Your picks: none yet"; "Alchemy: <recipe>, <recipe>, ..." (first 4, then "+N more"), or "Open Alchemy once to list recipe uses" if Alchemy was never scanned.
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
1. Mightie smoke-tests the folded Touchstone in game on this desktop: park the standalone folder
   (laptop), install the build, `/reload`, tick Touchstone, `/sf`, check a few gear verdicts.
2. Skinning dump from the Skinning character: with the sub-option ON, 10–15 kills, then
   `/mp skindiag dump`. The dump now ends with the stored record, so that one run verifies the
   recorder as well as the event surface.
3. Skinning 3/3: the UI side — leather vs corpse loot compared per creature, baseline vs personal
   (n≥10 only), hunt areas instead of node dots. The recorder's fields are in place.
4. Friend build: NodeTrail + Touchstone + Skinning, one zip; then the CurseForge upload when Mightie
   approves.

## Known gaps
- Touchstone fold never loaded in game: load order inside one TOC, `GetChildProfessionInfo`-style API
  presence, and the minimap button are all unproven until the smoke test.
- Touchstone settings migration is unproven on this machine — the desktop client has no old data;
  migration is proven only by copying the laptop's `Touchstone.lua` across.
- Skinning event surface is measured (see the recorder bullet): `UNIT_DIED` + spell 8613 + a second
  `LOOT_OPENED` on the same corpse GUID. What is still unproven is the **recorder's output in
  game** — the dump now prints the stored record, so one `/mp skindiag` run confirms it.
- Recorder still assumes `UNIT_SPELLCAST_SUCCEEDED` for herb gathering, loot within 5 s, player
  position rather than node position.
- Density tunables have never been tuned against real data.
- MapOverlay/MinimapPath frames load even when NodeTrail is off.
- **The world-map line is fixed by measurement but not yet SEEN in game** (t_a08cb3e0). The client
  accepted every `SetStartPoint`/`SetEndPoint` and kept no geometry, so the route is now a chain of
  two-corner-anchored dots. The next in-game run answers two things with `/nt mapdiag probe`: which
  of **marker / border / diagonal** is visible (nothing visible = frame/strata/alpha, or no texture
  primitive at all; marker+border only = the stroke path; all three but no route = the route
  geometry), and whether `two corner anchors -> WxH` on the `anchor probe:` line is non-zero. If the
  marker and border draw but the diagonal does not, `/nt mapdiag primitive rotate` (then
  ``texcoord``) A/Bs the remaining primitives without a code change.
- The world-map line has never been seen drawing in game. `/nt mapdiag` reports which frame this
  client exposes (canvas vs WorldMapDetailFrame vs WorldMapButton), the measured sizes, the
  displayed vs route mapID, what the last redraw queued, the measured draw order (host level vs the
  top art frame, with the raise recorded), the applied colour, both line objects, every projected
  point's pixels and a verdict line — that output is what closes the gap. t_c0a68ed2 added the
  z-order audit (a raise that already happened is reported as history, not as the verdict) and the
  next in-game run has to show `host_level` > `top`; if the line is still invisible, the `verdict:`
  line now names the next candidate instead of repeating draw order. If the diag says
  `DRAW ORDER (still below after the raise attempt)`, the client refused the raise and the two
  levels printed on that line are the finding.
- The held line OBJECTS are now measured too (`line 1:` / `line 2:` print size, level, strata,
  parent and vertex colour; a region with no independent z-order says `inherits the host`). The
  verdict names a `LINE OBJECT` cause — zero-size (0x0 only; a horizontal line legitimately has
  height 0), alpha 0, hidden, or the object sitting below the art — instead of falling through to
  `no draw-order, colour or geometry cause found` while the line is invisible. After a redraw that
  never reached the measurement stage, the objects' held endpoints print `not from the last redraw
  (<why>)` rather than the previous route's pixels.
- The minimap path's `queued=0` report is now explained per point/segment (inside/OUTSIDE vs the
  clipped circle, mode, radius and unit). If the in-game numbers say the route is simply farther
  than the view radius, nothing is wrong to fix — the diag says so instead of leaving it ambiguous.
  With no redraw recorded it prints `minimap verdict: no redraw on a usable minimap sample yet`
  rather than claiming a draw.
- The tooltip flash is instrumented, not proven fixed: the ring in `/nt ttdiag` must show the real
  sequence on the minimap hover (who fired, how many lines, whether Show ran) before the fix is
  called confirmed.
- The herb block has its own panel now, and the in-tooltip approach is withdrawn (t_f4ff9ea6) — the
  three append-based fixes all lost to the client's own layout, so the append path is deleted, not
  tuned. What is still unproven is the LIVE run of the replacement: hover a herb, leave, hover the
  SAME herb six times, then play ten minutes and hover again, and quote `/nt ttdiag`. The `panel:`
  lines give the rect, the width budget (45% of the screen), the widest of our lines, and
  `covers its widest line=yes|NO`; the answer closes the card. The specs prove the arithmetic on a
  modelled client, not the pixels on Forever.
- Herb tooltip node names are matched in English only.
- `/mpack status` reports `inert` for a module that refused to start (standalone Touchstone present).
