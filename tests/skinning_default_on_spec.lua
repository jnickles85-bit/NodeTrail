-- skinning_default_on_spec.lua — t_ba64b076 (skinning collector on by default).
--
-- The card: "Right now a fresh install records nothing until the player finds
-- the sub-option. Make recording the default." Three observable cases, and all
-- three are driven through the REAL files (locale/enUS, NodeTrail/Config,
-- NodeTrail/Core, Skinning/Record). Nothing here re-implements the toggle, the
-- migration or the recorder: the boot is ns.Enable(), the opt-out is the same
-- setter the Options checkbox calls (and the /nt skin command calls), and the
-- stored record is produced by R:OnKill / R:OnCorpseLoot / R:OnSkinCast /
-- R:OnSkinLoot.
--
-- What this pins:
--   1. FRESH — no saved NodeTrailDB: a login arms the recorder and a kill +
--      skin lands in NodeTrailDB.skinning.chars[...] with no setup, with no
--      user-set flag invented (a default is not a choice);
--   2. MIGRATED — a bucket saved with enabled = false and no user-set flag is
--      flipped on EXACTLY ONCE, the skinMigration marker is written, and a
--      later load that carries the marker but a false value is left alone;
--   3. OPTED OUT — /nt skin off (and the shared setter the Options checkbox
--      uses) writes skinUserSet, the value stays false across a SavedVariables
--      round-trip, and the migration never overrides it;
--   4. the migration preserves everything else in the bucket it upgrades.
--
-- RED on 710b0ea (origin/main, v0.3.3-beta): the default is false there, there
-- is no skinMigration / skinUserSet at all and /nt skin is an unknown command,
-- so sections 1-4 fail on that commit (and no check below can panic on a
-- missing field: every read is type-guarded).
--
-- Not loaded by the addon TOC.
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

-- ── chat capture ───────────────────────────────────────────────────────
local chat = {}
DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end,
}
local function clearChat()
  for i = #chat, 1, -1 do chat[i] = nil end
end
local function chatHas(needle)
  return table.concat(chat, "\n"):find(needle, 1, true) ~= nil
end

-- ── client stubs the four files actually reach ─────────────────────────
SlashCmdList = {}
StaticPopupDialogs = {}
local function deepCopy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = deepCopy(v) end
  return r
end
CopyTable = deepCopy
local now = 1000
GetTime = function() return now end
-- The recorder's character bucket is Name-Realm (Record.CharKey), so the spec
-- has to answer both, exactly like the live client does.
GetRealmName = function() return "Forever" end
GetUnitName = function(unit, withRealm)
  if unit == "player" then return "Bowdecia" end
  return nil -- a GUID is not a unit token: this is the client's answer
end
C_Map = {
  GetBestMapForUnit = function() return 1411 end,
  GetPlayerMapPosition = function()
    return { GetXY = function() return 0.4871, 0.3125 end }
  end,
}

-- ── boot: a fresh package + the real files, exactly like a login ───────
-- NodeTrailDB is the SavedVariables table: the same content a /reload hands
-- back. The probe namespace is a spy so this spec asserts that recording was
-- ARMED at login without driving the probe's event surface (skindiag_spec and
-- the recorder specs own that).
local function boot(savedNT)
  clearChat()
  SlashCmdList = {}
  NodeTrailDB = savedNT
  -- A spy in the probe's namespace: the real Enable/Disable are plain functions
  -- called with no self (Skinning/Core.lua), so this stub must be one too.
  local sk = { enabled = false }
  sk.Enable = function() sk.enabled = true return true end
  sk.Disable = function() sk.enabled = false return true end
  local pkg = { Skinning = sk }
  local files = {
    "MightiePack/Modules/NodeTrail/locale/enUS.lua",
    "MightiePack/Modules/NodeTrail/Config.lua",
    "MightiePack/Modules/NodeTrail/Core.lua",
    "MightiePack/Modules/Skinning/Record.lua",
  }
  for _, path in ipairs(files) do
    local chunk, err = loadfile(root .. "/" .. path)
    check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
    if chunk then
      local ok, e = pcall(chunk, "MightiePack", pkg)
      check(ok, "load " .. path .. ": " .. tostring(e))
    end
  end
  return pkg
