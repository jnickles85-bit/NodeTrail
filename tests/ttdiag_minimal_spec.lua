-- t_c0a68ed2 — /nt ttdiag on a client that is missing most of the tooltip API.
-- The command is the ONLY evidence channel for the minimap tooltip flash, and
-- it has to survive a client where the tooltip object exposes almost nothing
-- (no NumLines, no IsShown, no GetPoint, no edge getters, no UIParent). Every
-- read must answer "absent" instead of raising, and the refresh-decision ring
-- must still print — that ring is what makes the flash diagnosable after the
-- fact.
--
-- Not loaded by the addon TOC.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. (msg or "check") .. "\n")
  end
end

local chat = {}
local added = 0
DEFAULT_CHAT_FRAME = {
  AddMessage = function(_, m)
    added = added + 1
    chat[#chat + 1] = m
  end,
}
SlashCmdList = {}

function CopyTable(t)
  local out = {}
  for k, v in pairs(t) do
    out[k] = type(v) == "table" and CopyTable(v) or v
  end
  return out
end

-- No CreateFrame, no C_Timer, no UIParent, no GetCVar, no GetTime, no
-- UnitExists, no font strings. The tooltip is a bare table.
function CreateFrame()
  error("CreateFrame is not available on this client")
end

local pkg = {}
local function loadAddon(path)
  local chunk, err = loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path)
  assert(chunk, err)
  chunk("MightiePack", pkg)
end
loadAddon("locale/enUS.lua")
loadAddon("Config.lua")
loadAddon("Data/Recorder.lua")
loadAddon("Data/HerbData.lua")
loadAddon("Data/Recipes.lua")
loadAddon("UI/Tooltip.lua")

local ns = pkg.NodeTrail
local T = ns.Tooltip

local function diag()
  chat = {}
  local ok, err = pcall(T.Diag, T)
  return ok, err, table.concat(chat, "\n")
end

-- ── 1. no GameTooltip at all ───────────────────────────────────────────────
GameTooltip = nil
local ok, err, out = diag()
check(ok, "1: ttdiag does not raise with no GameTooltip (" .. tostring(err) .. ")")
check(out:find("refresh ring:", 1, true) ~= nil, "1: the ring is printed even with no tooltip")
check(out:find("empty", 1, true) ~= nil, "1: the empty ring says so")
check(out:find("GameTooltip unavailable", 1, true) ~= nil, "1: the missing tooltip is named")

-- ── 2. a tooltip table with no methods at all ─────────────────────────────
GameTooltip = {}
ok, err, out = diag()
check(ok, "2: ttdiag does not raise on a bare tooltip table (" .. tostring(err) .. ")")
check(out:find("tooltip hidden;", 1, true) ~= nil, "2: an unknowable visibility reads as hidden")
check(out:find("block: none", 1, true) ~= nil, "2: block state is reported")
check(out:find("error:", 1, true) == nil, "2: no error line is fabricated")

-- ── 3. a tooltip that claims to be shown but has no readers ───────────────
GameTooltip = {
  IsShown = function() return true end,
}
ok, err, out = diag()
check(ok, "3: ttdiag does not raise when the tooltip is shown but unreadable (" .. tostring(err) .. ")")
check(out:find("NumLines=? W=? H=?", 1, true) ~= nil, "3: every unreadable fact prints ? not an error")
check(out:find("points: none (frame unanchored)", 1, true) ~= nil, "3: anchors report absent")
check(out:find("screen: UIParent absent", 1, true) ~= nil, "3: a client with no UIParent says so")
check(out:find("error:", 1, true) == nil, "3: no error line is fabricated")

