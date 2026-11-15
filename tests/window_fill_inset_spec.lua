-- window_fill_inset_spec.lua — card t_07f778ca, PART A.
--
-- THE DEFECT (owner, in game, 2026-11-14): "a transparent box outline surrounds
-- the window, larger than the window on every side, most visible above the title
-- bar."
--
-- The cause is a BACKDROP CLASS error, not a layout slip. A WoW backdrop's
-- `insets` say how far the background is painted INSIDE the frame, and they
-- exist for one purpose: to leave room for border art, which is drawn in that
-- band. A flat colour (`bgFile = WHITE8X8`) with `insets = 8` therefore paints
-- its fill 8px inside its own frame — while the frame's 1px hairline is drawn at
-- the TRUE edge. The 8px between them is transparent: a box outline around the
-- window, widest where a fill (the title band) is inset from the top edge.
--
-- So the rule this spec pins is a rule about frames, not about one frame:
--
--   * a backdrop with a bgFile and NO edgeFile is a FLAT FILL. Nothing is drawn
--     in the inset band, so its insets must be zero on all four sides;
--   * a backdrop with BOTH is a fill inside border art. The fill must reach at
--     least to the inner edge of that art — `insets` no larger than `edgeSize`
--     — or a transparent ring is left between the fill and the border. (The
--     card words this as "bg and edge insets must be the same value so fill and
--     border coincide"; that is exactly true for our own 1px hairline, and it is
--     the case the chrome frames are pinned to below. A Blizzard 32px dialog
--     frame legitimately sets insets 8 inside 32px of art — the art covers the
--     band, so there is no ring — and the geometry, not the wording, is what
--     makes a gap.)
--
-- An edgeFile with no bgFile is a bare border: there is nothing to coincide, and
-- the window frame itself is exactly that, so it is not an offender.
--
-- Legs:
--   1. THE PASS LEG, over the whole tree the pack creates: no offenders.
--   2. NEGATIVE LEG (flat fill): install a frame the old way — WHITE8X8 fill,
--      insets = 8, no edgeFile — and require the checker to NAME it. Without
--      this leg, leg 1 going green would only prove the checker looks at
--      nothing.
--   3. NEGATIVE LEG (fill inside border art): a bgFile+edgeFile frame whose
--      insets (8) disagree with its edgeSize (1) — the fill floats inside its
--      own border — must also be named.
--   4. THE HOSTED BODY (PART A2). One window, one frame: while Touchstone is
--      hosted, its body draws no border of its own and its fill is transparent,
--      so the window is the only chrome.
--
-- Harness: tests/support/wowclient.lua. Not a screenshot: this is a tree
-- inspection of what the pack actually asked the client to draw.

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
tinsert, tremove, tsort = table.insert, table.remove, table.sort
format = string.format
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

-- ── The checker ────────────────────────────────────────────────────────────
-- One function, used by the pass leg AND by the negative legs. The value of a
-- negative leg is that the same code that is silent on the real tree names the
-- defect the moment it is installed.
local SIDES = { "left", "right", "top", "bottom" }

local function hasFile(v)
  return type(v) == "string" and v ~= ""
end

local function insetOf(bd, side)
  local ins = type(bd.insets) == "table" and bd.insets or nil
  if type(ins) ~= "table" then return 0 end
  return tonumber(ins[side]) or 0
end

local function label(f)
  return tostring(f.Name or "?") .. "/" .. tostring(f.kind or "frame")
end

