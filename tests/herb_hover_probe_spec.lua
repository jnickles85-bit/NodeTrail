-- t_e9eeb448 — a herb node hover must reach the herb block, and every refusal
-- must NAME the input that refused it.
--
-- The live report (client build 70888): a Hunter with Herbalism 8 and Skinning
-- 19 saw no block on any herb node. /nt ttdiag proved the profession gate was
-- answering correctly (`herbalism=yes`) and that every one of the eight ring
-- entries said the same thing:
--
--   eval #1815 src=poll kind=- cid=- name=- panel=no … — not a herb tooltip
--
-- `T:GetHoveredNodeName` answered nil, and it answered nil for FOUR different
-- reasons: no GetOwner on the tooltip object, a mouseover unit, an owner that
-- was none of {nil, UIParent, WorldFrame}, and a first line HerbData did not
-- recognise. One string for four causes is not a diagnostic: the next report of
-- this is a whole round trip.
--
-- This spec drives the hover shapes a client can present and pins both halves:
--   1. an ACCEPTED hover is a node that is not an item and not a unit — the
--      first line is a node name, no item, no unit — whatever the tooltip's
--      OWNER is, and whether or not the client exposes GetOwner at all;
--   2. a REFUSED hover still never shows the block, and its ring entry / ttdiag
--      line names the input (owner absent, owner frame, mouseover unit, the
--      first line's text or shape);
--   3. the guards that matter survive: a unit hover never produces a herb
--      block, an item tooltip (the same herb in a bag) never produces one, and
--      a character without Herbalism gets nothing.
--
-- Red on 2685138: 1 and 2 refuse every node hover (GetOwner absent, owner a
-- foreign frame), and no ring entry carries a refusal at all.
--
-- Not loaded by the addon TOC.
local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local F = dofile(root .. "/tests/support/fakeui.lua")
F.install({ width = 1920, height = 1080 })

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
SlashCmdList = {}

-- The reporting character: Herbalism in the same panel as Skinning. The specs
-- flip `herbalism` to model the "no Herbalism" character.
local herbalism = true
local skillLines = {
  { name = "Herbalism", rank = 8 },
  { name = "Skinning", rank = 19 },
}
GetNumSkillLines = function() return #skillLines end
GetSkillLineInfo = function(i)
  local row = skillLines[i]
  if not row then return nil end
  return row.name, false, true, row.rank
end

-- The hover, as the client reports it.
local mouseoverUnit = false
local mouseoverGUID = "Creature-0-1-1-1-3098-0000000001"
UnitExists = function(u) return u == "mouseover" and mouseoverUnit end
UnitGUID = function(u) return u == "mouseover" and mouseoverGUID or nil end

local pkg = {}
local function loadFile(path)
  local f = assert(loadfile(root .. "/MightiePack/Modules/NodeTrail/" .. path))
  f("MightiePack", pkg)
end

loadFile("locale/enUS.lua")
loadFile("Config.lua")
loadFile("Data/ItemNames.lua")
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

-- ── the hover shapes ──────────────────────────────────────────────────────
-- `mkTip` builds the tooltip the client would show and records the shape in the
-- same words the diagnostic uses. The defaults are the reporting client's node
-- hover: the name on line 1, no item, no unit, and the world as the owner.
local function mkTip(opts)
  opts = opts or {}
  local owner
  if opts.owner == "none" then
    owner = nil
  elseif opts.owner == nil then
    owner = WorldFrame
  else
    owner = opts.owner
  end
  local tip = F.newTooltip({
    lines = opts.lines or { "Peacebloom", "Herbalism" },
    owner = owner,
    left = 300,
    bottom = 700,
    width = 180,
    height = 60,
  })
  if opts.owner == "absent" then
    tip.GetOwner = nil -- a client whose tooltip object has no GetOwner at all
  end
  if opts.raw then
    -- The client's first line as it really arrives: a table (a colour/segment
    -- wrapper) or a secret. `SetText` would stringify it, so the field is set
    -- directly — this is the font string's own answer, not ours. GetLine is
    -- made to answer in the same shape: the fallback is only a fallback.
    _G["GameTooltipTextLeft1"].text = opts.raw
    tip.GetLine = function() return opts.raw end
  end
  -- GetItem / GetUnit: the positive way to tell a node from an item or a unit.
  if opts.item ~= "absent" then
    local item = opts.item
    tip.GetItem = function() 
      if not item then return nil, nil end
      return item.name, item.link
    end
  end
  if opts.unit ~= "absent" then
    local unit = opts.unit
    tip.GetUnit = function() return unit end
  end
  return tip
