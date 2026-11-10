if MightiePackTouchstoneSkip then return end
--- StatForge deep probe: direct-value reads for a client we cannot interrogate
--- interactively (WoW: Forever beta).
---
--- Why this exists: the capability probe in Diagnostics.lua reports only whether
--- a symbol is PRESENT and what its FIRST return value looked like. Several
--- capture paths depend on later return values (UnitArmor/UnitAttackPower/
--- UnitRangedAttackPower all return base AND effective), so a probe that stops at
--- the first value can report "ok" for a read that is actually starving the
--- export. It also cannot see a stats table that exists but is entirely zero,
--- which is precisely the Forever symptom.
---
--- This module records EVERY return value, and writes the result into
--- SavedVariables so it reaches disk where a human (or a companion app) can read
--- it without copying text out of a chat frame.
---
--- Read-only: it calls accessor APIs and stores strings. No file writes, no
--- network, no protected calls. Safe on any flavor.

StatForge = StatForge or {}
local SF = StatForge

local MAX_VALUE = 80

--- Describe one return value without ever touching a SECRET. Reading or
--- comparing a secret raises, and `tostring(secret)` is itself a read, so the
--- secret check must come FIRST and be the only operation performed.
local function describe(v)
  if v == nil then return "nil" end
  local t = type(v)
  -- The secret check must precede EVERY value-producing operation, including the
  -- `tostring` in the scalar branch below. It must also precede the early return
  -- for exotic types: a secret need not be a number, and a table-shaped secret
  -- reported as "ok(<table>)" would read as a healthy value. Only its TYPE is
  -- safe to report.
  if issecretvalue and issecretvalue(v) then
    return "SECRET(" .. t .. ")"
  end
  if t ~= "number" and t ~= "string" and t ~= "boolean" then
    return "ok(<" .. t .. ">)"
  end
  local s = tostring(v)
  s = s:gsub("%s+", " ")
  if #s > MAX_VALUE then
    s = s:sub(1, MAX_VALUE - 3) .. "..."
  end
  return "ok(" .. s .. ")"
end

--- Pack a pcall's results. Deliberately does NOT use unpack()/table.unpack():
--- this ships to a client whose Lua version we are explicitly not assuming.
local function packResults(...)
  return { n = select("#", ...), ... }
end

local function stripLocation(message)
  if type(message) ~= "string" then return tostring(message) end
  return (message:gsub("^.-:%d+:%s*", ""))
end

