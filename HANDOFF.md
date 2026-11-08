# NodeTrail Handoff

## Status
Bases A–E are on `main` (`c96bf91`, PR #2–#7).

**2026-11-08 — branch `fix/tooltip-refresh`, unmerged, unpushed, undeployed.**

- **The minimap route is now checked against the objects it drew, not against its own maths**
  (t_86583cf2). The earlier check was circular: it compared the diag's fresh recalculation of the
  player's map fraction with the previous recalculation. Now the drawer STAMPS every draw
  (`drawer.lastApplied.time/.mapID/.playerFrac`, mirrored on `MinimapPath._stamp`) and
  `/nt mapdiag` prints that stamp back verbatim — never recomputed — plus the anchors the client
  reports for the nearest drawn dot (`GetPoint(1)`/`GetPoint(2)`), the centre they imply, its
  distance from the minimap centre in px / radii / map fractions, the route segment and point that
  dot belongs to, the world-map canvas anchor for the same index, drawn-vs-planned counts and
  whether the ticker has fired since the last player move. New lines: `minimap stamp:`,
  `minimap drawn dot:`, `minimap drawn dot route:`, `minimap drawn vs planned:`,
  `minimap crosscheck:` (per index: world canvas anchor, minimap px, drawn/hidden + reason,
  mapID equality) and `minimap scale audit:` (HereBeDragons yard distance ÷ drawn px = the real
  yd/px, so the 0.075 fallback can be measured instead of assumed; prints `absent` without HBD).
  The WORLD MAP half got the same treatment: `route dots on the visible map: <inside>/<painted> inside
  (measured <m> of <p> painted; …)` (a route that is 100% outside can no longer read as a pass, and
  neither can one that is only partly measured — see the third-pass note at the end) and
  `/nt mapdiag probe` now draws
  labelled markers at #1/#10/#20/last plus `P` for the player, printing canvas, host and
  WorldMapFrame/ScrollContainer rects. New `/nt minimap on|off` switches the minimap route alone
  (world map untouched). New `/nt navwalk start|mark <label>|clear` records the four-stop walk
  (client coords, draw-time stamp, drawn anchors, segment/point index, distances) into
  `NodeTrailDB.navwalk`, which the client writes on `/reload` — so the live table can be read off
  disk instead of transcribed. New `tests/minimap_walk_spec.lua` replays four stops on a synthetic
  segment beside a landmark and asserts the DRAWN anchors (read from the regions) sit where the
  stamp puts them, move opposite the player, keep a constant offset from the landmark, and that the
  player's distance to the segment shrinks → ~0 → grows. It replays BOTH projections: the fraction
  fallback (§A) and, with a fake HereBeDragons, world mode with `C_Minimap.GetViewRadius()` yards
  (§G — the projection this build ships). **77 FAILs on `d34dcb3`**, green at this commit; all 45
  `tests/*.lua` pass under lua5.1. The live four-stop walk in Mightie's client is
  still the operator's step — the numbers this card's acceptance needs come from `/nt navwalk`.
  **The table already collected is from the pre-HBD build; see the third-pass note at the end.**
  Route generation and the dot primitive (`UI/LineDraw.lua`) are untouched.

- **The beast panel shows what SKINNING yields — the corpse loot is gone** (t_2c573dbf).
  Mightie on a Dire Mottled Boar: "beast tooltip doesnt need the actual items the mob can drop. Just
  what we obtain from skinning." `Data/SkinHints.lua` no longer aggregates or renders the corpse
  side: rows are the client's name, `skinnable · skin windows recorded: N` (only when known),
  `skinned` + its item rows, then `kills seen: N · skinned: M`. No `corpse loot` heading, no corpse
  item row, no corpse percentage — nothing read from the loot window that opened before the Skinning
  cast. The RECORD is untouched (`Modules/Skinning` still writes `corpseItems` into
  `NodeTrailDB.skinning`); the panel simply stops reading it, and `H.Aggregate` no longer builds a
  corpse list at all. The only item percentages left are the skin ones, still floored at
  `HerbData.PERSONAL_MIN` and never printed when an item outnumbers `skinned` (a skin window with no
  successful cast behind it is such a case: `Record:OnSkinLoot` does not set `rec.skinned`).
- **`Scroll: LOWER PING WHOMEVER` is the CLIENT's own name for item 211787** — the id question
  (t_2c573dbf). That label came from `GetItemInfo(id)`, so it was checked against the id instead of
  being "fixed": `/nt ttdiag` now prints one line per distinct recorded item id —
  `beast: item id: 211787 -> "Scroll: LOWER PING WHOMEVER" (GetItemInfo) · corpse · the loot slot said the same`
  — and says `DISAGREES (the keying is wrong, not the label)` when the client's name for that id is
  not the name the loot slot reported, and `GetItemInfo answered nothing` / `answered a secret
  string` when the client has no usable name. Item 211787 is a real world drop of **this** client's
  data (WoW Forever 1.60.1 / build 16001 — wowhead `/forever/item=211787`,
  `warcraftforever.wiki`, `thewowdb`, `ahledger` all carry the same id and name), so the label stays
  and no keying change was made. A secret answer is reported, never concatenated (the same
  `issecretvalue` guard `ItemName` uses). `tests/skin_tooltip_spec.lua` pins all of it: §1b the block
  line-for-line with no corpse trace, §2/§6 the thin and never-skinned cases, §12 the four id→name
  answers, §11 the impossible-percentage guard moved to the skin side. **16 checks fail on `d34dcb3`**
  (the new §1b/§2/§6/§12 checks, behavioural FAILs, no traceback); all 42 `tests/*.lua` pass under
  lua5.1. **Not yet run in game**: the live `id -> name` line for his own boar record is the next
  step — that is the one thing the specs cannot prove for this client.

- **Hovering a BEAST now shows what its corpse and its skinning have yielded** (t_c0221fd7).
  Mightie: "we are missing the skinning tooltip ... says what we might get if we kill it and skin
  it. Same as herbing just another step in the middle." The block is NodeTrail's own panel again
  (the poller drives it; nothing is written into `GameTooltip`), it appears only on a hovered
  `Creature` GUID whose `UnitCreatureType` is a beast and only when `Pr:Skinning()` does not say
  "no", and every number in it is an aggregate of OUR recorded corpses for that NPC id —
  `NodeTrailDB.skinning.chars[Name-Realm].records[*].creatureID` — never a researched table, because
  no such table exists for a beast. Rows: the client's creature name, `skinnable · skin windows
  recorded: N` (only when known), `corpse loot`, `skinned`, then `kills seen: N · skinned: M`.
  (**t_2c573dbf later removed the `corpse loot` section and its rows** — the panel is skinning only;
  see the bullet above.)
  A percentage is printed only at `PERSONAL_MIN` (reused from `HerbData`) and is labelled
  `(yours)`; below that, and whenever an item was seen more often than the sample that would
  divide it, the row is a count. New `tests/skin_tooltip_spec.lua` drives the REAL recorder to
  build its records: **46 FAILs on `06984f6`**, green at this commit; all 42 `tests/*.lua` pass under
  lua5.1. See the t_c0221fd7 section below for the measured client evidence and what is not yet
  proven in game.

- **The record now carries the items its windows carried, and a skill-line storm no longer eats
  the buffer** (t_67f26739). Live at Razor Hill the step log had `i=5466x1,4867x1` on the corpse
  window and `i=2318x1` on the skin window while the RECORD for the same corpse `..10B81C` said
  `corpse items: none seen (late read)` / `skin items: none seen`. Cause: a re-read of a LIVE loot
  window sees the window after the player took the items out, so it is a SUBSET of the earlier
  read — and `RereadWindow`/`R:SetWindowItems` REPLACED the window's list with it. Both layers now
  ACCUMULATE within one window (an item once seen in that window is never un-seen; its quantity
  only grows), and the probe writes the record on `LOOT_OPENED`, on **every** `LOOT_SLOT_CLEARED`
  and once more just before `LOOT_CLOSED` — where `Describe` re-renders it from the window log.
  The same run's 18 identical `SKILL_LINES_CHANGED` events on one timestamp (sk 181..200) each cost
  a ring slot; identical consecutive events (same name, same argument, same or next tick) now fold
  into one line with `(x18)`, and the duplicates line reports `SKILL_LINES_CHANGEDx17`. Money left
  the item lists (`i=5466x1,4867x1 coin=57` — it is counted beside them, never inside), a
  cast-bar's frame name never reaches the spell field (`last skin cast: spell=8613`; the name comes
  from `GetSpellInfo` when the client gives one), and a missing unit name prints `unknown`, never
  `?`. New spec `tests/skinning_items_spec.lua` replays the dump (burst + both item windows +
  the 8613 cast + the 2.77s gap): green at HEAD, **28 FAILs** on `aed27bc`. `skindiag_secret_spec`'s
  section I changed with it: `,money` in an item list is now the defect, not the fix.

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
  since. Now `NodeTrailDB.route = { active, mapID, startedAt, autoRefresh, autoRefreshPicks }` holds
  the **intent only** — no path, no anchors, no points (the spec asserts all three stay nil) — and
  `Modules/NodeTrail/Route/Auto.lua` (new, `ns.RouteAuto`, loaded right after `Route/Build.lua`) owns
  every automatic path (the per-pick trigger was replaced by a 5-gather tranche — see
  **t_57550700**):
  1. `Enable()` (a login and a `/reload` both run it) rebuilds and draws the saved route for its map
     — no command — and says `route restored (13 points from 12 herb picks on map 1429)`
     (trigger `login`). Off-map, the intent is kept and nothing is drawn until the player is back
     there; a `PLAYER_ENTERING_WORLD` handler rebuilds on arrival (and only redraws when the route is
     already in memory). A nil/unknown map at `ADDON_LOADED` is not "another map" and is not logged —
     the world event right after login is the answer.
  2. `ns.RecordHerb` now only **moves a due time** (`SchedulePick`: `GetTime() + 5`, pushed out by
     each pick). The frame's `OnUpdate` calls `Pump`, which rebuilds once, a few seconds after the
     last pick (trigger `pick`). Nothing is ever rebuilt inside the loot/gather event. (Since
     t_57550700 the window is only armed by the 5th pick of a tranche.)
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

- **The route was at the player all along; it was INVISIBLE over bright terrain** (t_7f6fdae4).
  Mightie: "the mini map has a different 'line' than the actual map. Im far from the line in the map,
  its across the zone." The two projections agree — the world-map points `#10 (560.3,241.2)` and
  `#11 (537.5,235.5)` straddle his own frac `(0.543,0.364)` → canvas `(544,243)`. What disagreed was
  legibility: 2.88 canvas px of white at 0.9 alpha on a canvas shown at **0.696** scale is **2.0
  screen px**, and the Barrens' tan centre swallows it. Where the route crossed dark ground (the
  north edge) it read as a line — hence "there's a line up there, not here".
  - **Dot size is now a SCREEN measurement**: `LineDraw.DotMetrics(pathWidth, canvasScale)` puts a
    **3px floor on screen** and divides by the scale (`2 / 0.696` → `4.31 canvas px = 3.00 screen px`).
    Spacing matches the dot, so the chain stays continuous at any zoom. The `pathWidth` setting and
    the `pathColor`/alpha path are untouched; the old canvas floor (`2.5px`) is gone.
  - **Every dot is drawn twice**: an opaque near-black dot 2 screen px larger (a 1px rim, sublevel 6)
    first, then the white dot (sublevel 7) — contrast, not brightness, because the map art's colour
    changes per zone. This doubles the regions per draw (the allocation cap still counts DOTS, not
    regions). Same treatment on the minimap, where the host's scale is read (`GetScale`) so both
    surfaces agree at 3 screen px.
  - **`/nt mapdiag` now says what it divided by**: `dots: canvas scale=0.696 pathWidth=2 px ->
    dot=4.31 canvas px = 3.00 screen px; outline=7.18 canvas px = 5.00 screen px; spacing=4.31 canvas
    px = 3.00 screen px; screen floor=3.00px; dots=51 object(s)=102`, and the minimap has its own
    `minimap dots:` line. A size without the scale cannot be checked — that is why "2.88px" hid the
    bug for four rounds.
  - New spec `tests/mapdot_scale_spec.lua` (5 sections, real files, fake canvas **at 0.696**):
    the pure metrics, ≥3 screen px measured off the drawn regions, **one outline object drawn before
    every white dot** (lower sublevel, larger, same centre), the diag line, and the minimap agreeing.
    **Green at HEAD, 16 FAILs before the fix.** Two existing specs pinned the old geometry
    (`2.5px` dots / `size=2.50`) and were updated to the 3 screen px contract. All 33 `tests/*.lua`
    pass under lua5.1. Line-mode clients are unchanged — this client draws dots only.
    **Not yet seen in game.**

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
- `tests/mapdot_scale_spec.lua` (t_7f6fdae4: the fake canvas is shown at **0.696** scale, the LIVE
  proportion, and the route is the live one — canvas `(403.6,108.2)` → `(581.6,224.5)`. Pins: the dot
  floor is 3 SCREEN px and canvas px = screen px / scale, on a zoomed-in canvas too and with a wide
  `pathWidth`; the drawn white dots measure ≥ 3 screen px and still start/end on the projected
  points; **every white dot has a dark outline object created before it, larger, centred on the same
  pixel and on a lower draw sublevel**; `/nt mapdiag` prints `dots: canvas scale=0.696 … dot=4.31
  canvas px = 3.00 screen px; outline=7.18 canvas px = 5.00 screen px …`; and the minimap lands on the
  same 3 screen px with the same outline. RED on `c3cf817` with 16 FAILs, the first being
  `the narrowest white dot is still >= 3 screen px (got 1.9999999999999)`)
- `tests/mapdraw_primitive_spec.lua` (t_a08cb3e0: the LIVE client shape — a `CreateLine` region whose `SetStartPoint`/`SetEndPoint` return and whose getters keep reading `TOPLEFT(0.0,absent)` at `size=0x0`, and a texture with no `SetWidth`/`SetHeight`/`SetRotation`. Pins: the line primitive is refused by measurement and the overlay falls back to `mode="dots"`; the dots are two-corner-anchored 3px quads every 3px (t_7f6fdae4: the 3 SCREEN px floor; they were 2.5px when the floor was a canvas size) that cover the segment end to end and reach both endpoints, drawn twice (dark outline first, white on top); the diag prints `primitive:` with both proofs, `anchor probe … two corner anchors -> 64x8 points=2`, and the held object's `object=`/`numpoints=`/`points=`/`methods=`; `verdict: PRIMITIVE` names the dropped endpoints instead of blaming a zero size; `mapdiag probe` draws the marker/border/diagonal with printed coordinates and is off by default; `mapdiag primitive <auto|line|dots|rotate>` reports the mode the measurement chose, not the one requested; and a client whose line region DOES keep its endpoints still uses `mode="line"`. Also unit-tests the pure `DotMetrics`/`DotPlan`/`PlanDots` (coverage, both endpoints, the 1200-dot cap, size/spacing scaled together). RED on `c220ec7` with 40 FAILs)
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
- **The legibility fix is measured but not yet SEEN in game** (t_7f6fdae4). The route is drawn at
  3 screen px with a dark rim; one world-map screenshot over the **bright centre of the Barrens**
  closes it, and the `dots:` line of `/nt mapdiag` states the scale and both sizes so the numbers can
  be checked against what the eye sees. What the client still cannot be asked is whether it paints
  the outline BELOW the white dot: the pool order and a lower draw sublevel both say "under", and if
  a zone ever reads inverted, the sublevel pair (6/7) is the single place to change.
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

### t_ec00e4f3 — the world map painted only the opening leg (measured, partly fixed)

**What the pixels say.** Two live screenshots of the same 17-point Barrens route, from two
different builds (2.88px dots at 10:25, 3px dots with a dark rim at 10:58) and two different
zooms, show the same thing: ONE short dash stroke near Orgrimmar and no other route pixel
anywhere on the map. A pixel scan (near-white, low-saturation) of the 10:58 shot found exactly
one cluster, 24x18px ≈ one 43-canvas-px segment, plus the player arrow. The minimap, drawing the
same path at the same moment, showed both legs. So the dots are not "too faint" and the route is
not "somewhere else": **the chain stops after its opening segment.**

**The route itself is sound.** `Density.Build(cell 0.02, warm 0.4, anchorCell 0.06, smooth 2,
maxStops 4)` on the live herb data reproduces exactly the 17 points / 16 segments the diag
reported, starting at canvas px (407.6, 98.0) — and the card's visible cluster
`0.4068..0.4454, 0.1448..0.1594` is points #1..#3 of that path. Reproduced offline, the drawer
paints all 130 dots (260 regions) on a permissive client, so the geometry/plan is not the defect.

**Three real defects fixed (each one can produce exactly this symptom).**
- *Painted was a tautology.* The dots branch derived `dots` from the loop index, so a route that
  stopped after its first segment still reported the whole plan. It now counts the dots whose own
  region exists (`paintedDots`) and reports `missingDots` — the number it could not paint.
- *A region ceiling truncated silently.* When `CreateTexture` stops handing out regions (the
  codebase already guards every create against that), the drawer used to skip those dots and keep
  counting; the route ended at the ceiling. It now records the measured `capacity` and re-plans the
  same route onto the regions that exist — fewer, wider dots that still span it end to end. On a
  150-region client a 130-dot plan becomes a 73-dot plan with `painted == planned == 73` and the
  last dot exactly on the closing point (spec A).
- *`hideFrom` used `#pool`.* A pool with one nil slot has an unspecified length, so the tail of a
  previous route could survive a shorter pass. It now hides to a high-water index; the diag prints
  the index and how many objects it hid.

**Instrumentation, so one run answers the card.** `/nt mapdiag` on the world map now also prints:
- `dots pool: planned=… painted=… sized=…/… anchored=…/… missing=… objects=… shown=… highest=…
  capacity=… widen=… replans=… refits=… prevPainted=… hideFrom=… hidden=… hiddenObjects=…
  createFailed=… reverted=… capStale=… stale=…` (t_57550700: `replans` = plans that replaced a
  different plan, `refits` = capacity re-fits, `hidden` = the DROP in painted dots with
  `hiddenObjects` behind it, `stale` = the ratchet tripwire `highest > 2 × painted`) — planned
  vs painted vs *measured* (`sized`/`anchored` read every painted object's `GetWidth`/`GetHeight`
  and `GetNumPoints`, so "created, shown, and 0x0" can no longer pass as painted).
- `dots box: painted bbox=… host=…x… outside=…/…` — where the painted dots LAND. A dot outside the
  host is invisible on a screenshot and looks exactly like a dot that was never painted; only the
  numbers tell them apart.
- `dot 8:`, `dot 9:`, `dot mid:`, `dot last:` in the same shape as `line 1:`/`line 2:` (shown,
  alpha, measured size **next to the planned size**, parent, both anchors). `dot mid`/`dot last`
  are the middle and final dot of what THIS draw painted: if they are shown with the right size and
  the route is still short on screen, the fault is draw order or clipping, not the paint.
- `draws: N draw(s) recorded, newest first: #seq count=… dots=…/… hideFrom=… hid=…` — a later pass
  that rewrites the pool with a shorter buffer is now visible instead of invisible.
- `clips: host clips=… rect=… ; hostParent … ; canvas …` — and the overlay host now calls
  `SetClipsChildren(false)`, so a client that clips children by default cannot crop the route.

**Review round 2 (three defects, all reproduced then fixed).** The review measured, on the spec's
own 40-region client, that every painted dot was `1034.8x1034.8 px` while the diag reported
`dotSize=4.31` — the retry loop called `paint(p2)` *before* testing `missing2 ~= 0`, so a plan that
could not fit was written into the pool and then abandoned, and `planFitting` kept widening past
the point where `PlanDots` could still shrink (the floor is both endpoints of every segment), which
is where the 1034px came from. Three fixes:

- **A plan is only painted when its dot count already fits.** `planFitting` now binary-searches the
  widen between 1 and the coarsest plan and returns nil when even that floor is too big; the retry
  checks the plan *before* touching the pool (`plannedDots(p2) <= capacity/2`), and if a plan that
  fitted on paper still comes up short it repaints the first plan so the pool always holds the dots
  the reported numbers describe (`reverted=true`). On the 40-region client the pool now holds 19
  dots of 4.31 px with `missing=111` — the "normal dot size + honest shortfall" the previous
  handoff claimed but did not produce.
- **`dot N:` prints the MEASURED size next to the planned one** (`size=1034.8x1034.8
  planned=4.31x4.31` cannot be mistaken for a healthy dot).
- **A recorded ceiling is re-measured upward.** `drawer.capacity` only ever decreased and was
  cleared only on a parent change, so one transient `CreateTexture` refusal widened and shortened
  every later draw for the session. A create that succeeds at `capacity + 1` now clears the ceiling
  and the widen it forced (`stale=true` on the diag line).

Also fixed, because it cost three rounds of chasing a geometry bug that only existed in the probe:
`TextureProof`'s two-corner probe anchored `BOTTOMLEFT` at y −8 and `TOPRIGHT` at −16, i.e. the top
edge above the bottom edge, so the client answered height **0** and the diag printed "two corner
anchors -> 64x0". The bottom anchor now gets the larger y-down offset.

Spec: `tests/mapdot_capacity_spec.lua` grew sections G–K (retry never paints an unfit plan; ceiling
re-measured upward; measured-vs-planned size in the middle-dot lines; `sized`/`anchored`/`dots box`
in the diag; the probe's anchors the right way up). **43 FAILs on `62c26b4`, 13 of them also red on
`51819d6`** (the reviewed commit), green at HEAD; all 36 `tests/*.lua` pass under lua5.1.

**Still unproven in game.** Which of the three it was. The build is installed; one world-map
open + `/nt mapdiag` closes it: `painted == planned` with the full loop visible is done. If the
loop is still short and `painted == planned`, read `dots box` (`outside=0/n` but nothing on screen =
draw order or clipping), then `dot mid:`/`dot last:` (`size=0x0` = the client kept no geometry;
`shown=true` with a real size = it is drawn and something covers it), then `draws:` (a
`count=2`/`count=3` pass on top of a `count=16` one means a rebuild shrank the route and `hideFrom`
cropped the pool).

### t_57550700 — the route re-planned under the player while gathering

**The complaint.** Mightie, gathering south of Crossroads: *"while i gather south of crossroads another
line as started to fill in?"* — a second line on the world map, no reload. Cause: `autoRefresh`
defaulted to TRUE and **every pick** moved a debounced re-plan of the whole zone route, so the ground
the line told him to walk changed under his feet. Then, from the live diag of a second re-plan in the
same session (no reload):

```
redraw: queued=36 segment(s); LineDraw mode=dots; objects held=908
dots pool: planned=240 painted=240 ... objects=908 shown=480 highest=908 replans=0
           hideFrom=481 hidden=0 ... stale=false
```

**What shipped** (branch `fix/tooltip-refresh`, local only — no push/merge/tag/deploy):

- **The trigger is a TRANCHE of gathers, not a clock.** Mightie's final ruling: *"change from minutes
  to every 5 gathers. doesnt need to come off by default."* `NodeTrailDB.route.autoRefreshPicks = 5`.
  `SchedulePick` counts every pick; the 5th (and any later one in the same tranche) arms the
  debounce; `Pump` rebuilds once, a few seconds after the last one. The counter resets with the plan,
  so a tranche is one re-plan, never one per herb. `autoRefresh` stays **ON by default**.
- **Guards** (`RouteAuto:Gate`): never while a loot window is open (`LootFrame:IsShown`), never in
  combat (`UnitAffectingCombat("player")`), never within 30 s of the previous plan. A shut gate keeps
  the armed window and looks again every second, so a loot window that closes or a fight that ends
  does not swallow the rebuild. Manual rebuilds (`/nt reload`, `/nt start`) are never gated.
- **`/nt autorefresh [on|off|<picks>]`** — switch, or how many gathers make a re-plan due (clamped
  2..100: 1 would be one re-plan per herb again). `/nt status` gains
  `Auto re-plan: switch on, every 5 gathers — 3 of 5 picks since the last plan`, and prints
  `New picks since that rebuild: N` when there are any.
- **The `/reload` restore is untouched.** Persisted intent, rebuild at `Enable()` — the requirement
  that started this, and the spec still proves it with the switch off.
- **The notice** when the switch is OFF and picks land: one short line, once per route
  (`3 new picks since this route was built — /nt reload to include them.`), printed from the frame
  loop, never inside the gather event, never with a loot window open. With the switch on it stays
  quiet: a re-plan is coming by itself.

**The pool was a one-way ratchet, and the counters lied about it.** `hideFrom` hid the surplus and
KEPT it: 428 objects of earlier plans stayed parented to the map host, `objects held=908` for a
480-object plan, `highest=908` against `shown=480`, `hideFrom=481 hidden=0` (the surplus had already
been hidden by the previous pass, so the hide count was bookkeeping noise), and `replans=0` through a
session whose route went 33 points/208 dots → 37 points/240 dots because the field counted capacity
re-fits. Now:

- surplus objects are hidden **and released** — hidden, un-anchored, re-parented onto a hidden
  retire frame (a region cannot be destroyed on this client) and dropped from the pool — so after
  every draw the pool holds exactly `painted × 2` objects;
- `hidden=` is the DROP in painted dots (same unit as `planned`/`painted`/`missing`, on purpose),
  `hiddenObjects=` is the objects behind it, and `prevPainted=` records the plan being replaced, so
  `hidden + painted == prevPainted` is checkable;
- `replans=` counts plans that REPLACED A DIFFERENT PLAN (an exact integer fingerprint of the pixel
  geometry), not capacity re-fits — those are now `refits=`;
- `stale=` is the ratchet tripwire (`highest > 2 × painted`) — it used to print the capacity flag,
  which reads false through all of the above. `capStale=` is that flag now.

**Spec.** New `tests/route_stability_spec.lua` (A–F) drives the real files end to end: defaults
(on, tranche 5, clamped), a burst of 9 gathers inside a tranche arming nothing and the 5th producing
exactly ONE re-plan, the loot/combat/30-second holds, `/nt autorefresh <picks>`, the shrink re-plan
(`hidden` == the drop, pool == painted×2, nothing stale shown, `replans` incremented, `stale=false`)
and the `stale=true` tripwire. **42 FAILs on `5ecc88f`** — including, verbatim from that run, the live shape:
`objects=200 ... painted=8 ... hideFrom=17 hidden=184 ... replans=0`. All 40 `tests/*.lua` pass
under lua5.1. `route_auto_spec` section (3) now gathers five picks and (8) checks
the tranche; `umbrella_spec` keeps "on by default". **Not yet run in game.**

### t_d17939c1 — a followable next-waypoint arrow with the yards counting down

**The complaint.** "Visually the lines move across the minimap as i walk. I cant follow a route if
it continues to move." A world-anchored line on a player-centred minimap slides by construction;
no rendering fix can make it followable. What Zygor/RXP give the player is the NEXT point plus a
distance, so the countdown is the feedback loop.

**What shipped** (local commits `02ce8f3`, `20cb2d2`, branch `fix/tooltip-refresh`, not pushed):

- `Nav/Target.lua` — pure, no WoW calls. Forward-only chooser: the target index can hold or
  advance, never retreat; every point inside the 12yd arrival radius is stepped over; the target is
  the far endpoint of the nearest FORWARD segment (or that segment's near end when the player is
  short of it, so a route's first target is not already its second waypoint). Plus bearing, the
  screen angle, `%d yd` and compass-word helpers.
- `Nav/Source.lua` — the yard scale ladder: `HereBeDragons:GetZoneSize` when a lib is already
  loaded (RXPGuides or GatherMate2 — never a dependency), then `C_Map.GetMapWorldSize`, then
  NOTHING. With neither, no arrow and one visible message: a guessed scale would count down wrong.
  Also builds `/nt navdiag`'s facts.
- `Nav/Arrow.lua` — five dots at the bearing (arrowhead, two flanks, two shaft dots) drawn with the
  primitive this client proved it keeps (two corner anchors, `LineDraw.TextureProof`), green with a
  2px dark rim, plus the `123 yd` label with an outline. 5 Hz. Hidden with no route, out of range
  (1200yd), minimap hidden, or `showNavArrow = false`. The arrowhead's TIP marks the waypoint and
  is clamped to the ring when the point is outside the view, so the pointer never leaves the map.
  `/nt arrow [on|off]` switches it without losing the line.
- `/nt navdiag` — the Step-1 measurement, as plain numbers: `C_Map` surface, LibStub/HereBeDragons
  reachability, `HBD:GetPlayerWorldPosition()`, zone size in yards, `HBD:GetWorldVector` to the
  route's first and last points, `GetPlayerFacing()`, `rotateMinimap`, the minimap's yard radius,
  and what the chooser picked (index, yards, bearing, projected px, clamped or not).

**Why dots and not a rotated arrow texture.** `SetRotation` exists on this client (RXPGuides uses
it on the same client), but its SIGN has not been established by eye here, and a pointer that
points the wrong way is the same failure as a line that draws nothing. The dot chain's direction
comes from arithmetic the specs check (`bearing - facing`, and the projection HereBeDragons-Pins
already applies), so it cannot be mirrored. If the crisp rotated texture is wanted later, the
transform is `Nav.Target.ScreenAngle`.

**Proof.** `tests/nav_target_spec.lua` walks a 17-point loop and requires the targets 2..17 in
order, zero backwards steps, zero targets behind the travel direction; it pins the 3-4-5 angle to
`bearing - facing` and `bearing` on a north-up map. `tests/nav_arrow_spec.lua` pins the marker's
pixel position against the yards/view-radius math, the countdown and the flip on arrival, the
walking-back case, the yard-scale ladder (native → HBD → visible refusal), range/off/no-route
hiding, and the diag's numbers. Both fail on `62c26b4`; all 36 `tests/*.lua` pass at HEAD.

**Still needs one in-game run.** `/nt navdiag` on the live client to quote the numbers, then walk a
route and confirm the arrow points at the next node and counts down. The diag prints the world
vector HereBeDragons gives for the same points, so a scale mismatch shows up there rather than as
a wrong number on the minimap.

**Step-1 measurement, as far as it can be taken without the client running.** The API names are
compiled into this build (`Wow.exe`, 16001) — measured with
`strings -a Wow.exe | grep -x <name> | wc -l`, every one of these returns 1:

`GetBestMapForUnit`, `GetMapInfo`, `GetWorldPosFromMapPos`, `GetMapWorldSize`,
`GetPlayerMapPosition`, `GetMapRectOnMap`, `GetViewRadius`, `UnitPosition`, `GetPlayerFacing`,
`GetMapChildrenInfo`; namespaces `C_Map` and `C_Minimap` are both present. `CreateVector2D` is NOT
a named symbol — which only matters to HereBeDragons' own load path, not to the arrow: the native
rung calls `C_Map.GetMapWorldSize(mapID)` and never needs a vector. `WTF/…/config-cache.wtf` has no
`rotateMinimap` entry, so the north-up path (the one the specs pin exactly) is the live one, and the
minimap's yard radius is already measured on this client (`/nt mapdiag` reported `radius=233.33`).

What the strings cannot prove is the VALUE: whether `GetMapWorldSize(1413)` answers 1000x1000 or
nothing, and whether `HereBeDragons-2.0` is registered in the session. `/nt navdiag` prints both,
plus `HBD:GetWorldVector` to the route's ends for comparison.

### t_c0221fd7 — the beast tooltip: what the corpse gave and what skinning gave

**The complaint.** "we are missing the skinning tooltip. we should have some information when
hovering over beasts that says what we might get if we kill it and skin it. Same as herbing just
another step in the middle."

**What shipped** (local commit on `fix/tooltip-refresh`, not pushed).

- `Modules/NodeTrail/Data/SkinHints.lua` (new) — the data build. It READS
  `NodeTrailDB.skinning.chars[<Name-Realm>].records[*]` (the recorder's own store, format untouched),
  matches records by `creatureID` (the NPC id parsed by `R.CreatureID` from `UnitGUID`, never the
  displayed name), and aggregates per creature: `kills` = records whose death was observed,
  `skinned` = records a successful 8613 cast was pinned to, `skinWindows` = the sum of
  `skinLootOpens`, plus per-item `count` (quantity) and `seen` (how many corpses carried it).
  It never creates a bucket — hovering a beast on a character with no records leaves the saved
  variables untouched (a spec pins that).
- `UI/Tooltip.lua` — `T.BuildBeastLines()` is the gate and `T:Refresh` asks it for every hover that
  is not one of our herb nodes: a `mouseover` unit must exist, its GUID must be a `Creature-` GUID,
  the NPC id must parse, `UnitCreatureType` must be a beast, `Pr:Skinning()` must not answer "no",
  and a client call that says "not skinnable" hides the block. The ring records `kind=beast cid=…`
  and `/nt ttdiag` carries a `beast:` section (store, floor, last aggregate, the measured
  skinnability probe).
- `Data/Profession.lua` — the herb gate's three tiers now take a context (names + label + spell), so
  Skinning is answered by the SAME code as Herbalism: `Pr:Skinning()`, cached per skill. Every
  existing herbalism detail string is unchanged, which is why `profession_gate_spec` still passes.
- `UI/TooltipPanel.lua` — a row may now be `{ name = <client string> }`: display-only, never
  wrapped, never `tostring`'d, never measured (a creature name can be SECRET). Its width comes from
  the tooltip's own rect (a frame read), not from a measurement, and it is excluded from the
  `covers` verdict rather than counted as a blind row.

**How the content is ordered** (the card's order): creature name · `skinnable · skin windows
recorded: N` only when known · `corpse loot` rows · `skinned` rows · `kills seen: N · skinned: M`.
An item row is `<client item name> x<count>` and gets `| <pct>% (yours)` only when the sample
reaches `HerbData.PERSONAL_MIN` (10) — and never when the item was seen more often than that
sample (a loot-only record would otherwise print 110%). Item names come from `GetItemInfo(id)`,
then the name the loot slot reported, then our own `item <id>`; no leather/hide table is hardcoded.

**Measured on the client, not assumed.** `strings -a Wow.exe` on
`/mnt/c/Program Files (x86)/World of Warcraft/_forever_/Wow.exe` (build 16001, `textLocale enUS`):
`UnitGUID`, `UnitName`, `UnitCreatureType`, `UnitExists`, `GetItemInfo`, `issecretvalue` are each
compiled in (1 match); **`UnitIsSkinnable`, `IsUnitSkinnable`, `C_UnitInfo` are absent (0)** — so no
call on this client answers "is this creature skinnable" as a boolean, and the line comes from our
own skin windows instead. The client does carry the vanilla tooltip strings `UNIT_SKINNABLE_LEATHER`
/ `_HERB` / `_ROCK` / `_BOLTS` and `SPELL_FAILED_TARGET_UNSKINNABLE`, i.e. it can draw a "Skinnable"
line in ITS tooltip; reading that line means matching CLIENT text (the read a secret value raises
on), so it is deliberately not done. `Beast` is not an exe literal — `UnitCreatureType` answers a
localized DBC string, and `BEAST_TYPES` is enUS-only, like `Profession.NAMES`.

**Proof.** `tests/skin_tooltip_spec.lua` builds its records by calling the real recorder
(`R:OnKill` / `R:OnCorpseLoot` / `R:OnSkinCast` / `R:OnSkinLoot`), then drives the real poller over
the fake client: 12 kills / 10 skins → labelled percentages + totals; 3 kills → counts only and no
`%` anywhere; a beast with no records → `no observations here yet` and no totals line; five
non-beast creature types, an unreadable type, a `Player-` and a `Pet-` GUID → hidden; a stubbed
`UnitIsSkinnable=false` → hidden, `=true` → `skinnable`; a non-skinner → hidden with `Skinning` in
the ring; an unreadable profession → the block still shows this character's own records; a
same-name creature with no records is not given another NPC's numbers; a loot-only item that
outnumbers its sample prints a count, not 110%; a SECRET name is carried to the panel whole with
zero `#`/concat/`tostring` reads (a `newproxy` userdata whose `__len`/`__concat` count and raise);
a hover on an empty store creates no bucket; and a write-hostile `GameTooltip` proxy records zero
writes. **46 checks fail on `06984f6`**; all 42 `tests/*.lua` pass under lua5.1 here.

**Still needs one in-game run.** Hover a Clattering Scorpid (id 3125) on the skinner and quote
`/nt ttdiag`: the `beast:` lines must show `store: N corpse record(s) for <Name-Realm>`, the floor
(10), and `last hover: cid=3125 records=… kills=… skinned=… skin-windows=…`. What the specs cannot
prove on this client: that `UnitCreatureType("mouseover")` really answers `Beast` (vanilla DBC
string), that `UnitName` for a beast is SECRET here (the panel handles both), and that the panel's
width floor from the tooltip rect really covers a long secret name.

**Review round 1 fix (same card).** The panel COMPUTED the tooltip-rect width floor but never stored
it, so `TooltipPanel:Diag().rawFloor` was permanently `nil` and `/nt ttdiag` printed no raw-row figure
at all — the very instrument named above for the width claim. `TooltipPanel:Update` now assigns
`self.rawFloor` (0 when the block carries no raw row, so "no floor" and "floor 0" are the same
reported number), and the diag's coverage line quotes it:
`panel: covers its widest line=yes (...; raw rows=1 floor=180px; drawn rows report 158)`.
A probe over a SECRET creature name (real panel, real poller, real `T:Diag`) prints
`P:Diag().rawRows = 1`, `P:Diag().rawFloor = 180`, `P.width = 180` and the line above. New checks —
`skin_tooltip_spec` §8 (the reported floor is ≥ the tooltip's own width, and the ttdiag text carries
the figure), `tooltip_panel_spec` T2b (no raw row ⇒ floor 0, reported), `tooltip_refresh_spec` T9
(`raw rows=0 floor=0px` on a herb block): **4 checks, all red on `34d0510`** (2 + 1 + 1, behavioural
FAILs, no traceback) and green here. The earlier commit message's "43 checks fail on `06984f6`" was a
typo — the real count is **46**.

**2026-11-08 (second pass, `d1c2e78` on `wt/t_86583cf2`) — the diag measures the dots on
screen; the minimap stops guessing its scale.**

The first pass instrumented the DRAW (stamp, drawn anchors, crosscheck) but left two things
that could lie. Both are fixed, and both are covered by specs that fail on `d6f2a31`.

1. **A bailed redraw no longer reports the previous draw.** `MapOverlay:ReleaseVisuals(why)` now
   calls `LineDraw.MarkIdle(drawer, why)`: the drawer's `lastApplied` says `painted=0` and names the
   reason. Before, opening a map that is not the route's map hid the overlay and left
   `paintedDots` at the old value, so `/nt mapdiag` printed `painted=288 missing=0 outside=0` for a
   route that was nowhere on the screen. Three diag lines now read `no draw on this map (<why>)`
   instead of quoting the stale count.
2. **The placement check is in SCREEN space, against the rect the player can see.**
   `MapOverlay:VisibleAudit()` computes each painted dot's centre from the anchors the draw set
   plus the host's measured rect (exactly the numbers the primitive used), counts how many fall
   inside `WorldMapFrame.ScrollContainer`'s screen rect (falling back to `WorldMapFrame`), and
   prints `route dots on the visible map: N/M inside (dots bbox=…; visible=…)<verdict>`. The old
   line compared the dots with their own host, which they are parented to and therefore always
   fit inside — a check that could not fail. New line `map on screen:` prints WorldMapFrame /
   ScrollContainer / canvas / host / UIParent rects side by side, with sizes converted through
   the scale chain, so the canvas-vs-visible-rect question is one line away.
   `dot screen:` now says "pool order, not route order": after a re-plan the pool still holds the
   previous plan's objects, so "dot 1" is not route point #1 — comparing those two orders is how a
   correctly drawn route was read as being in the wrong place.
3. **The same audit is persisted**: every world-map redraw writes `NodeTrailDB.mapProbe`
   (`at`, `mapID`, `painted`/`inside`/`measured`, `bbox`, `first dot screen pos`, `visible`/`host`/
   `canvas`/`scroll`/`frame`/`ui` rects, `canvasScale`, `idle`+`why`). The client writes SavedVariables
   on `/reload`, so the placement numbers are readable off
   `WTF/Account/JERMTHE1/SavedVariables/MightiePack.lua` instead of a pasted chat line.
4. **The minimap scale is measured when HereBeDragons is there.** `MinimapPath.getHBD` only looked at
   `GatherMate2.HBD`, and GatherMate2 is not installed on this client — so every draw printed
   `radius=0.0750 [map fractions (fallback: no yard radius for this zone)]` while RXPGuides was
   shipping the same library at `_forever_/Interface/AddOns/RXPGuides/libs/HereBeDragons`. It now
   also resolves it through LibStub (a TABLE with `__call`, not a function — the first cut of the
   check got that wrong and still read "absent"). With the library present the draw uses world
   coordinates and `C_Minimap.GetViewRadius()` yards, the diag names the source and version
   (`minimap hereBeDragons: LibStub:HereBeDragons-2.0 version=…`), and the scale audit prints yd/px
   plus the radius those pixels imply. Without it, the fallback is still used and still says so.
   Also documented the sign convention: HBD world coordinates run backwards from UI map fractions
   (`x = left - width * x` in `GetWorldCoordinatesFromZone`), so player-minus-point is what restores
   "east is +x" and keeps `pointDelta`'s two branches consistent — otherwise the minimap would
   mirror the route the moment HBD loads.

**Proof.** `tests/mapdiag_visible_spec.lua`: 10 behavioural FAILs on `d6f2a31` (no `map on screen:`
line, no visible-rect measurement, no idle record, stale count reported), green at `d1c2e78`.
`tests/minimap_hbd_spec.lua`: 12 behavioural FAILs on `d6f2a31` (HBD not found, radius stays 0.075,
dots at 18.67 px instead of 6.00 px for a 20 yd offset), green here. 45/45 `tests/*.lua` pass under
lua5.1. Route generation, the dot primitive and the projection maths are unchanged.

**Still needs the client (one step).** `/reload` loads `d1c2e78`; open the world map once (that is
what triggers a redraw) and `/reload` again. `NodeTrailDB.mapProbe` then holds, for that map, the
rects and the `inside/measured` count — the numbers that say whether the route is inside the map
the player can see, and whether the host rect and the visible rect agree. `/nt mapdiag` prints the
same lines live, and `/nt mapdiag probe` labels #1/#10/#20/last plus `P` for one screenshot.

**2026-11-08 (third pass, `wt/t_86583cf2`) — review round 1 corrections: the count cannot pass with
part of the route unexamined, and the walk is replayed in the projection this build actually uses.**

1. **`route dots on the visible map:` now divides by PAINTED, not by measured.** A dot whose anchors
   cannot be read is not evidence, so it no longer leaves the denominator. The line reads
   `route dots on the visible map: <inside>/<painted> inside (measured <m> of <p> painted; …)`, and
   when `m < p` the verdict names the remainder:
   `— 36 of 72 painted dot(s) report no screen rect — not measured`. Review round 1 reproduced the
   old behaviour exactly (`36/36 inside`, verdict nil, half the route gone); §7 of
   `tests/mapdiag_visible_spec.lua` now fails on that build with 6 behavioural FAILs and passes here.
   `NodeTrailDB.mapProbe` gained `unmeasured` next to `painted`/`measured`/`inside`, so the saved
   record keeps the two counts apart.
2. **The walk is replayed in WORLD mode (the projection this build ships).** §G of
   `tests/minimap_walk_spec.lua` installs the same fake HereBeDragons `minimap_hbd_spec` uses
   (LibStub, zone 1000×800 yd, `C_Minimap.GetViewRadius()` = 233.333 yd, 0.30 px/yd) and walks the
   same four stops past the same landmark. Same invariants: the drawn anchors sit where the yards
   put them, move opposite the player, keep a constant offset from the landmark, and the
   player→segment distance collapses onto the line then recedes:
   `12.00 → 3.00 → 0.60 → 4.50` px with the dot at `12.00 → 3.00 → −0.60 → 4.50` px.
   It fails on `d6f2a31` (which projected `mode=frac radius=0.0750`, drawing 37.33 px where the
   yards say 12.00) and passes at this commit.
3. **The four-stop table in the previous pass is from the PRE-HBD build, `d6f2a31`** — navwalk mtime
   13:57, `mode=frac radius=0.0750`. It proves anchoring for that projection; the shipped build draws
   `mode=world`. The world-mode replay above is the coverage for the shipped projection, and the
   live table still has to be re-walked on the shipped build to be a live measurement of it.
4. **The screenshot pair is not obtainable from this host.** `NodeTrailDB.mapProbe` still does not
   exist on disk (SavedVariables mtime 13:57, pre-deploy), and the client is in active use while this
   runs: `Wow` pid 33436 running, `GetLastInputInfo` idle **0 s**. Opening the world map and taking
   the two screenshots therefore needs the operator, once, after a `/reload`.

**2026-11-08 (fourth pass, `wt/t_86583cf2`) — review round 3: one ruler per check.**

Both defects were space/unit errors in the *instrument*, not projection errors, plus one real
robustness defect in the minimap's world-coordinate handling.

1. **World map: the visible-map check is now in CANVAS units.** `route dots on the visible map:`
   compared the host's `GetLeft/GetTop` with `ScrollContainer`'s rect. On this client the canvas is
   the scroll frame's child, so those are different rulers (canvas top 699.4 while the map frame it
   sits in reported 1084; the two rects did not even overlap) — which is why it printed `0/319` for a
   route drawn across the map. `VisibleAudit` now takes each painted dot's centre straight from the
   anchors the draw set (canvas units, no host rect, no scale multiplication) and compares it with a
   window measured from the scroll frame's own horizontal/vertical scroll offsets, converted into
   canvas units through the scale chain (`canvasWindow`). A client that exposes neither measurement
   prints `UNMEASURED: <reason>` — never a zero that reads as "nothing is visible".
   The printed line names the window and the method:
   `route dots on the visible map: 36/72 inside (measured 72 of 72 painted; dots bbox=… canvas px;
   window=300.0,200.0 400.0x300.0 in canvas units (ScrollContainer scroll offsets; canvas=1002.0x668.0))`.
2. **World map: `host on the canvas:` is a separate assertion.** A host re-anchored or resized moves
   every dot off the ground *while the canvas-unit count still reads inside*, so the host/canvas
   relation is checked in its own space (parent chain + size): `host on the canvas: yes (parented to
   the canvas, same size)` / `NO — <why>`. This is the assert ara asked for, without reparenting the
   overlay: on this client the proven placement is `WorldMapFrame:GetCanvas()` with canvas-unit
   coordinates (`RXPGuides/map.lua:466`, `HereBeDragons-Pins-2.0.lua:350` in the same game install).
3. **Minimap: one label per space.** The crosscheck printed the world map's canvas pixel as `world=`,
   which reads as a yards position. It now prints `#n frac=(…) canvas=(…) worldYd=(…) mini=(…) state`,
   and the summary says `world-map canvas N on this map`.
4. **Minimap: `useWorld` requires ALL points to convert.** Before, one converted point was enough and
   the rest produced no delta and vanished with no line saying so (the live diag showed
   `useWorld=true` with points that had no world position). A partial set now falls back to the
   zone/fraction projection and the header says why:
   `world projection OFF: HereBeDragons converted 1 of 2 point(s); 1 have no world position, so the
   world projection would drop them`. `tests/minimap_units_spec.lua` §1 drives exactly that.
5. **Minimap: the world-mode stamp carries the player fraction again.** It read
   `frac=(absent,absent)`; the four-stop table compares "player fraction" with "the fraction the draw
   was built from" on both surfaces, so the fraction is recorded (the projection still uses yards).
6. **Minimap: "nothing drawn" names the distance that decided it.**
   `minimap verdict: none of the 36 segment(s) reach the minimap: 37 of 37 point(s) project outside
   the 95px circle; nearest point #1 is 559.1px = 1317.8 yd = 5.64x-radius (the minimap covers 233.3 yd)`.
   A player five radii off the line and a wrong projection no longer read the same.
7. **The projection maths were NOT changed** (constraint): same world/zone/fraction projection, same
   yards, same radius. What changed is which space the check counts in, and what happens when a point
   cannot be converted.

Specs: `tests/minimap_units_spec.lua` (new) — 16 behavioural FAILs on `d855247`, green here;
`tests/mapdiag_visible_spec.lua` §8 (new) — the scroll window is set to 400×300 at 300,200 and the
expected inside count is computed in the spec from the objects' own anchors; 10 behavioural FAILs on
`d855247`. 46/46 `tests/*.lua` pass under lua5.1 at `9441e46`. Deployed byte-identical to
`_forever_/Interface/AddOns/MightiePack` (sha256 in `evidence/t_86583cf2-fourth-pass.txt`); the client
needs one `/reload` before any live line describes this build.
