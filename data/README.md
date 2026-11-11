# Wowhead Forever stat priorities

Touchstone's sole source for shipped gear-for-spec profiles. The JSON
is a fetch of every Wowhead Forever class stat-priority page
(28 pages, 33 list variants, fetched 2026-11-11, America/New_York).

To refresh the addon tables after editing or replacing the JSON:

    python3 tools/gen_wowhead_priorities.py

That rewrites the marked region in
`MightiePack/Modules/Touchstone/ChestAdvisor/Verdict.lua`. Do not
hand-edit that region. The JSON itself is not packaged into the
addon zip; only the generated Lua ships in-game.

Optional per-profile caveats live in `wowhead_profile_caveats.json`
(keyed `CLASS.weightsKey`, e.g. `SHAMAN.enhancement`). Each entry may
be a string, or an object with `text` (copied onto `profile.caveat`
and appended to verdicts) and `source` (an official citation URL,
recorded as a Lua comment). The published Wowhead order is never
reordered. Delete an entry and regenerate when the Wowhead page
catches up.

