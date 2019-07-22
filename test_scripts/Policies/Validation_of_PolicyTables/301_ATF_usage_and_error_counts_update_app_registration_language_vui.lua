---------------------------------------------------------------------------------------------
-- Requirement summary:
-- [RegisterAppInterface] "app_registration_language_vui" storage into PolicyTable
--
-- Check set value of "app_registration_language_vui" in Local Policy Table.
-- 1. Used preconditions:
-- Start default SDL
-- Add MobileApp to PreloadedPT
-- InitHMI register MobileApp
--
-- 2. Performed steps:
-- Stop SDL
-- Check LocalPT changes
--
-- Expected result:
-- SDL must: must write "languageDesired" value received via RegisterAppInterface into Local Policy Table
-- as "app_registration_language_vui" key value of "usage_and_error_counts"- >"app_level" - > <app id> section.
---------------------------------------------------------------------------------------------
--[[ General configuration parameters ]]
Test = require('connecttest')
local config = require('config')
config.defaultProtocolVersion = 2

--[[ Required Shared libraries ]]
local json = require("modules/json")
local commonFunctions = require ('user_modules/shared_testcases/commonFunctions')
local commonSteps = require ('user_modules/shared_testcases/commonSteps')
local testCasesForPolicyTableSnapshot = require ('user_modules/shared_testcases/testCasesForPolicyTableSnapshot')
local utils = require ('user_modules/utils')
require('cardinalities')
require('user_modules/AppTypes')

--[[ General precondition brfore ATF start]]
commonSteps:DeleteLogsFileAndPolicyTable()

--[[ Local Variables ]]
local PRELOADED_PT_FILE_NAME = "sdl_preloaded_pt.json"
local HMIAppId
local APP_ID = "0000001"
--local APP_LANGUAGE = "ES-MX"
local APP_LANGUAGE = "EN-US"

local basic_ptu_file = "files/ptu.json"
local ptu_first_app_registered = "files/ptu1app.json"

local TESTED_DATA = {
  preloaded = {
    policy_table = {
      app_policies = {
        [APP_ID] = {
          keep_context = false,
          steal_focus = false,
          priority = "NONE",
          default_hmi = "NONE",
          groups = {"Base-4"},
          RequestType = {
            "TRAFFIC_MESSAGE_CHANNEL",
            "PROPRIETARY",
            "HTTP",
            "QUERY_APPS"
          }
        }
      }
    }
  },
  expected = {
    policy_table = {
      usage_and_error_counts = {
        app_level = {
          [APP_ID] = {
            app_registration_language_vui = APP_LANGUAGE
          }
        }
      }
    }
  },
  application = {
    registerAppInterfaceParams = {
      syncMsgVersion = {
        majorVersion = 3,
        minorVersion = 0
      },
      appName = "Test Application",
      isMediaApplication = true,
      languageDesired = APP_LANGUAGE,
      hmiDisplayLanguageDesired = 'EN-US',
      appHMIType = { "MEDIA" },
      appID = APP_ID,
      deviceInfo = {
        os = "Android",
        carrier = "Megafon",
        firmwareRev = "Name: Linux, Version: 3.4.0-perf",
        osVersion = "4.4.2",
        maxNumberRFCOMMPorts = 1
      }
    }
  }
}
config.application1.registerAppInterfaceParams.fullAppID = APP_ID
config.application1.registerAppInterfaceParams.languageDesired = APP_LANGUAGE

local TestData = {
  path = config.pathToSDL .. "TestData",
  isExist = false,
  init = function(self)
    if not self.isExist then
      os.execute("mkdir ".. self.path)
      os.execute("echo 'List test data files files:' > " .. self.path .. "/index.txt")
      self.isExist = true
    end
  end,
  store = function(self, message, pathToFile, fileName)
    if self.isExist then
      local dataToWrite = message

      if pathToFile and fileName then
        os.execute(table.concat({"cp ", pathToFile, " ", self.path, "/", fileName}))
        dataToWrite = table.concat({dataToWrite, " File: ", fileName})
      end

      dataToWrite = dataToWrite .. "\n"
      local file = io.open(self.path .. "/index.txt", "a+")
      file:write(dataToWrite)
      file:close()
    end
  end,
  delete = function(self)
    if self.isExist then
      os.execute("rm -r -f " .. self.path)
      self.isExist = false
    end
  end,
  info = function(self)
    if self.isExist then
      commonFunctions:userPrint(35, "All test data generated by this test were stored to folder: " .. self.path)
    else
      commonFunctions:userPrint(35, "No test data were stored" )
    end
  end
}

