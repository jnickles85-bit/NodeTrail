# Changelog

All notable changes to MightiePack. The format follows Keep a Changelog, and the
project uses semantic-ish versioning: the pack version in `MightiePack.toc`
(substituted from the git tag by the packager) is the one CurseForge shows.
Touchstone still carries its own upstream module version, which may appear in
About and diagnostic lines; the Touchstone window header shows the pack version.

## [Unreleased]

### Changed
- **Touchstone re-pinned to StatForge `bb03d13`** (#128, #129, #130). It brings:
  - **One Ledger colours.** Every surface draws the same pair: the tooltip line, the bag arrow's
    glow, the bag trade-off chip and the Upgrades ledger. Upgrade is green `#22C55E` and trade-off
    is amber `#F59E0B` (the ledger used `#6fcf97` / `#e6a94c`).
  - **The + / ^ glyphs are on by default.** A character that never set `/up glyphs` now sees them.
    A character that turned them off keeps them off, and so does one that ran `/up reset` on an
    older version (that command saved "off"). `/up reset` now turns them on. No saved key is added
    or removed for this.
  - **SLOT header.** The ledger's third column is labelled SLOT (was CHANGE), and the label shows
    only when at least one row is drawn.
  - **A one-time "ready — hover your bags" line** the first time Touchstone is enabled on a
    character that has never had it on. Characters that used Touchstone before stay quiet. The one
    new saved key is `ChestAdvisorDB.readyAnnounced`; nothing is removed.
  - Arrow animation capped at 30 placements a second; GearAPI v2 (every v1 field unchanged); the
    band wording says what it measured and what it could not (A9, A11).

### Fixed
- **The Settings tab's About block stays inside the panel again.** The About text, the Commands
  line and the Tip line drew below the window's bottom edge (owner retest of 5e10486, window
  scale 1.00). When the Settings stack became a scrolled, clipped flow, every block moved onto
  the scrolled frame except About, which stayed on the frame around it: it still scrolled, but
  nothing clipped it, so at the top of the scroll its tail hung out of the panel — the symptom an
  earlier fix (card t_4ddeae90) had cured on the old fixed layout. About now lives in the scroll
  child with the rest of the stack: clipped at the top, fully on screen when you scroll down. No
  option, font or window size changed. `tests/touchstone_settings_clip_spec.lua` checks every
  Settings region against the panel's bottom and fails on the old shape. The change is in
  `tools/touchstone-patches/OptionsTab.lua.patch`, and `--verify-shipped` passes.
