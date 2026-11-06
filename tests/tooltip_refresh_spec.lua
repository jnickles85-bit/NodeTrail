local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

local pkg = {}
local function loadFile(path)
  local f = assert(loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path))
  f("MightiePack", pkg)
end

-- Client model (Forever client, as observed in Mightie's smoke test):
--  * repopulate of an already-visible tooltip = ClearLines + new content,
--    WITHOUT firing OnTooltipCleared;
--  * a repopulate replaces the content without necessarily calling Show again.
loadFile("locale/enUS.lua")
loadFile("Config.lua")
loadFile("Data/Recorder.lua")
loadFile("Data/HerbData.lua")
loadFile("Data/Recipes.lua")
loadFile("UI/Tooltip.lua")

local ns = pkg.NodeTrail

time = time or os.time
CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == table and CopyTable(v) or v end return c end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
CreateFrame = function() return { SetScript = function() end, RegisterEvent = function() end } end
GetSpellInfo = function() return nil end
local mouseoverUnit = false
UnitExists = function(u) return u == "mouseover" and mouseoverUnit end
UIParent = {}
WorldFrame = {}

local GT = {
  lines = {},
  hooks = {},
  scripts = {},
  owner = UIParent,
}
GT.HookScript = function(self, name, fn)
  self.hooks[name] = self.hooks[name] or {}
  table.insert(self.hooks[name], fn)
end
GT.SetScript = function(self, name, fn) self.scripts[name] = fn end
GT.GetOwner = function(self) return self.owner end
GT.NumLines = function(self) return #self.lines end
GT.AddLine = function(self, t) table.insert(self.lines, t) end
GT.AddDoubleLine = function(self, l, r) table.insert(self.lines, l .. " | " .. r) end
GT.Show = function(self)
  for _, fn in ipairs(self.hooks.OnShow or {}) do
    fn(self)
  end
end
-- Client clear: wipes every line and deliberately does NOT fire
-- OnTooltipCleared (the behaviour this spec guards against).
GT.ClearLines = function(self)
  self.lines = {}
end
GameTooltip = GT

_G["GameTooltipTextLeft1"] = { GetText = function() return GT.lines[1] end }

-- Client driver
local function clientRepopulate(name, viaApi)
  GT:ClearLines()
  if viaApi then
    -- real client populates through its AddLine API
    GT:AddLine(name)
    GT:AddLine("Herbalism")
  else
    GT.lines = { name, "Herbalism" }
  end
end

local function hover(name, viaApi)
  clientRepopulate(name, viaApi)
  GT:Show()
end

-- The client frame clock: OnUpdate on the tooltip frame ticks between frames.
local function pump()
  if GT.scripts.OnUpdate then
    GT.scripts.OnUpdate(GT, 0.01)
  end
end

local function headerCount()
  local n = 0
  for _, l in ipairs(GT.lines) do
    if l == "NodeTrail" then n = n + 1 end
  end
  return n
end

local function has(line)
  for _, l in ipairs(GT.lines) do
    if l == line then return true end
  end
  return false
end

-- Test 1: loading adds no hooks; Enable is idempotent (one OnShow hook)
check(GT.hooks.OnShow == nil or #GT.hooks.OnShow == 0, "Test 1: no OnShow hooks at load")
ns.Tooltip:Enable()
ns.Tooltip:Enable()
check(GT.hooks.OnShow and #GT.hooks.OnShow == 1, "Test 1: Enable idempotent — exactly one OnShow hook")

-- Test 2: baseline hover still works (the first hover of the session)
hover("Peacebloom")
check(headerCount() == 1, "Test 2: header present exactly once on first hover")
check(has("Peacebloom | 100% (base)"), "Test 2: Peacebloom drop line present")
check(has("Your picks: none yet"), "Test 2: picks line present")

-- Test 3: the client re-populates the SAME herb (the in-game 'flash'):
-- no OnTooltipCleared, and no new Show. The block must be back exactly once.
clientRepopulate("Peacebloom", true)
pump()
check(has("Peacebloom | 100% (base)"), "Test 3: block self-heals after same-herb repopulate")
check(headerCount() == 1, "Test 3: header exactly once after same-herb repopulate")

-- Test 4: move to a DIFFERENT herb after a repopulate (the 'Briarthorn shows
-- nothing' symptom). New herb's block must appear, old lines must be gone.
clientRepopulate("Briarthorn", false)
pump()
check(has("Briarthorn | 100% (base)"), "Test 4: Briarthorn drop line present")
check(has("Swiftthistle | 10% (base)"), "Test 4: Briarthorn Swiftthistle line present")
check(not has("Peacebloom | 100%"), "Test 4: stale Peacebloom line gone")
check(headerCount() == 1, "Test 4: header exactly once after herb switch")

-- Test 5: duplicate-hook case — the same population fires the OnShow hook(s)
-- again (several hooks for one tooltip); no duplicate headers may appear.
for _, fn in ipairs(GT.hooks.OnShow or {}) do fn(GT) end
for _, fn in ipairs(GT.hooks.OnShow or {}) do fn(GT) end
pump()
check(headerCount() == 1, "Test 5: no duplicate header when several hooks fire")
check(has("Briarthorn | 100% (base)"), "Test 5: Briarthorn line still present")

-- Test 6: unknown object adds nothing
hover("Stone Vein")
pump()
check(not has("NodeTrail"), "Test 6: unknown object adds no NodeTrail lines")
check(#GT.lines == 2, "Test 6: only client lines remain")

-- Test 7: unit tooltip still ignored, and that does not poison the next herb
mouseoverUnit = true
hover("Peacebloom")
pump()
check(not has("NodeTrail"), "Test 7: unit tooltip ignored")
mouseoverUnit = false
hover("Peacebloom")
check(has("Peacebloom | 100% (base)"), "Test 7: block returns on the next real herb hover")
check(headerCount() == 1, "Test 7: header exactly once")

-- Test 8: repeated client clock ticks must not duplicate the block
pump()
pump()
check(headerCount() == 1, "Test 8: clock pump is idempotent")

-- Test 9: nothing errored along the way
check(ns.Tooltip._error == nil, "Test 9: ns.Tooltip._error == nil")

if failed > 0 then
  os.exit(1)
else
  print("tooltip_refresh_spec: ok")
end
