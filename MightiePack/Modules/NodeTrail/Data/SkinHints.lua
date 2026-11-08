-- NodeTrail — what a beast's CORPSE and its SKINNING have yielded
-- (t_c0221fd7).
--
-- Mightie: "we are missing the skinning tooltip. we should have some
-- information when hovering over beasts that says what we might get if we kill
-- it and skin it. Same as herbing just another step in the middle."
--
-- The herb block can lean on a researched drop table (HerbData.NODES); a beast
-- has nothing of the sort, and this file never invents one. Every number it
-- prints is an aggregate of OUR OWN recorded corpses:
--
--   NodeTrailDB.skinning.chars[<Name-Realm>].records[<corpse GUID>]
--
-- which Modules/Skinning/Record.lua already writes (creatureID, corpseItems,
-- skinItems, killObserved, skinned, skinLootOpens). This file only READS that
-- store: it never creates a bucket, never writes a key, and never changes the
-- format — a tooltip must be able to run on a character that has no records
-- yet without leaving an empty bucket in the saved variables.
--
-- Aggregation is per CREATURE (creatureID), not per corpse: the store is one
-- record per corpse, and the question "what does a Clattering Scorpid give" is
-- answered across every corpse of that creature we have seen. Two consequences
-- the renderer keeps honest:
--
--   * `kills seen` counts the records whose death we actually observed
--     (rec.killObserved), and `skinned` counts the records a successful 8613
--     cast was pinned to (rec.skinned). They are different numbers, which is
--     the whole point of the totals line.
--   * a percentage is only printed once the sample is big enough to mean
--     something — the same PERSONAL_MIN floor the herb block uses. Below it the
--     row carries the COUNT only. No baseline, no "known drop rate", no rate is
--     ever computed from a thin sample.
--
-- SECRET strings: creature and item names can arrive as secret values on this
-- client (a secret may be shown but never measured, concatenated or formatted).
-- The creature name therefore travels to the panel in its own display-only slot
-- and is never put into a string here; an item name is only used when
-- `issecretvalue` says it is not secret, and `item <id>` (our own literal) is
-- the last resort.
local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

local H = {}
ns.SkinHints = H

-- Fallback for the evidence floor when HerbData is not loaded (it is in the
-- TOC, so this is only for a spec or a partial load). The VALUE always comes
-- from HerbData.PERSONAL_MIN when that module is there, so the two blocks can
-- never disagree about what "enough observations" means.
H.DEFAULT_MIN = 10

H._diag = {}

local function isSecret(v)
  if type(issecretvalue) ~= "function" then return false end
  local ok, s = pcall(issecretvalue, v)
  return ok and s == true
end

-- ── the stores this file reads ────────────────────────────────────────────
-- Skinning is NodeTrail's sub-feature but its files load AFTER NodeTrail's UI
-- (see MightiePack.toc), so the recorder is resolved at CALL time, never at
-- load. A missing recorder is reported, never guessed around: without it there
-- is no honest way to key a record by creature.
function H.Recorder()
  local skin = pkg.Skinning
  if type(skin) ~= "table" then return nil end
  local R = skin.Recorder
  if type(R) ~= "table" then return nil end
  return R
end

function H.Min()
  local herb = ns.HerbData
  local min = type(herb) == "table" and tonumber(herb.PERSONAL_MIN) or nil
  if type(min) ~= "number" or min < 1 then
    return H.DEFAULT_MIN
  end
  return math.floor(min + 0.5)
end

