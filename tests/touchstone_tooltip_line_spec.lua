-- The item tooltip's verdict line carries NO addon name (t_c2e67619).
--
-- The line used to read "Touchstone: Upgrade — Strength +4". The addon's own
-- name is not wanted in the player's tooltip: the verdict word leads. The
-- prefix constant is emptied, and the duplicate guard that keyed on it now keys
-- on the word the line leads with — those two have to change together, so this
-- spec drives the REAL post-call through the real vendored file and checks both:
--
--   1. what lands on the tooltip has no "Touchstone: " in it;
--   2. the same line is still RECOGNISED on a second call (no duplicate row),
--      and a client line that merely contains a verdict word is not mistaken
--      for ours.
--
-- Fails on 16e7954: there the rendered line still starts with the prefix, and
-- the guard still searches for it.
--
-- Run from the repo root:  lua5.1 tests/touchstone_tooltip_line_spec.lua

local here = (arg and arg[0] or "tests/touchstone_tooltip_line_spec.lua")
  :match("^(.*)[/\\][^/\\]*$") or "."
local root = here:gsub("[/\\]tests$", "")
if root == "tests" then root = "." end
local TOUCH = root .. "/MightiePack/Modules/Touchstone/"

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local function fileExists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

if not fileExists(TOUCH .. "ChestAdvisor/ChestAdvisor.lua") then
  io.stderr:write("FAIL: the vendored Touchstone is absent — nothing to check\n")
  os.exit(1)
end

-- ---- WoW stub (the same shapes tests/touchstone_fold_spec.lua proves) ------
local chat, frames = {}, {}
-- The captured item-tooltip post-call (the client's own registration surface).
local postCall

local function makeTexture()
  local t = {}
  for _, m in ipairs({ "SetPoint", "SetAllPoints", "SetTexture", "SetColorTexture",
    "SetTexCoord", "SetSize", "Hide", "Show", "SetBlendMode", "SetDesaturated" }) do
    t[m] = function() end
  end
  return t
end

local function makeFontString()
  local fs = { text = "" }
  fs.SetPoint = function() end
  fs.SetAllPoints = function() end
  fs.SetText = function(_, v) fs.text = v end
  fs.GetText = function() return fs.text end
  fs.SetTextColor = function() end
  fs.Hide = function() end
  fs.Show = function() end
  return fs
end

local function makeFrame(kind, name)
  local f = { kind = kind, name = name, events = {}, scripts = {}, children = {} }
  f.RegisterEvent = function(_, e) f.events[e] = true end
  f.UnregisterEvent = function(_, e) f.events[e] = nil end
  f.IsEventRegistered = function(_, e) return f.events[e] == true end
  f.SetScript = function(_, k, fn) f.scripts[k] = fn end
  f.GetScript = function(_, k) return f.scripts[k] end
  f.HookScript = function() end
  f.CreateTexture = function() return makeTexture() end
  f.CreateFontString = function() return makeFontString() end
  frames[#frames + 1] = f
  if name then _G[name] = f end
  -- A method the stub does not model must not explode a load: it is a no-op.
  setmetatable(f, { __index = function() return function() end end })
  return f
end

local function resetEnv()
  chat, frames = {}, {}
  SlashCmdList = setmetatable({}, {
    __newindex = function(t, k, v) rawset(t, k, v) end,
  })
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = m end }
  CreateFrame = makeFrame
  UIParent = makeFrame("Frame", "UIParent")
  frames = {}
  MightiePackTouchstoneSkip = nil
  StatForge, StatForgeDB, ChestAdvisor, ChestAdvisorDB = nil, nil, nil, nil
  MightiePackDB = nil
  C_AddOns = { DoesAddOnExist = function() return false end }
  GetAddOnInfo, IsAddOnLoaded = nil, nil
  _G.ChestAdvisor_Frame = nil
  hooksecurefunc = function() end
  -- The tooltip post-call surface this client exposes. Captured here so the
  -- spec can call it exactly the way the client does.
  postCall = nil
  TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn)
      check(kind == 0, "post-call registered for TooltipDataType.Item")
      postCall = fn
    end,
  }
  Enum = { TooltipDataType = { Item = 0 } }
end

postCall = nil

