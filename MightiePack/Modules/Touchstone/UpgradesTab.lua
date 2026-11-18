-- Host opt-out: a host that vendors these files sets TouchstoneSkip = true before
-- loading them, and every shipped file returns at this line. Unset -- the normal
-- case -- nothing changes. See README.md, "Embedding Touchstone in a host addon".
if TouchstoneSkip then return end
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
-- path comes from SF.AssetPath, resolved where the texture is set: a host that
-- vendors these files keeps them under its own folder and sets the base once.


-- Card t_2d2c37b0: the list's metrics ARE the window's metrics. The pack's
-- theme publishes them (MightiePack/Theme.lua, T.list) and the literal
-- fallbacks keep this file loadable on its own — the vendored specs load it
-- without the pack. ROW_MIN is a FLOOR, not a pitch: the row model measures the
-- wrapped reason and grows (card t_4e5ad8a4).
local LIST = (type(MightiePackTheme) == "table"
  and type(MightiePackTheme.list) == "table") and MightiePackTheme.list or {}
local ROW_MIN     = LIST.rowMin or 34     -- the LEAST a row may be (a one-line reason)
local ROW_INSET   = LIST.inset or 6       -- a row's own inset from the list edge
local MARK        = LIST.mark or 14       -- the marker glyph
local NAME_GAP    = LIST.nameGap or 1     -- between a row's name and its reason
-- The ledger's columns (card t_07f778ca, PART B). Every number here is the
-- window's token, not a value of this file's own.
local GUTTER      = LIST.gutter or 88     -- verdict gutter: marker over the word
local CHANGE_W    = LIST.change or 110    -- the right-aligned change column
local PAD_TOP     = LIST.padTop or 11
local PAD_BOTTOM  = LIST.padBottom or 12
local RULE_H      = LIST.rule or 1        -- the row's hairline
local NAME_GAP_X  = LIST.nameGapX or 12   -- gutter -> name
local NAME_SIZE   = LIST.nameSize or 14.5
local REASON_SIZE = LIST.reasonSize or 12
local LABEL_SIZE  = LIST.labelSize or 9.5 -- the column-label line, uppercase
local ROW_W       = 780                   -- the list's own width
local BODY_PAD    = (type(MightiePackTheme) == "table"
  and type(MightiePackTheme.size) == "table"
  and type(MightiePackTheme.size.bodyPad) == "number")
  and MightiePackTheme.size.bodyPad or 20

-- The pack's palette and type, through ONE read each (card t_07f778ca, PART B).
-- When the theme is loaded — it is, inside the window — the ledger takes its
-- colours from T.R("ledger…") and never states one of its own. The fallbacks are
-- the body's brand, so this file still draws something when a spec loads it
-- alone; they are not a second palette, they are the same file's old default.
local THEME = (type(MightiePackTheme) == "table") and MightiePackTheme or nil

local function ledgerColor(token, fallback)
  if THEME and type(THEME.R) == "function" then
    local ok, r, g, b, a = pcall(THEME.R, token)
    if ok and type(r) == "number" then return r, g, b, a or 1 end
  end
  local c = fallback or { 1, 1, 1 }
  return c[1], c[2], c[3], (c[4] or 1)
end

