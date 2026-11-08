local addonName, pkg = ...
pkg.NodeTrail = pkg.NodeTrail or {}
local ns = pkg.NodeTrail

local Rc = {}
ns.Recipes = Rc

function ns.GetRecipeDB()
  if type(NodeTrailDB) ~= "table" then
    ns.GetDB()
  end
  NodeTrailDB.recipes = NodeTrailDB.recipes or {}
  NodeTrailDB.recipes.alchemy = NodeTrailDB.recipes.alchemy or {}
  return NodeTrailDB.recipes
end

-- ── Two generations of trade-skill API ───────────────────────────────────
--  legacy : GetTradeSkillLine / GetNumTradeSkills / GetTradeSkillInfo /
--           GetTradeSkillNumReagents / GetTradeSkillReagentItemLink
--           — pre-Dragonflight globals, removed on mainline clients, so on
--           Forever 16001 `IsAlchemyOpen` returned false forever and the
--           tooltip sat on "Open Alchemy once…" (t_0d5badc3).
--  modern : C_TradeSkillUI.* — the live API. Its exact call surface is
--           not pinned for this client, so the candidates are probed,
--           every call is pcall'd, and unexpected shapes are skipped
--           instead of erroring. The legacy path is kept as the fallback
--           for a client that still carries it.
--
-- `Rc:APIInfo()` reports what exists; `Rc:Diag()` prints it for
-- `/nt ttdiag`; `Rc._diag` records the last scan; `Rc._error` the last
-- hard failure.

local MODERN_CALLS = {
  "GetNumRecipeIDs",
  "GetNumRecipes",
  "GetAllRecipeIDs",
  "GetRecipeIDs",
  "GetRecipeID",
  "GetRecipeIDAt",
  "GetRecipeIDByIndex",
  "GetRecipeInfo",
  "GetRecipeSchematic",
  "GetOpenTradeSkillLine",
  "GetOpenTradeSkillTab",
  "GetCurrentTradeSkillLine",
  "GetSkillLineName",
  "GetTabName",
  "GetTradeSkillLine",
}
local MODERN_ENUM = {
  GetNumRecipeIDs = 1,
  GetNumRecipes = 1,
  GetAllRecipeIDs = 1,
  GetRecipeIDs = 1,
}
local MODERN_INDEX = { "GetRecipeID", "GetRecipeIDAt", "GetRecipeIDByIndex" }
local MODERN_PROF = {
  -- The likely-live mainline calls for the OPEN profession window come
  -- first: on a current client these are the usual calls and they return
  -- a table (not a bare string). The older name-style calls stay as
  -- fallbacks for a client that still carries them (t_217033d4).
  "GetChildProfessionInfo",
  "GetBaseProfessionInfo",
  "GetOpenTradeSkillLine",
  "GetOpenTradeSkillTab",
  "GetCurrentTradeSkillLine",
  "GetSkillLineName",
  "GetTabName",
  "GetTradeSkillLine",
}
local LEGACY_CALLS = {
  "GetTradeSkillLine",
  "GetNumTradeSkills",
  "GetTradeSkillInfo",
  "GetTradeSkillNumReagents",
  "GetTradeSkillReagentItemLink",
}
-- Legacy pair that the legacy scan actually depends on.
local LEGACY_CORE = { "GetNumTradeSkills", "GetTradeSkillInfo" }

local TRADE_EVENTS = {
  "TRADE_SKILL_SHOW",
  "TRADE_SKILL_UPDATE",
  "TRADE_SKILLS_SHOW",
  "TRADE_SKILLS_UPDATE",
}

local function inList(list, v)
  for _, x in ipairs(list) do
    if x == v then
      return true
    end
  end
  return false
end

function Rc:AlchName()
  if type(GetSpellInfo) == "function" then
    local ok, n = pcall(GetSpellInfo, 2259)
    if ok and type(n) == "string" and n ~= "" then
      return n
    end
  end
  return "Alchemy"
end

-- What trade-skill API does this client actually have? Every probe is a
-- cheap existence check — no call crosses an API boundary.
function Rc:APIInfo()
  local info = {
    modern = { exists = type(C_TradeSkillUI) == "table", calls = {} },
    legacy = { exists = false, calls = {} },
    available = false,
  }
  local mod = C_TradeSkillUI
  if info.modern.exists then
    for _, n in ipairs(MODERN_CALLS) do
      if type(mod[n]) == "function" then
        table.insert(info.modern.calls, n)
      end
    end
  end
  for _, n in ipairs(LEGACY_CALLS) do
    if type(_G[n]) == "function" then
      table.insert(info.legacy.calls, n)
    end
  end
  local legacyAvail = true
  for _, n in ipairs(LEGACY_CORE) do
    if not inList(info.legacy.calls, n) then
      legacyAvail = false
      break
    end
  end
  info.legacy.exists = legacyAvail
  local modernAvail = false
  for _, n in ipairs(info.modern.calls) do
    if MODERN_ENUM[n] then
      modernAvail = true
      break
    end
  end
  info.available = legacyAvail or (info.modern.exists and modernAvail)
  return info
