local _, pkg = ...

local panel = CreateFrame("Frame", "MightiePackOptionsPanel")
panel.name = "MightiePack"

local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
title:SetText("MightiePack")

local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
subtitle:SetText("Tick a module to turn it on. Turning one off needs a UI reload.")

local boxes = {}
pkg.optionsBoxes = boxes

-- ── Row layout ──────────────────────────────────────────────────────
-- Modules are 32px apart. NodeTrail — the only gathering module — also
-- owns 22px indented sub-rows for its own sub-options: the skinning probe
-- (t_5507a0ba) and, under it, "Auto-refresh route" (t_2bc15917). Each is a
-- user-facing capability of NodeTrail, so each has a visible control here;
-- NodeTrail + its sub-options occupy one and a half rows and the recipe /
-- bug-report blocks below start after that, not after a fixed module count.
-- moduleOrder is complete by the time this file loads (the TOC lists every
-- module before Options.lua).
local ROW_H = 32
local SUB_ROW_H = 22
local SUB_INDENT = 36
local FIRST_ROW_Y = -48

local moduleY, skinY, autoY, skinRouteY, lastRowY = {}, nil, nil, nil, FIRST_ROW_Y
do
  local y = FIRST_ROW_Y
  for _, name in ipairs(pkg.moduleOrder or {}) do
    moduleY[name] = y
    lastRowY = y
    y = y - ROW_H
    if name == "NodeTrail" then
      skinY = y + (ROW_H - SUB_ROW_H)
      autoY = skinY - SUB_ROW_H
      -- t_b46e5e87: the skinning farming circle's switch, third sub-row.
      skinRouteY = autoY - SUB_ROW_H
      lastRowY = skinRouteY
      y = skinRouteY - ROW_H
    end
  end
end

-- ── Skinning sub-option helpers (t_5507a0ba) ────────────────────────
-- The probe is NodeTrail's, so the toggle is NodeTrail's too: it lives at
-- NodeTrailDB.skinning.enabled (not MightiePackDB.modules.Skinning) and is
-- owned by the NodeTrail namespace. Every lookup is guarded so the panel
-- still renders when NodeTrail (or the probe files) did not load.
local function ntModule()
  local nt = pkg.NodeTrail
  if type(nt) == "table" then
    return nt
  end
  return nil
end

local function nodeTrailOn()
  if type(pkg.IsModuleEnabled) ~= "function" then
    return false
  end
  local ok, on = pcall(pkg.IsModuleEnabled, "NodeTrail")
  return ok and on == true
end

local function skinningOn()
  local nt = ntModule()
  if nt and type(nt.IsSkinningEnabled) == "function" then
    local ok, on = pcall(nt.IsSkinningEnabled)
    if ok then
      return on == true
    end
  end
  return false
end

