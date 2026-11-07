if MightiePackTouchstoneSkip then return end
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

local ROW_H   = 30
local VISIBLE = 13

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
-- rendered in the danger colour rather than the accent. (Only a named negative
-- is ever logged — the advisor's own `isDisagreement` gate — so the colour is a
-- statement about the entry, not a guess.)
local function verdictColor(verdict)
  if verdict == "NOT_UPGRADE" then return C.danger end
  if verdict == "TRADE_OFF" then return C.warning end
  return C.textMuted
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
  return { total = #state.rows, offset = state.offset }
end

local function buildRow(parent, index)
  local row = CreateFrame("Frame", "TouchstoneLogRow" .. index, parent)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_H))
  row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * ROW_H))

  local stamp = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  stamp:SetPoint("LEFT", 6, 0)
  stamp:SetWidth(84)
  stamp:SetJustifyH("LEFT")
  stamp:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  row.stamp = stamp

  local slot = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  slot:SetPoint("LEFT", stamp, "RIGHT", 8, 0)
  slot:SetWidth(76)
  slot:SetJustifyH("LEFT")
  slot:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
  row.slot = slot

  local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  name:SetPoint("LEFT", slot, "RIGHT", 6, 0)
  name:SetWidth(190)
  name:SetJustifyH("LEFT")
  row.itemName = name

  local verdict = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  verdict:SetPoint("LEFT", name, "RIGHT", 8, 0)
  verdict:SetWidth(96)
  verdict:SetJustifyH("LEFT")
  row.verdict = verdict

  local reason = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  reason:SetPoint("LEFT", verdict, "RIGHT", 6, 0)
  reason:SetWidth(360)
  reason:SetJustifyH("LEFT")
  reason:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  row.reason = reason

  return row
end

local function build(host)
  local title = SF.UI_CreateLabel(host, "", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 18, -14)
  title:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
  host.title = title

  local count = SF.UI_CreateLabel(host, "", "GameFontNormalSmall")
  count:SetPoint("LEFT", title, "RIGHT", 12, -2)
  count:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  host.count = count

  local clear = SF.UI_CreateButton(host, "Clear log", 120, 24)
  clear:SetPoint("TOPRIGHT", -18, -12)
  clear:SetScript("OnClick", function() SF.LogTabClear() end)
  host.clear = clear

  local viewport = CreateFrame("Frame", "TouchstoneLogViewport", host)
  viewport:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 8, -10)
  viewport:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -18, 12)
  viewport:EnableMouseWheel(true)
  host.viewport = viewport

  local rowParent = CreateFrame("Frame", nil, viewport)
  rowParent:SetPoint("TOPLEFT")
  rowParent:SetSize(780, VISIBLE * ROW_H)
  host.rowParent = rowParent

  local function scrollBy(delta)
    if type(delta) ~= "number" or delta == 0 then return end
    local total = #state.rows
    local maxOffset = math.max(0, total - VISIBLE)
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

  local maxOffset = math.max(0, n - VISIBLE)
  if state.offset > maxOffset then state.offset = maxOffset end

  state.layout = function()
    for i, row in ipairs(state.pool) do
      local r = state.rows[i]
      local visible = (r ~= nil) and (i > state.offset) and (i <= state.offset + VISIBLE)
      if visible then
        row.stamp:SetText(r.stamp)
        row.slot:SetText(r.slot)
        row.itemName:SetText(r.name)
        -- Player word, not the stored token (card t_385a0817). The colour
        -- below still keys off the token.
        row.verdict:SetText(playerWord(r.verdict))
        local vc = verdictColor(r.verdict)
        row.verdict:SetTextColor(vc[1], vc[2], vc[3])
        row.reason:SetText(r.reason)
        row:Show()
      else
        row:Hide()
      end
    end
  end
  state.layout()
end

local function render(host)
  if state.host ~= host then build(host) end

  repopulate(host)

  local total = #state.rows
  host.title:SetText(SF.Accent("Log"))
  if total == 0 then
    host.count:SetText("")
    host.empty:Show()
    host.viewport:Hide()
    host.clear:SetLabel("Clear log")
  else
    host.empty:Hide()
    host.viewport:Show()
    local more = ""
    if total > VISIBLE then
      more = "  ·  rows " .. tostring(state.offset + 1) .. "-"
        .. tostring(math.min(state.offset + VISIBLE, total))
    end
    host.count:SetText(tostring(total) .. " recorded disagreement"
      .. (total == 1 and "" or "s") .. more)
    host.clear:SetLabel("Clear log")
  end
end

local function release()
end

SF.RegisterTab("log", render, release)