end

-- ── Shape-tolerant readers for the modern API ────────────────────────────
-- A reagent entry may be a number, an item link string, or a table with
-- an id-ish field; anything else is skipped, never raised.

-- The id may sit under itemID or reagentID (the live schematic slot
-- entries carry either), a bare id-ish field, an item link, or one level
-- of nesting ({ item = { itemID = 765 } }) (t_81da8886).
local ID_KEYS = { "itemID", "reagentID", "id", "itemid", "item", "reagent" }

local function idFromScalar(v)
  if type(v) == "number" then
    return v
  end
  if type(v) == "string" then
    local id = v:match("item:%s*(%d+)")
    if id then
      return tonumber(id)
    end
    local n = tonumber(v)
    if n then
      return n
    end
  end
  return nil
end

local function itemFrom(x)
  if type(x) == "number" then
    return x
  end
  if type(x) == "string" then
    local id = x:match("item:%s*(%d+)")
    if id then
      return tonumber(id)
    end
    local n = tonumber(x)
    if n then
      return n
    end
    return nil
  end
  if type(x) ~= "table" then
    return nil
  end
  for _, k in ipairs(ID_KEYS) do
    local v = x[k]
    if type(v) == "table" then
      local r = itemFrom(v)
      if r then
        return r
      end
    else
      local r = idFromScalar(v)
      if r then
        return r
      end
    end
  end
  local link = x.link
  if type(link) == "string" then
    local id = link:match("item:%s*(%d+)")
    if id then
      return tonumber(id)
    end
  end
  return nil
end

local function fromContainer(v)
  if type(v) ~= "table" then
    return nil
  end
  local out = {}
  if #v > 0 then
    -- list of entries
    for _, entry in ipairs(v) do
      local id = itemFrom(entry)
      if id then
        table.insert(out, id)
      end
    end
  else
    -- map keyed by item ID
    for k in pairs(v) do
      local id = tonumber(k)
      if id then
        table.insert(out, id)
      end
    end
  end
  if #out > 0 then
    return out
  end
  return nil
end

-- The live schematic (Forever 16001, t_81da8886) carries its reagents
-- in slots, NOT under the flat keys above:
--   reagentSlotSchematics[i].reagents[j]
-- each entry an itemID/reagentID holder, an item link, or a nested
-- id-table. A slot without its own `reagents` list is treated as the
-- reagent container itself.
local function slotReagentsFrom(t)
  if type(t) ~= "table" then
    return nil
  end
  local slots = t.reagentSlotSchematics
  if type(slots) ~= "table" then
    return nil
  end
  local out = {}
  for _, slot in ipairs(slots) do
    local list
    if type(slot) == "table" and type(slot.reagents) == "table" then
      list = fromContainer(slot.reagents)
    else
      list = fromContainer(slot)
    end
    if type(list) == "table" then
      for _, id in ipairs(list) do
        table.insert(out, id)
      end
    end
  end
  if #out > 0 then
    return out
  end
  return nil
end

local function reagentsFrom(t)
  if type(t) ~= "table" then
    return nil
  end
  local r = slotReagentsFrom(t)
  if r then
    return r
  end
  for _, key in ipairs({ "reagents", "requiredReagents", "reagentList" }) do
    r = fromContainer(t[key])
    if r then
      return r
    end
  end
  return nil
end

local function nameFrom(t)
  if type(t) ~= "table" then
    return nil
  end
  for _, k in ipairs({ "name", "recipeName", "schematicName", "title" }) do
    if type(t[k]) == "string" and t[k] ~= "" then
      return t[k]
    end
  end
  return nil
end

-- A profession call may answer as a bare name string, or as a table that
-- carries the name under any of the usual keys (the live
-- GetChildProfessionInfo / GetBaseProfessionInfo call returns a table).
-- Anything else — no recognisable name — is nil, never an error.
local function profName(r)
  if type(r) == "string" and r ~= "" then
    return r
  end
  if type(r) == "table" then
    for _, k in ipairs({ "skillLineName", "professionName", "name" }) do
      local v = r[k]
      if type(v) == "string" and v ~= "" then
        return v
      end
    end
  end
  return nil
end

local function openProfession(mod)
  for _, n in ipairs(MODERN_PROF) do
    local f = mod[n]
    if type(f) == "function" then
      local ok, r = pcall(f)
      if ok then
        local name = profName(r)
        if name ~= nil then
          return name
        end
      end
    end
  end
  return nil
end

