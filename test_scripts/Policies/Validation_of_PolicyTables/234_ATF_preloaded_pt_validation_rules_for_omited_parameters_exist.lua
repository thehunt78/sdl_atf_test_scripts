---------------------------------------------------------------------------------------------
-- Requirement summary:
-- [Policies]: PreloadedPolicyTable: Validation rules for omited parameters - exists
--
-- Description:
-- Behavior of SDL during start SDL in case when PreloadedPT has omited parameters
-- 1. Used preconditions:
-- Delete files and policy table from previous ignition cycle if any
-- Do not start default SDL
-- 2. Performed steps:
-- Create PreloadedPolicyTable file with couple omited parameters
-- Start SDL
--
-- Expected result:
-- PolicyManager shut SDL down
---------------------------------------------------------------------------------------------
require('user_modules/script_runner').isTestApplicable({ { extendedPolicy = { "EXTERNAL_PROPRIETARY" } } })

--[[ Required Shared libraries ]]
local commonFunctions = require ('user_modules/shared_testcases/commonFunctions')
local commonSteps = require('user_modules/shared_testcases/commonSteps')
local commonPreconditions = require('user_modules/shared_testcases/commonPreconditions')
local testCasesForPolicyTable = require('user_modules/shared_testcases/testCasesForPolicyTable')
local testCasesForPolicySDLErrorsStops = require('user_modules/shared_testcases/testCasesForPolicySDLErrorsStops')
local sdl = require('modules/SDL')

--[[ Local Variables ]]
local PRELOADED_PT_FILE_NAME = "sdl_preloaded_pt.json"

--[[ Local Functions ]]
local function checkSDLStatus(test, expStatus)
  local actStatus = sdl:CheckStatusSDL()
  print("SDL status: " .. tostring(actStatus))
  if actStatus ~= expStatus then
    local msg = "Expected SDL status: " .. expStatus .. ", actual: " .. actStatus
    test:FailTestCase(msg)
  end
end

--[[ General Precondition before ATF start ]]
config.defaultProtocolVersion = 2
config.ExitOnCrash = false
commonSteps:DeleteLogsFileAndPolicyTable()

--[[ General configuration parameters ]]
Test = require('connecttest')
require("user_modules/AppTypes")

--[[ Preconditions ]]
function Test:Precondition_stop_sdl()
  StopSDL(self)
end

function Test:CheckSDLStatus()
  checkSDLStatus(self, sdl.STOPPED)
end

function Test.Precondition()
  local testParameters = {vehicle_model = "Fiesta", vehicle_make = "Ford", vehicle_year = 2015}
  commonSteps:DeletePolicyTable()
  commonSteps:DeleteLogsFiles()
  commonPreconditions:BackupFile(PRELOADED_PT_FILE_NAME)
  testCasesForPolicySDLErrorsStops.updatePreloadedPT("data.policy_table.module_config", testParameters)
end

--[[ Test ]]
function Test.TestStep_start_sdl()
  StartSDL(config.pathToSDL, config.ExitOnCrash)
  os.execute("sleep 5")
end

function Test:CheckSDLStatus()
  checkSDLStatus(self, sdl.STOPPED)
end

function Test:TestStep_CheckSDLLogError()
  local result = testCasesForPolicySDLErrorsStops.ReadSpecificMessage("Policy table is not initialized.")
  if (result == false) then
    self:FailTestCase("Error: message 'Policy table is not initialized.' is not observed in smartDeviceLink.log.")
  end

  result = testCasesForPolicySDLErrorsStops.ReadSpecificMessage("BasicCommunication.OnSDLClose")
  if (result == false) then
    self:FailTestCase("Error: 'BasicCommunication.OnSDLClose' is not observed in smartDeviceLink.log.")
  end
end

--[[ Postconditions ]]
commonFunctions:newTestCasesGroup("Postconditions")
testCasesForPolicyTable:Restore_preloaded_pt()
function Test.Postcondition_Stop()
  StopSDL()
end
