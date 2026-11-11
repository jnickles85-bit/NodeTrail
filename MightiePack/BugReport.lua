local addonName, pkg = ...

-- In-game bug report and idea popups: a selectable EditBox the player
-- copies with Ctrl+C. WoW addons cannot write the clipboard and cannot
-- post to Discord; this file never pretends otherwise.
--
-- Permanent Discord invites for testers who are not yet in the server.
-- Leave nil until Mightie provides one that does not expire; the popup
-- hint then just names the channel.
pkg.BUG_DISCORD_INVITE = nil
pkg.IDEA_DISCORD_INVITE = nil

local IDEA_AREA_CHOICE = "NodeTrail / Touchstone / Skinning / General"
local IDEA_AREA_ALIASES = {
  nodetrail = "NodeTrail",
  nt = "NodeTrail",
  node = "NodeTrail",
  touchstone = "Touchstone",
  ts = "Touchstone",
  skinning = "Skinning",
  skin = "Skinning",
  general = "General",
  pack = "General",
  mightiepack = "General",
  umbrella = "General",
}

local function safeStr(v)
  if type(v) ~= "string" then return nil end
  if v == "" then return nil end
  return v
end

local function sanitize(text)
  if type(pkg.Sanitize) == "function" then
    local ok, s = pcall(pkg.Sanitize, text)
    if ok then return s end
  end
  return tostring(text or "")
end

local function addonVersion()
  if type(pkg.GetAddOnMeta) == "function" then
    local ok, v = pcall(pkg.GetAddOnMeta, addonName or "MightiePack", "Version")
    if ok and safeStr(v) then return v end
  end
  if type(C_AddOns) == "table" and type(C_AddOns.GetAddOnMetadata) == "function" then
    local ok, v = pcall(C_AddOns.GetAddOnMetadata, addonName or "MightiePack", "Version")
    if ok and safeStr(v) then
      if v:find("^@.*@$") then return "dev" end
      return v
    end
  end
  if type(GetAddOnMetadata) == "function" then
    local ok, v = pcall(GetAddOnMetadata, addonName or "MightiePack", "Version")
    if ok and safeStr(v) then
      if v:find("^@.*@$") then return "dev" end
      return v
    end
  end
  return "unknown"
end

-- GetBuildInfo: standard is (version, build, date, tocversion). The Forever
-- client has also been observed to return (major, minor, patch, build, ...).
local function clientBits()
  local version, build, interface = "unknown", "unknown", "unknown"
  if type(GetBuildInfo) == "function" then
    local ok, a, b, c, d = pcall(GetBuildInfo)
    if ok then
      if type(a) == "string" and a:find("%d+%.%d+") then
        version = a
        if b ~= nil and tostring(b) ~= "" then build = tostring(b) end
        if d ~= nil and tostring(d) ~= "" then interface = tostring(d) end
      elseif type(a) == "string" and type(b) == "string" and type(c) == "string"
        and a ~= "" and not a:find("%s") then
        version = a .. "." .. b .. "." .. c
        if d ~= nil and tostring(d) ~= "" then build = tostring(d) end
      else
        if safeStr(a) then version = a end
        if b ~= nil and tostring(b) ~= "" then build = tostring(b) end
        if d ~= nil and tostring(d) ~= "" then interface = tostring(d) end
      end
    end
  end
  if interface == "unknown" and type(pkg.GetAddOnMeta) == "function" then
    local ok, i = pcall(pkg.GetAddOnMeta, addonName or "MightiePack", "Interface")
    if ok and safeStr(i) then interface = i end
  end
  return version, build, interface
end