-- The per-character bucket, READ ONLY. R:GetDB() would create it (and write
-- `.chars[key] = {}` into the saved variables the first time a beast is
-- hovered); a tooltip reading data must not do that, so the shape is checked
-- here and nothing is created.
function H.Bucket()
  local R = H.Recorder()
  if type(R) ~= "table" or type(R.CharKey) ~= "function" then
    H._diag.bucket = "the skinning recorder is not loaded (Modules/Skinning/Record.lua)"
    return nil
  end
  if type(NodeTrailDB) ~= "table" then
    H._diag.bucket = "no saved variables yet"
    return nil
  end
  local store = NodeTrailDB.skinning
  if type(store) ~= "table" then
    H._diag.bucket = "NodeTrailDB.skinning is not set — the recorder never wrote one"
    return nil
  end
  if type(store.chars) ~= "table" then
    H._diag.bucket = "NodeTrailDB.skinning.chars is not set"
    return nil
  end
  local ok, key = pcall(R.CharKey)
  if not ok or type(key) ~= "string" or key == "" then
    H._diag.bucket = "this character's name could not be read, so no bucket can be named"
    return nil
  end
  local b = store.chars[key]
  H._diag.key = key
  if type(b) ~= "table" then
    H._diag.bucket = "no skinning bucket for " .. key .. " yet"
    return nil
  end
  if type(b.records) ~= "table" then
    H._diag.bucket = "the bucket for " .. key .. " carries no records table"
    return nil
  end
  H._diag.bucket = nil
  return b
end

-- The NPC id of a hovered creature, from UnitGUID. The recorder owns the parse
-- (R.CreatureID: the creature entry is the second-to-last field, and a secret
-- GUID is never parsed at all) — a second copy here would be a second answer to
-- the same question.
function H.CreatureID(guid)
  local R = H.Recorder()
  if type(R) ~= "table" or type(R.CreatureID) ~= "function" then
    return nil
  end
  local ok, id = pcall(R.CreatureID, guid)
  if ok and type(id) == "number" then
    return id
  end
  return nil
end

