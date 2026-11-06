local addonName, pkg = ...

pkg.modules = pkg.modules or {}
pkg.moduleOrder = pkg.moduleOrder or {}

function pkg.RegisterModule(name, def)
  if type(name) ~= "string" or name == "" then
    error("pkg.RegisterModule: name must be a non-empty string", 2)
  end
  if type(def) ~= "table" then
    error("pkg.RegisterModule: def must be a table", 2)
  end
  def.name = name
  local first = true
  for _, existing in ipairs(pkg.moduleOrder) do
    if existing == name then
      first = false
      break
    end
  end
  if first then
    table.insert(pkg.moduleOrder, name)
  end
  pkg.modules[name] = def
  return def
end

function pkg.IsModuleEnabled(name)
  local def = pkg.modules and pkg.modules[name]
  if not def then
    return false
  end
  if def.stub then
    return false
  end
  local settings = pkg.GetSettings()
  return settings.modules[name] == true
end

function pkg.SetModuleEnabled(name, on)
  local def = pkg.modules and pkg.modules[name]
  if not def or def.stub then
    return
  end
  local settings = pkg.GetSettings()
  settings.modules[name] = on and true or false
end

function pkg.EnableModules()
  for _, name in ipairs(pkg.moduleOrder or {}) do
    local def = pkg.modules and pkg.modules[name]
    if def and pkg.IsModuleEnabled(name) and type(def.Enable) == "function" and not def.loaded then
      local ok, err = pcall(def.Enable, def)
      if ok then
        def.loaded = true
      else
        pkg.Print("could not enable " .. tostring(def.title or name) .. ": " .. tostring(err))
      end
    end
  end
end

pkg.RegisterModule("Touchstone", {
  title = "Touchstone",
  notes = "Gear upgrade advice. Coming soon; this checkbox does nothing yet.",
  stub = true,
})
