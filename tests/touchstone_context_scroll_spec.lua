-- touchstone_context_scroll_spec.lua — audit A3 (Touchstone audit v0.3.10), the
-- half card t_ce1c4a4f left: the Context column must FLOW with the Settings stack.
--
-- THE DEFECT. The flow (card t_4e5ad8a4) places every block on the scrolled
-- `content` frame and the wheel moves `content`. The Context heading was the one
-- region left on `host`, pinned at the old fixed layout's (560, -293), and the
-- three boxes hang off it. So when the player scrolled the stack, the Role
-- heading moved and the Context column beside it stayed where it was — drawn
-- over whatever scrolled under it, and outside the viewport's clip.
--
-- WHAT THIS FILE PINS, on the SHIPPED file (rendered into a 900 x 240 host, short
-- enough that the stack must scroll):
--   K1  the heading and the three boxes are children of `host.content`, so the
--       viewport clips them with the rest of the stack.
--   K2  the heading sits on the Role heading's row, at content x 560 (the column
--       the tab's own comment and tests/t_1c9d5a17-settings.js measure).
--   K3  the stack scrolls (precondition), and after the wheel moves it the
--       heading and every box have moved by EXACTLY the Role heading's distance.
--
-- AND ITS OWN NON-VACUITY: a second copy of the shipped source with the heading
-- restored to the pre-fix lines (parent `host`, absolute (560, -293)) must fail
-- K1 and K3 — measured, not assumed. A mutation anchor that is not found FAILS.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local C = dofile(root .. "/tests/support/wowclient.lua")
C.Install({ width = 1920, height = 1080 })

local COLOR = { accent = { 0.4, 0.9, 0.95 }, textMuted = { 0.6, 0.6, 0.6 } }

-- The smallest StatForge a standalone load of the tab needs. Nothing here
-- implements the tab's behaviour: it is the host surface the file reads.
local function makeSF()
  local SF = {}
  SF.Colors = COLOR
  SF.optionControls = {}
  SF.VERSION = "spec"
  SF.RegisterTab = function(name, render) SF._tab = { name = name, render = render } end
  function SF.UI_CreateLabel(parent, text)
    local fs = parent:CreateFontString()
    fs:SetText(text or "")
    return fs
  end
  function SF.UI_CreateButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 100, h or 24)
    b:SetText(text or "")
    return b
  end
  function SF.UI_SetAccent() end
  function SF.UI_AccentText(s) return s end
  -- The accent wrapper the About block interpolates as a colour CODE.
  function SF.Accent(s) return "|cff66e6f2" .. tostring(s) .. "|r" end
  function SF.RepaintAccent() end
  function SF.SetTheme() end
  function SF.LogTabState() return {} end
  function SF.UpgradesTabState() return {} end
  function SF.ThemeAccent() return COLOR.accent end
  function SF.OnAccentRepaint() end
  function SF.GetWindowScale() return 1 end
  function SF.SetWindowScale() end
  function SF.WindowScaleBounds() return 0.5, 1.5 end
  function SF.ShowDiagnosticsPanel() end
  function SF.UpdateMinimapButton() end
  return SF
end

-- The advisor surface the tab reads for its Context row. These ARE the three
-- contexts Arbitration.CONTEXTS defines (leveling, dungeon, raid), in that order.
local CONTEXTS = {
  { word = "leveling", label = "Leveling", meaning = "Questing and solo play." },
  { word = "dungeon",  label = "Dungeon",  meaning = "Five-player instances." },
  { word = "raid",     label = "Raid",     meaning = "Group content with many players." },
}

ChestAdvisorDB = {}
local ADV = {
  contextOptions = CONTEXTS,
  context = function() return "leveling" end,
}
-- The tab reads the advisor at CALL time (the Context loop asks it what the
-- contexts are when the tab renders), so the global has to be in place for the
-- whole render, not only for the chunk's own evaluation.
ChestAdvisor = ADV

local function loadTab(source, sf)
  local savedSF = StatForge
  StatForge = sf
  -- Lua 5.1 spells it loadstring; 5.2+ spells the string form `load`.
  local loader = loadstring or load
  local chunk, err = loader(source, "OptionsTab")
  local ok, e = false, err
  if chunk then ok, e = pcall(chunk) end
  StatForge = savedSF
  check(ok, "the shipped OptionsTab.lua loads: " .. tostring(e))
  return sf._tab
end

local function boxOf(host, word)
  return host.contextChecks and host.contextChecks[word] or nil
end

local PATH = root .. "/MightiePack/Modules/Touchstone/OptionsTab.lua"
local fh = assert(io.open(PATH, "rb"))
local SOURCE = fh:read("*a"):gsub("\r\n", "\n")
fh:close()


local EPS = 0.05

-- A SHORT body, so the stack is guaranteed taller than it and the wheel has room
-- to move it: the claim under test is "scrolls WITH the stack", not "the stack
-- overflows at 441" (window_settings_flow_spec.lua pins that, on the full window).
local function renderedShort(tab)
  local host = CreateFrame("Frame", "TouchstoneOptionsHostShort", UIParent)
  host:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  host:SetSize(900, 240)
  tab.render(host)
  return host
