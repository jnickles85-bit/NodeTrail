local addonName, pkg = ...

-- MightiePack bug report form (t_ed1e009e).
--
-- HARD CONSTRAINT: WoW's Lua has no HTTP API, so this addon CANNOT post
-- to Discord. The report is assembled in-game and handed to the player
-- as selectable text: "Copy report" fills an edit box, SetFocus() +
-- HighlightText() select all of it, and the player presses Ctrl+C and
-- pastes it into the Discord channel. No UI text here may imply an
-- automatic upload — the footer says the opposite, on purpose.
--
-- Shape:
-- * Nothing happens at file load: no frame, no event registration, no
--   API call. All construction is deferred into pkg.OpenBugReport, and
--   the UI is built once (lazily) the first time it is asked for.
-- * No new SavedVariables: the description draft lives in this file's
--   upvalues (session only; a reload drops it).
-- * pkg.BuildBugReportHeader / pkg.BuildBugReport are pure string
--   builders (guarded against missing APIs — the same pattern /mpack
--   status uses), so they are testable without any UI at all.
-- * The NodeTrail diagnostics are NOT re-implemented here: we call
--   the same two builders /nt ttdiag uses (pkg.NodeTrail.Tooltip:Diag
--   and pkg.NodeTrail.Recipes:Diag) and capture the lines each
--   prints. If either is absent or errors, the header says so instead
--   of guessing. Other modules expose either a Diag function or a
--   _diag table; if a module has neither, the header honestly reads
--   "none".