local function constructPathToDatabase()
  if commonSteps:file_exists(config.pathToSDL .. "storage/policy.sqlite") then
    return config.pathToSDL .. "storage/policy.sqlite"
  elseif commonSteps:file_exists(config.pathToSDL .. "policy.sqlite") then
    return config.pathToSDL .. "policy.sqlite"
  else
    commonFunctions:userPrint(31, "policy.sqlite is not found" )
    return nil
  end
end

local function executeSqliteQuery(rawQueryString, dbFilePath)
  if not dbFilePath then
    return nil
  end
  local queryExecutionResult = {}
  local queryString = table.concat({"sqlite3 ", dbFilePath, " '", rawQueryString, "'"})
  local file = io.popen(queryString, 'r')
  if file then
    local index = 1
    for line in file:lines() do
      queryExecutionResult[index] = line
      index = index + 1
    end
    file:close()
    return queryExecutionResult
  else
    return nil
  end
end

local function isValuesCorrect(actualValues, expectedValues)
  if #actualValues ~= #expectedValues then
    return false
  end

  local tmpExpectedValues = {}
  for i = 1, #expectedValues do
    tmpExpectedValues[i] = expectedValues[i]
  end

  local isFound
  for j = 1, #actualValues do
    isFound = false
    for key, value in pairs(tmpExpectedValues) do
      if value == actualValues[j] then
        isFound = true
        tmpExpectedValues[key] = nil
        break
      end
    end
    if not isFound then
      return false
    end
  end
  if next(tmpExpectedValues) then
    return false
  end
  return true
end

function Test.checkLocalPT(checkTable)
  local expectedLocalPtValues
  local queryString
  local actualLocalPtValues
  local comparationResult
  local isTestPass = true
  for _, check in pairs(checkTable) do
    expectedLocalPtValues = check.expectedValues
    queryString = check.query
    actualLocalPtValues = executeSqliteQuery(queryString, constructPathToDatabase())
    if actualLocalPtValues then
      comparationResult = isValuesCorrect(actualLocalPtValues, expectedLocalPtValues)
      if not comparationResult then
        TestData:store(table.concat({"Test ", queryString, " failed: SDL has wrong values in LocalPT"}))
        TestData:store("ExpectedLocalPtValues")
        commonFunctions:userPrint(31, table.concat({"Test ", queryString, " failed: SDL has wrong values in LocalPT"}))
        commonFunctions:userPrint(35, "ExpectedLocalPtValues")
        for _, values in pairs(expectedLocalPtValues) do
          TestData:store(values)
          print(values)
        end
        TestData:store("ActualLocalPtValues")
        commonFunctions:userPrint(35, "ActualLocalPtValues")
        for _, values in pairs(actualLocalPtValues) do
          TestData:store(values)
          print(values)
        end
        isTestPass = false
      end
    else
      TestData:store("Test failed: Can't get data from LocalPT")
      commonFunctions:userPrint(31, "Test failed: Can't get data from LocalPT")
      isTestPass = false
    end
  end
  return isTestPass
end

function Test.backupPreloadedPT(backupPrefix)
  os.execute(table.concat({"cp ", config.pathToSDL, PRELOADED_PT_FILE_NAME, " ", config.pathToSDL, backupPrefix, PRELOADED_PT_FILE_NAME}))
end

function Test.restorePreloadedPT(backupPrefix)
  os.execute(table.concat({"mv ", config.pathToSDL, backupPrefix, PRELOADED_PT_FILE_NAME, " ", config.pathToSDL, PRELOADED_PT_FILE_NAME}))
end

