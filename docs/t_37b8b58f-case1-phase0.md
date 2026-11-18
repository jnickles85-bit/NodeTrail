# Case 1 phase 0 — what the four seams buy, measured

Card `t_37b8b58f`. Measurement only: no pin move, no deploy, no tag, nothing
merged. Branch `nt/t_37b8b58f` off `origin/main` (`e59ace6`).

**Measured against StatForge `eebfba4`** (the PR #121 merge that carries the four
seams). The repo's `SOURCE_REF` is `4183aee` (re-vendor #4) — not `6003176`, not
`eebfba4` — and this branch does **not** change it.

## Method (so the numbers can be re-derived)

1. **Pack edit lines** — file-level diff between pristine `4183aee` and the
   shipped vendored file. Baseline proven, not assumed: `generate(4183aee)` with
   `origin/main`'s `sync_touchstone.py` + patches reproduces all 14 shipped files
   byte-for-byte (0 mismatches). Every line in the table is therefore a line the
   sync tool puts there.
2. **Seam drop** — the same file-level measure with only the seam-bearing hunks
   applied. `UI.lua` hunks 1–13 measured this way: 403 lines. Anchor-based edits
   use the anchor's added+removed lines (toast trace: +360/−68 = 428).
3. **Must remain = (1) − (2).**
4. **Cross-check** — three-way merge (base `4183aee`, ours `eebfba4`, theirs the
   pack) gives the pack's intent replayed on the new pin: **≈3,730 lines**. That
   is the lower bound, because upstream already carries part of the pack's work.

## The table

| # | file | pristine now? | lines that must remain | why |
|---|---|---|---|---|
| 1 | `Constants.lua` | **yes** | 0 | trivial — guard only |
| 2 | `Weights.lua` | **yes** | 0 | trivial — guard only |
| 3 | `UI.lua` | no | **46** | presentation, no seam — the shared row model (`SF.PageRows`). The 403-line hosted-chrome + palette prototype is exactly what the seams now provide, and upstream has it |
| 4 | `OptionsTab.lua` | no | **≈304** | presentation, no seam — the Settings flow (`host.blocks` + `relayout`) ≈294; the ~10-line accent claim is rehoused |
| 5 | `UpgradesTab.lua` | no | **≈368** | presentation, no seam — row stack + ledger drawing. Its metrics come from `MightiePackTheme.list`, which `SF.SetTheme`'s three tokens do not cover. Asset path (11 lines) drops |
| 6 | `LogTab.lua` | no | **≈290** | presentation, no seam — row stack + ledger palette |
| 7 | `Diagnostics.lua` | **yes** | 0 | trivial — guard only |
| 8 | `Probe.lua` | **yes** | 0 | trivial — guard only |
| 9 | `ChestAdvisor/Marks.lua` | **yes** | 0 | trivial — the asset retarget (11 lines) drops; upstream resolves through `SF.AssetPath` |
| 10 | `ChestAdvisor/Verdict.lua` | no | **≈2,136** | engine behaviour — the weighted / order-profile layer: `WEIGHTS`, tiers, caps, tiebreak, the order-profile comparator, weapon DPS & speed. **Zero occurrences upstream** |
| 11 | `ChestAdvisor/ChestAdvisor.lua` | no | **≈763** | pack-local product (registry ≈390) + engine (weighted rows/tooltip ≈240) + lifecycle fold and diagnostics ≈133. Toast trace (428 lines) drops |
| 12 | `GearAPI.lua` | **yes** | 0 | trivial — guard only |
| 13 | `Integration.lua` | no | **≈11** | pack-local product — deferred load calls |
| 14 | `Core.lua` | no | **≈42** | pack-local product — the `SF.Enable` lifecycle fold and slash gating |

### Totals

- **6 of 14 go pristine** (five are guard-only; `Marks.lua` loses its whole edit
  to the asset seam).
- **≈3,960 lines still differ** across the other eight. Composition:
  **engine 2,376** · **row model + ledger 1,008** · **registry 390** ·
  **fold/product/diagnostics 186**.
- The four seams remove **≈890 lines** (chrome+theme 403 + asset ~22 + toast
  trace 428 + the rehoused palette claim ~20). They are not the bulk of the
  reduction; the weighted layer is more than twice all four seams combined.

### Which of the pack's edit files need what