pkg.bugReport = pkg.bugReport or {
  channelName = "#mightiepack-bugs",
  -- The channel exists (Mythic Traveler's Community, 2026-11-06); friends are
  -- already members, so this is a channel link, not an invite. Empty/nil
  -- prints the channel name only — never print a placeholder URL.
  channelUrl = "https://discord.com/channels/825795542390145024/1568478603170156694",
}

local frame = nil
local parts = {}
local state = {
  selected = nil,    -- module the report is about (picker selection)
  openedBy = nil,    -- module that opened the form
  requestedRaw = nil,-- what /mpack bug was given, if anything
  draft = nil,       -- description draft (session only)
}

local function channelInfo()
  local ch = pkg.bugReport or {}
  local name = (type(ch.channelName) == "string" and ch.channelName ~= "") and ch.channelName or "#mightiepack-bugs"
  local url = (type(ch.channelUrl) == "string" and ch.channelUrl ~= "") and ch.channelUrl or nil
  return name, url
end

-- Call the given diagnostic function and capture the lines it prints
-- to DEFAULT_CHAT_FRAME. This is how we reuse a module's existing
-- string builders (the /nt ttdiag output is built inside
-- Tooltip:Diag, not here) without duplicating their logic.
local function captureDiag(fn, selfref)
  local out = {}
  local cf = DEFAULT_CHAT_FRAME
  local orig = (type(cf) == "table") and cf.AddMessage or nil
  local can = (type(orig) == "function")
  if can then
    cf.AddMessage = function(_, line)
      out[#out + 1] = tostring(line)
    end
  end
  local ok, err = pcall(fn, selfref)
  if can then
    cf.AddMessage = orig
  end
  if not ok then
    return nil, tostring(err)
  end
  return out
end

local function nodeTrailDiagLines()
  local ns = pkg.NodeTrail
  if type(ns) ~= "table" then
    return { "none (NodeTrail module not loaded — no diagnostics available)" }
  end
  local all = {}
  -- The real /nt ttdiag is two halfs, both called here exactly as
  -- NodeTrail/Core.lua calls them (pcall'd), never re-implemented:
  local T = ns.Tooltip
  if type(T) == "table" and type(T.Diag) == "function" then
    local lines, err = captureDiag(T.Diag, T)
    if lines then
      for _, l in ipairs(lines) do
        all[#all + 1] = l:match("^NodeTrail ttdiag:%s*(.*)$") or l
      end
    else
      all[#all + 1] = "tooltip diagnostics unavailable (builder errored: " .. err .. ")"
    end
  else
    all[#all + 1] = "tooltip diagnostics unavailable (tooltip module not loaded)"
  end
  local R = ns.Recipes
  if type(R) == "table" and type(R.Diag) == "function" then
    local lines, err = captureDiag(R.Diag, R)
    if lines then
      for _, l in ipairs(lines) do
        all[#all + 1] = l:match("^NodeTrail recipes:%s*(.*)$") or l
      end
    else
      all[#all + 1] = "recipe diagnostics unavailable (builder errored: " .. err .. ")"
    end
  end
  -- t_5507a0ba: the skinning probe is NodeTrail's sub-feature now, so its
  -- state travels with the NodeTrail report. There is no "Skinning" module
  -- to select in the picker any more, and without this line the probe would
  -- be the only NodeTrail feature with no diagnostics in a report.
  local sk = pkg.Skinning
  if type(sk) == "table" then
    local skinOn = false
    if type(pkg.NodeTrail) == "table" and type(pkg.NodeTrail.IsSkinningEnabled) == "function" then
      local okS, s = pcall(pkg.NodeTrail.IsSkinningEnabled)
      skinOn = okS and s == true
    end
    local line = "skinning (NodeTrailDB.skinning.enabled): " .. (skinOn and "on" or "off")
    local P = sk.Probe
    if type(P) == "table" then
      line = line .. ", probe " .. (P.enabled and "armed" or "not started")
        .. ", capture " .. (P.capturing and "on" or "off")
        .. ", steps " .. tostring(#(P.steps or {}))
    end
    if sk._error then
      line = line .. ", error: " .. tostring(sk._error):gsub("[%c]", " ")
    end
    all[#all + 1] = line
  end
  if #all == 0 then
    return { "none" }
  end
  return all
end

local function moduleDiagLines(name)
  if name == "NodeTrail" then
    return nodeTrailDiagLines()
  end
  local st = pkg[name]
  if type(st) == "table" then
    if type(st.Diag) == "function" then
      local lines, err = captureDiag(st.Diag, st)
      if not lines then
        return { "unavailable (the module diagnostic builder errored: " .. err .. ")" }
      end
      if #lines == 0 then
        return { "none" }
      end
      return lines
    end
    if type(st._diag) == "table" then
      local pairs_ = {}
      for k, v in pairs(st._diag) do
        if type(k) == "string" and (type(v) == "string" or type(v) == "number" or type(v) == "boolean") then
          pairs_[#pairs_ + 1] = k .. " = " .. tostring(v):gsub("[%c]", " ")
        end
      end
      if #pairs_ == 0 then
        return { "none" }
      end
      return pairs_
    end
  end
  return { "none" }
end

local function defaultModule()
  if pkg.modules and pkg.modules.NodeTrail then
    return "NodeTrail"
  end
  local first = pkg.moduleOrder and pkg.moduleOrder[1]
  if first then
    return first
  end
  return "NodeTrail"
end

local function findModule(arg)
  if type(arg) ~= "string" or not arg:match("%S") then
    return nil
  end
  local wanted = arg:lower()
  for _, n in ipairs(pkg.moduleOrder or {}) do
    if n:lower() == wanted then
      return n
    end
  end
  return nil
end

-- Build the auto-filled header. `selectedName` is the module the
-- report is about. Every API is guarded the way /mpack status guards
-- them: missing function AND nil/empty return both become "unknown";
-- this must never error.
function pkg.BuildBugReportHeader(selectedName)
  selectedName = selectedName or state.selected or defaultModule()
  local lines = {}
  local function add(l) lines[#lines + 1] = l end

  local ts = "unknown"
  if type(date) == "function" then
    local ok, d = pcall(date, "%Y-%m-%d %H:%M:%S")
    if ok and type(d) == "string" and d ~= "" then
      ts = d
    end
  end
  add("MightiePack bug report — " .. ts)

  -- t_5507a0ba: same provider chain as /mpack status (pkg.GetAddOnMeta:
  -- C_AddOns.GetAddOnMetadata first, then the legacy global). This client
  -- has no global GetAddOnMetadata, so reading only the global here would
  -- have filled every report with "version unknown".
  local version, iface
  if type(pkg.GetAddOnMeta) == "function" then
    local okV, v = pcall(pkg.GetAddOnMeta, addonName, "Version")
    if okV and type(v) == "string" and v ~= "" then
      version = v
    end
    local okI, i = pcall(pkg.GetAddOnMeta, addonName, "Interface")
    if okI and type(i) == "string" and i ~= "" then
      iface = i
    end
  end
  add("Addon: version " .. (version or "unknown") .. ", interface " .. (iface or "unknown"))

  local build, full = "unknown", "unknown"
  if type(GetBuildInfo) == "function" then
    local ok, major, minor, patch, buildNum = pcall(GetBuildInfo)
    if ok then
      if type(buildNum) == "string" and buildNum ~= "" then
        build = buildNum
      end
      if type(major) == "string" and type(minor) == "string"
        and type(patch) == "string" and build ~= "unknown" then
        full = major .. "." .. minor .. "." .. patch .. "." .. build
      end
    end
  end
  add("Client: build " .. build .. ", version " .. full)

  local locale = "unknown"
  if type(GetLocale) == "function" then
    local ok, l = pcall(GetLocale)
    if ok and type(l) == "string" and l ~= "" then
      locale = l
    end
  end
  add("Locale: " .. locale)

  local charName, realm, klass = "unknown", "unknown", "unknown"
  if type(GetUnitName) == "function" then
    local ok, n = pcall(GetUnitName, "player")
    if ok and type(n) == "string" and n ~= "" then
      charName = n
    end
  end
  if type(GetUnitGUID) == "function" and type(GetPlayerInfoByGUID) == "function" then
    local ok, guid = pcall(GetUnitGUID, "player")
    if ok and type(guid) == "string" and guid ~= "" then
      local ok2, n2, r2, c2 = pcall(GetPlayerInfoByGUID, guid)
      if ok2 then
        if type(n2) == "string" and n2 ~= "" and charName == "unknown" then
          charName = n2
        end
        if type(r2) == "string" and r2 ~= "" then
          realm = r2
        end
        if type(c2) == "string" and c2 ~= "" then
          klass = c2
        end
      end
    end
  end
  if klass == "unknown" and type(UnitClass) == "function" then
    local ok, _, c = pcall(UnitClass, "player")
    if ok and type(c) == "string" and c ~= "" then
      klass = c
    end
  end
  add("Character: " .. charName .. ", realm " .. realm .. ", " .. klass)

  local zone, subzone = "unknown", "unknown"
  if type(GetZone) == "function" then
    local ok, z = pcall(GetZone)
    if ok and type(z) == "string" and z ~= "" then
      zone = z
    end
  end
  if type(GetSubzone) == "function" then
    local ok, s = pcall(GetSubzone)
    if ok and type(s) == "string" and s ~= "" then
      subzone = s
    end
  end
  add("Zone: " .. zone)
  add("Subzone: " .. subzone)

  local gm2 = "unknown"
  if type(IsAddOnLoaded) == "function" then
    local ok, loaded = pcall(IsAddOnLoaded, "GatherMate2")
    if ok == true then
      gm2 = (loaded and true or false) and "loaded" or "not loaded"
    end
  end
  add("GatherMate2: " .. gm2)

  add("Reported for: " .. tostring(selectedName))
  add("Opened by: " .. tostring(state.openedBy or selectedName))
  if state.requestedRaw then
    if not findModule(state.requestedRaw) then
      add("Note: \"" .. state.requestedRaw .. "\" is not a registered module — the report defaults to " .. defaultModule())
    end
  end

  add("Modules:")
  for _, mname in ipairs(pkg.moduleOrder or {}) do
    local def = pkg.modules and pkg.modules[mname]
    if def then
      local stateWord
      if type(pkg.IsModuleEnabled) == "function" then
        stateWord = pkg.IsModuleEnabled(mname) and "on" or "off"
      else
        stateWord = "unknown"
      end
      local line = "  " .. (def.title or mname) .. ": " .. stateWord
      if def.stub then
        line = line .. " (coming soon)"
      end
      if def.loaded then
        line = line .. " (loaded)"
      end
      if mname == state.openedBy then
        line = line .. " (opened this form)"
      end
      add(line)
    end
  end

  local diagLines = moduleDiagLines(selectedName)
  add(tostring(selectedName) .. " diagnostics:")
  for _, l in ipairs(diagLines) do
    add("  " .. l)
  end

  return table.concat(lines, "\n")
end

-- Build the full report text (header + description + the paste
-- instruction). Pure string work; usable without the UI.
function pkg.BuildBugReport(selectedName, description)
  selectedName = selectedName or state.selected or defaultModule()
  local channel, url = channelInfo()
  local desc = ""
  if type(description) == "string" then
    desc = description:match("^%s*(.-)%s*$") or ""
  end
  local descText = desc ~= "" and desc or "(the tester left the description empty)"
  local urlPart = url and (" (" .. url .. ")") or ""
  return pkg.BuildBugReportHeader(selectedName)
    .. "\n\nWhat happened:\n" .. descText
    .. "\n\nPaste this into " .. channel .. urlPart
    .. " on the MightiePack Discord. This addon cannot send the report itself — copy it and paste it yourself."
end

local function applySelection(name)
  state.selected = name
  if parts.headerText then
    local ok, h = pcall(pkg.BuildBugReportHeader, name)
    if ok and type(h) == "string" then
      parts.headerText:SetText(h)
    end
  end
end

local function doCopy()
  local sel = state.selected or defaultModule()
  local desc = ""
  if parts.desc and type(parts.desc.GetText) == "function" then
    local ok, t = pcall(parts.desc.GetText, parts.desc)
    if ok and type(t) == "string" then
      desc = t
    end
  end
  state.draft = desc
  local text = pkg.BuildBugReport(sel, desc)
  if parts.output and type(parts.output.SetText) == "function" then
    parts.output:SetText(text)
  end
  local out = parts.output
  local canFocus = out ~= nil and type(out.SetFocus) == "function"
  local canHL = out ~= nil and type(out.HighlightText) == "function"
  local focused, hl = false, false
  if canFocus then
    focused = pcall(out.SetFocus, out)
  end
  if canHL then
    hl = pcall(out.HighlightText, out)
  end
  local channel = (pkg.bugReport or {}).channelName or "#mightiepack-bugs"
  if parts.status and type(parts.status.SetText) == "function" then
    if focused and hl then
      parts.status:SetText(
        "The report is in the output box with its text selected — press Ctrl+C to copy it, then paste it into "
        .. channel .. " on the MightiePack Discord.")
    else
      parts.status:SetText(
        "The report is in the output box. Automatic selection is unavailable on this client — click into the box, "
        .. "select the text, then press Ctrl+C to copy it, and paste it into " .. channel .. " on the MightiePack Discord.")
    end
  end
  return text
end

-- Build the form once. Plain frames + OnClick handlers only: no events
-- are registered and nothing is created until this is called.
local function makeUI()
  if frame then
    return
  end
  frame = CreateFrame("Frame", "MightiePackBugReportFrame")
  frame:SetSize(480, 620)
  frame:SetPoint("CENTER")

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
  title:SetText("Report a bug — MightiePack")

  local y = -44
  local function label(text)
    local l = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
    l:SetText(text)
    y = y - 20
    return l
  end

  label("This addon cannot send the report — the client has no way to post to Discord. "
    .. "Fill in what happened, press Copy report, press Ctrl+C, paste into the Discord channel.")
  -- the note above takes more than one line at this font
  y = y - 24

  local moduleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  moduleLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
  moduleLabel:SetText("Module:")
  local picker = CreateFrame("Frame", nil, frame, "Dropdown")
  picker:SetPoint("LEFT", moduleLabel, "RIGHT", 8, 0)
  if type(picker.SetWidth) == "function" then
    picker:SetWidth(200)
  end
  local names = {}
  for _, n in ipairs(pkg.moduleOrder or {}) do
    names[#names + 1] = n
  end
  if #names == 0 then
    names = { "NodeTrail" }
  end
  local indexFor = {}
  for i, n in ipairs(names) do
    indexFor[n] = i
  end
  local function selectByName(n)
    local idx = indexFor[n]
    if idx and type(picker.SetValue) == "function" then
      picker:SetValue(idx)
    end
    applySelection(n)
  end
  for _, n in ipairs(names) do
    local def = pkg.modules and pkg.modules[n]
    local text = (def and def.title) or n
    if def and def.stub then
      text = text .. " (coming soon)"
    end
    picker:AddItem({ text = text, func = function() selectByName(n) end })
  end
  parts.picker = picker
  parts.names = names
  y = y - 28

  label("Auto-filled report header (read-only):")
  local headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  headerText:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
  headerText:SetWidth(448)
  headerText:SetText("")
  parts.headerText = headerText
  y = y - 288 -- the header is long; leave room for its lines

  label("What happened (the only part you write):")
  local descBox = CreateFrame("EditBox", "MightiePackBugReportDesc", frame)
  descBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
  descBox:SetSize(448, 80)
  descBox:SetText("")
  parts.desc = descBox
  y = y - 96

  label("Report (press Copy report to fill this box):")
  -- A classic EditBox: long text scrolls inside it, and
  -- SetFocus + HighlightText selects the whole buffer, which is the
  -- copy mechanism this client supports (Ctrl+C). If either method is
  -- missing, doCopy() falls back to telling the player to select
  -- manually instead of claiming it did.
  local outBox = CreateFrame("EditBox", "MightiePackBugReportOut", frame)
  outBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
  outBox:SetSize(448, 120)
  outBox:SetText("")
  parts.output = outBox
  y = y - 132

  local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
  status:SetWidth(448)
  status:SetText("Click Copy report to fill the box above. There is no upload — you paste it into Discord.")
  parts.status = status
  y = y - 28

  local copyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  copyBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, y)
  copyBtn:SetSize(120, 26)
  copyBtn:SetText("Copy report")
  copyBtn:SetScript("OnClick", function()
    doCopy()
  end)
  copyBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Fill the report box with the full report and select its text — then press Ctrl+C and paste it into Discord")
    GameTooltip:Show()
  end)
  copyBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  closeBtn:SetPoint("LEFT", copyBtn, "RIGHT", 8, 0)
  closeBtn:SetSize(96, 26)
  closeBtn:SetText("Close")
  closeBtn:SetScript("OnClick", function()
    frame:Hide()
  end)
  parts.close = closeBtn
end

-- Open (or focus) the form. `moduleArg` is optional: it preselects
-- that module (matched case-insensitively against the registry); nil
-- or an unregistered name falls back to the default module (NodeTrail,
-- or the first registered one).
function pkg.OpenBugReport(moduleArg)
  makeUI()
  local sel = findModule(moduleArg) or defaultModule()
  state.selected = sel
  state.openedBy = sel
  if type(moduleArg) == "string" and moduleArg:match("%S") then
    state.requestedRaw = moduleArg
  else
    state.requestedRaw = nil
  end
  local picker = parts.picker
  local idx = nil
  for i, n in ipairs(parts.names) do
    if n == sel then
      idx = i
      break
    end
  end
  -- A module registered after the first open (a second module landing
  -- late, or a test registering one) is not in the picker yet: add the
  -- item instead of silently ignoring the request.
  if not idx and picker and type(picker.AddItem) == "function" then
    local def = pkg.modules and pkg.modules[sel]
    local text = (def and def.title) or sel
    if def and def.stub then
      text = text .. " (coming soon)"
    end
    picker:AddItem({ text = text, func = function() applySelection(sel) end })
    parts.names[#parts.names + 1] = sel
    idx = #parts.names
  end
  if picker and idx and type(picker.SetValue) == "function" then
    picker:SetValue(idx)
  end
  applySelection(sel)
  -- The description box keeps its text across Close (the client does
  -- not clear EditBoxes on Hide) — keep what the player typed; only
  -- restore the last copied draft when the box is empty (fresh open).
  local cur = ""
  if parts.desc and type(parts.desc.GetText) == "function" then
    local ok, t = pcall(parts.desc.GetText, parts.desc)
    if ok and type(t) == "string" then
      cur = t
    end
  end
  if cur == "" and type(state.draft) == "string" and state.draft ~= "" then
    if parts.desc and type(parts.desc.SetText) == "function" then
      parts.desc:SetText(state.draft)
    end
  end
  frame:Show()
  return sel
end
