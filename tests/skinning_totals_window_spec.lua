-- skinning_totals_window_spec.lua — t_6976540d (the window path must count).
--
-- The defect, measured on 2685138: #17 added the per-creature totals the beast
-- panel reads, and #18 made an UNPINNED 8613 cast return early — deliberately,
-- because a cast with no pin names no corpse. The two changes together split
-- one increment in two. R:OnSkinCast increments row.skinned only when the cast
-- carries a GUID; R:OnSkinLoot sets rec.skinned = true when it claims the
-- window (ev.cast == true) but never incremented the row. Everything the probe
-- sends on the normal path is an unpinned cast, so every skin landed in
-- record.skinned and in skinWindows and MISSED skinned.
--
-- Live report: a player skinned 5 Plainstriders on a fresh character and the
-- beast panel said "kills seen: 18 · skinned: 3".
--
-- This spec drives the REAL entry points — R:OnKill, R:OnSkinCast,
-- R:OnSkinLoot, R:Store, R:Upgrade and H.Aggregate/H.Rows — with no
-- hand-written totals row and no re-implementation of the arithmetic, and
-- covers the four ways a skin can be observed:
--
--   1. the window claims the skin (unpinned cast, then OnSkinLoot cast = true):
--      the record is skinned AND totals.skinned counts it once;
--   2. both paths observe one corpse (pinned cast, then a window that claims
--      it, then a second window that claims it): totals.skinned is 1, not 2
--      and not 3;
--   3. a skin window with NO successful cast behind it (cast ~= true): nothing
--      is marked and nothing is counted;
--   4. a schema 1 bucket upgraded in place seeds totals.skinned = N from its N
--      skinned records, and a skin observed after the upgrade takes it to
--      N + 1 — never N + 2, including when the claimed corpse is one the
--      seeding already counted.
--
-- RED before the change: sections 1, 2 and 4 report totals.skinned = 0 (the
-- window path increments nothing), and the panel row reads "skinned: 0". Each
-- check is written to report that as a FAILED check rather than a traceback.
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

-- The sub-toggle ON, so the recorder persists into the character bucket the
-- beast panel reads (NodeTrail owns that key; this spec sets it directly).
NodeTrailDB = { skinning = { enabled = true } }

