-- MightiePack — the Touchstone tab (card t_a5de2f16, review layout item 3).
--
-- The vendored window's CONTENT moves into the unified window in whole: its
-- inner strip (Upgrades / Log / Settings), its renderers, its scale memory
-- (StatForgeDB.ui.scale, applied to the frame itself) and its first-use splash
-- all stay exactly as upstream wrote them. Only the outer chrome goes — the
-- title bar is hidden by Window.AttachTouchstone and the close button with it,
-- because the unified window has the only title and the only close.
--
-- This file is the seam, and it is deliberately thin:
--
--   * it captures the vendored entry points ONCE at load and replaces them
--     with window-aware ones, so every existing caller — /up, /upgrade,
--     /chestadvice, /ts, /touchstone, /sf, /statforge, the minimap button and
--     anything in the vendored code that calls SF.ShowMain — reaches the same
--     one window. No slash alias is touched, re-registered or dropped.
--   * it registers the tab's renderer, which attaches the content frame on
--     first activation and asks the vendored module to repaint afterwards.
--
-- No vendored file is edited for any of this (hard rule 3): the seam is a
-- runtime replacement of five public functions on a table the fold owns.

local _, pkg = ...

local W = pkg.Window
local SF = rawget(_G, "StatForge")
local T = {}
if type(W) == "table" then W.TouchstoneTab = T end

local function body(host)
  if type(T.body) == "table" then return T.body end
  local C = W and W.UI
  if type(C) ~= "table" or type(host) ~= "table" then return nil end
  local fs = C.Label(host, "GameFontNormalLarge", "")
  if type(fs) ~= "table" then return nil end
  pcall(fs.SetPoint, fs, "TOPLEFT", host, "TOPLEFT", 8, -8)
  T.body = fs
  return fs
end

local function say(text)
  local fs = body(W.hosts and W.hosts.touchstone)
  if type(fs) == "table" then
    pcall(fs.SetText, fs, text or "")
    pcall(fs.Show, fs)
  end
end

--- The tab's renderer.
function T.Render()
  local host = W.hosts and W.hosts.touchstone
  if type(host) ~= "table" then return false end
  local state = W.TouchstoneState()
  if state ~= "ready" then
    say(W.MODULE_OFF_TEXT.touchstone)
    return false
  end
  local fs = body(host)
  if type(fs) == "table" then
    -- An empty label over the moved-in content would sit on top of it.
    pcall(fs.SetText, fs, "")
    pcall(fs.Hide, fs)
  end
  if not W.AttachTouchstone() then
    say("Touchstone could not be shown: the module's window was not created.")
    return false
  end
  -- Repaint the inner tab that is active. The vendored refresh is a no-op when
  -- the frame is hidden; this window is visible by definition here.
  if type(W._sfRefresh) == "function" then pcall(W._sfRefresh) end
  return true
end

-- ── The seam ──────────────────────────────────────────────────────────────
-- Five public functions on StatForge, replaced once. Each replacement keeps the
-- original in W so nothing is lost: the attach path still calls the vendored
-- creator to build the frame, and the refresh still asks the vendored module to
-- repaint.
if type(SF) == "table" and type(W) == "table" then
  W._sfShowMain = type(SF.ShowMain) == "function" and SF.ShowMain or nil
  W._sfHideMain = type(SF.HideMain) == "function" and SF.HideMain or nil
  W._sfToggleMain = type(SF.ToggleMain) == "function" and SF.ToggleMain or nil
  W._sfIsMainShown = type(SF.IsMainShown) == "function" and SF.IsMainShown or nil
  W._sfRefresh = type(SF.RefreshActiveTab) == "function" and SF.RefreshActiveTab or nil

  SF.ShowMain = function(tabId)
    W.Open("touchstone")
    -- An explicit inner tab (Upgrades / Log / Settings) still wins, exactly as
    -- the vendored ShowMain's own argument did.
    if type(tabId) == "string" and type(SF.SelectTab) == "function" then
      pcall(SF.SelectTab, tabId)
    end
    return true
  end

  SF.HideMain = function()
    W.Close()
    return true
  end

  SF.ToggleMain = function()
    W.Toggle("touchstone")
    return W.IsOn("touchstone")
  end

  SF.IsMainShown = function()
    return W.IsOn("touchstone")
  end

  SF.RefreshActiveTab = function()
    if W.IsOn("touchstone") and type(W._sfRefresh) == "function" then
      return W._sfRefresh()
    end
    return false
  end
end

if type(W) == "table" and type(W.OnSelect) == "function" then
  W.OnSelect("touchstone", T.Render)
end
