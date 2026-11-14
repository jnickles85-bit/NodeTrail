# MightiePack — Touchstone (and the NodeTrail hand-over)

MightiePack is an umbrella addon for WoW Forever Classic (Interface 16001). It
ships one module, **Touchstone** (gear upgrade advice; formerly StatForge), and
it holds the door open for **NodeTrail**, which is its own addon again: the herb
and skinning recorder with route guidance now lives in the `NodeTrail` folder.

**If you gathered herbs or skinned beasts while NodeTrail was part of this pack,
your history comes with you into the NodeTrail addon.** See
[NodeTrail moved out](#nodetrail-moved-out) — it takes one login.

## Install
1. Install the `NodeTrail` addon if you want the recorder (it is a separate
   download now).
2. Copy the `MightiePack` folder into the client's AddOns folder.
3. If you are coming from an older pack, keep both installed and **enabled for
   one login** — that login is what carries your history over to NodeTrail.
   After it, you can delete either one you do not want.
4. Remove any old standalone `Touchstone` folder: it defines the globals the
   pack's vendored copy uses (`StatForge` / `StatForgeDB`), and two copies must
   never write `StatForgeDB`.
5. GatherMate2 is optional.

## NodeTrail moved out

NodeTrail (herb routes, herb tooltips, Alchemy recipe uses, the skinning
recorder and its farming circles) is a **separate addon** now. This pack does
not ship its files, does not answer `/nt`, and does not start its recorder.

It does keep **one thing**: the `NodeTrailDB` declaration in its TOC. Saved
variables are stored by the game in one file per addon, so a history that was
recorded while NodeTrail lived here is in `MightiePack.lua`. That declaration is
what makes the game load it, and it is what lets the NodeTrail addon take the
history over on the first login with both installed — it then writes it to
`NodeTrail.lua` and owns it from there. The pack reads and writes **no key** of
that store (`tests/no_nodetrail_keys_spec.lua` pins that), and the declaration
comes out in a later release, once nobody is migrating any more.

What that means for you:

* Keep MightiePack installed **and enabled** for the first login after you
  install NodeTrail. Then `/nt migrated` in NodeTrail shows what was carried
  over and whether anything is missing.
* If you delete this pack *before* that login, the game never loads
  `MightiePack.lua` — nothing is deleted, but no addon can read it either.

## Modules
| Module | Description | Default |
|--------|-------------|---------|
| Touchstone (formerly StatForge) | Gear upgrade advice (vendored Touchstone 0.8.3) | Off |

Touchstone's files are generated into `MightiePack/Modules/Touchstone/` by
`tools/sync_touchstone.py` from the pinned StatForge commit, plus anchored
fold edits and post-copy patches under `tools/touchstone-patches/`. Do not
hand-edit the vendored files without adding or updating a patch — a re-sync
would drop an unanchored change (including the ChestAdvisor secret-values
guard). The module refuses to run while the standalone `Touchstone` addon
folder is installed. Remove that folder and reload to use the vendored copy.

## Slash commands

Aliases: `/mp` = `/mpack` = `/mightiepack`. Touchstone (formerly StatForge)
registers `/touchstone`, `/sf`, and `/statforge` on one handler, and `/ts`,
`/up`, `/upgrade`, and `/chestadvice` on the advisor handler. Commands marked
**(diag)** are diagnostics.

| Command | Description |
|---------|-------------|
| `/mp` or `/mp options` or `/mp config` | Open the MightiePack window on its **Pack Settings** tab |
| `/mp status` | Print pack version, interface, client build, and module on/off state |
| `/mp bug` | Open the bug report popup (no upload — copy and paste into Discord) |
| `/mp idea [area]` | Open the idea popup (optional area: nodetrail, touchstone, skinning, general) |
| `/touchstone` (aliases `/sf`, `/statforge`) | Open the MightiePack window on its **Touchstone** tab |
| `/touchstone options` | Open Touchstone on the Settings tab |
| `/touchstone diag` or `diagnostics` **(diag)** | Open the Touchstone diagnostics panel |
| `/touchstone doctor` **(diag)** | Print the diagnostics report and open the panel |
| `/touchstone probe` **(diag)** | Run the deep probe into SavedVariables |
| `/touchstone stats <itemlink>` **(diag)** | Print this client's `C_Item.GetItemStats` pairs for a pasted link |
| `/ts` (aliases `/up`, `/upgrade`, `/chestadvice`) | Open the MightiePack window on its **Touchstone** tab |
| `/ts help` | Print the advisor command list |
| `/ts scale <0.5-1.5>` | Window scale (also the Settings slider; saved across `/reload`) |
| `/up role <melee\|spell\|clear>` | Record the focus role for a hybrid class |
| `/up spec [key\|name\|auto]` | Which spec Touchstone scores gear for (overrides talents and `/up role`) |
| `/up tooltip <on\|off>` | Item-tooltip verdict line (default on) |
| `/up detail <full\|compact\|upgrades>` | How much the tooltip shows (default full) |
| `/up toast <on\|off>` | "Upgrade found!" toast (default on) |
| `/up toast lifetime <seconds>` | Toast lifetime, 1–30 (default 3.5) |
| `/up toasts` or `/up testtoast` **(diag)** | Raise one "Test Upgrade" toast now |
| `/up toastdebug [on\|off\|dump]` **(diag)** | Trace every toast transition with timestamps |
| `/up glyphs <on\|off>` | Colorblind-safe marker glyphs (default off) |
| `/up reset` | Restore display defaults and clear a chosen Gear-for spec; does not clear `/up role` or the log |
| `/up log` / `/up log clear` | Disagreement log (items you equipped that were not called an upgrade) |
| `/up rescan` | Re-scan bags now |
| `/up probe` **(diag)** | Run the Phase D probes (read-only) |
| `/up diag` **(diag)** | Write a SavedVariables + global diag record; print rows to chat |

Retired Touchstone words (`/touchstone export`, `/touchstone gear`) print that
those features are retired; they are not silently ignored.

## Options
- Open with `/mp`, `/mpack`, or `/mightiepack`.
- Tick a module: turns on immediately, no reload.
- Untick: confirm popup "Turn off <module>? This needs a UI reload." OK saves it off and runs ReloadUI(); Cancel (or Escape) keeps it on and re-ticks the box.

## Layout
Shipping addon (the CurseForge zip contains this folder only):

```
MightiePack/MightiePack.toc
MightiePack/Core.lua
MightiePack/Modules.lua
MightiePack/Options.lua
MightiePack/BugReport.lua
MightiePack/ErrorHandler.lua
MightiePack/Modules/Touchstone/Bootstrap.lua
MightiePack/Modules/Touchstone/Constants.lua
MightiePack/Modules/Touchstone/UI.lua
MightiePack/Modules/Touchstone/OptionsTab.lua
MightiePack/Modules/Touchstone/UpgradesTab.lua
MightiePack/Modules/Touchstone/LogTab.lua
MightiePack/Modules/Touchstone/Diagnostics.lua
MightiePack/Modules/Touchstone/Probe.lua
MightiePack/Modules/Touchstone/Integration.lua
MightiePack/Modules/Touchstone/Core.lua
MightiePack/Modules/Touchstone/ChestAdvisor/Verdict.lua
MightiePack/Modules/Touchstone/ChestAdvisor/ChestAdvisor.lua
MightiePack/Modules/Touchstone/ChestAdvisor/marker.tga
MightiePack/Window.lua
MightiePack/Window/Common.lua
MightiePack/Window/TouchstoneTab.lua
```

Also shipped in the zip (not listed above): `CHANGELOG.md` and `LICENSE`.

Repo-only (not shipped): `README.md`, `tests/`,
`tools/` (`sync_touchstone.py`, `touchstone-patches/`, `gen_wowhead_priorities.py`),
`data/`, `evidence/`, `docs/archive/HANDOFF.md`, `.github/`, `.luacheckrc`,
`.pkgmeta`.

## Tests
Run from repo root with lua5.1 (`lua5.1 tests/<name>.lua`). 26 specs:
- `tests/bugreport_spec.lua`
- `tests/chestadvisor_diag_spec.lua`
- `tests/chestadvisor_secret_values_spec.lua`
- `tests/gear_for_spec.lua`
- `tests/idea_spec.lua`
- `tests/no_nodetrail_keys_spec.lua`
- `tests/slash_spec.lua`
- `tests/status_meta_spec.lua`
- `tests/sync_touchstone_patch_spec.lua`
- `tests/toast_test_spec.lua`
- `tests/toast_trace_spec.lua`
- `tests/touchstone_assets_spec.lua`
- `tests/touchstone_fold_spec.lua`
- `tests/touchstone_loadorder_spec.lua`
- `tests/touchstone_secret_guard_spec.lua`
- `tests/touchstone_tiebreak_single_rule_spec.lua`
- `tests/touchstone_tiebreak_spec.lua`
- `tests/touchstone_tooltip_line_spec.lua`
- `tests/touchstone_weights_spec.lua`
- `tests/umbrella_spec.lua`
- `tests/window_inner_input_spec.lua`
- `tests/window_settings_build_spec.lua`
- `tests/window_strata_spec.lua`
- `tests/window_tab_clicks_spec.lua`
- `tests/window_tabs_spec.lua`
- `tests/window_touchstone_shade_spec.lua`
