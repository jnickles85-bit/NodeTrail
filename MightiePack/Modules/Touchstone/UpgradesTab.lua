if MightiePackTouchstoneSkip then return end
--- Touchstone — Upgrades tab (card t_b7b5f60c, audit U1).
---
--- WHAT THIS IS. The window's DEFAULT tab, and the reason the window exists: the
--- advisor's own answer list. Every row is one bag item that has a verdict, read
--- from `ChestAdvisor.getVerdicts()` — the scan's own record — and NOTHING here
--- judges anything. There is no second comparator, no re-derived number and no
--- second source of truth. If a row is missing, the scan did not produce it; if a
--- row is wrong, the scan produced it wrong. This file is a VIEW.
---
--- Reuses, deliberately, rather than rebuilding:
---   * the verdict data — ChestAdvisor.getVerdicts();
---   * the item's real client icon — C_Item.GetItemIconByID (the toast's own read);
---   * the item's name / rarity — C_Item.GetItemInfo (the tooltip's own read);
---   * the mark art — ChestAdvisor/marker.tga, the SAME texture the bag arrow and
---     the toast use, and a plain amber SetColorTexture square for the trade-off
---     (the bag chip's own grammar). NO new asset, so no `## Assets:` change;
---   * the tooltip — the client's own GameTooltip: SetOwner + SetHyperlink, which
---     is exactly the surface the advisor's existing TooltipDataProcessor post-call
---     already annotates with the Touchstone verdict line. Hovering a row shows the
---     REAL item tooltip with the SAME line the bag hover shows; a second tooltip
---     implementation is exactly what the card forbids.
---
--- B8 (card t_b7b5f60c). Every widget below is created ONCE per host frame and is
--- then re-bound. `build` runs on the first render only; `repopulate` runs on every
--- later refresh and only ever calls SetText / SetTexture / Show / Hide on pooled
--- objects. WoW never frees a frame, so a tab that re-creates its tree on each
--- refresh leaks one tree per refresh — the defect (audit B8) this file must not
--- reintroduce.

StatForge = StatForge or {}
local SF = StatForge
local C = SF.Colors

-- The marker texture the bag arrow and the toast both use. Loaded BY PATH (a
-- texture is not a loadable file — listing it in the TOC raises at login). The
-- path is the merged layout's own: Touchstone/ChestAdvisor/marker.tga.
local MARKER_TEXTURE =
  "Interface\\AddOns\\Touchstone\\ChestAdvisor\\marker.tga"

local ROW_H   = 34
local ICON    = 22
local MARK    = 14
local VISIBLE = 12               -- rows that fit the host without scrolling
local ROW_INSET = 6

-- The verdict the advisor reports for a genuine trade-off. Read off the
-- comparator when it is present (never a second hard-coded truth), with the bare
-- literal only as the load-order fallback — the same posture ChestAdvisor.lua
-- itself takes toward Verdict.
local function tradeOffWord()
  local V = rawget(_G, "Verdict")
  if type(V) == "table" and type(V.TRADE_OFF) == "string" then return V.TRADE_OFF end
  return "TRADE_OFF"
end

-- Rank for the card's own sort order: UPGRADE first, then TRADE_OFF, then the
-- rest. A verdict the advisor did not produce (a future word) lands in "the
-- rest" rather than being dropped.
local function verdictRank(v)
  if v == "UPGRADE" then return 1 end
  if v == tradeOffWord() then return 2 end
  return 3
end

-- Does this row carry a MARK (an arrow or a chip)? The toggle narrows the list
-- to these; everything else is the "no change" tail.
local function isMarked(v)
  return verdictRank(v) <= 2
end

-- The client's own rarity colour, with a local fallback table so a client that
-- does not expose GetItemQualityColor still colours the name instead of
-- crashing. Index 1 is the client's "unknown rarity" (white).
local FALLBACK_QUALITY = {
  [0] = { 0.62, 0.62, 0.62 },
  [1] = { 1.00, 1.00, 1.00 },
  [2] = { 0.12, 1.00, 0.00 },
  [3] = { 0.00, 0.44, 0.87 },
  [4] = { 0.64, 0.21, 0.93 },
  [5] = { 1.00, 0.50, 0.00 },
  [6] = { 0.90, 0.80, 0.50 },
}
local function qualityColor(quality)
  if type(GetItemQualityColor) == "function" and type(quality) == "number" then
    local ok, r, g, b = pcall(GetItemQualityColor, quality)
    if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
      return r, g, b
    end
  end
  local c = FALLBACK_QUALITY[quality or 1] or FALLBACK_QUALITY[1]
  return c[1], c[2], c[3]
end

-- The item's name and rarity from the client's own read. Never fabricated: a
-- miss falls back to the link's own bracket text, and only then to a literal.
local function itemIdentity(link)
  local name, quality = nil, nil
  if C_Item and type(C_Item.GetItemInfo) == "function" then
    -- pcall prepends the success flag, so the client's returns shift by one:
    -- [1]=ok, [2]=name, [3]=link, [4]=quality. Collected in a table because the
    -- call returns many values and only two of them are wanted here.
    local r = { pcall(C_Item.GetItemInfo, link) }
    if r[1] then
      if type(r[2]) == "string" and r[2] ~= "" then name = r[2] end
      if type(r[4]) == "number" then quality = r[4] end
    end
  end
  if name == nil and type(link) == "string" then
    local bracket = link:match("%[(.-)%]")
    if bracket and bracket ~= "" then name = bracket end
  end
  if name == nil then name = "item" end
  return name, quality
end

-- The item's real client icon (the fallback bag icon — the same one the toast
-- falls back to — when the client will not answer).
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local function itemIcon(id)
  if C_Item and type(C_Item.GetItemIconByID) == "function" and type(id) == "number" then
    local ok, tex = pcall(C_Item.GetItemIconByID, id)
    if ok and tex then return tex end
  end
  return FALLBACK_ICON
