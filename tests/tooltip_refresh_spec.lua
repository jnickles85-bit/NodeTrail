-- t_f4ff9ea6 — the tooltip poller drives the herb PANEL, and touches nothing
-- Blizzard owns.
--
-- The previous design hooked GameTooltip (OnShow / OnTooltipSetUnit /
-- OnTooltipSetItem / OnTooltipCleared) and appended lines to it. That is gone:
-- on this client the tooltip's backdrop is sized at show time and never follows
-- late lines, so every append-based fix was reset on the next show. The block now
-- lives in ns.TooltipPanel, and this spec pins the contract that makes it stable:
--
--   * Enable installs NO script on GameTooltip — no HookScript, no replaced
--     method, no OnUpdate clobber. The only clock is the addon's own private
--     frame, and it drives everything at ~5x/second;
--   * a hidden tooltip hides the panel and costs no evaluation;
--   * a herb shows the block; a non-herb (or a unit tooltip) hides it, and the
--     next herb comes back clean;
--   * six hovers of the same herb render the same rows every time — one frame,
--     no duplicate block, no drift;
--   * /nt ttdiag prints the panel's rect, width budget, shown state and the
--     widest of our lines, plus the refresh ring that names the source.
--
-- Not loaded by the addon TOC.
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. msg .. "\n")
  end
end

local F = dofile(root .. "/tests/support/fakeui.lua")
local SCREEN_W, SCREEN_H = F.install({ width = 1920, height = 1080 })

time = time or os.time
CopyTable = function(t)
  local c = {}
  for k, v in pairs(t) do
    c[k] = type(v) == "table" and CopyTable(v) or v
  end
  return c
