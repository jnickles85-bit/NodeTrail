-- window_inner_input_spec.lua — card t_cdee6bb6: the INPUT half of the strata
-- class, one layer down.
--
-- The paint half was fixed on t_5d0cc41a: the window's fill moved to its own
-- BACKGROUND frame, so the hosted Touchstone body (MEDIUM) is no longer painted
-- over. The owner's live retest of cb358e1: Touchstone renders at full
-- brightness, the border is present — and its INNER controls are dead. The
-- Upgrades / Log / Settings strip does not respond, nor do the panel's buttons,
-- while the four OUTER tabs still work.
--
-- The mechanism is the same strata rule, read for the mouse instead of the
-- brush. Mouse hit-testing uses the same ordering as painting — strata first,
-- then frame level — and the window frame sat in DIALOG with EnableMouse(true):
--
--     Window.lua:191  window frame  SetFrameStrata("DIALOG")
--     Window.lua:192  window frame  EnableMouse(true)      <-- the click-eater
--     Window.lua:223  fill (W.bg)   EnableMouse(false)     BACKGROUND
--     Window.lua:560  Touchstone    SetFrameStrata("MEDIUM")
--
-- So the chrome frame is above the MEDIUM body for input as well, and every
-- click over the body is handed to the window instead of to the control under
-- the cursor. Nothing was wrong with Touchstone's own controls; they were never
-- reached.
--
-- This file pins the BEHAVIOUR, not the structure — what the client's own
-- `GetMouseFocus()` would answer at a point, modelled by the harness:
--
--   AC-1  a click at the centre of an inner tab (Upgrades / Log / Settings) is
--         owned by that button, and the owner's ancestor chain contains
--         StatForgeMainFrame. Same for a panel button inside an inner tab.
--   AC-2  a click at the centre of an OUTER tab button is still owned by that
--         button (the window_tab_clicks_spec invariant, re-measured here
--         because this fix moves the input ordering the whole window sits on).
--   AC-3  a click in EMPTY window area is owned by a frame of the window, never
--         by the world: the fix must not trade a dead control for a window you
--         can click through into the camera.
--   TEETH the same detector, run against a deliberately installed DIALOG cover
--         over an inner tab, must name it. A detector that cannot fail is not
--         evidence.
--
-- The RED this file produced at cb358e1 named the taker: every inner control
-- answered `MightiePackWindow`, the window's DIALOG frame.
--
-- Harness: tests/support/wowclient.lua (C.MouseOwnerAt = GetMouseFocus at a
-- point, C.MouseChain = the owner-and-ancestors read the owner pasted from his
-- client). Not a screenshot: harness evidence. The live verdict is the owner's.

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
-- The client's convenience globals, which the harness does not model.
tinsert, tremove, tsort = table.insert, table.remove, table.sort
format = string.format
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local pkg = {}
local function loadFile(path)
  local chunk, err = loadfile(root .. "/MightiePack/" .. path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. path .. ": " .. tostring(e))
end

-- The owner's live state, reduced to the keys that matter: both modules on,
-- Touchstone used before (no first-use splash in play at all).
MightiePackDB = { modules = { NodeTrail = true, Touchstone = true }, seen = { firstRun = true }, bugCount = 0 }
NodeTrailDB = {
  schema = 2,
  herbs = { schema = 2, total = 0, maps = {}, mapTotals = {}, stats = { gathers = {}, co = {}, names = {} }, hotspots = {}, folded = {} },
  skinning = { enabled = true, schema = 2, chars = {} },
  route = {},
}
StatForgeDB = { ui = { scale = 1 }, firstUse = false }

