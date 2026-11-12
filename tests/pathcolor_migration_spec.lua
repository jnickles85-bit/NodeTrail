-- pathcolor_migration_spec.lua — the old white default, including a
-- partial {1,1,1} with no alpha, migrates to teal once in GetDB.
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end
local function near(a, b, msg)
  check(type(a) == "number" and math.abs(a - b) < 1e-9,
    msg .. " got " .. tostring(a) .. " expected " .. tostring(b))
end

function CopyTable(t)
  if type(t) ~= "table" then return t end
  local n = {}
  for k, v in pairs(t) do
    n[k] = type(v) == "table" and CopyTable(v) or v
  end
  return n
end

local function loadConfig()
  local ns = {}
  local chunk, err = loadfile(root .. "/MightiePack/Modules/NodeTrail/Config.lua")
  assert(chunk, err)
  chunk("MightiePack", { NodeTrail = ns })
  return ns
end

local TEAL_R, TEAL_G, TEAL_B, TEAL_A = 0.400, 0.988, 0.945, 0.85

-- 1. Partial {1,1,1} (no alpha) must migrate. fillMissing would otherwise
--    write the new teal alpha into [4] and the colour would no longer
--    match {1,1,1,0.9}.
NodeTrailDB = { profile = { pathColor = { 1, 1, 1 } } }
local ns = loadConfig()
local db = ns.GetDB()
near(db.pathColor[1], TEAL_R, "1: partial white R")
near(db.pathColor[2], TEAL_G, "1: partial white G")
near(db.pathColor[3], TEAL_B, "1: partial white B")
near(db.pathColor[4], TEAL_A, "1: partial white A")
check(NodeTrailDB.profile.pathColorMigration == 1, "1: the migration is stamped")

-- 2. The exact old default {1,1,1,0.9} migrates too.
NodeTrailDB = { profile = { pathColor = { 1, 1, 1, 0.9 } } }
ns = loadConfig()
db = ns.GetDB()
near(db.pathColor[1], TEAL_R, "2: old white default R")
near(db.pathColor[4], TEAL_A, "2: old white default A")

-- 3. Any other stored colour is left alone.
NodeTrailDB = { profile = { pathColor = { 1, 0, 0, 0.5 } } }
ns = loadConfig()
db = ns.GetDB()
near(db.pathColor[1], 1, "3: custom R is kept")
near(db.pathColor[4], 0.5, "3: custom A is kept")
check(NodeTrailDB.profile.pathColorMigration == 1, "3: the marker is still stamped")

if failed > 0 then
  io.stderr:write(failed .. " pathcolor migration check(s) failed\n")
  os.exit(1)
end
print("pathcolor_migration_spec: ok")
