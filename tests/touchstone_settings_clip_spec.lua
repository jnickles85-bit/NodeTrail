-- touchstone_settings_clip_spec.lua — the Settings tab's tail stays inside the
-- panel (owner retest of 5e10486, 2026-11-22, window scale 1.00: "Settings page
-- has words off of the panel again").
--
-- THE DEFECT. The flow (card t_4e5ad8a4) put the Settings stack on a scrolled
-- `content` frame under a clipping `viewport`, and moved every block onto
-- `content` -- except the About block, which stayed parented to `host`.
-- relayout() still anchored it under the role row, so it scrolled, but a region
-- is clipped only by a clipping ANCESTOR, and `host` is the viewport's parent.
-- At the top of the scroll the About paragraph, the Commands line and the Tip
-- line therefore drew below the panel's bottom edge. (Card t_4ddeae90 had fixed
-- the same symptom on the old fixed stack; the flow undid that anchor.)
--
-- WHAT THIS FILE PINS, on the live hosted path (W.Open("touchstone"), the
-- Settings sub-tab, the shipped window size at scale 1.00):
--   P1  the premise: the stack is taller than the body, so something MUST be
--       clipped or scrolled -- otherwise every check below is vacuous;
--   P2  the Settings host sits inside the pack window (its bottom is the visible
--       content area's bottom);
--   R   EVERY drawn region under the Settings host either has its bottom at or
--       above the visible area's bottom, or sits inside a scroll child: below a
--       clipping ancestor whose own bottom is inside the area. Asserted per
--       region, at the top of the scroll AND at the end of it;
--   A1  the About block, by name, is under the clipping viewport;
--   A2  its Commands and Tip lines (the owner's two lost lines) are either inside
--       the area or clipped -- measured line by line from the block's rect;
--   A3  scrolled to the end, the Tip line is ABOVE the area's bottom (the clip
--       did not just hide it for good).

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
for line in tocText:gmatch("[^\r\n]+") do
  local t = line:gsub("^%s+", ""):gsub("%s+$", "")
  if t ~= "" and not t:match("^##") then loadFile(t) end
end
local okEnable, errEnable = pcall(pkg.EnableModules)
check(okEnable, "the enabled modules start (as they do at login): " .. tostring(errEnable))

local W = pkg.Window
local SF = rawget(_G, "StatForge")
check(type(W) == "table" and type(SF) == "table", "the window and the vendored body exist")
if not (type(W) == "table" and type(SF) == "table") then
  io.stderr:write(failed .. " check(s) failed\n")
  os.exit(1)
end

W.Open("touchstone")
SF.SelectTab("options")
local L = type(SF.OptionsTabLayout) == "function" and SF.OptionsTabLayout() or nil
check(type(L) == "table" and type(L.host) == "table", "the Settings tab rendered in the window")
if type(L) ~= "table" or type(L.host) ~= "table" then
  io.stderr:write(failed .. " check(s) failed\n")
  os.exit(1)
end

local EPS = 0.05
local host, viewport = L.host, L.viewport
local win = W.Frame()
check(math.abs(C.Scale(host) - 1) < 1e-6, "precondition: window scale 1.00")

-- The visible content area: the Settings host, cut to the pack window.
local hr, wr = C.Rect(host), C.Rect(win)
local area = {
  left = math.max(hr.left, wr.left), right = math.min(hr.right, wr.right),
  top = math.min(hr.top, wr.top), bottom = math.max(hr.bottom, wr.bottom),
}

-- P1, P2
check((L.scrollMax or 0) > 0, "P1 the stack is taller than the body (overflow "
  .. format("%.1f", L.scrollMax or 0) .. "), so its tail must be clipped")
check(hr.bottom >= wr.bottom - EPS and hr.top <= wr.top + EPS,
  "P2 the Settings host sits inside the pack window")

local function label(f)
  if type(f.GetText) == "function" then
    local t = f:GetText()
    if type(t) == "string" and t ~= "" then
      t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n.*", "")
      return '"' .. t:sub(1, 40) .. '"'
    end
  end
  return tostring(f.Name or ("<" .. tostring(f.kind) .. ">"))
end

-- The nearest clipping ancestor of f strictly below `host` (or nil).
local function clipperOf(f)
  local p = f:GetParent()
  while type(p) == "table" and p ~= host do
    if type(p.GetClipsChildren) == "function" and p:GetClipsChildren() then return p end
    p = p:GetParent()
  end
  return nil
end

local function isUnder(f, anc)
  local p = f:GetParent()
  while type(p) == "table" do
    if p == anc then return true end
    p = p:GetParent()
  end
  return false
end

-- Each region once, however many paths reach it.
local function walk(rootFrame, out, seen)
  seen = seen or {}
  for _, kid in ipairs(rootFrame:GetChildren()) do
    if not seen[kid] then
      seen[kid] = true
      out[#out + 1] = kid
      walk(kid, out, seen)
    end
  end
  return out
end

-- R — every drawn region is inside the area or inside a scroll child.
local function auditRegions(when)
  local n = 0
  for _, f in ipairs(walk(host, {})) do
    if C.Drawn(f) then
      n = n + 1
      local r = C.Rect(f)
      if r.bottom < area.bottom - EPS then
        local clip = clipperOf(f)
        local ok = false
        if clip then
          local cr = C.Rect(clip)
          ok = cr.bottom >= area.bottom - EPS
        end
        check(ok, ("R [%s] %s ends %.1f below the panel's bottom and is in no scroll child")
          :format(when, label(f), area.bottom - r.bottom))
      end
    end
  end
  check(n >= 20, "R [" .. when .. "] premise: the audit saw the tab's regions (" .. n .. ")")
end

auditRegions("top of scroll")

-- A1/A2 — the About block and its two last lines, by name.
local about = host.about
check(type(about) == "table", "A1 the About block exists")
if type(about) == "table" then
  check(type(viewport) == "table" and isUnder(about, viewport),
    "A1 the About block is under the clipping viewport (a scroll child)")
  local text = about:GetText() or ""
  check(text:find("Commands:", 1, true) and text:find("Tip: run", 1, true),
    "A2 premise: the block carries the Commands and Tip lines")
  local lineH = C.defaultFontSize * C.lineHeight
  local ar = C.Rect(about)
  local lines = math.floor((ar.height + 0.01) / lineH)
  -- The Tip line is the last line, Commands two above it (a blank line between).
  local tipBottom = ar.top - lines * lineH
  local cmdBottom = tipBottom + 2 * lineH
  local clipped = clipperOf(about) ~= nil
  check(cmdBottom >= area.bottom - EPS or clipped,
    "A2 the Commands line is inside the panel or clipped to it")
  check(tipBottom >= area.bottom - EPS or clipped,
    "A2 the Tip line is inside the panel or clipped to it")
end

-- A3 — scroll to the end: everything still obeys R, and the Tip line is on screen.
if type(viewport) == "table" then
  for _ = 1, 80 do C.FireScript(viewport, "OnMouseWheel", -1) end
  auditRegions("end of scroll")
  if type(about) == "table" then
    check(C.Rect(about).bottom >= area.bottom - EPS,
      "A3 scrolled to the end, the Tip line is above the panel's bottom")
  end
end

if failed > 0 then
  io.stderr:write(tostring(failed) .. " check(s) failed\n")
  os.exit(1)
end
print("touchstone_settings_clip_spec: ok")
