-- MightiePack — the Skinning tab (card t_a5de2f16, review layout item 2).
--
-- A UI over data the probe already records. Nothing here measures anything:
--
--   * the creatures and their counts — NodeTrailDB.skinning.chars[<char>]
--     .creatures[<npc id>], the per-creature totals Modules/Skinning/Record.lua
--     has been keeping since schema 2 (kills, corpse windows, skins);
--   * what a beast yields — SkinHints.Rows(cid, name, agg), the same rows the
--     beast tooltip renders, through TooltipPanel's row helper;
--   * the accounting — Record:AccountingLine(), which reconciles every kill and
--     every cast (its "lost kills / windows / casts" clause IS the unattributed
--     count: a window that produced neither a corpse nor a skin record).
--
-- The compact dump the pack has always offered stays exactly where it was —
-- pkg.ShowSkinDiagCopy(), the same function `/mp skindiag copy` calls — behind
-- this tab's Copy button. The options panel's copy button moves here, and that
-- slash path keeps working unchanged.

local _, pkg = ...

local W = pkg.Window
local C = W and W.UI
local L = {}
if type(W) == "table" then W.SkinningTab = L end

local MAX_ROWS = 300

local function call(obj, name, ...)
  local f = type(obj) == "table" and obj[name]
  if type(f) ~= "function" then return false end
  local ok, r = pcall(f, obj, ...)
  if not ok then return false end
  return true, r
end

local function skinning()
  return type(pkg.Skinning) == "table" and pkg.Skinning or nil
end

--- The per-character store, read WITHOUT creating one. Opening a tab must not
--- write a bucket into a character that has never skinned anything (the same
--- rule SkinHints.Bucket follows for the tooltip). The recorder writes
--- straight into the character bucket, so reading it shows the live counts;
--- when the sub-option is off there is only the session buffer.
local function store()
  local sk = skinning()
  local R = sk and sk.Recorder
  if type(R) ~= "table" then return nil end
  local db = rawget(_G, "NodeTrailDB")
  local chars = type(db) == "table" and type(db.skinning) == "table" and db.skinning.chars
  local key = nil
  if type(R.CharKey) == "function" then
    local ok, k = pcall(R.CharKey, R)
    if ok and type(k) == "string" then key = k end
  end
  if type(chars) == "table" and key and type(chars[key]) == "table" then
    return chars[key]
  end
  if type(R.session) == "table" then return R.session end
  return nil
end

--- Creature display names. The totals row is keyed by NPC id and carries no
--- name, so the name comes from the corpse records the same store keeps (the
--- ring is capped at 100 entries, which is why the NAMES are read from it and
--- the COUNTS are not).
local function nameOf(s, cid)
  local R = skinning() and skinning().Recorder
  local recs = type(s) == "table" and type(s.records) == "table" and s.records or {}
  local order = type(s) == "table" and type(s.order) == "table" and s.order or {}
  for i = #order, 1, -1 do
    local rec = recs[order[i]]
    if type(rec) == "table" and type(R) == "table" and type(R.CreatureID) == "function" then
      local ok, rid = pcall(R.CreatureID, rec.guid)
      if ok and rid == cid then
        local okN, name = pcall(R.DisplayName, rec)
        if okN and type(name) == "string" and name ~= "" then return name end
      end
    end
  end
  return "creature " .. tostring(cid)
end

--- One entry per creature that has a totals row, busiest first.
function L.Entries()
  local s = store()
  if type(s) ~= "table" or type(s.creatures) ~= "table" then return {} end
  local out = {}
  for cid, row in pairs(s.creatures) do
    if type(cid) == "number" and type(row) == "table" then
      local skinned = tonumber(row.skinned) or 0
      local kills = tonumber(row.kills) or 0
      local wins = tonumber(row.skinWindows) or 0
      out[#out + 1] = {
        id = cid,
        text = nameOf(s, cid) .. "  ·  skinned " .. tostring(skinned)
          .. " / killed " .. tostring(kills),
        sortKey = skinned * 1000 + wins,
      }
    end
  end
  table.sort(out, function(a, b)
    if a.sortKey ~= b.sortKey then return a.sortKey > b.sortKey end
    return a.text < b.text
  end)
  if #out > MAX_ROWS then
    local cut = {}
    for i = 1, MAX_ROWS do cut[i] = out[i] end
    out = cut
  end
  return out