-- ── aggregation over our own observations ────────────────────────────────
local function addItems(byID, order, items)
  if type(items) ~= "table" then
    return
  end
  for i = 1, #items do
    local it = items[i]
    if type(it) == "table" and type(it.itemID) == "number" and it.itemID > 0 then
      local row = byID[it.itemID]
      if not row then
        row = { itemID = it.itemID, count = 0, seen = 0, name = nil }
        byID[it.itemID] = row
        order[#order + 1] = row
      end
      local qty = tonumber(it.quantity) or 1
      if qty < 1 then qty = 1 end
      row.count = row.count + qty
      -- `seen` is the number of RECORDS that carried this item, which is the
      -- only denominator a percentage may use: `count` is a quantity and two
      -- hides from one corpse must not read as two kills.
      row.seen = row.seen + 1
      if row.name == nil and type(it.name) == "string" and it.name ~= ""
        and not isSecret(it.name) then
        row.name = it.name
      end
    end
  end
end

-- Biggest yield first; ties broken by item id so the block reads the same on
-- every hover (pairs() over the record map is unordered).
local function sorted(order)
  table.sort(order, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.itemID < b.itemID
  end)
  return order
end

-- Returns agg or nil:
--   agg = { records, kills, skinned, skinWindows,
--           corpse = { {itemID, count, seen, name}, ... },
--           skin   = { ... } }
-- The denominator a percentage may use is `kills` (corpse side) and `skinned`
-- (skin side) — the same two numbers the totals line prints, so the block can
-- never divide by a sample it does not show.
function H.Aggregate(cid)
  if type(cid) ~= "number" then
    return nil
  end
  local bucket = H.Bucket()
  if not bucket then
    return nil
  end
  local agg = {
    records = 0, kills = 0, skinned = 0, skinWindows = 0,
    corpse = {}, skin = {},
  }
  local byCorpse, bySkin = {}, {}
  for _, rec in pairs(bucket.records) do
    -- `creatureID` is the recorder's own field; a record whose id this client
    -- could not derive (R.CreatureID returned nil) matches nothing.
    if type(rec) == "table" and type(rec.creatureID) == "number"
      and rec.creatureID == cid then
      agg.records = agg.records + 1
      if rec.killObserved == true then
        agg.kills = agg.kills + 1
      end
      if rec.skinned == true then
        agg.skinned = agg.skinned + 1
      end
      local opens = tonumber(rec.skinLootOpens) or 0
      if opens < 0 then opens = 0 end
      if opens > 0 then
        agg.skinWindows = agg.skinWindows + opens
      elseif type(rec.skinItems) == "table" and #rec.skinItems > 0 then
        -- Items with no window counter (an older record): the window existed.
        agg.skinWindows = agg.skinWindows + 1
      end
      addItems(byCorpse, agg.corpse, rec.corpseItems)
      addItems(bySkin, agg.skin, rec.skinItems)
    end
  end
  sorted(agg.corpse)
  sorted(agg.skin)
  H._diag.agg = ("cid=%d records=%d kills=%d skinned=%d skin-windows=%d")
    :format(cid, agg.records, agg.kills, agg.skinned, agg.skinWindows)
  return agg
end

-- ── the client's own answer, if this client has one ───────────────────────
-- The card asks for "skinnable / not skinnable" from the client's creature
-- data IF it exposes one, MEASURED first and never assumed. This is that
-- measurement: the calls that could answer it are looked up by name and called
-- only when they exist, and only a real boolean is accepted.
--
-- MEASURED on this client (build 16001, `strings -a Wow.exe` on
-- `_forever_/Wow.exe`): `UnitIsSkinnable`, `IsUnitSkinnable` and `C_UnitInfo`
-- are NOT compiled in (0 matches), so nothing here answers skinnability — the
-- line comes from our own skin windows, and /nt ttdiag says so by name. The
-- client DOES carry the vanilla tooltip strings `UNIT_SKINNABLE_LEATHER`,
-- `UNIT_SKINNABLE_HERB`, `UNIT_SKINNABLE_ROCK`, `UNIT_SKINNABLE_BOLTS` and
-- `SPELL_FAILED_TARGET_UNSKINNABLE`, i.e. it can draw a "Skinnable" line in its
-- OWN tooltip; reading that line would mean matching CLIENT text, which is
-- exactly the read a secret value raises on, so it is deliberately not done
-- here. A wrong "no" would hide the block on a real beast.
H.CLIENT_SKIN_CALLS = { "UnitIsSkinnable", "IsUnitSkinnable" }

function H.SkinFlag(unit)
  unit = unit or "mouseover"
  local tried = {}
  for _, n in ipairs(H.CLIENT_SKIN_CALLS) do
    local f = _G[n]
    if type(f) ~= "function" then
      tried[#tried + 1] = n .. " absent"
    else
      local ok, v = pcall(f, unit)
      if ok and (v == true or v == false) then
        H._diag.flag = n .. "=" .. tostring(v)
        return v, n
      end
      tried[#tried + 1] = ok and (n .. " answered no boolean") or (n .. " raised")
    end
  end
  local detail = table.concat(tried, ", ")
  H._diag.flag = "no client call answers skinnability (" .. detail .. ")"
  return nil, detail
end

-- ── item names ────────────────────────────────────────────────────────────
-- "Leather/hide names come from the client's item data, not from a hardcoded
-- table": GetItemInfo(id) is asked first, the name the loot slot itself
-- reported (stored on the record) second, and only when neither names the item
-- does the row fall back to our own literal `item <id>`. A secret name is
-- skipped rather than measured — the panel measures the label it is given.
function H.ItemName(item)
  if type(item) ~= "table" then
    return "item ?"
  end
  local id = item.itemID
  local name = nil
  if type(id) == "number" and type(GetItemInfo) == "function" then
    local ok, n = pcall(GetItemInfo, id)
    if ok and type(n) == "string" and n ~= "" and not isSecret(n) then
      name = n
    end
  end
  if name == nil and type(item.name) == "string" and item.name ~= ""
    and not isSecret(item.name) then
    name = item.name
  end
  if name == nil then
    name = "item " .. tostring(id)
    H._diag.nameless = (H._diag.nameless or 0) + 1
  end
  return name
end

-- ── the block, in the card's order ────────────────────────────────────────
-- Rows are the panel's own shape: { left = <our text>, right = <our text> } for
-- a two-column row, and { name = <CLIENT string> } for the creature name —
-- which is display-only, never measured, never concatenated (see
-- TooltipPanel's row contract).
--
-- 1 creature name · 2 skinnable (only when known) · 3 corpse drops ·
-- 4 skinning results · 5 kills/skins seen.
local function pct(seen, total)
  if total <= 0 then return nil end
  local v = math.floor(seen / total * 100 + 0.5)
  if v < 0 then v = 0 end
  if v > 100 then v = 100 end
  return v
end

local function itemRows(rows, list, samples, label)
  if #list == 0 then
    return
  end
  local min = H.Min()
  rows[#rows + 1] = { left = label }
  -- A percentage is printed only when the sample is big enough to mean
  -- something AND the item cannot have been seen more often than the sample it
  -- is compared against (a loot-only record with no observed death would
  -- otherwise print 120%). Below that the row is a count, which is a fact.
  local enough = samples >= min
  for _, it in ipairs(list) do
    local left = H.ItemName(it) .. " x" .. tostring(it.count)
    local right = nil
    if enough and it.seen <= samples then
      local p = pct(it.seen, samples)
      if p then
        right = tostring(p) .. "% (yours)"
      end
    end
    rows[#rows + 1] = { left = left, right = right }
  end
end

function H.Rows(cid, creatureName)
  local rows = {}
  local nameOK = creatureName ~= nil
    and (isSecret(creatureName)
      or (type(creatureName) == "string" and creatureName ~= ""))
  if nameOK then
    -- The client's own name, in its own slot: see the row contract above.
    rows[#rows + 1] = { name = creatureName }
  end
  local agg = H.Aggregate(cid)
  if not agg or agg.records == 0 then
    -- Never zeros dressed as data: a creature we have no corpse for says so.
    rows[#rows + 1] = { left = "no observations here yet" }
    return rows, nil
  end
  -- 2) Skinnable — only when we KNOW. A client call that answers a boolean
  -- wins; otherwise our own skin windows are the evidence, and no skin window
  -- yet means we say nothing (five kills we never skinned is not evidence that
  -- a creature is unskinnable).
  local flag = H.SkinFlag("mouseover")
  if flag == true then
    rows[#rows + 1] = { left = "skinnable" }
  elseif flag == false then
    rows[#rows + 1] = { left = "not skinnable" }
  elseif agg.skinWindows > 0 then
    rows[#rows + 1] = {
      left = "skinnable · skin windows recorded: " .. tostring(agg.skinWindows),
    }
  end
  -- 3) what the corpse gave — the denominator is the kills we SAW.
  itemRows(rows, agg.corpse, agg.kills, "corpse loot")
  -- 4) what skinning gave — the denominator is the corpses we SKINNED.
  itemRows(rows, agg.skin, agg.skinned, "skinned")
  -- 5) how thin the evidence is.
  rows[#rows + 1] = {
    left = "kills seen: " .. tostring(agg.kills) .. " · skinned: " .. tostring(agg.skinned),
  }
  return rows, agg
end

-- ── /nt ttdiag ────────────────────────────────────────────────────────────
-- What this file measured and why a beast block may be empty. No client string
-- is formatted or measured here: names are counts, keys and our own literals.
function H.Diag()
  local out = {}
  local R = H.Recorder()
  out[#out + 1] = "recorder: " .. (type(R) == "table"
    and ("loaded (Modules/Skinning/Record.lua" .. (type(R.CharKey) == "function" and ", CharKey present" or ", CharKey ABSENT") .. ")")
    or "NOT loaded")
  out[#out + 1] = "evidence floor: " .. tostring(H.Min())
    .. " (HerbData.PERSONAL_MIN — below it, counts only)"
  local bucket = H.Bucket()
  if bucket == nil then
    out[#out + 1] = "store: " .. tostring(H._diag.bucket or "unavailable")
  else
    local n = 0
    for _ in pairs(bucket.records) do n = n + 1 end
    out[#out + 1] = ("store: %d corpse record(s) for %s"):format(
      n, tostring(H._diag.key or "this character"))
  end
  if H._diag.agg then
    out[#out + 1] = "last hover: " .. H._diag.agg
  else
    out[#out + 1] = "last hover: no beast aggregate computed yet"
  end
  out[#out + 1] = "skinnability: " .. tostring(H._diag.flag or "not probed yet")
  if (H._diag.nameless or 0) > 0 then
    out[#out + 1] = ("item names: %d row(s) fell back to \"item <id>\" — the client named neither"):format(H._diag.nameless)
  end
  return out
end

return H
