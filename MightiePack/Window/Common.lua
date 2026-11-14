-- MightiePack — the two widgets every browse tab is built from (card
-- t_a5de2f16).
--
-- The Herbs and the Skinning tab are the same shape: a column of things on the
-- left, the picked thing's rows on the right. That shape lives here once, so
-- the tabs carry data and wording only.
--
-- The right-hand rows are TooltipPanel's rows: CreateRowIn is the same
-- two-column row builder the hover panel draws with (born with a font object,
-- right column right-justified, the tooltip's font adopted through _ApplyFont).
-- A tab therefore cannot drift from the tooltip's look, and there is one row
-- renderer in the pack instead of two.

local _, pkg = ...

local W = pkg.Window
local C = {}
W.UI = C

local TP = type(pkg.NodeTrail) == "table" and pkg.NodeTrail.TooltipPanel or nil

local function call(obj, name, ...)
  local f = type(obj) == "table" and obj[name]
  if type(f) ~= "function" then return false end
  local ok, r = pcall(f, obj, ...)
  if not ok then return false end
  return true, r
end

local function set(obj, name, ...)
  local f = type(obj) == "table" and obj[name]
  if type(f) ~= "function" then return false end
  return (pcall(f, obj, ...)) and true or false
end

local function num(obj, name)
  local ok, v = call(obj, name)
  if ok and type(v) == "number" then return v end
  return nil
end

function C.NewFrame(kind, name, parent, template)
  if type(CreateFrame) ~= "function" then return nil end
  if template ~= nil then
    local ok, f = pcall(CreateFrame, kind, name, parent, template)
    if ok and type(f) == "table" then return f end
  end
  local ok, f = pcall(CreateFrame, kind, name, parent)
  if ok and type(f) == "table" then return f end
  return nil
end

function C.Label(parent, template, text, size)
  if type(parent) ~= "table" or type(parent.CreateFontString) ~= "function" then
    return nil
  end
  local ok, fs = pcall(parent.CreateFontString, parent, nil, "OVERLAY", template)
  if not ok or type(fs) ~= "table" then return nil end
  set(fs, "SetText", text or "")
  if size then set(fs, "SetFont", nil, size) end
  return fs
end

--- A framed container with a title, used for both columns.
local function column(parent, title, x, width, height)
  local box = C.NewFrame("Frame", nil, parent, "BackdropTemplate") or C.NewFrame("Frame", nil, parent)
  if not box then return nil end
  set(box, "SetPoint", "TOPLEFT", parent, "TOPLEFT", x, 0)
  set(box, "SetSize", width, height)
  if type(box.SetBackdrop) == "function" then
    pcall(box.SetBackdrop, box, {
      bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    set(box, "SetBackdropColor", 0.05, 0.05, 0.06, 0.85)
    set(box, "SetBackdropBorderColor", 0.30, 0.27, 0.16, 0.9)
  end
  box.header = C.Label(box, "GameFontNormalSmall", title)
  if type(box.header) == "table" then
    set(box.header, "SetPoint", "TOPLEFT", box, "TOPLEFT", 6, -6)
    set(box.header, "SetTextColor", 0.92, 0.83, 0.55)
  end
  return box
end

-- ── The left column: a scrollable list of pickable rows ───────────────────
--- opts: { title, width, height, rowHeight, onPick(id) }
function C.List(parent, opts)
  opts = opts or {}
  local rowHeight = opts.rowHeight or 20
  local box = column(parent, opts.title or "", opts.x or 0, opts.width or 280, opts.height or 400)
  if not box then return nil end
  local o = { box = box, rowHeight = rowHeight, rows = {}, entries = {}, selected = nil }
  local scroll = C.NewFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
  if not scroll then scroll = C.NewFrame("ScrollFrame", nil, box) end
  o.scroll = scroll
  set(scroll, "SetPoint", "TOPLEFT", box, "TOPLEFT", 4, -22)
  -- Leave room for the template's scrollbar when the client gave us one.
  local insetRight = (select(2, call(scroll, "GetChildren")) ~= nil) and 24 or 4
  set(scroll, "SetPoint", "BOTTOMRIGHT", box, "BOTTOMRIGHT", -insetRight, 4)
  local content = C.NewFrame("Frame", nil, scroll)
  o.content = content
  set(content, "SetSize", (opts.width or 280) - insetRight - 8, rowHeight)
  set(scroll, "SetScrollChild", content)
  set(scroll, "EnableMouseWheel", true)
  if type(scroll.SetScript) == "function" then
    pcall(scroll.SetScript, scroll, "OnMouseWheel", function()
      local cur = num(scroll, "GetVerticalScroll") or 0
      set(scroll, "SetVerticalScroll", math.max(0, cur - rowHeight * 3))
    end)
  end

  local function paint()
    for i, row in ipairs(o.rows) do
      local e = o.entries[i]
      if type(row.label) == "table" then
        set(row.label, "SetText", e and (e.text or "") or "")
        if e and e.id == o.selected then
          set(row.label, "SetTextColor", 0.98, 0.88, 0.50)
        else
          set(row.label, "SetTextColor", 0.85, 0.85, 0.85)
        end
      end
      if e then set(row.frame, "Show") else set(row.frame, "Hide") end
    end
  end

  local function rowAt(i)
    local row = o.rows[i]
    if type(row) == "table" then return row end
    local btn = C.NewFrame("Button", nil, content) or C.NewFrame("Frame", nil, content)
    if not btn then return nil end
    set(btn, "SetSize", (opts.width or 280) - insetRight - 8, rowHeight)
    set(btn, "SetPoint", "TOPLEFT", content, "TOPLEFT", 0, -((i - 1) * rowHeight))
    set(btn, "EnableMouse", true)
    local label = C.Label(btn, "GameFontHighlightSmall")
    if type(label) == "table" then
      set(label, "SetPoint", "LEFT", btn, "LEFT", 4, 0)
      set(label, "SetPoint", "RIGHT", btn, "RIGHT", -4, 0)
      set(label, "SetJustifyH", "LEFT")
    end
    btn.label = label
    if type(btn.SetScript) == "function" then
      pcall(btn.SetScript, btn, "OnClick", function()
        local e = o.entries[i]
        if not e then return end
        o.selected = e.id
        paint()
        if type(opts.onPick) == "function" then pcall(opts.onPick, e.id) end
      end)
    end
    row = { frame = btn, label = label }
    o.rows[i] = row
    return row
  end

  --- Replace the list. Entries are { id = <any>, text = <string> }.
  function o.SetEntries(entries)
    o.entries = type(entries) == "table" and entries or {}
    set(content, "SetHeight", math.max(rowHeight, #o.entries * rowHeight))
    for i = 1, #o.entries do rowAt(i) end
    if o.selected ~= nil then
      local found = false
      for _, e in ipairs(o.entries) do
        if e.id == o.selected then found = true end
      end
      if not found then o.selected = nil end
    end
    paint()
  end

  --- Pick a row by id (used to keep a selection across a refresh).
  function o.Select(id)
    o.selected = id
    paint()
    if type(opts.onPick) == "function" then pcall(opts.onPick, id) end
  end

  function o.Count()
    return #o.entries
  end

  return o
end

-- ── The right column: a title, a sub-line, then TooltipPanel rows ─────────
--- opts: { title, width, height }
function C.Detail(parent, opts)
  opts = opts or {}
  local box = column(parent, opts.title or "", opts.x or 0, opts.width or 620, opts.height or 400)
  if not box then return nil end
  local o = { box = box, rows = {} }
  o.title = C.Label(box, "GameFontNormalLarge")
  if type(o.title) == "table" then
    set(o.title, "SetPoint", "TOPLEFT", box, "TOPLEFT", 8, -26)
    set(o.title, "SetTextColor", 0.95, 0.87, 0.55)
  end
  o.sub = C.Label(box, "GameFontHighlightSmall")
  if type(o.sub) == "table" then
    set(o.sub, "SetPoint", "TOPLEFT", box, "TOPLEFT", 8, -46)
    set(o.sub, "SetPoint", "RIGHT", box, "RIGHT", -8, 0)
    set(o.sub, "SetJustifyH", "LEFT")
    set(o.sub, "SetTextColor", 0.62, 0.62, 0.62)
  end
  o.list = nil
  o.firstRowY = -66

  local function rowAt(i)
    local row = o.rows[i]
    if type(row) == "table" then return row end
    local maker = TP and TP.CreateRowIn
    if type(maker) == "function" then
      local ok, made = pcall(maker, TP, box)
      if ok and type(made) == "table" then
        row = made
      end
    end
    if type(row) ~= "table" then
      -- No TooltipPanel on this client: the same two font strings, drawn here,
      -- so a tab is never blank.
      row = { left = C.Label(box, "GameFontHighlightSmall"), right = C.Label(box, "GameFontHighlightSmall") }
      if type(row.right) == "table" then set(row.right, "SetJustifyH", "RIGHT") end
    end
    local y = o.firstRowY - (i - 1) * 16
    if type(row.left) == "table" then
      set(row.left, "SetPoint", "TOPLEFT", box, "TOPLEFT", 8, y)
      set(row.left, "SetJustifyH", "LEFT")
    end
    if type(row.right) == "table" then
      set(row.right, "SetPoint", "TOPRIGHT", box, "TOPRIGHT", -8, y)
    end
    o.rows[i] = row
    return row
  end

  --- Replace the body. `lines` are { left = , right = } or { name = } rows,
  --- exactly the shapes Tooltip.BuildLines and SkinHints.Rows already return.
  function o.SetLines(title, sub, lines)
    if type(o.title) == "table" then set(o.title, "SetText", title or "") end
    if type(o.sub) == "table" then set(o.sub, "SetText", sub or "") end
    lines = type(lines) == "table" and lines or {}
    for i = 1, #lines do
      local line = lines[i]
      local row = rowAt(i)
      if type(row) == "table" then
        local left = line.left
        if left == nil and line.name ~= nil then left = tostring(line.name) end
        if type(row.left) == "table" then
          set(row.left, "SetText", left ~= nil and tostring(left) or "")
        end
        if type(row.right) == "table" then
          set(row.right, "SetText", line.right ~= nil and tostring(line.right) or "")
        end
        set(row.left, "Show")
        if type(row.right) == "table" then set(row.right, "Show") end
      end
    end
    for i = #lines + 1, #o.rows do
      local row = o.rows[i]
      if type(row) == "table" then
        set(row.left, "Hide")
        if type(row.right) == "table" then set(row.right, "Hide") end
      end
    end
  end

  return o
end

--- A caption line under a detail column (used by the Skinning tab's
--- accounting block, which is prose rather than rows).
function C.Caption(parent, text)
  local fs = C.Label(parent, "GameFontHighlightSmall", text)
  return fs
end
