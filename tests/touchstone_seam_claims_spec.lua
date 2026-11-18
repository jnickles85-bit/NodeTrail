-- touchstone_seam_claims_spec.lua — card t_37b8b58f (Case 1 phase 0).
--
-- The pack now STATES its presentation through two host seams instead of
-- carrying a modified copy of the vendored files:
--
--   SF.SetAssetRoot(root)   the base every texture path resolves through
--   SF.SetTheme{tokens}     accent / tab underline / underline height
--   SF.RepaintAccent()      paint once, after the whole palette is set
--
-- This spec exists because "the call is guarded" and "the call is correct" are
-- two different claims, and only the first is visible by running the suite
-- against the current pin (where the seams do not exist yet):
--
--   A. INERT. Against a body with NO seams, Enable() still succeeds and makes
--      no presentation call at all — behaviour is unchanged, which is what lets
--      this ship before the pin moves.
--   B. ACTIVE. Against a body WITH the seams (stubbed to the contract in
--      StatForge at eebfba4), the pack claims the right root and the right
--      tokens, in the right order (claims before SF.Enable, repaint after).
--   C. INERT-MODULE. When the standalone Touchstone is installed the module is
--      inert; it must not claim a palette for a body it is not running.

local src = debug.getinfo(1, "S").source:gsub("^@", "")
local root = src:match("^(.*)/tests/[^/]+$") or "."

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end

-- ── A fresh package per scenario ──────────────────────────────────────────
local function scenario()
  local pkg = {}
  pkg.Print = function() end
  local function loadPack(rel)
    local chunk, err = loadfile(root .. "/MightiePack/" .. rel)
    check(chunk ~= nil, "loadfile " .. rel .. ": " .. tostring(err))
    if not chunk then return false end
    local ok, e = pcall(chunk, "MightiePack", pkg)
    check(ok, "load " .. rel .. ": " .. tostring(e))
    return ok
  end
  loadPack("Modules/Touchstone/Constants.lua")   -- the real brand table
  loadPack("Modules.lua")
  loadPack("Theme.lua")
  check(type(StatForge) == "table", "precondition: the vendored body published StatForge")
  check(type(pkg.Theme) == "table", "precondition: the pack published pkg.Theme")
  return pkg
end

local function enable(pkg, skip)
  MightiePackTouchstoneSkip = skip and true or nil
  pkg.TouchstoneDetection = { path = "C_AddOns.DoesAddOnExist", present = skip and true or false,
                              skip = skip and true or false }
  local def = pkg.modules and pkg.modules.Touchstone
  check(type(def) == "table", "the Touchstone module is registered")
  if type(def) ~= "table" or type(def.Enable) ~= "function" then return nil end
  local ok, result = pcall(def.Enable, def)
  check(ok, "Enable ran without raising: " .. tostring(result))
  return result
end

-- ── A. INERT against a body with no seams ─────────────────────────────────
do
  local pkg = scenario()
  local calls = 0
  local before = { StatForge.SetAssetRoot, StatForge.SetTheme, StatForge.RepaintAccent }
  -- The current pin's body: the seam functions do not exist.
  StatForge.SetAssetRoot = nil
  StatForge.SetTheme = nil
  StatForge.RepaintAccent = nil
  StatForge.Enable = function() calls = calls + 1 end
  ChestAdvisor = nil

  local result = enable(pkg, false)
  check(result == true, "no-seam body: Enable still succeeds")
  check(calls == 1, "no-seam body: SF.Enable still runs (got " .. calls .. ")")
  check(StatForge.SetAssetRoot == nil, "no-seam body: the pack invents no seam")
end

-- ── B. ACTIVE against the eebfba4 contract ────────────────────────────────
do
  local pkg = scenario()
  local T = pkg.Theme
  local seen = { order = {} }
  StatForge.SetAssetRoot = function(r)
    seen.root = r
    seen.order[#seen.order + 1] = "root"
    return r
  end
  StatForge.SetTheme = function(t)
    seen.theme = t
    seen.order[#seen.order + 1] = "theme"
    return t
  end
  StatForge.RepaintAccent = function()
    seen.repainted = true
    seen.order[#seen.order + 1] = "repaint"
  end
  StatForge.Enable = function()
    seen.order[#seen.order + 1] = "enable"
  end
  ChestAdvisor = nil

  local result = enable(pkg, false)
  check(result == true, "seam body: Enable succeeds")

  check(seen.root == "Interface\\AddOns\\MightiePack\\Modules\\Touchstone\\ChestAdvisor\\",
    "claims the vendored asset folder, not the standalone one (got " .. tostring(seen.root) .. ")")

  check(type(seen.theme) == "table", "claims a palette")
  if type(seen.theme) == "table" then
    local ar, ag, ab = T.Ledger("text")
    check(type(seen.theme.accent) == "table" and seen.theme.accent[1] == ar
      and seen.theme.accent[2] == ag and seen.theme.accent[3] == ab,
      "the accent is the ledger's reading white (what hosted mode painted), not the body's teal")
    local ur, ug, ub = T.Dim("text")
    check(type(seen.theme.underline) == "table" and seen.theme.underline[1] == ur
      and seen.theme.underline[2] == ug and seen.theme.underline[3] == ub,
      "the tab underline is the pack's text token")
    check(seen.theme.underlineHeight == T.size.underline,
      "the underline height is the pack's own token")
  end
  check(seen.repainted == true, "asks for one repaint after the palette is set")

  -- Order: the claims must precede SF.Enable (its creation path reads them)
  -- and the repaint must follow the palette.
  local function at(name)
    for i, v in ipairs(seen.order) do if v == name then return i end end
    return nil
  end
  check(at("root") and at("enable") and at("root") < at("enable"),
    "the asset root is set before SF.Enable creates the frame")
  local ti = at("theme")
  check(ti and ti < at("enable"), "the palette is set before SF.Enable")
  check(ti and at("repaint") and at("repaint") > ti, "the repaint follows SetTheme")
end

-- ── C. INERT MODULE: standalone detected ──────────────────────────────────
do
  local pkg = scenario()
  local seen = 0
  StatForge.SetAssetRoot = function() seen = seen + 1 end
  StatForge.SetTheme = function() seen = seen + 1 end
  StatForge.RepaintAccent = function() seen = seen + 1 end
  local result = enable(pkg, true)
  check(result == false, "standalone detected: Enable returns false (module inert)")
  check(seen == 0, "standalone detected: no palette is claimed for a body that is not running")
end

if failed == 0 then
  print("touchstone_seam_claims_spec: ok")
else
  print(("touchstone_seam_claims_spec: %d failure(s)"):format(failed))
  os.exit(1)
end
