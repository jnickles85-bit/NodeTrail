-- touchstone_window_row_word_spec.lua — card t_c8970547.
--
-- THE DEFECT (owner retest of aa82f70, first Sidegrade sighted in the client):
--   "The window files the pair as trade-off while the tooltip headlines
--    Sidegrade — by design, or should the window carry the arbitrated state too?"
--
-- It is not by design, and the code says so. ChestAdvisor.lua publishes ONE
-- arbitration-aware row word — TOOLTIP_UI.wordFor(row), which reads
-- row.arbitration.state — and the item tooltip and both mark hovers read it.
-- The unified window's ledger row (Modules/Touchstone/UpgradesTab.lua) read
-- TOOLTIP_UI.word(row.verdict) instead: the pre-arbitration TOKEN map. So for
-- one pair the player got two words, and the window's was the wrong one.
--
-- WHAT THIS SPEC PINS. The real engine, the real word map and the real renderer,
-- no fixture of the vocabulary:
--
--   1. SIDEGRADE (the parity spec's case 3: TRADE_C vs TRADE_E, totals = MID):
--      the window row word and the tooltip headline are the SAME string, and that
--      string is "Sidegrade" — not the token's "Trade-off".
--   2. UPGRADE and NOT_UPGRADE (cases 1 and 2, both arbitrated): both surfaces
--      still read the token's own word, unchanged.
--   3. NON-VACUITY: the pre-fix word (word(row.verdict)) is quoted beside the
--      window's, and the spec asserts the window did NOT print it. Point the
--      ledger back at the token and leg 1 reddens, naming the window surface.
--
-- The state word is the model's; the token is the surface's; the map between them
-- is Verdict.ARBITRATION_STATE_TOKEN. Nothing here re-derives a word: every
-- string asserted on is read off a surface (a drawn FontString, or the tooltip's
-- own line table).
--
-- Run from the repo root:  lua5.1 tests/touchstone_window_row_word_spec.lua

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."
if root == "." and not src:find("/") then root = "." end

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

local C = dofile(root .. "/tests/support/wowclient.lua")
C.Install({ width = 1920, height = 1080 })

local pkg = { PackVersion = function() return "0.5.0" end }
_G.MightiePack = pkg

-- The client's global aliases, which the module uses (UI.lua calls tinsert).
tinsert = table.insert
tremove = table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
MightiePackDB = { modules = {} }
StatForgeDB = { ui = { scale = 1 }, firstUse = false }

local TOUCH = root .. "/MightiePack/Modules/Touchstone/"
local function loadFile(name)
  local chunk, err = loadfile(TOUCH .. name)
  check(chunk ~= nil, "loadfile " .. name .. ": " .. tostring(err))
  if not chunk then return end
  local ok, e = pcall(chunk, "MightiePack", pkg)
  check(ok, "load " .. name .. ": " .. tostring(e))
end

-- The pack's own TOC order for everything this spec touches. Constants and the
-- two tab files first (they are what the window renders), then the engine and
-- the advisor it renders words from.
for _, name in ipairs({
  "Bootstrap.lua", "Constants.lua", "Weights.lua", "UI.lua",
  "UpgradesTab.lua", "LogTab.lua",
  "ChestAdvisor/Marks.lua", "ChestAdvisor/Verdict.lua", "ChestAdvisor/StatOrders.lua",
  "ChestAdvisor/Arbitration.lua", "ChestAdvisor/ChestAdvisor.lua",
}) do
  loadFile(name)
end

local SF = _G.StatForge
local CA = _G.ChestAdvisor
check(type(SF) == "table", "the module loads")
check(type(CA) == "table", "the advisor loads")

-- The advisor publishes its tooltip surface from its init functions, which the
-- pack calls from Enable() (the fold's load-order rule). This is the client's own
-- sequence: load, then enable.
local okEnable, enableErr = pcall(CA.Enable)
check(okEnable, "ChestAdvisor.Enable: " .. tostring(enableErr))
local TIP = type(CA) == "table" and CA.tooltipUI or nil
check(type(TIP) == "table", "ChestAdvisor.tooltipUI is published")
check(type(TIP) == "table" and type(TIP.wordFor) == "function",
  "the advisor publishes the arbitration-aware row word (TOOLTIP_UI.wordFor)")
check(type(TIP) == "table" and type(TIP.word) == "function",
  "the advisor still publishes the token map (TOOLTIP_UI.word)")
if type(TIP) ~= "table" or type(TIP.wordFor) ~= "function" or type(TIP.word) ~= "function" then
  io.stderr:write("cannot continue without the advisor's word map\n")
  os.exit(1)
end

-- ── the three pairs, judged by the real engine ───────────────────────────────
-- Verbatim from tests/touchstone_arbitration_parity_spec.lua (the §5a measured
-- healer, MID): one character, one context, so each state is a property of the
-- chest pair rather than of a hand-written row.
local SPELL = { id = 19939, name = "Holy Light", rank = 5, cost = 190, castTimeMs = 2500 }
local MID = {
  pool = 2060, regenCasting = 5.5885, crit = 6.38, bonusHealing = 36, level = 34,
  regenMeasured = true, spell = SPELL,
  stats = { Intellect = 101, Spirit = 80 },
}
local SPEC = { role = "spell", class = "PALADIN", context = "raid" }
local BETTER = { Intellect = 12, Healing = 30 }
local WORN = { Intellect = 10, Healing = 20 }
local TRADE_C = { Intellect = 6, Healing = 38 }
local TRADE_E = { Intellect = 12, Healing = 15 }

-- ── the rows, in the shape ChestAdvisor.getVerdicts publishes ────────────────
-- `arbitration` is Verdict.arbitrate's third return, exactly what the advisor
-- records (ChestAdvisor.lua, "arbitration = (type(arbDet) == \"table\") ...").
local ROWS = {}
local function row(caseKey, link, cand, eq)
  local token, reason, detail = Verdict.arbitrate(cand, eq, SPEC, MID)
  check(type(token) == "string", caseKey .. ": Verdict.arbitrate answered a token")
  check(type(detail) == "table", caseKey .. ": Verdict.arbitrate answered a detail table")
  local r = {
    id = 9000 + #ROWS + 1,
    verdict = token,
    reason = type(reason) == "string" and reason or "",
    arbitration = (type(detail) == "table") and detail or nil,
    slotWord = "Chest",
  }
  return r
end

local function addRow(caseKey, link, cand, eq)
  local entry = { key = caseKey, link = link, row = row(caseKey, link, cand, eq) }
  ROWS[#ROWS + 1] = entry
  return entry
end

local byKey = {}
for _, spec in ipairs({
  { key = "UPGRADE",     link = "[Parity Chest of the Better]", cand = BETTER,  eq = WORN },
  { key = "SIDEGRADE",   link = "[Parity Chest of the Trade]",  cand = TRADE_C, eq = TRADE_E },
  { key = "NOT_UPGRADE", link = "[Parity Chest of the Worse]",  cand = WORN,    eq = BETTER },
}) do
  byKey[spec.key] = addRow(spec.key, spec.link, spec.cand, spec.eq)
end

-- ── the words, read off the two real surfaces ───────────────────────────────
local function stripEscapes(text)
  text = tostring(text or "")
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return text
end

--- The tooltip's own first line for this row, and the word it headlines with.
--- ChestAdvisor.tooltipLines is the exported renderer (verdictLines); its first
--- entry is the verdict line the client puts on the item tooltip.
local function tooltipHeadline(r)
  local lines = CA.tooltipLines(r)
  if type(lines) ~= "table" or type(lines[1]) ~= "table" then return nil, nil end
  local text = stripEscapes(lines[1].text)
  local word = text:match("^([^—]+)") or text
  return text, (word:gsub("%s+$", ""))
end

-- Drive the REAL renderer: the window's Upgrades tab, fed by the advisor's own
-- getVerdicts. The rows read here are the drawn FontStrings, not a re-derivation.
local verdicts = {}
for _, entry in ipairs(ROWS) do verdicts[entry.link] = entry.row end
CA.getVerdicts = function() return verdicts end

check(type(SF.ShowMain) == "function", "SF.ShowMain exists")
local okShow, showErr = pcall(SF.ShowMain, "upgrades")
check(okShow, "SF.ShowMain(\"upgrades\"): " .. tostring(showErr))

--- The drawn row word for one link: the ledger row whose __link is that link.
local function windowWord(link)
  local seen, stack = {}, { UIParent }
  while #stack > 0 do
    local frame = table.remove(stack)
    if type(frame) == "table" and not seen[frame] then
      seen[frame] = true
      if frame.__link == link and type(frame.verdictWord) == "table" then
        local text = frame.verdictWord:GetText()
        if text ~= nil then return stripEscapes(text) end
      end
      for _, child in ipairs(frame:GetChildren() or {}) do stack[#stack + 1] = child end
    end
  end
  return nil
end

-- ── leg 1: SIDEGRADE — one word, both surfaces ───────────────────────────────
local side = byKey.SIDEGRADE
local sideWindow = windowWord(side.link)
local sideTipText, sideTipWord = tooltipHeadline(side.row)
local sideTokenWord = TIP.word(side.row.verdict)

check(side.row.verdict == "TRADE_OFF",
  "case 3 is a token-level trade-off (" .. tostring(side.row.verdict) .. ")")
check(type(side.row.arbitration) == "table" and side.row.arbitration.state == "SIDEGRADE",
  "case 3 is an arbitrated SIDEGRADE ("
    .. tostring(side.row.arbitration and side.row.arbitration.state) .. ")")
check(sideWindow ~= nil, "the window drew a row for the SIDEGRADE pair ("
  .. tostring(side.link) .. ")")
check(sideTipWord ~= nil, "the tooltip produced a headline for the SIDEGRADE pair")

print("case 3 · SIDEGRADE   window row word   " .. string.format("%q", tostring(sideWindow)))
print("case 3 · SIDEGRADE   tooltip headline  " .. string.format("%q", tostring(sideTipWord)))
print("case 3 · SIDEGRADE   tooltip line      " .. string.format("%q", tostring(sideTipText)))
print("case 3 · SIDEGRADE   pre-fix token word " .. string.format("%q", tostring(sideTokenWord)))

check(sideWindow == sideTipWord,
  "window ledger row (" .. tostring(sideWindow) .. ") and tooltip headline ("
    .. tostring(sideTipWord) .. ") name the same pair the same way")
check(sideWindow == TIP.words.SIDEGRADE,
  "the window ledger row reads the model's word, not the token's: expected "
    .. string.format("%q", tostring(TIP.words.SIDEGRADE)) .. ", got "
    .. string.format("%q", tostring(sideWindow)))

-- NON-VACUITY. The pre-fix source is `word(row.verdict)`, which is still a real
-- function on the advisor: if the window printed it, this leg names the window.
check(sideTokenWord == "Trade-off",
  "the token map still says Trade-off for this token (" .. tostring(sideTokenWord)
    .. ") — so the two words really are different strings")
check(sideWindow ~= sideTokenWord,
  "the window ledger row does NOT print the pre-arbitration word "
    .. string.format("%q", tostring(sideTokenWord)) .. " for a SIDEGRADE pair")

-- ── leg 2: UPGRADE and NOT_UPGRADE — unchanged on both surfaces ─────────────
for _, key in ipairs({ "UPGRADE", "NOT_UPGRADE" }) do
  local entry = byKey[key]
  local got = windowWord(entry.link)
  local _, tipWord = tooltipHeadline(entry.row)
  local tokenWord = TIP.word(entry.row.verdict)
  print(string.format("case %s   window row word %q   tooltip headline %q   token word %q",
    key, tostring(got), tostring(tipWord), tostring(tokenWord)))
  check(entry.row.arbitration and entry.row.arbitration.state == key,
    key .. ": the fixture really is an arbitrated " .. key)
  check(got ~= nil, key .. ": the window drew a row (" .. tostring(entry.link) .. ")")
  check(got == tipWord,
    key .. ": window ledger row (" .. tostring(got) .. ") and tooltip headline ("
      .. tostring(tipWord) .. ") agree")
  check(got == tokenWord,
    key .. ": the word is unchanged by this card — expected the token word "
      .. string.format("%q", tostring(tokenWord)) .. ", got "
      .. string.format("%q", tostring(got)))
end

if failed > 0 then
  io.stderr:write(tostring(failed) .. " check(s) failed\n")
  os.exit(1)
end
print("touchstone_window_row_word_spec: ok")
