-- window_tab_clicks_spec.lua — card t_ea66cd84: the CLICK, not the callback.
--
-- The defect this spec class exists for: in the live client the four outer tab
-- labels did not respond to clicks, while every spec stayed green.
-- `window_tabs_spec` called `W.SelectTab(id)` directly and asserted host
-- visibility, so it exercised the HANDLER and never the BUTTON. A test that
-- invokes the callback is not a test of the input path.
--
-- What this file pins, and why each assertion is evidence rather than restating
-- the implementation:
--
--   1. WIRING. Each tab switches through its OWN button's `GetScript("OnClick")`.
--      Fails if a button is unwired, or if a refactor drops the script and moves
--      the switching somewhere the button cannot reach.
--   2. HIT PATH. The frame the client would hand the click to at each button's
--      centre is the button itself — measured with real anchor geometry and
--      WoW's ordering (strata, then frame level, then creation order), not by
--      asking the button whether it is clickable.
--   3. NO COVER. No mouse-enabled frame that DRAWS ABOVE a tab button may
--      overlap its rect. This is the invariant that describes "something
--      invisible eats the click". It walks the whole client, not just the
--      window's children, and it excludes only the button's own ancestors: a
--      parent cannot take a click from its child, but a later sibling at the
--      same level can.
--   4. THE CHECKER HAS TEETH. The same detector is run against a deliberately
--      installed cover frame and must name it. Without this leg, (3) going
--      green would only prove the checker found nothing — which is exactly how
--      the old harness "passed" a dead row.
--   5. AFFORDANCE (AC-N4). Each button carries a visible plate and a hover
--      state: firing its own OnEnter changes what it draws, OnLeave restores
--      it. Text-only tabs are a defect even with the click path repaired.
--
-- The harness: tests/support/wowclient.lua, extended for this card with
--   * real rect math (GetLeft/GetRight/GetTop/GetBottom from anchors),
--   * EnableMouse/IsMouseEnabled that mean something,
--   * Show/Hide that fire OnShow/OnHide only on an own-flag transition.
-- Not a screenshot: harness evidence. A live verdict is the owner's alone.

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
C.trackUIParent = true

local pkg = {}
local function loadFile(path)
  local chunk, err = loadfile(root .. "/MightiePack/" .. path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. path .. ": " .. tostring(e))
end

MightiePackDB = { modules = { NodeTrail = true, Touchstone = true }, seen = { firstRun = true }, bugCount = 0 }
NodeTrailDB = {
  schema = 2,
  herbs = {
    schema = 2, total = 0, maps = {}, mapTotals = {},
    stats = { gathers = {}, co = {}, names = {} }, hotspots = {}, folded = {},
  },
  skinning = { enabled = true, schema = 2, chars = {} },
  route = {},
}
StatForgeDB = { ui = { scale = 1 } }

loadFile("Core.lua")
loadFile("Modules.lua")
for _, f in ipairs({
  "Modules/NodeTrail/locale/enUS.lua",
  "Modules/NodeTrail/Config.lua",
  "Modules/NodeTrail/Data/ItemNames.lua",
  "Modules/NodeTrail/Data/HerbData.lua",
  "Modules/NodeTrail/Data/Recorder.lua",
  "Modules/NodeTrail/Data/Density.lua",
  "Modules/NodeTrail/Data/Recipes.lua",
  "Modules/NodeTrail/Data/Profession.lua",
  "Modules/NodeTrail/Data/SkinHints.lua",
  "Modules/NodeTrail/UI/TooltipPanel.lua",
  "Modules/NodeTrail/UI/Tooltip.lua",
  "Modules/NodeTrail/Core.lua",
}) do loadFile(f) end
loadFile("Modules/Skinning/Core.lua")
loadFile("Modules/Skinning/Record.lua")
loadFile("BugReport.lua")
loadFile("Options.lua")
loadFile("Window.lua")
loadFile("Window/Common.lua")
loadFile("Window/Herbs.lua")
loadFile("Window/Skinning.lua")

-- The Touchstone seam reroutes five public entry points on StatForge and
-- registers the tab's renderer; it needs the module's shape, not its body.
StatForge = {
  ShowMain = function() end, HideMain = function() end, ToggleMain = function() end,
  IsMainShown = function() return false end, RefreshActiveTab = function() end,
  SelectTab = function() end,
}
loadFile("Window/TouchstoneTab.lua")

local okEnable = pcall(pkg.EnableModules)
check(okEnable, "the enabled modules start (as they do at login)")

local W = pkg.Window
check(type(W) == "table", "pkg.Window exists")
local f = W.Frame()
check(type(f) == "table", "the window frame is created")
W.Open("herbs")