end

-- Everything the checks need, measured on one rendered host.
local function measure(host)
  local m = { ok = false }
  local content, viewport = host.content, host.viewport
  local header, role = host.contextHeader, host.roleHeader
  local boxes = { boxOf(host, "leveling"), boxOf(host, "dungeon"), boxOf(host, "raid") }
  if not (content and viewport and header and role and boxes[1] and boxes[2] and boxes[3]) then
    return m
  end
  m.ok = true
  m.parents = { header:GetParent() == content }
  for i = 1, 3 do m.parents[i + 1] = boxes[i]:GetParent() == content end
  local hr, rr, cr = C.Rect(header), C.Rect(role), C.Rect(content)
  m.headerTop0, m.roleTop0 = hr.top, rr.top
  m.headerX = hr.left - cr.left
  local boxTop0 = {}
  for i = 1, 3 do boxTop0[i] = C.Rect(boxes[i]).top end
  -- Wheel down until the stack has moved; the clamp keeps it inside the overflow.
  for _ = 1, 4 do C.FireScript(viewport, "OnMouseWheel", -1) end
  m.scroll = host.scroll or 0
  m.scrollMax = host.scrollMax or 0
  m.roleDy = C.Rect(role).top - rr.top
  m.headerDy = C.Rect(header).top - hr.top
  m.boxDy = {}
  for i = 1, 3 do m.boxDy[i] = C.Rect(boxes[i]).top - boxTop0[i] end
  return m
end

local function k1(m)
  if not m.ok then return false end
  for _, p in ipairs(m.parents) do if not p then return false end end
  return true
end

local function k3(m)
  if not m.ok or not (m.scroll > 0) or math.abs(m.roleDy) < 1 then return false end
  if math.abs(m.headerDy - m.roleDy) > EPS then return false end
  for i = 1, 3 do if math.abs(m.boxDy[i] - m.roleDy) > EPS then return false end end
  return true
end

-- ── the shipped file ───────────────────────────────────────────────────────
local tab = loadTab(SOURCE, makeSF())
check(type(tab) == "table" and type(tab.render) == "function",
  "the tab registers its render with SF.RegisterTab")
local m = measure(renderedShort(tab))
check(m.ok, "the Context heading, the three boxes, the Role heading, content and viewport all exist")
if m.ok then
  io.write(string.format("  shipped  heading x=%.1f (role top %.1f, heading top %.1f); scroll %.1f -> "
    .. "role moved %.1f, heading %.1f, boxes %.1f/%.1f/%.1f\n", m.headerX, m.roleTop0, m.headerTop0,
    m.scroll, m.roleDy, m.headerDy, m.boxDy[1], m.boxDy[2], m.boxDy[3]))
  check(k1(m), "K1: the Context heading and its three boxes are children of the scrolled content")
  check(math.abs(m.headerTop0 - m.roleTop0) < EPS,
    "K2: the Context heading sits on the Role heading's row")
  check(math.abs(m.headerX - 560) < EPS,
    "K2: the Context heading is at content x 560 (got " .. string.format("%.1f", m.headerX) .. ")")
  check(m.scroll > 0, "K3 precondition: the stack scrolls in a 240-unit body (scroll "
    .. string.format("%.1f", m.scroll) .. " of " .. string.format("%.1f", m.scrollMax) .. ")")
  check(k3(m), "K3: scrolled, the heading and every box moved exactly as far as the Role heading")
end

-- ── non-vacuity: the pre-fix heading, in a second copy ─────────────────────
local FROM = '  local contextHeader = SF.UI_CreateLabel(content, "Context", "GameFontNormal")\n'
  .. '  contextHeader:SetPoint("TOPLEFT", roleHeader, "TOPLEFT", 540, 0)\n'
local TO = '  local contextHeader = SF.UI_CreateLabel(host, "Context", "GameFontNormal")\n'
  .. '  contextHeader:SetPoint("TOPLEFT", 560, -293)\n'
local at = SOURCE:find(FROM, 1, true)
check(at ~= nil, "the heading lines this spec reverts are present in the shipped source")
if at then
  local mutated = SOURCE:sub(1, at - 1) .. TO .. SOURCE:sub(at + #FROM)
  local m2 = measure(renderedShort(loadTab(mutated, makeSF())))
  check(m2.ok, "mutation: the pre-fix copy still renders the Context column")
  if m2.ok then
    io.write(string.format("  pre-fix  scroll %.1f -> role moved %.1f, heading %.1f, boxes %.1f/%.1f/%.1f\n",
      m2.scroll, m2.roleDy, m2.headerDy, m2.boxDy[1], m2.boxDy[2], m2.boxDy[3]))
    check(not k1(m2), "NON-VACUITY: the pre-fix heading is not a child of the scrolled content")
    check(not k3(m2), "NON-VACUITY: the pre-fix heading stays put while the stack scrolls")
  end
end

if failed > 0 then
  io.stderr:write(tostring(failed) .. " check(s) failed\n")
  os.exit(1)
end
io.write("PASS: the Context column is on the scrolled content, on Role's row at x 560, and "
  .. "scrolls with it — and the pinned pre-fix shape is measured red.\n")
