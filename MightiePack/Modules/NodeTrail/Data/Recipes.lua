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
  "GetTradeSkillNumAvailable",
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

-- ── Which signal can say "this character can make it"? (t_4ab7c230) ───────
-- The first pass read only `numAvailable` / `requiredSkill` off GetRecipeInfo,
-- and Forever 16001 answers NEITHER: its client carries
--
--   C_TradeSkillUI.GetCraftableCount(recipeSpellID [, recipeLevel]) -> numAvailable
--   C_TradeSkillUI.IsRecipeProfessionLearned(recipeID)              -> boolean
--
-- (both usage strings are in Wow.exe, build 16001; the recipeInfo struct's own
-- fields are `numAvailable`, `requiredSkillRank`, `skillLineAbilityID`). An
-- UNLEARNED recipe is enumerated exactly like a known one — that is the list
-- Mightie saw — so the learned flag is the signal that answers his complaint,
-- and the skill rank is the second half.
--
-- Decided in this order; `how` always names the one that answered:
--   1. the client's own craftable count > 0   — proof it can be made now;
--   2. IsRecipeProfessionLearned == false     — the recipe is not known;
--   3. requiredSkillRank / requiredSkill      — rank comparison;
--   4. IsRecipeProfessionLearned == true      — known, no readable skill field;
--   5. craftable count == 0                   — the only answer there is;
--   6. isAvailable                            — boolean some clients offer.
-- nil means the client answered nothing for this recipe: the panel then HIDES
-- the line instead of advertising a list nobody can vouch for.
local function craftableCount(info, id, mod)
  if type(info) == "table" and type(info.numAvailable) == "number" then
    return info.numAvailable, "numAvailable"
  end
  if type(mod) == "table" and type(mod.GetCraftableCount) == "function" then
    local ok, n = pcall(mod.GetCraftableCount, id)
    if ok and type(n) == "number" then
      return n, "GetCraftableCount"
    end
  end
  return nil, nil
end

local function requiredSkillFrom(info)
  if type(info) ~= "table" then
    return nil, nil
  end
  if type(info.requiredSkillRank) == "number" then
    return info.requiredSkillRank, "requiredSkillRank"
  end
  if type(info.requiredSkill) == "number" then
    return info.requiredSkill, "requiredSkill"
  end
  return nil, nil
end

local function learnedFrom(mod, id)
  if type(mod) ~= "table" or type(mod.IsRecipeProfessionLearned) ~= "function" then
    return nil
  end
  local ok, v = pcall(mod.IsRecipeProfessionLearned, id)
  if ok and type(v) == "boolean" then
    return v
  end
  return nil
end

local function availabilityFrom(info, id, mod, rankbox)
  local n, countHow = craftableCount(info, id, mod)
  if n ~= nil and n > 0 then
    return true, countHow
  end
  local learned = learnedFrom(mod, id)
  if learned == false then
    return false, "IsRecipeProfessionLearned"
  end
  local req, reqHow = requiredSkillFrom(info)
  if req ~= nil then
    local rank, why = alchemyRank(rankbox)
    if type(rank) == "number" then
      return rank >= req, reqHow
    end
    if learned == nil and n == nil then
      return nil, reqHow .. " (the character's Alchemy rank could not be read: "
        .. tostring(why) .. ")"
    end
  end
  if learned == true then
    return true, "IsRecipeProfessionLearned"
  end
  if n ~= nil then
    return n > 0, countHow
  end
  if type(info) == "table" and type(info.isAvailable) == "boolean" then
    return info.isAvailable, "isAvailable"
  end
  return nil, nil
end

-- Which answering signal wins when recipes disagree (used for the diag's single
-- `availability:` word). A count is the strongest proof; a skill comparison is
-- not proof the recipe is known.
local SIGNAL_ORDER = {
  numAvailable = 1,
  GetCraftableCount = 2,
  GetTradeSkillNumAvailable = 3,
  IsRecipeProfessionLearned = 4,
  requiredSkillRank = 5,
  requiredSkill = 6,
  isAvailable = 7,
  GetTradeSkillInfo = 8,
}