end

local function login(savedNT)
  local pkg = boot(savedNT)
  local ns = pkg.NodeTrail
  check(type(ns) == "table", "NodeTrail namespace loaded")
  if type(ns) ~= "table" then return pkg end
  if type(ns.Enable) == "function" then
    local ok, e = pcall(ns.Enable)
    check(ok, "NodeTrail login (ns.Enable): " .. tostring(e))
  else
    check(false, "ns.Enable exists (a login runs it)")
  end
  return pkg
end

local function skinDB(pkg)
  local ns = pkg.NodeTrail
  if type(ns) ~= "table" or type(ns.GetSkinDB) ~= "function" then return nil end
  local ok, db = pcall(ns.GetSkinDB)
  if not ok or type(db) ~= "table" then return nil end
  return db
end

-- ════════════════════════════════════════════════════════════════════════
-- 0. the defaults themselves
-- ════════════════════════════════════════════════════════════════════════
local p0 = boot(deepCopy({ profile = { routeSource = "gm2" } }))
local ns0 = p0.NodeTrail
check(type(ns0) == "table", "0: NodeTrail namespace loaded")
check(type(ns0) == "table" and type(ns0.defaults) == "table"
  and type(ns0.defaults.skinning) == "table"
  and ns0.defaults.skinning.enabled == true,
  "0: ns.defaults.skinning.enabled is TRUE (recording is the default)")
-- The accessor's own fallbacks, not just the defaults table: every place that
-- would hand back `false` on that key is covered by the fresh boot below, and
-- this names the table the fallbacks come from.
local d0 = skinDB(p0)
check(d0 ~= nil and d0.enabled == true,
  "0: ns.GetSkinDB() hands back enabled = true for a bucket that never had the key")

-- ════════════════════════════════════════════════════════════════════════
-- 1. FRESH INSTALL — nothing saved, no setup, a kill + skin is recorded
-- ════════════════════════════════════════════════════════════════════════
local p1 = login(nil) -- no NodeTrailDB at all: a brand-new install
local ns1 = p1.NodeTrail
check(type(NodeTrailDB) == "table", "1: a login creates NodeTrailDB")
check(type(ns1) == "table" and type(ns1.IsSkinningEnabled) == "function"
  and ns1.IsSkinningEnabled() == true,
  "1: the sub-option reads ON after a first login with no saved value")
check(type(NodeTrailDB) == "table" and type(NodeTrailDB.skinning) == "table"
  and NodeTrailDB.skinning.enabled == true,
  "1: NodeTrailDB.skinning.enabled is true (nothing to find in the options panel)")
check(type(NodeTrailDB) == "table" and type(NodeTrailDB.skinning) == "table"
  and NodeTrailDB.skinning.skinUserSet ~= true,
  "1: a default is not a choice — no skinUserSet flag is invented")
check(type(NodeTrailDB) == "table" and type(NodeTrailDB.skinning) == "table"
  and NodeTrailDB.skinning.skinMigration == 1,
  "1: the one-time migration is marked as already run")
check(p1.Skinning.enabled == true,
  "1: the login armed the recorder (no /mp skindiag, no checkbox)")

