-- Event-registration gate.
--
-- The probe (and the recipe scanner) used to ask C_EventUtils.IsEventValid
-- before registering an event. That namespace is restricted to Blizzard's own
-- code: calling it is refused at the secure-call boundary, and the client
-- answers with the modal
--   "MightiePack has been blocked from an action only available to the
--    Blizzard UI"
-- rather than a Lua error, so pcall cannot contain it. Live 2026-11-07 the
-- block fired on the exact frame /mp skindiag ran.
--
-- The gate must therefore TRY the registration and classify the failure:
-- "unknown event" is recorded as "invalid event", anything else keeps its
-- error text. This spec pins both halves — the source has no C_EventUtils
-- reference, and the classification still works.

local here = (arg and arg[0] or "tests/event_gate_spec.lua"):match("^(.*)[/\\][^/\\]*$") or "."
local root = here:gsub("[/\\]tests$", "")
if root == "tests" then root = "." end

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

-- 1) Source invariant: no CODE in the addon may touch the restricted
--    namespace. Comments that explain why it is banned are fine.
local p = io.popen('grep -rn "C_EventUtils" "' .. root .. '/MightiePack" --include=*.lua 2>/dev/null')
local hits = {}
if p then
  for line in p:lines() do
    if not line:match("^.-:%d+:%s*%-%-") then hits[#hits + 1] = line end
  end
  p:close()
end
check(#hits == 0, "no C_EventUtils call in the addon (found " .. #hits .. ")")
for _, line in ipairs(hits) do print("   " .. line) end

-- 2) Behaviour: load the probe against a client where one event is unknown and
--    another raises for a different reason, then read the recorded states.
local INVALID = "UNIT_SPELLCAST_START"      -- client says: unknown event
local WEIRD = "SKILL_LINES_CHANGED"         -- client raises something else

local function stub(name)
  local t = {}
  setmetatable(t, {
    __index = function(self, k)
      local v = stub(name .. "." .. tostring(k))
      rawset(self, k, v)
      return v
    end,
    __call = function() return stub(name .. "()") end,
    __tostring = function() return "<stub " .. name .. ">" end,
    __concat = function(a, b) return tostring(a) .. tostring(b) end,
  })
  return t
end

local frames = {}
local env = {
  tonumber = tonumber, tostring = tostring, type = type,
  pairs = pairs, ipairs = ipairs, select = select, unpack = unpack,
  error = error, pcall = pcall, print = print, assert = assert,
  table = table, string = string, math = math, os = os,
  GetTime = function() return 100 end,
  CreateFrame = function()
    local f = {
      RegisterEvent = function(_, e)
        if e == INVALID then
          error("Attempt to register unknown event \"" .. e .. "\"", 2)
        elseif e == WEIRD then
          error("cannot register right now", 2)
        end
        return true
      end,
      UnregisterEvent = function() return true end,
      SetScript = function() return true end,
    }
    frames[#frames + 1] = f
    return f
  end,
}
setmetatable(env, {
  __index = function(_, k)
    local v = stub(tostring(k))
    env[k] = v
    return v
  end,
})

local path = root .. "/MightiePack/Modules/Skinning/Probe.lua"
local chunk, err = loadfile(path)
check(chunk ~= nil, "Probe.lua parses: " .. tostring(err))
if chunk then
  setfenv(chunk, env)
  local pkg = {}
  local ok, loadErr = pcall(chunk, "MightiePack", pkg)
  check(ok, "Probe.lua loads: " .. tostring(loadErr))
  local P = pkg.Skinning and pkg.Skinning.Probe
  check(type(P) == "table", "probe table exists")
  if type(P) == "table" then
    local okE, errE = pcall(P.Enable, P)
    check(okE, "Enable does not raise: " .. tostring(errE))
    check(P._events["UNIT_SPELLCAST_SUCCEEDED"] == true,
      "a valid event records true")
    check(P._events[INVALID] == "invalid event",
      "an unknown event records 'invalid event' (got " .. tostring(P._events[INVALID]) .. ")")
    check(type(P._events[WEIRD]) == "string" and P._events[WEIRD] ~= "invalid event",
      "a different registration error keeps its own text")
    check(P.enabled == true, "the probe is enabled after Enable")
  end
end

if fails == 0 then
  print("event_gate_spec: ok")
else
  print(("event_gate_spec: %d failure(s)"):format(fails))
  os.exit(1)
end