-- Which recipe IDs does the module enumerate, and which call did it?
-- Returns (ids, enumeratorName) or (nil, nil).
local function collectModernIDs(mod, errbox)
  -- 1) a single call that returns the whole ID list
  for _, n in ipairs({ "GetAllRecipeIDs", "GetRecipeIDs" }) do
    local f = mod[n]
    if type(f) == "function" then
      local ok, r = pcall(f)
      if not ok then
        errbox.err = "C_TradeSkillUI." .. n .. ": " .. tostring(r)
      elseif type(r) == "table" and #r > 0 then
        local ids = {}
        for _, v in ipairs(r) do
          if v ~= nil then
            table.insert(ids, v)
          end
        end
        if #ids > 0 then
          return ids, n
        end
      end
    end
  end
  -- 2) a count plus an index getter
  local n
  local via
  for _, name in ipairs({ "GetNumRecipeIDs", "GetNumRecipes" }) do
    local f = mod[name]
    if type(f) == "function" then
      local count
      local ok, r = pcall(f, true) -- learnedOnly on the live API
      if ok and type(r) == "number" and r > 0 then
        count = r
      else
        if not ok then
          errbox.err = ("C_TradeSkillUI.%s: %s"):format(name, tostring(r))
        end
        local ok2, r2 = pcall(f)
        if ok2 and type(r2) == "number" and r2 > 0 then
          count = r2
        end
      end
      if count then
        n = count
        via = name
        break
      end
    end
  end
  if n then
    local ids = {}
    for i = 1, n do
      local id
      for _, gname in ipairs(MODERN_INDEX) do
        local g = mod[gname]
        if type(g) == "function" then
          local ok, r = pcall(g, i)
          if not ok then
            errbox.err = ("C_TradeSkillUI.%s: %s"):format(gname, tostring(r))
          elseif type(r) == "number" or (type(r) == "string" and r ~= "") then
            id = r
            break
          end
        end
      end
      if id ~= nil then
        table.insert(ids, id)
      end
    end
    if #ids > 0 then
      return ids, via
    end
  end
  return nil, nil
end

-- ── Can this character make it RIGHT NOW? (t_04c983cc) ───────────────────
-- Mightie: "alchemy tooltip is giving info for crafts i cant do yet." The scan
-- used to keep only the recipe NAME, so every recipe the client enumerated was
-- advertised on every herb as if it were available. Availability is therefore
-- part of the recipe record now, captured ONCE here and never recomputed
-- elsewhere (one source of truth for recipe state):
--
--   * numAvailable  — the client's own count of how many times the recipe can
--     be made with what is in the bags. A number; 0 means not right now.
--   * requiredSkill — when the client carries no numAvailable, compare the
--     recipe's required skill against the character's CURRENT Alchemy rank
--     (Data/Profession.lua, the same skill-line tier the tooltip gates use).
--   * neither field — the client cannot say. Answer nil and let the caller
--     record that, so the panel labels the list instead of pretending.
--
-- `how` always says WHICH answer this was, so the diag never mistakes an
-- unreadable client for a client that said "no".
local function alchemyRank(box)
  if box.rank == nil and box.why == nil then
    local P = ns.Profession
    if type(P) == "table" and type(P.Rank) == "function" then
      local ok, rank, why = pcall(P.Rank, P, "alchemy")
      if ok and type(rank) == "number" then
        box.rank = rank
      else
        box.why = tostring(why or rank)
      end
    else
      box.why = "Data/Profession.lua is not loaded, so the Alchemy rank cannot be read"
    end
  end
  return box.rank, box.why
end

local function availabilityFrom(info, rankbox)
  if type(info) ~= "table" then
    return nil, nil
  end
  local n = info.numAvailable
  if type(n) == "number" then
    return n > 0, "numAvailable"
  end
  local req = info.requiredSkill
  if type(req) == "number" then
    local rank, why = alchemyRank(rankbox)
    if type(rank) == "number" then
      return rank >= req, "requiredSkill"
    end
    return nil, "requiredSkill (the character's Alchemy rank could not be read: "
      .. tostring(why) .. ")"
  end
  return nil, nil
end