-- The player kills the mob, loots it, casts Skinning and loots the corpse
-- again — the real recorder entry points, no hand-written store shape.
local R1 = p1.Skinning.Recorder
check(type(R1) == "table", "1: the recorder loaded")
if type(R1) == "table" then
  local guid = "Creature-0-7072-1-48-3124-F090F29C6F"
  R1:OnKill({ guid = guid, t = 100, name = "Scorpid Worker", map = 1411, x = 0.4871, y = 0.3125 })
  R1:OnCorpseLoot({ guid = guid, t = 101, items = { { itemID = 7100, quantity = 1 } } })
  R1:OnLootClosed(102)
  R1:OnSkinCast({ guid = guid, t = 103, spellID = 8613 })
  R1:OnSkinLoot({ guid = guid, t = 104, items = { { itemID = 2934, quantity = 3 } } })

  local bucket = type(NodeTrailDB.skinning.chars) == "table"
    and NodeTrailDB.skinning.chars["Bowdecia-Forever"] or nil
  check(type(bucket) == "table", "1: the record landed in the character bucket (NodeTrailDB.skinning.chars)")
  local rec = type(bucket) == "table" and type(bucket.records) == "table"
    and bucket.records[guid] or nil
  check(type(rec) == "table", "1: the kill + skin produced a record for the corpse GUID")
  if type(rec) == "table" then
    check(rec.killObserved == true, "1: the kill was observed")
    check(rec.skinned == true, "1: the 8613 cast marked the corpse skinned")
    check(type(rec.skinItems) == "table" and type(rec.skinItems[1]) == "table"
      and rec.skinItems[1].itemID == 2934,
      "1: the skin loot (2934) is on the record")
  end
end

-- ════════════════════════════════════════════════════════════════════════
-- 2. MIGRATED INSTALL — a saved `enabled = false` with no user-set flag
-- ════════════════════════════════════════════════════════════════════════
-- The old build's default was false, so a bucket written before this change
-- carries false with no flag. It must be flipped ONCE. The record ring in the
-- fixture is there to prove the upgrade does not throw the player's history
-- away while it flips a default.
local OLD_GUID = "Creature-0-7072-1-48-3124-0CC9AE"
local oldBucket = {
  skinning = {
    enabled = false,
    chars = {
      ["Bowdecia-Forever"] = {
        schema = 1,
        counts = { kills = 7, corpseWindows = 5, skinWindows = 4, skinCasts = 4, unattributedWindows = 0 },
        records = { [OLD_GUID] = { guid = OLD_GUID, killObserved = true, skinned = true } },
        order = { OLD_GUID },
        unclassified = {},
      },
    },
  },
}
local p2 = login(oldBucket)
local ns2 = p2.NodeTrail
check(type(ns2) == "table" and type(ns2.IsSkinningEnabled) == "function"
  and ns2.IsSkinningEnabled() == true,
  "2: a saved false with no user-set flag flips to ON")
check(NodeTrailDB.skinning.enabled == true, "2: the migration wrote enabled = true")
check(NodeTrailDB.skinning.skinMigration == 1,
  "2: the skinMigration marker is written so it never fires again")
check(NodeTrailDB.skinning.skinUserSet ~= true,
  "2: migrating a default does NOT claim the player chose it")
check(type(NodeTrailDB.skinning.chars) == "table"
  and type(NodeTrailDB.skinning.chars["Bowdecia-Forever"]) == "table"
  and NodeTrailDB.skinning.chars["Bowdecia-Forever"].records[OLD_GUID] ~= nil,
  "2: the upgrade kept the existing record (a bucket is never discarded)")
check(type(NodeTrailDB.skinning.chars) == "table"
  and NodeTrailDB.skinning.chars["Bowdecia-Forever"].counts.kills == 7,
  "2: the upgrade kept the existing counts")

-- Second load: the marker IS the guard. A bucket that carries the marker but a
-- false value (no user-set flag) must be left alone — otherwise every future
-- release would turn it back on and the marker would mean nothing.
local afterFirst = deepCopy(NodeTrailDB)
afterFirst.skinning.enabled = false
local p2b = login(afterFirst)
check(NodeTrailDB.skinning.enabled == false,
  "2: with skinMigration already set, the migration does not fire a second time")
check(NodeTrailDB.skinning.skinMigration == 1, "2: the marker is unchanged by the second load")

-- ════════════════════════════════════════════════════════════════════════
-- 3. OPTED OUT — the player's "off" survives a reload and every later update
-- ════════════════════════════════════════════════════════════════════════
local p3 = login(nil)
local ns3 = p3.NodeTrail
check(ns3.IsSkinningEnabled() == true, "3: the fresh install starts ON")