end

--- Right-hand column for one creature: the beast tooltip's own rows.
function L.Detail(cid)
  local n = type(pkg.NodeTrail) == "table" and pkg.NodeTrail or nil
  local H = n and n.SkinHints
  local s = store()
  local name = type(s) == "table" and nameOf(s, cid) or ("creature " .. tostring(cid))
  if type(H) ~= "table" or type(H.Rows) ~= "function" then
    return name, "skin hints module not loaded", {}
  end
  local ok, rows = pcall(H.Rows, cid, name, nil)
  if not ok or type(rows) ~= "table" then
    return name, "no observations here yet", {}
  end
  return name, "your own skins, by NPC id " .. tostring(cid), rows
end

local function accountingText()
  local sk = skinning()
  local R = sk and sk.Recorder
  local s = store()
  if type(R) ~= "table" or type(s) ~= "table" or type(R.AccountingLine) ~= "function" then
    return "accounting unavailable"
  end
  local ok, line = pcall(R.AccountingLine, R, s)
  if ok and type(line) == "string" then return line end
  return "accounting unavailable"
end

local function ensure(host)
  if type(L.widgets) == "table" then return L.widgets end
  if type(C) ~= "table" or type(host) ~= "table" then return nil end
  local height = 470
  local okH, h = call(host, "GetHeight")
  if okH and type(h) == "number" and h > 160 then height = h - 80 end
  local list = C.List(host, {
    title = "Beasts skinned", x = 0, width = 300, height = height,
    onPick = function(cid) L.Show(cid) end,
  })
  local detail = C.Detail(host, { title = "Detail", x = 308, width = 636, height = height })
  local accounting = C.Label(host, "GameFontHighlightSmall", "")
  if type(accounting) == "table" then
    pcall(accounting.SetPoint, accounting, "TOPLEFT", host, "TOPLEFT", 2, -(height + 10))
    pcall(accounting.SetTextColor, accounting, 0.62, 0.62, 0.62)
  end
  local copy = C.NewFrame("Button", nil, host, "UIPanelButtonTemplate")
  if not copy then copy = C.NewFrame("Button", nil, host) end
  if type(copy) == "table" then
    pcall(copy.SetSize, copy, 150, 22)
    pcall(copy.SetPoint, copy, "TOPLEFT", host, "TOPLEFT", 2, -(height + 30))
    if type(copy.SetText) == "function" then
      pcall(copy.SetText, copy, "Copy diagnostic")
    end
    -- The SAME function /mp skindiag copy calls. Moving the button must not
    -- fork the dump.
    pcall(copy.SetScript, copy, "OnClick", function()
      if type(pkg.ShowSkinDiagCopy) == "function" then pcall(pkg.ShowSkinDiagCopy) end
    end)
  end
  L.widgets = {
    list = list, detail = detail, accounting = accounting, copy = copy, height = height,
  }
  return L.widgets
end

function L.Show(cid)
  local w = ensure(W.hosts and W.hosts.skinning)
  if type(w) ~= "table" or type(w.detail) ~= "table" then return false end
  if cid == nil then cid = L.selected end
  if cid == nil then return false end
  L.selected = cid
  local title, sub, rows = L.Detail(cid)
  w.detail.SetLines(title, sub, rows)
  return true
end

function L.Render()
  local host = W.hosts and W.hosts.skinning
  if type(host) ~= "table" then return false end
  local w = ensure(host)
  if type(w) ~= "table" then return false end
  local n = type(pkg.NodeTrail) == "table" and pkg.NodeTrail or nil
  local enabled = type(n) == "table" and n.enabled
  if type(w.accounting) == "table" then
    pcall(w.accounting.SetText, w.accounting,
      enabled and accountingText() or W.MODULE_OFF_TEXT.skinning)
  end
  if not enabled then
    w.list.SetEntries({})
    w.detail.SetLines("Skinning", W.MODULE_OFF_TEXT.skinning, {})
    return false
  end
  local entries = L.Entries()
  w.list.SetEntries(entries)
  local pick = L.selected
  if pick == nil then pick = entries[1] and entries[1].id or nil end
  L.Show(pick)
  return true
end

if type(W) == "table" and type(W.OnSelect) == "function" then
  W.OnSelect("skinning", L.Render)
end