-- One recipe: name + reagent IDs, from whichever call answers.
-- `GetRecipeInfo` may answer as a table or as (name, reagents); a
-- `GetRecipeSchematic` table fills any missing half. Skips cleanly when
-- neither names the recipe.
-- Returns name, reagents, craftable (true/false/nil), availHow (nil when the
-- client exposed no availability field).
local function modernRecipe(mod, id, errbox, rankbox)
  local name
  local reagents
  local info
  local craftable, availHow
  local f = mod.GetRecipeInfo
  if type(f) == "function" then
    local ok, a, b = pcall(f, id)
    if not ok then
      errbox.err = "C_TradeSkillUI.GetRecipeInfo: " .. tostring(a)
    elseif type(a) == "table" then
      info = a
    elseif type(a) == "string" then
      name = a
      reagents = reagentsFrom(b)
    end
  end
  if info then
    if name == nil then
      name = nameFrom(info)
    end
    if reagents == nil then
      reagents = reagentsFrom(info)
    end
    craftable, availHow = availabilityFrom(info, rankbox)
  end
  if (name == nil or reagents == nil) and type(mod.GetRecipeSchematic) == "function" then
    -- LIVE CONTRACT (Forever 16001, t_81da8886):
    --   GetRecipeSchematic(recipeSpellID, isRecraft [, recipeLevel])
    -- The second argument is REQUIRED — a one-argument call raises
    -- "bad argument #2 to '?'" and every schematic read fails. Pass
    -- isRecraft=false: we read normal recipes, not recrafts.
    local ok, s = pcall(mod.GetRecipeSchematic, id, false)
    if not ok then
      errbox.err = "C_TradeSkillUI.GetRecipeSchematic: " .. tostring(s)
    elseif type(s) == "table" then
      if name == nil then
        name = nameFrom(s)
      end
      if reagents == nil then
        reagents = reagentsFrom(s)
      end
    end
  end
  if name == nil then
    return nil, nil, craftable, availHow
  end
  return name, reagents or {}, craftable, availHow
end

function Rc:ScanModern()
  local mod = C_TradeSkillUI
  if type(mod) ~= "table" then
    return false
  end
  local errbox = {}
  local ids, via = collectModernIDs(mod, errbox)
  if ids == nil then
    Rc._diag = {
      path = "modern",
      enumVia = via,
      profession = openProfession(mod),
      recipeCount = 0,
      error = errbox.err or "C_TradeSkillUI present but no usable recipe enumeration (probe returned no IDs)",
    }
    return false
  end
  local prof = openProfession(mod)
  local alchName = Rc:AlchName()
  local isAlchemy = (prof ~= nil) and (prof == alchName or prof == "Alchemy")
  if not isAlchemy then
    if prof ~= nil then
      -- The open window is a DIFFERENT, identifiable profession (Cooking,
      -- Enchanting, …). Its recipes are not alchemy, so persisting them
      -- would mislabel every reagent's tooltip. Same contract as the
      -- legacy gate; the scan can still run when the player opens Alchemy.
      Rc._diag = {
        path = "modern",
        gated = "profession",
        profession = prof,
        recipeCount = #ids,
        error = nil,
      }
    else
      -- The client reports no profession name at all: we cannot
      -- POSITIVELY confirm this is the Alchemy window, so whatever the
      -- open window enumerated is unverified. Persisting it would make
      -- every herb tooltip claim "Alchemy: <a recipe that is not
      -- Alchemy>" — silent wrong data is worse than a missing feature, so
      -- refuse to write and say why (t_217033d4).
      Rc._diag = {
        path = "modern",
        gated = "unknown-profession",
        profession = nil,
        recipeCount = #ids,
        error = "client reports no open profession name; the enumerated recipes cannot be verified as Alchemy, so they were not saved",
      }
    end
    return false
  end
  local newMap = {}
  local recipesRead = 0
  local reagentSlots = 0
  -- Availability, captured per recipe as it is read (t_04c983cc). Keyed by
  -- recipe name — the same name the reagent map stores — so a herb's list can
  -- be filtered without any second availability calculation anywhere.
  local craft = {}
  local canMake, cannotMake, unverified = 0, 0, 0
  local availHow = nil
  local rankbox = {}
  for _, id in ipairs(ids) do
    local rname, reagents, craftable, how = modernRecipe(mod, id, errbox, rankbox)
    if rname ~= nil then
      recipesRead = recipesRead + 1
      if craftable == true then
        craft[rname] = true
        canMake = canMake + 1
      elseif craftable == false then
        craft[rname] = false
        cannotMake = cannotMake + 1
      else
        unverified = unverified + 1
      end
      if how == "numAvailable" then
        availHow = "numAvailable"
      elseif how ~= nil and availHow == nil then
        availHow = how
      end
      for _, rid in ipairs(reagents) do
        reagentSlots = reagentSlots + 1
        newMap[rid] = newMap[rid] or {}
        table.insert(newMap[rid], rname)
      end
    end
  end
  local finalMap = {}
  for rid, names in pairs(newMap) do
    local unique = {}
    local seen = {}
    for _, nm in ipairs(names) do
      if not seen[nm] then
        seen[nm] = true
        table.insert(unique, nm)
      end
    end
    table.sort(unique)
    finalMap[rid] = unique
  end
  -- Zero reagent slots means the recipe/schematic surface did not answer
  -- on this client (e.g. every GetRecipeSchematic call failed). Writing
  -- an empty map AND setting alchemyScanned would make the feature
  -- silently empty with the hint gone (t_81da8886): treat it as an
  -- incomplete scan, record why, and let the next TRADE_SKILL_SHOW retry.
  if reagentSlots == 0 then
    Rc._diag = {
      path = "modern",
      enumVia = via,
      profession = prof,
      recipeCount = #ids,
      recipesRead = recipesRead,
      reagentSlots = 0,
      gated = "no-reagents",
      error = errbox.err or ("the scan read " .. recipesRead .. " recipe(s) but found no reagents — nothing was saved"),
    }
    return false
  end
  local db = ns.GetRecipeDB()
  db.alchemy = finalMap
  -- The gate is persisted WITH the recipe state and rebuilt on every scan, so a
  -- character who levels up (or learns a recipe) stops seeing yesterday's list
  -- the next time Alchemy is opened — no restart needed (t_04c983cc).
  --   alchemyCraft        name -> true|false, captured above
  --   alchemyFilterable   true when the client answered for at least one recipe
  --   alchemyAvailability which field answered ("numAvailable"/"requiredSkill"/"none")
  db.alchemyCraft = craft
  db.alchemyFilterable = (canMake + cannotMake) > 0
  db.alchemyAvailability = availHow or "none"
  NodeTrailDB.recipes.alchemyScanned = time()
  Rc._diag = {
    path = "modern",
    enumVia = via,
    profession = prof,
    recipeCount = #ids,
    recipesRead = recipesRead,
    reagentSlots = reagentSlots,
    availability = db.alchemyAvailability,
    craftable = canMake,
    excluded = cannotMake,
    unverified = unverified,
    error = errbox.err,
  }
  return true