--- Every backdrop that paints a fill in the wrong place. Returns a list of
--- sentences, empty when the tree is clean.
local function auditBackdrops(frames)
  local out = {}
  for _, f in ipairs(frames) do
    local bd = (type(f) == "table") and f.backdrop or nil
    if type(bd) == "table" then
      local bg, edge = hasFile(bd.bgFile), hasFile(bd.edgeFile)
      if bg and not edge then
        -- A flat fill. Its inset band is empty: any inset is a transparent ring.
        for _, side in ipairs(SIDES) do
          local v = insetOf(bd, side)
          if v ~= 0 then
            out[#out + 1] = label(f) .. ": flat fill (no edgeFile) inset " .. tostring(v)
              .. "px on the " .. side .. " — the fill stops short of its own frame"
          end
        end
      elseif bg and edge then
        -- A fill inside border art: the fill must reach the art's inner edge.
        local size = tonumber(bd.edgeSize) or 0
        for _, side in ipairs(SIDES) do
          local v = insetOf(bd, side)
          if v > size then
            out[#out + 1] = label(f) .. ": a transparent ring between fill and border — "
              .. side .. " inset " .. tostring(v) .. " under " .. tostring(size) .. "px of art"
          end
        end
      end
    end
  end
  return out
end

-- ── What the pass leg walks ────────────────────────────────────────────────
-- "For every frame the pack creates" — which is every frame in the tree EXCEPT
--   * the harness's own screen frames (created before the pack loaded), and
--   * the vendored Touchstone body and everything under it: that module is not
--     ours (hard rule 3), it arrives already drawn, and leg 4 pins the one thing
--     the pack must do to it when hosting it.
local HARNESS = { UIParent = true, WorldFrame = true, GameTooltip = true }

local function vendoredBodyTree()
  local skip = {}
  local body = rawget(_G, "StatForgeMainFrame")
  if type(body) ~= "table" then return skip end
  local function walk(f)
    if type(f) ~= "table" or skip[f] then return end
    skip[f] = true
    local ok, kids = pcall(f.GetChildren, f)
    if ok and type(kids) == "table" then
      for _, k in ipairs(kids) do walk(k) end
    end
  end
  walk(body)
  return skip
end

local function packTree()
  local skip = vendoredBodyTree()
  local out = {}
  for _, f in ipairs(C.allFrames) do
    if not skip[f] and not HARNESS[tostring(f.Name)] then out[#out + 1] = f end
  end
  return out
end
local pkg = {}
local function loadFile(path)
  local chunk, err = loadfile(root .. "/MightiePack/" .. path)
  check(chunk ~= nil, "loadfile " .. path .. ": " .. tostring(err))
  if not chunk then return end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. path .. ": " .. tostring(e))
end

MightiePackDB = { modules = { Touchstone = true }, seen = { firstRun = true }, bugCount = 0 }
StatForgeDB = { ui = { scale = 1 }, firstUse = false }

local toc = assert(io.open(root .. "/MightiePack/MightiePack.toc", "r"))
local tocText = toc:read("*a")
toc:close()
local files = {}
for line in tocText:gmatch("[^\r\n]+") do
  local t = line:gsub("^%s+", ""):gsub("%s+$", "")
  if t ~= "" and not t:match("^##") then files[#files + 1] = t end
end
check(#files > 0, "the TOC lists files")
for _, path in ipairs(files) do loadFile(path) end

local okEnable, errEnable = pcall(pkg.EnableModules)
check(okEnable, "the enabled modules start (as they do at login): " .. tostring(errEnable))

local W = pkg.Window
local T = pkg.Theme
check(type(W) == "table" and type(T) == "table", "the window and the theme exist")

-- Building the window (and the tab trees) creates the frames under test.
local win = W.Frame()
check(type(win) == "table", "the window frame is created")
W.Open("touchstone")
W.Open("settings")
W.Open("touchstone")

-- ── 1. THE PASS LEG ────────────────────────────────────────────────────────
-- The tree must contain real flat fills, or this leg would pass on nothing.
local packFrames = packTree()
local filled, edged = 0, 0
for _, f in ipairs(packFrames) do
  local bd = f.backdrop
  if type(bd) == "table" then
    if hasFile(bd.bgFile) and not hasFile(bd.edgeFile) then filled = filled + 1 end
    if hasFile(bd.bgFile) and hasFile(bd.edgeFile) then edged = edged + 1 end
  end
end
check(filled > 0, "the pack creates flat fills (found " .. tostring(filled) .. ")")
check(edged >= 0, "the pack's bordered backdrops are counted")

local offenders = auditBackdrops(packFrames)
check(#offenders == 0,
  "no fill is painted inside its own frame (" .. tostring(#offenders) .. " offender(s)):\n    "
    .. table.concat(offenders, "\n    "))

-- The surfaces the owner named, checked by identity where the window publishes
-- them — a tree-wide pass is only as good as the tree it walked.
local function backdropOf(f) return (type(f) == "table") and f.backdrop or nil end
local bgBd = backdropOf(W.bg)
check(type(bgBd) == "table" and hasFile(bgBd.bgFile),
  "the window fill is a flat fill (W.bg has a bgFile)")
if type(bgBd) == "table" then
  for _, side in ipairs(SIDES) do
    check(insetOf(bgBd, side) == 0,
      "the window fill reaches the frame edge (" .. side .. " inset is 0)")
  end
end
local bandBd = backdropOf(W.titleBar)
check(type(bandBd) == "table" and hasFile(bandBd.bgFile),
  "the title band is a flat fill (W.titleBar has a bgFile)")
if type(bandBd) == "table" then
  for _, side in ipairs(SIDES) do
    check(insetOf(bandBd, side) == 0,
      "the title band reaches the window's top edge (" .. side .. " inset is 0)")
  end
end

-- ── 2. NEGATIVE LEG: a flat fill with 8px insets is named ──────────────────
local bad = CreateFrame("Frame", "FillInsetSpecBadFlat", UIParent, "BackdropTemplate")
bad:SetSize(100, 40)
bad:SetBackdrop({
  bgFile = T.tex.solid, tile = false,
  insets = { left = 8, right = 8, top = 8, bottom = 8 },
})
local badHits = auditBackdrops({ bad })
check(#badHits > 0, "the checker names a flat fill inset by 8px")
check(#badHits == 4, "it names all four sides of the flat fill (got " .. tostring(#badHits) .. ")")
local named = false
for _, hit in ipairs(badHits) do
  if hit:find("FillInsetSpecBadFlat", 1, true) then named = true end
end
check(named, "the offender is NAMED, not just counted: " .. table.concat(badHits, "; "))

-- ── 3. NEGATIVE LEG: a fill that floats inside its own border is named ─────
local bad2 = CreateFrame("Frame", "FillInsetSpecBadEdge", UIParent, "BackdropTemplate")
bad2:SetSize(100, 40)
bad2:SetBackdrop({
  bgFile = T.tex.solid, edgeFile = T.tex.edge, tile = false, edgeSize = 1,
  insets = { left = 8, right = 8, top = 8, bottom = 8 },
})
local bad2Hits = auditBackdrops({ bad2 })
check(#bad2Hits > 0, "the checker names a fill whose insets disagree with its edgeSize")
local named2 = false
for _, hit in ipairs(bad2Hits) do
  if hit:find("FillInsetSpecBadEdge", 1, true) then named2 = true end
end
check(named2, "that offender is named too: " .. table.concat(bad2Hits, "; "))

-- The checker must stay silent on the one shape that is correct with insets:
-- border art whose fill starts exactly where the border ends.
local good = CreateFrame("Frame", "FillInsetSpecGoodEdge", UIParent, "BackdropTemplate")
good:SetSize(100, 40)
good:SetBackdrop({
  bgFile = T.tex.solid, edgeFile = T.tex.edge, tile = false, edgeSize = 1,
  insets = { left = 1, right = 1, top = 1, bottom = 1 },
})
check(#auditBackdrops({ good }) == 0,
  "a 1px border with a 1px fill inset is not an offender")

-- The chrome's own case, asserted where it matters: every 1px hairline the pack
-- draws has its fill start exactly at that 1px, so fill and border coincide and
-- no ring can appear at the window's edge.
local hairlineCount = 0
for _, f in ipairs(packFrames) do
  local bd = f.backdrop
  if type(bd) == "table" and hasFile(bd.bgFile) and hasFile(bd.edgeFile)
    and tonumber(bd.edgeSize) == T.size.windowEdge then
    hairlineCount = hairlineCount + 1
    for _, side in ipairs(SIDES) do
      check(insetOf(bd, side) == T.size.windowEdge,
        label(f) .. ": the hairline's fill starts at the border's inner edge (" .. side .. ")")
    end
  end
end
check(hairlineCount > 0, "the pack draws at least one hairline'd surface (found " .. hairlineCount .. ")")

-- ── 4. THE HOSTED BODY DRAWS NO FRAME OF ITS OWN (PART A2) ────────────────
-- The Settings screenshot showed the Touchstone body drawing its own bordered
-- box inside the window: a second, nested frame. One window, one frame.
local body = rawget(_G, "StatForgeMainFrame")
check(type(body) == "table", "StatForgeMainFrame exists after the tab opened")
if type(body) == "table" then
  local host = W.hosts and W.hosts.touchstone
  check(type(host) == "table" and body:GetParent() == host,
    "the Touchstone body is parented into the window's touchstone host")
  local bd = backdropOf(body)
  check(type(bd) == "table", "the hosted body still has a backdrop table (it is claimed, not left alone)")
  if type(bd) == "table" then
    check(not hasFile(bd.edgeFile),
      "the hosted body draws NO border of its own (edgeFile is " .. tostring(bd.edgeFile) .. ")")
    local okC, r, g, b, a = pcall(body.GetBackdropColor, body)
    check(okC and type(a) == "number" and a == 0,
      "the hosted body's fill is transparent (alpha " .. tostring(a) .. ")")
  end
end

-- ── 5. THE OPTIONS PANEL IS SHOWN ONLY ON ITS OWN TAB (PART A3) ───────────
-- The panel used to be shown for the whole session. Inside the window that means
-- a DIALOG frame above whatever tab is active — painting nothing today, which is
-- exactly why it survived, and exactly how the strata and input defects started.
local panel = pkg.optionsPanel
check(type(panel) == "table", "the options panel exists")
W.Open("touchstone")
check(panel:IsShown() == false,
  "the options panel is NOT shown while Touchstone is the active tab")
check(type(body) == "table" and C.Visible(body) == true,
  "while Touchstone is active the body IS visible")
W.Open("settings")
check(panel:IsShown() == true, "the options panel IS shown on its own tab")
check(type(body) == "table" and C.Visible(body) == false,
  "while Pack Settings is active the hosted body is not visible")
W.Open("touchstone")
check(panel:IsShown() == false and C.Visible(body) == true,
  "coming back to Touchstone hides the panel and shows the body")

if failed == 0 then
  print("window_fill_inset_spec: ok")
else
  print(("window_fill_inset_spec: %d failure(s)"):format(failed))
  os.exit(1)
end
