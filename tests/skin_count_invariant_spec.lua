-- skin_count_invariant_spec.lua — t_f2571ca7, defect B.
--
-- The report: one skin window, and the beast block printed "skinned: 2".
-- Measured by Mira from the owner's account SavedVariables
-- (_forever_/WTF/Account/JERMTHE1/SavedVariables/MightiePack.lua,
-- NodeTrailDB.skinning, schema 2) the store keeps two records of the same
-- history in two places, and they disagreed in both directions:
--
--   cid 2957   4 records skinned=true   bucket (skinned=0, windows=0, corpses=1)
--   cid 2954   3 records skinned=true   bucket (skinned=4, windows=4, corpses=21)
--   cid 3125   2 records skinned=true   one of them has no skin loot window
--
-- This spec pins ONE authoritative answer and the three clauses that keep it
-- honest. The rule implemented here, and the reason for each part:
--
--   1. THE TOTALS ROW IS AUTHORITATIVE. `creatures[cid]` is the only store
--      that never evicts (schema 2, t_e3ea3698); the `records` ring is the
--      newest 100 corpses and is route data. So a bucket that is AHEAD of its
--      records is history that outlived the ring — cid 2954's 4 is right and
--      its 3 ring records are a window, not a contradiction (section 2).
--
--   2. THE DISPLAY MAY NEVER BE BEHIND THE EVIDENCE IN HAND. A totals row that
--      missed a fold (the cid 2957 shape) must be lifted to what the records
--      still prove; that is a read-side derivation, no rewrite of the save
--      (section 1).
--
--   3. A SKIN NEEDS EVIDENCE. A record counts as a skinned corpse only when it
--      carries a skin loot window (skinLootOpens >= 1), skin items from one, or
--      a successful 8613 cast pinned to it (skinCastAt/skinSpellID). A mark
--      with none of those is not proof and is never counted — not at the seed
--      fold (section 4) and not from the ring (section 3).
--
--      NOTE the case the report names as "skinned with no window at all" is
--      cid 3125's ..AA020CC9AE, and that record HAS a pinned cast:
--      skinCastAt=599308.978, skinSpellID=8613 on a corpse it had already
--      looted. This client can never loot a skin window the client did not
--      open, and the owner asked for the opposite fix on t_a2f44fb2 ("it should
--      still count the skin even if i dont get loot"). So "skinned with no
--      window" is a real skin, not a phantom, and section 5 pins that it keeps
--      counting. Only a mark with NO cast behind it is a phantom.
--
--   4. NOTHING IS SUBTRACTED FROM THE TOTALS. A phantom mark that is still in
--      the ring could, in principle, have been counted by an old seed; but a
--      real skin whose record has been evicted is indistinguishable from it,
--      and the hard rule is that gathered history is never dropped. So the
--      read correction only ever moves UP, and the phantom is kept out of the
--      ring side instead (section 3).
--
-- RED on the tree this spec was written against: sections 1, 3, 4 and 7 fail
-- (1 and 3 read 0 where the records prove 4 and 1; 4 seeds a phantom and reads
-- 2; 7's R:Invariants does not exist yet). Sections 2, 5 and 6 are pins on the
-- directions that must NOT change, so a fix cannot buy the red sections by
-- deriving everything from the ring or by deleting no-window skins.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

-- ── the client ──────────────────────────────────────────────────────────
local clock = 100
GetTime = function() return clock end
GetUnitName = function(u) if u == "player" then return "Mightie" end return nil end
GetRealmName = function() return "Forever" end
NodeTrailDB = { skinning = { enabled = true } }

local pkg = {}
local function loadFile(path)
  local chunk, err = loadfile(root .. "/MightiePack/" .. path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return false end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. path .. ": " .. tostring(e))
  return ok
end

loadFile("Modules/NodeTrail/Data/SkinHints.lua")
loadFile("Modules/Skinning/Record.lua")

local ns = type(pkg.NodeTrail) == "table" and pkg.NodeTrail or {}
local H = ns.SkinHints
local R = type(pkg.Skinning) == "table" and pkg.Skinning.Recorder or nil

check(type(H) == "table" and type(H.Aggregate) == "function",
  "0: Data/SkinHints.lua loaded (the beast panel's aggregator)")
check(type(R) == "table" and type(R.OnKill) == "function",
  "0: the skinning recorder is loaded (this spec drives the real one)")

local KEY = "Mightie-Forever"

-- ── store fixtures (the three shapes Mira measured, plus the flow) ─────
local function rec(guid, cid, o)
  o = o or {}
  return {
    guid = guid,
    creatureID = cid,
    killObserved = o.kill ~= false,
    corpseLootOpens = 1,
    corpseItems = {},
    skinned = o.skinned,
    skinLootOpens = o.windows,
    skinItems = o.items or {},
    skinCastAt = o.castAt,
    skinSpellID = o.spellID,
    map = o.map,
    x = o.x,
    y = o.y,
  }
end

local LEATHER = { id = 2318, name = "Light Leather", qty = 1 }

local function use(schema, rows, recs)
  local b = {
    schema = schema,
    records = {},
    order = {},
    creatures = rows or {},
    counts = {},
  }
  for i = 1, #(recs or {}) do
    b.records[recs[i].guid] = recs[i]
    b.order[i] = recs[i].guid
  end
  NodeTrailDB = { skinning = { enabled = true, schema = 2,
    chars = { [KEY] = b } } }
  return b
end

local function aggregate(cid)
  local ok, agg = pcall(H.Aggregate, cid)
  if not ok then
    check(false, "H.Aggregate(" .. tostring(cid) .. ") raised: " .. tostring(agg))
    return nil
  end
  return agg
end

local function panelLeft(cid, name)
  local bits = {}
  for _, r in ipairs(H.Rows(cid, name) or {}) do
    if type(r.left) == "string" then bits[#bits + 1] = r.left end
  end
  return table.concat(bits, "\n")
end

if type(H) == "table" and type(R) == "table" then
  -- ══════════════════════════════════════════════════════════════════
  -- 1. cid 2957: the bucket never folded its records.
  --    Four records are skinned; the bucket says (0, 0, 1).
  --    The panel must render 4. Direction pinned: the records lift the
  --    totals UP.
  -- ══════════════════════════════════════════════════════════════════
  do
    local CID = 2957
    local recs = {}
    for i = 1, 4 do
      recs[i] = rec(("Creature-0-7072-1-48-2957-%04X"):format(i), CID,
        { skinned = true, windows = 1, items = { LEATHER }, map = 1411, x = 0.5, y = 0.5 })
    end
    use(2, {
      [CID] = { corpses = 1, kills = 1, skinned = 0, skinWindows = 0, skin = {} },
    }, recs)
    local agg = aggregate(CID)
    check(agg and agg.skinned == 4,
      "1: the bucket is lifted to the 4 skinned records it holds (got "
      .. tostring(agg and agg.skinned) .. ")")
    check(agg and agg.skinWindows == 4,
      "1: the windows are lifted with it (got " .. tostring(agg and agg.skinWindows) .. ")")
    local text = panelLeft(CID, "Plainstrider")
    check(text:find("skinned: 4", 1, true) ~= nil,
      "1: the beast block prints 'skinned: 4' (got:\n" .. text .. ")")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- 2. cid 2954: the bucket is AHEAD of its records (4 vs 3), because
  --    one skinned corpse left the 100-record ring. That is history
  --    outliving the ring, not an error: 4 must survive.
  --    Direction pinned: the records never pull the totals DOWN.
  -- ══════════════════════════════════════════════════════════════════
  do
    local CID = 2954
    local recs = {}
    for i = 1, 20 do
      recs[i] = rec(("Creature-0-6834-1-3-2954-%04X"):format(i), CID)
    end
    for i = 1, 3 do
      recs[i].skinned = true
      recs[i].skinLootOpens = 1
      recs[i].skinItems = { LEATHER }
    end
    use(2, {
      [CID] = { corpses = 21, kills = 21, skinned = 4, skinWindows = 4, skin = {} },
    }, recs)
    local agg = aggregate(CID)
    check(agg and agg.skinned == 4,
      "2: history that outlived the ring is not deleted (got "
      .. tostring(agg and agg.skinned) .. ", want 4 — the ring only holds 3)")
    check(agg and agg.skinned ~= 3,
      "2: the ring is a window, not the answer")
    local text = panelLeft(CID, "Bristleback Battleboar")
    check(text:find("skinned: 4", 1, true) ~= nil,
      "2: the beast block keeps 'skinned: 4' (got:\n" .. text .. ")")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- 3. a mark with no window and no cast is not a skin.
  --    Two records claim skinned, only one has a window behind it.
  --    The ring must count one, never two. Direction pinned: the ring
  --    never INVENTS a skin from a bare mark.
  -- ══════════════════════════════════════════════════════════════════
  do
    local CID = 3126
    local recs = {
      rec("Creature-0-6829-1-3-3126-AAAA", CID,
        { skinned = true, windows = 1, items = { LEATHER } }),
      rec("Creature-0-6829-1-3-3126-BBBB", CID,
        { skinned = true }), -- bare mark: no window, no cast, no items
    }
    use(2, {}, recs)
    local agg = aggregate(CID)
    check(agg and agg.skinned == 1,
      "3: a bare 'skinned' mark is not a skin (got "
      .. tostring(agg and agg.skinned) .. ", want 1)")
    check(agg and agg.skinned ~= 2,
      "3: the phantom mark must not raise the count to 2")
    check(agg and agg.skinWindows == 1,
      "3: one window is one window (got " .. tostring(agg and agg.skinWindows) .. ")")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- 4. the seed fold (schema 1 -> 2) also refuses a bare mark.
  --    Same two records, but in a schema 1 bucket: the upgrade seeds
  --    the totals, and the phantom must not be seeded. The record
  --    itself is left untouched (gathered history is not rewritten).
  -- ══════════════════════════════════════════════════════════════════
  do
    local CID = 2966
    local real = rec("Creature-0-6829-1-3-2966-CCCC", CID,
      { skinned = true, windows = 1, items = { LEATHER } })
    local bare = rec("Creature-0-6829-1-3-2966-DDDD", CID, { skinned = true })
    local b = use(1, nil, { real, bare })
    local agg = aggregate(CID)
    check(agg and agg.skinned == 1,
      "4: the schema-1 seed counts only the evidenced skin (got "
      .. tostring(agg and agg.skinned) .. ", want 1)")
    local row = b.creatures and b.creatures[CID]
    check(type(row) == "table" and row.skinned == 1,
      "4: the seeded totals row says 1 (got "
      .. tostring(type(row) == "table" and row.skinned) .. ")")
    check(b.records[bare.guid] ~= nil and b.records[bare.guid].skinned == true,
      "4: the bare record is left exactly as stored (no rewrite of history)")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- 5. cid 3125 on disk: a skinned corpse whose skin window never
  --    opened, but whose successful 8613 cast is pinned to it
  --    (skinCastAt=599308.978). That IS a skin — the owner asked for it
  --    on t_a2f44fb2. Direction pinned: a cast-backed skin counts, so
  --    the count is 2 skins over 1 window, not 1.
  -- ══════════════════════════════════════════════════════════════════
  do
    local CID = 3125
    local withWindow = rec("Creature-0-6829-1-3-3125-A4EE0C6171", CID,
      { skinned = true, windows = 1, items = { LEATHER },
        castAt = 599262.081, spellID = 8613 })
    local castOnly = rec("Creature-0-6829-1-3-3125-AA020CC9AE", CID,
      { skinned = true, castAt = 599308.978, spellID = 8613 })
    use(1, nil, { withWindow, castOnly })
    local agg = aggregate(CID)
    check(agg and agg.skinned == 2,
      "5: a skin with a pinned 8613 cast but no loot window still counts (got "
      .. tostring(agg and agg.skinned) .. ", want 2; a 'fix' that prints 1 has deleted a real skin)")
    check(agg and agg.skinWindows == 1,
      "5: only the one window is a window (got " .. tostring(agg and agg.skinWindows) .. ")")
    local text = panelLeft(CID, "Clattering Scorpid")
    check(text:find("skinned: 2", 1, true) ~= nil,
      "5: the beast block prints 'skinned: 2' (got:\n" .. text .. ")")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- 6. the count survives the ring: three skinned corpses that are
  --    evicted by 130 later kills still read 3.
  --    Direction pinned: no derivation may shrink gathered history.
  -- ══════════════════════════════════════════════════════════════════
  do
    local CID = 2970
    NodeTrailDB = { skinning = { enabled = true } }
    local guids = {}
    clock = 100
    for i = 1, 3 do
      guids[i] = ("Creature-0-7072-1-48-2970-%04X"):format(i)
      clock = clock + 1
      -- no map position: these are the skinned records the ring drops first
      R:OnKill({ guid = guids[i], t = clock })
      R:OnSkinLoot({
        guid = guids[i], t = clock + 0.1, cast = true, spellID = 8613,
        castAt = clock + 0.05, items = { LEATHER },
      })
    end
    clock = 200
    for i = 1, 130 do
      clock = clock + 1
      R:OnKill({ guid = ("Creature-0-7072-1-48-9999-%04X"):format(i), t = clock })
    end
    for i = 1, 3 do
      check(R:Find(guids[i]) == nil,
        "6: the fixture really evicted skinned record " .. i .. " from the ring")
    end
    local agg = aggregate(CID)
    check(agg and agg.skinned == 3,
      "6: three skinned corpses read 3 after their records left the ring (got "
      .. tostring(agg and agg.skinned) .. ")")
    local text = panelLeft(CID, "Plainstrider")
    check(text:find("skinned: 3", 1, true) ~= nil,
      "6: the beast block prints 'skinned: 3' (got:\n" .. text .. ")")
  end

  -- ══════════════════════════════════════════════════════════════════
  -- 7. the fold contract is explicit and checkable: R:Invariants reports
  --    a totals row that is behind its own records, and reports nothing
  --    for a store that agrees with itself.
  -- ══════════════════════════════════════════════════════════════════
  do
    local CID = 2958
    local recs = {}
    for i = 1, 2 do
      recs[i] = rec(("Creature-0-7072-1-48-2958-%04X"):format(i), CID,
        { skinned = true, windows = 1, items = { LEATHER } })
    end
    local behind = use(2, {
      [CID] = { corpses = 2, kills = 2, skinned = 0, skinWindows = 0, skin = {} },
    }, recs)
    check(type(R.Invariants) == "function",
      "7: the recorder publishes R:Invariants (the fold contract as a function)")
    if type(R.Invariants) == "function" then
      local ok, list = pcall(R.Invariants, R, behind)
      check(ok and type(list) == "table",
        "7: R:Invariants returns a list: " .. tostring(list))
      if ok and type(list) == "table" then
        check(#list >= 1,
          "7: a bucket that never counted its records is reported (got 0 violations)")
        local joined = table.concat(list, " | ")
        check(joined:find("2958", 1, true) ~= nil,
          "7: the violation names the cid (got: " .. joined .. ")")
      end
    end

    local agreed = use(2, {
      [CID] = { corpses = 2, kills = 2, skinned = 2, skinWindows = 2, skin = {} },
    }, recs)
    if type(R.Invariants) == "function" then
      local ok, list = pcall(R.Invariants, R, agreed)
      check(ok and type(list) == "table" and #list == 0,
        "7: a consistent store reports no violations (got "
        .. (ok and type(list) == "table" and table.concat(list, " | ") or tostring(list)) .. ")")
    end
  end
end

if failed > 0 then
  io.stderr:write(failed .. " failed\n")
  os.exit(1)
end
print("ok")