end
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chat[#chat + 1] = tostring(m) end }
GetSpellInfo = function(id)
  local map = { [2366] = "Herb Gathering", [2259] = "Alchemy" }
  return map[id]
end
local mouseoverUnit = false
UnitExists = function(u) return u == "mouseover" and mouseoverUnit end
SlashCmdList = {}

-- t_d4848ce0: the block is gated on the character's profession. This spec's
-- character is an herbalist (the client's skill lines say so), which is why the
-- block shows at all; the picks wording is account-wide because the store is.
local skillLines = {
  { name = "Herbalism", rank = 300 },
  { name = "Alchemy", rank = 300 },
}
GetNumSkillLines = function() return #skillLines end
GetSkillLineInfo = function(i)
  local row = skillLines[i]
  if not row then return nil end
  return row.name, false, true, row.rank
end

local pkg = {}
local function loadFile(path)
  local f = assert(loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path))
  f("MightiePack", pkg)
end

loadFile("locale/enUS.lua")
loadFile("Config.lua")
loadFile("Data/Recorder.lua")
loadFile("Data/HerbData.lua")
loadFile("Data/Profession.lua")
loadFile("Data/Recipes.lua")
loadFile("UI/TooltipPanel.lua")
loadFile("UI/Tooltip.lua")
loadFile("Core.lua")

local ns = pkg.NodeTrail
local T = ns.Tooltip
local P = ns.TooltipPanel

NodeTrailDB = { recipes = {}, profile = {}, herbs = { schema = 1, total = 0, maps = {} } }

-- ── T1: loading creates nothing and hooks nothing ────────────────────────
check(#F.frames == 0, "T1: no frame exists at load")
check(T.poller == nil, "T1: no poll clock before Enable")

-- The tooltip the addon will be driven from, with a rect on the screen.
local function herbTooltip(name, opts)
  opts = opts or {}
  return F.newTooltip({
    lines = { name, "Herbalism" },
    owner = UIParent,
    left = opts.left or 300,
    bottom = opts.bottom or 700,
    width = 180,
    height = 60,
  })
end

local gt = herbTooltip("Peacebloom")
_G.GameTooltip = gt
local origMethods = {}
for _, name in ipairs({ "HookScript", "SetScript", "AddLine", "AddDoubleLine", "SetWidth",
  "SetHeight", "Show", "Hide", "SetOwner", "ClearLines", "Clear", "SetText" }) do
  origMethods[name] = gt[name]
end

T:Enable()
T:Enable() -- idempotent
check(#F.frames == 1, "T1: Enable created exactly one frame (the private poll clock), got " .. #F.frames)
check(T.poller ~= nil and F.frames[1] == T.poller, "T1: the created frame is the poll clock")
check(type(T.poller.scripts.OnUpdate) == "function", "T1: the poll clock drives one OnUpdate")

-- ── T2: NOTHING was hooked or replaced on GameTooltip ─────────────────────
local hookCount = 0
for name, list in pairs(gt.hooks) do
  hookCount = hookCount + #list
end
check(hookCount == 0, "T2: no script was hooked on GameTooltip (got " .. hookCount .. " hook(s))")
check(gt.scripts.OnUpdate == nil and gt.scripts.OnShow == nil,
  "T2: GameTooltip keeps its own scripts (none was clobbered)")
for name, orig in pairs(origMethods) do
  check(gt[name] == orig, "T2: GameTooltip." .. name .. " was not replaced")
end

-- ── T3: a hidden tooltip hides the panel and spends no evaluation ────────
local calls = 0
local origRefresh = T.Refresh
T.Refresh = function(self, tt, source)
  calls = calls + 1
  return origRefresh(self, tt, source)
end
local function tick(elapsed)
  T.poller.scripts.OnUpdate(T.poller, elapsed or T.POLL_INTERVAL or 0.2)
end
gt.shown = false
local ringBefore = #T.RingEntries()
tick(0.25)
check(calls == 0, "T3: a hidden tooltip costs no refresh evaluation (got " .. calls .. ")")
check(#T.RingEntries() == ringBefore, "T3: a hidden tooltip adds no ring entry")
check(P:IsShown() == false, "T3: the panel is hidden while the tooltip is hidden")

-- ── T4: a herb hover shows the block ──────────────────────────────────────
gt.shown = true
gt:SyncFirstLine()
tick(0.25)
check(calls == 1, "T4: one tick evaluated the tooltip once (got " .. calls .. ")")
check(P:IsShown() == true, "T4: the panel is shown for a herb")
local rows = P:TextLines()
check(rows[1] == "Peacebloom | 100% (base)", "T4: the block opens with the node's drop row (got \""
  .. tostring(rows[1]) .. "\")")
check(#rows >= 1 and rows[#rows]:find("^Picks: ") ~= nil,
  "T4: the picks row is the last row (got " .. #rows .. " row(s))")
check(type(P.width) == "number" and P.width + 0.01 >= (P.widest or 0),
  ("T4: panel width %s covers the widest line %s"):format(tostring(P.width), tostring(P.widest)))
local last = T.RingEntries()[#T.RingEntries()]
check(last and last.source == "poll", "T4: the ring names the source (poll)")
check(last and last.name == "Peacebloom" and last.panelShown == true,
  "T4: the ring records the node and that the panel is shown")

-- ── T5: a non-herb hides it; a unit tooltip hides it; the next herb is clean
gt.lines = { "Copper Vein", "Mining" }
gt:SyncFirstLine()
tick(0.25)
check(P:IsShown() == false, "T5: a non-herb node hides the panel")
local nonHerb = T.RingEntries()[#T.RingEntries()]
check(nonHerb and nonHerb.skip == "not a herb tooltip", "T5: the non-herb decision is recorded")
mouseoverUnit = true
gt.lines = { "Peacebloom", "Herbalism" }
gt:SyncFirstLine()
tick(0.25)
check(P:IsShown() == false, "T5: a UNIT tooltip hides the panel (mouseover unit)")
mouseoverUnit = false
gt.lines = { "Peacebloom", "Herbalism" }
gt:SyncFirstLine()
tick(0.25)
check(P:IsShown() == true, "T5: the next real herb hover brings the panel back")

-- ── T6: SIX hovers of the same herb — one frame, one block ────────────────
local frameBefore = P.frame
local firstRows = P:TextLines()
for i = 1, 6 do
  gt.shown = false
  tick(0.25) -- leave the node
  gt.shown = true
  gt:SyncFirstLine()
  tick(0.25) -- hover it again
  local r = P:TextLines()
  local same = #r == #firstRows
  if same then
    for k = 1, #r do
      if r[k] ~= firstRows[k] then same = false end
    end
  end
  check(same, ("T6: hover %d renders the same rows (no duplicate, no drift)"):format(i))
  check(P.width >= (P.widest or 0) - 0.01,
    ("T6: hover %d width %.1f >= widest %.1f"):format(i, P.width, P.widest or 0))
end
check(P.frame == frameBefore, "T6: six hovers reused the one panel frame")
check(#P.frame.textures == 5, "T6: six hovers did not multiply the panel's textures")
check(#firstRows >= 2, "T6: the block has more than one row (got " .. #firstRows .. ")")

-- ── T7: the clock is throttled to ~5 evaluations a second ────────────────
calls = 0
for _ = 1, 4 do
  tick(0.1)
end
check(calls == 2, "T7: 0.4s of ticks evaluates twice, not four times (got " .. calls .. ")")

-- ── T8: the tooltip going away hides the panel, with no evaluation ───────
gt.shown = false
local hidesBefore = T._hiddenHides or 0
calls = 0
tick(0.25)
check(P:IsShown() == false, "T8: the panel hides when the tooltip goes away")
check(calls == 0, "T8: hiding the panel costs no evaluation (got " .. calls .. ")")
check((T._hiddenHides or 0) == hidesBefore + 1, "T8: the hide is counted for the diag")

-- ── T9: /nt ttdiag prints the panel's numbers ─────────────────────────────
gt.shown = true
gt:SyncFirstLine()
tick(0.25)
chat = {}
local okDiag, errDiag = pcall(T.Diag, T)
local out = table.concat(chat, "\n")
check(okDiag, "T9: ttdiag does not raise (" .. tostring(errDiag) .. ")")
check(out:find("panel: SHOWN", 1, true) ~= nil, "T9: ttdiag prints that the panel is shown")
check(out:find("panel: width budget=", 1, true) ~= nil, "T9: ttdiag prints the width budget")
check(out:find("widest of our lines=", 1, true) ~= nil, "T9: ttdiag prints the widest of our lines")
check(out:find("rect L=", 1, true) ~= nil, "T9: ttdiag prints the panel's rect")
check(out:find("covers its widest line=yes", 1, true) ~= nil,
  "T9: ttdiag asserts the panel covers its widest line (got:\n" .. out .. ")")
check(out:find("src=poll", 1, true) ~= nil, "T9: ttdiag prints the refresh ring with its source")
gt.shown = false
tick(0.25)
chat = {}
pcall(T.Diag, T)
out = table.concat(chat, "\n")
check(out:find("panel: hidden", 1, true) ~= nil, "T9: ttdiag says the panel is hidden once it is")
check(out:find("tooltip hidden;", 1, true) ~= nil, "T9: ttdiag still reports the tooltip itself")

-- ── T10: a whole hover cycle writes NOTHING into the tooltip ────────────
local guardSource = herbTooltip("Briarthorn")
local guard, writes = F.readOnly(guardSource, "GameTooltip")
local okPoll, errPoll = pcall(T.Poll, T, guard)
check(okPoll, "T10: Poll against a write-hostile tooltip does not raise (" .. tostring(errPoll) .. ")")
check(#writes == 0, "T10: zero writes to the tooltip (got " .. #writes .. ": "
  .. table.concat(writes, ", ") .. ")")
check(P:IsShown() == true, "T10: the panel still shows the block")

-- ── T11: nothing errored ─────────────────────────────────────────────────
check(T._error == nil, "T11: ns.Tooltip recorded no error (" .. tostring(T._error) .. ")")
check(P._error == nil, "T11: the panel recorded no error (" .. tostring(P._error) .. ")")

if failed > 0 then
  io.stderr:write(failed .. " tooltip-refresh check(s) failed\n")
  os.exit(1)
end
print(("tooltip_refresh_spec: ok (panel %.0fx%.0f, widest %.1f, %d row(s))"):format(
  P.width, P.height, P.widest or 0, #P:TextLines()))
