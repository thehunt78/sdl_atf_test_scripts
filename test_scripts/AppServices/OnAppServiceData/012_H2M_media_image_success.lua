---------------------------------------------------------------------------------------------------
--  Precondition: 
--  1) Application with <appID> is registered on SDL.
--  2) Specific permissions are assigned for <appID> with OnAppServiceData
--  3) App sends putfile with an image
--  4) Application has published a MEDIA service
--  5) HMI is subscribed to OnAppServiceData
--
--  Steps:
--  1) Application sends a OnAppServiceData RPC notification with serviceType MEDIA including a mediaImage
--
--  Expected:
--  1) SDL forwards the OnAppServiceData notification to HMI with full media image path
---------------------------------------------------------------------------------------------------

--[[ Required Shared libraries ]]
local runner = require('user_modules/script_runner')
local common = require('test_scripts/AppServices/commonAppServices')
local SDLConfig = require('user_modules/shared_testcases/SmartDeviceLinkConfigurations')
local utils = require("user_modules/utils")

--[[ Test Configuration ]]
runner.testSettings.isSelfIncluded = false

--[[ Local Variables ]]
local deviceMAC = utils.getDeviceMAC()
local storagePath = config.pathToSDL .. SDLConfig:GetValue("AppStorageFolder") .. "/" .. tostring(config.application1.registerAppInterfaceParams.fullAppID .. "_" .. deviceMAC .. "/")


local putFileParams = {
  syncFileName = "icon_png.png",
  fileType ="GRAPHIC_PNG",
}

local result = { success = true, resultCode = "SUCCESS"}

local manifest = {
  serviceName = config.application1.registerAppInterfaceParams.appName,
  serviceType = "MEDIA",
  allowAppConsumers = true,
  rpcSpecVersion = config.application1.registerAppInterfaceParams.syncMsgVersion,
  mediaServiceManifest = {}
}

local appServiceData = {
  serviceType = manifest.serviceType,
  mediaServiceData = {
    mediaType = "MUSIC",
    mediaTitle = "Song name",
    mediaArtist = "Band name",
    mediaAlbum = "Album name",
    playlistName = "Good music",
    isExplicit = false,
    trackPlaybackProgress = 200,
    trackPlaybackDuration = 300,
    queuePlaybackProgress = 2200,
    queuePlaybackDuration = 4000,
    queueCurrentTrackNumber = 12,
    queueTotalTrackCount = 20,
    mediaImage = {
      value = "icon_png.png",
      imageType = "DYNAMIC"
    }
  }
}

local hmiServiceData = {
  serviceType = manifest.serviceType,
  mediaServiceData = {
    mediaType = "MUSIC",
    mediaTitle = "Song name",
    mediaArtist = "Band name",
    mediaAlbum = "Album name",
    playlistName = "Good music",
    isExplicit = false,
    trackPlaybackProgress = 200,
    trackPlaybackDuration = 300,
    queuePlaybackProgress = 2200,
    queuePlaybackDuration = 4000,
    queueCurrentTrackNumber = 12,
    queueTotalTrackCount = 20,
    mediaImage = {
      value = storagePath .. "icon_png.png",
      imageType = "DYNAMIC"
    }
  }
}

local rpc = {
  name = "OnAppServiceData",
  hmiName = "AppService.OnAppServiceData"
}

local expectedNotification = {
  serviceData = appServiceData
}

local hmiNotification = {
  serviceData = hmiServiceData
}

local function PTUfunc(tbl)
  tbl.policy_table.app_policies[common.getConfigAppParams(1).fullAppID] = common.getAppServiceProducerConfig(1);
end

--[[ Local Functions ]]
local function processRPCSuccess(self)
  local mobileSession = common.getMobileSession()
  local service_id = common.getAppServiceID(1)
  local notificationParams = expectedNotification
  local hmiNotificationParams = hmiNotification
  notificationParams.serviceData.serviceID = service_id
  hmiNotificationParams.serviceData.serviceID = service_id

  mobileSession:SendNotification(rpc.name, notificationParams)

  EXPECT_HMINOTIFICATION(rpc.hmiName, hmiNotificationParams)
end

--[[ Scenario ]]
runner.Title("Preconditions")
runner.Step("Clean environment", common.preconditions)
runner.Step("Start SDL, HMI, connect Mobile, start Session", common.start)
runner.Step("RAI", common.registerApp)
runner.Step("PTU", common.policyTableUpdate, { PTUfunc })
runner.Step("Activate App", common.activateApp)
runner.Step("Putfile Image", common.putFileInStorage, {1, putFileParams, result})
runner.Step("Publish App Service", common.publishMobileAppService, { manifest })

runner.Title("Test")
runner.Step("RPC " .. rpc.name .. "_resultCode_SUCCESS", processRPCSuccess)

runner.Title("Postconditions")
runner.Step("Stop SDL", common.postconditions)