-- ── 1. WIRING: the click goes through the button's own script ─────────────
-- Reading the script and firing it is the closest a harness can come to the
-- client's own dispatch. `W.SelectTab(id)` is deliberately NOT called here.
for _, id in ipairs(W.TABS) do
  local btn = W.tabButtons[id]
  check(type(btn) == "table", "there is a button for the " .. id .. " tab")
  if type(btn) == "table" then
    local script = btn:GetScript("OnClick")
    check(type(script) == "function",
      "the " .. id .. " tab button has its own OnClick script (got " .. type(script) .. ")")
    if type(script) == "function" then
      local okFire, err = pcall(script, btn, "LeftButton")
      check(okFire, "firing the " .. id .. " button's OnClick does not raise: " .. tostring(err))
      check(W.Current() == id,
        "clicking the " .. id .. " button selects " .. id .. " (got " .. tostring(W.Current()) .. ")")
      local visible = {}
      for _, t in ipairs(W.TABS) do
        local host = W.hosts[t]
        if host and host:IsShown() then visible[#visible + 1] = t end
      end
      check(#visible == 1 and visible[1] == id,
        "clicking " .. id .. " shows exactly its own body (got {" .. table.concat(visible, ",") .. "})")
    end
  end
end

-- ── 2. HIT PATH: the client would hand the click to the button ────────────
-- `C.MouseOwnerAt` is the harness's `GetMouseFocus()`: the topmost VISIBLE,
-- MOUSE-ENABLED frame under the point, ordered by strata, then frame level,
-- then creation order.
for _, id in ipairs(W.TABS) do
  local btn = W.tabButtons[id]
  if type(btn) == "table" then
    local x, y = C.Centre(btn)
    local owner, chain = C.MouseChain(x, y)
    check(owner == btn,
      "the frame under the " .. id .. " button's centre is the button itself (got "
        .. tostring(owner and (owner.Name or owner.kind) or "nothing")
        .. "; chain: " .. tostring(chain) .. ")")
    check(btn:IsMouseEnabled(), "the " .. id .. " tab button is mouse-enabled")
  end
end

-- ── 3. NO COVER: nothing that draws above the row may overlap it ──────────
local function ancestors(frame)
  local out = {}
  local p = frame
  while type(p) == "table" do
    out[p] = true
    p = p:GetParent()
  end
  return out
end

--- Every mouse-enabled visible frame that draws ABOVE `control` and overlaps
--- it. Ancestors are skipped: a parent cannot steal its child's click (the
--- child is drawn and hit-tested inside it), and the window itself always
--- covers the row's rect by definition.
local function coveters(control)
  local out = {}
  local above = ancestors(control)
  for _, frame in ipairs(C.allFrames) do
    if frame ~= control and frame.mouse == true and C.Visible(frame) and not above[frame] then
      if C.DrawsAbove(frame, control) and C.Overlaps(frame, control) then
        out[#out + 1] = frame
      end
    end
  end
  return out
end

local function describe(frame)
  local r = C.Rect(frame)
  return string.format("%s/%s L%d [x %.0f..%.0f, y %.0f..%.0f]",
    tostring(frame.Name), tostring(frame.kind), frame:GetFrameLevel(),
    r.left, r.right, r.top, r.bottom)
end

for _, id in ipairs(W.TABS) do
  local btn = W.tabButtons[id]
  if type(btn) == "table" then
    local found = coveters(btn)
    check(#found == 0,
      "nothing draws over the " .. id .. " tab button and takes its clicks (found: "
        .. (found[1] and describe(found[1]) or "none") .. ")")
  end
end

-- ── 4. THE CHECKER HAS TEETH ─────────────────────────────────────────────
-- Install the exact defect the live client is suspected of — a transparent,
-- mouse-enabled frame over the row — and require the detector to name it. A
-- detector that cannot fail is not evidence; that is the whole lesson of the
-- card this file exists for.
do
  local herbs = W.tabButtons.herbs
  local cover = CreateFrame("Frame", "SpecClickEater", f)
  cover:SetPoint("TOPLEFT", herbs, "TOPLEFT", 0, 0)
  cover:SetPoint("BOTTOMRIGHT", herbs, "BOTTOMRIGHT", 0, 0)
  cover:SetFrameLevel(herbs:GetFrameLevel() + 1)
  cover:EnableMouse(true)
  local found = coveters(herbs)
  check(#found == 1 and found[1] == cover,
    "the overlap check NAMES a transparent cover frame placed over a tab button (found "
      .. tostring(#found) .. " offender(s))")
  local owner = C.MouseOwnerAt(C.Centre(herbs))
  check(owner == cover,
    "and the hit test agrees the cover would take the click (owner: "
      .. tostring(owner and (owner.Name or owner.kind) or "nothing") .. ")")
  cover:Hide()
  check(#coveters(herbs) == 0, "hiding the cover clears the finding again")
  cover:SetParent(nil)
end

-- ── 5. AFFORDANCE (AC-N4): a plate, and a hover state ─────────────────────
-- Minimal by design: the strip's real look belongs to the reshape card
-- t_2d2c37b0. What is asserted is only that the control DRAWS as a control and
-- that hovering it changes what it draws.
for _, id in ipairs(W.TABS) do
  local btn = W.tabButtons[id]
  if type(btn) == "table" then
    local plate = btn.hasBackdrop == true
      or type(btn.GetNormalTexture) == "function" and btn:GetNormalTexture() ~= nil
    check(plate, "the " .. id .. " tab button draws a plate (template or backdrop)")
    local enter, leave = btn:GetScript("OnEnter"), btn:GetScript("OnLeave")
    check(type(enter) == "function", "the " .. id .. " tab button has a hover-in state")
    check(type(leave) == "function", "the " .. id .. " tab button has a hover-out state")
    if type(enter) == "function" and type(leave) == "function" then
      pcall(leave, btn)
      local r0, g0, b0, a0 = btn:GetBackdropColor()
      pcall(enter, btn)
      local r1, g1, b1, a1 = btn:GetBackdropColor()
      check(r0 ~= r1 or g0 ~= g1 or b0 ~= b1 or a0 ~= a1,
        "hovering the " .. id .. " tab changes its plate colour")
      pcall(leave, btn)
      local r2, g2, b2, a2 = btn:GetBackdropColor()
      check(r0 == r2 and g0 == g2 and b0 == b2 and a0 == a2,
        "leaving the " .. id .. " tab restores its plate colour")
    end
  end
end

check(#C.uiParentCalls == 0,
  "the row never Show/Hide/SetPoint/SetSize UIParent (got "
    .. table.concat(C.uiParentCalls, ",") .. ")")

if failed == 0 then
  print("window_tab_clicks_spec: ok")
else
  print(("window_tab_clicks_spec: %d failure(s)"):format(failed))
  os.exit(1)
end