end

-- Open the bags so the player can see the cell the row is about. Guarded against
-- every name this client family has used; the sweep card owns marker behaviour,
-- so nothing here flashes or touches a cell.
local OPENERS = { "OpenAllBags", "ToggleAllBags", "OpenBackpack", "ToggleBackpack" }
local function openBags()
  for _, name in ipairs(OPENERS) do
    local fn = rawget(_G, name)
    if type(fn) == "function" then
      pcall(fn)
      return true
    end
  end
  return false
end

-- Rows, in the card's order: UPGRADE, then TRADE_OFF, then the rest. The tail
-- inside a rank is ordered by name then link, so the list is repeatable rather
-- than dependent on pairs() order.
local function buildRows(verdicts)
  local rows = {}
  if type(verdicts) ~= "table" then return rows end
  for link, row in pairs(verdicts) do
    if type(row) == "table" and type(row.verdict) == "string" then
      local name, quality = itemIdentity(link)
      rows[#rows + 1] = {
        link     = link,
        verdict  = row.verdict,
        reason   = (type(row.reason) == "string") and row.reason or "",
        slotWord = (type(row.slotWord) == "string") and row.slotWord or "slot",
        id       = row.id,
        name     = name,
        quality  = quality,
        rank     = verdictRank(row.verdict),
      }
    end
  end
  table.sort(rows, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.name ~= b.name then return a.name < b.name end
    return tostring(a.link) < tostring(b.link)
  end)
  return rows
end