local function loaded(path, ...)
  local chunk, err = loadfile(path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return false end
  local ok, runErr = pcall(chunk, ...)
  check(ok, "load " .. path .. ": " .. tostring(runErr))
  return ok
end

local VENDORED = {
  "Constants.lua", "UI.lua", "OptionsTab.lua", "UpgradesTab.lua", "LogTab.lua",
  "Diagnostics.lua", "Probe.lua", "ChestAdvisor/Verdict.lua",
  "ChestAdvisor/ChestAdvisor.lua", "Integration.lua", "Core.lua",
}

resetEnv()
local pkg = { Print = function(_, msg) chat[#chat + 1] = tostring(msg) end }
loaded(TOUCH .. "Bootstrap.lua", "MightiePack", pkg)
for _, name in ipairs(VENDORED) do
  loaded(TOUCH .. name, "MightiePack", pkg)
end
check(type(ChestAdvisor) == "table", "the vendored ChestAdvisor loaded")

ChestAdvisorDB = { role = {} }
local okEnable, enableErr = pcall(ChestAdvisor.Enable, ChestAdvisor)
check(okEnable, "ChestAdvisor.Enable runs: " .. tostring(enableErr))
check(type(postCall) == "function",
  "the item-tooltip post-call was registered through TooltipDataProcessor")

-- ---- A client tooltip, modelled on the real one ----------------------------
-- The client renders each AddLine into <name>TextLeft<i>; the text keeps its
-- colour escapes (that is what GetText returns, and what the guard reads).
local TIP_NAME = "GameTooltip"
local function makeTip(clientLines)
  local tip = { lines = {}, texts = {} }
  for i, l in ipairs(clientLines or {}) do tip.texts[i] = l end
  tip.GetName = function() return TIP_NAME end
  tip.NumLines = function(self) return #self.texts end
  tip.AddLine = function(self, text, r, g, b, wrap)
    self.lines[#self.lines + 1] = { text = text, r = r, g = g, b = b, wrap = wrap }
    self.texts[#self.texts + 1] = text
  end
  tip.SetText = function(self, text)
    self.lines[#self.lines + 1] = { text = text }
    self.texts[#self.texts + 1] = text
  end
  tip.__sync = function()
    -- The client renders every line into its own font string, in order.
    for i = 1, #tip.texts do
      local txt = tip.texts[i]
      _G[TIP_NAME .. "TextLeft" .. i] = { GetText = function() return txt end }
    end
    -- Nothing above the last rendered line may answer, or the guard would scan
    -- stale text from an earlier case in this file.
    for i = #tip.texts + 1, #tip.texts + 8 do
      _G[TIP_NAME .. "TextLeft" .. i] = { GetText = function() return nil end }
    end
  end
  return tip
end

local LINK = "|cff1eff00|Hitem:1234:0:0:0:0:0:0:0|h[Test Chest]|h|r"

ChestAdvisor.__verdicts = {
  [LINK] = { id = 1234, verdict = "UPGRADE", reason = "upgrade: Strength +4" },
}

local function rendered(tip)
  local out = {}
  for i = 1, #tip.lines do out[i] = tip.lines[i].text end
  return out
end

-- ---- 1. The rendered line carries no addon name ----------------------------
local tip = makeTip({ "Test Chest", "Item Level 70" })
tip:__sync()
local okCall, callErr = pcall(postCall, tip, { hyperlink = LINK })
check(okCall, "the post-call runs on an item tooltip: " .. tostring(callErr))
check(#tip.lines == 1, "one verdict line was appended (got " .. #tip.lines .. ")")
local headline = tip.lines[1] and tip.lines[1].text or ""
check(headline ~= "", "the verdict line is not empty")
check(headline:find("Touchstone", 1, true) == nil,
  "the rendered line carries no addon name (got: " .. headline .. ")")
-- The verdict word leads, after the colour escape the line opens with.
local plain = headline:gsub("^%|c%x%x%x%x%x%x%x%x", ""):gsub("%|r$", "")
check(plain:sub(1, #"Upgrade") == "Upgrade",
  "the verdict word leads the line (got: " .. plain .. ")")
check(plain:find("Strength +4", 1, true) ~= nil,
  "the headline keeps its detail (got: " .. plain .. ")")
check(tip.lines[1].wrap == true,
  "the line still lands through the wrapping AddLine path (5th argument)")

-- The block-level statement the card asks for, in one line.
print("rendered gear line: " .. plain)

-- ---- 2. Recognised on a second call: no duplicate row ----------------------
tip:__sync()
pcall(postCall, tip, { hyperlink = LINK })
check(#tip.lines == 1,
  "a second post-call on the same tooltip appends nothing (got " .. #tip.lines .. " lines)")
local dupes = 0
for _, l in ipairs(rendered(tip)) do
  if type(l) == "string" and l:find("Upgrade", 1, true) then dupes = dupes + 1 end
end
check(dupes == 1, "exactly one verdict row on the tooltip (got " .. dupes .. ")")

-- ---- 3. A client line that merely mentions a verdict word is not ours ------
-- The old guard searched for the prefix ANYWHERE in the line. The new one is
-- anchored at position 1, so the client's own sentence cannot suppress the row
-- (with an empty prefix the guard would have matched everything — this is the
-- regression the pair of edits exists to prevent).
local tip2 = makeTip({
  "Test Chest",
  "Upgrade available from the vendor", -- contains "Upgrade", but not as a lead
})
tip2:__sync()
pcall(postCall, tip2, { hyperlink = LINK })
check(#tip2.lines == 1,
  "a client line mentioning 'Upgrade' does not count as ours (got " .. #tip2.lines .. " appended)")
if tip2.lines[1] then
  check(tip2.lines[1].text:find("Touchstone", 1, true) == nil,
    "the line appended over it still carries no addon name")
end

-- ---- 4. No addon name anywhere in the vendored renderer --------------------
-- Every rendered surface reads the one constant, so this pins that the constant
-- itself is not the addon's name any more.
local f = io.open(TOUCH .. "ChestAdvisor/ChestAdvisor.lua", "rb")
local src = f and f:read("*a") or ""
if f then f:close() end
check(src ~= nil and src:find('TOOLTIP_PREFIX = "Touchstone: "', 1, true) == nil,
  "the vendored renderer no longer defines the addon-name prefix")
check(src ~= nil and src:find("text:find(TOOLTIP_PREFIX", 1, true) == nil,
  "the duplicate guard no longer searches for the (now empty) prefix")

if failed > 0 then
  io.stderr:write(("touchstone_tooltip_line_spec: %d failure(s)\n"):format(failed))
  os.exit(1)
end
print("touchstone_tooltip_line_spec: ok")