end

-- ── Legacy path (pre-Dragonflight clients) — kept as the fallback ──────

function Rc:IsAlchemyOpen()
  if type(GetTradeSkillLine) ~= "function" then
    return false
  end
  local ok, line = pcall(GetTradeSkillLine)
  if not ok or line == nil then
    return false
  end
  local alch = Rc:AlchName()
  return line == alch or line == "Alchemy"
end

local function dedupNames(names)
  local unique = {}
  local seen = {}
  for _, nm in ipairs(names) do
    if not seen[nm] then
      seen[nm] = true
      table.insert(unique, nm)
    end
  end
  table.sort(unique)
  return unique
end

local function scanLegacy()
  if not Rc:IsAlchemyOpen() then
    local prof
    if type(GetTradeSkillLine) == "function" then
      local ok, l = pcall(GetTradeSkillLine)
      if ok then
        prof = l
      end
    end
    Rc._diag = {
      path = "legacy",
      gated = "profession",
      profession = prof,
      recipeCount = 0,
      error = nil,
    }
    return false
  end
  local errbox = {}
  if type(GetNumTradeSkills) ~= "function" then
    Rc._diag = {
      path = "legacy",
      profession = "Alchemy",
      recipeCount = 0,
      error = "GetNumTradeSkills missing",
    }
    return false
  end
  local nSkills = 0
  local okN, rN = pcall(GetNumTradeSkills)
  if not okN then
    errbox.err = "GetNumTradeSkills: " .. tostring(rN)
  elseif type(rN) == "number" then
    nSkills = rN
  end
  local newMap = {}
  local recipesRead = 0
  local reagentSlots = 0
  for i = 1, nSkills do
    local okI, name, skillType = pcall(GetTradeSkillInfo, i)
    if not okI then
      errbox.err = ("GetTradeSkillInfo(%d): %s"):format(i, tostring(name))
    end
    if okI and name ~= nil and skillType ~= "header" then
      recipesRead = recipesRead + 1
      local numReagents = 0
      if type(GetTradeSkillNumReagents) == "function" then
        local okR, rR = pcall(GetTradeSkillNumReagents, i)
        if not okR then
          errbox.err = ("GetTradeSkillNumReagents(%d): %s"):format(i, tostring(rR))
        elseif type(rR) == "number" then
          numReagents = rR
        end
      end
      if type(GetTradeSkillReagentItemLink) == "function" then
        for r = 1, numReagents do
          local okL, link = pcall(GetTradeSkillReagentItemLink, i, r)
          if not okL then
            errbox.err = ("GetTradeSkillReagentItemLink(%d,%d): %s"):format(i, r, tostring(link))
          elseif type(link) == "string" then
            local id = link:match("item:(%d+)")
            if id then
              local nid = tonumber(id)
              reagentSlots = reagentSlots + 1
              newMap[nid] = newMap[nid] or {}
              table.insert(newMap[nid], name)
            end
          end
        end
      end
    end
  end
  local finalMap = {}
  for id, names in pairs(newMap) do
    finalMap[id] = dedupNames(names)
  end
  -- Same incomplete-scan rule as the modern path (t_81da8886): a scan
  -- that read zero reagent slots must not persist an empty map and set
  -- alchemyScanned.
  if reagentSlots == 0 then
    Rc._diag = {
      path = "legacy",
      profession = Rc:AlchName(),
      recipeCount = nSkills,
      recipesRead = recipesRead,
      reagentSlots = 0,
      gated = "no-reagents",
      error = errbox.err or ("the scan read " .. recipesRead .. " recipe(s) but found no reagents — nothing was saved"),
    }
    return false
  end
  local db = ns.GetRecipeDB()
  db.alchemy = finalMap
  -- The legacy trade-skill API carries no availability field at all (its
  -- GetTradeSkillInfo answers name + difficulty only), so this path cannot
  -- gate. It CLEARS the gate rather than leaving a modern scan's stale verdict
  -- in place, and records "none" so the panel labels the list honestly
  -- (t_04c983cc).
  db.alchemyCraft = nil
  db.alchemyFilterable = false
  db.alchemyAvailability = "none"
  NodeTrailDB.recipes.alchemyScanned = time()
  Rc._diag = {
    path = "legacy",
    profession = Rc:AlchName(),
    recipeCount = nSkills,
    recipesRead = recipesRead,
    availability = "none",
    error = errbox.err,
  }
  return true