local function updateJSON(pathToFile, updaters)
  local file = io.open(pathToFile, "r")
  local json_data = file:read("*a")
  file:close()

  local data = json.decode(json_data)
  if data then
    for _, updateFunc in pairs(updaters) do
      updateFunc(data)
    end
    -- Workaround. null value in lua table == not existing value. But in json file it has to be
    data.policy_table.functional_groupings["DataConsent-2"].rpcs = "tobedeletedinjsonfile"
    local dataToWrite = json.encode(data)
    dataToWrite = string.gsub(dataToWrite, "\"tobedeletedinjsonfile\"", "null")
    file = io.open(pathToFile, "w")
    file:write(dataToWrite)
    file:close()
  end

end

function Test.preparePreloadedPT()
  local preloadedUpdaters = {
    function(data)
      data.policy_table.app_policies[APP_ID] = TESTED_DATA.preloaded.policy_table.app_policies[APP_ID]
    end
  }
  updateJSON(config.pathToSDL .. PRELOADED_PT_FILE_NAME, preloadedUpdaters)
end

function Test:updatePolicyInDifferentSessions(PTName, appName, mobileSession)

  local iappID = self.applications[appName]
  local RequestIdGetURLS = self.hmiConnection:SendRequest("SDL.GetPolicyConfigurationData",
      { policyType = "module_config", property = "endpoints" })
  EXPECT_HMIRESPONSE(RequestIdGetURLS)
  :Do(function(_,_)
      self.hmiConnection:SendNotification("BasicCommunication.OnSystemRequest", { requestType = "PROPRIETARY", fileName = "PolicyTableUpdate"} )

      mobileSession:ExpectNotification("OnSystemRequest", { requestType = "PROPRIETARY" })
      :Do(function(_,_)
          local CorIdSystemRequest = mobileSession:SendRPC("SystemRequest",
            {
              fileName = "PolicyTableUpdate",
              requestType = "PROPRIETARY",
              appID = iappID
            },
            PTName)

          local systemRequestId
          EXPECT_HMICALL("BasicCommunication.SystemRequest")
          :Do(function(_,_data1)
              systemRequestId = _data1.id
              self.hmiConnection:SendNotification("SDL.OnReceivedPolicyUpdate", { policyfile = "/tmp/fs/mp/images/ivsu_cache/PolicyTableUpdate"} )
              local function to_run()
                self.hmiConnection:SendResponse(systemRequestId,"BasicCommunication.SystemRequest", "SUCCESS", {})
              end

              RUN_AFTER(to_run, 500)
            end)
          mobileSession:ExpectResponse(CorIdSystemRequest, { success = true, resultCode = "SUCCESS"})
        end)
    end)

  EXPECT_HMINOTIFICATION("SDL.OnStatusUpdate",
    {status = "UPDATING"}, {status = "UP_TO_DATE"}):Times(2)

end

local function activateAppInSpecificLevel(self, HMIAppID, hmi_level)
  local RequestId = self.hmiConnection:SendRequest("SDL.ActivateApp", { appID = HMIAppID, level = hmi_level})

  --hmi side: expect SDL.ActivateApp response
  EXPECT_HMIRESPONSE(RequestId)
  :Do(function(_,data)
      --In case when app is not allowed, it is needed to allow app
      if data.result.isSDLAllowed ~= true then
        --hmi side: sending SDL.GetUserFriendlyMessage request
        RequestId = self.hmiConnection:SendRequest("SDL.GetUserFriendlyMessage",
          {language = "EN-US", messageCodes = {"DataConsent"}})

        EXPECT_HMIRESPONSE(RequestId)
        :Do(function(_,_)

            --hmi side: send request SDL.OnAllowSDLFunctionality
            self.hmiConnection:SendNotification("SDL.OnAllowSDLFunctionality",
              {allowed = true, source = "GUI", device = {id = utils.getDeviceMAC(), name = utils.getDeviceName()}})

            --hmi side: expect BasicCommunication.ActivateApp request
            EXPECT_HMICALL("BasicCommunication.ActivateApp")
            :Do(function(_,data2)

                --hmi side: sending BasicCommunication.ActivateApp response
                self.hmiConnection:SendResponse(data2.id,"BasicCommunication.ActivateApp", "SUCCESS", {})
              end)
            -- :Times()
          end)
        EXPECT_NOTIFICATION("OnHMIStatus", {hmiLevel = hmi_level, systemContext = "MAIN" })
      end
    end)
end