local function enabledModules()
  local names = {}
  if type(pkg.moduleOrder) == "table" and type(pkg.IsModuleEnabled) == "function" then
    for _, name in ipairs(pkg.moduleOrder) do
      local ok, on = pcall(pkg.IsModuleEnabled, name)
      if ok and on then
        local title = name
        local def = pkg.modules and pkg.modules[name]
        if type(def) == "table" and safeStr(def.title) then
          title = def.title
        end
        names[#names + 1] = title
      end
    end
  end
  if #names == 0 then return "none" end
  return table.concat(names, ", ")
end

-- Class and level only. Names and realms are never written here.
local function characterLine()
  local class = "unknown"
  if type(UnitClass) == "function" then
    local ok, a, b = pcall(UnitClass, "player")
    if ok then
      local loc, token = safeStr(a), safeStr(b)
      if loc and token then
        if loc == loc:upper() and token ~= token:upper() then
          class = token
        else
          class = loc
        end
      else
        class = loc or token or "unknown"
      end
    end
  end
  local level = "unknown"
  if type(UnitLevel) == "function" then
    local ok, lvl = pcall(UnitLevel, "player")
    if ok and type(lvl) == "number" then
      level = tostring(lvl)
    end
  end
  return class .. " " .. level
end

local function zoneLine()
  local zone = "unknown"
  if type(GetRealZoneText) == "function" then
    local ok, z = pcall(GetRealZoneText)
    if ok and safeStr(z) then zone = z end
  end
  local mapId
  if type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function" then
    local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
    if ok and (type(id) == "number" or (type(id) == "string" and id ~= "")) then
      mapId = tostring(id)
    end
  end
  if mapId then
    return zone .. " (" .. mapId .. ")"
  end
  return zone
end

local function firstLines(text, n)
  local out = {}
  for line in tostring(text or ""):gmatch("[^\r\n]+") do
    if not line:match("^stack traceback") then
      out[#out + 1] = line
      if #out >= n then break end
    end
  end
  return table.concat(out, "\n")
end

local function looksLikeOurError(text)
  return tostring(text or ""):find("MightiePack", 1, true) ~= nil
end

local function fromBugGrabber()
  if type(BugGrabber) ~= "table" then return nil end
  local db
  if type(BugGrabber.GetDB) == "function" then
    local ok, r = pcall(BugGrabber.GetDB, BugGrabber)
    if ok then db = r end
  end
  if type(db) ~= "table" and type(BugGrabber.errors) == "table" then
    db = BugGrabber.errors
  end
  if type(db) ~= "table" then return nil end
  for i = #db, 1, -1 do
    local e = db[i]
    local msg, stack = "", ""
    if type(e) == "table" then
      msg = tostring(e.message or e.error or e.err or "")
      stack = tostring(e.stack or e.stacktrace or "")
    elseif type(e) == "string" then
      msg = e
    end
    local combined = msg .. "\n" .. stack
    if looksLikeOurError(combined) then
      local body = firstLines(sanitize(msg), 8)
      local extra = firstLines(sanitize(stack), 6)
      if extra ~= "" then
        body = body .. "\n" .. extra
      end
      return body
    end
  end
  return nil
end

local function luaErrorText()
  local grabbed
  local ok, r = pcall(fromBugGrabber)
  if ok then grabbed = r end
  if safeStr(grabbed) then return grabbed end
  local captured
  if type(pkg.GetCapturedLuaError) == "function" then
    local okC, e = pcall(pkg.GetCapturedLuaError)
    if okC then captured = e end
  end
  if safeStr(captured) then return captured end
  return "none"
end

function pkg.CopyHint()
  local hint = "Press Ctrl+C to copy, then paste in #mightiepack-bugs on Discord"
  local invite = pkg.BUG_DISCORD_INVITE
  if type(invite) == "string" and invite ~= "" then
    hint = hint .. ": " .. invite
  end
  return hint
end

function pkg.IdeaCopyHint()
  local hint = "Press Ctrl+C to copy, then paste it into #mightiepack-ideas."
  local invite = pkg.IDEA_DISCORD_INVITE
  if type(invite) == "string" and invite ~= "" then
    hint = hint .. ": " .. invite
  end
  return hint
end

function pkg.BuildBugReport()
  local ok, text = pcall(function()
    local version = addonVersion()
    local ver, build, interface = clientBits()
    local err = luaErrorText()
    local errBlock
    if err == "none" then
      errBlock = "Lua error: none"
    else
      errBlock = "Lua error:\n" .. err
    end
    return table.concat({
      "MightiePack bug report",
      "Addon version: " .. version,
      "Client version: " .. ver .. " (build " .. build .. ", interface " .. interface .. ")",
      "Module(s): " .. enabledModules(),
      "Character: " .. characterLine(),
      "Zone/map: " .. zoneLine(),
      "Steps to reproduce:",
      "",
      "Expected:",
      "",
      "Actual:",
      "",
      errBlock,
      "Screenshot: (attach in Discord)",
    }, "\n")
  end)
  if ok and type(text) == "string" then
    return text
  end
  return "MightiePack bug report\nAddon version: unknown\n(report builder failed)\nSteps to reproduce:\n\nExpected:\n\nActual:\n\nLua error: none\nScreenshot: (attach in Discord)"
end

-- Map a /mp idea argument to a single area, or the choice list when
-- missing/unknown. Only the first token of the rest is considered
-- (e.g. `/mp idea nodetrail please` fills NodeTrail). Never echoes the
-- raw argument (it is player-typed).
function pkg.ParseIdeaArea(arg)
  local s = safeStr(arg)
  if not s then return IDEA_AREA_CHOICE end
  local token = s:match("^%s*(%S+)")
  if not token then return IDEA_AREA_CHOICE end
  token = token:lower()
  return IDEA_AREA_ALIASES[token] or IDEA_AREA_CHOICE
end

function pkg.BuildIdeaReport(areaArg)
  local ok, text = pcall(function()
    local version = addonVersion()
    local ver, build, interface = clientBits()
    local area = pkg.ParseIdeaArea(areaArg)
    return table.concat({
      "**MightiePack idea**",
      "Addon version: " .. version,
      "Client version: " .. ver .. " (build " .. build .. ", interface " .. interface .. ")",
      "Area: " .. area,
      "",
      "What would you like:",
      "",
      "Why / what problem it solves:",
      "",
      "Nice-to-have details:",
    }, "\n")
  end)
  if ok and type(text) == "string" then
    return text
  end
  return "**MightiePack idea**\nAddon version: unknown\n(report builder failed)\nArea: " .. IDEA_AREA_CHOICE .. "\n\nWhat would you like:\n\nWhy / what problem it solves:\n\nNice-to-have details:"
end

-- Shared, combat-safe copy popup (plain Frame + EditBox, no secure
-- templates or SetAttribute). Creation is idempotent per key. Escape
-- and OnHide clear focus so the EditBox cannot trap the keyboard.
local copyPopups = {}

local function ensureCopyPopup(key, opts)
  local p = copyPopups[key]
  if p and p.frame then
    return p
  end
  p = {}

  local parent = rawget(_G, "UIParent")
  local okF, created = pcall(CreateFrame, "Frame", opts.frameName, parent, "BackdropTemplate")
  if not okF or not created then
    created = CreateFrame("Frame", opts.frameName, parent)
  end
  local frame = created
  p.frame = frame
  if type(frame.SetSize) == "function" then frame:SetSize(520, 460) end
  if type(frame.SetPoint) == "function" then frame:SetPoint("CENTER") end
  if type(frame.SetFrameStrata) == "function" then pcall(frame.SetFrameStrata, frame, "DIALOG") end
  if type(frame.SetMovable) == "function" then pcall(frame.SetMovable, frame, true) end
  if type(frame.EnableMouse) == "function" then pcall(frame.EnableMouse, frame, true) end
  if type(frame.RegisterForDrag) == "function" then pcall(frame.RegisterForDrag, frame, "LeftButton") end
  if type(frame.SetScript) == "function" then
    frame:SetScript("OnDragStart", function(self)
      if type(self.StartMoving) == "function" then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
      if type(self.StopMovingOrSizing) == "function" then self:StopMovingOrSizing() end
    end)
  end
  if type(frame.SetBackdrop) == "function" then
    pcall(frame.SetBackdrop, frame, {
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
  end

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
  title:SetText(opts.title)

  local hintFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hintFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -40)
  hintFS:SetWidth(488)
  p.hintFS = hintFS

  local edit = CreateFrame("EditBox", opts.editName, frame)
  edit:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -72)
  if type(edit.SetSize) == "function" then edit:SetSize(488, 340) end
  if type(edit.SetMultiLine) == "function" then pcall(edit.SetMultiLine, edit, true) end
  if type(edit.SetAutoFocus) == "function" then pcall(edit.SetAutoFocus, edit, false) end
  if type(edit.SetTextInsets) == "function" then pcall(edit.SetTextInsets, edit, 6, 6, 6, 6) end
  p.editBox = edit
  if type(edit.SetScript) == "function" then
    edit:SetScript("OnEscapePressed", function(self)
      if type(self.ClearFocus) == "function" then
        self:ClearFocus()
      end
      if frame and type(frame.Hide) == "function" then
        frame:Hide()
      end
    end)
  end
  if type(frame.SetScript) == "function" then
    frame:SetScript("OnHide", function()
      if edit and type(edit.ClearFocus) == "function" then
        edit:ClearFocus()
      end
    end)
  end

  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  closeBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
  if type(closeBtn.SetSize) == "function" then closeBtn:SetSize(96, 24) end
  closeBtn:SetText("Close")
  closeBtn:SetScript("OnClick", function()
    frame:Hide()
  end)

  if type(tinsert) == "function" and type(UISpecialFrames) == "table" then
    pcall(tinsert, UISpecialFrames, opts.frameName)
  end

  copyPopups[key] = p
  return p
end

-- The two popups both sit at CENTER; opening one hides the other so
-- they never stack on top of each other.
local function hideOtherCopyPopups(exceptKey)
  for k, p in pairs(copyPopups) do
    if k ~= exceptKey and p and p.frame and type(p.frame.Hide) == "function" then
      pcall(p.frame.Hide, p.frame)
    end
  end
end

local function openCopyPopup(key, opts, text, failMsg)
  local ok, err = pcall(function()
    hideOtherCopyPopups(key)
    local p = ensureCopyPopup(key, opts)
    if p.editBox and type(p.editBox.SetText) == "function" then
      p.editBox:SetText(text)
    end
    if p.hintFS and type(p.hintFS.SetText) == "function" and type(opts.hintFn) == "function" then
      pcall(p.hintFS.SetText, p.hintFS, opts.hintFn())
    end
    if p.frame and type(p.frame.Show) == "function" then
      p.frame:Show()
    end
    if p.editBox and type(p.editBox.SetFocus) == "function" then
      pcall(p.editBox.SetFocus, p.editBox)
    end
    if p.editBox and type(p.editBox.HighlightText) == "function" then
      pcall(p.editBox.HighlightText, p.editBox)
    end
  end)
  if not ok and type(pkg.Print) == "function" then
    pkg.Print(failMsg .. tostring(err))
  end
end

function pkg.OpenBugReport()
  openCopyPopup("bug", {
    frameName = "MightiePackBugReportFrame",
    editName = "MightiePackBugReportEdit",
    title = "Report a bug",
    hintFn = pkg.CopyHint,
  }, pkg.BuildBugReport(), "could not open the bug report: ")
end

function pkg.OpenIdeaReport(areaArg)
  openCopyPopup("idea", {
    frameName = "MightiePackIdeaFrame",
    editName = "MightiePackIdeaEdit",
    title = "Suggest an idea",
    hintFn = pkg.IdeaCopyHint,
  }, pkg.BuildIdeaReport(areaArg), "could not open the idea form: ")
end
