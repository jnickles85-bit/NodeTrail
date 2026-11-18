-- Host opt-out: a host that vendors these files sets TouchstoneSkip = true before
-- loading them, and every shipped file returns at this line. Unset -- the normal
-- case -- nothing changes. See README.md, "Embedding Touchstone in a host addon".
if TouchstoneSkip then return end
--- Touchstone — Log tab (card t_b7b5f60c, audit U1 §4).
---
--- The disagreement log as a TABLE, with a Clear action, replacing the `/up log`
--- chat dump as the place a player reads it. ADDITIONAL surface only: the
--- `/up log` command keeps working exactly as before (AC-E) — this tab calls that
--- same command to clear, so there is one clear implementation, not two.
---
--- The log itself belongs to the advisor (`ChestAdvisorDB.log`, written by
--- ChestAdvisor.lua's own disagreement recorder). This tab reads it through
--- `ChestAdvisor.getLog()` and renders it; it records nothing and judges nothing.
---
--- B8: rows are pooled and re-bound, never re-created per refresh.

StatForge = StatForge or {}
local SF = StatForge
local C = SF.Colors

local ROW_MIN   = 34               -- the LEAST a row may be (a one-line reason)
local ROW_INSET = (type(MightiePackTheme) == "table"
  and type(MightiePackTheme.list) == "table"
  and tonumber(MightiePackTheme.list.inset)) or 6
local MARK      = (type(MightiePackTheme) == "table"
  and type(MightiePackTheme.list) == "table"
  and tonumber(MightiePackTheme.list.mark)) or 14
local NAME_GAP  = 1

-- The ledger's columns and type (card t_07f778ca, PART B): the same tokens the
-- Upgrades list uses, so the two tabs cannot draw two different ledgers.
local LIST = (type(MightiePackTheme) == "table"
  and type(MightiePackTheme.list) == "table") and MightiePackTheme.list or {}
local GUTTER      = LIST.gutter or 88
local CHANGE_W    = LIST.change or 110
local PAD_TOP     = LIST.padTop or 11
local PAD_BOTTOM  = LIST.padBottom or 12
local RULE_H      = LIST.rule or 1
local NAME_GAP_X  = LIST.nameGapX or 12
local NAME_SIZE   = LIST.nameSize or 14.5
local REASON_SIZE = LIST.reasonSize or 12
local LABEL_SIZE  = LIST.labelSize or 9.5
local ROW_W       = 780
local BODY_PAD    = (type(MightiePackTheme) == "table"
  and type(MightiePackTheme.size) == "table"
  and tonumber(MightiePackTheme.size.bodyPad)) or 20

local THEME = (type(MightiePackTheme) == "table") and MightiePackTheme or nil

--- A ledger colour, from the pack's theme when it is loaded; the body's brand
--- token is only the fallback for a standalone load (the vendored specs load
--- this file without the pack).
local function ledgerColor(token, fallback)
  if THEME and type(THEME.R) == "function" then
    local ok, r, g, b, a = pcall(THEME.R, token)
    if ok and type(r) == "number" then return r, g, b, a or 1 end
  end
  local c = fallback or { 1, 1, 1 }
  return c[1], c[2], c[3], (c[4] or 1)
end

--- The drawing's type sizes: SetFont(path, size, flags) is the client's whole
--- font surface (no weight axis, no letter-spacing).
local function ledgerFont(fs, size)
  if THEME and type(THEME.SetFont) == "function" then pcall(THEME.SetFont, fs, size) end
end

-- The wall-clock stamp the log entry carries (`at`). The advisor's formatter
-- is the one the chat print uses. This fallback is the same rule for a host
-- that loaded without it: a session age only when `time` is a GetTime value
-- from the client process running now, otherwise "earlier". A previous
-- process's uptime (hundreds of hours) is not an age.
local function formatStamp(at, entry)
  if ChestAdvisor and type(ChestAdvisor.formatLogStamp) == "function" and type(entry) == "table" then
    return ChestAdvisor.formatLogStamp(entry)
  end
  if type(at) == "number" and type(date) == "function" then
    local ok, s = pcall(date, "%m-%d %H:%M", at)
    if ok and type(s) == "string" and s ~= "" then return s end
  end
  if type(entry) == "table" and type(entry.time) == "number" then
    local now = nil
    local getTime = rawget(_G, "GetTime")
    if type(getTime) == "function" then
      local ok, t = pcall(getTime)
      if ok and type(t) == "number" then now = t end
    end
    if type(now) == "number" and entry.time >= 0 and entry.time <= now + 1 then
      local sec = math.floor(entry.time)
      if sec < 0 then sec = 0 end
      local m = math.floor(sec / 60)
      local h = math.floor(m / 60)
      m = m % 60
      if h > 0 then return string.format("session %dh%02dm", h, m) end
      return string.format("session %dm%02ds", m, sec % 60)
    end
    return "earlier"
  end
  return "no wall clock"
end

local function itemName(link)
  local name = nil
  if C_Item and type(C_Item.GetItemInfo) == "function" and type(link) == "string" then
    local ok, n = pcall(C_Item.GetItemInfo, link)
    if ok and type(n) == "string" and n ~= "" then name = n end
  end
  if name == nil and type(link) == "string" then
    local bracket = link:match("%[(.-)%]")
    if bracket and bracket ~= "" then name = bracket end
  end
  return name or tostring(link)
end

-- Which verdict colour: a recorded disagreement is a named negative, so it is
-- drawn in the ledger's own negative colours (card t_07f778ca, PART B) — the
-- drawing's palette has no alarm red, and the ledger's rule is that the VERDICT
-- carries the colour. A trade-off reads amber, a refusal the neutral grey.
local function verdictColor(verdict)
  if verdict == "TRADE_OFF" then return ledgerColor("ledgerTradeoff", C.warning) end
  return ledgerColor("ledgerNoUpgrade", C.textMuted)
end

-- The player-facing word for a stored verdict token. The mapping lives on the
-- advisor (ChestAdvisor.tooltipUI.word) so this tab does not keep a second
-- table. A missing mapper, or a nil return, falls back to the stored token.
local function playerWord(token)
  local ui = ChestAdvisor and ChestAdvisor.tooltipUI
  if type(ui) == "table" and type(ui.word) == "function" then
    local word = ui.word(token)
    if word ~= nil then return word end
  end
  return token
end

local state = {
  rows   = {},
  pool   = {},
  offset = 0,
  shown  = 0,   -- rows on the page the layout last placed
  host   = nil,
  layout = nil,
}

-- Read the log into render rows, oldest-first (the stored order), capped read.
local function readRows()
  local log = nil
  if ChestAdvisor and type(ChestAdvisor.getLog) == "function" then
    log = ChestAdvisor.getLog()
  end
  local rows = {}
  if type(log) ~= "table" then return rows end
  for i = 1, #log do
    local e = log[i]
    if type(e) == "table" then
      rows[#rows + 1] = {
        stamp   = formatStamp(e.at, e),
        slot    = (type(e.slotName) == "string") and e.slotName
                    or ("slot " .. tostring(e.slot)),
        link    = e.link,
        name    = itemName(e.link),
        verdict = tostring(e.verdict),
        reason  = tostring(e.reason),
      }
    end
  end
  return rows
end

-- Clear through the ONE implementation the player already has: the slash
-- command. This keeps a single clear path and keeps the command exercised.
-- The store is only touched directly if the command is somehow unavailable, so
-- a button can never be a silent no-op.
function SF.LogTabClear()
  local handler = type(SlashCmdList) == "table" and SlashCmdList.CHESTADVISOR
  if type(handler) == "function" then
    pcall(handler, "log clear")
    if state.host then SF.RefreshActiveTab() end
    return true
  end
  if type(ChestAdvisorDB) == "table" then
    ChestAdvisorDB.log = {}
    if state.host then SF.RefreshActiveTab() end
    return true
  end
  return false
end

function SF.LogTabState()
  return { total = #state.rows, offset = state.offset, shown = state.shown or 0 }
end

-- ---------------------------------------------------------------------------
-- THE LEDGER ROW (card t_07f778ca, PART B) — the same three columns as Upgrades,
-- so the two lists read as one drawing:
--
--   verdict gutter (88)   marker above the verdict word, both in its colour
--   name                  the item, on its own line
--     reason              beneath it, muted
--   change (110, right)   the slot the entry is about, dim — and, BENEATH it,
--                         the wall-clock stamp: a log row's "when" belongs with
--                         its "what changed", and the drawing has no fourth
--                         column for it
--
-- plus the row rule. Log entries are all negatives, so most rows have no marker
-- glyph — the verdict word alone is the statement (the bag grammar has no mark
-- for a refusal either).
-- ---------------------------------------------------------------------------
local function buildRow(parent, index)
  local row = CreateFrame("Frame", "TouchstoneLogRow" .. index, parent)
  row:SetHeight(ROW_MIN)
  -- No pitch (card t_4e5ad8a4): the row's height comes from its own measured
  -- cells and the stacking pass places it (SF.StackRow).
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)

  local gutter = CreateFrame("Frame", nil, row)
  gutter:SetWidth(GUTTER)
  gutter:SetPoint("TOPLEFT", row, "TOPLEFT", ROW_INSET, -PAD_TOP)
  row.gutter = gutter

  local mark = gutter:CreateTexture(nil, "OVERLAY")
  mark:SetSize(MARK, MARK)
  mark:SetPoint("TOPLEFT", gutter, "TOPLEFT", 0, 0)
  mark:Hide()
  row.mark = mark

  local verdict = gutter:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ledgerFont(verdict, NAME_SIZE)
  verdict:SetPoint("TOPLEFT", gutter, "TOPLEFT", 0, -(MARK + 4))
  verdict:SetWidth(GUTTER)
  verdict:SetJustifyH("LEFT")
  row.verdictWord = verdict

  local textLeft = GUTTER + NAME_GAP_X
  local textWidth = ROW_W - ROW_INSET * 2 - textLeft - CHANGE_W - 8
  if textWidth < 120 then textWidth = 120 end

  local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ledgerFont(name, NAME_SIZE)
  name:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -PAD_TOP)
  name:SetWidth(textWidth)
  name:SetJustifyH("LEFT")
  local nr, ng, nb, na = ledgerColor("ledgerText", C.text)
  name:SetTextColor(nr, ng, nb, na)
  row.itemName = name

  local reason = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ledgerFont(reason, REASON_SIZE)
  reason:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -NAME_GAP)
  reason:SetWidth(textWidth)
  reason:SetJustifyH("LEFT")
  local rr, rg, rb, ra = ledgerColor("ledgerMuted", C.textMuted)
  reason:SetTextColor(rr, rg, rb, ra)
  row.reason = reason

  local change = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ledgerFont(change, REASON_SIZE)
  change:SetPoint("TOPRIGHT", row, "TOPRIGHT", -ROW_INSET, -PAD_TOP)
  change:SetWidth(CHANGE_W)
  change:SetJustifyH("RIGHT")
  local dr, dg, db, da = ledgerColor("ledgerDim", C.textDim)
  change:SetTextColor(dr, dg, db, da)
  row.change = change

  local stamp = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ledgerFont(stamp, REASON_SIZE)
  stamp:SetPoint("TOPRIGHT", change, "BOTTOMRIGHT", 0, -NAME_GAP)
  stamp:SetWidth(CHANGE_W)
  stamp:SetJustifyH("RIGHT")
  local sr, sg, sb, sa = ledgerColor("ledgerDim", C.textDim)
  stamp:SetTextColor(sr, sg, sb, sa)
  row.stamp = stamp

  local rule = row:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(RULE_H)
  rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", ROW_INSET, 0)
  rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -ROW_INSET, 0)
  local lr, lg, lb, la = ledgerColor("ledgerLine")
  rule:SetColorTexture(lr, lg, lb, la)
  row.rule = rule

  return row