-- Un-tick it: the Options checkbox calls this exact setter (Options.lua
-- applySkinning), so this is the checkbox path without a UI harness.
ns3.SetSkinningEnabled(false)
check(NodeTrailDB.skinning.enabled == false, "3: un-ticking persists enabled = false")
check(NodeTrailDB.skinning.skinUserSet == true,
  "3: un-ticking writes the user-set flag (an explicit off, not a default)")

-- /reload: the SavedVariables table comes back, everything in memory is rebuilt.
local reloaded = deepCopy(NodeTrailDB)
local p3b = boot(reloaded)
local ns3b = p3b.NodeTrail
local okB = pcall(ns3b.Enable)
check(okB, "3: the reload boot runs")
check(NodeTrailDB.skinning.enabled == false,
  "3: the player's off survives a /reload")
check(NodeTrailDB.skinning.skinUserSet == true,
  "3: the user-set flag survives a /reload")
check(ns3b.IsSkinningEnabled() == false, "3: the sub-option still reads OFF after the reload")
check(p3b.Skinning.enabled == false, "3: the recorder was NOT armed at login after the opt-out")

-- And the migration never overrides it: wipe the marker (a bucket whose
-- migration has NOT run) and load again. The user-set flag alone must stop it,
-- because the player's choice outranks a default.
local noMarker = deepCopy(NodeTrailDB)
noMarker.skinning.skinMigration = nil
local p3c = login(noMarker)
check(NodeTrailDB.skinning.enabled == false,
  "3: a migration that has never run still does not override an explicit off")
check(NodeTrailDB.skinning.skinUserSet == true, "3: and it leaves the user-set flag alone")
check(NodeTrailDB.skinning.skinMigration == 1, "3: the migration marks itself as run regardless")
check(p3c.NodeTrail.IsSkinningEnabled() == false, "3: the sub-option still reads OFF")

-- ════════════════════════════════════════════════════════════════════════
-- 4. /nt skin — the chat toggle is the same choice, written the same way
-- ════════════════════════════════════════════════════════════════════════
local p4 = login(nil)
local ns4 = p4.NodeTrail
check(type(SlashCmdList.NODETRAIL) == "function", "4: /nt is registered at login")
check(ns4.IsSkinningEnabled() == true, "4: the fresh install starts ON")

clearChat()
if type(SlashCmdList.NODETRAIL) == "function" then
  local okS = pcall(SlashCmdList.NODETRAIL, "skin off")
  check(okS, "4: /nt skin off does not error")
end
check(NodeTrailDB.skinning.enabled == false, "4: /nt skin off persists enabled = false")
check(NodeTrailDB.skinning.skinUserSet == true,
  "4: /nt skin off writes the user-set flag (the chat path is a choice too)")
check(p4.Skinning.enabled == false, "4: /nt skin off stops the recorder immediately")
check(chatHas("skinning off"), "4: /nt skin off says so in chat")
-- What a /reload would hand back after the chat opt-out.
local chatOptOut = deepCopy(NodeTrailDB)

clearChat()
if type(SlashCmdList.NODETRAIL) == "function" then
  local okS = pcall(SlashCmdList.NODETRAIL, "skin on")
  check(okS, "4: /nt skin on does not error")
end
check(NodeTrailDB.skinning.enabled == true, "4: /nt skin on persists enabled = true")
check(p4.Skinning.enabled == true, "4: /nt skin on arms the recorder immediately")
check(chatHas("skinning on"), "4: /nt skin on says so in chat")

-- A reload after the chat opt-out keeps the chat-written flag, exactly like the
-- checkbox path: one flag, two write paths.
local p4b = login(chatOptOut)
check(NodeTrailDB.skinning.enabled == false,
  "4: an off written in chat is the same off a reload keeps")
check(NodeTrailDB.skinning.skinUserSet == true,
  "4: the chat-written user-set flag survives the reload")
check(p4b.Skinning.enabled == false, "4: and the recorder stays off after that reload")

-- ════════════════════════════════════════════════════════════════════════
if failed > 0 then
  io.stderr:write(failed .. " checks failed\n")
  os.exit(1)
end
print("skinning_default_on_spec: ok")