local function addApplicationToPTJsonFile(basic_file, new_pt_file, app_name, app_)
  local pt = io.open(basic_file, "r")
  if pt == nil then
    error("PTU file not found")
  end
  local pt_string = pt:read("*all")
  pt:close()
  local pt_table = json.decode(pt_string)
  pt_table["policy_table"]["app_policies"][app_name] = app_
  -- Workaround. null value in lua table == not existing value. But in json file it has to be
  pt_table["policy_table"]["functional_groupings"]["DataConsent-2"]["rpcs"] = "tobedeletedinjsonfile"
  local pt_json = json.encode(pt_table)
  pt_json = string.gsub(pt_json, "\"tobedeletedinjsonfile\"", "null")
  local new_ptu = io.open(new_pt_file, "w")

  new_ptu:write(pt_json)
  new_ptu:close()
end

local function PrepareJsonPTU1(name, new_ptufile)
  local json_app = [[ {
    "keep_context": false,
    "steal_focus": false,
    "priority": "NONE",
    "default_hmi": "NONE",
    "groups": [
    "Base-4"
    ],
    "RequestType":[
    "TRAFFIC_MESSAGE_CHANNEL",
    "PROPRIETARY",
    "HTTP",
    "QUERY_APPS"
    ]
  }]]
  local app = json.decode(json_app)
  addApplicationToPTJsonFile(basic_ptu_file, new_ptufile, name, app)
end

--[[ Test ]]
commonFunctions:newTestCasesGroup("Test")
function Test.PreparePTData()
  PrepareJsonPTU1(APP_ID, ptu_first_app_registered)
end

function Test:ActivateApp()
  HMIAppId = self.applications[config.application1.registerAppInterfaceParams.appName]
  activateAppInSpecificLevel(self,HMIAppId,"FULL")
end

function Test:TestStep_Check_app_registration_language_vui_PTS()
  local app_registration_language_vui = testCasesForPolicyTableSnapshot:get_data_from_PTS("usage_and_error_counts.app_level.0000001.app_registration_language_vui")

  if (app_registration_language_vui ~= APP_LANGUAGE) then
    self:FailTestCase("app_registration_language_vui is not as Expected: "..APP_LANGUAGE..". Real: "..app_registration_language_vui)
  end
end

function Test.Wait()
  os.execute("sleep 3")
end

function Test:CheckLocalPTBeforeUpdate()
  local checks = {
    {
      query = table.concat(
        {
          'select app_registration_language_vui from app_level where application_id = "',
          APP_ID,
          '"'
        }),
      expectedValues = {table.concat(
          {
            TESTED_DATA.expected.policy_table.usage_and_error_counts.app_level[APP_ID].app_registration_language_vui, ""
          })
      }
    }
  }
  if not self.checkLocalPT(checks) then
    self:FailTestCase("SDL has wrong values in LocalPT")
  end
end

function Test:InitiatePTUForGetSnapshot()
  self:updatePolicyInDifferentSessions(ptu_first_app_registered,
    config.application1.registerAppInterfaceParams.appName,
    self.mobileSession)
  -- updatePolicyInDifferentSessions(Test, ptu_first_app_registered,
  -- TESTED_DATA.application.registerAppInterfaceParams.appName, self.mobileSession)
end

function Test.Wait()
  os.execute("sleep 3")
end

function Test:CheckPTUinLocalPT()
  local checks = {
    {
      query = table.concat(
        {
          'select app_registration_language_vui from app_level where application_id = "',
          APP_ID,
          '"'
        }),
      expectedValues = {table.concat(
          {
            TESTED_DATA.expected.policy_table.usage_and_error_counts.app_level[APP_ID].app_registration_language_vui, ""
          })
      }
    }
  }
  if not self.checkLocalPT(checks) then
    self:FailTestCase("SDL has wrong values in LocalPT")
  end
end

--[[ Postconditions ]]
commonFunctions:newTestCasesGroup("Postconditions")

function Test.Postcondition()
  Test.restorePreloadedPT("backup_")
  TestData:info()
end

--[[ Postconditions ]]
commonFunctions:newTestCasesGroup("Postconditions")
function Test.Postcondition_Stop()
  StopSDL()
end

return Test