end

-- One row's height: the TALLEST column, measured (wrapped lines included), plus
-- the row's padding and its rule. ROW_MIN is a floor, not a pitch: a three-line
-- reason grows the row and the next entry starts below it (card t_4e5ad8a4).
local function rowHeight(row)
  local gutterH = MARK + 4 + (row.verdictWord:GetHeight() or 0)
  local textH = (row.itemName:GetHeight() or 0) + NAME_GAP + (row.reason:GetHeight() or 0)
  local changeH = (row.change:GetHeight() or 0) + NAME_GAP + (row.stamp:GetHeight() or 0)
  local inner = gutterH
  if textH > inner then inner = textH end
  if changeH > inner then inner = changeH end
  local h = PAD_TOP + inner + PAD_BOTTOM + RULE_H
  if h < ROW_MIN then h = ROW_MIN end
  return h
end

local function build(host)
  local title = SF.UI_CreateLabel(host, "", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", BODY_PAD, -BODY_PAD)
  local tr, tg, tb, ta = ledgerColor("ledgerText", C.text)
  title:SetTextColor(tr, tg, tb, ta)
  host.title = title

  local count = SF.UI_CreateLabel(host, "", "GameFontNormalSmall")
  count:SetPoint("LEFT", title, "RIGHT", 12, 0)
  local mr, mg, mb, ma = ledgerColor("ledgerMuted", C.textMuted)
  count:SetTextColor(mr, mg, mb, ma)
  host.count = count

  local clear = SF.UI_CreateButton(host, "Clear log", 120, 24)
  clear:SetPoint("TOPRIGHT", -BODY_PAD, -(BODY_PAD - 8))
  clear:SetScript("OnClick", function() SF.LogTabClear() end)
  host.clear = clear

  -- The column-label line, on the same three columns as the rows.
  local labels = CreateFrame("Frame", "TouchstoneLogColumns", host)
  labels:SetPoint("TOPLEFT", host, "TOPLEFT", BODY_PAD, -(BODY_PAD + 34))
  labels:SetPoint("TOPRIGHT", host, "TOPRIGHT", -BODY_PAD, -(BODY_PAD + 34))
  labels:SetHeight(LABEL_SIZE + 6)
  local function columnLabel(text, left, width, justify)
    local fs = labels:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ledgerFont(fs, LABEL_SIZE)
    fs:SetPoint("TOPLEFT", labels, "TOPLEFT", left, 0)
    fs:SetWidth(width)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetText(text)
    local r, g, b, a = ledgerColor("ledgerDim", C.textDim)
    fs:SetTextColor(r, g, b, a)
    return fs
  end
  host.colVerdict = columnLabel("VERDICT", ROW_INSET, GUTTER)
  host.colItem = columnLabel("ITEM AND REASON", GUTTER + NAME_GAP_X,
    ROW_W - ROW_INSET * 2 - GUTTER - NAME_GAP_X - CHANGE_W - 8)
  host.colChange = columnLabel("CHANGE", ROW_W - ROW_INSET * 2 - CHANGE_W, CHANGE_W, "RIGHT")
  host.columns = labels

  local viewport = CreateFrame("Frame", "TouchstoneLogViewport", host)
  viewport:SetPoint("TOPLEFT", labels, "BOTTOMLEFT", 0, -6)
  viewport:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -BODY_PAD, BODY_PAD)
  viewport:EnableMouseWheel(true)
  -- No page holds more than fits, but a single row taller than the viewport is
  -- still admitted (SF.PageRows) — clip so it cannot paint over the panel.
  if type(viewport.SetClipsChildren) == "function" then
    viewport:SetClipsChildren(true)
  end
  host.viewport = viewport

  local rowParent = CreateFrame("Frame", nil, viewport)
  rowParent:SetPoint("TOPLEFT")
  rowParent:SetWidth(ROW_W)
  host.rowParent = rowParent

  local function scrollBy(delta)
    if type(delta) ~= "number" or delta == 0 then return end
    local total = #state.rows
    -- One row per wheel step, to the last entry: the page is whatever fits.
    local maxOffset = math.max(0, total - 1)
    state.offset = math.max(0, math.min(maxOffset, state.offset + delta))
    if state.layout then state.layout() end
  end
  viewport:SetScript("OnMouseWheel", function(_, delta) scrollBy(-(delta or 0)) end)
  host.scrollBy = scrollBy

  local empty = SF.UI_CreateLabel(host,
    "Nothing logged yet. Equip an item Touchstone called not an upgrade and it is recorded here.",
    "GameFontHighlight")
  empty:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 20, -40)
  empty:SetWidth(700)
  empty:SetJustifyH("LEFT")
  empty:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  host.empty = empty

  state.host = host