- **A healer's weapon trade-off is now judged by the healer model** (advisor ruling (e)+(a)). Holy
  paladins (and other healers) used to see Trade-off on a weapon that clearly heals better, because
  the weapon path sorted the stats by priority and never asked the healer model the armour path
  already uses: Polished ZweiHander of Healing (+34 Healing, +9 Int) against an enchanted, proc-ing
  Wolfsbane (+10 Int) read amber on the 1 Intellect alone. The weapon path now asks the model on
  exactly the pairs the armour path does: the stat-priority check first, the model only on its
  Trade-offs, only when the character's totals were read, and only when the evaluation is healing:
  a healer spec with the spell role, in Dungeon or Raid, or in Leveling once `/up role spell` is
  recorded. Leveling with Role clear keeps the old Trade-off and its reason gains one line, "Set
  Role to Spell (/up role spell) to judge this as a healer"; a recorded Melee role and every
  non-healer spec (Protection included) keep the old verdict byte for byte. Weapon DPS, Spell
  Damage (damage only), the proc and the enchant are left out of that healing evaluation and the
  line says so: "not counted for healing; you'd lose Wolfsbane's on-hit effect and its Weapon
  Damage +5 enchant". Spell Power heals, so it is never called not counted: a pair that moves it is
  not sent to the model and stays Trade-off with the cause printed. Likewise an enchant on either
  weapon that may change healing (healing, spell power, mana, Intellect or Spirit, or enchant text
  Touchstone cannot place) keeps the pair out of the model, Trade-off with the sizes and the cause
  ("the equipped weapon's enchant, Healing Power +30, may change healing, and enchants are never
  priced"); a melee-only enchant such as Weapon Damage +5 is still left out and disclosed. The
  Leveling hint appears only where Role Spell really would send the pair to the model. Nothing is
  priced and no stat ratio is added. When the model declines, the word stays Trade-off and the reason prints the sizes
  and the cause ("Trade-off: +34 Healing Power vs −1 Intellect. Healer model: …"). The talents
  path now carries the Context switch too. No setting, saved key or UI change.
  Changed in `tools/touchstone-patches/` (Verdict and ChestAdvisor patches);
  `tests/touchstone_healer_weapon_spec.lua` pins it.
- **The ledger's VERDICT column draws again** (Upgrades and Log). The green arrow, the amber
  trade-off square and the verdict word ("Upgrade", "Not an upgrade", …) sat in a gutter frame that
  had a width but no height, and the client paints nothing owned by a frame with no area, so the
  column was blank in game. The gutter now spans the row. Pack-only (the gutter is the ledger
  patch's; upstream draws the mark on the row), changed in `tools/touchstone-patches/`.
- **The Context switch scrolls with the rest of Settings** (audit A3). The Context heading was the
  one part of the Settings stack still pinned at the old fixed layout's position, about 60 units
  below the Role heading it belongs beside, and it stayed put while the rest of the stack scrolled,
  with its three boxes. It now sits on Role's row in the same right-hand column and moves and clips
  with the stack. `tests/touchstone_context_scroll_spec.lua` pins it and fails on the old shape.
  The change is in `tools/touchstone-patches/OptionsTab.lua.patch`, and `--verify-shipped` passes.

### Held for the next release
- **Melee may not claim equality over a line it never read** — verified and unmerged; `t_dc1decd1`
  re-derives the M11 pin first.
- **A two-sided Block tie** reads "no change" in the pack where upstream decides it on the ordinal
  tiebreak (`t_a4124aed`; fix written and held).
- Contract Y (`t_0bf5c207`) — parked, not scheduled. Superseded by the engine measurement, not by neglect.

## [0.3.13-beta] - 2026-11-18

**The retest fixes, and nothing else.** Everything here came from the owner's own sitting with
0.3.12-beta, and nothing that was working has moved: the model's wire, the verdicts it produces and
the pairs it judges are exactly as 0.3.12 left them.

### A declined pair now says why

The advisor asks a throughput model about trade-offs, and when it turns one down it used to say
nothing at all — which reads exactly like the model never being called. It was called; its reason
was simply dropped at the boundary. Now the refusal reaches the tooltip as one short clause:

```
(throughput not judged: no mana reading yet — it is read out of combat)
(throughput not judged: the client did not give your mana numbers)
(throughput not judged: no spell reading for this character)
(throughput not judged: no role chosen — /upgrade role <melee|spell>)
(throughput moves nothing either way)
```

**Two of those read differently on purpose.** A reading that has not happened *yet* — the ordinary
state on a first hover after logging in — says so, and tells you when it fills in. The permanent
cases say the client refused. Naming them the same way would have made the commonest one look like
a fault.

The clause appears **only** on pairs the model was actually asked about and declined. A clear
upgrade, a clear downgrade and a refusal never reach the gate, and those rows are silent — no
apology on every hover. The verdict word never changes because of this: it is a disclosure, not a
judgement.

The clause map and the renderer that calls it are asserted **in the shipped bytes** by
`tests/touchstone_decline_clause_spec.lua`, which also drives a real declined scan end to end.
`--verify-shipped` alone cannot see this: it compares the vendored copy to the pin and never asks
whether the patch's overlay carried the map.

### One `v`, on both surfaces

The window header and the Options footer now read the same rule. The footer appended its own `" v"`
to whatever version it was given, so a source checkout read `MightiePack vdev` under a header that
read `dev` — one convention, two copies, and the footer's copy was the wrong one.

The label rule lives once, as `pkg.VersionLabel()` in `MightiePack/Core.lua`, and both surfaces call
it: a version gets one `v`, `dev` gets none, and no version renders a bare `MightiePack` with a
stray separator. `tests/mightiepack_version_spec.lua` asserts the two surfaces **agree** character
for character on every TOC shape — not merely that neither contains `vv`, which the dev case never
did.

### The wire, unchanged

No gate, weight, band or profile moved. What the model judges, and what it says when it does, is
what 0.3.12 shipped; the difference is that a decline is now legible.

## [0.3.12-beta] - 2026-11-18

**The build that switches the model on — and says plainly what 0.3.10 and 0.3.11 got wrong.**

### The correction

0.3.10-beta and 0.3.11-beta shipped with Step 3's arbitration **unwired**. The verdicts you saw in
those builds came from the ordinal layer alone: the model was in the addon, fully written and fully
tested, and nothing called it. A tooltip headline that read **Sidegrade** in either of those builds
was a **renderer default, not the model's answer** — the renderer started from that word and only
overwrote it for two of the states it knew.

The seam was blocked twice over: the flag that admits the model was off, and the pack's own patch —
the layer that carries this addon's customisations into the vendored copy — replaced the region
holding the call and did not carry it back. The patch applied cleanly, the digests matched, and the
addon had no caller. That is the shape that looks wired and answers nothing.

### What this build changes

- **The model is wired, and the gate is deliberately narrow.** It is consulted only on a pair the
  weighted engine has already judged a **trade-off**, only when the client has supplied the totals,
  and only while the flag is on. A clear upgrade, a clear downgrade, and a refusal are untouchable by
  construction — the call never fires for them.
- **Measured blast radius, over 15,840 cells** (32 item pairs × 33 spec profiles × 5 totals snapshots
  × 3 contexts, each cell judged twice, flag off and flag on):

  | | |
  |---|---|
  | word changes | **266**, every one of them **Trade-off → Upgrade** |
  | model answered "inside the band" | **19**, rendered Sidegrade |
  | clear answers moved | **0** |
  | refusals moved | **0** |
  | direction of any move | upward only; nothing was downgraded |

  The one pair behind those 266 rows is a Holy priest chest pair with +22 Healing where the model
  says the extra healing per cast outruns the smaller mana pool. It reaches the same answer in every
  context and every totals set — which is what "the model's home ground" means.

### Fixed
- The window's header read `vv0.3.12-beta` on the owner's first retest of it. The title band shows the TOC's `## Version:` line, and the packager substitutes the git TAG there — `v0.3.12-beta`, leading v included — while `Window.lua` built the label as `"v" .. ver` and added a second one (every tagged build since 0.3.10 carried it; nobody had read that corner of the header). The label now takes the version as it arrives and prefixes a v only when the string does not already carry one: a tagged release reads `v0.3.12-beta`, and a TOC whose Version line has no v also reads `v0.3.12-beta`, so the shape of the TOC cannot decide what the header says. A source checkout renders `dev` rather than the machinery — the modern metadata path already answers `dev` for the unsubstituted token, and the legacy path's raw `@project-version@` maps to the same word, so neither prints `vdev` or `v@project-version@`. Nothing else in the title band moved: the name text is still exactly `MightiePack`, and the label keeps its font token, anchor and colour. `tests/window_header_version_spec.lua` drives those strings through the real header — the whole TOC loaded into a fresh package, the pack's own `PackVersion` → `GetAddOnMeta` → `C_AddOns`/legacy chain — and asserts the header never contains `vv` or `v@`; it is RED at `98d8ce0`, naming the header, and carries a teeth leg that runs the detector on the pre-fix expression.
- The pack's Options **footer** read `MightiePack vv0.3.12-beta` on the same build. Same cause, different consumer: the TOC's `## Version:` line arrives from the git tag with its `v`, and `Options.lua`'s footer built `" v" .. ver` on top of it. The header's fix was one site, not the class — a third consumer would have doubled it too — so the prefix now comes off **once, in `pkg.PackVersion()`** (`MightiePack/Core.lua`), the single value both consumers read; each caller adds its own convention (the header `v`, the footer ` v`). This also settles the source-checkout word: the unsubstituted `@project-version@` answers `dev` there for both metadata providers, so neither surface can print `v@project-version@`. A tagged build reads `v0.3.12-beta` in the header and `MightiePack v0.3.12-beta` in the footer; a TOC without a v reads the same; a dev build reads `dev` and `MightiePack vdev`; with no version at all the footer is exactly `MightiePack · …`, no stray separator. `tests/mightiepack_version_spec.lua` drives seven TOC shapes through both surfaces off the drawn labels and asserts neither ever contains `vv` or `v@` — the check that would have caught the footer, which a header-only assertion did not; it is RED with the un-normalised `PackVersion()` restored, naming the footer. `tests/touchstone_version_label_spec.lua` measures the three Touchstone surfaces (subtitle, About, diagnostics) against `SF.VERSION` — `0.8.3`, no leading v — which is the value they concatenate, so their `"v" ..` is correct and was never the defect.

- **The shipped addon calls the arbitration — the flag and the call ship in one cut** (`t_58762500`).
  The re-pin to StatForge `ff64bc5` (PR #123) brought `Arbitration.ENABLED = true` by itself:
  `Arbitration.lua` is a pristine file the pack copies byte for byte. The CALL lives in `Verdict.lua`,
  which this pack replaces whole, and that replacement region had dropped it — so the vendored file had
  the definition of `Verdict.arbitrate` and no caller. Flag on with the call absent is the worst shape:
  it looks wired, reads exactly like 0.3.11, and every check stays green. The re-cut patch carries the
  call, gated exactly as upstream gates it, and `tests/touchstone_shipped_seam_spec.lua` drives a real
  scan through the vendored tree to prove a row comes out arbitrated (token, state and the model's own
  sentence), with the tooltip and the window naming that row the same way.
- **The three Context checkboxes in Pack Settings sit in a row instead of on top of each other**
  (`t_ce1c4a4f`). The row was built by a loop that still passed the old fixed position to a helper
  that no longer places anything — Lua discarded the position, nothing anchored the boxes, and
  Leveling, Dungeon and Raid were created at the same point on the panel, each label drawn over the
  last. The first box now hangs under the Context heading and the other two beside it, 110 units
  apart, measured in the pack's own harness.

## [0.3.11-beta] - 2026-11-18

A patch release carrying one fix. The release before it rebuilt the pipeline and turned on
totals-aware judging; this one makes the record agree with the two surfaces that already did.

### Fixed
- **The disagreement log names an arbitrated pair the way the other two surfaces do**
  (`t_baea7949`). The Log tab and `/up log` printed the token's word, so a pair the
  window and the tooltip call **Sidegrade** read "Trade-off" in the log — the same
  defect `t_c8970547` fixed in the window, moved to the record. A log entry now carries
  the arbitration's own state (`arbState`), and both readers of a stored entry ask the
  advisor's `entryWord`, which reads it through `wordFor`. An entry written before the
  field existed has no key and renders the token's word, exactly as recorded; no
  migration, no re-derivation.

## [0.3.10-beta] - 2026-11-18

The advisor runs on a rebuilt pipeline and judges a live character. Two things change for a player:
a pair can now read **Sidegrade**, and the number behind that word moves as *your own sheet* moves.

### Added
- **Step 3 — totals-aware judging.** A pair the ordinal engine calls a trade-off is now arbitrated
  against the character's live totals at hover time: the candidate is substituted, the throughput is
  modelled from the spell the character actually casts, and the answer is stated with the context it
  was judged in, the term that drove it, and a confidence when a constant is still unmeasured. The new
  word is **Sidegrade** — inside the measured band, so "pick the one you like" is the honest answer.
- The survival line speaks on a Sidegrade only (§4.4): losing 90 health is worth saying when the
  throughput cannot separate the two.
- `docs/touchstone-divergences.md`: where the pack's behaviour differs from the pinned upstream on
  purpose, with both sides measured.

### Changed
- **The vendored payload carries Step 3's two pure modules** — `ChestAdvisor/StatOrders.lua` and
  `ChestAdvisor/Arbitration.lua`, both the pin's own blobs, listed after `Verdict.lua` and before
  `ChestAdvisor.lua` so `Arbitration` is in `_G` when the advisor's call-time lookups ask for it.
  `Calibration.lua` stays out on purpose: it is a dev surface and no verdict path reads it. Fourteen
  vendored files became sixteen. (Card `t_13c807af`.)
- **The engine under the pack's patch moved to StatForge `eebfba4`** — Contract Y (upstream no longer
  lets a weight decide a Step 1 verdict) and the equal-dps gate fix arrived with it. The pack's own
  weighted/order-profile layer still decides; that is the divergence recorded below, not an accident.

### Fixed
- **The window names a pair the way the tooltip does.** The Upgrades ledger row read the stored verdict
  TOKEN (`TOOLTIP_UI.word`), so a pair the arbitration answered SIDEGRADE printed *Trade-off* in the
  window while the item tooltip headlined *Sidegrade*. The row now asks the ROW (`TOOLTIP_UI.wordFor`,
  the one arbitration-aware word the tooltip and both mark hovers already read). UPGRADE and
  NOT_UPGRADE read exactly as before. (Card `t_c8970547`.)

### Built differently — no player-visible change, and the reason to trust the next fix
- **Touchstone is vendored by a copy-and-patch tool, not an anchored text editor.** 3,023 lines became
  788: pinned blob → optional patch → output. Of sixteen files, **eight are the pin's blobs byte for
  byte** and eight carry one patch, each naming its reason in its own header.
- `--verify-shipped` now has **two lanes that fail alone and by name**: `COPY` names a file whose copy
  is not the pin's blob; `PATCH` names a patch that no longer applies to the pin. Both run in CI on
  every pull request. The point was never the hash check — it was that an upstream move fails **loudly**
  instead of silently.

### Divergence, stated rather than hidden
- At **equal weapon damage per second**, the pack lets the spec's weighted profile decide and names the
  tier that decided it; upstream refuses (`UNKNOWN — cannot classify`). Permanent by the owner's
  decision of 2026-11-17, recorded with both sides measured in `docs/touchstone-divergences.md`.

### Known limitation
- The toast seam is **observation-only**: the pack keeps its own toast block and its `/up toastdebug`
  and `/up testtoast` commands, because the upstream hook cannot carry them.

### Not in this release
- Melee, the two-sided Block tie and Contract Y — named under `[Unreleased]`, unchanged.

## [0.3.9-beta] - 2026-11-16

One re-vendor of settled StatForge main (`740f7d5` → `4183aee`), plus the one fix the owner's live test
found before the tag. Everything below was measured on the pack's own tree before he tested it in game.
- **Bag arrows, quest-reward marks and `GearAPI`** — the three surfaces lit by the verdict the reader already produces, with no new scoring underneath. (Slice 1, PR #98.)
- **An enchant is never a blocker and never priced** — it leaves the stat list like chrome and is disclosed like a proc, on the side that carries it. (Card `t_c65cc350`.)
- **Weapon fail-closed is not defeated by a `Sell Price:` line** placed before an unreadable one. (Card `t_195a0e07`.)
- **Rogue weapons** — a dagger-locked spec is not judged against a sword on damage per second alone, and the off-hand is scored rather than refused. (Card `t_1677cd39`.)
- **Tank coverage** — Hit priced at zero makes `+1 Hit` read equal to `+20 Block`, and the same Block decides one pair and not another. (Card `t_ea260b42`.)
- **An item the character cannot wear is a definite no, not a cannot-judge** — the requirement, with no gain. (Card `t_8d3af71d`.)
- **A trade-off tooltip no longer swallows what it could not price** — the reader's `(judged, with …)` disclosure now rides the pack's own "decided by …" headline as well as the plain-reason one, and names the side that carries the enchant and the proc. One hover direction printed the disclosure and the other did not. Touchstone `740f7d5` → `4183aee` (PR #106 upstream). (Card `t_77debc1f`.)

## [0.3.8-beta] - 2026-11-15

The reader carries the fixes; the pack changes nothing but its pin. Touchstone `30f3d32` → `ec947b3`
(PRs #95, #96 and #97 upstream).

### Changed
- **The verdict line is drawn with the item's own lines**, immediately under the item's stats and above every third-party block, instead of below them. The answer is the headline. (Card `t_92e703ac`, PR #95.)

### Fixed
- **A refusal now says which item it is about.** All six `cannot classify:` gates name the side — `(on the hovered item)` / `(on the equipped item)` — because a player reading `cannot classify: Enchanted: Weapon Damage +5` could not tell which weapon carried the line. The refusal was about the worn weapon and said nothing of the kind. (Card `t_fc11dd1c`, PR #96.)
- **A refusal no longer carries a judged clause.** An `UNKNOWN` verdict used to inherit `(judged, with an unpriced on-hit effect)` from the *other* item's proc line; the clause now rides a judged verdict only, and judged reasons are byte-identical to before.
- **Weapon reading** (arrives with the pin). A wand's school-named `12 - 22 Arcane Damage` line is recognised as weapon chrome, so the printed damage per second is compared instead of the pair being refused. A weapon's `Chance on hit: …` line is treated as an unpriced effect, named in the disclosure beside the reason, instead of blocking the comparison. `Equip: Increases healing done by up to 34 and damage done by up to 11` is priced as healing. The Lesser Magic Wand over the Novice's Practice Wand now reads **UPGRADE** — 11.30 vs 4.00 damage per second, +1 Spell Power.
- **CI**: the changed-verdicts sweep pins a named base revision (`96985c3`) instead of resolving `origin/main`, and refuses a base equal to HEAD. On `main` the old form compared the tree with itself, saw no difference, and reported its own allowances as unpinned — a gate that was green only where it could not matter.

### Known issues
- **An `Enchanted:` line still refuses the pair**, naming the side. An enchant is never a classification blocker and never priced — it is disclosed like a proc, on the side that carries it — from the next release. (Owner ruling; card `t_c65cc350`.)
- **`Sell Price:` placed before an unreadable line can turn a refusal into a judgement** on the no-API fallback. (Card `t_195a0e07`, fix in review.)
- **Shapes not covered above can still read `UNKNOWN — cannot classify`** — failing closed is deliberate.
- **The bag arrows, quest-reward marks and `GearAPI` are not in this build**, nor is the melee re-derivation; both are the next release.

## [0.3.7-beta] - 2026-11-14

### Known issues
Failing closed is deliberate: these verdicts read **UNKNOWN — cannot classify** rather than guessing. The weapon-reading pass is in progress (`t_d5c915f2`).

- **School-named damage lines.** A wand's `12 - 22 Arcane Damage` is not recognised as weapon chrome (the stripper expects the digits immediately before `damage`), so the whole pair is suppressed. Fire, Frost, Shadow, Nature and Holy wands fail the same way.
- **Proc lines on a weapon.** A `Chance on hit: …` line survives the stripper by design — a line carrying an effect is not “nothing but arithmetic” — and suppresses the weapon, so a Fishing Pole with a `dealing 39 to 59 Holystorm damage` proc cannot be judged.
- **Healing / spell-power Equip lines.** `Increases healing done by up to 34 and damage done by up to 11 for all magical spells and effects` carries two real stats in one sentence and is not yet attributed, so an “of Healing” weapon reads UNKNOWN instead of being priced.

### Changed (release note)
- **The current tab's underline belongs to the pack, not to the module.** The token read `base = "accent"`, and `accent` resolves against the vendored Touchstone body's brand — so the window inherited the module's teal (#66fcf1) with no hex literal in any pack file, which is why the raw-literal scan in `theme_tokens_spec` reported zero offenders while the underline stayed teal in game. It is now `base = "text"` (#eef1f5), the approved render's own colour, and pinned: the spec requires the underline to equal the pack's text token AND to differ from the brand accent, and fails with two named failures if the old value returns.


### Fixed
- **Hosted, the Touchstone body draws NO chrome of its own** (card t_07f778ca, review 2: the owner's live retest of 670c1ef still showed the old panel's bordered box, its second title bar with a close button, and the module's teal).
  - **The fix is a mode in the vendored UI, not a post-hoc strip.** `tools/touchstone-patches/UI.lua.patch` adds `SF.SetHostedChrome(true)`: called by the pack BEFORE the body is created (so the title bar and its close button are never built) and again on the live frame (so a body a `/ts` session already built loses them). The chrome parts are held by REFERENCE — `SF.Chrome()` — and are never recognised by a child's measured height, its order or its name; matching the title bar by its 40px height is exactly the guess that failed on the client while the harness agreed with it.
  - **One flat plane.** Hosted, the body and its content frame paint no border and no fill (zero-inset `WHITE8X8` fills, alpha 0). The inner strip (Upgrades / Log / Settings) is KEPT as navigation and restyled: flat zero-inset plates, the active tab on the ledger's `raised` with its label in `text`, the rest in `muted` — no vendored teal highlight, no bordered plate. Buttons created under the body are flat plates too, and buttons built before hosting are repainted when the body is adopted.
  - **The palette follows the host.** `SF.UI_Accent` / `SF.UI_SetAccent` / `SF.UI_AccentText` resolve through `MightiePackTheme` when hosted and return the body's own brand standalone, so the Settings headings (`Options`, `What Touchstone shows`, `Role`) and the About block's accent COLOUR CODE stop re-painting `#66fcf1` inside the window. Repaint callbacks registered with `SF.OnAccentRepaint` fix text built before adoption.
  - **Pinned on the live path.** `tests/window_hosted_body_spec.lua` opens the window through `W.Open("touchstone")` and asserts, over the whole subtree under the body: no shown frame paints a backdrop edge, the content frame (by reference, `SF.ContentFrame()`) has no edge and a transparent fill, the chrome (`SF.Chrome()`) is not created in hosted mode and not shown when it was, no visible FontString carries the vendored accent by colour VALUE or by colour CODE, the inner strip still offers and switches all three tabs, and the Settings headings paint in the ledger's reading colour — each leg with a negative leg that makes the same checker name a re-introduced edge, teal string, title bar or bordered content frame. `tests/window_hosted_adoption_spec.lua` is the other path: `/ts` builds the standalone window first (the pre-state is asserted, so "gone afterwards" is not vacuous), then the pack adopts it and the same audits must be clean.
  - **Not changed:** Part A's fills, the hosted backdrop claim and the options panel's born-hidden state, the summary strip and the ledger themselves. The first-use splash is still created on a fresh install and still covers the body at 0.78 — recorded by `tests/window_touchstone_shade_spec.lua`, not changed here.

### Changed
- **Upgrades and Log are one LEDGER, and the window's fills reach their frames** (card t_07f778ca: the owner picked V1 · Ledger, with V4's summary line as the strip under the tab bar).
  - **The verdict gutter.** A row is now three columns on a 1px rule: a verdict gutter (the token's 88 units) carrying the marker glyph ABOVE the verdict word, both in the verdict's colour; the item name with the reason on its own line BENEATH it, in the ledger's `muted`; and the change column right-aligned in 110 units at `dim`. The information design is the card's: the name is the anchor, the verdict carries the colour and the weight, the reason is secondary but readable — never dimmed to near-invisible, and never beside the name. Rows keep the variable-height model of t_4e5ad8a4: `rowMin` is a floor and a wrapped reason grows the row. Above the rows is the column-label line (`VERDICT` / `ITEM AND REASON` / `CHANGE`) and the section head (`5 judged · 2 worth taking`), both counted from the list on every render.
  - **The palette is the pack's own.** `MightiePack/Theme.lua` publishes `T.ledgerPalette` with the approved values (`#14161a`, `#191c22`, `#1b1f26`, `#20242c`, white at 7.5% and 12% for the rules, `#eef1f5`, `#a8b2c0`, `#7c8695`, `#6fcf97`, `#e6a94c`, `#8b95a5`) and one accessor, `T.R("ledger…")`, so every primitive reaches them the same way. The vendored tabs read them through `MightiePackTheme`; the body's own widgets keep `StatForge.Colors` (`T.Brand()` is unchanged). The item list no longer takes `rowPad`/`icon` — the drawing pads top and bottom by token (11/12) and has no icon column — and its name is painted in the ledger's text colour, so the verdict is the only coloured word in a row.
  - **The summary strip.** Under the tab strip, above the tab's content: `2 of 5 are worth taking` with the count in the upgrade colour, `1 trade-off · 2 refused` on the right, and a 3px meter segmented in the three verdict colours by proportion. It recomputes from `ChestAdvisor.getVerdicts()` on every activation and every vendored refresh, survives an empty list (`0 of 0`, empty meter, no divide-by-zero) and counts the advisor's real shape — a table KEYED BY ITEM LINK, walked with `pairs()`; an `ipairs()` draft of this strip read zero over a full list, and `tests/window_summary_strip_spec.lua` now pins the keyed shape with a leg of its own.
  - **What the client cannot express, said plainly.** FontStrings have no letter-spacing (uppercase 9.5px labels are the substitute), no text shadow and no corner radius; `SetFont(path, size, flags)` is the whole font surface, so "semibold" is not selectable and the weight comes from the verdict's colour and the name's size. The drawing is flat and ruled precisely so it needs none of those. The rarity colour is no longer painted on item names — the card's rule is that the verdict carries the colour — but the rarity is still recorded on the row.
  - **Pinned by spec.** `tests/window_ledger_spec.lua` measures the real rows (gutter width, shared verdict colour on glyph and word, reason below the name in its own column at the muted token, change column right-aligned at its token width, row height ≥ content height, the palette's exact values) and builds a row the OLD way — reason inline, fixed pitch, dim reason — requiring the same checker to name it. `tools/ledger_geometry_dump.lua` prints the resolved geometry and the tokens; its output is filed at `evidence/t_07f778ca-geometry.txt`.
- **The window is Touchstone's house now** (card t_2d2c37b0: the reshape and design pass). One frame, one identity, two tabs: **Touchstone** (the product) and **Pack Settings**. Herbs and Skinning are gone, not hidden — there is no placeholder, no "coming soon" panel, no link; the frame simply has two tabs.
  - **One theme file.** `MightiePack/Theme.lua` is the only place the pack states a design value: colour, font objects, the 8px spacing grid, band/row/inset sizes, the two textures it may draw with, backdrop insets, and the item list's own metrics. The palette it publishes is the vendored body's own table (`StatForge.Colors`) looked up live — not a matching copy — so the chrome and the Touchstone content cannot drift apart. Pack-only colours (window fill, band, hairline, tab plates, the status dot's five states) are written as DERIVATIONS of a brand colour plus our alpha, so tuning the brand moves the frame with it. `tests/theme_tokens_spec.lua` fails if a colour, inline RGB triple or texture path reappears in a window file; it also fails if the fallback palette ever disagrees with the body's.
  - **The widget kit moved into that file.** `Window/Common.lua` (the Herbs/Skinning two-column browser by then, dead after the extraction) is deleted; `Theme.lua` carries the three primitives the window is built from (`NewFrame`, `Label`/`Text`, `Panel`/`Rule`/`Swatch`). One kit, reachable by the window and by Pack Settings before either loads.
  - **Modern hierarchy.** A title band across the top (the pack's name, its version dim beside it, the status line, the close button — one plane, one hairline under it), a tab strip of text tabs whose current tab carries a rule and a plate, and content inset one token from the frame on every side. Every offset in `Window.lua` and `Options.lua` comes from the theme; a value that is not the theme's is a second palette.
  - **Progress signalling.** The band carries a dot and a sentence read from real state: `Touchstone did not load` (danger), `Touchstone off — see Pack Settings` (dim), `Scan waits for combat to end` (warning — the advisor's only in-flight signal is its combat deferral), `No verdicts yet — open your bags` (muted), `N items scored · no change` (calm accent), `N upgrades · M trade-offs · K items scored` (success). The line is repainted on every open, every tab switch and every vendored refresh, so it cannot go stale while the window is up. It never claims a scan is running when nothing is.
  - **Pack Settings rebuilt.** The panel is now: a one-line subtitle, a MODULES card (one row per module, driven from `pkg.modules` rather than a hard-coded list, each row stating `on`/`off` in words), Touchstone's "Gear for" as an indented sub-option on its own row (present only while Touchstone is on), a FEEDBACK section with the same two popups as before, and a footer naming the version, the interface and `/mp status`. The dead NodeTrail rows that the extraction left unreachable are deleted with their helpers (`ntModule`, `skinningOn`, `autoRefreshOn`, `skinRouteOn`, `skinRouteNote`, `applySkinR*`, `ntRecipes`, `syncRecipesBlock`, the last-widget flow helpers) — `tests/pack_settings_spec.lua` fails if any of them, or any read of `NodeTrailDB`, comes back.
  - **The item list's spacing is the window's spacing.** `UpgradesTab.lua` (vendored, through `tools/touchstone-patches/`) now takes `rowMin`, `rowPad`, `icon`, `mark`, `inset` and `nameGap` from `T.list`, with its own literals kept only as the standalone-load fallback. The row model itself is unchanged from t_4e5ad8a4: the height is MEASURED from the wrapped reason and the row grows, which is the decision the backlog note asked for (variable height, not a clamped reason — the reason is the product).
  - **Retired slash aliases, listed.** `/nt` and `/nodetrail` left with NodeTrail and are not registered here; `/mp skindiag` (a subcommand for the Skinning tab's diagnostics) is retired with a sentence saying where it went instead of the generic usage text. `pkg.SlashAliases` names every live alias and the tab it opens, `pkg.RetiredSlashAliases` names every retirement and why; `tests/slash_retirement_spec.lua` drives all three alias families and fails if either list disagrees with what the pack registers.
  - **Patterns, not copies.** MasterCraft was read as a design reference only — one consistent dark language, clean navigation, disciplined spacing, progress signalling. No art, icon, string, guide content, palette value or data was taken from it. The palette is Touchstone's own brand (cyan on near-black), which the vendored body already shipped; everything else in this pass was authored here.
  - **Evidence.** `tools/geometry_dump.lua` prints the resolved chrome and content geometry for each tab and the invariants (band/strip heights, content insets, card height on the grid, no overlapping rows) inside the harness client; its output is filed at `evidence/t_2d2c37b0-geometry.txt`. It is harness evidence, labelled as such — a real in-game capture is the owner's, and is not faked anywhere in this repo.
- **NodeTrail is a separate addon again** (card t_75309c97). The pack no longer ships NodeTrail's module (`Modules/NodeTrail/**`), its skinning probe (`Modules/Skinning/**`), the Herbs and Skinning tab bodies, its `/nt` command, or its `/mp skindiag` diagnostics. The module list is Touchstone alone, and `/mp help`, `/mp status` and the options panel say where NodeTrail went instead of answering for it.
- **The pack keeps declaring `NodeTrailDB`**, and nothing else. Saved variables are stored by the game in one file per addon, so a history recorded while NodeTrail lived here sits in `MightiePack.lua`. That declaration is what makes the game load it, and it is what lets the NodeTrail addon take the history over on the first login with both installed — after which NodeTrail owns `NodeTrail.lua`. The pack reads and writes no key of the store (`tests/no_nodetrail_keys_spec.lua` pins that; the declaration is dropped in a later release, once nobody is migrating). A saved `MightiePackDB.modules.NodeTrail` key is left exactly as it is.
- The unified window is back to the pack's own two tabs — **Touchstone** and **Pack Settings** — and a bare `/mp` still opens Pack Settings. Everything the frame learned about strata, fill ordering, drag and input is unchanged.
- `tests/` follows the split: NodeTrail's 54 specs moved to that addon (with its code), the 26 that remain are the pack's. `options_spec` went with the recipe block it tested (the options panel has no NodeTrail rows any more); `umbrella_spec` now pins the post-extraction shape (no NodeTrail module, no NodeTrail file, `NodeTrailDB` untouched), and `slash_spec` pins `/mp` alone. Two tree-walking specs (`touchstone_assets_spec`, and the same helper elsewhere) learned to walk on a Windows checkout, where `find` is not GNU find.


### Added
- `tests/support/wowclient.lua`: a measurable client model, for the class of defect where a control is present, wired and correct on paper and still does not respond. It computes a frame's rect from its anchors, so `GetLeft`/`GetRight`/`GetTop`/`GetBottom` answer real numbers; `EnableMouse`/`IsMouseEnabled` mean something; a frame is BORN shown and `OnShow`/`OnHide` fire only on a false→true / true→false transition of its own flag; and a hit test returns the topmost visible mouse-enabled frame under a point using the client's ordering (strata, then frame level, then creation order) — which is what `GetMouseFocus()` answers in game. Two specs use it (`window_tab_clicks_spec`, `window_settings_build_spec`).
- `tests/window_touchstone_shade_spec.lua` pins the one question a uniformly dimmed embedded panel has to answer first: can anything the pack creates draw over the hosted Touchstone body and tint it? A "shader" is a visible frame that covers at least half of the body, draws above every frame the panel owns, and is not fully transparent; the spec installs a deliberate 0.78 cover to prove the detector names an offender instead of passing because it found nothing. With the owner's saved state (`StatForgeDB.firstUse == false`) nothing shades the body and the splash cover is not even created — the first-use splash needs `firstUse ~= false`, so it is not what dims his tab. On a fresh install (`firstUse == nil`) the same spec shows the vendored show path DOES leave that 0.78 cover over the hosted body, because the splash was written for a standalone window; that behaviour is recorded, not changed. The spec also records that the full-brightness Pack Settings body is reparented in at a level no higher than Touchstone's, so "the moved frame kept its frame level" cannot be what dims the tab.
- ONE movable MightiePack window, 960x640 on every tab, with four tabs: **Herbs**, **Skinning**, **Touchstone** and **Pack Settings**. It replaces the separate options panel and Touchstone window; the panel and the vendored window's content are moved into it in whole, so there is one outer frame, one title bar and one close button. The herb hover panel is untouched and remains the in-the-moment surface - the Herbs tab is the browse/history surface, two columns (herbs on the left, the selected herb's researched drop table and your own gather count on the right, built from `Tooltip.BuildLines` and rendered through `TooltipPanel`'s own row helper). The Skinning tab is a new UI over data the probe already records: a beast list from the per-creature totals, the beast tooltip's own yield rows, and the accounting line whose lost-kill / unattributed-window / cast-without-window counts are the unattributed casts, with the existing compact dump behind a **Copy diagnostic** button that calls the same `pkg.ShowSkinDiagCopy` as `/mp skindiag copy`. `/mp`, `/mpack`, `/mightiepack` open the window on Pack Settings; a bare `/nt` or `/nodetrail` opens it on Herbs (`/nt help` and every argument form are unchanged); `/up`, `/upgrade`, `/chestadvice`, `/ts`, `/touchstone`, `/sf` and `/statforge` all open it on Touchstone through the module's own `SF.ShowMain`, so no alias is re-registered or lost. The window's position is a NEW `MightiePackDB.windowPos` key written only on a drag stop, defaulting to a centred window when absent; no existing key is read, moved or rewritten.
- Skinning farming circles survive ring turnover: unskinned kills are evicted from the 100-corpse ring first, and a skinned record with a map position is folded into a durable per-map hotspot grid (2% map-width cells, the same cell size and `{n, nodes, last}` shape as the herb-history grid, plus stored positions for the circle) before it leaves the ring. Guid idempotency lives in `cell.seen` (one entry per counted fold, not trimmed by the 32-point sample cap), so a re-fold of a guid that missed the `pts` cap cannot increment `n`; only the position samples are capped, and the circle reads at most those 32 points per cell. A fold is committed before the record is removed from the ring, so a crash mid-eviction can retry without losing the position. A skinned record evicted with no map position cannot be folded and is counted per map in `unpositionedEvicted`. The circle is built from that store plus the ring, so `MIN_SKINS` counts both. A one-time migration folds the current ring's skinned positions into the store and never discards data. A load backfills `cell.seen` from existing `pts` even when `hotspotsSeeded` is already set, so a save written before `seen` existed cannot be double-counted. `seen` is stamped after `n` is incremented. `cell.seen` and `unpositionedEvictedGuids` grow without a bound, at about 38 bytes per unique skinned corpse.

### Changed
- `tests/support/wowclient.lua` freezes a frame's level at birth (parent level + 1), as the client does, instead of re-deriving it from the frame's current parent. Re-deriving silently repaired every reparent — the class of defect where a body moved into a window keeps the level it was born with. A NAMED frame also becomes a global, as it does in the client, so the model can see a module that reaches its own frame through `_G["StatForgeMainFrame"]`.
- Herb gathering history is now capped per map without wiping a player's totals. `NodeTrailDB.herbs.maps` still stores raw picks (position, time, items) in the same shape, but only the newest 2,000 per map are kept — the bound the audit recommended, and well above the 40 stops a density route already uses. Lifetime pick counts (`total` and per-map) and the personal drop-rate stats the tooltip shows are stored in aggregates and are never evicted. When a raw pick is trimmed it is folded into a compact, never-evicted per-map hotspot grid (`herbs.hotspots[mapID][cell] = {n, nodes, last}`, 2% map-width cells, bounded to 50×50 cells and 32 node keys per cell) so a later "Find a resource" feature can query `NT.Hotspots(mapID, nodeFilter)`. Density routes still see only the newest 2,000 raw picks; they do not yet read the hotspot cells. An existing schema 1 save is migrated in place once: aggregates are computed from every raw record still in the file, trimmed picks seed the hotspot grid, a per-map folded marker (`aggT` / `hsT` / `n`) is written so a downgrade that re-attaches raw picks cannot double-count or drop history on the next upgrade, the schema marker is stamped, and only then are oversized lists replaced. A crash before the stamp retries from the intact raw lists; a second load does not re-seed from the trimmed ones. A newer numeric schema is never downgraded. A non-numeric schema is treated as unknown and left alone.
- Touchstone order-only verdicts are more cautious: an item is an Upgrade only when it is equal or better on every ranked Wowhead stat and better on at least one. A gain on a higher-ranked stat with a loss on a later ranked stat is now a Trade-off (for example Trophy Belt +5 Intellect vs Stormbringer Belt +5 Strength / +2 Stamina). A loss on the first differing ranked stat is still a Downgrade. Unranked stats such as Spirit, or Armor on non-tank specs, still do not decide. Ranked equality uses the named WEIGHT_EPSILON floor so float noise cannot mint an Upgrade. The tooltip keeps the deciding tier and names both sides of a Trade-off.
- Herb and skinning routes are drawn as a continuous stroke with a dark outline, direction chevrons, and start/end (or loop) markers, instead of a dotted stair-step. Defaults are teal for herbs (the pack's Touchstone accent) and rust for skinning; a steel colour is reserved for mining if that route type is added later. Smoothing is light and keeps every stop on its node. An existing save still holding the old white default is migrated to teal once; any other stored path colour is left alone. The options panel notes the colour legend next to the route toggles.

### Fixed

- **The transparent box around the window is gone, the hosted body draws no frame of its own, and the options panel is shown only on its own tab** (card t_07f778ca, part A — the owner's in-game report: *"a transparent box outline surrounds the window, larger than the window on every side, most visible above the title bar"*).
  - **The outline was a backdrop-inset class error, not a layout slip.** A backdrop's `insets` exist to leave room for border art: the background is painted that far inside the frame. A flat `WHITE8X8` fill given the panel insets (8px) therefore stopped 8px short of every edge, while the window's 1px hairline was drawn at the TRUE 960x640 edge — an 8px transparent ring between fill and border, widest above the title bar because the band's fill was inset from the top edge too. It could not show on `65b9dd9`, whose frame edge was 32px of dialog art that covered the margin. `MightiePack/Theme.lua` now has one constructor for flat fills — `T.Fill(parent, colourToken, opts)` / `T.FillBackdrop(frame, …)` — which sets `insets = {0,0,0,0}` and no edge; the window fill, the title band and the summary strip use it. A non-zero inset survives ONLY where a `edgeFile` is also set, where it must be no larger than the edge art (`T.inset.edge`, the 1px hairline). `T.Panel` now delegates to `T.Fill`, so a panel cannot re-introduce the ring.
  - **The harness now fails if any flat fill is inset.** `tests/window_fill_inset_spec.lua` walks every backdrop the pack creates — flat fills must have all-zero insets on all four sides, and a fill inside border art must reach the art's inner edge — and it has teeth: it installs an 8px-inset flat fill and a 8px-inset-under-1px-border fill and requires the checker to NAME each. It also pins the hosted body and the options panel (below).
  - **One window, one frame.** The hosted Touchstone body arrived with its own bordered backdrop, so a second, nested box was drawn inside the window — the box the owner saw on Pack Settings. `Window.AttachTouchstone` now strips the body's edge and makes its fill transparent when hosting it, keeping the backdrop table (its rows still paint on it). `tests/window_fill_inset_spec.lua` pins `edgeFile == nil` and a zero-alpha fill while hosted.
  - **The options panel was shown for the whole session.** `MightiePackOptionsPanel` is created and (in the client) BORN SHOWN, so a `DIALOG` frame sat over the UIParent painting nothing — verified in the harness sitting over the Touchstone body. It is now hidden at creation, shown by the two surfaces that own it (Blizzard's Settings canvas when the player opens AddOns > MightiePack, and this window's Pack Settings tab on every activation), and hidden again by `Window.SelectTab` the moment another tab is selected — and only when the window actually owns it, so a player reading the AddOns page keeps it. `tests/window_tabs_spec.lua` and `tests/window_fill_inset_spec.lua` pin "shown iff Pack Settings is active", and `tests/window_settings_build_spec.lua`'s "born shown" premise is inverted with it (OnShow now really does fire on the first activation, so the build-count legs assert the ACTIVATION path on activations #2 and #3 instead).
- Touchstone's list rows and its Settings stack no longer overprint. Both were content-versus-fixed-pixel assumptions older than the unified window; with the body finally readable they showed through — the owner's 2026-11-14 retest of `7e300c3`, "the wording in the Upgrades panel, Log, and Settings, are bunched up and hard to read".
  - **Upgrades and Log rows (item A).** A row's height is now its own measured content and the next row starts at the previous row's bottom, so a reason that wraps to three lines GROWS its row instead of printing over the next item's name. The card's decision, applied to both lists: variable height, not a clamped reason — a verdict reason ("eligibility unconfirmed (fail-closed): …") is the product, and clamping it hides the sentence the advisor exists to say. `ROW_H` (34 Upgrades, 30 Log) survives as a FLOOR, so a one-line row keeps the height it always had; the row's cells are anchored to the row's TOP instead of its centre, which is what makes the bottom measurable. The page is now the run of rows that FITS the viewport, measured the same way, instead of a fixed 12 / 13 rows — once the pitch varies, a fixed count either clips the last row or draws the extra rows outside the panel, and nothing in this window clips a child to its parent. Both tabs run the same two helpers (`SF.PageRows`, `SF.StackRow` in the vendored `UI.lua`, through `tools/touchstone-patches/`), so they cannot drift apart.
  - **Settings (item B).** The stack is a FLOW: every block is anchored under the block above it at that block's measured height, and no absolute y offset survives (`-24/-60/-94/-135/-152/-203/-258/-293/-309` are gone). The About/help block used to hang off the content frame's BOTTOM edge, which is a bet on the body's height: tuned for the standalone 515-unit body, it climbed 74 units into Role/Class inside the unified window's 441-unit body (measured on the owner's screenshot: the panel's interior spans 661 px at 1.5 px per unit) and printed the paragraph over `Role`, `Class: …` and the role note. The tab is re-flowed after every text change (`syncShown` can turn the class line into two lines), a hidden block takes no room at all (the role row is hidden for a class with one stat order), and the content is taller than the body at every size this window has had (≈593 units of measured content against 441), so the flow lives on a wheel-scrolled content frame rather than its tail being drawn outside the panel — the wheel moves the stack, it does not rescale anything (the scale slider and `/ts scale` remain the only scale controls, card t_75261b9a).
  - **The harness could not have seen either.** `tests/support/wowclient.lua` answered ONE line for every FontString, which is exactly the assumption the tabs were making. It now measures a font string the way the client does — explicit `\n` breaks a line and a string with a width wraps at that width — and a label with no explicit width now reports its own width instead of zero, without which every overlap check against a plain heading was vacuous (`About` vs `Role` read as "no overlap" on the head this card fixes, with the paragraph sitting on top of it). It also records `SetClipsChildren` and passes extra arguments to a script, so a wheel delta is part of what a spec can exercise. `tests/window_list_rows_spec.lua` renders the real Upgrades and Log tabs and asserts, for both, that the row contains its reason (row bottom ≥ reason bottom), that the next row's top is at or below the row above's bottom and overlaps nothing, that a three-line row is taller than a one-line row, and that the page is what fits and is maximal — at the standalone 515-unit body AND at the unified window's 441. `tests/window_settings_flow_spec.lua` asserts that no two blocks overlap, that `Role` and `Class:` do not (and that Class is below Role), that the About block and its Tip line collide with nothing, that every block's offset from the top is identical at 441 and 515, and that the scroll range is exactly the content over the viewport and ends with the content's bottom on the viewport's. Both are RED on `7e300c3`.
- Touchstone's inner controls were dead inside the unified window: the hosted module's own `Upgrades / Log / Settings` strip and its panel buttons did not respond, while the four outer tabs did. This is the same strata rule read for the mouse instead of the brush. Mouse hit-testing orders by strata, then level — exactly like painting — and `Window.lua` set `EnableMouse(true)` on the window frame, which carries `DIALOG`, while the reparented Touchstone body keeps `MEDIUM`. The chrome frame therefore outranked the body for input and took every click over it; the body's controls were present, wired and correct, and never reached. The window frame is now `EnableMouse(false)`, and the `MightiePackWindowBackground` fill — the lowest layer, `BACKGROUND` — is `EnableMouse(true)`, which is where "empty window area must not click through to the camera" now lives: content (`MEDIUM`) and chrome (`DIALOG`) win the hit test over it, so it only ever catches the clicks that land on nothing. Nothing is lost by turning the window frame's mouse off: dragging is the title bar's own `bar:EnableMouse(true)` + `RegisterForDrag`, and the tab row, close button and hosts are their own frames. Raising the body above `DIALOG` instead would put it over the title bar, the tab row and the close button, which is the defect the reparent guard exists to prevent. `tests/window_inner_input_spec.lua` measures the client's own `GetMouseFocus()` at the centre of each inner tab, of a panel button on two different inner tabs, of each of the four outer tabs, and of two points in empty window area; it is RED at `cb358e1`, naming `MightiePackWindow` as the frame that took every inner click, and it installs a deliberate mouse-enabled `DIALOG` cover over an inner tab to prove the detector names an offender. `tests/window_strata_spec.lua`'s "the fill is NOT mouse-enabled" structural leg is replaced by its converse plus the behavioural checks that still have teeth (the fill does not own the mouse over the body or over any outer tab, and the window's chrome frame does not take clicks at all).
- The Touchstone tab rendered at a fraction of its neighbours' brightness inside the unified window while every frame alpha read 1.00. The window painted its own opaque fill on the frame that also carries `DIALOG` strata, and the reparented Touchstone body keeps its `MEDIUM` strata, so strata beat frame level outright and the fill drew over the whole body — header, inner strip and item list, uniformly — while the native tabs (children of the window, in `DIALOG`) stayed bright. Measured in game: `TS MEDIUM` against `WIN DIALOG`, all alphas 1.00. The fill now lives on its own `MightiePackWindowBackground` frame at `BACKGROUND` strata, `SetAllPoints` the window, and a frame level at or below the window's; the window frame keeps only its border. The ordering is now structure — fill (BACKGROUND) < content (MEDIUM) < chrome (DIALOG) — so any future body reparented at MEDIUM is correct without its own strata hack. (Which layer owns the MOUSE was settled separately, in the inner-controls fix below: the fill, being the lowest layer, is the frame that catches empty-space clicks.) `tests/support/wowclient.lua` now honours an explicit strata as written (it used to clamp a child up to its parent's, which silently repaired exactly this reparent: that is why a level-only model shipped the defect) and compares strata against the new parent at the moment of the move (`C.StrataCover`, `C.ZOrderHazards`, `C.reparentHazards`). `tests/window_strata_spec.lua` pins the order, the empty hazard set, and proves the model names a MEDIUM frame moved under a DIALOG parent's fill — then names it again when the fill is put back on the chrome frame.
- The Pack Settings tab builds its rows on every activation. The rows exist only after `syncCheckboxes()` + `syncRecipesBlock()` + `relayoutLowerSections()`, and that build was attached to the panel's `OnShow` alone — which can never fire from opening the tab, because a frame created by `CreateFrame` is BORN SHOWN, so the birth `OnShow` is already spent and `Show()` on an already-shown frame fires nothing. Measured against the real `Window.lua`: **0 builds across 3 activations**. The build now has one named path, `pkg.SyncOptionsRows`, called from the panel's `OnShow` and from the tab's own activation in `W.AttachSettings`, and `AttachSettings` shows the panel on every activation instead of returning early once it is parented (the AddOns ▸ MightiePack canvas hides the panel when the player leaves it, and the early return left the tab blank for the rest of the session).
- The window and the Bug report popup were see-through over live terrain. `bgFile = Interface\DialogFrame\UI-DialogBox-Background` does not resolve on this client, so the fill painted nothing while the `edgeFile` still drew — a thin border around the game world. Both call sites now use `Interface\Buttons\WHITE8X8`, which the owner proved resolves there; `SetBackdropColor` still tints it, so `COLOR.bg` continues to decide the colour. The two `WHITE8x8` (lowercase) paths inside the vendored Touchstone module are untouched: they are a suspicion, not a proven defect.
- The four outer tab buttons are drawn as buttons and cannot be covered. They were template-less `Button`s — no backdrop, no normal/pushed/highlight texture — so the row read as plain text, and `paintTabs` could only recolour the label. Each button now carries a `BackdropTemplate` plate with a hover tint, and a frame level five above its strip, so no frame the window creates (the hosts, the title bar, anything added later) can draw over the row and take its clicks.
- A spec that invokes a callback is not a test of the input path. `tests/window_tab_clicks_spec.lua` fires each tab button's own `GetScript("OnClick")` and requires the resulting body to be visible; it also asserts that the frame the client would hand the click to at each button's centre is the button, and that no mouse-enabled frame drawing above a button overlaps its rect — with a deliberate cover frame installed to prove the check names an offender rather than passing because it found nothing. `tests/window_settings_build_spec.lua` pins the build: three activations, three builds, and a hidden panel coming back. `window_tabs_spec`'s fake client now fires `OnShow`/`OnHide` only on an own-flag transition, and `gear_for_spec` no longer invokes the panel's `OnShow` script by hand — the pattern that kept the dead build green.
- A herb pick recorded after the clock goes backwards (`t` older than the per-map `aggT` watermark) is now folded into `mapTotals` and the personal drop-rate stats. Historical picks below the watermark are still skipped, a second load does not double-count, and `hsFolded` / `aggFolded` idempotency is unchanged. `RecordHerb` already counted those picks in the session; the load path now catches appends that had not yet reached the totals. For the `t == aggT` / `aggTN` gate, only marks on records with `t >= aggT` (or untimed) count toward `anyMarked`, so a leftover stamp on a trailing rollback pick cannot disable the skip and double-count history at the watermark. The same reached-watermark rule is used when backfilling a pre-#29 or `noTN`-only save, so a trailing uncounted `t < aggT` pick is not stamped and still reaches the totals.
- The capped-window check in Touchstone's order-only verdict (Hit, Expertise, and other cap tiers) uses the same `ranksAsDifferent` WEIGHT_EPSILON floor as the other ranked tiers, so a rating crumb cannot mint an Upgrade. `tiebreakTotal` uses that same floor instead of an exact `~= 0` comparison.
- Route-line leftovers after PR #27: the contain clip tests now drive `decorClip` itself (including the SQUARE and CORNER insets); decoration clip pads are per kind, and a start/end or loop marker uses half of (`core` + `DECOR_RIM`) so it is not dropped by the larger chevron-arm pad; `_viewAuxHooked` is set only after the canvas OnSizeChanged hook is installed successfully, so a nil or failed canvas can be retried; `numberMethod` drops a value `canaccessvalue` rejects, matching `readPoint`.
- Herb aggregate and hotspot folds no longer drop a second pick from the same second. Aggregates key off `aggT` / `aggTN` for kept records (a mid-loop crash stamp `aggFolded` is cleared once the pass finishes, so a full map does not keep a mark on every raw pick, about 30 KB or 15 bytes per record for 2,000 records). Historical picks with `t < aggT` are skipped; `anyMarked` only gates the `t == aggT` `aggTN` skip, so a same-second sibling is not swallowed after a crash and an unmarked older pick is not re-counted. Only marks on records with `t >= aggT` (or untimed) count toward that gate. A trailing clock-rollback append that is not yet in `mapTotals` is still applied. A schema-2 save from before this change (`aggT` set, no `aggTN` or marks, or a `noTN`-only marker with `aggT` still 0) is backfilled without re-applying totals and without stamping a trailing uncounted rollback pick. A downgrade that re-attaches unmarked picks still skips timestamps below the watermark; at the watermark only the stored `aggTN` / `hsTN` count is treated as already folded.
- A record carrying no `t` no longer counts toward `anyAggFolded`: an untimed crash stamp says nothing about the history cap, and treating it as beyond the cap disabled the pre-#29 backfill so a three-pick save came back as five. Re-appending an already-counted older pick after the watermark is idempotent too: the fold skips a pick whose `(t, x, y)` is already above it in list order (the front re-attach's rule, applied to the append), while a genuinely new clock-rollback pick still reaches the totals. In Touchstone's `Verdict.lua`, `tiebreakTotal` now calls `Verdict.ranksAsDifferent` instead of carrying its own copy of the epsilon comparison, so the ranked comparator and the tiebreaker cannot disagree about a crumb inside `WEIGHT_EPSILON` (changed through `tools/touchstone-patches/ChestAdvisor__Verdict.lua.patch` only).
- `NT.Hotspots` returns a copy of each cell's `nodes` table, so a caller cannot mutate the store. A pick folded into the herb hotspot grid is marked `hsFolded` on the record itself, so a crash mid-loop, a second live trim of new untimed picks, or two evicted picks that share a timestamp cannot skip or double-count (idempotency does not use `noTN` or compare `t` to `hsT` on the first pass). `hsT` remains only as a fallback for a downgrade that re-attaches the trimmed prefix without the mark. `HerbCellKey` recognises a client SECRET coordinate and reaches `tonumber` only through `pcall`.
- A mid-seed crash during the skinning schema 1→2 upgrade could leave `skinContribution` stamps on records and under-count per-item totals on retry. Seeding now clears those stamps first, then rebuilds the totals, so a retry cannot under-seed.
- Chevrons and start/end markers are hidden when a route cannot be drawn (the same `MarkIdle` path the stroke drawer already used), instead of remaining on the map. The minimap no longer draws decorations across an unprojected vertex, including a missing first or last point (those ends are never treated as a closed loop, and start/end markers sit on the first and last usable vertices). Decorations and leftover pool regions are clipped to the minimap, so they cannot paint over the rest of the UI. It skips rebuilding a projection when the route, zoom, rotation, position, minimap shape, instance, colour, and width have not changed, and rebuilds when any of those change. The world-map overlay redraws when the canvas scale or pan changes, so a zoom or scroll cannot leave the route stuck to the window. A diagonal stroke prefers a proved SetRotation primitive as the confirmed default (texcoord is only used when `/nt linetest use texcoord` pins it), and otherwise uses a heavier-overlapping dot chain; `/nt linetest` measures which method this client keeps. Chevrons and start/end/loop markers use the same `Interface/Buttons/WHITE8X8` + SetVertexColor path and the same OVERLAY sublevels (rim 6, core 7) as the rotate stroke, because a core at sublevel 8 is outside the client's -8..7 range and was dropped under the black rim. Chevrons are a rust V of two short ticks with no rim; start/end/loop markers are a light cream square at half the previous size (3.5 screen px, loop 4.5) with a 1-screen-px dark rim (at least one pixel larger than the core after snap). A saved path colour of `{1,1,1}` with no alpha is treated as the old white default and migrated to teal; leftover green fallbacks for the skinning route now use rust.
- Route-line follow-ups after PR #26: the cream marker rim is 1 screen px so it stays visible after pixel snap; ClipItems and the world-map window clip test a chevron by its arm extent, not only its centre; SetClipsChildren on the minimap host is used only when the client exposes it; LineProof only marks CreateLine as taken when the PROBE_SPAN endpoints round-trip; `/nt linetest` invalidates the style drawers as well as the stroke drawers; `_viewHooked` is set only after the ScrollContainer hooks are actually installed; `numberMethod` drops a result `issecretvalue` flags. Minimap decorations use a containing clip (a chevron whose arm would cross the ROUND inset is dropped) so they cannot paint into the square host's corners.
- README Layout now lists `CHANGELOG.md` and `LICENSE` as shipping in the zip (they were wrongly called repo-only). `/nt help` documents `/nt ttdiag` and `/nt navwalk ...|clear`. The skinning default-on comment in `Config.lua` matches the 0.3.4 changelog: offs set before 0.3.4 are turned back on once. `pkg.PackVersion()`'s comment matches GetAddOnMeta (the C_AddOns path returns `dev` for a source token; the legacy path returns the raw token). Touchstone sync patches require a unique context match per hunk and fail if a patch applies zero hunks.

### Changed
- The Touchstone window header shows the pack version from the TOC, not Touchstone's upstream module version. The module version remains on the Settings About line and in diagnostic output.
- Pack options no longer show a raw Alchemy scan error under Alchemy Recipes. The line now reads "Alchemy scan isn't available on this client yet"; `/nt recipediag` and the Scan-now chat line still carry the technical text.
- README slash table covers `/mp` (including `bug`, `idea`, and `skindiag` / `skindiag copy`), the `/nt` family, and the Touchstone family (`/touchstone`, `/ts`, `/sf`, `/up`, and aliases). Diagnostic commands are marked as such. Layout and Tests are regenerated from the tree. `HANDOFF.md` is archived under `docs/archive/`.
- CI pins Lua 5.1 and LuaRocks (leafo actions by SHA), caches luacheck, and times out a stalled toolchain install separately from lint.

### Fixed
- The vendored Touchstone secret-values guard (and other NodeTrail-local Touchstone edits) is reproduced by an anchored post-copy patch in `tools/sync_touchstone.py`, so a re-sync cannot silently drop the ChestAdvisor crash fix.
- `pkg.version` is no longer a hardcoded `"0.3.0"`. The pack version is read from the TOC via `pkg.PackVersion()` (nil-safe).
- The Touchstone Settings "Reset to defaults" description wraps within the frame instead of running off the right edge.

## [0.3.5-beta] - 2026-11-11

### Fixed
- Skinning a pack more than 10 seconds after the kills, when the skin loot window has no loot-source GUID (common on this client — corpse windows already fell back to `UNIT_DIED`), now marks those corpses skinned. A GUID-less window may be attributed to the dead target only within a short bound after `UNIT_SPELLCAST_SUCCEEDED` (`TARGET_ATTRIB_WINDOW`, 3s starting value, to be live-measured), and only while that target is still the cast's corpse if known. The pending pin's GUID is never invented onto a GUID-less window, and target-change or an unclaimed `LOOT_CLOSED` clears that attribution, so a later herb, chest, or fishing window cannot be filed as skin loot. Live on v0.3.4-beta: 11 beasts killed and skinned on a map, the tooltip said `kills seen: 11 · skinned: 0` with no materials, and `/nt skinroute` said `0 of 8 skinned corpses` because no ring record had `skinned = true`.
- Skinning spell detection includes classic ranks `8613`, `8617`, `8618`, `10768` and Forever 1.60.1.70532 IDs `1240952`, `1240963`, `1240974`, `1240987`. The 4th `UNIT_SPELLCAST_*` argument on this client is a CastBar frame name and is not required to contain "skin".
- ChestAdvisor no longer errors when the Forever client returns a secret number from combat-stat APIs (`GetHitModifier`, `GetSpellHitModifier`, `GetCombatRatingBonus`, `GetExpertisePercent`, `UnitDefense`, `UnitAttackBothHands`). Those values still have type `number`, so adding them in `Verdict.playerHitPercent` raised `attempt to perform arithmetic on a secret number value (execution tainted by 'MightiePack')` — live, while opening the character sheet (`ChestAdvisor.scan` from the paper-doll refresh). Secret returns are now skipped (the cap is treated as unreadable) and a scan requested in combat is deferred until `PLAYER_REGEN_ENABLED`, checking `UnitAffectingCombat` as well as `InCombatLockdown`.

### Changed
- The beast tooltip no longer prints `kills seen`. It shows `skinned: N` and the top 4 skin materials for that creature as `Name xN`, using the name stored at loot time, with fallback `item <id>`. Kills remain in `/mp skindiag` and the saved totals.

### Added
- `/mp skindiag copy` and a **Copy skinning diagnostics** button next to Skinning (experimental) open a compact dump (header, counts/accounting, last ~20 steps) in the same copyable popup as the bug report, so it can be Ctrl+A / Ctrl+C pasted into Discord. The popup path does not print the dump to chat. It still opens when the collector is off and says so in the text.

## [0.3.4-beta] - 2026-11-11

### Changed
- The skinning recorder is on by default: a fresh install records from the first corpse with no setup. A one-time migration switches the previous default on for an existing install, and an explicit off — un-ticking Skinning (experimental) in settings or `/nt skin off` — is stored as the player's own choice (`NodeTrailDB.skinning.skinUserSet`), so it survives `/reload` and later updates and the migration never overrides it. `/nt skin status` reports the current state. Correction: that last claim is only true for offs recorded on 0.3.4 or later, when `skinUserSet` exists. An explicit off set under 0.3.3 or earlier is indistinguishable from a player who never touched the setting, so the one-time migration turns those older offs back on once.

### Fixed
- Skinning counts every skin once again, whichever way the recorder saw it. A successful skin is normally reported as a cast with no corpse pinned to it followed by the skin loot window, and only the pinned path incremented the per-creature total — so the window marked the corpse skinned (its items were recorded and its loot was correct) while the skinned count the beast panel prints stayed behind. Live: 5 Plainstriders skinned, the panel said `kills seen: 18 · skinned: 3`. The window now counts the corpse it marks, and a corpse already counted — by the cast path, by a re-opened window, or by the schema 1 → 2 seeding — is never counted twice. A skin window with no successful cast behind it still marks and counts nothing.
- Skinning now counts a skin even when the corpse had no loot, and the skin loot attaches to the corpse that was actually skinned. A corpse with nothing in it produces a `LOOT_OPENED`/`LOOT_CLOSED` pair in the same instant, and the recorder used to treat that empty window as "the corpse the player just looted" — so the cast was pinned to the empty corpse and the real skin window was filed as ordinary corpse loot. The corpse you skinned was never marked skinned, which also kept it out of the skinning farming circles. A real run that reported `kills=8 corpse-windows=3 skin-windows=1 skin-casts=2 | lost casts=1` now reports `lost casts=0` with the skinned corpse carrying its own skin items.
- The skinning tooltip no longer forgets a creature once 100 newer corpses land behind it. Kills, skinned count and skinning item counts are kept per creature id and never evicted, so a beast you have skinned dozens of times shows its totals instead of `no observations here yet`; the 100-record window is now only the source of the farming-circle positions. An existing save is upgraded in place on the next load — its totals are seeded from the corpses it still holds, every record is kept, and the upgrade happens exactly once.

## [0.3.3-beta] - 2026-11-11

### Added
- Touchstone can score and gate gear for a chosen spec (`/up spec`, and a Gear for picker under Touchstone in settings) even when you are talented into a different one. Auto still follows your current talents. A spec without a sourced profile would stay silent (`no sourced weights for <spec> yet`) rather than guessing another pack.
- Wowhead is the sole source for every shipped Touchstone spec. All 28 Forever specs (including Feral Cat) use the published stat-priority list as an order-only, cap-aware profile: tiers are compared in published order, the first differing tier decides, and there are no invented numeric weights. Per-spec caps come from each page (for example melee hit is 8% for Arms / Rogue / Feral Cat / Enhancement and 9% for Fury / Retribution / Hunter; Rogue then has a second Hit cap at 17% for poisons). When the client can be read, gains past a cap do not count and losses that drop below a cap do; otherwise the verdict says cap status unknown and still ranks the stat. Each profile records its Wowhead URL and the page's updated date (pages fetched 2026-11-11). The lists live in `data/wowhead_stat_priorities.json`; `tools/gen_wowhead_priorities.py` regenerates the Lua tables, so an update is a data change.
- Tank defaults follow Wowhead's published variants: Protection Warrior and Protection Paladin use the Balanced list, and Feral Bear (which has no Balanced list) uses Defensive. The Gear for picker also exposes Defensive and Offensive as `Protection (Balanced)` / `Protection (Defensive)` / `Protection (Offensive)` and `Feral (Bear, Defensive)` / `Feral (Bear, Offensive)`.
- Enhancement keeps Wowhead's published order as written, with no extra tiers. Its verdicts append a caveat — `Wowhead list predates the Nov 10 Mental Dexterity hotfix; Intellect may be overrated. Hit past the listed 8% melee minimum is not scored.` — from a per-profile `caveat` field (`data/wowhead_profile_caveats.json`, citing the official Forever hotfix notes). Remove that entry and regenerate when the Wowhead page is updated.
- Leveling-only tags on a list (Elemental `Strength (Only while leveling)`, Restoration Shaman `Spell Damage (Only while leveling)`) apply only below level 60.

### Fixed
- Defense skill is the Classic `UnitDefense` total (`base + armorBonus`), so a 440-cap window can close and a later tier such as Armor can decide.
- Expertise is no longer converted with an unsourced rating-per-percent of 10. Forever percent tooltip text is compared directly to Wowhead's 6.5% / 14% caps; a rating-only line reports cap status unknown.
- Caster 17% spell-hit caps read `GetSpellHitModifier` (and spell hit rating), not melee hit chance. Expertise current is only taken from APIs that return a percent (`GetExpertisePercent` or `GetCombatRatingBonus`). Weapon skill is read as a skill total (`UnitAttackBothHands`), not `GetCombatRating(CR_WEAPON_SKILL)`.
- Enhancement follows Wowhead's numbered list exactly: hit past the listed 8% melee minimum is not scored, and that is noted in the caveat. The Mental Dexterity caveat cites the official Forever hotfix notes (`https://news.blizzard.com/en-us/article/24315281/wow-forever-hotfixes-november-10-2026`).
- `/up spec` with no argument names a recorded `/up role` when Auto is in effect (precedence is chosen spec > `/up role` > talents). `/up reset` also clears a chosen Gear-for spec (back to Auto) and does not clear `/up role` or the log.
- Arcane and Fire Mage Hit caps are scored as spell hit. `hitKind` is taken from the spec profile family (every Hit tier on a spell profile is spell), not from caps-map keywords, so a 17% cap that mentions Arcane Focus or Precision uses `GetSpellHitModifier`.
- Combat-rating reads no longer invent a `CR_*` index when the client does not expose one (`CR_EXPERTISE`, `CR_HIT_MELEE`, and any other guessed `CR_*` fallback).
- Mixed percent-vs-rating Expertise is a trade-off with cap status unknown, not a comparison that treats the missing percent as 0.
- Dual-wield weapon skill uses the lower of the two hands from `UnitAttackBothHands` only when an off-hand weapon is equipped (`OffhandHasWeapon`, or slot 17 as `INVTYPE_WEAPON` / `INVTYPE_WEAPONOFFHAND`). The unarmed skill Classic reports in the off-hand slots for a two-hander or a shield is ignored.
- An item that has both percent Expertise text and `ITEM_MOD_EXPERTISE_RATING` uses the percent only.
- Expertise percent text matches Forever item wording (`Reduces the chance for your attacks to be dodged or parried by N%`).

## [0.3.2-beta] - 2026-11-11

### Added
- `/mp idea` (also `/mpack idea`, and a Suggest an idea button next to Report a bug) opens a movable popup with a pre-filled, already-selected idea to copy into #mightiepack-ideas. Addon version, client version, and an Area line (NodeTrail / Touchstone / Skinning / General, or a single area if given as `/mp idea nodetrail`; only the first word after `idea` is used) are filled in; character names, realms, class, level, zone, and Lua errors are left out. WoW cannot write the clipboard, so the player presses Ctrl+C.

### Fixed
- The Report a bug / Suggest an idea popup now shows the pre-filled text in a typable, selectable EditBox (a font is applied, the box has a real size, and the frame is toplevel above the Options window) and has a single Close button.
- The MightiePack options page uses a vertical flow so the skinning-circle status no longer overlaps its checkbox, Alchemy's Scan now sits under its status, and Feedback has Report a bug and Suggest an idea side by side.
- The skinning tooltip no longer hides known skin/leather details when the unit is not a Beast (for example Cursed Darkhound, a Demon). Known records are shown regardless of creature type; the empty "no observations" hint stays Beast-only when we have no data for that NPC.

## [0.3.1-beta] - 2026-11-11

### Added
- `/mp bug` (also `/mpack bug`, and a Report a bug button) opens a movable popup with a pre-filled, already-selected report to copy into #mightiepack-bugs. Addon version, client version, enabled modules, class and level, zone/map, and the last MightiePack Lua error are filled in; character names and realms are left out. WoW cannot write the clipboard, so the player presses Ctrl+C.

## [0.3.0-beta]

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