--- The drawing's type sizes. WoW has no weight axis and no letter-spacing:
--- SetFont(path, size, flags) is the whole surface, so the size and the colour
--- carry the hierarchy (see T.SetFont's note in MightiePack/Theme.lua).
local function ledgerFont(fs, size)
  if THEME and type(THEME.SetFont) == "function" then pcall(THEME.SetFont, fs, size) end
end

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

-- The verdict's COLOUR is the information (card t_07f778ca, PART B): green when
-- equipping is right, amber when it is a trade-off, grey when it is refused.
-- One function, so the marker glyph and the verdict word beside it can never be
-- two different colours. The fallback is the body's brand token, for a load
-- without the pack's theme.
local function verdictColor(v)
  if v == "UPGRADE" then return ledgerColor("ledgerUpgrade", C.success) end
  if v == tradeOffWord() then return ledgerColor("ledgerTradeoff", C.warning) end
  return ledgerColor("ledgerNoUpgrade", C.textMuted)
end

-- The player word for a ROW. The mapping lives on the advisor
-- (ChestAdvisor.tooltipUI), so this tab keeps no second vocabulary — the same
-- rule the Log tab applies.
--
-- Card t_c8970547: ask the ROW, not the stored token. `wordFor` is the one
-- arbitration-aware word the item tooltip and both mark hovers already read, so
-- a pair the model answered SIDEGRADE reads "Sidegrade" in the ledger exactly as
-- it does in the tooltip. A renderer that re-derived the word from `row.verdict`
-- would say "Trade-off" for that same pair, and would drift the moment the
-- state -> token map moved. The token map (`word`) stays only as the fallback
-- for a build whose advisor does not publish `wordFor`; the raw token is last.
local function verdictWord(row)
  local ui = ChestAdvisor and ChestAdvisor.tooltipUI
  local token = type(row) == "table" and row.verdict or row
  if type(ui) == "table" then
    if type(ui.wordFor) == "function" then
      local word = ui.wordFor(row)
      if word ~= nil then return tostring(word) end
    end
    if type(ui.word) == "function" then
      local word = ui.word(token)
      if word ~= nil then return tostring(word) end
    end
  end
  return tostring(token)
end

-- NO RARITY COLOUR ON THE NAME (card t_07f778ca, PART B). The drawing's rule is
-- that "the verdict carries the colour and the weight": a row with a blue item
-- name AND a green verdict AND an amber trade-off is five colours in three
-- lines, which is the "panel of panels" look the reshape card ended. The name is
-- the anchor in the ledger's text colour; the verdict is the only coloured word.
-- (The rarity is still recorded on the row — `quality` — it is just not painted.)

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

-- The item's real client icon is NOT drawn in the ledger (card t_07f778ca,
-- PART B): the drawing is flat and ruled, and an icon column would put a 22px
-- picture where the verdict's marker belongs. The row's `id` is still recorded —
-- the tooltip and the bag markers use it — it is simply not painted here.

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
        -- Card t_c8970547: the model's own answer rides into the tab with the
        -- token. The row WORD is asked of this table (TOOLTIP_UI.wordFor on the
        -- advisor), never re-derived from the token, and it is nil on every row
        -- the model did not answer — exactly the shape the advisor records.
        arbitration = (type(row.arbitration) == "table") and row.arbitration or nil,
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
  shown    = 0,    -- rows on the page the layout last placed
  host     = nil,
  layout   = nil,
}

-- A read-only snapshot for the tests. Mirrors the toastState() convention: the
-- tab exposes what it drew, it does not re-derive it.
--   * `rows`    — every row, in the card's sort order (the full verdict set);
--   * `admitted`— the rows the toggle currently admits (a subset of `rows`);
--   * `shown`   — how many of the admitted rows the layout placed on the page.
function SF.UpgradesTabState()
  local out = {
    showAll  = state.showAll,
    total    = #state.rows,
    admitted = #state.rendered,
    shown    = state.shown or 0,
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
--
-- THE LEDGER ROW (card t_07f778ca, PART B). Three columns, and the row is a
-- RULED line rather than a card:
--
--   verdict gutter (88)      marker glyph ABOVE the verdict word, both in the
--                            verdict's colour — the widest-reading cell, first
--   name                     the anchor, on its own line
--     reason                 beneath the name, muted — never beside it, so a
--                            long reason grows the row instead of pushing the
--                            name sideways
--   change (110, right)      what the verdict would change, dim and quiet
--
-- plus a 1px hairline at the row's bottom, which is what makes a run of rows
-- read as a ledger.
-- ---------------------------------------------------------------------------
local function buildRow(parent, index)
  local row = CreateFrame("Button", "TouchstoneUpgradeRow" .. index, parent)
  row:SetHeight(ROW_MIN)
  -- No pitch baked in here (card t_4e5ad8a4). The row's own height is set from
  -- its measured text and it is PLACED by the stacking pass (SF.StackRow), so a
  -- reason that wraps to three lines pushes the next row down instead of
  -- printing over it.
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)

  -- The gutter is a frame of its own so its width is the TOKEN and not an
  -- accident of where two labels happen to end.
  local gutter = CreateFrame("Frame", nil, row)
  gutter:SetWidth(GUTTER)
  gutter:SetPoint("TOPLEFT", row, "TOPLEFT", ROW_INSET, -PAD_TOP)
  row.gutter = gutter

  -- The mark. The green arrow is the SAME marker.tga the bag arrow uses; the
  -- trade-off mark is a plain amber square (SetColorTexture) — the identical
  -- no-new-art grammar the bag chip uses. Both are tinted with the verdict's own
  -- colour below, so the glyph and the word never disagree.
  local mark = gutter:CreateTexture(nil, "OVERLAY")
  mark:SetSize(MARK, MARK)
  mark:SetPoint("TOPLEFT", gutter, "TOPLEFT", 0, 0)
  mark:Hide()
  row.mark = mark

  local word = gutter:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ledgerFont(word, NAME_SIZE)
  word:SetPoint("TOPLEFT", gutter, "TOPLEFT", 0, -(MARK + 4))
  word:SetWidth(GUTTER)
  word:SetJustifyH("LEFT")
  row.verdictWord = word

  -- The name and the reason share one column, so they wrap at the same width.
  local textLeft = GUTTER + NAME_GAP_X
  local textWidth = ROW_W - ROW_INSET * 2 - textLeft - CHANGE_W - 8
  if textWidth < 120 then textWidth = 120 end

  local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ledgerFont(name, NAME_SIZE)
  -- Anchored to the row's TOP: the reason hangs below the name, so the row's
  -- height is measured against its content's bottom.
  name:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -PAD_TOP)
  name:SetWidth(textWidth)
  name:SetJustifyH("LEFT")
  row.itemName = name

  local reason = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ledgerFont(reason, REASON_SIZE)
  reason:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -NAME_GAP)
  reason:SetWidth(textWidth)
  reason:SetJustifyH("LEFT")
  row.reason = reason

  -- The change column: the same width as the token, right-aligned, dim.
  local change = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  ledgerFont(change, REASON_SIZE)
  change:SetPoint("TOPRIGHT", row, "TOPRIGHT", -ROW_INSET, -PAD_TOP)
  change:SetWidth(CHANGE_W)
  change:SetJustifyH("RIGHT")
  local dr, dg, db, da = ledgerColor("ledgerDim", C.textDim)
  change:SetTextColor(dr, dg, db, da)
  row.change = change

  -- The row rule: one hairline, the ledger's own line token.
  local rule = row:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(RULE_H)
  rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", ROW_INSET, 0)
  rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -ROW_INSET, 0)
  local lr, lg, lb, la = ledgerColor("ledgerLine")
  rule:SetColorTexture(lr, lg, lb, la)
  row.rule = rule

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

