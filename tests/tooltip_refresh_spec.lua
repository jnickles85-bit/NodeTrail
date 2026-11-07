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

-- Client model (as observed in Mightie's smoke test):
--  * a repopulate of an already-visible tooltip may rewrite the content
--    directly — a C-side SetUnit / SetGameObject path that never calls the
--    Lua ClearLines method and never fires a hook the addon can wrap;
--  * a repopulate replaces content without necessarily calling Show again;
--  * while a tooltip is visible the client ticks the update clock.
loadFile("locale/enUS.lua")
loadFile("Config.lua")
loadFile("Data/Recorder.lua")
loadFile("Data/HerbData.lua")
loadFile("Data/Recipes.lua")
loadFile("UI/Tooltip.lua")

local ns = pkg.NodeTrail
local T = ns.Tooltip

time = time or os.time
CopyTable = function(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == table and CopyTable(v) or v end return c end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
GetSpellInfo = function() return nil end
local mouseoverUnit = false
UnitExists = function(u) return u == "mouseover" and mouseoverUnit end
UIParent = {}
WorldFrame = {}

-- Private helper frames the addon may create (the v2 poller lives here).
local frames = {}
CreateFrame = function(kind, name)
  local f = { kind = kind, name = name, scripts = {}, shown = false }
  f.SetScript = function(self, n, fn) self.scripts[n] = fn end
  f.GetScript = function(self, n) return self.scripts[n] end
  f.Show = function(self) self.shown = true end
  f.Hide = function(self) self.shown = false end
  frames[#frames + 1] = f
  return f
end

local GT = {
  lines = {},
  hooks = {},
  scripts = {},
  shown = false,
  owner = UIParent,
}
GT.HookScript = function(self, name, fn)
  self.hooks[name] = self.hooks[name] or {}
  table.insert(self.hooks[name], fn)
end
GT.SetScript = function(self, name, fn) self.scripts[name] = fn end
GT.GetOwner = function(self) return self.owner end
GT.IsShown = function(self) return self.shown end
GT.Show = function(self)
  self.shown = true
  for _, fn in ipairs(self.hooks.OnShow or {}) do
    fn(self)
  end
end
GT.Hide = function(self)
  self.shown = false
  for _, fn in ipairs(self.hooks.OnHide or {}) do
    fn(self)
  end
end
GT.NumLines = function(self) return #self.lines end
GT.GetLine = function(self, i)
  local l = self.lines[i]
  if type(l) == "string" then return l end
  return nil
end
GT.AddLine = function(self, t) table.insert(self.lines, t) end
GT.AddDoubleLine = function(self, l, r) table.insert(self.lines, l .. " | " .. r) end
-- Client clear: wipes every line and deliberately does NOT fire
-- OnTooltipCleared (the behaviour this spec guards against).
GT.ClearLines = function(self)
  self.lines = {}
end
GameTooltip = GT

_G["GameTooltipTextLeft1"] = { GetText = function() return GT.lines[1] end }

-- Refresh spy: counts every time the addon evaluates a refresh, whether or
-- not it ends up a no-op.
local refreshCalls = 0
local origRefresh = T.Refresh
T.Refresh = function(self, tt)
  refreshCalls = refreshCalls + 1
  return origRefresh(self, tt)
end

-- Client driver
local function clientRepopulate(name, viaApi)
  if viaApi then
    -- repopulate through the Lua API: ClearLines + new content, no
    -- OnTooltipCleared — the path the v1 fix could see.
    GT:ClearLines()
    GT:AddLine(name)
    GT:AddLine("Herbalism")
  else
    -- the C-side repopulate path: content is assigned directly, no Lua
    -- clear call, no hook — the clear the addon never sees.
    GT.lines = { name, "Herbalism" }
  end
end

local function hover(name, viaApi)
  clientRepopulate(name, viaApi)
  GT:Show()
end

local function fire(event)
  for _, fn in ipairs(GT.hooks[event] or {}) do
    fn(GT)
  end
end

-- Backstop clock: tick the addon's private poller when it exists; fall back
-- to the v1 GameTooltip OnUpdate so this spec can also run against pre-v2
-- code (where the unseen-clear tests must come out red).
local function pollTick(elapsed)
  local e = elapsed or 0.2
  local poller = T.poller
  if poller and poller.scripts and poller.scripts.OnUpdate then
    poller.scripts.OnUpdate(poller, e)
  elseif GT.scripts and GT.scripts.OnUpdate then
    GT.scripts.OnUpdate(GT, e)
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
check(T.poller ~= nil, "Test 1: private poller frame created in Enable")
check(GT.scripts.OnUpdate == nil, "Test 1: GameTooltip keeps its own scripts (no OnUpdate clobber)")

-- Test 2: baseline hover still works (the first hover of the session)
hover("Peacebloom")
check(headerCount() == 1, "Test 2: header present exactly once on first hover")
check(has("Peacebloom | 100% (base)"), "Test 2: Peacebloom drop line present")
check(has("Your picks: none yet"), "Test 2: picks line present")

-- Test 3: the client re-populates the SAME herb (the in-game 'flash'):
-- no OnTooltipCleared, and no new Show. The block must be back exactly once.
clientRepopulate("Peacebloom", true)
pollTick()
check(has("Peacebloom | 100% (base)"), "Test 3: block self-heals after same-herb repopulate")
check(headerCount() == 1, "Test 3: header exactly once after same-herb repopulate")

-- Test 4: move to a DIFFERENT herb after a repopulate (the 'Briarthorn shows
-- nothing' symptom). New herb's block must appear, old lines must be gone.
clientRepopulate("Briarthorn", false)
pollTick()
check(has("Briarthorn | 100% (base)"), "Test 4: Briarthorn drop line present")
check(has("Swiftthistle | 10% (base)"), "Test 4: Briarthorn Swiftthistle line present")
check(not has("Peacebloom | 100%"), "Test 4: stale Peacebloom line gone")
check(headerCount() == 1, "Test 4: header exactly once after herb switch")

-- Test 5: duplicate-hook case — the same population fires the OnShow hook(s)
-- again (several hooks for one tooltip); no duplicate headers may appear.
for _, fn in ipairs(GT.hooks.OnShow or {}) do fn(GT) end
for _, fn in ipairs(GT.hooks.OnShow or {}) do fn(GT) end
pollTick()
check(headerCount() == 1, "Test 5: no duplicate header when several hooks fire")
check(has("Briarthorn | 100% (base)"), "Test 5: Briarthorn line still present")

-- Test 6: unknown object adds nothing
hover("Stone Vein")
pollTick()
check(not has("NodeTrail"), "Test 6: unknown object adds no NodeTrail lines")
check(#GT.lines == 2, "Test 6: only client lines remain")

-- Test 7: unit tooltip still ignored, and that does not poison the next herb
mouseoverUnit = true
hover("Peacebloom")
pollTick()
check(not has("NodeTrail"), "Test 7: unit tooltip ignored")
mouseoverUnit = false
hover("Peacebloom")
check(has("Peacebloom | 100% (base)"), "Test 7: block returns on the next real herb hover")
check(headerCount() == 1, "Test 7: header exactly once")

-- Test 8: repeated clock ticks must not duplicate the block
pollTick()
pollTick()
check(headerCount() == 1, "Test 8: clock pump is idempotent")

-- Test 9: UNSEEN CLEAR — the client wipes the tooltip without going through
-- anything the addon wrapped: no ClearLines call, no clear hook, no Show.
-- Content is the truth: one poll tick must re-append the block exactly once.
check(headerCount() == 1, "Test 9: precondition — block present before unseen wipe")
GT.lines = { "Peacebloom", "Herbalism" }
check(headerCount() == 0, "Test 9: unseen wipe took our block (header gone)")
local callsBefore9 = refreshCalls
pollTick()
check(refreshCalls == callsBefore9 + 1, "Test 9: one poll tick evaluated a refresh")
check(has("Peacebloom | 100% (base)"), "Test 9: Peacebloom drop line present after unseen wipe")
check(headerCount() == 1, "Test 9: header present exactly once after one poll tick")

-- Test 10: POPULATE-EVENT FAST PATH — firing OnTooltipSetUnit /
-- OnTooltipSetItem after a client repopulate restores the block without
-- waiting for a poll tick.
GT.lines = { "Peacebloom", "Herbalism" }
check(headerCount() == 0, "Test 10: unseen wipe took our block (header gone)")
fire("OnTooltipSetUnit")
check(headerCount() == 1, "Test 10: OnTooltipSetUnit restores the block without a poll")
check(has("Peacebloom | 100% (base)"), "Test 10: block content correct after SetUnit restore")
GT.lines = { "Peacebloom", "Herbalism" }
fire("OnTooltipSetItem")
check(headerCount() == 1, "Test 10: OnTooltipSetItem restores the block without a poll")

-- Test 11: the poll must do nothing while the tooltip is hidden
check(headerCount() == 1, "Test 11: precondition — block present")
GT:Hide()
local callsBefore11 = refreshCalls
local linesBefore11 = #GT.lines
pollTick(0.2)
pollTick(0.2)
check(refreshCalls == callsBefore11, "Test 11: poll does nothing while tooltip hidden")
check(#GT.lines == linesBefore11, "Test 11: hidden — no lines change")
GT:Show()
check(headerCount() == 1, "Test 11: re-show keeps exactly one header")

-- Test 12: polling is capped at ~5x/second
local callsBefore12 = refreshCalls
for i = 1, 8 do
  pollTick(0.05)
end
check(refreshCalls == callsBefore12 + 2, "Test 12: 0.4s of ticks evaluates the refresh at most ~5x/s (exactly 2)")
check(headerCount() == 1, "Test 12: no duplicate header from throttled polls")

-- Test 13: nothing errored along the way
check(T._error == nil, "Test 13: ns.Tooltip._error == nil")

if failed > 0 then
  os.exit(1)
else
  print("tooltip_refresh_spec: ok")
end
