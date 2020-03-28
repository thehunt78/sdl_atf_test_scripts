---------------------------------------------------------------------------------------------------
-- Proposal:https://github.com/smartdevicelink/sdl_evolution/blob/master/proposals/0249-Persisting-HMI-Capabilities-specific-to-headunit.md
--
-- Description: Check that SDL is requested all capability in case HMI does not send BC.GetSystemInfo notification
--
-- Preconditions:
-- 1) hmi_capabilities_cache.json file doesn't exist on file system
-- 2) SDL and HMI are started
-- 3) HMI sends all HMI capabilities
-- 4) HMI sends GetSystemInfo with ccpu_version = "New_ccpu_version_1" to SDL
-- 5) SDL stored capability to "hmi_capabilities_cache.json" file in AppStorageFolder
-- 6) Ignition OFF/ON cycle performed
-- Steps:
-- 1) HMI does not send "BasicCommunication.GetSystemInfo" response
-- SDL does:
-- - a) sends all HMI capabilities request (VR/TTS/RC/UI etc)
---------------------------------------------------------------------------------------------------
--[[ Required Shared libraries ]]
local common = require('test_scripts/Capabilities/PersistingHMICapabilities/common')

--[[ Local Functions ]]
local function noResponseGetSystemInfo()
  local hmiCapabilities = common.getDefaultHMITable()
  hmiCapabilities.BasicCommunication.GetSystemInfo = nil
  return hmiCapabilities
end

--[[ Scenario ]]
common.Title("Preconditions")
common.Step("Clean environment", common.preconditions)
common.Step("Start SDL, HMI", common.start, { common.updateHMISystemInfo("version_1") })

common.Title("Test")
common.Step("Ignition off", common.ignitionOff)
common.Step("Ignition on, Start SDL, HMI does not send GetSystemInfo notification",
  common.start, { noResponseGetSystemInfo() })

common.Title("Postconditions")
common.Step("Stop SDL", common.postconditions)