| edit file | verdict |
|---|---|
| `UI.lua.patch` | **rehouse** hunks 1–13 (403 lines → the chrome/theme claims); **re-cut** hunk 14 (PageRows, 46) |
| `OptionsTab.lua.patch` | **rehouse** hunk 1 + hunk 12's accent block; **re-cut** hunks 2–11, 13 |
| `UpgradesTab.lua.patch` | **re-cut** (all 10 hunks); asset lines deleted |
| `LogTab.lua.patch` | **no change** — all 6 hunks still apply to `eebfba4` |
| `ChestAdvisor__Verdict.lua.patch` | **re-cut** (all 22 hunks) |
| `ChestAdvisor__ChestAdvisor.lua.patch` | **re-cut** (registry + engine hunks); asset retarget and toast trace **rehoused/deleted** |
| `retarget_assets()` in the tool | **delete** — the asset seam replaces it outright |

Anchors: **18 of the 69** no longer match `eebfba4`; **5 of the 6** patch files
have at least one drifted hunk. Editors needing re-anchoring: `edit_verdict`
(2 anchors) and `edit_chestadvisor` (16 anchors). `edit_core` and
`edit_integration` re-anchor untouched.

## The Bootstrap neutral flag

**Question:** with `TouchstoneSkip` set from the install detection, do the five
"standalone detected" checks pass on *pristine* bytes?

**Measured** by running `tests/touchstone_fold_spec.lua` against a tree whose 14
vendored files are entirely pristine `eebfba4` bytes:

| mode | the five checks |
|---|---|
| pristine + guard | **5/5 pass** — `StatForge` untouched, `ChestAdvisor` untouched, no frame, no slash, `Enable` runs no body |
| pristine, no guard | **0/5 pass** |

It still holds at this pin, unchanged from the previous measurement. The
consequence for the table: the single guard line is the only distance between
"pristine" and "byte-identical" for the six files, and it is proven neutral. It
is a property of the vendoring method (the TOC loads these files
unconditionally), not of any file's content.

## Findings about the seams themselves

1. **Chrome** — already claimed, before this card: `Window.AttachTouchstone`
   calls `SF.SetHostedChrome(true)` twice (before creation and on the live
   frame), guarded. Nothing to add.
2. **Theme + assets** — now claimed in `Modules.lua`'s Touchstone `Enable`, the
   module's single initialisation point (there is **no `Host.lua` anywhere in the
   repo**; the host surface is `Window.lua` + `Window/TouchstoneTab.lua`). Both
   claims are guarded on the seam existing, so against `4183aee` they are inert —
   proven by `tests/touchstone_seam_claims_spec.lua`, which exercises the inert
   and active paths and the inert-module path.
3. **Toast** — **not claimable for the whole block.** `ChestAdvisor.OnToast` is
   observation only; the pack's toast block is not:
   - it re-homes two player-facing diagnostic commands, `/up toastdebug` and
     `/up testtoast` (114 anchor lines). Dropping the block without re-homing
     them makes both commands stop existing — a visible change;
   - it used to carry the alpha-restore fix. **Upstream has an equivalent and
     stronger one** at `eebfba4` (sets the resting alpha to 1 the moment the
     animation takes over, instead of the pack's delayed timer), so the fix is
     no longer a reason to keep the block.

   So the seam is claimable, and the commands are not covered by it. Either they
   are re-homed onto `OnToast` in pack code (small, but it is product work) or
   their loss is accepted and ledgered. **Not claimed on this branch** — a claim
   with no consumer would be dead code. This is the finding that belongs upstream
   if the pack wants the seam to cover the diagnostic surface too.
4. The row model and the registry are confirmed seams-that-do-not-exist:
   `rowHeight`/`PageRows`/`specsFor`/`lookupSpec`/`GEAR_ALIASES`/`gearFor` have
   **zero occurrences** in `eebfba4`.

## What this means for the Case 1 ruling

The choice is not "reduced form vs two more seams". The reduced form already
leaves ≈3,960 lines, and **≈2,376 of them are the weighted engine, which no
presentation seam can absorb** — it is a scoring layer, not a drawing layer.
Authorising the row model and the registry removes ≈1,400 of the remaining
≈1,580 non-engine lines. The engine stays either way and must be ledgered as a
permanent pack-side fork.

## Validation performed on this branch

- `luac -p` on all 23 shipping files: clean.
- `luacheck MightiePack`: 0 warnings / 0 errors.
- Specs: **40/40 pass** under Lua 5.1 (39 at `origin/main` + the new
  `touchstone_seam_claims_spec.lua`).
- Guard neutrality: 5/5 → 0/5, measured as above.
- `sync_touchstone.py` `generate(4183aee)` == shipped bytes, 14/14.
