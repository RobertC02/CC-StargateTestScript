local M = {}

function M.new(ctx)
  local interface = ctx.interface
  local config = ctx.config
  local addresses = ctx.addresses
  local state = ctx.state
  local validSides = ctx.validSides
  local setMessage = ctx.setMessage
  local util = ctx.util

  local function setAlarm(on, forceOff)
    if not on and config.alarmLatched and not forceOff then
      return
    end
    state.alarmActive = on
    if validSides[config.alarmSide] then
      redstone.setOutput(config.alarmSide, on)
    end
  end

  local function resetAlarm()
    setAlarm(false, true)
  end

  local function applyWhitelist()
    local ok = pcall(interface.setFilterType, config.whitelistEnabled and 1 or 0)
    if not ok then
      setMessage("Failed to set filter type", 5)
      return
    end
    if not config.whitelistEnabled then
      return
    end
    pcall(interface.clearWhitelist)
    for _, entry in ipairs(addresses) do
      if entry.whitelisted and type(entry.address) == "table" then
        local len = #entry.address
        if len >= 6 and len <= 8 then
          pcall(interface.addToWhitelist, entry.address)
        end
      end
    end
  end

  local function updateStatus()
    state.status.connected = util.safeCall(interface.isStargateConnected) or false
    state.status.dialingOut = util.safeCall(interface.isStargateDialingOut) or false
    state.status.wormholeOpen = util.safeCall(interface.isWormholeOpen) or false
    state.status.topSignal = redstone.getInput("top") == true
    local iris = util.safeCall(interface.getIrisProgressPercentage) or 0
    state.status.irisPercent = math.floor(iris + 0.5)
    state.status.chevrons = util.safeCall(interface.getChevronsEngaged) or 0
    state.status.filterType = util.safeCall(interface.getFilterType) or 0
    if state.status.wormholeOpen then
      local addr = util.safeCall(interface.getConnectedAddress) or {}
      state.status.connectedAddressStr = util.addressToString(addr)
    else
      state.status.connectedAddressStr = "-"
    end
  end

  local function addressesEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
      return false
    end
    if #a ~= #b then
      return false
    end
    for i = 1, #a do
      if a[i] ~= b[i] then
        return false
      end
    end
    return true
  end

  local function isAddressWhitelisted(address)
    for _, entry in ipairs(addresses) do
      if entry.whitelisted and addressesEqual(entry.address, address) then
        return true
      end
    end
    return false
  end

  local function dialAddress(entry, opts)
    opts = opts or {}
    local allowUnlisted = opts.allowUnlisted or opts.tempWhitelist
    local useTempWhitelist = opts.tempWhitelist == true
    if not entry or type(entry.address) ~= "table" then
      setMessage("Invalid address", 4)
      return false
    end
    local len = #entry.address
    if len < 6 or len > 8 then
      setMessage("Address length must be 6-8", 4)
      return false
    end
    if config.whitelistEnabled and not entry.whitelisted and not allowUnlisted then
      setMessage("Entry not whitelisted", 4)
      return false
    end
    if util.safeCall(interface.isStargateConnected) then
      setMessage("Stargate already connected", 4)
      return false
    end

    local tempAdded = false
    if useTempWhitelist and config.whitelistEnabled and not entry.whitelisted and not isAddressWhitelisted(entry.address) then
      if pcall(interface.addToWhitelist, entry.address) then
        tempAdded = true
      end
    end

    if not (config.irisLock and state.irisManualOpen) then
      util.safeCall(interface.closeIris)
      if not config.irisLock then
        state.irisManualOpen = false
      end
    end
    local dial = util.buildDialAddress(entry.address)
    for i = 1, #dial do
      local ok = pcall(interface.engageSymbol, dial[i])
      if not ok then
        setMessage("Dial failed at symbol " .. tostring(dial[i]), 5)
        if tempAdded then
          pcall(interface.removeFromWhitelist, entry.address)
        end
        return false
      end
      sleep(0.5)
    end

    local timeout = os.clock() + 30
    while os.clock() < timeout do
      if util.safeCall(interface.isWormholeOpen) then
        util.safeCall(interface.openIris)
        if not config.irisLock then
          state.irisManualOpen = false
        end
        if tempAdded then
          pcall(interface.removeFromWhitelist, entry.address)
        end
        return true
      end
      if not util.safeCall(interface.isStargateConnected) and (util.safeCall(interface.getChevronsEngaged) or 0) == 0 then
        break
      end
      sleep(0.1)
    end
    if tempAdded then
      pcall(interface.removeFromWhitelist, entry.address)
    end
    setMessage("Dial timed out", 5)
    return false
  end

  return {
    applyWhitelist = applyWhitelist,
    dialAddress = dialAddress,
    resetAlarm = resetAlarm,
    setAlarm = setAlarm,
    updateStatus = updateStatus
  }
end

return M