-- ---------------------------------------------------------------------------
-- Tab state. `showAll` gates the non-marked tail. It defaults ON so that a fresh
-- window shows exactly the rows getVerdicts() returned (AC-B); the toggle is an
-- explicit narrowing, never a hidden filter.
-- ---------------------------------------------------------------------------
local state = {
  showAll  = true,
  rows     = {},   -- every row, sorted (the card's order)
  rendered = {},   -- the rows the toggle admits
  pool     = {},   -- one Button per index, created once
  offset   = 0,
  host     = nil,
  layout   = nil,
}

-- A read-only snapshot for the tests. Mirrors the toastState() convention: the
-- tab exposes what it drew, it does not re-derive it.
--   * `rows`    — every row, in the card's sort order (the full verdict set);
--   * `admitted`— the rows the toggle currently admits (a subset of `rows`);
--   * `shown`   — how many of the admitted rows are inside the visible window.
function SF.UpgradesTabState()
  local out = {
    showAll  = state.showAll,
    total    = #state.rows,
    admitted = #state.rendered,
    shown    = 0,
    offset   = state.offset,
    rows     = {},
    rendered = {},
  }
  for i, r in ipairs(state.rows) do
    out.rows[i] = {
      link = r.link, verdict = r.verdict, reason = r.reason,
      slotWord = r.slotWord, name = r.name, rank = r.rank,
    }
  end
  for i, r in ipairs(state.rendered) do
    out.rendered[i] = {
      link = r.link, verdict = r.verdict, reason = r.reason,
      slotWord = r.slotWord, name = r.name, rank = r.rank,
    }
  end
  for i = 1, #state.rendered do
    if i > state.offset and i <= state.offset + VISIBLE then
      out.shown = out.shown + 1
    end
  end
  return out
end

-- The show/hide toggle, callable from a test as well as from the button. Returns
-- the new setting. It changes the ROW SET only — the verdict data is untouched.
function SF.UpgradesTabSetShowAll(on)
  state.showAll = on and true or false
  state.offset = 0
  if state.host and state.layout then
    SF.RefreshActiveTab()
  end
  return state.showAll
end

-- ---------------------------------------------------------------------------
-- One-time widget build. Everything created here is created exactly once.
-- ---------------------------------------------------------------------------
local function buildRow(parent, index)
  local row = CreateFrame("Button", "TouchstoneUpgradeRow" .. index, parent)
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_H))
  row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((index - 1) * ROW_H))

  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON, ICON)
  icon:SetPoint("LEFT", ROW_INSET, 0)
  row.icon = icon

  -- The mark. The green arrow is the SAME marker.tga the bag arrow uses; the
  -- trade-off mark is a plain amber square drawn with SetColorTexture — the
  -- identical no-new-art grammar the bag chip uses.
  local mark = row:CreateTexture(nil, "OVERLAY")
  mark:SetSize(MARK, MARK)
  mark:SetPoint("TOPLEFT", icon, "TOPLEFT", -3, 3)
  mark:Hide()
  row.mark = mark

  local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  name:SetPoint("LEFT", icon, "RIGHT", 10, 6)
  name:SetWidth(400)
  name:SetJustifyH("LEFT")
  row.itemName = name

  local reason = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  reason:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
  reason:SetWidth(400)
  reason:SetJustifyH("LEFT")
  row.reason = reason

  local slot = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  slot:SetPoint("RIGHT", -10, 0)
  slot:SetJustifyH("RIGHT")
  slot:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  row.slot = slot

  -- Hover: the client's own tooltip, on the item's own link. The advisor's
  -- existing post-call adds the Touchstone verdict line to it on the live
  -- client; no second tooltip path is built here.
  row:SetScript("OnEnter", function(self)
    if type(self.__link) ~= "string" or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(self.__link)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
  -- Click opens the bags. Flashing the cell is the sweep card's business; this
  -- only gets the player to the right window.
  row:SetScript("OnClick", function() openBags() end)

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

  -- The show/hide toggle. Its label states what a click will DO.
  local toggle = SF.UI_CreateButton(host, "Show all", 130, 24)
  toggle:SetPoint("TOPRIGHT", -18, -12)
  toggle:SetScript("OnClick", function()
    SF.UpgradesTabSetShowAll(not state.showAll)
  end)
  host.toggle = toggle

  -- The viewport. A plain frame with a wheel handler: no UIPanelScrollFrameTemplate,
  -- no second named scroll global, no new art. Rows live in a child frame that is
  -- sized once and re-positioned by the wheel handler.
  local viewport = CreateFrame("Frame", "TouchstoneUpgradesViewport", host)
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
    local shown = #state.rendered
    local maxOffset = math.max(0, shown - VISIBLE)
    state.offset = math.max(0, math.min(maxOffset, state.offset + delta))
    if state.layout then state.layout() end
  end
  viewport:SetScript("OnMouseWheel", function(_, delta) scrollBy(-(delta or 0)) end)
  host.scrollBy = scrollBy

  local empty = SF.UI_CreateLabel(host,
    "No verdicts yet — open your bags, or run /up rescan.", "GameFontHighlight")
  empty:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 20, -40)
  empty:SetWidth(600)
  empty:SetJustifyH("LEFT")
  empty:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3])
  host.empty = empty

  state.host = host
