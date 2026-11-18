# Touchstone: where the pack's copy diverges from the pin

The vendored Touchstone under `MightiePack/Modules/Touchstone/` is generated from a
named StatForge commit (`SOURCE_REF` in `tools/sync_touchstone.py`). Six of the
fourteen files are that commit's blobs, byte for byte. Eight carry a patch, and every
patch names its reason in its own header.

**A file that differs from the pin is not a divergence. It is a failed copy check.**
This document records *behaviour* that differs on purpose — the things a reader of the
pin would answer differently — and the places where a seam exists but cannot carry
what the pack does. A patched file with no entry here means its patch carries the
pack's own product surface (the registry, the row model, the ledger drawing, the
Settings flow), which is additive and answers nothing differently.

The mechanism that keeps this honest is `tools/sync_touchstone.py --verify-shipped`:
it hashes the six pristine files against the pin's blobs (`COPY:`) and reverses each
of the eight patches back to the pin's blob (`PATCH:`). Both messages name the file
and the patch, and both run in CI on every pull request.

---

## 1. The equal-dps melee tier — **permanent, by owner decision (2026-11-17)**

**What differs.** On a weapon pair whose weapon damage per second is EQUAL, the pack
lets the spec's weighted profile decide the Step 1 verdict and quotes the tier that
decided it. Upstream does not: at the pin, no weight decides a Step 1 verdict
(Contract Y), and the pair returns the order's own answer.

| pair | StatForge `eebfba4` | MightiePack |
|---|---|---|
| `+12 Weapon Skill` vs the equipped weapon, at equal dps, Retribution | `UNKNOWN` — *"cannot classify: 12 Weapon Skill (the weapons tie on damage per second, but that line could not be placed; on the hovered item)"* | `UPGRADE` — decided by the Weapon Skill tier |

Measured, not remembered: the left column is the pin's own `Verdict.compareWeapon` on
that pair (Constants + Weights + Verdict from `eebfba4`, no pack code loaded), the
right column is the pack's `ChestAdvisor/Verdict.lua` on the same two line sets. The
fixture is `tests/touchstone_reader_pin_spec.lua` leg 6 (`SKILL_CAND` / `SKILL_WORN`),
which asserts the pack's answer.

**Why it is deliberate, not stale.** The pack's shipped verdict engine is the
weighted/order-profile layer (1,732 lines in `ChestAdvisor__Verdict.lua.patch`, the
pack's own code). Upstream retired that model on purpose and replaced it with the
order-decides cascade plus Step 3's arbitration. The pack has not followed, and that
is a decision: two copies must not answer the same pair differently *inside one
client*, so the module's own answer is the one this pack ships. The owner ruled the
divergence permanent on 2026-11-17.

**Where it lives.** `ChestAdvisor__Verdict.lua.patch` — the `Verdict.weightedVerdict`
block and the equal-dps arm of `Verdict.evaluate`. The fixture that pins it is
`tests/touchstone_weights_spec.lua` (the live case: `+12 Weapon Skill` at equal dps
is a `Downgrade`/`UPGRADE` off the weighted total, with the profile named) and
`tests/touchstone_tiebreak_spec.lua` for the tier-name wording.

**What it would take to retire.** Upstream answering the question the tier answers —
*on an equal-dps pair, does Weapon Skill decide?* — in a form the pack can call.
Until then the pack's answer stands, and this entry stays.

---

## 2. Seam limitations (not divergences)

These are places where an upstream seam exists but is observation-only, or where no
seam exists at all. The pack therefore keeps its own code; nothing here answers a
question differently, so nothing here is a behaviour divergence.

### `ChestAdvisor.OnToast` — observation-only

Upstream publishes `ChestAdvisor.OnToast(fn)`: a host can *observe* each toast phase
(`show`, `end`) but cannot replace the panel, its queue, its timers or its trace. The
pack needs all four — its toast is the surface its own `/up toasts` / `/up testtoast`
/ `/up toastdebug` commands drive, and its tests measure the panel's real on-screen
time — so the pack keeps its own toast block rather than half-adopting a hook that
cannot carry it.

Consequences, stated plainly:

- the pack ships its own toast code (queue, fade, countdown, trace) rather than a
  thin observer on upstream's;
- `/up toasts`, `/up testtoast` and `/up toastdebug` are the pack's commands; they
  document and drive the pack's toast;
- 114 anchor lines around those commands are in `ChestAdvisor__ChestAdvisor.lua.patch`
  and cannot be absorbed by the seam as it stands.

If upstream ever lets a host *own* the toast rather than observe it, this section
shrinks to the commands and the patch loses the block.

### The presentation layers — no seam, or no model

- **The measured row stack** (`UI.lua`, 46 lines): `SF.PageRows` / `SF.StackRow`.
  Upstream has no row model at all — its tabs use a fixed pitch — so a row that grows
  to a wrapped reason and a page measured to the viewport have nowhere else to live.
- **The ledger drawing and the row stacks** (`UpgradesTab.lua`, `LogTab.lua`): the
  ranked row stack, the verdict gutter, the change column, the hairline rules.
  Upstream has no ledger and no seam for one.
- **The Settings flow** (`OptionsTab.lua`): `host.blocks` + `relayout`, and the About
  block's accent repaint. The window owns the layout; upstream ships no hook for it.

These are the pack's product surface. They add; they do not re-answer anything
upstream answers.

---

## Keeping this document true

- A new behaviour divergence needs an entry here **in the same commit** as the patch
  hunk that causes it, marked permanent or pending.
- A retired divergence is deleted, not annotated: the entry describes what the shipped
  bytes do today.
- `--verify-shipped` proves the *files* are the pin plus their patches. It cannot
  prove that a patch's contents are intended — that is this document's job, and it is
  why every patch carries a named reason at the top.
