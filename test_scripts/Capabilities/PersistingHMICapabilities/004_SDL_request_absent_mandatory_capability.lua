---------------------------------------------------------------------------------------------------
-- Proposal:https://github.com/smartdevicelink/sdl_evolution/blob/master/proposals/0249-Persisting-HMI-Capabilities-specific-to-headunit.md
--
-- Description: Check that SDL sends all HMI capabilities request (VR/TTS/RC/UI etc)
--  in case "hmi_capabilities_cache.json" file doesn't exist
--
-- Preconditions:
-- 1) hmi_capabilities_cache.json file doesn't exist on file system
-- 2) SDL and HMI are started
-- Steps:
-- 1) HMI does not provide any HMI capabilities
-- 2) IGN_OFF/IGN_ON
-- SDL does:
--  a) sends all HMI capabilities request to HMI
---------------------------------------------------------------------------------------------------
--[[ Required Shared libraries ]]
local common = require('test_scripts/Capabilities/PersistingHMICapabilities/common')

--[[ Scenario ]]
common.Title("Preconditions")
common.Step("Clean environment", common.preconditions)
common.Step("Ignition on, Start SDL, HMI", common.start, { common.noResponseGetHMIParam() })
common.Step("Check that capability file doesn't exist", common.checkIfDoesNotExistCapabilityFile)
common.Step("Ignition off", common.ignitionOff)

common.Title("Test")
common.Step("Ignition on, SDL sends all HMI capabilities requests",
  common.start, { common.noResponseGetHMIParam() })

common.Title("Postconditions")
common.Step("Stop SDL", common.postconditions)