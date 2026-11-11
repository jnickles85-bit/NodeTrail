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