end

-- Dispatch: modern first (mainline clients only have it), legacy
-- fallback for a client that still ships the old globals. When neither
-- API exists the scan cannot run — record why, and let the status /
-- tooltip say so instead of promising an impossible step.
function Rc:Scan()
  Rc._diag = nil
  local info = Rc:APIInfo()
  if not info.available then
    Rc._diag = {
      path = "none",
      recipeCount = 0,
      error = "no usable trade-skill API on this client (C_TradeSkillUI and the legacy trade-skill globals are both absent)",
    }
    return false
  end
  if info.modern.exists then
    local hasEnum = false
    for _, n in ipairs(info.modern.calls) do
      if MODERN_ENUM[n] then
        hasEnum = true
        break
      end
    end
    if hasEnum then
      local ok, r, err = pcall(Rc.ScanModern)
      if not ok then
        Rc._error = tostring(err)
        Rc._diag = { path = "modern", error = tostring(err) }
        return false
      end
      if r then
        return true
      end
      -- Modern dead-ended (no enumeration or a non-alchemy window): a
      -- client that also still has the legacy globals can serve it.
      if not info.legacy.exists then
        return false
      end
    end
  end
  local ok, r, err = pcall(scanLegacy)
  if not ok then
    Rc._error = tostring(err)
    if type(Rc._diag) ~= "table" then
      Rc._diag = { path = "legacy", error = tostring(err) }
    end
    return false
  end
  return r
end