-- t_57550700: ON by default (Mightie's final call: "doesnt need to come off by
-- default"). What the box turns on is a re-plan every `autoRefreshPicks`
-- gathers — not one per herb, which is what made the line move under him.
local function autoRefreshOn()
  local nt = ntModule()
  if nt and type(nt.IsAutoRefreshRoute) == "function" then
    local ok, on = pcall(nt.IsAutoRefreshRoute)
    if ok then
      return on == true
    end
  end
  return true
end

-- t_b46e5e87: the skinning farming circle's switch (default ON). Its own key at
-- NodeTrailDB.skinroute.enabled, separate from the probe and from the herb route.
local function skinRouteOn()
  local nt = ntModule()
  if nt and type(nt.IsSkinRouteEnabled) == "function" then
    local ok, on = pcall(nt.IsSkinRouteEnabled)
    if ok then
      return on == true
    end
  end
  return true
end

-- The one sentence the circle's row shows, and ONLY for a confirmed skinner:
-- a non-skinner must not see a "no data" line anywhere (t_b46e5e87). It states
-- the count needed whenever nothing can be drawn yet.
local function skinRouteNote()
  local nt = ntModule()
  if not nt then
    return nil
  end
  local Pr = nt.Profession
  if type(Pr) ~= "table" or type(Pr.Skinning) ~= "function" then
    return nil
  end
  local okG, answer = pcall(Pr.Skinning, Pr)
  if not okG or answer ~= true then
    return nil
  end
  if type(nt.SkinRoute) ~= "table" or type(nt.SkinRoute.StatusText) ~= "function" then
    return nil
  end
  local ok, line = pcall(nt.SkinRoute.StatusText, nt.SkinRoute)
  if ok and type(line) == "string" and line ~= "" then
    if #line > 84 then
      line = line:sub(1, 81) .. "..."
    end
    return line
  end
  return nil
end

-- Apply the sub-toggle: persist it and re-evaluate the layer immediately.
local function applySkinRoute(on)
  local nt = ntModule()
  if not nt then
    pkg.Print("skinning circle: NodeTrail is not loaded — the sub-option was not saved")
    return false
  end
  if type(nt.SetSkinRouteEnabled) ~= "function" then
    pkg.Print("skinning circle: NodeTrail has no sub-option setter — the sub-option was not saved")
    return false
  end
  local okS, errS = pcall(nt.SetSkinRouteEnabled, on)
  if not okS then
    pkg.Print("skinning circle: could not save the sub-option: " .. tostring(errS))
    return false
  end
  local route, why
  if type(nt.RefreshSkinRoute) == "function" then
    local okR, r, w = pcall(nt.RefreshSkinRoute)
    if okR then
      route, why = r, w
    else
      pkg.Print("skinning circle: refresh failed: " .. tostring(r))
      return false
    end
  end
  if on then
    if route then
      pkg.Print(("Skinning farming circle on — %d-point green loop over %d clusters on this map.")
        :format(#route.path, #route.clusters))
    elseif why == "NOT_SKINNER" then
      pkg.Print("Skinning farming circle on, but this character has no Skinning — nothing is drawn.")
    elseif why == "GATE_UNREADABLE" or why == "NO_GATE" then
      pkg.Print("Skinning farming circle on, but this client cannot read the character's professions — nothing is drawn.")
    else
      local line = (type(nt.SkinRoute) == "table" and type(nt.SkinRoute.StatusText) == "function")
        and nt.SkinRoute:StatusText() or nil
      pkg.Print("Skinning farming circle on, but " .. (line or "there is no route to draw yet") .. ".")
    end
  else
    pkg.Print("Skinning farming circle off — the green loop is cleared; the herb route is unaffected.")
  end
  return true
end

-- Apply the sub-toggle: persist it, then start/stop the probe immediately.
-- No reload is needed — switching off unregisters the probe's events and
-- drops its session buffer (P:Disable) — so this deliberately does NOT
-- raise MIGHTIEPACK_DISABLE_MODULE. That popup exists to warn about a
-- reload; there is nothing to warn about here, and the chat line says so.
local function applySkinning(on)
  local nt = ntModule()
  if not nt then
    pkg.Print("skinning: NodeTrail is not loaded — the sub-option was not saved")
    return false
  end
  if type(nt.SetSkinningEnabled) ~= "function" then
    pkg.Print("skinning: NodeTrail has no sub-option setter — the sub-option was not saved")
    return false
  end
  local okS, errS = pcall(nt.SetSkinningEnabled, on)
  if not okS then
    pkg.Print("skinning: could not save the sub-option: " .. tostring(errS))
    return false
  end
  if on then
    if type(nt.EnableSkinning) == "function" then
      local okE, errE = nt.EnableSkinning()
      if okE == false then
        pkg.Print("skinning: probe did not start: " .. tostring(errE))
        return false
      end
    end
    pkg.Print("Skinning (experimental) on — recording corpses into NodeTrailDB; /mp skindiag dump shows what was stored.")
  else
    if type(nt.DisableSkinning) == "function" then
      nt.DisableSkinning()
    end
    pkg.Print("Skinning (experimental) off — the probe stopped now; no UI reload needed.")
  end
  return true
end

local function syncCheckboxes()
  for index, name in ipairs(pkg.moduleOrder or {}) do
    local def = pkg.modules and pkg.modules[name]
    if def then
      local y = moduleY[name] or (FIRST_ROW_Y - (index - 1) * ROW_H)
      local cb = boxes[name]
      if not cb then
        cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)

        local label
        if cb.Text or cb.text then
          label = cb.Text or cb.text
        else
          label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
          label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        end
        local labelText = def.title or name
        if def.stub then
          labelText = labelText .. " (coming soon)"
        end
        label:SetText(labelText)

        if def.stub then
          cb:Disable()
        else
          cb:SetScript("OnClick", function(self)
            local on = self:GetChecked() and true or false
            if on then
              pkg.SetModuleEnabled(name, true)
              pkg.EnableModules()
              -- A module can refuse to run (Touchstone while the standalone
              -- addon folder is installed). Its Enable() has already printed
              -- why; "enabled." here would be a lie.
              if not def.inert then
                pkg.Print((def.title or name) .. " enabled.")
              end
              -- The skinning sub-option is greyed out while NodeTrail is
              -- off; re-sync so it becomes usable the moment it is on.
              syncCheckboxes()
            else
              StaticPopup_Show("MIGHTIEPACK_DISABLE_MODULE", def.title or name, nil, { name = name, checkbox = self })
            end
          end)
        end

        cb:SetScript("OnEnter", function(self)
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:SetText(def.title or name)
          if def.notes then
            GameTooltip:AddLine(def.notes, 1, 1, 1, true)
          end
          GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function()
          GameTooltip:Hide()
        end)

        boxes[name] = cb
      end

      if def.stub then
        cb:SetChecked(false)
      else
        cb:SetChecked(pkg.IsModuleEnabled(name))
      end
    end
  end

  -- ── Skinning sub-option (t_5507a0ba) ──────────────────────────────
  -- Indented under the NodeTrail checkbox, its own checkbox, and NOT a
  -- module row: Mightie's "Skinning should be inside NodeTrail." Greyed out
  -- and inert while NodeTrail is off (the probe is NodeTrail's), persisted
  -- in NodeTrailDB.skinning.enabled, applied immediately in both
  -- directions — no reload, so no MIGHTIEPACK_DISABLE_MODULE popup here.
  if skinY then
    local sb = boxes.Skinning
    if not sb then
      sb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
      sb:SetPoint("TOPLEFT", panel, "TOPLEFT", SUB_INDENT, skinY)

      local skinLabel
      if sb.Text or sb.text then
        skinLabel = sb.Text or sb.text
      else
        skinLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        skinLabel:SetPoint("LEFT", sb, "RIGHT", 4, 0)
      end
      skinLabel:SetText("Skinning (experimental)")

      sb:SetScript("OnClick", function(self)
        if not nodeTrailOn() then
          -- inert: NodeTrail owns the probe, so it cannot be on without it
          self:SetChecked(skinningOn())
          return
        end
        applySkinning(self:GetChecked() and true or false)
        syncCheckboxes()
      end)
      sb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Skinning (experimental)")
        GameTooltip:AddLine("NodeTrail's skinning probe: kill -> loot -> skin -> skin-loot capture for "
          .. "/mp skindiag and /mp skindiag dump. Off by default while this client's event surface "
          .. "is still unverified. Turn it off at any time — no UI reload needed.", 1, 1, 1, true)
        GameTooltip:Show()
      end)
      sb:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)

      boxes.Skinning = sb
    end

    sb:SetChecked(skinningOn())
    if nodeTrailOn() then
      sb:Enable()
    else
      sb:Disable()
    end
  end

  -- ── Auto-refresh route sub-option (t_2bc15917, default flipped t_57550700)
  -- Mightie: "yes it needs to be automated for sure, at least on /reloads".
  -- The automatic behaviour has to be visible and switchable, so it is a
  -- checkbox beside the skinning one, persisted in
  -- NodeTrailDB.route.autoRefresh. It is OFF by default: ON is what re-planned
  -- the whole zone route under him while he gathered, and the line he was
  -- following is the ground he is walking. The /reload restore is NOT this
  -- switch — that always happens. It applies immediately in both directions:
  -- switching it off keeps the line that is drawn and stops pick-triggered
  -- rebuilds; switching it on rebuilds now and lets the next pick schedule one.
  if autoY then
    local ab = boxes.AutoRefresh
    if not ab then
      ab = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
      ab:SetPoint("TOPLEFT", panel, "TOPLEFT", SUB_INDENT, autoY)

      local autoLabel
      if ab.Text or ab.text then
        autoLabel = ab.Text or ab.text
      else
        autoLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        autoLabel:SetPoint("LEFT", ab, "RIGHT", 4, 0)
      end
      autoLabel:SetText("Auto-refresh route")

      ab:SetScript("OnClick", function(self)
        local nt = ntModule()
        if not nodeTrailOn() or not nt then
          self:SetChecked(autoRefreshOn())
          return
        end
        -- t_57550700: one implementation of the switch, shared with
        -- /nt autorefresh — so the box also rebuilds at once when turned on.
        local okS, value
        if type(nt.SetAutoRefresh) == "function" then
          okS, value = pcall(nt.SetAutoRefresh, self:GetChecked() and "on" or "off")
        elseif type(nt.SetAutoRefreshRoute) == "function" then
          okS, value = pcall(nt.SetAutoRefreshRoute, self:GetChecked() and true or false)
        else
          self:SetChecked(autoRefreshOn())
          return
        end
        if not okS then
          pkg.Print("auto-refresh: could not save the sub-option: " .. tostring(value))
        elseif value then
          pkg.Print("Auto-refresh route on — the route is rebuilt a few seconds after each gather.")
        else
          pkg.Print("Auto-refresh route off — the route stays as it is until /nt reload.")
        end
        syncCheckboxes()
      end)
      ab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Auto-refresh route")
        GameTooltip:AddLine("When on, a route you started is rebuilt and drawn again after a /reload or a login " ..
          "(if it is younger than the saved-route limit and you are on its map), and the line follows the " ..
          "herbs you gather — once, a few seconds after the last pick. Off keeps the line as it is.",
          1, 1, 1, true)
        GameTooltip:Show()
      end)
      ab:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)

      boxes.AutoRefresh = ab
    end

    ab:SetChecked(autoRefreshOn())
    if nodeTrailOn() then
      ab:Enable()
    else
      ab:Disable()
    end
  end

  -- ── Skinning farming circle sub-option (t_b46e5e87) ─────────────────
  -- The circle is a DRAW layer, so its switch is independent of the probe and of
  -- the herb route. The status line under it is shown ONLY to a confirmed
  -- skinner and says how many more skinned corpses this map needs — the maps
  -- themselves stay clean until there is real skinning data.
  if skinRouteY then
    local rb = boxes.SkinRoute
    if not rb then
      rb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
      rb:SetPoint("TOPLEFT", panel, "TOPLEFT", SUB_INDENT, skinRouteY)

      local rbLabel
      if rb.Text or rb.text then
        rbLabel = rb.Text or rb.text
      else
        rbLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        rbLabel:SetPoint("LEFT", rb, "RIGHT", 4, 0)
      end
      rbLabel:SetText("Skinning farming circle")

      rb:SetScript("OnClick", function(self)
        if not nodeTrailOn() then
          self:SetChecked(skinRouteOn())
          return
        end
        applySkinRoute(self:GetChecked() and true or false)
        syncCheckboxes()
      end)
      rb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Skinning farming circle")
        GameTooltip:AddLine("A green closed loop through the places this character has killed AND skinned on "
          .. "the current zone's map. Built from your own recorded corpses only. It stays hidden until the map "
          .. "has enough skinned corpses to make a circle, until a Skinning character is logged in, and while "
          .. "this box is unticked. The herb route (white) is a separate line and is not affected.",
          1, 1, 1, true)
        GameTooltip:Show()
      end)
      rb:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)

      boxes.SkinRoute = rb
    end

    local note = boxes.SkinRouteNote
    if not note then
      note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      note:SetPoint("TOPLEFT", panel, "TOPLEFT", SUB_INDENT + 20, skinRouteY - 18)
      note:SetText("")
      boxes.SkinRouteNote = note
    end
    local text = skinRouteNote()
    if text then
      note:SetText(text)
      note:Show()
    else
      note:SetText("")
      note:Hide()
    end

    rb:SetChecked(skinRouteOn())
    if nodeTrailOn() then
      rb:Enable()
    else
      rb:Disable()
    end
  end