end

local function repopulate(host)
  state.rows = readRows()
  local n = #state.rows
  for i = 1, n do
    if not state.pool[i] then
      state.pool[i] = buildRow(host.rowParent, i)
    end
  end

  local maxOffset = math.max(0, n - 1)
  if state.offset > maxOffset then state.offset = maxOffset end

  -- Card t_4e5ad8a4: the same row model Upgrades uses — bind and measure every
  -- row, take the page that fits the viewport, stack the rows at each other's
  -- bottoms. SF.PageRows / SF.StackRow are the shared rule, so a change to one
  -- list's geometry cannot leave the other behind.
  state.layout = function()
    for i, row in ipairs(state.pool) do
      local r = state.rows[i]
      if r then
        row.stamp:SetText(r.stamp)
        row.change:SetText(r.slot)
        row.itemName:SetText(r.name)
        -- Player word, not the stored token (card t_385a0817), in the verdict's
        -- colour — the word and the marker are one colour, read once.
        row.verdictWord:SetText(playerWord(r.verdict))
        local vc = { verdictColor(r.verdict) }
        row.verdictWord:SetTextColor(vc[1], vc[2], vc[3], vc[4] or 1)
        if r.verdict == "TRADE_OFF" then
          row.mark:SetTexture(nil)
          row.mark:SetColorTexture(vc[1], vc[2], vc[3], 0.95)
          row.mark:Show()
        else
          row.mark:Hide()
        end
        row.reason:SetText(r.reason)
        row:SetHeight(rowHeight(row))
      end
    end

    local heights = {}
    for i = 1, n do
      heights[i] = state.pool[i]:GetHeight()
    end
    local first, count = SF.PageRows(heights, state.offset, host.viewport:GetHeight() or 0)
    local y = 0
    for i = first, first + count - 1 do
      y = SF.StackRow(state.pool[i], host.rowParent, y)
      state.pool[i]:Show()
    end
    for i, row in ipairs(state.pool) do
      if i < first or i >= first + count then row:Hide() end
    end
    host.rowParent:SetHeight(math.max(y, 1))
    state.shown = count
  end
  state.layout()
end

local function render(host)
  if state.host ~= host then build(host) end

  repopulate(host)

  local total = #state.rows
  -- The section head reads in the ledger's text colour — not SF.Accent(), which
  -- would put the body's cyan in a drawing whose only colour is the verdict.
  host.title:SetText("Log")
  if total == 0 then
    host.count:SetText("0 recorded disagreements")
    host.empty:Show()
    host.viewport:Hide()
    host.clear:SetLabel("Clear log")
  else
    host.empty:Hide()
    host.viewport:Show()
    local page = state.shown or 0
    local more = ""
    if total > page and page > 0 then
      more = " · rows " .. tostring(state.offset + 1) .. "-"
        .. tostring(math.min(state.offset + page, total))
    end
    host.count:SetText(tostring(total) .. " recorded disagreement"
      .. (total == 1 and "" or "s") .. more)
    host.clear:SetLabel("Clear log")
  end
end

local function release()
end

SF.RegisterTab("log", render, release)