-- ── 4. readers that RAISE must not abort the block ────────────────────────
GameTooltip = {
  IsShown = function() return true end,
  NumLines = function() error("boom: NumLines") end,
  GetWidth = function() error("boom: GetWidth") end,
  GetHeight = function() return 12 end,
  GetNumPoints = function() return 2 end,
  GetPoint = function() error("boom: GetPoint") end,
  GetLeft = function() error("boom: GetLeft") end,
  GetRight = function() return 10 end,
  GetTop = function() return 10 end,
  GetBottom = function() return 0 end,
}
ok, err, out = diag()
check(ok, "4: a raising reader does not abort ttdiag (" .. tostring(err) .. ")")
check(out:find("point 1: GetPoint error", 1, true) ~= nil, "4: a raising GetPoint is reported per point")
check(out:find("NumLines=? W=? H=12", 1, true) ~= nil, "4: raising readers print ? while the others still read")
check(out:find("measured: edge getters present but returned non-numbers", 1, true) ~= nil,
  "4: a half-readable edge set is called out")

-- ── 5. the ring records and prints a real evaluation ──────────────────────
-- Refresh itself must survive a tooltip with nothing on it, and the decision
-- must land in the ring that ttdiag prints.
local okR, errR = pcall(T.Refresh, T, {}, "poll")
check(okR, "5: Refresh does not raise on an empty tooltip (" .. tostring(errR) .. ")")
local ring = T.RingEntries()
check(#ring >= 1, "5: the evaluation is in the ring")
local e = ring[#ring]
check(e and e.source == "poll", "5: the ring names the source")
check(e and e.skip == "not a herb tooltip", "5: the ring names the decision")
GameTooltip = { IsShown = function() return false end }
ok, err, out = diag()
check(ok, "5: ttdiag does not raise (" .. tostring(err) .. ")")
check(out:find("eval #", 1, true) ~= nil, "5: ttdiag prints the evaluation line")
check(out:find("src=poll", 1, true) ~= nil, "5: ttdiag prints the source")
check(out:find("not a herb tooltip", 1, true) ~= nil, "5: ttdiag prints the decision")

-- ── 6. a chat frame that raises falls back to print, not to an error ──────
local goodChat = DEFAULT_CHAT_FRAME
DEFAULT_CHAT_FRAME = { AddMessage = function() error("chat frame is gone") end }
local printed = {}
local origPrint = print
print = function(msg) printed[#printed + 1] = tostring(msg) end
ok, err = pcall(T.Diag, T)
print = origPrint
check(ok, "6: ttdiag does not raise when the chat frame raises (" .. tostring(err) .. ")")
check(#printed > 0, "6: the lines fall back to print")
check(table.concat(printed, "\n"):find("NodeTrail ttdiag:", 1, true) ~= nil,
  "6: the fallback keeps the diag prefix")
DEFAULT_CHAT_FRAME = goodChat

-- ── 7. the block was never fabricated by any of the above ────────────────
check(T._error == nil, "7: no module error was recorded (" .. tostring(T._error) .. ")")

-- ── 8. a readable tooltip: the real 5-tuple GetPoint order ───────────────
-- (point, relativeTo, relativePoint, offsetX, offsetY) — a diag that prints
-- these in another order wastes the smoke test.
local relTo = { GetName = function() return "UIParent" end }
GameTooltip = {
  IsShown = function() return true end,
  NumLines = function() return 7 end,
  GetNumPoints = function() return 1 end,
  GetPoint = function(_, i)
    if i == 1 then
      return "BOTTOMLEFT", relTo, "BOTTOMLEFT", 14, 22
    end
    return nil
  end,
}
ok, err, out = diag()
check(ok, "8: ttdiag does not raise on a readable tooltip (" .. tostring(err) .. ")")
check(out:find("NumLines=7", 1, true) ~= nil, "8: NumLines is read")
check(out:find("point 1: BOTTOMLEFT of UIParent BOTTOMLEFT xOfs=14 yOfs=22", 1, true) ~= nil,
  "8: the anchor is printed in the real 5-tuple order (got block: " .. out .. ")")

if failed > 0 then
  io.stderr:write(failed .. " ttdiag minimal-client check(s) failed\n")
  os.exit(1)
end
print("ttdiag_minimal_spec: ok")