-- Load in TOC order, exactly as the client does: the Touchstone body this file
-- measures is the real vendored UI, not a stub.
local tocPath = root .. "/MightiePack/MightiePack.toc"
local toc = assert(io.open(tocPath, "r"), "cannot open " .. tocPath)
local tocText = toc:read("*a")
toc:close()
local files = {}
for line in tocText:gmatch("[^\r\n]+") do
  local t = line:gsub("^%s+", ""):gsub("%s+$", "")
  if t ~= "" and not t:match("^##") then files[#files + 1] = t end
end
check(#files > 0, "the TOC lists files")
for _, f in ipairs(files) do loadFile(f) end

local okEnable, errEnable = pcall(pkg.EnableModules)
check(okEnable, "the enabled modules start (as they do at login): " .. tostring(errEnable))

local W = pkg.Window
check(type(W) == "table", "pkg.Window exists")
local win = W.Frame()
check(type(win) == "table", "the window frame is created")
check(W.Open("touchstone") == true, "the window opens on the touchstone tab")

local SF = rawget(_G, "StatForge")
local body = rawget(_G, "StatForgeMainFrame")
local host = W.hosts and W.hosts.touchstone

-- ── Naming helpers ─────────────────────────────────────────────────────────
local function nameOf(f)
  if type(f) ~= "table" then return "the world (no frame owns the click)" end
  return tostring(f.Name or "(unnamed)") .. "/" .. tostring(f.kind)
end

local function ancestorChain(f)
  local out = {}
  local p = f
  for _ = 1, 12 do
    if type(p) ~= "table" then break end
    out[#out + 1] = nameOf(p) .. " L" .. tostring(p:GetFrameLevel())
    p = p:GetParent()
  end
  return table.concat(out, " <- ")
end

local function contains(frame, target)
  local p = frame
  for _ = 1, 12 do
    if type(p) ~= "table" then return false end
    if p == target then return true end
    p = p:GetParent()
  end
  return false
end

--- The frame the client would hand a click to at a region's centre, plus the
--- chain it prints. `what` goes into the failure text so a red line names the
--- control AND the taker.
local function ownerAt(control, what)
  local x, y = C.Centre(control)
  local owner = C.MouseOwnerAt(x, y)
  return owner, x, y
end

-- ── PREMISE: the body is hosted, shown, and has the three inner tabs ───────
check(type(body) == "table", "StatForgeMainFrame exists (the vendored Touchstone body)")
check(type(host) == "table", "the touchstone host exists")
if type(body) ~= "table" or type(host) ~= "table" then
  print("window_inner_input_spec: cannot measure without the hosted body")
  os.exit(1)
end
check(body:GetParent() == host, "the Touchstone body is parented into the touchstone host")
check(C.Visible(body), "the Touchstone body is visible inside the open window")

--- The vendored inner strip: the body's 32px child (the same frame
--- AttachTouchstone re-anchors). Found by measurement, not by name, because the
--- vendored UI names none of its strip frames.
local strip
for _, child in ipairs(body:GetChildren()) do
  if math.abs(C.Rect(child).height - 32) < 0.5 then strip = child end
end
check(type(strip) == "table", "the body has its 32px inner tab strip")
if type(strip) ~= "table" then
  print("window_inner_input_spec: cannot measure without the inner strip")
  os.exit(1)
end

local innerTabs = {}
for _, btn in ipairs(strip:GetChildren()) do
  if btn.kind == "Button" and type(btn.label) == "table" and type(btn.label.GetText) == "function" then
    local text = btn.label:GetText()
    if text == "Upgrades" or text == "Log" or text == "Settings" then
      innerTabs[#innerTabs + 1] = { text = text, btn = btn }
    end
  end
end
check(#innerTabs == 3,
  "the inner strip carries the three tabs (Upgrades / Log / Settings), found " .. #innerTabs)
if #innerTabs ~= 3 then
  print("window_inner_input_spec: cannot measure without the three inner tabs")
  os.exit(1)
end

-- ── AC-1a: the INNER TABS get their own clicks ─────────────────────────────
-- This is the owner's report, measured: his click over "Log" went to the
-- window, so the Log button's own handler never ran.
for _, t in ipairs(innerTabs) do
  local owner, x, y = ownerAt(t.btn, t.text)
  local okChain = type(owner) == "table" and contains(owner, body)
  check(owner == t.btn and okChain,
    ("a click at the centre of the inner \"%s\" tab (%.0f,%.0f) reaches the body: "
      .. "got %s; chain %s")
      :format(t.text, x, y, nameOf(owner), ancestorChain(owner)))
  print(("inner tab \"%s\" (%.0f,%.0f) -> %s | %s")
    :format(t.text, x, y, nameOf(owner), ancestorChain(owner)))
end

-- The inner strip must also SWITCH when its own button's script is fired: the
-- hit test alone proves the click would arrive, not that the wire behind it
-- works. Firing the button's OnClick is the closest a harness comes to the
-- client's dispatch (window_tab_clicks_spec's rule: never call SelectTab).
-- Done below, AFTER the Upgrades panel button is measured, because switching
-- tabs hides the Upgrades host.
local logTab
for _, t in ipairs(innerTabs) do
  if t.text == "Log" then logTab = t.btn end
end

-- ── AC-1b: the PANEL BUTTONS inside an inner tab get their clicks ──────────
-- Two tabs, because the owner said the whole panel is dead, not one strip:
-- the Upgrades tab's own button (the tab the window opens on) and the Log
-- tab's "Clear log", which only exists after the strip above switched tabs.
local SFcontent = type(SF) == "table" and type(SF.GetContentFrame) == "function"
  and SF.GetContentFrame() or nil
check(type(SFcontent) == "table", "the body exposes its content frame")

local function measurePanelButton(btn, what)
  if type(btn) ~= "table" then
    check(false, "the " .. what .. " exists")
    return
  end
  local owner, x, y = ownerAt(btn, what)
  local okChain = type(owner) == "table" and contains(owner, body)
  check(owner == btn and okChain,
    ("a click at the centre of the %s (%.0f,%.0f) reaches the body: got %s; chain %s")
      :format(what, x, y, nameOf(owner), ancestorChain(owner)))
  check(btn:IsMouseEnabled(), "the " .. what .. " is mouse-enabled")
  print(("%s (%.0f,%.0f) -> %s | %s")
    :format(what, x, y, nameOf(owner), ancestorChain(owner)))
end

-- Before the switch: the Upgrades tab is the visible one.
local shownHost
for _, h in ipairs(type(SFcontent) == "table" and SFcontent:GetChildren() or {}) do
  if type(h) == "table" and h:IsShown() then shownHost = h end
end
check(type(shownHost) == "table", "the visible inner tab has a host frame")
if type(shownHost) == "table" then
  measurePanelButton(shownHost.toggle, "Upgrades tab button")
else
  check(false, "the Upgrades tab button exists")
end

-- After the switch: the Log tab's own button. Measured after the inner strip
-- above fired the Log tab's OnClick, so this reads the panel the click built.
local logScript = type(logTab) == "table" and logTab:GetScript("OnClick")
check(type(logScript) == "function", "the inner Log tab has its own OnClick script")
if type(logScript) == "function" then
  local okFire, err = pcall(logScript, logTab, "LeftButton")
  check(okFire, "firing the inner Log tab's OnClick does not raise: " .. tostring(err))
end
local logHost
for _, h in ipairs(type(SFcontent) == "table" and SFcontent:GetChildren() or {}) do
  if type(h) == "table" and h:IsShown() and h ~= shownHost then logHost = h end
end
check(type(logHost) == "table", "the Log tab has a host frame after the switch")
if type(logHost) == "table" then
  measurePanelButton(logHost.clear, "Log tab button")
else
  check(false, "the Log tab button exists")
end

-- ── AC-2: the OUTER tabs still win their own clicks ────────────────────────
-- The window_tab_clicks_spec invariant, re-measured here: this fix changes the
-- input ordering of the whole window, and the four outer buttons are the row
-- that was repaired one card ago.
for _, id in ipairs(W.TABS) do
  local btn = W.tabButtons and W.tabButtons[id]
  if type(btn) == "table" then
    local owner, x, y = ownerAt(btn, id)
    check(owner == btn,
      ("a click at the centre of the outer %s tab (%.0f,%.0f) is still owned by that "
        .. "button: got %s; chain %s")
        :format(id, x, y, nameOf(owner), ancestorChain(owner)))
  else
    check(false, "there is a button for the outer " .. id .. " tab")
  end
end

-- ── The chrome keeps its own clicks ────────────────────────────────────────
-- Turning the window frame's mouse off must not cost the affordances that
-- lived on the chrome. The drag handle is the title bar (its OnDragStart moves
-- the WINDOW, not the bar), and the close button sits on it — both have to own
-- their own clicks on their own rect, or the fix would have traded a dead panel
-- for a window nobody can move or close.
do
  local bar = W.titleBar
  check(type(bar) == "table", "the window has a title bar")
  if type(bar) == "table" then
    check(bar:IsMouseEnabled(), "the title bar (the drag handle) is mouse-enabled")
    check(type(bar:GetScript("OnDragStart")) == "function",
      "the title bar still carries the drag handler")
    local bx, by = C.Centre(bar)
    local owner = C.MouseOwnerAt(bx, by)
    check(owner == bar,
      ("a click on the title bar (%.0f,%.0f) is owned by the title bar: got %s")
        :format(bx, by, nameOf(owner)))
  end
  local close = W.close
  check(type(close) == "table", "the window has a close button on the title bar")
  if type(close) == "table" then
    check(close:IsMouseEnabled(), "the close button is mouse-enabled")
    local cx, cy = C.Centre(close)
    local owner = C.MouseOwnerAt(cx, cy)
    check(owner == close,
      ("a click on the close button (%.0f,%.0f) is owned by the close button: got %s")
        :format(cx, cy, nameOf(owner)))
  end
end

-- ── AC-3: EMPTY window area blocks the world ──────────────────────────────
-- The other half of the fix: the fill must take the click that used to fall
-- through to the camera. Two points in the window's border ring — inside the
-- window, outside every hosted body and chrome control.
local rw = C.Rect(win)
local emptyPoints = {
  { x = rw.left + 4, y = (rw.top + rw.bottom) / 2 },
  { x = rw.right - 4, y = (rw.top + rw.bottom) / 2 },
}
for _, p in ipairs(emptyPoints) do
  local insideWindow = C.Contains(win, p.x, p.y)
  check(insideWindow, ("the empty point (%.0f,%.0f) is inside the window"):format(p.x, p.y))
  local owner = C.MouseOwnerAt(p.x, p.y)
  local ours = type(owner) == "table" and contains(owner, win)
  check(ours,
    ("a click in EMPTY window area (%.0f,%.0f) stays in the window and does not "
      .. "reach the world: got %s; chain %s")
      :format(p.x, p.y, nameOf(owner), ancestorChain(owner)))
  print(("empty area (%.0f,%.0f) -> %s | %s")
    :format(p.x, p.y, nameOf(owner), ancestorChain(owner)))
end

-- ── TEETH: the detector can fail ──────────────────────────────────────────
-- Put a transparent, mouse-enabled DIALOG frame over the inner Log tab — the
-- exact shape of the defect this file exists for — and require the same
-- measurement to name it. Without this leg, AC-1 going green would only prove
-- that nothing was found.
do
  local cover = CreateFrame("Frame", "SpecInnerClickEater", win)
  cover:SetFrameStrata("DIALOG")
  cover:SetPoint("TOPLEFT", logTab, "TOPLEFT", 0, 0)
  cover:SetPoint("BOTTOMRIGHT", logTab, "BOTTOMRIGHT", 0, 0)
  cover:SetFrameLevel(win:GetFrameLevel() + 20)
  cover:EnableMouse(true)
  local owner = C.MouseOwnerAt(C.Centre(logTab))
  check(owner == cover,
    "the detector NAMES a mouse-enabled DIALOG cover placed over an inner tab "
      .. "(got " .. nameOf(owner) .. ")")
  check(not contains(owner, body),
    "and that cover is correctly reported as outside the body's chain")
  cover:Hide()
  local after = C.MouseOwnerAt(C.Centre(logTab))
  check(after == logTab,
    "hiding the cover hands the inner Log tab back to itself (got " .. nameOf(after) .. ")")
  cover:SetParent(nil)
end

if failed == 0 then
  print("window_inner_input_spec: ok")
else
  print(("window_inner_input_spec: %d failure(s)"):format(failed))
  os.exit(1)
end
