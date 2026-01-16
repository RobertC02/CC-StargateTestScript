local M = {}

function M.clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

function M.safeCall(fn, ...)
  local ok, result = pcall(fn, ...)
  if ok then
    return result
  end
  return nil
end

function M.addressToString(address)
  if type(address) ~= "table" or #address == 0 or #address > 8 then
    return "-"
  end
  local s = "-"
  for i = 1, #address do
    s = s .. tostring(address[i]) .. "-"
  end
  return s
end

function M.buildDialAddress(addr)
  local dial = {}
  for i = 1, #addr do
    dial[i] = addr[i]
  end
  if #dial > 0 and dial[#dial] ~= 0 then
    dial[#dial + 1] = 0
  end
  return dial
end

return M