--- Call `fn` with up to three arguments and describe EVERY value it returns.
--- One row per call, so a reader can compare return arity across clients.
local function row(lines, label, fn, a1, a2, a3)
  local argc = select("#", a1, a2, a3)
  local results
  if type(fn) ~= "function" then
    lines[#lines + 1] = label .. " = ABSENT"
    return
  end
  if argc == 0 then
    results = packResults(pcall(fn))
  elseif argc == 1 then
    results = packResults(pcall(fn, a1))
  elseif argc == 2 then
    results = packResults(pcall(fn, a1, a2))
  else
    results = packResults(pcall(fn, a1, a2, a3))
  end

  if not results[1] then
    lines[#lines + 1] = label .. " = THREW(" .. stripLocation(results[2]) .. ")"
    return
  end

  local parts = {}
  for i = 2, results.n do
    parts[#parts + 1] = describe(results[i])
  end
  lines[#lines + 1] = label .. " = " .. table.concat(parts, " | ")
end

--- Read `name` off _G, tolerating a "Table.Field" form.
local function fromGlobal(name)
  local head, tail = name:match("^([%w_]+)%.([%w_]+)$")
  if head then
    local tbl = _G[head]
    if type(tbl) ~= "table" then return nil end
    return tbl[tail]
  end
  return _G[name]
end

--- Run the full sweep. Returns an ordered list of report lines; never throws,
--- because a client we are describing must not be able to kill the descriptor.
function SF.RunDeepProbe()
  local lines = {}
  lines[#lines + 1] = "Touchstone deep probe"
  lines[#lines + 1] = "addon=" .. tostring(SF.VERSION) .. " toc=" ..
    tostring(SF.TOC_INTERFACE or "?") .. " at=" .. tostring(date("%Y-%m-%dT%H:%M:%S"))

  -- Client identity
  row(lines, "GetBuildInfo", _G.GetBuildInfo)
  row(lines, "WOW_PROJECT_ID", function() return WOW_PROJECT_ID end)
  row(lines, "UnitName", _G.UnitName, "player")
  row(lines, "UnitClass", _G.UnitClass, "player")
  row(lines, "UnitLevel", _G.UnitLevel, "player")
  row(lines, "UnitRace", _G.UnitRace, "player")
  row(lines, "GetRealmName", _G.GetRealmName)

  -- Character sheet: the PRIMARY STAT reads behind the zeroed export.
  -- UnitStat is reported per-index so a partial sheet is visible.
  for i = 1, 5 do
    row(lines, "UnitStat(" .. i .. ")", _G.UnitStat, "player", i)
  end
  row(lines, "UnitHealthMax", _G.UnitHealthMax, "player")
  row(lines, "UnitPowerType", _G.UnitPowerType, "player")
  row(lines, "UnitPowerMax", _G.UnitPowerMax, "player", 0)
  -- These three return (base, positive, negative) / (base, effective): the
  -- second value is what the export actually consumes.
  row(lines, "UnitArmor", _G.UnitArmor, "player")
  row(lines, "UnitAttackPower", _G.UnitAttackPower, "player")
  row(lines, "UnitRangedAttackPower", _G.UnitRangedAttackPower, "player")
  row(lines, "UnitDefenseSkill", _G.UnitDefenseSkill, "player")

  -- Optional sheet getters, probed so we learn presence on this client.
  row(lines, "GetCritChance", _G.GetCritChance)
  row(lines, "GetRangedCritChance", _G.GetRangedCritChance)
  row(lines, "GetSpellCritChance", _G.GetSpellCritChance, 2)
  row(lines, "GetSpellBonusDamage", _G.GetSpellBonusDamage, 2)
  row(lines, "GetSpellBonusHealing", _G.GetSpellBonusHealing)
  row(lines, "GetDodgeChance", _G.GetDodgeChance)
  row(lines, "GetParryChance", _G.GetParryChance)
  row(lines, "GetBlockChance", _G.GetBlockChance)

  -- Talents: classic-style APIs the optimizer models depend on.
  row(lines, "GetNumTalentTabs", _G.GetNumTalentTabs)
  row(lines, "GetNumTalents(1)", _G.GetNumTalents, 1)
  row(lines, "GetTalentInfo(1,1)", _G.GetTalentInfo, 1, 1)
  row(lines, "GetTalentLink(1,1)", _G.GetTalentLink, 1, 1)
  row(lines, "GetSpecialization", _G.GetSpecialization)
  row(lines, "C_SpecializationInfo.GetSpecialization",
    fromGlobal("C_SpecializationInfo.GetSpecialization"))

  -- Equipment / items
  row(lines, "GetInventoryItemLink(1)", _G.GetInventoryItemLink, "player", 1)
  row(lines, "GetInventoryItemLink(16)", _G.GetInventoryItemLink, "player", 16)
  row(lines, "GetInventoryItemsForSlot", _G.GetInventoryItemsForSlot, 1)
  row(lines, "C_Item.GetItemInfo", fromGlobal("C_Item.GetItemInfo"), 6948)
  row(lines, "GetItemInfo", _G.GetItemInfo, 6948)

  -- Containers (both API generations)
  row(lines, "C_Container.GetContainerNumSlots",
    fromGlobal("C_Container.GetContainerNumSlots"), 0)
  row(lines, "GetContainerNumSlots", _G.GetContainerNumSlots, 0)
  row(lines, "C_Container.GetContainerItemLink",
    fromGlobal("C_Container.GetContainerItemLink"), 0, 1)
  row(lines, "GetContainerItemLink", _G.GetContainerItemLink, 0, 1)

  -- Card t_adf556d6: the two CAPTURE lines used to report what the addon's own
  -- snapshot produced, so a discrepancy between "the API answers" and "the
  -- capture got it" was visible in one artifact. The capture is retired and
  -- Snapshot.lua is deleted, so there is nothing left to compare against. The
  -- probe now reports the CLIENT and only the client -- which is what the
  -- advisor needs when a verdict goes wrong on someone's machine.

  return lines
end

--- Persist the sweep so it reaches disk and CANNOT be lost to the reload that
--- flushes it.
---
--- SavedVariables is written by the client on /reload or logout, so the readout
--- must already be in the table the client serialises. The first version of this
--- stored a single `deepProbe` slot and relied on Core.initDB to preserve it —
--- but initDB only re-creates its own keys, and the export path rewrites the
--- table from memory, so the slot silently vanished on the very reload it needed
--- to be written by. Keep a bounded ROLLING history instead, keyed by character,
--- so a later run cannot erase an earlier readout.
local MAX_PROBES = 5

function SF.SaveDeepProbe()
  local lines = SF.RunDeepProbe()
  StatForgeDB = StatForgeDB or {}
  local history = StatForgeDB.deepProbes
  if type(history) ~= "table" then
    history = {}
    StatForgeDB.deepProbes = history
  end
  local entry = {
    at = time(),
    atIso = date("%Y-%m-%dT%H:%M:%SZ"),
    level = tostring(UnitLevel and UnitLevel("player") or "?"),
    name = tostring(UnitName and UnitName("player") or "?"),
    lines = lines,
  }
  -- Newest first, bounded: an unbounded log would grow SavedVariables forever.
  table.insert(history, 1, entry)
  for i = #history, MAX_PROBES + 1, -1 do
    history[i] = nil
  end
  -- Also keep the flat slot so anything already reading `deepProbe` keeps working.
  StatForgeDB.deepProbe = entry
  return lines
end

--- Slash entry point: run, persist, and echo to chat.
function SF.DeepProbe()
  local ok, lines = pcall(SF.SaveDeepProbe)
  if not ok then
    SF.PrintError("deep probe failed: " .. stripLocation(lines))
    return
  end
  for _, line in ipairs(lines) do
    SF.Print("probe: " .. line)
  end
  SF.Print("probe saved, no /reload needed.")
end

-- ---- Card t_acc9fd97: the raw stat-pair probe — the owner's unit reading ---------
--
-- THE QUESTION IT SERVES. The weight packs price the HIT / CRIT / DODGE /
-- PARRY terms per rating point, but the client's own tooltips print
-- percentages ("+1% Crit") and C_Item.GetItemStats returns whatever the
-- client reports — the two are not proven equal by anything in this repo.
-- The card defers the unit decision to the owner's in-game read, and this is
-- that read: for a NAMED item it reports the client's own stat pairs
-- verbatim — the key exactly as the client spelled it, the value exactly as
-- returned, and the Lua type the client used for it. No conversion, no
-- interpretation, no verdict.
--
-- THE ITEM COMES FROM ITS OWN LINK — right-click, Copy Link to Item, pasted
-- into the command (the owner's own surface, pinned in card t_119d120c's
-- evidence). No cursor API is called: GetCursorItem has no evidenced
-- existence on this client, and a stale pool button is exactly the wrong
-- item this reading must never report on. The first printed line names the
-- item the pairs belong to (its id standing in when the name read is
-- missing), so a mis-pasted link is visible before any number is trusted.
--
-- EVERY stage fails closed and says what it could not do. No number in this
-- output is a guess, and nothing here requires the item to be owned or worn.
function SF.StatProbe(link)
  -- The arm passes the LINK from the raw (un-lowercased) message; the guard
  -- below is the same contract at the direct-call edge: no link, or a link
  -- without an id, asks for the pasted-link form instead of inventing an
  -- item to read.
  local function wantLink()
    SF.Print("statprobe: paste the item's own link (right-click it, Copy Link to Item), "
      .. "then run: /touchstone stats <link>")
  end
  if type(link) ~= "string" or link:match("^%s*$") ~= nil then
    return wantLink()
  end
  local idStr = link:match("item:(%d+)")
  if not idStr then
    return wantLink()
  end
  local id = tonumber(idStr)

  -- The item's name for the label line: the ONE proven name read (the
  -- advisor's single C_Item.GetItemInfo call). Best-effort on purpose — a
  -- missing name never blocks the pairs, and the id stands in the label.
  local name = nil
  if C_Item and type(C_Item.GetItemInfo) == "function" then
    local ok, n = pcall(C_Item.GetItemInfo, link)
    if ok and type(n) == "string" and n ~= "" then
      name = n
    end
  end
  local label = (name ~= nil and name) or ("item id " .. tostring(id))
  SF.Print("stat probe — item: " .. label)

  -- THE READ — the advisor's own edge pattern (ChestAdvisor.lua's apiStatsOf):
  -- same call, same pcall discipline, same secret checks. The only
  -- difference is the contract: that edge maps the pairs into the module's
  -- words; this one reports them verbatim.
  if not (C_Item and type(C_Item.GetItemStats) == "function") then
    return SF.PrintError("stat probe: this client offers no C_Item.GetItemStats — the pairs cannot be read")
  end
  local ok, raw = pcall(C_Item.GetItemStats, id)
  if not ok then
    return SF.PrintError("stat probe: C_Item.GetItemStats raised for this item — " .. stripLocation(raw))
  end
  if type(raw) ~= "table" then
    return SF.PrintError("stat probe: the client returned nothing for this item (no stat pairs)")
  end
  -- A secret/withheld READ: the table itself may not be touched — not even
  -- iterated — so this is the one arm that names the condition and stops.
  if type(issecretvalue) == "function" then
    local sok, sec = pcall(issecretvalue, raw)
    if sok and sec then
      return SF.Print("stat probe: the client marked the whole read a secret/withheld value — no pairs are reported")
    end
  end
  local keys = {}
  for k in pairs(raw) do
    if type(k) == "string" then keys[#keys + 1] = k end
  end
  table.sort(keys)
  if #keys == 0 then
    -- A read that answers is a read: zero stats is the client's own answer
    -- for this item, and the owner needs that sentence, not silence.
    return SF.Print("stat probe: " .. label .. " carries ZERO stats — "
      .. "the client returned an empty table (say so in the reply)")
  end
  for _, k in ipairs(keys) do
    local v = raw[k]
    -- The secret check comes FIRST and is the only operation performed on a
    -- secret value (the describe() discipline, lines 24-35): tostring is
    -- itself a read, and a secret's metatable raises on it.
    local secret = false
    if issecretvalue and type(issecretvalue) == "function" then
      local vk, vs = pcall(issecretvalue, v)
      if vk and vs then secret = true end
    end
    if secret then
      SF.Print(k .. " = SECRET (the client withheld this value) [" .. type(v) .. "]")
    else
      SF.Print(k .. " = " .. tostring(v) .. " [" .. type(v) .. "]")
    end
  end
  SF.Print("stat probe: " .. #keys .. " stat pair(s) for " .. label
    .. " — key and value verbatim from C_Item.GetItemStats")
end