-- One recipe: name + reagent IDs, from whichever call answers.
-- `GetRecipeInfo` may answer as a table or as (name, reagents); a
-- `GetRecipeSchematic` table fills any missing half. Skips cleanly when
-- neither names the recipe.
-- Returns name, reagents, craftable (true/false/nil), availHow (the signal that
-- answered — nil when the client exposed no availability signal at all).
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
    return nil, nil, nil, nil
  end
  -- Availability is read last: it needs the recipe id (the count and learned
  -- calls take it) and, for the skill comparison, the character's rank. It is
  -- read even when GetRecipeInfo answered only a name string.
  craftable, availHow = availabilityFrom(info, id, mod, rankbox)
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
      if how ~= nil then
        -- Keep the strongest answering signal for the diag's single word
        -- (t_4ab7c230): a craftable count is proof, a rank comparison is not
        -- proof the recipe is known.
        local rank = SIGNAL_ORDER[how] or 99
        if availHow == nil or rank < (SIGNAL_ORDER[availHow] or 99) then
          availHow = how
        end
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
  local craft = {}
  local canMake, cannotMake, unverified = 0, 0, 0
  local availHow = nil
  local recipesRead = 0
  local reagentSlots = 0
  for i = 1, nSkills do
    local okI, name, skillType, learnable = pcall(GetTradeSkillInfo, i)
    if not okI then
      errbox.err = ("GetTradeSkillInfo(%d): %s"):format(i, tostring(name))
    end
    if okI and name ~= nil and skillType ~= "header" then
      recipesRead = recipesRead + 1
      -- Availability on the legacy API (t_4ab7c230): the count call is the
      -- same "how many can I make now" the modern path reads, and some
      -- clients also answer a learnable boolean as GetTradeSkillInfo's third
      -- return. Neither exists on Forever 16001, so this changes nothing
      -- there — it keeps an older client filterable instead of hiding a list
      -- that COULD be gated.
      local craftable, how
      if type(GetTradeSkillNumAvailable) == "function" then
        local okA, nA = pcall(GetTradeSkillNumAvailable, i)
        if okA and type(nA) == "number" then
          craftable, how = nA > 0, "GetTradeSkillNumAvailable"
        end
      end
      if craftable == nil and type(learnable) == "boolean" then
        craftable, how = learnable, "GetTradeSkillInfo"
      end
      if craftable == true then
        craft[name] = true
        canMake = canMake + 1
      elseif craftable == false then
        craft[name] = false
        cannotMake = cannotMake + 1
      else
        unverified = unverified + 1
      end
      if how ~= nil then
        local rank = SIGNAL_ORDER[how] or 99
        if availHow == nil or rank < (SIGNAL_ORDER[availHow] or 99) then
          availHow = how
        end
      end
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
  -- Persist whatever the legacy API answered (t_4ab7c230). When it answered
  -- nothing — Forever 16001's case, since its legacy globals are gone — the
  -- gate is cleared rather than leaving a modern scan's stale verdict, and the
  -- panel hides the line instead of advertising an unfiltered list.
  if canMake + cannotMake > 0 then
    db.alchemyCraft = craft
    db.alchemyFilterable = true
    db.alchemyAvailability = availHow or "none"
  else
    db.alchemyCraft = nil
    db.alchemyFilterable = false
    db.alchemyAvailability = "none"
  end
  NodeTrailDB.recipes.alchemyScanned = time()
  Rc._diag = {
    path = "legacy",
    profession = Rc:AlchName(),
    recipeCount = nSkills,
    recipesRead = recipesRead,
    availability = db.alchemyAvailability,
    craftable = canMake,
    excluded = cannotMake,
    unverified = unverified,
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
---              "nobody can say", and the panel must draw NO Alchemy line at
---              all — a list it cannot vouch for is worse than silence
---              (t_4ab7c230).
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

--- Why the panel is drawing no Alchemy line, for the options panel — nil when
--- there is nothing to explain (a filtered client, or no saved recipes yet).
--- One short sentence, no caveat the player has to decode in a tooltip
--- (t_4ab7c230): a client that answered no availability hides the list, and
--- this is where the reason lives.
function Rc:HiddenHint()
  local db = ns.GetRecipeDB()
  if db.alchemyFilterable == true then
    return nil
  end
  local has = false
  for _ in pairs(db.alchemy or {}) do
    has = true
    break
  end
  if not has then
    return nil
  end
  if db.alchemyAvailability == "none" and NodeTrailDB.recipes.alchemyScanned ~= nil then
    return "alchemy uses hidden — this client has no recipe-availability API "
      .. "(GetCraftableCount, IsRecipeProfessionLearned, requiredSkillRank all absent)"
  end
  if NodeTrailDB.recipes.alchemyScanned ~= nil then
    return "alchemy uses hidden — the saved scan recorded no availability; open Alchemy once to rescan"
  end
  return nil
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
  -- Availability (t_04c983cc, t_4ab7c230): which signal the client answered
  -- with (or that none did), and what the gate made of it. A client that
  -- answered nothing HIDES the line, so this says which signal was missing
  -- once — /nt recipediag carries the raw per-recipe values.
  local dbd = nil
  if type(NodeTrailDB) == "table" and type(NodeTrailDB.recipes) == "table" then
    dbd = NodeTrailDB.recipes
  end
  local avail = (d and d.availability) or (dbd and dbd.alchemyAvailability)
  if avail == nil then
    avail = "unknown (no scan has recorded one yet)"
  end
  if avail == "none" then
    say("availability: none — no recipe-availability signal answered "
      .. "(GetCraftableCount / IsRecipeProfessionLearned / requiredSkillRank all absent; "
      .. "numAvailable / requiredSkill / isAvailable did not answer either), so the Alchemy line is hidden "
      .. "for this character — /nt recipediag prints the raw per-recipe values")
  elseif avail == "unknown (no scan has recorded one yet)" then
    say("availability: unknown (no scan has recorded one yet) — open Alchemy once, then /nt recipediag")
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

-- ── /nt recipediag (t_4ab7c230) ───────────────────────────────────────────
-- The in-client measurement the card asks for: for one recipe this character
-- can make and one it cannot, print EVERY candidate signal and its raw value.
-- Nothing here is inferred or shaped: the client's own fields are printed by
-- name, and a call that is absent says so. This is the only way to see inside
-- Forever 16001 (no /run, no /dump); its Wow.exe carries the usage strings
--
--   local numAvailable           = C_TradeSkillUI.GetCraftableCount(recipeSpellID [, recipeLevel])
--   local recipeProfessionLearned = C_TradeSkillUI.IsRecipeProfessionLearned(recipeID)
--
-- and the recipeInfo fields `numAvailable`, `requiredSkillRank`,
-- `skillLineAbilityID`. The scan reads those three (Data/Recipes.lua above);
-- this command is how anyone can check that claim against the live client.
--
-- Targets: the last scan's persisted gate picks the first recipe it marked
-- craftable and the first it marked not craftable (that IS "one he can and one
-- he can't"). With no saved gate — an older scan, or a client that answered
-- nothing — the first two enumerated ids are dumped instead and the labels say
-- `stored gate: unknown`. `/nt recipediag <id|name>` puts that recipe first.

local function sortedKeys(t)
  local nums, strs = {}, {}
  for k in pairs(t) do
    if type(k) == "number" then
      table.insert(nums, k)
    else
      table.insert(strs, tostring(k))
    end
  end
  table.sort(nums)
  table.sort(strs)
  local out = {}
  for _, k in ipairs(nums) do
    table.insert(out, k)
  end
  for _, k in ipairs(strs) do
    table.insert(out, k)
  end
  return out
end

-- A value with its type, so an absent field can never be read as a zero and a
-- table can be seen as a table. Nested tables are printed two levels deep with
-- a per-table cap; a recipeInfo/schematic is flat or one level in practice.
local function fmtValue(v, depth)
  local t = type(v)
  if t == "string" then
    return '"' .. v .. '" (' .. t .. ')'
  end
  if t == "number" or t == "boolean" then
    return tostring(v) .. " (" .. t .. ")"
  end
  if t == "table" then
    if depth <= 0 then
      return "table"
    end
    local keys = sortedKeys(v)
    local parts = {}
    local cap = 24
    for i, k in ipairs(keys) do
      if i > cap then
        table.insert(parts, "... (+" .. (#keys - cap) .. " more)")
        break
      end
      table.insert(parts, tostring(k) .. "=" .. fmtValue(v[k], depth - 1))
    end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return tostring(v) .. " (" .. t .. ")"
end

function Rc:RecipeDiag(arg)
  local function say(m)
    if type(DEFAULT_CHAT_FRAME) == "table" and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
      DEFAULT_CHAT_FRAME:AddMessage("NodeTrail recipediag: " .. tostring(m))
    end
  end
  local mod = C_TradeSkillUI
  say("client: C_TradeSkillUI " .. (type(mod) == "table" and "present" or "ABSENT"))
  local MODERN_PROBES = {
    "GetRecipeInfo",
    "GetRecipeSchematic",
    "GetCraftableCount",
    "GetRecipeRequirements",
    "IsRecipeProfessionLearned",
    "GetRecipeCooldown",
    "GetRecipeInfoForSkillLineAbility",
    "GetOriginalCraftRecipeID",
    "GetAllRecipeIDs",
    "GetNumRecipeIDs",
  }
  local parts = {}
  for _, n in ipairs(MODERN_PROBES) do
    table.insert(parts, n .. "=" .. ((type(mod) == "table" and type(mod[n]) == "function") and "present" or "absent"))
  end
  say("modern calls: " .. table.concat(parts, ", "))
  local LEGACY_PROBES = {
    "GetTradeSkillLine",
    "GetNumTradeSkills",
    "GetTradeSkillInfo",
    "GetTradeSkillNumAvailable",
    "GetTradeSkillNumReagents",
    "GetTradeSkillReagentInfo",
    "GetTradeSkillReagentItemLink",
  }
  parts = {}
  for _, n in ipairs(LEGACY_PROBES) do
    table.insert(parts, n .. "=" .. (type(_G[n]) == "function" and "present" or "absent"))
  end
  say("legacy calls: " .. table.concat(parts, ", "))

  local rank, rankWhy
  if type(ns.Profession) == "table" and type(ns.Profession.Rank) == "function" then
    local ok, r, w = pcall(ns.Profession.Rank, ns.Profession, "alchemy")
    if ok and type(r) == "number" then
      rank = r
    else
      rankWhy = tostring(w or r)
    end
  else
    rankWhy = "Data/Profession.lua is not loaded, so no skill API was asked"
  end
  say("character Alchemy rank: "
    .. (rank and (rank .. " (GetSkillLineInfo / Pr:Rank)") or ("unreadable (" .. tostring(rankWhy) .. ")")))

  local prof
  if type(mod) == "table" then
    prof = openProfession(mod)
  end
  if prof == nil and type(GetTradeSkillLine) == "function" then
    local okP, l = pcall(GetTradeSkillLine)
    if okP and type(l) == "string" and l ~= "" then
      prof = l
    end
  end
  say("open profession: " .. tostring(prof or "unknown (no call answered)"))

  local errbox = {}
  local ids, via
  if type(mod) == "table" then
    ids, via = collectModernIDs(mod, errbox)
  end
  if ids == nil then
    say("recipe ids: none enumerated (" .. tostring(errbox.err or "the client returned no ids") .. ")")
    return
  end
  say(("recipe ids: %d enumerated via %s"):format(#ids, tostring(via or "?")))

  local db = ns.GetRecipeDB()
  local craft = type(db.alchemyCraft) == "table" and db.alchemyCraft or nil
  local names, infos = {}, {}
  local canMake, cannotMake, unverified = 0, 0, 0
  if craft then
    for _, v in pairs(craft) do
      if v == true then
        canMake = canMake + 1
      elseif v == false then
        cannotMake = cannotMake + 1
      else
        unverified = unverified + 1
      end
    end
  end

  local function readRecipe(id)
    local info, nm
    if type(mod) == "table" and type(mod.GetRecipeInfo) == "function" then
      local ok, a = pcall(mod.GetRecipeInfo, id)
      if ok then
        if type(a) == "table" then
          info = a
          nm = nameFrom(a)
        elseif type(a) == "string" and a ~= "" then
          nm = a
        end
      end
    end
    if nm == nil and type(mod) == "table" and type(mod.GetRecipeSchematic) == "function" then
      local ok, s = pcall(mod.GetRecipeSchematic, id, false)
      if ok and type(s) == "table" then
        nm = nameFrom(s)
      end
    end
    return nm, info
  end

  local shown = 0
  for _, id in ipairs(ids) do
    local nm, info = readRecipe(id)
    names[id] = nm
    infos[id] = info
    shown = shown + 1
    if shown <= 12 then
      say(("[%d] id=%s name=%s"):format(shown, tostring(id), nm and ('"' .. nm .. '"') or "unnamed"))
    end
  end
  if #ids > shown or #ids > 12 then
    say(("... %d more id(s) not listed"):format(#ids - math.min(shown, 12)))
  end
  if craft then
    say(("stored gate: %d craftable, %d not craftable, %d unverified (availability=%s)")
      :format(canMake, cannotMake, unverified, tostring(db.alchemyAvailability or "none")))
  else
    say("stored gate: none (no saved alchemyCraft — an older scan, or a client that answered nothing)")
  end

  -- Pick the two probes: the first recipe the stored gate says he can make and
  -- the first it says he cannot. An explicit argument overrides target 1.
  local firstID, secondID
  local argID = tonumber(arg)
  local argName = type(arg) == "string" and arg ~= "" and arg:lower() or nil
  if argID and names[argID] ~= nil then
    firstID = argID
  elseif argName then
    for _, id in ipairs(ids) do
      local nm = names[id]
      if nm and nm:lower():find(argName, 1, true) then
        firstID = id
        break
      end
    end
  end
  if craft then
    for _, id in ipairs(ids) do
      local nm = names[id]
      if nm and craft[nm] == true and firstID == nil and id ~= secondID then
        firstID = id
      elseif nm and craft[nm] == false and secondID == nil and id ~= firstID then
        secondID = id
      end
    end
  end
  if firstID == nil then
    firstID = ids[1]
  end
  if secondID == nil or secondID == firstID then
    for _, id in ipairs(ids) do
      if id ~= firstID then
        secondID = id
        break
      end
    end
  end

  local function storedLabel(id)
    local nm = names[id]
    if craft and nm and craft[nm] == true then
      return "craftable"
    elseif craft and nm and craft[nm] == false then
      return "not craftable"
    end
    return "unknown"
  end

  local function callLine(name, arg)
    local f = type(mod) == "table" and mod[name] or nil
    local shown = name .. "(" .. tostring(arg) .. ")"
    if type(f) ~= "function" then
      say(shown .. " -> absent")
      return
    end
    local ok, a = pcall(f, arg)
    if not ok then
      say(shown .. " raised: " .. tostring(a))
      return
    end
    say(shown .. " -> " .. fmtValue(a, 2))
  end

  local function dumpTarget(label, id)
    if id == nil then
      say("--- " .. label .. ": no recipe id to probe")
      return
    end
    local nm = names[id]
    say(("--- %s: %s (recipe id %s) · stored gate: %s")
      :format(label, nm and ('"' .. nm .. '"') or "unnamed", tostring(id), storedLabel(id)))
    local info = infos[id]
    if info ~= nil then
      say(("GetRecipeInfo(%s) -> %s"):format(tostring(id), fmtValue(info, 2)))
    else
      say(("GetRecipeInfo(%s) -> no table (the call is absent, raised, or answered a bare name)"):format(tostring(id)))
    end
    if type(mod) == "table" and type(mod.GetRecipeSchematic) == "function" then
      local ok, s = pcall(mod.GetRecipeSchematic, id, false)
      if ok then
        say(("GetRecipeSchematic(%s, false) -> %s"):format(tostring(id), fmtValue(s, 2)))
      else
        say(("GetRecipeSchematic(%s, false) raised: %s"):format(tostring(id), tostring(s)))
      end
    else
      say("GetRecipeSchematic(...) -> absent")
    end
    callLine("GetCraftableCount", id)
    callLine("GetRecipeRequirements", id)
    callLine("IsRecipeProfessionLearned", id)
    callLine("GetRecipeCooldown", id)
    if info and type(info.skillLineAbilityID) == "number" then
      callLine("GetRecipeInfoForSkillLineAbility", info.skillLineAbilityID)
    end
    -- Legacy: only when the globals exist. The index is the one whose name
    -- matches; without a match the first three rows are printed so the shape
    -- is still visible.
    if type(GetNumTradeSkills) == "function" and type(GetTradeSkillInfo) == "function" then
      local okN, n = pcall(GetNumTradeSkills)
      say("legacy GetNumTradeSkills() -> " .. fmtValue(n, 0))
      if okN and type(n) == "number" then
        local hit
        for i = 1, math.min(n, 200) do
          local ok, a = pcall(GetTradeSkillInfo, i)
          if ok and a == nm then
            hit = i
            break
          end
        end
        local rows = hit and { hit } or { 1, 2, 3 }
        for _, i in ipairs(rows) do
          local ok, a, b, c = pcall(GetTradeSkillInfo, i)
          if ok then
            say(("legacy GetTradeSkillInfo(%d) -> %s, %s, %s")
              :format(i, fmtValue(a, 0), fmtValue(b, 0), fmtValue(c, 0)))
          end
        end
        if hit then
          if type(GetTradeSkillNumAvailable) == "function" then
            local okA, avail = pcall(GetTradeSkillNumAvailable, hit)
            say(("legacy GetTradeSkillNumAvailable(%d) -> %s"):format(hit, okA and fmtValue(avail, 0) or ("raised: " .. tostring(avail))))
          else
            say("legacy GetTradeSkillNumAvailable(...) -> absent")
          end
          if type(GetTradeSkillNumReagents) == "function" then
            local okR, nr = pcall(GetTradeSkillNumReagents, hit)
            say(("legacy GetTradeSkillNumReagents(%d) -> %s"):format(hit, okR and fmtValue(nr, 0) or ("raised: " .. tostring(nr))))
            if okR and type(nr) == "number" and type(GetTradeSkillReagentInfo) == "function" then
              for r = 1, math.min(nr, 3) do
                local okI, a, b, c = pcall(GetTradeSkillReagentInfo, hit, r)
                if okI then
                  say(("legacy GetTradeSkillReagentInfo(%d, %d) -> %s, %s, %s")
                    :format(hit, r, fmtValue(a, 0), fmtValue(b, 0), fmtValue(c, 0)))
                end
              end
            end
          end
        end
      end
    else
      say("legacy trade-skill globals: absent (GetNumTradeSkills / GetTradeSkillInfo)")
    end
  end

  dumpTarget("target 1 (craftable per stored gate)", firstID)
  dumpTarget("target 2 (not craftable per stored gate)", secondID)

  local avail = db.alchemyAvailability
  if avail == nil then
    say("signal: not measured yet — no completed scan recorded availability; open Alchemy once, then rerun")
  elseif avail == "none" then
    say("signal: NONE — GetCraftableCount / IsRecipeProfessionLearned / requiredSkillRank / "
      .. "numAvailable / requiredSkill / isAvailable all absent or unreadable for these recipes; "
      .. "the Alchemy line is hidden")
  else
    say("signal: " .. tostring(avail) .. " — the Alchemy line is filtered on it")
  end
end