-- ── load (the addon's own order: NodeTrail first, Skinning after) ────────
local pkg = {}
local function loadFile(path)
  local chunk, err = loadfile(root .. "/MightiePack/" .. path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return false end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. path .. ": " .. tostring(e))
  return ok
end

loadFile("Modules/NodeTrail/Route/Cluster.lua")
loadFile("Modules/NodeTrail/Route/Build.lua")
loadFile("Modules/NodeTrail/Route/SkinRoute.lua")
loadFile("Modules/NodeTrail/Data/SkinHints.lua")
loadFile("Modules/Skinning/Record.lua")

local ns = type(pkg.NodeTrail) == "table" and pkg.NodeTrail or {}
local H = ns.SkinHints
local R = type(pkg.Skinning) == "table" and pkg.Skinning.Recorder or nil

check(type(H) == "table" and type(H.Aggregate) == "function",
  "0: Data/SkinHints.lua loaded (the beast panel's aggregator)")
check(type(R) == "table" and type(R.OnSkinLoot) == "function",
  "0: the skinning recorder is loaded (this spec drives the real one)")
if type(R) ~= "table" or type(H) ~= "table" then
  io.stderr:write("the recorder or the panel did not load — nothing can be measured\n")
  os.exit(1)
end

-- ── helpers ─────────────────────────────────────────────────────────────
-- A creature entry in the GUID's second-to-last field is what R.CreatureID
-- parses, so every corpse below belongs to a known id.
local seq = 0
local function guidFor(cid)
  seq = seq + 1
  return ("Creature-0-7072-1-48-%d-%012X"):format(cid, seq)
end

local function kill(guid, t)
  R:OnKill({ guid = guid, t = t, map = 1411, x = 0.5, y = 0.5, zone = "Desolace" })
end

local function totalsRow(cid)
  local store = select(1, R:Store())
  local row = type(store.creatures) == "table" and store.creatures[cid] or nil
  return type(row) == "table" and row or {}
end

local function panelRow(cid, name, label)
  for _, r in ipairs(H.Rows(cid, name) or {}) do
    if type(r.left) == "string" and r.left:find(label, 1, true) then return r.left end
  end
  return nil
end

-- ════════════════════════════════════════════════════════════════════════
-- 1. The window claims the skin: the reported replay, exactly
-- ════════════════════════════════════════════════════════════════════════
local A_CID = 3124   -- Plainstrider
local aGuid = guidFor(A_CID)
kill(aGuid, 100)
R:OnSkinCast({ t = 101, spellID = 8613 })   -- no pin: what the probe sends after #18
R:OnSkinLoot({
  guid = aGuid, t = 101.5, cast = true, spellID = 8613, castAt = 101,
  items = { { id = 2934, name = "Ruined Leather Scraps", qty = 1 } },
})

local aRec = R:Find(aGuid)
check(type(aRec) == "table" and aRec.skinned == true,
  "1: the corpse is marked skinned (record.skinned)")
check(type(aRec) == "table" and type(aRec.skinItems) == "table" and #aRec.skinItems == 1,
  "1: the corpse keeps its skin item (skinItems = 1)")

local aRow = totalsRow(A_CID)
check(aRow.skinned == 1,
  "1: the WINDOW path increments the creature's skinned total (got "
  .. tostring(aRow.skinned) .. ")")
check(aRow.skinWindows == 1,
  "1: the window is still counted as a skin window (got "
  .. tostring(aRow.skinWindows) .. ")")

local aAgg = H.Aggregate(A_CID)
check(type(aAgg) == "table" and aAgg.skinned == 1,
  "1: the panel's aggregate reports 1 skinned corpse (got "
  .. tostring(type(aAgg) == "table" and aAgg.skinned) .. ")")
check(panelRow(A_CID, "Plainstrider", "skinned: 1") == "skinned: 1",
  "1: the panel line reads skinned: 1 (got: "
  .. tostring(panelRow(A_CID, "Plainstrider", "skinned:")) .. ")")

-- ════════════════════════════════════════════════════════════════════════
-- 2. Both paths, ONE corpse, one count
-- ════════════════════════════════════════════════════════════════════════
local B_CID = 3125   -- Plainstrider seen by the cast path first
local bGuid = guidFor(B_CID)
kill(bGuid, 200)
R:OnSkinCast({ guid = bGuid, t = 201, spellID = 8613 })     -- pinned: counted here
local bAfterCast = totalsRow(B_CID).skinned
check(bAfterCast == 1,
  "2: a pinned cast counts the corpse once (got " .. tostring(bAfterCast) .. ")")
R:OnSkinLoot({ guid = bGuid, t = 201.5, cast = true, spellID = 8613, castAt = 201,
               items = { { id = 2319, name = "Medium Leather", qty = 1 } } })
local bAfterWindow = totalsRow(B_CID).skinned
check(bAfterWindow == 1,
  "2: the window that claims an already-counted corpse does not count it again (got "
  .. tostring(bAfterWindow) .. ")")
-- a re-opened corpse: a SECOND claimed window on the same guid
R:OnLootClosed(202)
R:OnSkinLoot({ guid = bGuid, t = 203, cast = true, spellID = 8613, castAt = 201,
               items = { { id = 2319, name = "Medium Leather", qty = 1 } } })
local bAfterSecond = totalsRow(B_CID).skinned
check(bAfterSecond == 1,
  "2: a second claimed window on the same corpse counts nothing more (got "
  .. tostring(bAfterSecond) .. ")")
local bAgg = H.Aggregate(B_CID)
check(type(bAgg) == "table" and bAgg.skinned == 1,
  "2: the panel reports 1 skinned corpse, not 2 (got "
  .. tostring(type(bAgg) == "table" and bAgg.skinned) .. ")")

-- ════════════════════════════════════════════════════════════════════════
-- 3. A window with no successful cast behind it marks and counts NOTHING
-- ════════════════════════════════════════════════════════════════════════
local C_CID = 3126
local cGuid = guidFor(C_CID)
kill(cGuid, 300)
R:OnSkinLoot({ guid = cGuid, t = 300.5, cast = false, spellID = 8613,
               items = { { id = 4306, name = "Silk Cloth", qty = 2 } } })
local cRec = R:Find(cGuid)
check(type(cRec) == "table" and cRec.skinned ~= true,
  "3: a window with no cast behind it does not mark the corpse skinned")
local cRow = totalsRow(C_CID)
check(cRow.skinned == 0,
  "3: a window with no cast behind it counts no skin (got "
  .. tostring(cRow.skinned) .. ")")
check(cRow.skinWindows == 1,
  "3: it is still a window (skinWindows, got " .. tostring(cRow.skinWindows) .. ")")
check(panelRow(C_CID, "Clattering Scorpid", "skinned: 0") == "skinned: 0",
  "3: the panel line still reads skinned: 0 (got: "
  .. tostring(panelRow(C_CID, "Clattering Scorpid", "skinned:")) .. ")")

-- ════════════════════════════════════════════════════════════════════════
-- 4. Schema 1 → 2 seeding counts N, and a skin after the upgrade makes N + 1
-- ════════════════════════════════════════════════════════════════════════
-- The bucket a schema 1 build left behind: a ring and nothing else, no
-- `creatures` table. 3 of the 4 corpses were skinned.
local D_CID = 3170
local SEED_KEY = "Mightie-Forever"
local seedGuids = {}
local seedRecords = {}
local seedOrder = {}
for i = 1, 4 do
  local g = ("Creature-0-7072-1-48-%d-0000000000C%d"):format(D_CID, i)
  seedGuids[i] = g
  seedOrder[i] = g
  seedRecords[g] = {
    guid = g, creatureID = D_CID, killObserved = true,
    diedAt = 400 + i, map = 1411, x = 0.5, y = 0.5, zone = "Desolace",
    skinned = i <= 3, skinSpellID = i <= 3 and 8613 or nil,
    skinLootOpens = i <= 3 and 1 or 0,
    skinItems = i <= 3 and { { itemID = 8170, quantity = 1, name = "Rugged Leather" } } or {},
    corpseItems = {}, corpseLootOpens = 0,
  }
end
NodeTrailDB = {
  skinning = {
    enabled = true,
    schema = 1,
    chars = {
      [SEED_KEY] = {
        schema = 1,
        records = seedRecords,
        order = seedOrder,
        unclassified = {},
      },
    },
  },
}

-- the panel's own read path is what upgrades a bucket in the client
local dAggSeeded = H.Aggregate(D_CID)
check(type(dAggSeeded) == "table" and dAggSeeded.skinned == 3,
  "4: the upgrade seeds the 3 skinned records (got "
  .. tostring(type(dAggSeeded) == "table" and dAggSeeded.skinned) .. ")")
local dSeedBucket = NodeTrailDB.skinning.chars[SEED_KEY]
check(type(dSeedBucket) == "table" and dSeedBucket.schema == 2,
  "4: the bucket is stamped schema 2 (got " .. tostring(
    type(dSeedBucket) == "table" and dSeedBucket.schema) .. ")")

-- a skin observed AFTER the upgrade, by the window path
local dGuidNew = guidFor(D_CID)
kill(dGuidNew, 500)
R:OnSkinCast({ t = 501, spellID = 8613 })
R:OnSkinLoot({ guid = dGuidNew, t = 501.5, cast = true, spellID = 8613, castAt = 501,
               items = { { id = 8170, name = "Rugged Leather", qty = 1 } } })
local dRow = totalsRow(D_CID)
check(dRow.skinned == 4,
  "4: a skin after the upgrade takes the seeded 3 to 4 (got "
  .. tostring(dRow.skinned) .. ")")

-- a window that claims a corpse the SEEDING already counted adds nothing
R:OnSkinLoot({ guid = seedGuids[1], t = 600, cast = true, spellID = 8613, castAt = 599,
               items = { { id = 8170, name = "Rugged Leather", qty = 1 } } })
local dRowAgain = totalsRow(D_CID)
check(dRowAgain.skinned == 4,
  "4: a claimed window on a seeded corpse is not counted again (got "
  .. tostring(dRowAgain.skinned) .. ")")

-- the unskinned seeded corpse is still not counted: a window with no cast on it
R:OnSkinLoot({ guid = seedGuids[4], t = 601, cast = false, items = {} })
check(totalsRow(D_CID).skinned == 4,
  "4: an unskinned seeded corpse with no cast stays uncounted (got "
  .. tostring(totalsRow(D_CID).skinned) .. ")")

if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("skinning_totals_window_spec: ok")