end

-- ── Recipes block (NodeTrail's Alchemy recipe scan) ─────────────────
-- The scan used to be invisible unless you knew /nt status, and
-- learning a recipe never refreshed it (t_36412359). This block
-- surfaces the SAME truth the panel/slash share (Rc:StatusLine —
-- four states: scanned / not scanned yet / cannot list / no reagents)
-- plus a "Scan now" button (Rc:TryScanNow). Every lookup is pcall'd,
-- so the panel still renders when the NodeTrail module is off.
local function ntRecipes()
  if pkg and pkg.NodeTrail and type(pkg.NodeTrail.Recipes) == "table" then
    return pkg.NodeTrail.Recipes
  end
  return nil
end

-- The recipe block starts under the last module/sub-option row.
local recHeaderY = lastRowY - 36
local recStatusY = recHeaderY - 18
local recErrorY = recStatusY - 16
local recNoteY = recErrorY - 16
local recButtonY = recNoteY - 22

local recHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
recHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, recHeaderY)
recHeader:SetText("Alchemy Recipes")

local recStatus = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
recStatus:SetPoint("LEFT", recHeader, "LEFT", 0, recStatusY - recHeaderY)
recStatus:SetText("")

local recError = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
recError:SetPoint("LEFT", recHeader, "LEFT", 0, recErrorY - recHeaderY)
recError:SetText("")
recError:Hide()

