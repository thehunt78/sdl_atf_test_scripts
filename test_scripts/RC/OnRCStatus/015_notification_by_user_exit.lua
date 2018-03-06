---------------------------------------------------------------------------------------------------
-- User story: TBD
-- Use case: TBD
--
-- Requirement summary:
-- [SDL_RC] TBD
--
-- Description: SDL shall send OnRCStatus notifications to rc registered app
-- by allocation module via SetInteriorVehicleData
---------------------------------------------------------------------------------------------------
--[[ Required Shared libraries ]]
local runner = require('user_modules/script_runner')
local common = require('test_scripts/RC/OnRCStatus/commonOnRCStatus')

--[[ Test Configuration ]]
runner.testSettings.isSelfIncluded = false

--[[ Local Variables ]]
local freeModules = common.getModules()
local allocatedModules = {}

--[[ Local Functions ]]
local function alocateModule(pModuleType)
  local ModulesStatus = common.setModuleStatus(freeModules, allocatedModules, pModuleType)
  common.rpcAllowed(pModuleType, 1, "SetInteriorVehicleData")
  common.getMobileSession(1):ExpectNotification("OnRCStatus", ModulesStatus)
  EXPECT_HMINOTIFICATION("RC.OnRCStatus", ModulesStatus)
  :ValidIf(common.validateHMIAppIds)
end

local function userExit()
  local hmiAppId = common.getHMIAppId()
  common.getHMIconnection():SendNotification("BasicCommunication.OnExitApplication",
    { appID = hmiAppId, reason = "USER_EXIT" })
  common.getMobileSession(1):ExpectNotification("OnHMIStatus",
    { systemContext = "MAIN", hmiLevel = "NONE", audioStreamingState = "NOT_AUDIBLE" })
  local ModulesStatus = {
    freeModules = common.getModulesArray(freeModules),
    allocatedModules = common.getModulesArray(allocatedModules)
  }
  common.getMobileSession(1):ExpectNotification("OnRCStatus", ModulesStatus)
  EXPECT_HMINOTIFICATION("RC.OnRCStatus", ModulesStatus)
  :ValidIf(common.validateHMIAppIds)
end

--[[ Scenario ]]
runner.Title("Preconditions")
runner.Step("Clean environment", common.preconditions)
runner.Step("Start SDL, HMI, connect Mobile, start Session", common.start)
runner.Step("Register RC application", common.registerRCApplication)
runner.Step("Activate App", common.activateApp)
runner.Step("App allocates module CLIMATE ", alocateModule, { "CLIMATE" })

runner.Title("Test")
runner.Step("OnRCStatus notification by user exit", userExit)

runner.Title("Postconditions")
runner.Step("Stop SDL", common.postconditions)