--- The raw persisted list for a reagent (the scan's own output, sorted).
--- The panel-facing view is Rc:Uses below: it is the ONE place the stored
--- availability is turned into "what may be listed now".
function Rc:GetUses(itemID)
  local db = ns.GetRecipeDB()
  return db.alchemy[itemID]
end

--- What the tooltip may say about one reagent (t_04c983cc).
--- Filtering ONLY: the availability was captured by the scan above, so nothing
--- here asks the client anything or recomputes a skill comparison.
--- Returns nil when the item has no recorded use, else:
---   names      the recipes as scanned (sorted)
---   craftable  the names this character can make right now — the only ones
---              the panel may list — or `names` itself when the client could
---              not be filtered (see `filtered`)
---   excluded   how many scanned recipes are NOT craftable now
---   filtered   true when the client answered availability at all. false means
---              "nobody can say", and the panel must label the list instead of
---              pretending it is gated.
function Rc:Uses(itemID)
  local db = ns.GetRecipeDB()
  local names = db.alchemy[itemID]
  if type(names) ~= "table" or #names == 0 then
    return nil
  end
  local craft = db.alchemyCraft
  local out = { names = names, craftable = names, excluded = 0, filtered = false }
  if db.alchemyFilterable == true and type(craft) == "table" then
    out.filtered = true
    out.craftable = {}
    for _, nm in ipairs(names) do
      if craft[nm] == true then
        table.insert(out.craftable, nm)
      else
        -- Not craftable now, OR the client gave no availability for this one.
        -- Either way the panel must not advertise it; the count is what keeps
        -- that from being a silent drop.
        out.excluded = out.excluded + 1
      end
    end
  end
  return out
end

-- ── Shared truth for the options panel and /nt scanrecipes ────────
-- One source, three surfaces: the panel's status line, the slash
-- command, and the manual "Scan now" button all read these, so they
-- can never drift apart from each other.

local function trunc(s, n)
  if type(s) ~= "string" or s == "" then
    return nil
  end
  if #s <= n then
    return s
  end
  return s:sub(1, n - 3) .. "..."
end

-- A human "when" for a recorded scan timestamp, from pure epoch
-- arithmetic — no date() call, so it is safe in the addon sandbox.
function Rc:When(epoch)
  local e = tonumber(epoch) or 0
  local dt = time() - e
  if dt < 0 then
    dt = 0
  end
  if dt < 90 then
    return dt .. "s ago"
  end
  if dt < 90 * 60 then
    return math.floor(dt / 60) .. "m ago"
  end
  return math.floor(dt / 3600) .. "h ago"
end

-- Can the OPEN profession window be positively identified as Alchemy?
-- Undecidable is false — the scan gate (t_217033d4) refuses to write
-- on exactly the same condition.
function Rc:AlchemyOpen()
  local prof
  if type(C_TradeSkillUI) == "table" then
    prof = openProfession(C_TradeSkillUI)
  end
  if prof == nil and type(GetTradeSkillLine) == "function" then
    local ok, l = pcall(GetTradeSkillLine)
    if ok and type(l) == "string" and l ~= "" then
      prof = l
    end
  end
  if prof == nil then
    return false
  end
  local alch = self:AlchName()
  return prof == alch or prof == "Alchemy"
end

-- THE one status line (t_36412359). Four states, same truth as
-- /nt status:
--   "scanned: N recipes (modern, <when>)"       — the map is persisted
--   "last scan found no reagents"               — a scan ran, saved nothing
--   "this client cannot list recipes (<reason>)" — no trade-skill API
--   "not scanned yet"                           — API present, no scan yet
function Rc:StatusLine()
  local scanned
  if type(NodeTrailDB) == "table" and type(NodeTrailDB.recipes) == "table" then
    scanned = NodeTrailDB.recipes.alchemyScanned
  end
  local d = type(Rc._diag) == "table" and Rc._diag or nil
  if scanned ~= nil then
    local n = tonumber(d and d.recipeCount) or 0
    local via = d and d.path or "unknown"
    return ("scanned: %d recipes (%s, %s)"):format(n, via, self:When(scanned))
  end
  if d and d.gated == "no-reagents" then
    return "last scan found no reagents"
  end
  local okA, a = pcall(Rc.APIInfo, Rc)
  if okA and type(a) == "table" and a.available == false then
    local reason = trunc(d and d.error, 80)
    if reason == nil then
      reason = "no trade skill API found on this client"
    end
    return "this client cannot list recipes (" .. reason .. ")"
  end
  return "not scanned yet"
end

-- The last recorded scan error, truncated for the panel — nil when
-- the current state carries no error (a completed scan, a clean
-- "not scanned yet").
function Rc:LastError()
  local d = type(Rc._diag) == "table" and Rc._diag or nil
  if d and type(d.error) == "string" and d.error ~= "" then
    return trunc(d.error, 100)
  end
  return nil
end

-- Manual rescan: the options panel's "Scan now" button and
-- /nt scanrecipes both go through here. Returns (done, msg) where
-- msg is chat-ready. Truthful by construction — it never claims a
-- scan it did not get (t_36412359):
--   * no usable trade-skill API  → the client-cannot-list line;
--   * Alchemy window not open   → the instruction line, nothing else;
--   * Alchemy window open       → run the scan; success OR the real
--     error string from Rc._diag, truncated.
function Rc:TryScanNow()
  local okI, info = pcall(Rc.APIInfo, Rc)
  if not okI then
    return false, "NodeTrail recipes: could not probe the client API: " .. tostring(info)
  end
  if info.available == false then
    local d = type(Rc._diag) == "table" and Rc._diag or nil
    local reason = trunc(d and d.error, 80) or "no trade skill API found on this client"
    return false,
      "NodeTrail recipes: this client cannot list recipes (" .. reason .. ")"
  end
  if not self:AlchemyOpen() then
    return false,
      "NodeTrail recipes: open your Alchemy window, then press this again."
  end
  local ok, done, err = pcall(Rc.Scan, Rc)
  if not ok then
    return false, "NodeTrail recipes: scan failed: " .. tostring(err)
  end
  if done then
    local db = ns.GetRecipeDB()
    local n = 0
    for _ in pairs(db.alchemy or {}) do
      n = n + 1
    end
    return true,
      "NodeTrail recipes: scanned successfully (" .. n .. " reagent(s) mapped)."
  end
  local d = type(Rc._diag) == "table" and Rc._diag or nil
  local reason = trunc(d and d.error, 100) or "the scan found no usable data"
  return false, "NodeTrail recipes: " .. reason
end

function Rc:Enable()
  if self._enabled then
    return
  end
  self._enabled = true
  local frame = CreateFrame("Frame")
  frame:SetScript("OnEvent", function(_, event)
    if event == "TRADE_SKILL_SHOW"
      or event == "TRADE_SKILL_UPDATE"
      or event == "TRADE_SKILLS_SHOW"
      or event == "TRADE_SKILLS_UPDATE" then
      -- Every Alchemy open is a fresh scan — a newly learned recipe
      -- must appear without the player pressing anything, so a
      -- successful earlier scan never suppresses this one
      -- (t_36412359). A pending flag set by a NEW_RECIPE_LEARNED that
      -- fired while the window was closed flushes here.
      Rc._pendingRescan = false
      local ok, err = pcall(Rc.Scan)
      if not ok then
        Rc._error = tostring(err)
      end
    elseif event == "NEW_RECIPE_LEARNED" then
      -- Only clients that know this event ever fire it (it is gated at
      -- registration below, never registered when the client rejects
      -- it). While the Alchemy window is open, rescan immediately;
      -- otherwise flag the next open to rescan (t_36412359).
      if Rc:AlchemyOpen() then
        local ok, err = pcall(Rc.Scan)
        if not ok then
          Rc._error = tostring(err)
        end
      else
        Rc._pendingRescan = true
      end
    end
  end)
  local allEvents = {}
  for _, e in ipairs(TRADE_EVENTS) do
    table.insert(allEvents, e)
  end
  table.insert(allEvents, "NEW_RECIPE_LEARNED")
  Rc._events = {}
  for _, e in ipairs(allEvents) do
    -- Register by TRYING, never by asking C_EventUtils.IsEventValid: that
    -- namespace is restricted to Blizzard's code and the call is refused at
    -- the secure-call boundary with the modal "MightiePack has been blocked
    -- from an action only available to the Blizzard UI", which pcall cannot
    -- catch (live 2026-11-07). On Forever 16001 only TRADE_SKILL_SHOW is
    -- valid; the rest raise "unknown event", which we do catch and record as
    -- "invalid event" so /nt ttdiag stays truthful (t_81da8886).
    local ok, err = pcall(frame.RegisterEvent, frame, e)
    if ok then
      Rc._events[e] = true
    else
      local msg = tostring(err)
      if msg:find("unknown event", 1, true) then
        Rc._events[e] = "invalid event"
      else
        Rc._events[e] = msg
      end
    end
  end
end

-- /nt ttdiag (recipes half) — the in-client evidence channel for the
-- trade-skill scan: which APIs exist, what the open window reports, and
-- what the last scan saw. Forever 16001 has no /run or /dump; these
-- lines are the only way to see inside (t_0d5badc3).
function Rc:Diag()
  local function say(m)
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail recipes: " .. m)
  end
  local ok, info = pcall(Rc.APIInfo, Rc)
  if not ok then
    say("API probe failed: " .. tostring(info))
    return
  end
  if info.modern.exists then
    say("C_TradeSkillUI present; calls probed: "
      .. (table.concat(info.modern.calls, ", ") or ("(none of " .. #MODERN_CALLS .. " candidates found)")))
  else
    say("C_TradeSkillUI absent")
  end
  if #info.legacy.calls > 0 then
    say("legacy trade-skill globals: " .. table.concat(info.legacy.calls, ", ")
      .. ((info.legacy.exists and "") or "  (incomplete — the legacy scan will not use them)"))
  else
    say("legacy trade-skill globals absent")
  end
  local prof
  if type(C_TradeSkillUI) == "table" then
    prof = openProfession(C_TradeSkillUI)
  end
  if prof == nil and type(GetTradeSkillLine) == "function" then
    local okP, l = pcall(GetTradeSkillLine)
    if okP and type(l) == "string" and l ~= "" then
      prof = l
    end
  end
  say("open profession: " .. (prof or "unknown (no API on this client answered)"))
  if type(Rc._events) == "table" then
    local parts = {}
    for _, e in ipairs(TRADE_EVENTS) do
      local v = Rc._events[e]
      table.insert(parts, e .. "=" .. (v == true and "on" or tostring(v)))
    end
    say("events: " .. table.concat(parts, ", "))
  end
  local d = Rc._diag
  if d then
    say(("last scan: path=%s recipes_read=%s profession=%s error=%s"):format(
      tostring(d.path),
      tostring(d.recipeCount or 0),
      tostring(d.profession or "n/a"),
      tostring(d.error or "nil")))
  else
    say("last scan: none (no scan has run since the addon loaded)")
  end
  -- Availability (t_04c983cc): which field the client answered with, and what
  -- the gate made of it. A list that is NOT filtered says so here once, so the
  -- panel's "recipes (not filtered by skill)" label is explainable rather than
  -- mysterious.
  local dbd = nil
  if type(NodeTrailDB) == "table" and type(NodeTrailDB.recipes) == "table" then
    dbd = NodeTrailDB.recipes
  end
  local avail = (d and d.availability) or (dbd and dbd.alchemyAvailability)
  if avail == nil then
    avail = "unknown (no scan has recorded one yet)"
  end
  if avail == "none" or avail == "unknown (no scan has recorded one yet)" then
    say("availability: " .. tostring(avail)
      .. " — this client exposed neither numAvailable nor requiredSkill, so the tooltip lists recipes (not filtered by skill)")
  elseif d and d.availability then
    say(("availability: %s — craftable=%s excluded=%s unverified=%s"):format(
      tostring(avail), tostring(d.craftable or 0), tostring(d.excluded or 0),
      tostring(d.unverified or 0)))
  else
    say("availability: " .. tostring(avail) .. " (recorded by an earlier scan)")
  end
  if Rc._error then
    say("module error: " .. tostring(Rc._error))
  end
end