-- t_4ab7c230: when the client answers no availability at all, the herb tooltip
-- draws NO Alchemy line (a list of crafts he cannot make is worse than none).
-- This is the one short place the reason lives, so nobody re-opens the card
-- expecting a fix this client cannot support.
local recNote = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
recNote:SetPoint("LEFT", recHeader, "LEFT", 0, recNoteY - recHeaderY)
recNote:SetText("")
recNote:Hide()

local function syncRecipesBlock()
  local rec = ntRecipes()
  if rec and type(rec.StatusLine) == "function" then
    local ok, line = pcall(rec.StatusLine, rec)
    if ok and type(line) == "string" then
      recStatus:SetText(line)
    else
      recStatus:SetText("recipes: status unavailable (" .. tostring(line) .. ")")
    end
    recStatus:Show()
  else
    recStatus:SetText("recipe module not loaded — turn NodeTrail on")
    recStatus:Show()
  end
  local err
  if rec and type(rec.LastError) == "function" then
    local okE, e = pcall(rec.LastError, rec)
    if okE and type(e) == "string" and e ~= "" then
      err = e
    end
  end
  if err then
    recError:SetText("last error: " .. err)
    recError:Show()
  else
    recError:SetText("")
    recError:Hide()
  end
  -- The hidden-list explanation (t_4ab7c230). nil when the gate is working or
  -- nothing is saved yet, so the line stays invisible in the normal case.
  local hint
  if rec and type(rec.HiddenHint) == "function" then
    local okH, h = pcall(rec.HiddenHint, rec)
    if okH and type(h) == "string" and h ~= "" then
      hint = h
    end
  end
  if hint then
    recNote:SetText(hint)
    recNote:Show()
  else
    recNote:SetText("")
    recNote:Hide()
  end
