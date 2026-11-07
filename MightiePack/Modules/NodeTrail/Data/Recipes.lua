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
  if type(x) == "table" then
    for _, k in ipairs({ "itemID", "id", "itemid", "item" }) do
      local v = x[k]
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
    end
    local link = x.link
    if type(link) == "string" then
      local id = link:match("item:%s*(%d+)")
      if id then
        return tonumber(id)
      end
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

local function reagentsFrom(t)
  if type(t) ~= "table" then
    return nil
  end
  for _, key in ipairs({ "reagents", "requiredReagents", "reagentList" }) do
    local r = fromContainer(t[key])
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

-- One recipe: name + reagent IDs, from whichever call answers.
-- `GetRecipeInfo` may answer as a table or as (name, reagents); a
-- `GetRecipeSchematic` table fills any missing half. Skips cleanly when
-- neither names the recipe.
local function modernRecipe(mod, id, errbox)
  local name
  local reagents
  local info
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
    local ok, s = pcall(mod.GetRecipeSchematic, id)
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
    return nil, nil
  end
  return name, reagents or {}
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
  for _, id in ipairs(ids) do
    local rname, reagents = modernRecipe(mod, id, errbox)
    if rname ~= nil then
      recipesRead = recipesRead + 1
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
  local db = ns.GetRecipeDB()
  db.alchemy = finalMap
  NodeTrailDB.recipes.alchemyScanned = time()
  Rc._diag = {
    path = "modern",
    enumVia = via,
    profession = prof,
    recipeCount = #ids,
    recipesRead = recipesRead,
    reagentSlots = reagentSlots,
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
  local db = ns.GetRecipeDB()
  db.alchemy = finalMap
  NodeTrailDB.recipes.alchemyScanned = time()
  Rc._diag = {
    path = "legacy",
    profession = Rc:AlchName(),
    recipeCount = nSkills,
    recipesRead = recipesRead,
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

function Rc:GetUses(itemID)
  local db = ns.GetRecipeDB()
  return db.alchemy[itemID]
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
      local ok, err = pcall(Rc.Scan)
      if not ok then
        Rc._error = tostring(err)
      end
    end
  end)
  Rc._events = {}
  for _, e in ipairs(TRADE_EVENTS) do
    local ok, err = pcall(frame.RegisterEvent, frame, e)
    Rc._events[e] = ok and true or tostring(err)
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
  if Rc._error then
    say("module error: " .. tostring(Rc._error))
  end
end
