---------------------------------------------------------------------------------------------------
-- Proposal: https://github.com/smartdevicelink/sdl_evolution/blob/master/proposals/0256-Refactor-Fuel-Information-Related-Vehicle-Data.md
--
-- Description: SDL transfers OnVehicleData notification to app if HMI sends it with only one parameter
--  in 'fuelRange' structure.
--
-- In case:
-- 1) App is subscribed to 'fuelRange' data.
-- 2) HMI sends valid OnVehicleData notification with only one parameter in 'fuelRange' structure.
-- SDL does:
--  a) process this notification and transfer it to mobile app.
---------------------------------------------------------------------------------------------------
--[[ Required Shared libraries ]]
local common = require('test_scripts/API/VehicleData/common')

--[[ Local Variables ]]
local param = "fuelRange"

local typeEnumValues = {
  "GASOLINE",
  "DIESEL",
  "CNG",
  "LPG",
  "HYDROGEN",
  "BATTERY"
}

local levelStateEnumValues = {
  "UNKNOWN",
  "NORMAL",
  "LOW",
  "FAULT",
  "ALERT",
  "NOT_SUPPORTED"
}

local capacityUnitEnumValues = {
  "LITERS",
  "KILOWATTHOURS",
  "KILOGRAMS"
}

local fuelRangeData = {
  type = typeEnumValues[1],
  range = 20,
  level = 5,
  levelState = levelStateEnumValues[1],
  capacity = 1234,
  capacityUnit = capacityUnitEnumValues[1]
}

local fuelRangeDataMinValues = {
  range = 0,
  level = -6,
  capacity = 0
}

local fuelRangeDataMaxValues = {
  range = 10000,
  level = 1000000,
  capacity = 1000000
}

local maxArraySize = {}
for i = 1, 100 do
  maxArraySize[i] = fuelRangeData
end

--[[ Scenario ]]
common.Title("Preconditions")
common.Step("Clean environment", common.preconditions)
common.Step("Start SDL, HMI, connect Mobile, start Session", common.start)
common.Step("Register App", common.registerApp)
common.Step("Activate App", common.activateApp)
common.Step("RPC " .. common.rpc.sub, common.processSubscriptionRPC, { common.rpc.sub, param })

common.Title("Test")
common.Title("VD parameter: " .. param)
for sub_param, value in common.spairs(fuelRangeDataMinValues) do
  common.Step("RPC " .. common.rpc.on .. " minValue " .. sub_param .. "=" .. value,
    common.sendOnVehicleData, { param, common.isExpected, { [1] = { [sub_param] = value } } })
end
for sub_param, value in common.spairs(fuelRangeDataMaxValues) do
  common.Step("RPC " .. common.rpc.on .. " maxValue " .. sub_param .. "=" .. value,
    common.sendOnVehicleData, { param, common.isExpected, { [1] = { [sub_param] = value } } })
end
for _, value in common.spairs(typeEnumValues) do
  common.Step("RPC " .. common.rpc.on .. " enum value " .. "type" .. "=" .. value,
    common.sendOnVehicleData, { param, common.isExpected, { [1] = { ["type"] = value } } })
end
for _, value in common.spairs(levelStateEnumValues) do
  common.Step("RPC " .. common.rpc.on .. " enum value " .. "levelState" .. "=" .. value,
    common.sendOnVehicleData, { param, common.isExpected, { [1] = { ["levelState"] = value } } })
end
for _, value in common.spairs(capacityUnitEnumValues) do
  common.Step("RPC " .. common.rpc.on .. " enum value " .. "capacityUnit" .. "=" .. value,
    common.sendOnVehicleData, { param, common.isExpected, { [1] = { ["capacityUnit"] = value } } })
end
common.Step("RPC " .. common.rpc.on .. " max  " .. param .. " array size",
    common.sendOnVehicleData, { param, common.isExpected, maxArraySize })

common.Title("Postconditions")
common.Step("Stop SDL", common.postconditions)
