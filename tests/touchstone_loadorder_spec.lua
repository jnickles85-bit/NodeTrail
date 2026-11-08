-- Load-order invariant for the vendored Touchstone (live bug 2026-11-07).
--
-- Upstream publishes `_readWornLinks`, `_judgeQuestReward`, `_maybeToastUpgrades`
-- and `refreshQuestMarkers` from inside init functions, then CALLS those init
-- functions at load, so `local f = ChestAdvisor._x` captures at load get real
-- functions. The fold defers the calls to ChestAdvisor.Enable(), which runs
-- after the captures — so every capture took nil and each scan died with
--   ChestAdvisor.lua:4982: attempt to call a nil value
-- (confirmed in the client, Count: 3, then 1).
--
-- The fix resolves those names at call time. This spec pins both halves:
--   1. the file loads with the module disabled and defines scan/Enable;
--   2. the source contains no column-1 load-time capture of a late export.
--
-- It fails on the pre-fix file.

local here = (arg and arg[0] or "tests/touchstone_loadorder_spec.lua"):match("^(.*)[/\\][^/\\]*$") or "."
local root = here:gsub("[/\\]tests$", "")
if root == "tests" then root = "." end
local path = (arg and arg[1]) or (root .. "/MightiePack/Modules/Touchstone/ChestAdvisor/ChestAdvisor.lua")

local fails = 0
local function check(cond, msg)
  if not cond then
    print("FAIL: " .. msg)
    fails = fails + 1
  end
end

local function readAll(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local source = assert(readAll(path), "cannot read " .. path)

local late = {
  "_readWornLinks", "_judgeQuestReward", "_maybeToastUpgrades",
  "refreshQuestMarkers", "_toastIsEnabled",
}
-- Only the region before the scan definition is load-time code; a capture
-- inside a function body (initLogAndSlash runs from Enable, after
-- _initToastSurface) resolves at call time and is fine.
local scanAt = source:find("ChestAdvisor%.scan%s*=%s*function")
check(scanAt ~= nil, "ChestAdvisor.scan is defined")
local loadRegion = scanAt and source:sub(1, scanAt) or source
for _, name in ipairs(late) do
  local pattern = "\nlocal%s+[%a_][%w_]*%s*=%s*ChestAdvisor%." .. name:gsub("%-", "%%-")
  check(not loadRegion:find(pattern), "no load-time capture of ChestAdvisor." .. name)
end

-- The wrappers that replaced them must exist.
for _, fn in ipairs({ "readWornLinks", "judgeQuestReward", "maybeToastUpgrades", "refreshQuestMarkers" }) do
  local pattern = "local function%s+" .. fn .. "%s*%("
  check(source:find(pattern) ~= nil, "lazy wrapper `local function " .. fn .. "(` is present")
end

-- And the file must still load with Enable() never called.
local function stub(name)
  local t = {}
  local mt = {
    __index = function(self, k)
      local v = stub(name .. "." .. tostring(k))
      rawset(self, k, v)
      return v
    end,
    __call = function() return stub(name .. "()") end,
    __tostring = function() return "<stub " .. name .. ">" end,
    __concat = function(a, b) return tostring(a) .. tostring(b) end,
  }
  return setmetatable(t, mt)
end

local env = {
  tonumber = tonumber, tostring = tostring, type = type,
  pairs = pairs, ipairs = ipairs, select = select,
  error = error, pcall = pcall, print = print,
  table = table, string = string, math = math,
  -- The fold's guard is the first statement: the permissive stub would make it
  -- truthy and the chunk would return before defining anything.
  MightiePackTouchstoneSkip = false,
  GetTime = function() return 0 end,
  GetLocale = function() return "enUS" end,
  UnitClass = function() return "Paladin", "PALADIN" end,
  UnitLevel = function() return 18 end,
  UnitName = function() return "Tester" end,
  CreateFrame = function() return stub("frame") end,
}
setmetatable(env, {
  __index = function(_, k)
    local v = stub(tostring(k))
    env[k] = v
    return v
  end,
})

local chunk, loadErr = loadfile(path)
check(chunk ~= nil, "ChestAdvisor.lua must parse: " .. tostring(loadErr))
if chunk then
  setfenv(chunk, env)
  local ok, err = pcall(chunk, "MightiePack", { NodeTrail = {}, Touchstone = {} })
  check(ok, "ChestAdvisor.lua load chunk must not error: " .. tostring(err))
  local CA = rawget(env, "ChestAdvisor")
  check(type(CA) == "table", "ChestAdvisor table exists after load")
  if type(CA) == "table" then
    check(type(CA.scan) == "function", "ChestAdvisor.scan is defined at load")
    check(type(CA.Enable) == "function", "ChestAdvisor.Enable is defined at load")
  end
end

if fails == 0 then
  print("touchstone_loadorder_spec: ok")
else
  print(("touchstone_loadorder_spec: %d failure(s)"):format(fails))
  os.exit(1)
end