end

-- ---------------------------------------------------------------------------
-- Repopulate. Reads the pool; creates a row only when the pool is too small, so
-- a tab switch or a rescan reuses the same frames.
-- ---------------------------------------------------------------------------
local function repopulate(host)
  state.rows = buildRows(ChestAdvisor and ChestAdvisor.getVerdicts())
  local keepAll = state.showAll
  state.rendered = {}
  for _, r in ipairs(state.rows) do
    if keepAll or isMarked(r.verdict) then
      state.rendered[#state.rendered + 1] = r
    end
  end

  local n = #state.rendered
  for i = 1, n do
    if not state.pool[i] then
      state.pool[i] = buildRow(host.rowParent, i)
    end
  end

  local maxOffset = math.max(0, n - VISIBLE)
  if state.offset > maxOffset then state.offset = maxOffset end

  state.layout = function()
    for i, row in ipairs(state.pool) do
      local r = state.rendered[i]
      local visible = (r ~= nil) and (i > state.offset) and (i <= state.offset + VISIBLE)
      if visible then
        row.__link = r.link
        row.slot:SetText(r.slotWord)

        local qr, qg, qb = qualityColor(r.quality)
        row.itemName:SetText(r.name)
        row.itemName:SetTextColor(qr, qg, qb)
        row.reason:SetText(r.reason)

        row.icon:SetTexture(itemIcon(r.id))

        if r.verdict == "UPGRADE" then
          row.mark:SetTexture(MARKER_TEXTURE)
          row.mark:Show()
        elseif r.verdict == tradeOffWord() then
          row.mark:SetTexture(nil)
          row.mark:SetColorTexture(1, 0.65, 0.15, 0.9)
          row.mark:Show()
        else
          row.mark:Hide()
        end

        row:Show()
      else
        row.__link = nil
        row:Hide()
      end
    end
  end
  state.layout()
end

local function render(host)
  if state.host ~= host then
    build(host)
  end

  repopulate(host)

  host.toggle:SetLabel(state.showAll and "Upgrades only" or "Show all")

  local total = #state.rows
  local shown = #state.rendered
  host.title:SetText(SF.Accent("Upgrades"))
  if total == 0 then
    host.count:SetText("")
    host.empty:Show()
    host.viewport:Hide()
  else
    host.empty:Hide()
    host.viewport:Show()
    local more = ""
    if shown > VISIBLE then
      more = "  ·  rows " .. tostring(state.offset + 1) .. "-"
        .. tostring(math.min(state.offset + VISIBLE, shown))
    end
    host.count:SetText(tostring(shown) .. " of " .. tostring(total)
      .. " item" .. (total == 1 and "" or "s") .. more)
  end
end

local function release()
  -- Nothing session-scoped is held: the host and the row pool outlive a hide, and
  -- the tooltip is the client's own. The rows keep no state that must be dropped.
end

SF.RegisterTab("upgrades", render, release)