end

-- The ring keeps the last eight evaluations, so "a new entry" means a higher
-- sequence number, not a longer table.
local function lastSeq()
  local ring = T.RingEntries()
  local last = ring[#ring]
  return last and last.n or 0
end

local function evaluate(tip, source)
  local before = lastSeq()
  T:Refresh(tip, source or "poll")
  local ring = T.RingEntries()
  local entry = ring[#ring]
  check(entry and entry.n ~= before,
    "an evaluation is recorded in the ring (seq stayed at " .. tostring(before) .. ")")
  return entry or {}
end

local function lines()
  local ok, rows = pcall(P.TextLines, P)
  if ok and type(rows) == "table" then return rows end
  return {}
end

local function joined(rows)
  return table.concat(rows or {}, "\n")
end

-- ── 1. an ACCEPTED node hover: no GetOwner on this client ──────────────────
-- The shape the old predicate refused before it read a single line. A tooltip
-- that cannot answer GetOwner is UNMEASURED, not "not ours".
local e = evaluate(mkTip({ owner = "absent", item = nil, unit = nil }))
check(P:IsShown() == true, "1: a node hover on a client with no GetOwner shows the block")
check(joined(lines()):find("Peacebloom", 1, true) ~= nil,
  "1: the block carries the node's rows (got \"" .. #lines() .. "\" row(s))")
check(lines()[#lines()] and lines()[#lines()]:find("^Picks: ") ~= nil,
  "1: the block carries the account-wide picks line (got \"" .. tostring(lines()[#lines()]) .. "\")")
check(e.kind == "herb" and e.name == "Peacebloom",
  "1: the ring says kind=herb name=Peacebloom (got kind=" .. tostring(e.kind)
    .. " name=" .. tostring(e.name) .. ")")
check(e.panelShown == true, "1: the ring records that the panel is drawn")
check(e.ownerApi == "absent", "1: the ring names the owner API (got " .. tostring(e.ownerApi) .. ")")

-- ── 2. an ACCEPTED node hover: the owner is somebody else's frame ─────────
-- The owner test was a proxy for "not an item tooltip". Where the client can
-- answer GetItem/GetUnit directly, the proxy must not refuse a node.
local foreign = F.newFrame("AnotherAddonTipHost", nil, 10, 10)
e = evaluate(mkTip({ owner = foreign, item = nil, unit = nil }))
check(P:IsShown() == true, "2: a node hover owned by another addon's frame still shows the block")
check(e.kind == "herb" and e.name == "Peacebloom",
  "2: the ring still says kind=herb name=Peacebloom")
check(type(e.owner) == "string" and e.owner:find("AnotherAddonTipHost", 1, true) ~= nil,
  "2: the ring records WHICH frame owned the tooltip (got " .. tostring(e.owner) .. ")")

-- ── 3. an ACCEPTED node hover: the world, the way the old code expected it ─
-- (pinned so the fix cannot pass by breaking the shape that already worked)
e = evaluate(mkTip({ owner = WorldFrame, item = nil, unit = nil }))
check(P:IsShown() == true and e.kind == "herb", "3: the world-owned node hover still shows the block")
e = evaluate(mkTip({ owner = "none", item = nil, unit = nil }))
check(P:IsShown() == true and e.kind == "herb", "3: a nil owner still shows the block")

-- ── 4. REFUSED: the same herb in a bag is an ITEM tooltip ──────────────────
-- The false positive the owner test existed to stop. It is still stopped —
-- now by measuring the item, and the refusal says so.
e = evaluate(mkTip({
  owner = "absent",
  item = { name = "Peacebloom", link = "|cff1eff00|Hitem:2447:0:0:0|h[Peacebloom]|h|r" },
  unit = nil,
}))
check(P:IsShown() == false, "4: a bag herb (item tooltip) never shows the herb block")
check(e.kind ~= "herb" and e.name == nil, "4: no herb decision is recorded for an item tooltip")
check(e.skip == "not a herb tooltip", "4: the item tooltip is refused as not a herb tooltip")
check(type(e.refusal) == "string" and e.refusal:find("item", 1, true) ~= nil,
  "4: the refusal NAMES the item (got " .. tostring(e.refusal) .. ")")
check(type(e.item) == "string" and e.item:find("2447", 1, true) ~= nil,
  "4: the ring records the item id it measured (got " .. tostring(e.item) .. ")")

-- ── 5. REFUSED: a mouseover unit is never a node hover ────────────────────
mouseoverUnit = true
e = evaluate(mkTip({ owner = WorldFrame, item = nil, unit = nil }))
mouseoverUnit = false
check(P:IsShown() == false, "5: a unit hover never shows the herb block")
check(e.name == nil, "5: no node name is taken from a unit hover")
check(type(e.refusal) == "string" and e.refusal:find("mouseover", 1, true) ~= nil,
  "5: the refusal NAMES the mouseover unit (got " .. tostring(e.refusal) .. ")")
check(type(e.mouseover) == "string" and e.mouseover:find("^unit:Creature", 1) ~= nil,
  "5: the ring records the unit it saw (got " .. tostring(e.mouseover) .. ")")

-- ── 6. REFUSED: a unit hover whose first line happens to be a node name ───
-- The guard has to hold whatever the text says.
mouseoverUnit = true
e = evaluate(mkTip({ owner = WorldFrame, lines = { "Peacebloom" }, item = nil, unit = nil }))
mouseoverUnit = false
check(P:IsShown() == false, "6: a unit hover with a node's name on line 1 still shows no herb block")
check(e.kind ~= "herb", "6: the ring never records kind=herb for a unit hover")

-- ── 7. REFUSED: the first line is not a node name — and it is quoted back ──
e = evaluate(mkTip({ lines = { "Copper Vein", "Mining" }, item = nil, unit = nil }))
check(P:IsShown() == false, "7: a mining node shows no herb block")
check(type(e.refusal) == "string" and e.refusal:find("Copper Vein", 1, true) ~= nil,
  "7: the refusal quotes the first line (got " .. tostring(e.refusal) .. ")")
check(type(e.line1) == "string" and e.line1 == "Copper Vein",
  "7: the ring records the raw first line (got " .. tostring(e.line1) .. ")")

-- ── 8. REFUSED: the first line is a TABLE — not text, and named as such ────
-- GetLine can hand back a colour wrapper (tooltip contract rule 3). A table must
-- never be read as a node name, and the diagnostic has to say "table", not nil.
e = evaluate(mkTip({ raw = { "Peacebloom" }, item = nil, unit = nil }))
check(P:IsShown() == false, "8: a non-string first line never shows the herb block")
check(type(e.refusal) == "string" and e.refusal:find("not text", 1, true) ~= nil,
  "8: the refusal says the first line is not text (got " .. tostring(e.refusal) .. ")")
check(type(e.line1) == "string" and e.line1:find("table", 1, true) ~= nil,
  "8: the ring records the SHAPE it got, not just absence (got " .. tostring(e.line1) .. ")")

-- ── 9. REFUSED: a character with no Herbalism gets nothing ────────────────
-- The gate that was blamed for this defect still holds.
herbalism = false
skillLines = { { name = "Skinning", rank = 19 } }
e = evaluate(mkTip({ owner = "absent", item = nil, unit = nil }))
herbalism = true
skillLines = { { name = "Herbalism", rank = 8 }, { name = "Skinning", rank = 19 } }
check(P:IsShown() == false, "9: a character without Herbalism gets no herb block")
check(e.kind == "herb" and e.name == "Peacebloom",
  "9: the hover IS a node — the gate, not the probe, is what refuses it")
check(type(e.refusal) == nil or e.refusal == nil,
  "9: no probe refusal is recorded for a recognised node")
check(type(e.skip) == "string" and e.skip:find("Herbalism", 1, true) ~= nil,
  "9: the ring says the profession gate refused it (got " .. tostring(e.skip) .. ")")

-- ── 10. the ttdiag line carries the inputs ─────────────────────────────────
-- The whole point of the card: one line of output, not a round trip.
evaluate(mkTip({ owner = foreign, lines = { "Copper Vein" }, item = nil, unit = nil }))
chat = {}
local okDiag, errDiag = pcall(T.Diag, T)
check(okDiag, "10: ttdiag does not raise (" .. tostring(errDiag) .. ")")
local out = table.concat(chat, "\n")
check(out:find("ownerapi=function", 1, true) ~= nil, "10: the eval line names the owner API")
check(out:find("owner=frame:AnotherAddonTipHost", 1, true) ~= nil,
  "10: the eval line names the owning frame")
check(out:find("mouseover=none", 1, true) ~= nil, "10: the eval line names the mouseover answer")
check(out:find('line1="Copper Vein"', 1, true) ~= nil, "10: the eval line quotes the first line")
check(out:find("not a herb tooltip (herb probe:", 1, true) ~= nil,
  "10: the refusal is printed beside the decision, not instead of it")
check(out:find('not a herb tooltip (herb probe: the first line "Copper Vein" is not a node name)', 1, true) ~= nil,
  "10: that refusal names the first line as the input that refused")

-- ── 11. a tooltip object that is not a frame is recorded, not skipped ──────
-- The first refusal in the list is the object itself. It used to cost no ring
-- entry at all, so ttdiag could show an empty ring and nothing else.
GameTooltip = nil
local seqBefore = lastSeq()
T:Poll(nil)
local ring = T.RingEntries()
check((ring[#ring] and ring[#ring].n or 0) ~= seqBefore,
  "11: poll records a tooltip object it cannot read")
local last = ring[#ring]
check(last and last.source == "poll-shape", "11: the entry names the poll shape source")
check(last and type(last.refusal) == "string" and last.refusal:find("not a frame", 1, true) ~= nil,
  "11: the refusal names the tooltip object (got " .. tostring(last and last.refusal) .. ")")

-- ── 12. the beast block is untouched: a unit hover is a beast, not a herb ──
-- Kind is decided once, by the probe; the beast path still gets its chance and
-- the herb block never appears for a creature.
GameTooltip = mkTip({ owner = WorldFrame, item = nil, unit = nil })
mouseoverUnit = true
e = evaluate(mkTip({ owner = WorldFrame, lines = { "Clattering Scorpid" }, item = nil, unit = nil }))
mouseoverUnit = false
check(e.kind ~= "herb", "12: a creature hover is never recorded as a herb")
check(e.name == nil, "12: no node name is taken from a creature hover")
check(e.kind == "beast" or e.kind == nil,
  "12: the beast decision is the one recorded (got kind=" .. tostring(e.kind) .. ")")

-- ── 13. the accepted hover reads back from ttdiag as kind=herb, panel drawn ─
-- This is the line the card's acceptance names: `kind=herb name=Peacebloom`
-- with the panel drawn, on the shape the reporting client presents.
mouseoverUnit = false
evaluate(mkTip({ owner = "absent", item = nil, unit = nil }))
chat = {}
local okD2, errD2 = pcall(T.Diag, T)
check(okD2, "13: ttdiag does not raise (" .. tostring(errD2) .. ")")
local out2 = table.concat(chat, "\n")
check(out2:find("kind=herb", 1, true) ~= nil, "13: ttdiag reports kind=herb for a node hover")
check(out2:find("name=Peacebloom", 1, true) ~= nil, "13: ttdiag reports the node's name")
check(out2:find("panel=yes", 1, true) ~= nil, "13: ttdiag reports the panel drawn")
check(out2:find('line1="Peacebloom"', 1, true) ~= nil, "13: ttdiag quotes the text it matched")
check(P:IsShown() == true, "13: the panel really is on screen, not just reported")

print(("herb hover probe: %d check(s) failed"):format(failed))
os.exit(failed == 0 and 0 or 1)
