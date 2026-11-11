local addonName, pkg = ...

-- Earliest TOC file: wrap the client error handler so load errors in later
-- files can be captured once ObserveLuaError is in place. WoW addons cannot
-- recover a missed error from before this file runs.

local lastError = nil
local installed = false

local function safeStr(v)
  if type(v) ~= "string" then return nil end
  if v == "" then return nil end
  return v
end

local function patternEscape(s)
  return (tostring(s):gsub("(%W)", "%%%1"))
end

local function mentionsPack(text)
  return tostring(text or ""):find("MightiePack", 1, true) ~= nil
end

-- Read identity only to scrub it; never written into the report.
local function identityTerms()
  local name, realm
  if type(UnitName) == "function" then
    local ok, n = pcall(UnitName, "player")
    if ok then name = safeStr(n) end
  end
  if type(GetRealmName) == "function" then
    local ok, r = pcall(GetRealmName)
    if ok then realm = safeStr(r) end
  end
  return name, realm
end

function pkg.Sanitize(text)
  local s = tostring(text or ""):gsub("\r\n", "\n")

  -- Keep AddOns-relative paths readable; strip whatever precedes them.
  s = s:gsub("[^\n]*[Ii]nterface[/\\][Aa]dd[Oo]ns[/\\]([^\n]*)", function(rest)
    rest = rest:gsub("/", "\\")
    return "Interface\\AddOns\\" .. rest
  end)

  -- Lua 5.1 does not allow a quantifier on a captured group, so these are
  -- per-segment replacements rather than a repeated-group path matcher.
  s = s:gsub("\\\\[^%s\"']+", "<path>")
  s = s:gsub("[A-Za-z]:[/\\][^%s\"']*", "<path>")
  s = s:gsub("/[%w%._%-/]+", "<path>")

  s = s:gsub("Player%-%d+%-%x+", "<guid>")
  s = s:gsub("%f[%a]Creature%-[%x%-]+", "<guid>")
  s = s:gsub("%f[%a]Vehicle%-[%x%-]+", "<guid>")
  s = s:gsub("%f[%a]Pet%-[%x%-]+", "<guid>")
  s = s:gsub("%f[%a]GameObject%-[%x%-]+", "<guid>")
  s = s:gsub("%f[%a]Item%-[%x%-]+", "<guid>")
  s = s:gsub("%f[%a]Vignette%-[%x%-]+", "<guid>")

  s = s:gsub("%w+#%d%d%d%d+", "<battletag>")
  -- Name-Realm tokens: both sides start with a capital so version strings
  -- like 0.3.0-from-caddons are left alone.
  s = s:gsub("%f[%a]%u[%w']*%-%u[%w']+", "<name-realm>")

  local name, realm = identityTerms()
  if name then
    s = s:gsub(patternEscape(name), "<name>")
  end
  if realm then
    s = s:gsub(patternEscape(realm), "<realm>")
  end
  return s
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

local function isOurFrame(line)
  return line:find("ErrorHandler.lua", 1, true) ~= nil
    or line:find("BugReport.lua", 1, true) ~= nil
end

local function stackSnippet()
  local raw = ""
  if type(debugstack) == "function" then
    local ok, s = pcall(debugstack, 3, 8)
    if ok and type(s) == "string" then raw = s end
  elseif type(debug) == "table" and type(debug.traceback) == "function" then
    local ok, s = pcall(debug.traceback, "", 3)
    if ok and type(s) == "string" then raw = s end
  end
  local kept = {}
  for line in raw:gmatch("[^\r\n]+") do
    if not isOurFrame(line) then
      kept[#kept + 1] = line
    end
  end
  return table.concat(kept, "\n")
end

function pkg.GetCapturedLuaError()
  return lastError
end

-- Store only the most recent MightiePack error (message + first ~6 stack lines).
function pkg.ObserveLuaError(msg)
  local raw = tostring(msg or "")
  local stack = stackSnippet()
  -- Filter on the live message or stack (own frames already stripped so a
  -- stack generated from this file does not count as a pack error).
  if not mentionsPack(raw) and not mentionsPack(stack) then
    return
  end
  local message = pkg.Sanitize(raw)
  local extra = pkg.Sanitize(stack)
  local body = firstLines(message, 8)
  local clipped = firstLines(extra, 6)
  if clipped ~= "" then
    body = body .. "\n" .. clipped
  end
  lastError = body
end

function pkg.InstallErrorHandler()
  if installed then return end
  if type(seterrorhandler) ~= "function" then return end
  if type(geterrorhandler) ~= "function" then return end
  local ok, prev = pcall(geterrorhandler)
  if not ok or type(prev) ~= "function" then return end
  installed = true
  local busy = false
  seterrorhandler(function(...)
    if not busy then
      busy = true
      if type(pkg.ObserveLuaError) == "function" then
        pcall(pkg.ObserveLuaError, ...)
      end
      busy = false
    end
    return prev(...)
  end)
end

pcall(pkg.InstallErrorHandler)

-- Retry after every addon load: handlers may be missing at file-eval time,
-- and OptionalDeps: BugGrabber should already be in place; if it was not,
-- this is a second chance without wrapping twice (installed flag).
pcall(function()
  local f = CreateFrame("Frame")
  if type(f.RegisterEvent) == "function" then
    f:RegisterEvent("ADDON_LOADED")
  end
  if type(f.SetScript) == "function" then
    f:SetScript("OnEvent", function(_, _, name)
      if name == (addonName or "MightiePack") or name == "BugGrabber" then
        pcall(pkg.InstallErrorHandler)
      end
    end)
  end
end)