end

local recButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
recButton:SetPoint("TOPLEFT", recHeader, "LEFT", 0, recButtonY - recHeaderY)
recButton:SetSize(96, 24)
recButton:SetText("Scan now")
recButton:SetScript("OnClick", function()
  local rec = ntRecipes()
  if rec and type(rec.TryScanNow) == "function" then
    local ok, done, msg = pcall(rec.TryScanNow, rec)
    if not ok then
      DEFAULT_CHAT_FRAME:AddMessage("NodeTrail recipes: scan failed: " .. tostring(done))
    else
      DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
  else
    DEFAULT_CHAT_FRAME:AddMessage("NodeTrail recipes: module not loaded (turn NodeTrail on)")
  end
  syncRecipesBlock()
end)
recButton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText("Rescan your learned Alchemy recipes now")
  GameTooltip:AddLine("Needs the Alchemy window open. A learned recipe also refreshes automatically the next time you open Alchemy.", 1, 1, 1, true)
  GameTooltip:Show()
end)
recButton:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

-- ── Bug report entry point ──────────────────────────────────────────
-- Opens the same selectable popup as /mp bug. The report is pre-filled
-- (version, client, modules, class+level, zone, last Lua error) for the
-- player to copy with Ctrl+C. Nothing is uploaded.
local bugHeaderY = recButtonY - 40
local bugButtonY = bugHeaderY - 26

local bugHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
bugHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, bugHeaderY)
bugHeader:SetText("Bug reports")

local bugButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
bugButton:SetPoint("TOPLEFT", bugHeader, "LEFT", 0, bugButtonY - bugHeaderY)
bugButton:SetSize(128, 24)
bugButton:SetText("Report a bug")
bugButton:SetScript("OnClick", function()
  if type(pkg.OpenBugReport) == "function" then
    -- Same popup as /mp bug.
    pkg.OpenBugReport()
  else
    DEFAULT_CHAT_FRAME:AddMessage("MightiePack: bug report form unavailable (BugReport module did not load)")
  end
end)
bugButton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText("Open a pre-filled bug report — press Ctrl+C to copy, then paste it in #mightiepack-bugs on Discord")
  GameTooltip:AddLine("Nothing is uploaded: copy the report and paste it into the #mightiepack-bugs Discord channel.", 1, 1, 1, true)
  GameTooltip:Show()
end)
bugButton:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

panel:SetScript("OnShow", function()
  syncCheckboxes()
  syncRecipesBlock()
end)

StaticPopupDialogs["MIGHTIEPACK_DISABLE_MODULE"] = {
  text = "Turn off %s?\nThis needs a UI reload. OK reloads now; Cancel keeps it on.",
  button1 = OKAY,
  button2 = CANCEL,
  OnAccept = function(self, data)
    if data and data.name then
      pkg.SetModuleEnabled(data.name, false)
    end
    ReloadUI()
  end,
  OnCancel = function(self, data)
    if data and data.checkbox then
      data.checkbox:SetChecked(pkg.IsModuleEnabled(data.name))
    end
  end,
  OnHide = function(self)
    local data = self.data
    if data and data.checkbox then
      data.checkbox:SetChecked(pkg.IsModuleEnabled(data.name))
    end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

pcall(function()
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
    pkg.settingsCategory = category
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end)

function pkg.OpenOptions()
  if pkg.settingsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(pkg.settingsCategory:GetID())
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
  else
    panel:Show()
  end
end

pkg.optionsPanel = panel
