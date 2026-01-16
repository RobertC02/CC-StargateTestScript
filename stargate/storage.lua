local M = {}

function M.ensureDir(path)
  if path ~= "" and not fs.exists(path) then
    fs.makeDir(path)
  end
end

function M.loadJson(path, defaultValue)
  if not fs.exists(path) then
    return defaultValue
  end
  local handle = fs.open(path, "r")
  if not handle then
    return defaultValue
  end
  local content = handle.readAll()
  handle.close()
  local ok, data = pcall(textutils.unserializeJSON, content)
  if ok and type(data) == "table" then
    return data
  end
  return defaultValue
end

function M.saveJson(path, dataDir, data)
  if dataDir then
    M.ensureDir(dataDir)
  end
  local handle = fs.open(path, "w")
  handle.write(textutils.serializeJSON(data))
  handle.close()
end

function M.normalizeConfig(cfg, defaultConfig, validSides)
  cfg = type(cfg) == "table" and cfg or {}
  if type(cfg.whitelistEnabled) ~= "boolean" then
    cfg.whitelistEnabled = defaultConfig.whitelistEnabled
  end
  if type(cfg.terminateIncoming) ~= "boolean" then
    cfg.terminateIncoming = defaultConfig.terminateIncoming
  end
  if type(cfg.incomingOverride) ~= "boolean" then
    cfg.incomingOverride = defaultConfig.incomingOverride
  end
  if type(cfg.irisLock) ~= "boolean" then
    cfg.irisLock = defaultConfig.irisLock
  end
  if type(cfg.alarmLatched) ~= "boolean" then
    cfg.alarmLatched = defaultConfig.alarmLatched
  end
  if type(cfg.alarmSide) ~= "string" or not validSides[cfg.alarmSide] then
    cfg.alarmSide = defaultConfig.alarmSide
  end
  if type(cfg.textScale) ~= "number" then
    cfg.textScale = defaultConfig.textScale
  end
  return cfg
end

function M.normalizeAddressEntry(entry)
  if type(entry) ~= "table" then
    return nil
  end
  local name = type(entry.name) == "string" and entry.name or ""
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  local addr = {}
  if type(entry.address) == "table" then
    for _, v in ipairs(entry.address) do
      local n = tonumber(v)
      if n and n >= 1 and n <= 38 then
        addr[#addr + 1] = math.floor(n)
      end
    end
  end
  while #addr > 8 do
    table.remove(addr)
  end
  while #addr > 0 and addr[#addr] == 0 do
    table.remove(addr)
  end
  local whitelisted = entry.whitelisted == true
  return { name = name, address = addr, whitelisted = whitelisted }
end

function M.normalizeAddresses(list)
  local result = {}
  if type(list) == "table" then
    for _, entry in ipairs(list) do
      local clean = M.normalizeAddressEntry(entry)
      if clean then
        result[#result + 1] = clean
      end
    end
  end
  return result
end

return M