-- One row's height: the TALLEST of its columns, MEASURED (a FontString's
-- GetHeight is its rendered height, wrapped lines included), plus the row's own
-- padding and its rule. ROW_MIN is a floor, not a pitch: a one-line row keeps
-- the floor, a three-line reason makes the row taller and the next row starts
-- below it — the rule this file must never lose (card t_4e5ad8a4).
local function rowHeight(row)
  local gutterH = MARK + 4 + (row.verdictWord:GetHeight() or 0)
  local textH = (row.itemName:GetHeight() or 0) + NAME_GAP + (row.reason:GetHeight() or 0)
  local changeH = row.change:GetHeight() or 0
  local inner = gutterH
  if textH > inner then inner = textH end
  if changeH > inner then inner = changeH end
  local h = PAD_TOP + inner + PAD_BOTTOM + RULE_H
  if h < ROW_MIN then h = ROW_MIN end
  return h
end

local function build(host)
  -- The section head: "Upgrades" and the count in the ledger's own words
  -- ("5 judged · 2 worth taking"), both set from the list at render time.
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

  -- The show/hide toggle. Its label states what a click will DO.
  local toggle = SF.UI_CreateButton(host, "Show all", 130, 24)
  toggle:SetPoint("TOPRIGHT", -BODY_PAD, -(BODY_PAD - 8))
  toggle:SetScript("OnClick", function()
    SF.UpgradesTabSetShowAll(not state.showAll)
  end)
  host.toggle = toggle

  -- The column-label line: VERDICT / ITEM AND REASON / CHANGE, at 9.5px
  -- uppercase. Uppercase IS the client's substitute for letter-spacing (a
  -- FontString has none); the labels sit on the same three columns as the rows,
  -- so a column cannot drift from its heading.
  local labels = CreateFrame("Frame", "TouchstoneUpgradesColumns", host)
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
  host.colChange = columnLabel("CHANGE",
    ROW_W - ROW_INSET * 2 - CHANGE_W, CHANGE_W, "RIGHT")
  host.columns = labels

  -- The viewport. A plain frame with a wheel handler: no UIPanelScrollFrameTemplate,
  -- no second named scroll global, no new art. Rows live in a child frame that is
  -- sized once and re-positioned by the wheel handler.
  local viewport = CreateFrame("Frame", "TouchstoneUpgradesViewport", host)
  viewport:SetPoint("TOPLEFT", labels, "BOTTOMLEFT", 0, -6)
  viewport:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -BODY_PAD, BODY_PAD)
  viewport:EnableMouseWheel(true)
  -- A row is admitted to a page only if it fits, but one row taller than the
  -- whole viewport is still admitted (SF.PageRows) — clip so that case cannot
  -- paint over the panel. Guarded: not every client exposes the call.
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
    local shown = #state.rendered
    -- One row per wheel step, all the way to the last row: the page is whatever
    -- fits, so "rows minus a page" is no longer a number that can be known here.
    local maxOffset = math.max(0, shown - 1)
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

  local maxOffset = math.max(0, n - 1)
  if state.offset > maxOffset then state.offset = maxOffset end

  -- Card t_4e5ad8a4: the row model. Every admitted row is BOUND and MEASURED
  -- first (its height is its own text), then the page is the run of rows that
  -- fits the viewport, and each row is placed at the previous row's BOTTOM.
  -- Upgrades and Log run the same two helpers (SF.PageRows / SF.StackRow), so
  -- the two lists cannot drift apart.
  state.layout = function()
    for i, row in ipairs(state.pool) do
      local r = state.rendered[i]
      if r then
        row.__link = r.link
        -- The change column: what this verdict would change (the advisor's own
        -- slot word — the same word its tooltip uses), dim and right-aligned.
        row.change:SetText(r.slotWord or "")

        -- The name is the anchor: one line, the ledger's text colour (PART B).
        -- The verdict, not the item's rarity, carries the colour.
        row.itemName:SetText(r.name)
        local nr, ng, nb, na = ledgerColor("ledgerText", C.text)
        row.itemName:SetTextColor(nr, ng, nb, na)

        -- The reason: its OWN line under the name, muted — secondary, but
        -- readable; never dimmed into the background and never beside the name.
        row.reason:SetText(r.reason)
        local rr, rg, rb, ra = ledgerColor("ledgerMuted", C.textMuted)
        row.reason:SetTextColor(rr, rg, rb, ra)

        -- The verdict: word and marker in ONE colour, from ONE read. The WORD is
        -- the row's (card t_c8970547): an arbitrated pair reads the model's word
        -- here exactly as it does in the tooltip.
        local vr, vg, vb, va = verdictColor(r.verdict)
        row.verdictWord:SetText(verdictWord(r))
        row.verdictWord:SetTextColor(vr, vg, vb, va)
        if r.verdict == "UPGRADE" then
          row.mark:SetTexture(SF.AssetPath("marker.tga"))
          row.mark:SetVertexColor(vr, vg, vb, 1)
          row.mark:Show()
        elseif r.verdict == tradeOffWord() then
          row.mark:SetTexture(nil)
          row.mark:SetColorTexture(vr, vg, vb, 0.95)
          row.mark:Show()
        else
          -- No glyph for a refusal: the bag grammar has no mark for one, and the
          -- verdict word alone is the statement.
          row.mark:Hide()
        end

        row:SetHeight(rowHeight(row))
      else
        row.__link = nil
      end
    end

    local heights = {}
    for i = 1, #state.rendered do
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
    -- The rows end where the page ends: the parent is exactly as tall as what it
    -- holds, so a grown row can never be pushed outside the panel.
    host.rowParent:SetHeight(math.max(y, 1))
    state.shown = count
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
  local admitted = #state.rendered
  local page = state.shown or 0
  -- The section head reads in the ledger's own text colour. It is deliberately
  -- NOT SF.Accent(): that wraps the word in the body's cyan, and the ledger is
  -- one dark language in which only the verdict carries a colour.
  host.title:SetText("Upgrades")
  if total == 0 then
    host.count:SetText("0 judged · 0 worth taking")
    host.empty:Show()
    host.viewport:Hide()
  else
    host.empty:Hide()
    host.viewport:Show()
    -- The section head's second half, in the ledger's own words: how many rows
    -- the advisor judged and how many are worth taking. Both are COUNTED from
    -- the list on this render — never carried over from the last one.
    local worth = 0
    for _, r in ipairs(state.rows) do
      if r.verdict == "UPGRADE" then worth = worth + 1 end
    end
    local more = ""
    if admitted > page and page > 0 then
      more = " · rows " .. tostring(state.offset + 1) .. "-"
        .. tostring(math.min(state.offset + page, admitted))
    end
    host.count:SetText(tostring(total) .. " judged · " .. tostring(worth)
      .. " worth taking" .. more)
  end
end

local function release()
  -- Nothing session-scoped is held: the host and the row pool outlive a hide, and
  -- the tooltip is the client's own. The rows keep no state that must be dropped.
end

SF.RegisterTab("upgrades", render, release)
