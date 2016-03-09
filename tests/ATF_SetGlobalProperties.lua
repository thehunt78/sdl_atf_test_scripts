-- ATF verstion: 2.2

Test = require('connecttest')
require('cardinalities')
local events = require('events')
local mobile_session = require('mobile_session')
local mobile  = require('mobile_connection')
local tcp = require('tcp_connection')
local file_connection  = require('file_connection')


---------------------------------------------------------------------------------------------
-----------------------------Required Shared Libraries---------------------------------------
---------------------------------------------------------------------------------------------
require('user_modules/AppTypes')
local commonTestCases = require('user_modules/shared_testcases/commonTestCases')
local commonSteps = require('user_modules/shared_testcases/commonSteps')
local commonFunctions = require('user_modules/shared_testcases/commonFunctions')
APIName = "SetGlobalProperties" -- use for above required scripts.
strMaxLengthFileName255 = string.rep("a", 251)  .. ".png" -- set max length file name

local iTimeout = 5000
local strAppFolder = config.pathToSDL .. "storage/" ..config.application1.registerAppInterfaceParams.appID.. "_" .. config.deviceMAC.. "/"


---------------------------------------------------------------------------------------------
---------------------------------------Common functions--------------------------------------
---------------------------------------------------------------------------------------------

function DelayedExp(time)
  local event = events.Event()
  event.matches = function(self, e) return self == e end
  EXPECT_EVENT(event, "Delayed event")
  	:Timeout(time+1000)
  RUN_AFTER(function()
              RAISE_EVENT(event, event)
            end, time)
end


function copy_table(t)
  local t2 = {}
  for k,v in pairs(t) do
    t2[k] = v
  end
  return t2
end
---------------------------------------------------------------------------------------------
-------------------------------------------Preconditions-------------------------------------
---------------------------------------------------------------------------------------------
	
	--1. Activate application
	commonSteps:ActivationApp()

	--2
	--Description: Update Policy with SetGlobalProperties API in FULL, LIMITED, BACKGROUND is allowed
	function Test:Precondition_PolicyUpdate()
		--hmi side: sending SDL.GetURLS request
		local RequestIdGetURLS = self.hmiConnection:SendRequest("SDL.GetURLS", { service = 7 })
		
		--hmi side: expect SDL.GetURLS response from HMI
		EXPECT_HMIRESPONSE(RequestIdGetURLS,{result = {code = 0, method = "SDL.GetURLS", urls = {{url = "http://policies.telematics.ford.com/api/policies"}}}})
		:Do(function(_,data)
			--print("SDL.GetURLS response is received")
			--hmi side: sending BasicCommunication.OnSystemRequest request to SDL
			self.hmiConnection:SendNotification("BasicCommunication.OnSystemRequest",
				{
					requestType = "PROPRIETARY",
					fileName = "filename"
				}
			)
			--mobile side: expect OnSystemRequest notification 
			EXPECT_NOTIFICATION("OnSystemRequest", { requestType = "PROPRIETARY" })
			:Do(function(_,data)
				--print("OnSystemRequest notification is received")
				--mobile side: sending SystemRequest request 
				local CorIdSystemRequest = self.mobileSession:SendRPC("SystemRequest",
					{
						fileName = "PolicyTableUpdate",
						requestType = "PROPRIETARY"
					},
				"files/ptu_general.json")
				
				local systemRequestId
				--hmi side: expect SystemRequest request
				EXPECT_HMICALL("BasicCommunication.SystemRequest")
				:Do(function(_,data)
					systemRequestId = data.id
					--print("BasicCommunication.SystemRequest is received")
					
					--hmi side: sending BasicCommunication.OnSystemRequest request to SDL
					self.hmiConnection:SendNotification("SDL.OnReceivedPolicyUpdate",
						{
							policyfile = "/tmp/fs/mp/images/ivsu_cache/PolicyTableUpdate"
						}
					)
					function to_run()
						--hmi side: sending SystemRequest response
						self.hmiConnection:SendResponse(systemRequestId,"BasicCommunication.SystemRequest", "SUCCESS", {})
					end
					
					RUN_AFTER(to_run, 500)
				end)
				
				--hmi side: expect SDL.OnStatusUpdate
				EXPECT_HMINOTIFICATION("SDL.OnStatusUpdate")
				:ValidIf(function(exp,data)
					if 
						exp.occurences == 1 and
						data.params.status == "UP_TO_DATE" then
							return true
					elseif
						exp.occurences == 1 and
						data.params.status == "UPDATING" then
							return true
					elseif
						exp.occurences == 2 and
						data.params.status == "UP_TO_DATE" then
							return true
					else 
						if 
							exp.occurences == 1 then
								print ("\27[31m SDL.OnStatusUpdate came with wrong values. Expected in first occurrences status 'UP_TO_DATE' or 'UPDATING', got '" .. tostring(data.params.status) .. "' \27[0m")
						elseif exp.occurences == 2 then
								print ("\27[31m SDL.OnStatusUpdate came with wrong values. Expected in second occurrences status 'UP_TO_DATE', got '" .. tostring(data.params.status) .. "' \27[0m")
						end
						return false
					end
				end)
				:Times(Between(1,2))
				
				--mobile side: expect SystemRequest response
				EXPECT_RESPONSE(CorIdSystemRequest, { success = true, resultCode = "SUCCESS"})
				:Do(function(_,data)
					--print("SystemRequest is received")
					--hmi side: sending SDL.GetUserFriendlyMessage request to SDL
					local RequestIdGetUserFriendlyMessage = self.hmiConnection:SendRequest("SDL.GetUserFriendlyMessage", {language = "EN-US", messageCodes = {"StatusUpToDate"}})
					
					--hmi side: expect SDL.GetUserFriendlyMessage response
					-- TODO: update after resolving APPLINK-16094 EXPECT_HMIRESPONSE(RequestIdGetUserFriendlyMessage,{result = {code = 0, method = "SDL.GetUserFriendlyMessage", messages = {{line1 = "Up-To-Date", messageCode = "StatusUpToDate", textBody = "Up-To-Date"}}}})
					EXPECT_HMIRESPONSE(RequestIdGetUserFriendlyMessage)
					:Do(function(_,data)
						print("SDL.GetUserFriendlyMessage is received")			
					end)
				end)
				
			end)
		end)
	end

	--3. PutFiles	
	commonSteps:PutFile("PutFile_MinLength", "a")
	commonSteps:PutFile("PutFile_action.png", "action.png")	
	commonSteps:PutFile("PutFile_MaxLength_255Characters", strMaxLengthFileName255)	
	commonSteps:PutFile("Putfile_SpaceBefore", " SpaceBefore")
	
---------------------------------------------------------------------------------------------
-----------------------------------------I TEST BLOCK----------------------------------------
--CommonRequestCheck: Check of mandatory/conditional request's parameters (mobile protocol)--
---------------------------------------------------------------------------------------------

--Begin test suit CommonRequestCheck
--Description:
	-- request with all parameters
	-- request with only mandatory parameters
	-- request with all combinations of conditional-mandatory parameters (if exist)
	-- request with one by one conditional parameters (each case - one conditional parameter)
	-- request with missing mandatory parameters one by one (each case - missing one mandatory parameter)
	-- request with all parameters are missing
	-- request with fake parameters (fake - not from protocol, from another request)
	-- request is sent with invalid JSON structure
	-- different conditions of correlationID parameter (invalid, several the same etc.)


	--Requirement id in JAMA: SDLAQ-CRS-11

	--Verification criteria:
		--SetGlobalProperties sets-up global properties for the current application.
		--SDL sets-up default values for "vrHelpTitle" and "vrHelp" parameters if they both don't exist in request.
		--VRHelpTitle and VRHelpItems are sent with SetGlobalProperties request for setting app�s help items. HMI will open by itself a top level HelpList as a result of VR activation.


	--Begin test case CommonRequestCheck.1
	--Description: Check request with all parameters

		function Test:SetGlobalProperties_PositiveCase_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[[ TODO: update after resolving APPLINK-16052
						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case CommonRequestCheck.1
	-----------------------------------------------------------------------------------------


	--Begin test case CommonRequestCheck.2
	--Description: Check request with only mandatory parameters

		--There is no mandatory parameter.
		
	--End test case CommonRequestCheck.2
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.3
	--Description: Check request with one by one conditional parameters: vrHelpTitle

		function Test:SetGlobalProperties_WithOnlyOneParameter_vrHelpTitle_REJECTED()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				vrHelpTitle = "VR help title"
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "REJECTED"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case CommonRequestCheck.3
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.4
	--Description: Check request with one by one conditional parameters: menuTitle

		function Test:SetGlobalProperties_WithOnlyOneParameter_menuTitle_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title"
			})
		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title"
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case CommonRequestCheck.4
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.5
	--Description: Check request with one by one conditional parameters: menuIcon

		--Verification criteria: Set optional icon to draw on an app menu button (for certain touchscreen platforms).

		function Test:SetGlobalProperties_WithOnlyOneParameter_menuIcon_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				}
			})
		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case CommonRequestCheck.5
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.6
	--Description: Check request with one by one conditional parameters: keyboardProperties

		function Test:SetGlobalProperties_WithOnlyOneParameter_keyboardProperties_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[[ TODO: update after resolving APPLINK-16047
					limitedCharacterList = 
					{
						"a"
					},]]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case CommonRequestCheck.6
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.7
	--Description: Check request with one by one conditional parameters: vrHelp


		function Test:SetGlobalProperties_WithOnlyOneParameter_vrHelp_REJECTED()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "REJECTED"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case CommonRequestCheck.7
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.8
	--Description: Check request with one by one conditional parameters: helpPrompt

		function Test:SetGlobalProperties_WithOnlyOneParameter_helpPrompt_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
				:Timeout(iTimeout)
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
							{
								vrHelpTitle = config.application1.registerAppInterfaceParams.appName
							})
				:Timeout(iTimeout)
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case CommonRequestCheck.8
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.9
	--Description: Check request with one by one conditional parameters: timeoutPrompt

		function Test:SetGlobalProperties_WithOnlyOneParameter_timeoutPrompt_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
													{
														timeoutPrompt = 
														{
															{
																text = "Timeout prompt",
																type = "TEXT"
															}
														}
													})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
							{
								timeoutPrompt = 
								{
									{
										text = "Timeout prompt",
										type = "TEXT"
									}
								}
							})
				:Timeout(iTimeout)
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
							{
								vrHelpTitle = config.application1.registerAppInterfaceParams.appName
							})
				:Timeout(iTimeout)
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)


			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
				:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case CommonRequestCheck.9
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.10
	--Description: Check request with all parameters are missing

		--Requirement id in JAMA: SDLAQ-CRS-11, SDLAQ-CRS-383

		--Verification criteria: SDL response INVALID_DATA in case mandatory parameters are not provided

		commonTestCases:VerifyRequestIsMissedAllParameters()
		
	--End test case CommonRequestCheck.10
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.11
	--Description: Check request with fake parameters

		--Requirement id in JAMA/or Jira ID: APPLINK-4518

		--Verification criteria: According to xml tests by Ford team all fake parameters should be ignored by SDL...
		
		--Check fake parameter
		function Test:SetGlobalProperties_FakeParameters_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				fakeparameter = "fakeparameters",
				timeoutPrompt = 
				{
					{
						fakeparameter1 = "fakeparameter",
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						fakeparameter2 = "fakeparameter",
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					fakeparameter3 = "fakeparameter",
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						fakeparameter4 = "fakeparameter",
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					fakeparameter5 = "fakeparameter",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})



			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:ValidIf(function(_,data)
						if data.params.fakeParameter or
							data.params.timeoutPrompt[1].fakeParameter1 or
							data.params.helpPrompt[1].fakeParameter4
						then
								print(" SDL re-sends fakeParameters to HMI in UI.SetAppIcon request")
								return false
						else 
							return true
						end
					end)
					
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

	
	
			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:ValidIf(function(_,data)
						if data.params.fakeParameter or
							data.params.vrHelp[1].fakeParameter2 or
							data.params.menuIcon.fakeParameter3 or
							data.params.keyboardProperties.fakeParameter5
						then
								print(" SDL re-sends fakeParameters to HMI in UI.SetAppIcon request")
								return false
						else 
							return true
						end
					end)
					
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)			

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

		--Check request with parameter of other request
		function Test:SetGlobalProperties_ParametersAnotherAPI_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				syncFileName = "action.png",
				timeoutPrompt = 
				{
					{
						syncFileName = "action.png",
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						syncFileName = "action.png",
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					syncFileName = "action.png",
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						syncFileName = "action.png",
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					syncFileName = "action.png",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})


			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:ValidIf(function(_,data)
						if data.params.syncFileName or
							data.params.timeoutPrompt[1].syncFileName or
							data.params.helpPrompt[1].syncFileName
						then
								print(" SDL re-sends syncFileName parameter to HMI in UI.SetAppIcon request")
								return false
						else 
							return true
						end
					end)
					
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)
			
			
			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:ValidIf(function(_,data) 
						if data.params.syncFileName or
							data.params.vrHelp[1].syncFileName or
							data.params.menuIcon.syncFileName or
							data.params.keyboardProperties.syncFileName
						then
								print(" SDL re-sends syncFileName parameter to HMI in UI.SetAppIcon request")
								return false
						else 
							return true
						end
					end)
					
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)			

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

		
	--End test case CommonRequestCheck.11
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.12
	--Description: Check request is sent with invalid JSON structure

		--Requirement id in JAMA: SDLAQ-CRS-11, SDLAQ-CRS-383

		--Verification criteria: SDL responses INVALID_DATA
		
		--change ":" by "="
		local Payload = '{"helpPrompt"=[{"type":"TEXT","text":"Help prompt 1"},{"type":"TEXT","text":"Second help prompt"}],"timeoutPrompt":{{"type":"TEXT","text":"First timeout prompt"},{"type":"TEXT","text":"Another timeout prompt"}}}'
		
		commonTestCases:VerifyInvalidJsonRequest(12, Payload)

	--End test case CommonRequestCheck.12
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.13
	--Description: Check missing helpPrompt parameter is not mandatory

		function Test:SetGlobalProperties_helpPrompt_isMissing_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case CommonRequestCheck.13
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.14
	--Description: Check missing timeoutPrompt parameter is not mandatory

		function Test:SetGlobalProperties_timeoutPrompt_isMissing_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case CommonRequestCheck.14
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.15
	--Description: Check missing vrHelpTitle parameter is not mandatory

		--Requirement id in JAMA: SDLAQ-CRS-389

		--Verification criteria: "3. SDL rejects the request with REJECTED resultCode when vrHelpTitle is omitted and the vrHelpItems are provided at the same time."

		function Test:SetGlobalProperties_vrHelpTitle_isMissing_REJECTED()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "REJECTED"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case CommonRequestCheck.15
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.16
	--Description: Check vrHelp parameter is missed

		--Requirement id in JAMA: SDLAQ-CRS-389

		--Verification criteria: SDL rejects the request with REJECTED resultCode when vrHelpItems are omitted and the vrHelpTitle is provided at the same time.

		function Test:SetGlobalProperties_vrHelp_isMissing_REJECTED()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "REJECTED"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case CommonRequestCheck.16
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.17
	--Description: Check missing menuTitle parameter is not mandatory

		function Test:SetGlobalProperties_menuTitle_isMissing_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				},
				vrHelpTitle = "VR help title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case CommonRequestCheck.17
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.18
	--Description: Check missing menuIcon parameter is not mandatory

		function Test:SetGlobalProperties_menuIcon_isMissing_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				},
				vrHelpTitle = "VR help title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case CommonRequestCheck.18
	-----------------------------------------------------------------------------------------

	--Begin test case CommonRequestCheck.19
	--Description: Check missing keyboardProperties parameter is not mandatory

		function Test:SetGlobalProperties_keyboardProperties_isMissing_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title"
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case CommonRequestCheck.19
	-----------------------------------------------------------------------------------------


	--Begin test case CommonRequestCheck.20
	--Description: check request with correlation Id is duplicated

		--Requirement id in JAMA/or Jira ID: APPLINK-14293

		--Verification criteria: The response comes with SUCCESS result code.

		function Test:SetGlobalProperties_CorrelationID_Duplicated_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt duplicate",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties")
			:Times(2)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties")
			:Times(2)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)
			:Do(function(exp,data)
				if exp.occurences == 1 then 
					local msg = 
						{
							serviceType      = 7,
							frameInfo        = 0,
							rpcType          = 0,
							rpcFunctionId    = 3, --SetGlobalPropertiesID  
							rpcCorrelationId = cid,
							payload          = '{"vrHelp":[{"image":{"imageType":"DYNAMIC","value":"action.png"},"position":1,"text":"VR help item"}],"helpPrompt":[{"type":"TEXT","text":"Help prompt"}],"menuTitle":"Menu Title","vrHelpTitle":"VR help title","timeoutPrompt":[{"type":"TEXT","text":"Timeout prompt duplicate"}],"menuIcon":{"imageType":"DYNAMIC","value":"action.png"}}'
						}
			
					self.mobileSession:Send(msg)
				end

				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})					
				
			end)
				

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Times(2)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(2)
		end

	--End test case CommonRequestCheck.20
	-----------------------------------------------------------------------------------------



---------------------------------------------------------------------------------------------
----------------------------------------II TEST BLOCK----------------------------------------
----------------------------------------Positive cases---------------------------------------
---------------------------------------------------------------------------------------------

	--Precondition 2: Put files
	commonSteps:PutFile("Precondition_Putfile_SpaceAfter", "SpaceAfter ")
	commonSteps:PutFile("Precondition_Putfile_SpaceInTheMiddle", "Space In The Middle")
	commonSteps:PutFile("Precondition_Putfile_SpacesEveryWhere", " Space Every Where ")
	
	--=================================================================================--
	--------------------------------Positive request check-------------------------------
	--=================================================================================--

--Begin test case PositiveResponseCheck.1
--Description: Check positive request

	--Requirement id in JAMA: SDLAQ-CRS-11, SDLAQ-CRS-382

	--Verification criteria: SDL response SUCCESS in case the request is executed successfully.

	--Begin test case PositiveResponseCheck.1.1
	--Description: Check helpPrompt parameter is lower bound

		function Test:SetGlobalProperties_helpPrompt_Array_minsize_1_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.1
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.2
	--Description: Check helpPrompt parameter is upper bound

		function Test:SetGlobalProperties_helpPrompt_Array_maxsize_100_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt_001",
						type = "TEXT"
					},
					{
						text = "Help prompt_002",
						type = "TEXT"
					},
					{
						text = "Help prompt_003",
						type = "TEXT"
					},
					{
						text = "Help prompt_004",
						type = "TEXT"
					},
					{
						text = "Help prompt_005",
						type = "TEXT"
					},
					{
						text = "Help prompt_006",
						type = "TEXT"
					},
					{
						text = "Help prompt_007",
						type = "TEXT"
					},
					{
						text = "Help prompt_008",
						type = "TEXT"
					},
					{
						text = "Help prompt_009",
						type = "TEXT"
					},
					{
						text = "Help prompt_010",
						type = "TEXT"
					},
					{
						text = "Help prompt_011",
						type = "TEXT"
					},
					{
						text = "Help prompt_012",
						type = "TEXT"
					},
					{
						text = "Help prompt_013",
						type = "TEXT"
					},
					{
						text = "Help prompt_014",
						type = "TEXT"
					},
					{
						text = "Help prompt_015",
						type = "TEXT"
					},
					{
						text = "Help prompt_016",
						type = "TEXT"
					},
					{
						text = "Help prompt_017",
						type = "TEXT"
					},
					{
						text = "Help prompt_018",
						type = "TEXT"
					},
					{
						text = "Help prompt_019",
						type = "TEXT"
					},
					{
						text = "Help prompt_020",
						type = "TEXT"
					},
					{
						text = "Help prompt_021",
						type = "TEXT"
					},
					{
						text = "Help prompt_022",
						type = "TEXT"
					},
					{
						text = "Help prompt_023",
						type = "TEXT"
					},
					{
						text = "Help prompt_024",
						type = "TEXT"
					},
					{
						text = "Help prompt_025",
						type = "TEXT"
					},
					{
						text = "Help prompt_026",
						type = "TEXT"
					},
					{
						text = "Help prompt_027",
						type = "TEXT"
					},
					{
						text = "Help prompt_028",
						type = "TEXT"
					},
					{
						text = "Help prompt_029",
						type = "TEXT"
					},
					{
						text = "Help prompt_030",
						type = "TEXT"
					},
					{
						text = "Help prompt_031",
						type = "TEXT"
					},
					{
						text = "Help prompt_032",
						type = "TEXT"
					},
					{
						text = "Help prompt_033",
						type = "TEXT"
					},
					{
						text = "Help prompt_034",
						type = "TEXT"
					},
					{
						text = "Help prompt_035",
						type = "TEXT"
					},
					{
						text = "Help prompt_036",
						type = "TEXT"
					},
					{
						text = "Help prompt_037",
						type = "TEXT"
					},
					{
						text = "Help prompt_038",
						type = "TEXT"
					},
					{
						text = "Help prompt_039",
						type = "TEXT"
					},
					{
						text = "Help prompt_040",
						type = "TEXT"
					},
					{
						text = "Help prompt_041",
						type = "TEXT"
					},
					{
						text = "Help prompt_042",
						type = "TEXT"
					},
					{
						text = "Help prompt_043",
						type = "TEXT"
					},
					{
						text = "Help prompt_044",
						type = "TEXT"
					},
					{
						text = "Help prompt_045",
						type = "TEXT"
					},
					{
						text = "Help prompt_046",
						type = "TEXT"
					},
					{
						text = "Help prompt_047",
						type = "TEXT"
					},
					{
						text = "Help prompt_048",
						type = "TEXT"
					},
					{
						text = "Help prompt_049",
						type = "TEXT"
					},
					{
						text = "Help prompt_050",
						type = "TEXT"
					},
					{
						text = "Help prompt_051",
						type = "TEXT"
					},
					{
						text = "Help prompt_052",
						type = "TEXT"
					},
					{
						text = "Help prompt_053",
						type = "TEXT"
					},
					{
						text = "Help prompt_054",
						type = "TEXT"
					},
					{
						text = "Help prompt_055",
						type = "TEXT"
					},
					{
						text = "Help prompt_056",
						type = "TEXT"
					},
					{
						text = "Help prompt_057",
						type = "TEXT"
					},
					{
						text = "Help prompt_058",
						type = "TEXT"
					},
					{
						text = "Help prompt_059",
						type = "TEXT"
					},
					{
						text = "Help prompt_060",
						type = "TEXT"
					},
					{
						text = "Help prompt_061",
						type = "TEXT"
					},
					{
						text = "Help prompt_062",
						type = "TEXT"
					},
					{
						text = "Help prompt_063",
						type = "TEXT"
					},
					{
						text = "Help prompt_064",
						type = "TEXT"
					},
					{
						text = "Help prompt_065",
						type = "TEXT"
					},
					{
						text = "Help prompt_066",
						type = "TEXT"
					},
					{
						text = "Help prompt_067",
						type = "TEXT"
					},
					{
						text = "Help prompt_068",
						type = "TEXT"
					},
					{
						text = "Help prompt_069",
						type = "TEXT"
					},
					{
						text = "Help prompt_070",
						type = "TEXT"
					},
					{
						text = "Help prompt_071",
						type = "TEXT"
					},
					{
						text = "Help prompt_072",
						type = "TEXT"
					},
					{
						text = "Help prompt_073",
						type = "TEXT"
					},
					{
						text = "Help prompt_074",
						type = "TEXT"
					},
					{
						text = "Help prompt_075",
						type = "TEXT"
					},
					{
						text = "Help prompt_076",
						type = "TEXT"
					},
					{
						text = "Help prompt_077",
						type = "TEXT"
					},
					{
						text = "Help prompt_078",
						type = "TEXT"
					},
					{
						text = "Help prompt_079",
						type = "TEXT"
					},
					{
						text = "Help prompt_080",
						type = "TEXT"
					},
					{
						text = "Help prompt_081",
						type = "TEXT"
					},
					{
						text = "Help prompt_082",
						type = "TEXT"
					},
					{
						text = "Help prompt_083",
						type = "TEXT"
					},
					{
						text = "Help prompt_084",
						type = "TEXT"
					},
					{
						text = "Help prompt_085",
						type = "TEXT"
					},
					{
						text = "Help prompt_086",
						type = "TEXT"
					},
					{
						text = "Help prompt_087",
						type = "TEXT"
					},
					{
						text = "Help prompt_088",
						type = "TEXT"
					},
					{
						text = "Help prompt_089",
						type = "TEXT"
					},
					{
						text = "Help prompt_090",
						type = "TEXT"
					},
					{
						text = "Help prompt_091",
						type = "TEXT"
					},
					{
						text = "Help prompt_092",
						type = "TEXT"
					},
					{
						text = "Help prompt_093",
						type = "TEXT"
					},
					{
						text = "Help prompt_094",
						type = "TEXT"
					},
					{
						text = "Help prompt_095",
						type = "TEXT"
					},
					{
						text = "Help prompt_096",
						type = "TEXT"
					},
					{
						text = "Help prompt_097",
						type = "TEXT"
					},
					{
						text = "Help prompt_098",
						type = "TEXT"
					},
					{
						text = "Help prompt_099",
						type = "TEXT"
					},
					{
						text = "Help prompt_100",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt_001",
						type = "TEXT"
					},
					{
						text = "Help prompt_002",
						type = "TEXT"
					},
					{
						text = "Help prompt_003",
						type = "TEXT"
					},
					{
						text = "Help prompt_004",
						type = "TEXT"
					},
					{
						text = "Help prompt_005",
						type = "TEXT"
					},
					{
						text = "Help prompt_006",
						type = "TEXT"
					},
					{
						text = "Help prompt_007",
						type = "TEXT"
					},
					{
						text = "Help prompt_008",
						type = "TEXT"
					},
					{
						text = "Help prompt_009",
						type = "TEXT"
					},
					{
						text = "Help prompt_010",
						type = "TEXT"
					},
					{
						text = "Help prompt_011",
						type = "TEXT"
					},
					{
						text = "Help prompt_012",
						type = "TEXT"
					},
					{
						text = "Help prompt_013",
						type = "TEXT"
					},
					{
						text = "Help prompt_014",
						type = "TEXT"
					},
					{
						text = "Help prompt_015",
						type = "TEXT"
					},
					{
						text = "Help prompt_016",
						type = "TEXT"
					},
					{
						text = "Help prompt_017",
						type = "TEXT"
					},
					{
						text = "Help prompt_018",
						type = "TEXT"
					},
					{
						text = "Help prompt_019",
						type = "TEXT"
					},
					{
						text = "Help prompt_020",
						type = "TEXT"
					},
					{
						text = "Help prompt_021",
						type = "TEXT"
					},
					{
						text = "Help prompt_022",
						type = "TEXT"
					},
					{
						text = "Help prompt_023",
						type = "TEXT"
					},
					{
						text = "Help prompt_024",
						type = "TEXT"
					},
					{
						text = "Help prompt_025",
						type = "TEXT"
					},
					{
						text = "Help prompt_026",
						type = "TEXT"
					},
					{
						text = "Help prompt_027",
						type = "TEXT"
					},
					{
						text = "Help prompt_028",
						type = "TEXT"
					},
					{
						text = "Help prompt_029",
						type = "TEXT"
					},
					{
						text = "Help prompt_030",
						type = "TEXT"
					},
					{
						text = "Help prompt_031",
						type = "TEXT"
					},
					{
						text = "Help prompt_032",
						type = "TEXT"
					},
					{
						text = "Help prompt_033",
						type = "TEXT"
					},
					{
						text = "Help prompt_034",
						type = "TEXT"
					},
					{
						text = "Help prompt_035",
						type = "TEXT"
					},
					{
						text = "Help prompt_036",
						type = "TEXT"
					},
					{
						text = "Help prompt_037",
						type = "TEXT"
					},
					{
						text = "Help prompt_038",
						type = "TEXT"
					},
					{
						text = "Help prompt_039",
						type = "TEXT"
					},
					{
						text = "Help prompt_040",
						type = "TEXT"
					},
					{
						text = "Help prompt_041",
						type = "TEXT"
					},
					{
						text = "Help prompt_042",
						type = "TEXT"
					},
					{
						text = "Help prompt_043",
						type = "TEXT"
					},
					{
						text = "Help prompt_044",
						type = "TEXT"
					},
					{
						text = "Help prompt_045",
						type = "TEXT"
					},
					{
						text = "Help prompt_046",
						type = "TEXT"
					},
					{
						text = "Help prompt_047",
						type = "TEXT"
					},
					{
						text = "Help prompt_048",
						type = "TEXT"
					},
					{
						text = "Help prompt_049",
						type = "TEXT"
					},
					{
						text = "Help prompt_050",
						type = "TEXT"
					},
					{
						text = "Help prompt_051",
						type = "TEXT"
					},
					{
						text = "Help prompt_052",
						type = "TEXT"
					},
					{
						text = "Help prompt_053",
						type = "TEXT"
					},
					{
						text = "Help prompt_054",
						type = "TEXT"
					},
					{
						text = "Help prompt_055",
						type = "TEXT"
					},
					{
						text = "Help prompt_056",
						type = "TEXT"
					},
					{
						text = "Help prompt_057",
						type = "TEXT"
					},
					{
						text = "Help prompt_058",
						type = "TEXT"
					},
					{
						text = "Help prompt_059",
						type = "TEXT"
					},
					{
						text = "Help prompt_060",
						type = "TEXT"
					},
					{
						text = "Help prompt_061",
						type = "TEXT"
					},
					{
						text = "Help prompt_062",
						type = "TEXT"
					},
					{
						text = "Help prompt_063",
						type = "TEXT"
					},
					{
						text = "Help prompt_064",
						type = "TEXT"
					},
					{
						text = "Help prompt_065",
						type = "TEXT"
					},
					{
						text = "Help prompt_066",
						type = "TEXT"
					},
					{
						text = "Help prompt_067",
						type = "TEXT"
					},
					{
						text = "Help prompt_068",
						type = "TEXT"
					},
					{
						text = "Help prompt_069",
						type = "TEXT"
					},
					{
						text = "Help prompt_070",
						type = "TEXT"
					},
					{
						text = "Help prompt_071",
						type = "TEXT"
					},
					{
						text = "Help prompt_072",
						type = "TEXT"
					},
					{
						text = "Help prompt_073",
						type = "TEXT"
					},
					{
						text = "Help prompt_074",
						type = "TEXT"
					},
					{
						text = "Help prompt_075",
						type = "TEXT"
					},
					{
						text = "Help prompt_076",
						type = "TEXT"
					},
					{
						text = "Help prompt_077",
						type = "TEXT"
					},
					{
						text = "Help prompt_078",
						type = "TEXT"
					},
					{
						text = "Help prompt_079",
						type = "TEXT"
					},
					{
						text = "Help prompt_080",
						type = "TEXT"
					},
					{
						text = "Help prompt_081",
						type = "TEXT"
					},
					{
						text = "Help prompt_082",
						type = "TEXT"
					},
					{
						text = "Help prompt_083",
						type = "TEXT"
					},
					{
						text = "Help prompt_084",
						type = "TEXT"
					},
					{
						text = "Help prompt_085",
						type = "TEXT"
					},
					{
						text = "Help prompt_086",
						type = "TEXT"
					},
					{
						text = "Help prompt_087",
						type = "TEXT"
					},
					{
						text = "Help prompt_088",
						type = "TEXT"
					},
					{
						text = "Help prompt_089",
						type = "TEXT"
					},
					{
						text = "Help prompt_090",
						type = "TEXT"
					},
					{
						text = "Help prompt_091",
						type = "TEXT"
					},
					{
						text = "Help prompt_092",
						type = "TEXT"
					},
					{
						text = "Help prompt_093",
						type = "TEXT"
					},
					{
						text = "Help prompt_094",
						type = "TEXT"
					},
					{
						text = "Help prompt_095",
						type = "TEXT"
					},
					{
						text = "Help prompt_096",
						type = "TEXT"
					},
					{
						text = "Help prompt_097",
						type = "TEXT"
					},
					{
						text = "Help prompt_098",
						type = "TEXT"
					},
					{
						text = "Help prompt_099",
						type = "TEXT"
					},
					{
						text = "Help prompt_100",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.2
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.3
	--Description: Check helpPrompt: type parameter is valid data (TEXT)

		--It is covered by SetGlobalProperties_PositiveCase_SUCCESS
		
	--End test case PositiveResponseCheck.1.3
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.4
	--Description: Check helpPrompt: type parameter is valid data (SAPI_PHONEMES)

		function Test:SetGlobalProperties_helpPrompt_type_SAPI_PHONEMES_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "SAPI_PHONEMES"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "SAPI_PHONEMES"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.4
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.5
	--Description: Check helpPrompt: type parameter is valid data (LHPLUS_PHONEMES)

		function Test:SetGlobalProperties_helpPrompt_type_LHPLUS_PHONEMES_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "LHPLUS_PHONEMES"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "LHPLUS_PHONEMES"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.5
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.6
	--Description: Check helpPrompt: type parameter is valid data (PRE_RECORDED)

		function Test:SetGlobalProperties_helpPrompt_type_PRE_RECORDED_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "PRE_RECORDED"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "PRE_RECORDED"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.6
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.7
	--Description: Check helpPrompt: type parameter is valid data (SILENCE)

		function Test:SetGlobalProperties_helpPrompt_type_SILENCE_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "SILENCE"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "SILENCE"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.7
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.8
	--Description: Check helpPrompt: text parameter is lower bound

		function Test:SetGlobalProperties_helpPrompt_text_IsLowerBound_1_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "q",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "q",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.8
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.9
	--Description: Check helpPrompt: text parameter is upper bound

		function Test:SetGlobalProperties_helpPrompt_text_IsUpperBound_500_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.9
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.10
	--Description: Check helpPrompt: text parameter contains space characters _SpaceCharacter_SpaceBefore

		function Test:SetGlobalProperties_helpPrompt_text__SpaceCharacter_SpaceBefore_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = " SpaceBefore",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = " SpaceBefore",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.10
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.11
	--Description: Check helpPrompt: text parameter contains space characters SpaceAfter_SpaceCharacter_

		function Test:SetGlobalProperties_helpPrompt_text_SpaceAfter_SpaceCharacter__SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "SpaceAfter ",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "SpaceAfter ",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.11
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.12
	--Description: Check helpPrompt: text parameter contains space characters Space_SpaceCharacter_In_SpaceCharacter_The_SpaceCharacter_Middle

		function Test:SetGlobalProperties_helpPrompt_text_Space_SpaceCharacter_In_SpaceCharacter_The_SpaceCharacter_Middle_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Space In The Middle",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Space In The Middle",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.12
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.13
	--Description: Check helpPrompt: text parameter contains space characters _SpaceCharacter_Space_SpaceCharacter_Every_SpaceCharacter_Where_SpaceCharacter_

		function Test:SetGlobalProperties_helpPrompt_text__SpaceCharacter_Space_SpaceCharacter_Every_SpaceCharacter_Where_SpaceCharacter__SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = " Space Every Where ",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = " Space Every Where ",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.13
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.14
	--Description: Check timeoutPrompt parameter is lower bound

		function Test:SetGlobalProperties_timeoutPrompt_Array_minsize_1_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.14
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.15
	--Description: Check timeoutPrompt parameter is upper bound

		function Test:SetGlobalProperties_timeoutPrompt_Array_maxsize_100_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt_001",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_002",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_003",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_004",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_005",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_006",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_007",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_008",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_009",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_010",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_011",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_012",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_013",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_014",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_015",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_016",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_017",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_018",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_019",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_020",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_021",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_022",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_023",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_024",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_025",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_026",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_027",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_028",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_029",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_030",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_031",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_032",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_033",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_034",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_035",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_036",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_037",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_038",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_039",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_040",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_041",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_042",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_043",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_044",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_045",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_046",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_047",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_048",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_049",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_050",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_051",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_052",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_053",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_054",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_055",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_056",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_057",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_058",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_059",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_060",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_061",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_062",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_063",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_064",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_065",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_066",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_067",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_068",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_069",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_070",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_071",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_072",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_073",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_074",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_075",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_076",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_077",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_078",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_079",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_080",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_081",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_082",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_083",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_084",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_085",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_086",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_087",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_088",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_089",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_090",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_091",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_092",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_093",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_094",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_095",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_096",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_097",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_098",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_099",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_100",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt_001",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_002",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_003",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_004",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_005",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_006",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_007",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_008",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_009",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_010",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_011",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_012",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_013",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_014",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_015",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_016",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_017",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_018",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_019",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_020",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_021",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_022",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_023",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_024",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_025",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_026",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_027",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_028",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_029",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_030",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_031",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_032",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_033",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_034",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_035",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_036",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_037",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_038",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_039",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_040",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_041",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_042",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_043",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_044",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_045",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_046",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_047",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_048",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_049",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_050",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_051",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_052",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_053",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_054",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_055",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_056",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_057",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_058",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_059",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_060",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_061",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_062",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_063",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_064",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_065",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_066",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_067",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_068",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_069",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_070",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_071",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_072",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_073",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_074",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_075",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_076",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_077",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_078",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_079",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_080",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_081",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_082",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_083",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_084",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_085",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_086",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_087",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_088",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_089",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_090",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_091",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_092",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_093",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_094",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_095",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_096",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_097",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_098",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_099",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_100",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.15
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.16
	--Description: Check timeoutPrompt: type parameter is valid data (TEXT)

		function Test:SetGlobalProperties_timeoutPrompt_type_TEXT_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.16
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.17
	--Description: Check timeoutPrompt: type parameter is valid data (SAPI_PHONEMES)

		function Test:SetGlobalProperties_timeoutPrompt_type_SAPI_PHONEMES_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "SAPI_PHONEMES"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "SAPI_PHONEMES"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.17
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.18
	--Description: Check timeoutPrompt: type parameter is valid data (LHPLUS_PHONEMES)

		function Test:SetGlobalProperties_timeoutPrompt_type_LHPLUS_PHONEMES_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "LHPLUS_PHONEMES"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "LHPLUS_PHONEMES"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.18
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.19
	--Description: Check timeoutPrompt: type parameter is valid data (PRE_RECORDED)

		function Test:SetGlobalProperties_timeoutPrompt_type_PRE_RECORDED_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "PRE_RECORDED"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "PRE_RECORDED"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.19
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.20
	--Description: Check timeoutPrompt: type parameter is valid data (SILENCE)

		function Test:SetGlobalProperties_timeoutPrompt_type_SILENCE_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "SILENCE"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "SILENCE"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.20
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.21
	--Description: Check timeoutPrompt: text parameter is lower bound

		function Test:SetGlobalProperties_timeoutPrompt_text_IsLowerBound_1_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "q",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "q",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.21
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.22
	--Description: Check timeoutPrompt: text parameter is upper bound

		function Test:SetGlobalProperties_timeoutPrompt_text_IsUpperBound_500_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.22
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.23
	--Description: Check timeoutPrompt: text parameter contains space characters _SpaceCharacter_SpaceBefore

		function Test:SetGlobalProperties_timeoutPrompt_text__SpaceCharacter_SpaceBefore_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = " SpaceBefore",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = " SpaceBefore",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.23
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.24
	--Description: Check timeoutPrompt: text parameter contains space characters SpaceAfter_SpaceCharacter_

		function Test:SetGlobalProperties_timeoutPrompt_text_SpaceAfter_SpaceCharacter__SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "SpaceAfter ",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "SpaceAfter ",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.24
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.25
	--Description: Check timeoutPrompt: text parameter contains space characters Space_SpaceCharacter_In_SpaceCharacter_The_SpaceCharacter_Middle

		function Test:SetGlobalProperties_timeoutPrompt_text_Space_SpaceCharacter_In_SpaceCharacter_The_SpaceCharacter_Middle_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Space In The Middle",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Space In The Middle",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.25
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.26
	--Description: Check timeoutPrompt: text parameter contains space characters _SpaceCharacter_Space_SpaceCharacter_Every_SpaceCharacter_Where_SpaceCharacter_

		function Test:SetGlobalProperties_timeoutPrompt_text__SpaceCharacter_Space_SpaceCharacter_Every_SpaceCharacter_Where_SpaceCharacter__SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = " Space Every Where ",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = " Space Every Where ",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.26
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.27
	--Description: Check vrHelpTitle parameter is lower bound

		function Test:SetGlobalProperties_vrHelpTitle_IsLowerBound_1_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "q",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "q",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.27
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.28
	--Description: Check vrHelpTitle parameter is upper bound

		function Test:SetGlobalProperties_vrHelpTitle_IsUpperBound_500_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.28
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.29
	--Description: Check vrHelpTitle parameter contains space characters _SpaceCharacter_SpaceBefore

		function Test:SetGlobalProperties_vrHelpTitle__SpaceCharacter_SpaceBefore_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = " SpaceBefore",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = " SpaceBefore",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.29
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.30
	--Description: Check vrHelpTitle parameter contains space characters SpaceAfter_SpaceCharacter_

		function Test:SetGlobalProperties_vrHelpTitle_SpaceAfter_SpaceCharacter__SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "SpaceAfter ",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "SpaceAfter ",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.30
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.31
	--Description: Check vrHelpTitle parameter contains space characters Space_SpaceCharacter_In_SpaceCharacter_The_SpaceCharacter_Middle

		function Test:SetGlobalProperties_vrHelpTitle_Space_SpaceCharacter_In_SpaceCharacter_The_SpaceCharacter_Middle_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "Space In The Middle",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "Space In The Middle",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.31
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.32
	--Description: Check vrHelpTitle parameter contains space characters _SpaceCharacter_Space_SpaceCharacter_Every_SpaceCharacter_Where_SpaceCharacter_

		function Test:SetGlobalProperties_vrHelpTitle__SpaceCharacter_Space_SpaceCharacter_Every_SpaceCharacter_Where_SpaceCharacter__SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = " Space Every Where ",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = " Space Every Where ",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.32
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.33
	--Description: Check vrHelp parameter is lower bound

		function Test:SetGlobalProperties_vrHelp_Array_minsize_1_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.33
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.34
	--Description: Check vrHelp parameter is upper bound

		function Test:SetGlobalProperties_vrHelp_Array_maxsize_100_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_001"
					},
					{
						position = 2,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_002"
					},
					{
						position = 3,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_003"
					},
					{
						position = 4,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_004"
					},
					{
						position = 5,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_005"
					},
					{
						position = 6,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_006"
					},
					{
						position = 7,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_007"
					},
					{
						position = 8,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_008"
					},
					{
						position = 9,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_009"
					},
					{
						position = 10,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_010"
					},
					{
						position = 11,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_011"
					},
					{
						position = 12,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_012"
					},
					{
						position = 13,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_013"
					},
					{
						position = 14,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_014"
					},
					{
						position = 15,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_015"
					},
					{
						position = 16,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_016"
					},
					{
						position = 17,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_017"
					},
					{
						position = 18,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_018"
					},
					{
						position = 19,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_019"
					},
					{
						position = 20,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_020"
					},
					{
						position = 21,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_021"
					},
					{
						position = 22,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_022"
					},
					{
						position = 23,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_023"
					},
					{
						position = 24,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_024"
					},
					{
						position = 25,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_025"
					},
					{
						position = 26,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_026"
					},
					{
						position = 27,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_027"
					},
					{
						position = 28,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_028"
					},
					{
						position = 29,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_029"
					},
					{
						position = 30,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_030"
					},
					{
						position = 31,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_031"
					},
					{
						position = 32,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_032"
					},
					{
						position = 33,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_033"
					},
					{
						position = 34,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_034"
					},
					{
						position = 35,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_035"
					},
					{
						position = 36,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_036"
					},
					{
						position = 37,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_037"
					},
					{
						position = 38,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_038"
					},
					{
						position = 39,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_039"
					},
					{
						position = 40,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_040"
					},
					{
						position = 41,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_041"
					},
					{
						position = 42,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_042"
					},
					{
						position = 43,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_043"
					},
					{
						position = 44,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_044"
					},
					{
						position = 45,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_045"
					},
					{
						position = 46,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_046"
					},
					{
						position = 47,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_047"
					},
					{
						position = 48,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_048"
					},
					{
						position = 49,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_049"
					},
					{
						position = 50,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_050"
					},
					{
						position = 51,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_051"
					},
					{
						position = 52,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_052"
					},
					{
						position = 53,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_053"
					},
					{
						position = 54,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_054"
					},
					{
						position = 55,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_055"
					},
					{
						position = 56,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_056"
					},
					{
						position = 57,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_057"
					},
					{
						position = 58,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_058"
					},
					{
						position = 59,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_059"
					},
					{
						position = 60,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_060"
					},
					{
						position = 61,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_061"
					},
					{
						position = 62,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_062"
					},
					{
						position = 63,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_063"
					},
					{
						position = 64,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_064"
					},
					{
						position = 65,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_065"
					},
					{
						position = 66,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_066"
					},
					{
						position = 67,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_067"
					},
					{
						position = 68,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_068"
					},
					{
						position = 69,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_069"
					},
					{
						position = 70,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_070"
					},
					{
						position = 71,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_071"
					},
					{
						position = 72,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_072"
					},
					{
						position = 73,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_073"
					},
					{
						position = 74,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_074"
					},
					{
						position = 75,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_075"
					},
					{
						position = 76,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_076"
					},
					{
						position = 77,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_077"
					},
					{
						position = 78,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_078"
					},
					{
						position = 79,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_079"
					},
					{
						position = 80,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_080"
					},
					{
						position = 81,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_081"
					},
					{
						position = 82,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_082"
					},
					{
						position = 83,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_083"
					},
					{
						position = 84,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_084"
					},
					{
						position = 85,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_085"
					},
					{
						position = 86,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_086"
					},
					{
						position = 87,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_087"
					},
					{
						position = 88,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_088"
					},
					{
						position = 89,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_089"
					},
					{
						position = 90,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_090"
					},
					{
						position = 91,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_091"
					},
					{
						position = 92,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_092"
					},
					{
						position = 93,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_093"
					},
					{
						position = 94,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_094"
					},
					{
						position = 95,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_095"
					},
					{
						position = 96,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_096"
					},
					{
						position = 97,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_097"
					},
					{
						position = 98,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_098"
					},
					{
						position = 99,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_099"
					},
					{
						position = 100,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_100"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_001"
					},
					{
						position = 2,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_002"
					},
					{
						position = 3,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_003"
					},
					{
						position = 4,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_004"
					},
					{
						position = 5,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_005"
					},
					{
						position = 6,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_006"
					},
					{
						position = 7,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_007"
					},
					{
						position = 8,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_008"
					},
					{
						position = 9,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_009"
					},
					{
						position = 10,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_010"
					},
					{
						position = 11,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_011"
					},
					{
						position = 12,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_012"
					},
					{
						position = 13,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_013"
					},
					{
						position = 14,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_014"
					},
					{
						position = 15,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_015"
					},
					{
						position = 16,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_016"
					},
					{
						position = 17,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_017"
					},
					{
						position = 18,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_018"
					},
					{
						position = 19,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_019"
					},
					{
						position = 20,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_020"
					},
					{
						position = 21,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_021"
					},
					{
						position = 22,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_022"
					},
					{
						position = 23,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_023"
					},
					{
						position = 24,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_024"
					},
					{
						position = 25,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_025"
					},
					{
						position = 26,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_026"
					},
					{
						position = 27,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_027"
					},
					{
						position = 28,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_028"
					},
					{
						position = 29,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_029"
					},
					{
						position = 30,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_030"
					},
					{
						position = 31,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_031"
					},
					{
						position = 32,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_032"
					},
					{
						position = 33,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_033"
					},
					{
						position = 34,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_034"
					},
					{
						position = 35,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_035"
					},
					{
						position = 36,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_036"
					},
					{
						position = 37,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_037"
					},
					{
						position = 38,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_038"
					},
					{
						position = 39,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_039"
					},
					{
						position = 40,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_040"
					},
					{
						position = 41,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_041"
					},
					{
						position = 42,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_042"
					},
					{
						position = 43,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_043"
					},
					{
						position = 44,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_044"
					},
					{
						position = 45,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_045"
					},
					{
						position = 46,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_046"
					},
					{
						position = 47,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_047"
					},
					{
						position = 48,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_048"
					},
					{
						position = 49,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_049"
					},
					{
						position = 50,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_050"
					},
					{
						position = 51,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_051"
					},
					{
						position = 52,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_052"
					},
					{
						position = 53,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_053"
					},
					{
						position = 54,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_054"
					},
					{
						position = 55,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_055"
					},
					{
						position = 56,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_056"
					},
					{
						position = 57,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_057"
					},
					{
						position = 58,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_058"
					},
					{
						position = 59,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_059"
					},
					{
						position = 60,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_060"
					},
					{
						position = 61,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_061"
					},
					{
						position = 62,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_062"
					},
					{
						position = 63,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_063"
					},
					{
						position = 64,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_064"
					},
					{
						position = 65,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_065"
					},
					{
						position = 66,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_066"
					},
					{
						position = 67,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_067"
					},
					{
						position = 68,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_068"
					},
					{
						position = 69,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_069"
					},
					{
						position = 70,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_070"
					},
					{
						position = 71,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_071"
					},
					{
						position = 72,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_072"
					},
					{
						position = 73,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_073"
					},
					{
						position = 74,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_074"
					},
					{
						position = 75,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_075"
					},
					{
						position = 76,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_076"
					},
					{
						position = 77,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_077"
					},
					{
						position = 78,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_078"
					},
					{
						position = 79,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_079"
					},
					{
						position = 80,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_080"
					},
					{
						position = 81,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_081"
					},
					{
						position = 82,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_082"
					},
					{
						position = 83,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_083"
					},
					{
						position = 84,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_084"
					},
					{
						position = 85,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_085"
					},
					{
						position = 86,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_086"
					},
					{
						position = 87,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_087"
					},
					{
						position = 88,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_088"
					},
					{
						position = 89,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_089"
					},
					{
						position = 90,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_090"
					},
					{
						position = 91,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_091"
					},
					{
						position = 92,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_092"
					},
					{
						position = 93,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_093"
					},
					{
						position = 94,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_094"
					},
					{
						position = 95,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_095"
					},
					{
						position = 96,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_096"
					},
					{
						position = 97,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_097"
					},
					{
						position = 98,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_098"
					},
					{
						position = 99,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_099"
					},
					{
						position = 100,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item_100"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.34
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.35
	--Description: Check vrHelpposition parameter is lower bound

		function Test:SetGlobalProperties_vrHelp_position_IsLowerBound_1_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)						
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.35
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.36
	--Description: Check vrHelpposition parameter is upper bound

		function Test:SetGlobalProperties_vrHelp_position_IsUpperBound_100_REJECTED()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 100,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item 100"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "REJECTED"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case PositiveResponseCheck.1.36
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.37
	--Description: Check vrHelptext parameter is lower bound

		function Test:SetGlobalProperties_vrHelp_text_IsLowerBound_1_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "q"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "q"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)							
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.37
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.38
	--Description: Check vrHelptext parameter is upper bound

		function Test:SetGlobalProperties_vrHelp_text_IsUpperBound_500_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)							
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.38
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.39
	--Description: Check vrHelptext parameter contains space characters _SpaceCharacter_SpaceBefore

		function Test:SetGlobalProperties_vrHelp_text__SpaceCharacter_SpaceBefore_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = " SpaceBefore"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = " SpaceBefore"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)							
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.39
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.40
	--Description: Check vrHelptext parameter contains space characters SpaceAfter_SpaceCharacter_

		function Test:SetGlobalProperties_vrHelp_text_SpaceAfter_SpaceCharacter__SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "SpaceAfter "
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "SpaceAfter "
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)							
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.40
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.41
	--Description: Check vrHelptext parameter contains space characters Space_SpaceCharacter_In_SpaceCharacter_The_SpaceCharacter_Middle

		function Test:SetGlobalProperties_vrHelp_text_Space_SpaceCharacter_In_SpaceCharacter_The_SpaceCharacter_Middle_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "Space In The Middle"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "Space In The Middle"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)							
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.41
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.42
	--Description: Check vrHelptext parameter contains space characters _SpaceCharacter_Space_SpaceCharacter_Every_SpaceCharacter_Where_SpaceCharacter_

		function Test:SetGlobalProperties_vrHelp_text__SpaceCharacter_Space_SpaceCharacter_Every_SpaceCharacter_Where_SpaceCharacter__SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = " Space Every Where "
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = " Space Every Where "
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)							
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.42
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.43
	--Description: Check image: imageType parameter is valid data (STATIC)

		function Test:SetGlobalProperties_vrHelp_image_imageType_STATIC_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "STATIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "STATIC",
							value = "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)							
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.43
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.44
	--Description: Check image: imageType parameter is valid data (DYNAMIC)

		function Test:SetGlobalProperties_vrHelp_image_imageType_DYNAMIC_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)							
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.44
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.45
	--Description: Check image: value parameter is lower bound

		function Test:SetGlobalProperties_vrHelp_image_value_IsLowerBound_0_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case PositiveResponseCheck.1.45
	-----------------------------------------------------------------------------------------

	--Reason: can not put file with file name length is 65535
	--Begin test case PositiveResponseCheck.1.46
	--Description: Check image: value parameter is upper bound
		
		--It is not able to test because max-length of file name is 255.
	
	--End test case PositiveResponseCheck.1.45
	-----------------------------------------------------------------------------------------

	
	--Begin test case PositiveResponseCheck.1.47
	--Description: Check image: value parameter contains space character _SpaceCharacter_SpaceBefore

		function Test:SetGlobalProperties_vrHelp_image_value__SpaceCharacter_SpaceBefore_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = " SpaceBefore",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. " SpaceBefore"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.47
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.48
	--Description: Check image: value parameter contains space character SpaceAfter_SpaceCharacter_

		function Test:SetGlobalProperties_vrHelp_image_value_SpaceAfter_SpaceCharacter__SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "SpaceAfter ",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "SpaceAfter "
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.48
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.49
	--Description: Check image: value parameter contains space character Space_SpaceCharacter_In_SpaceCharacter_The_SpaceCharacter_Middle

		function Test:SetGlobalProperties_vrHelp_image_value_Space_SpaceCharacter_In_SpaceCharacter_The_SpaceCharacter_Middle_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "Space In The Middle",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "Space In The Middle"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.49
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.50
	--Description: Check image: value parameter contains space character _SpaceCharacter_Space_SpaceCharacter_Every_SpaceCharacter_Where_SpaceCharacter_

		function Test:SetGlobalProperties_vrHelp_image_value__SpaceCharacter_Space_SpaceCharacter_Every_SpaceCharacter_Where_SpaceCharacter__SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = " Space Every Where ",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. " Space Every Where "
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.50
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.51
	--Description: Check image: value parameter is lower bound of an existing file

		function Test:SetGlobalProperties_vrHelp_image_value_IsLowerBoundOfRealImageName_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "a",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "a"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.51
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.52
	--Description: Check image: value parameter is upper bound of an existing file

		function Test:SetGlobalProperties_vrHelp_image_value_IsUpperBoundOfRealImageName_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = strMaxLengthFileName255,
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. strMaxLengthFileName255
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.52
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.53
	--Description: Check menuTitle parameter is lower bound

		function Test:SetGlobalProperties_menuTitle_IsLowerBound_1_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "q",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "q",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.53
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.54
	--Description: Check menuTitle parameter is upper bound

		function Test:SetGlobalProperties_menuTitle_IsUpperBound_500_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.54
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.55
	--Description: Check menuTitle parameter contains space characters _SpaceCharacter_SpaceBefore

		function Test:SetGlobalProperties_menuTitle__SpaceCharacter_SpaceBefore_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = " SpaceBefore",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = " SpaceBefore",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.55
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.56
	--Description: Check menuTitle parameter contains space characters SpaceAfter_SpaceCharacter_

		function Test:SetGlobalProperties_menuTitle_SpaceAfter_SpaceCharacter__SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "SpaceAfter ",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "SpaceAfter ",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.56
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.57
	--Description: Check menuTitle parameter contains space characters Space_SpaceCharacter_In_SpaceCharacter_The_SpaceCharacter_Middle

		function Test:SetGlobalProperties_menuTitle_Space_SpaceCharacter_In_SpaceCharacter_The_SpaceCharacter_Middle_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Space In The Middle",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Space In The Middle",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.57
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.58
	--Description: Check menuTitle parameter contains space characters _SpaceCharacter_Space_SpaceCharacter_Every_SpaceCharacter_Where_SpaceCharacter_

		function Test:SetGlobalProperties_menuTitle__SpaceCharacter_Space_SpaceCharacter_Every_SpaceCharacter_Where_SpaceCharacter__SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = " Space Every Where ",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = " Space Every Where ",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.58
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.59
	--Description: Check menuIcon: imageType parameter is valid data (STATIC)

		function Test:SetGlobalProperties_menuIcon_imageType_STATIC_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "STATIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "STATIC",
					value = "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.59
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.60
	--Description: Check menuIcon: imageType parameter is valid data (DYNAMIC)

		function Test:SetGlobalProperties_menuIcon_imageType_DYNAMIC_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.60
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.61
	--Description: Check menuIcon: value parameter is lower bound

		function Test:SetGlobalProperties_menuIcon_value_IsLowerBound_0_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case PositiveResponseCheck.1.61
	-----------------------------------------------------------------------------------------


	--Begin test case PositiveResponseCheck.1.62
	--Description: Check menuIcon: value parameter is upper bound

		--It is not able to test because max-length of file name is 255

	--End test case PositiveResponseCheck.1.62
	-----------------------------------------------------------------------------------------
	
	--Begin test case PositiveResponseCheck.1.63
	--Description: Check menuIcon: value parameter contains space character _SpaceCharacter_SpaceBefore

		function Test:SetGlobalProperties_menuIcon_value__SpaceCharacter_SpaceBefore_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = " SpaceBefore",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. " SpaceBefore"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.63
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.64
	--Description: Check menuIcon: value parameter contains space character SpaceAfter_SpaceCharacter_

		function Test:SetGlobalProperties_menuIcon_value_SpaceAfter_SpaceCharacter__SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "SpaceAfter ",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "SpaceAfter "
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.64
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.65
	--Description: Check menuIcon: value parameter contains space character Space_SpaceCharacter_In_SpaceCharacter_The_SpaceCharacter_Middle

		function Test:SetGlobalProperties_menuIcon_value_Space_SpaceCharacter_In_SpaceCharacter_The_SpaceCharacter_Middle_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "Space In The Middle",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "Space In The Middle"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.65
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.66
	--Description: Check menuIcon: value parameter contains space character _SpaceCharacter_Space_SpaceCharacter_Every_SpaceCharacter_Where_SpaceCharacter_

		function Test:SetGlobalProperties_menuIcon_value__SpaceCharacter_Space_SpaceCharacter_Every_SpaceCharacter_Where_SpaceCharacter__SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = " Space Every Where ",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. " Space Every Where "
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.66
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.67
	--Description: Check menuIcon: value parameter is lower bound of an existing file

		function Test:SetGlobalProperties_menuIcon_value_IsLowerBoundOfRealImageName_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "a",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "a"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.67
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.68
	--Description: Check menuIcon: value parameter is upper bound of an existing file

		function Test:SetGlobalProperties_menuIcon_value_IsUpperBoundOfRealImageName_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = strMaxLengthFileName255,
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. strMaxLengthFileName255
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.68
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.69-1.91
	--Description: Check keyboardPropertieslanguage parameter is valid data
	--Note: During SDL-HMI starting SDL should request HMI UI.GetSupportedLanguages, VR.GetSupportedLanguages, TTS.GetSupportedLanguages and HMI should respond with all languages 
	--specified in this test (added new languages which should be supported by SDL - CRQ APPLINK-13745: "NL-BE", "EL-GR", "HU-HU", "FI-FI", "SK-SK") 
			local Languages = {"AR-SA", "CS-CZ", "DA-DK", "DE-DE", "EN-AU",
										"EN-GB", "EN-US", "ES-ES", "ES-MX", "FR-CA", 
										"FR-FR", "IT-IT", "JA-JP", "KO-KR", "NL-NL", 
										"NO-NO", "PL-PL", "PT-PT", "PT-BR", "RU-RU", 
										"SV-SE", "TR-TR", "ZH-CN", "ZH-TW", "NL-BE",
										"EL-GR", "HU-HU", "FI-FI", "SK-SK"}
		for i = 1, #Languages do
			Test["SetGlobalProperties_keyboardProperties_language_" .. Languages[i] .. "_SUCCESS"]  = function(self)
			
				--mobile side: sending SetGlobalProperties request
				local cid = self.mobileSession:SendRPC("SetGlobalProperties",
				{
					menuTitle = "Menu Title",
					timeoutPrompt = 
					{
						{
							text = "Timeout prompt",
							type = "TEXT"
						}
					},
					vrHelp = 
					{
						{
							position = 1,
							image = 
							{
								value = "action.png",
								imageType = "DYNAMIC"
							},
							text = "VR help item"
						}
					},
					menuIcon = 
					{
						value = "action.png",
						imageType = "DYNAMIC"
					},
					helpPrompt = 
					{
						{
							text = "Help prompt",
							type = "TEXT"
						}
					},
					vrHelpTitle = "VR help title",
					keyboardProperties = 
					{
						keyboardLayout = "QWERTY",
						keypressMode = "SINGLE_KEYPRESS",
						limitedCharacterList = 
						{
							"a"
						},
						language = Languages[i],
						autoCompleteText = "Daemon, Freedom"
					}
				})
			

				--hmi side: expect TTS.SetGlobalProperties request
				EXPECT_HMICALL("TTS.SetGlobalProperties",
				{
					timeoutPrompt = 
					{
						{
							text = "Timeout prompt",
							type = "TEXT"
						}
					},
					helpPrompt = 
					{
						{
							text = "Help prompt",
							type = "TEXT"
						}
					}
				})
				:Timeout(iTimeout)
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)

			

				--hmi side: expect UI.SetGlobalProperties request
				EXPECT_HMICALL("UI.SetGlobalProperties",
				{
					menuTitle = "Menu Title",
					vrHelp = 
					{
						{
							position = 1,
							--[=[ TODO: update after resolving APPLINK-16052

							image = 
							{
								imageType = "DYNAMIC",
								value = strAppFolder .. "action.png"
							},]=]
							text = "VR help item"
						}
					},
					menuIcon = 
					{
						imageType = "DYNAMIC",
						value = strAppFolder .. "action.png"
					},
					vrHelpTitle = "VR help title",
					keyboardProperties = 
					{
						keyboardLayout = "QWERTY",
						keypressMode = "SINGLE_KEYPRESS",
						--[=[ TODO: update after resolving APPLINK-16047

						limitedCharacterList = 
						{
							"a"
						},]=]
						language = Languages[i],
						autoCompleteText = "Daemon, Freedom"
					}
				})
				:Timeout(iTimeout)
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)

			

				--mobile side: expect SetGlobalProperties response
				EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
				:Timeout(iTimeout)									
			
				--mobile side: expect OnHashChange notification
				EXPECT_NOTIFICATION("OnHashChange")
			end
			
		end
	--End test case PositiveResponseCheck.1.69-1.91
	-----------------------------------------------------------------------------------------


	--Begin test case PositiveResponseCheck.1.92
	--Description: Check keyboardPropertieskeyboardLayout parameter is valid data

		function Test:SetGlobalProperties_keyboardProperties_keyboardLayout_QWERTY_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.92
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.93
	--Description: Check keyboardPropertieskeyboardLayout parameter is valid data

		function Test:SetGlobalProperties_keyboardProperties_keyboardLayout_QWERTZ_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTZ",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTZ",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.93
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.94
	--Description: Check keyboardPropertieskeyboardLayout parameter is valid data

		function Test:SetGlobalProperties_keyboardProperties_keyboardLayout_AZERTY_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "AZERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "AZERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.94
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.95
	--Description: Check keyboardPropertieskeypressMode parameter is valid data

		function Test:SetGlobalProperties_keyboardProperties_keypressMode_SINGLE_KEYPRESS_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.95
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.96
	--Description: Check keyboardProperties keypressMode parameter is valid data

		function Test:SetGlobalProperties_keyboardProperties_keypressMode_QUEUE_KEYPRESSES_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "QUEUE_KEYPRESSES",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "QUEUE_KEYPRESSES",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.96
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.97
	--Description: Check keyboardPropertieskeypressMode parameter is valid data

		function Test:SetGlobalProperties_keyboardProperties_keypressMode_RESEND_CURRENT_ENTRY_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "RESEND_CURRENT_ENTRY",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "RESEND_CURRENT_ENTRY",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.97
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.98
	--Description: Check limitedCharacterList parameter is lower bound

		function Test:SetGlobalProperties_keyboardProperties_limitedCharacterList_Array_IsLowerBound_Length_IsLowerUpperBound_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					limitedCharacterList = 
					{
						"q"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					language = "EN-US",
					keyboardLayout = "QWERTY",
					autoCompleteText = "Daemon, Freedom",
					--[=[ TODO: update after resolving APPLINK-16047
					limitedCharacterList = 
					{
						"q"
					}]=]
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.98
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.99
	--Description: Check limitedCharacterList parameter is upper bound

		function Test:SetGlobalProperties_keyboardProperties_limitedCharacterList_Array_IsUpperBound_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					limitedCharacterList = 
					{
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					language = "EN-US",
					keyboardLayout = "QWERTY",
					autoCompleteText = "Daemon, Freedom",
					--[=[ TODO: update after resolving APPLINK-16047
					limitedCharacterList = 
					{
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q"
					}]=]
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.99
	----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.100
	--Description: Check keyboardProperties.limitedCharacterList parameter is lower/upper bound

		function Test:SetGlobalProperties_keyboardProperties_limitedCharacterList_IsLowerUpperBound_1_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"q"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"q"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.100
	-----------------------------------------------------------------------------------------
	
	--Begin test case PositiveResponseCheck.1.101
	--Description: Check keyboardPropertiesautoCompleteText parameter is lower bound

		function Test:SetGlobalProperties_keyboardProperties_autoCompleteText_IsLowerBound_1_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "q"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "q"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.101
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.102
	--Description: Check keyboardPropertiesautoCompleteText parameter is upper bound

		function Test:SetGlobalProperties_keyboardProperties_autoCompleteText_IsUpperBound_1000_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_cB6_vA7_bB8_nA9_mB0_qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_cB6_vA7_bB8_nA9_mB0_qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.102
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.103
	--Description: Check keyboardPropertiesautoCompleteText parameter contains space characters _SpaceCharacter_SpaceBefore

		function Test:SetGlobalProperties_keyboardProperties_autoCompleteText__SpaceCharacter_SpaceBefore_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = " SpaceBefore"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = " SpaceBefore"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.103
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.104
	--Description: Check keyboardPropertiesautoCompleteText parameter contains space characters SpaceAfter_SpaceCharacter_

		function Test:SetGlobalProperties_keyboardProperties_autoCompleteText_SpaceAfter_SpaceCharacter__SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "SpaceAfter "
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "SpaceAfter "
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.104
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.105
	--Description: Check keyboardPropertiesautoCompleteText parameter contains space characters Space_SpaceCharacter_In_SpaceCharacter_The_SpaceCharacter_Middle

		function Test:SetGlobalProperties_keyboardProperties_autoCompleteText_Space_SpaceCharacter_In_SpaceCharacter_The_SpaceCharacter_Middle_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Space In The Middle"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Space In The Middle"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.105
	-----------------------------------------------------------------------------------------

	--Begin test case PositiveResponseCheck.1.106
	--Description: Check keyboardPropertiesautoCompleteText parameter contains space characters _SpaceCharacter_Space_SpaceCharacter_Every_SpaceCharacter_Where_SpaceCharacter_

		function Test:SetGlobalProperties_keyboardProperties_autoCompleteText__SpaceCharacter_Space_SpaceCharacter_Every_SpaceCharacter_Where_SpaceCharacter__SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = " Space Every Where "
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = " Space Every Where "
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case PositiveResponseCheck.1.106
	-----------------------------------------------------------------------------------------

--End test case PositiveResponseCheck.1


----------------------------------------------------------------------------------------------
----------------------------------------III TEST BLOCK----------------------------------------
----------------------------------------Negative cases----------------------------------------
----------------------------------------------------------------------------------------------

	--=================================================================================--
	---------------------------------Negative request check------------------------------
	--=================================================================================--


--Begin test case NegativeRequestCheck.1
--Description: Check negative request

	--Requirement id in JAMA: SDLAQ-CRS-11, SDLAQ-CRS-383

	--Verification criteria:
		--The request with wrong JSON syntax is sent, the response comes with INVALID_DATA result code.
		--The request with "helpPrompt" value out of bounds is sent, the response comes with INVALID_DATA result code.
		--The request with "timeoutPrompt" value out of bounds is sent, the response comes with INVALID_DATA result code.
		--The request with "VRHelpItem" value out of bounds is sent, the response comes with INVALID_DATA result code.
		--The request with empty "helpPrompt" ttsChunk value is sent, the response comes with INVALID_DATA result code.
		--The request with empty "timeoutPrompt" ttsChunk value is sent, the response comes with INVALID_DATA result code.
		--The request with empty "vrHelpTitle" value is sent, the response comes with INVALID_DATA result code.
		--The request with empty "vrHelp" array is sent, the response comes with INVALID_DATA result code.
		--The request with empty "helpPrompt" array is sent, the response comes with INVALID_DATA result code.
		--The request with empty "timeoutPrompt" array is sent, the response comes with INVALID_DATA result code.
		--The request with empty "VRHelpItem" value is sent, the response comes with INVALID_DATA result code.
		--The request with "vrHelpTitle" value greater than 500 symbols is sent, the response comes with INVALID_DATA result code.
		--The request with "helpPrompt" array which contains more than 100 items is sent, the response comes with INVALID_DATA result code.
		--The request with "timeoutPrompt" array which contains more than 100 items is sent, the response comes with INVALID_DATA result code.
		--The request with "vrHelp" array which contains more than 100 items is sent, the response comes with INVALID_DATA result code.
		--The request with wrong "helpPrompt" value is sent, the response comes with INVALID_DATA result code.
		--The request with wrong "timeoutPrompt" value is sent, the response comes with INVALID_DATA result code.
		--The request with wrong type of "vrHelpTitle" parameter is sent, the response comes with INVALID_DATA result code.
		--The request with wrong type of "vrHelpItem" text parameter is sent, the response comes with INVALID_DATA result code.
		--The request with wrong type of "vrHelpItem" position parameter is sent (e.g. String), the response comes with INVALID_DATA result code.
		--The request with "vrHelp" array which contains at least one image element with wrong image path (the file does not exist) is sent, the response comes with INVALID_DATA result code.
		--5. app->SDL: SetGlobalProperties{TTSChunk{text: "abcd\nabcd"}, params}}    //then, SetGlobalProperties {TTSChunk{text: "abcd\tabcd"}},   thenSetGlobalProperties {TTSChunk{text: "       "}} SDL-app: SetGlobalProperties{INVALID_DATA}
		-- 5.1. app->SDL: SetGlobalProperties{VrHelpItem{Image{{value: "abcd\nabcd"}, params}}    //then, SetGlobalProperties {VrHelpItem{Image{{value: "abcd\tabcd"}},   thenSetGlobalProperties {VrHelpItem{Image{{value: "       "}} SDL-app: SetGlobalProperties{INVALID_DATA}
		-- 5.2. app->SDL: SetGlobalProperties{menuIcon{value: "abcd\nabcd"}, params}}    //then, SetGlobalProperties {menuIcon{{value: "abcd\tabcd"}},   thenSetGlobalProperties {VmenuIcon{value: "       "}} SDL-app: SetGlobalProperties{INVALID_DATA}
		--5.3. app->SDL: SetGlobalProperties{VrHelpTitle: "abcd\nabcd"}, params}}    //then, SetGlobalProperties {VrHelpTitle: "abcd\tabcd"}},   thenSetGlobalProperties {VrHelpTitle: "       "}} SDL-app: SetGlobalProperties{INVALID_DATA}
		--5.4. app->SDL: SetGlobalProperties{VrHelpItem{text: "abcd\nabcd"}, params}}    //then, SetGlobalProperties {VrHelpItem{text: "abcd\tabcd"}},   thenSetGlobalProperties {VrHelpItem{text: "       "}} SDL-app: SetGlobalProperties{INVALID_DATA}
		--5.5. app->SDL: SetGlobalProperties{menuTitle: "abcd\nabcd"}, params}}    //then, SetGlobalProperties {menuTitle: "abcd\tabcd"}},   thenSetGlobalProperties {menuTitle: "       "}} SDL-app: SetGlobalProperties{INVALID_DATA}
		--5.6. app->SDL: SetGlobalProperties{KeyboardProperties{limitedCharacterList: "abcd\nabcd"}, params}}    //then, SetGlobalProperties {KeyboardProperties{limitedCharacterList: "abcd\tabcd"}},   then SetGlobalProperties {KeyboardProperties{limitedCharacterList: "       "}}  SDL-app: SetGlobalProperties{INVALID_DATA}
		--5.7. app->SDL: SetGlobalProperties{KeyboardProperties{autoCompleteText: "abcd\nabcd"}, params}}    //then, SetGlobalProperties {KeyboardProperties{autoCompleteText: "abcd\tabcd"}},   then SetGlobalProperties {KeyboardProperties{autoCompleteText: "       "}}  SDL-app: SetGlobalProperties{INVALID_DATA}
		--The request with no parameters (any of helpPrompt, timeoutPrompt, vrHelpTitle, vrHelp parameters do not exist ) is sent, the response comes with INVALID_DATA result code.
		--The request with empty "vrHelpItem" value is sent, the response comes with INVALID_DATA result code.
		--The request with empty "image" value of vrHelpItem is sent, the response comes with INVALID_DATA result code.

	--Begin test case NegativeRequestCheck.1.1
	--Description: Check helpPrompt parameter is wrong type

		function Test:SetGlobalProperties_helpPrompt_Array_WrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 123,
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.1
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.2
	--Description: Check helpPrompt parameter is out lower bound

		function Test:SetGlobalProperties_helpPrompt_Array_Outminsize_0_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{

				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.2
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.3
	--Description: Check helpPrompt parameter is out upper bound

		function Test:SetGlobalProperties_helpPrompt_Array_Outmaxsize_101_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt_001",
						type = "TEXT"
					},
					{
						text = "Help prompt_002",
						type = "TEXT"
					},
					{
						text = "Help prompt_003",
						type = "TEXT"
					},
					{
						text = "Help prompt_004",
						type = "TEXT"
					},
					{
						text = "Help prompt_005",
						type = "TEXT"
					},
					{
						text = "Help prompt_006",
						type = "TEXT"
					},
					{
						text = "Help prompt_007",
						type = "TEXT"
					},
					{
						text = "Help prompt_008",
						type = "TEXT"
					},
					{
						text = "Help prompt_009",
						type = "TEXT"
					},
					{
						text = "Help prompt_010",
						type = "TEXT"
					},
					{
						text = "Help prompt_011",
						type = "TEXT"
					},
					{
						text = "Help prompt_012",
						type = "TEXT"
					},
					{
						text = "Help prompt_013",
						type = "TEXT"
					},
					{
						text = "Help prompt_014",
						type = "TEXT"
					},
					{
						text = "Help prompt_015",
						type = "TEXT"
					},
					{
						text = "Help prompt_016",
						type = "TEXT"
					},
					{
						text = "Help prompt_017",
						type = "TEXT"
					},
					{
						text = "Help prompt_018",
						type = "TEXT"
					},
					{
						text = "Help prompt_019",
						type = "TEXT"
					},
					{
						text = "Help prompt_020",
						type = "TEXT"
					},
					{
						text = "Help prompt_021",
						type = "TEXT"
					},
					{
						text = "Help prompt_022",
						type = "TEXT"
					},
					{
						text = "Help prompt_023",
						type = "TEXT"
					},
					{
						text = "Help prompt_024",
						type = "TEXT"
					},
					{
						text = "Help prompt_025",
						type = "TEXT"
					},
					{
						text = "Help prompt_026",
						type = "TEXT"
					},
					{
						text = "Help prompt_027",
						type = "TEXT"
					},
					{
						text = "Help prompt_028",
						type = "TEXT"
					},
					{
						text = "Help prompt_029",
						type = "TEXT"
					},
					{
						text = "Help prompt_030",
						type = "TEXT"
					},
					{
						text = "Help prompt_031",
						type = "TEXT"
					},
					{
						text = "Help prompt_032",
						type = "TEXT"
					},
					{
						text = "Help prompt_033",
						type = "TEXT"
					},
					{
						text = "Help prompt_034",
						type = "TEXT"
					},
					{
						text = "Help prompt_035",
						type = "TEXT"
					},
					{
						text = "Help prompt_036",
						type = "TEXT"
					},
					{
						text = "Help prompt_037",
						type = "TEXT"
					},
					{
						text = "Help prompt_038",
						type = "TEXT"
					},
					{
						text = "Help prompt_039",
						type = "TEXT"
					},
					{
						text = "Help prompt_040",
						type = "TEXT"
					},
					{
						text = "Help prompt_041",
						type = "TEXT"
					},
					{
						text = "Help prompt_042",
						type = "TEXT"
					},
					{
						text = "Help prompt_043",
						type = "TEXT"
					},
					{
						text = "Help prompt_044",
						type = "TEXT"
					},
					{
						text = "Help prompt_045",
						type = "TEXT"
					},
					{
						text = "Help prompt_046",
						type = "TEXT"
					},
					{
						text = "Help prompt_047",
						type = "TEXT"
					},
					{
						text = "Help prompt_048",
						type = "TEXT"
					},
					{
						text = "Help prompt_049",
						type = "TEXT"
					},
					{
						text = "Help prompt_050",
						type = "TEXT"
					},
					{
						text = "Help prompt_051",
						type = "TEXT"
					},
					{
						text = "Help prompt_052",
						type = "TEXT"
					},
					{
						text = "Help prompt_053",
						type = "TEXT"
					},
					{
						text = "Help prompt_054",
						type = "TEXT"
					},
					{
						text = "Help prompt_055",
						type = "TEXT"
					},
					{
						text = "Help prompt_056",
						type = "TEXT"
					},
					{
						text = "Help prompt_057",
						type = "TEXT"
					},
					{
						text = "Help prompt_058",
						type = "TEXT"
					},
					{
						text = "Help prompt_059",
						type = "TEXT"
					},
					{
						text = "Help prompt_060",
						type = "TEXT"
					},
					{
						text = "Help prompt_061",
						type = "TEXT"
					},
					{
						text = "Help prompt_062",
						type = "TEXT"
					},
					{
						text = "Help prompt_063",
						type = "TEXT"
					},
					{
						text = "Help prompt_064",
						type = "TEXT"
					},
					{
						text = "Help prompt_065",
						type = "TEXT"
					},
					{
						text = "Help prompt_066",
						type = "TEXT"
					},
					{
						text = "Help prompt_067",
						type = "TEXT"
					},
					{
						text = "Help prompt_068",
						type = "TEXT"
					},
					{
						text = "Help prompt_069",
						type = "TEXT"
					},
					{
						text = "Help prompt_070",
						type = "TEXT"
					},
					{
						text = "Help prompt_071",
						type = "TEXT"
					},
					{
						text = "Help prompt_072",
						type = "TEXT"
					},
					{
						text = "Help prompt_073",
						type = "TEXT"
					},
					{
						text = "Help prompt_074",
						type = "TEXT"
					},
					{
						text = "Help prompt_075",
						type = "TEXT"
					},
					{
						text = "Help prompt_076",
						type = "TEXT"
					},
					{
						text = "Help prompt_077",
						type = "TEXT"
					},
					{
						text = "Help prompt_078",
						type = "TEXT"
					},
					{
						text = "Help prompt_079",
						type = "TEXT"
					},
					{
						text = "Help prompt_080",
						type = "TEXT"
					},
					{
						text = "Help prompt_081",
						type = "TEXT"
					},
					{
						text = "Help prompt_082",
						type = "TEXT"
					},
					{
						text = "Help prompt_083",
						type = "TEXT"
					},
					{
						text = "Help prompt_084",
						type = "TEXT"
					},
					{
						text = "Help prompt_085",
						type = "TEXT"
					},
					{
						text = "Help prompt_086",
						type = "TEXT"
					},
					{
						text = "Help prompt_087",
						type = "TEXT"
					},
					{
						text = "Help prompt_088",
						type = "TEXT"
					},
					{
						text = "Help prompt_089",
						type = "TEXT"
					},
					{
						text = "Help prompt_090",
						type = "TEXT"
					},
					{
						text = "Help prompt_091",
						type = "TEXT"
					},
					{
						text = "Help prompt_092",
						type = "TEXT"
					},
					{
						text = "Help prompt_093",
						type = "TEXT"
					},
					{
						text = "Help prompt_094",
						type = "TEXT"
					},
					{
						text = "Help prompt_095",
						type = "TEXT"
					},
					{
						text = "Help prompt_096",
						type = "TEXT"
					},
					{
						text = "Help prompt_097",
						type = "TEXT"
					},
					{
						text = "Help prompt_098",
						type = "TEXT"
					},
					{
						text = "Help prompt_099",
						type = "TEXT"
					},
					{
						text = "Help prompt_100",
						type = "TEXT"
					},
					{
						text = "Help prompt_101",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.3
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.4
	--Description: Check helpPrompt parameter contains an array with only one empty item

		function Test:SetGlobalProperties_helpPrompt_Array_ContainAnEmptyItem_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{

					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.4
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.5
	--Description: Check helpPrompt parameter is empty (missed all child items)

		--It is covered by SetGlobalProperties_helpPrompt_Array_ContainAnEmptyItem_INVALID_DATA
		
	--End test case NegativeRequestCheck.1.5
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.6
	--Description: Check helpPrompt parameter is wrong type

		function Test:SetGlobalProperties_helpPrompt_WrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					123
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.6
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.7
	--Description: Check helpPrompt: type parameter is missed

		function Test:SetGlobalProperties_helpPrompt_type_IsMising_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.7
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.8
	--Description: Check helpPrompt: type parameter is wrong value

		function Test:SetGlobalProperties_helpPrompt_type_WrongValue_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "Wrong Value"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.8
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.9
	--Description: Check helpPrompt: text parameter is missed

		function Test:SetGlobalProperties_helpPrompt_text_IsMising_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.9
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.10
	--Description: Check helpPrompt: text parameter is wrong type

		function Test:SetGlobalProperties_helpPrompt_text_IsWrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = 123,
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.10
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.11
	--Description: Check helpPrompt: text parameter is lower bound

		--Requirement id in JAMA: SDLAQ-CRS-11, SDLAQ-CRS-2910

		--Verification criteria: "1. In case the mobile application sends any RPC with 'text:""' (empty string) of 'ttsChunk' structure and other valid parameters, SDL must consider such RPC as valid and transfer it to HMI"

		function Test:SetGlobalProperties_helpPrompt_text_IsOutLowerBound_0_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")			
		end

	--End test case NegativeRequestCheck.1.11
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.12
	--Description: Check helpPrompt: text parameter is out upper bound

		function Test:SetGlobalProperties_helpPrompt_text_IsOutUpperBound_501_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_c",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.12
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.13
	--Description: Check helpPrompt: text parameter contains escape characters _NewLineCharacter_

		function Test:SetGlobalProperties_helpPrompt_text__NewLineCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "\n",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.13
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.14
	--Description: Check helpPrompt: text parameter contains escape characters _TabChacracter_

		function Test:SetGlobalProperties_helpPrompt_text__TabChacracter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "\t",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.14
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.15
	--Description: Check helpPrompt: text parameter contains escape characters _SpaceCharacter_

		function Test:SetGlobalProperties_helpPrompt_text__SpaceCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = " ",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.15
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.16
	--Description: Check timeoutPrompt parameter is wrong type

		function Test:SetGlobalProperties_timeoutPrompt_Array_WrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 123,
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.16
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.17
	--Description: Check timeoutPrompt parameter is out lower bound

		function Test:SetGlobalProperties_timeoutPrompt_Array_Outminsize_0_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{

				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.17
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.18
	--Description: Check timeoutPrompt parameter is out upper bound

		function Test:SetGlobalProperties_timeoutPrompt_Array_Outmaxsize_101_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt_001",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_002",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_003",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_004",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_005",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_006",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_007",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_008",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_009",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_010",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_011",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_012",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_013",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_014",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_015",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_016",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_017",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_018",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_019",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_020",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_021",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_022",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_023",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_024",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_025",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_026",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_027",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_028",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_029",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_030",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_031",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_032",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_033",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_034",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_035",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_036",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_037",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_038",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_039",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_040",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_041",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_042",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_043",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_044",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_045",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_046",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_047",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_048",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_049",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_050",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_051",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_052",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_053",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_054",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_055",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_056",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_057",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_058",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_059",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_060",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_061",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_062",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_063",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_064",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_065",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_066",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_067",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_068",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_069",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_070",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_071",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_072",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_073",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_074",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_075",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_076",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_077",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_078",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_079",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_080",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_081",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_082",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_083",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_084",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_085",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_086",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_087",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_088",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_089",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_090",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_091",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_092",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_093",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_094",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_095",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_096",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_097",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_098",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_099",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_100",
						type = "TEXT"
					},
					{
						text = "Timeout prompt_101",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.18
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.19
	--Description: Check timeoutPrompt parameter contains an array with only one empty item

		function Test:SetGlobalProperties_timeoutPrompt_Array_ContainAnEmptyItem_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{

					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.19
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.20
	--Description: Check timeoutPrompt parameter is empty (missed all child items

		--It is covered by SetGlobalProperties_timeoutPrompt_Array_ContainAnEmptyItem
		
	--End test case NegativeRequestCheck.1.20
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.21
	--Description: Check timeoutPrompt parameter is wrong type

		function Test:SetGlobalProperties_timeoutPrompt_WrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					123
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.21
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.22
	--Description: Check timeoutPrompt: type parameter is missed

		function Test:SetGlobalProperties_timeoutPrompt_type_IsMising_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.22
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.23
	--Description: Check timeoutPrompt: type parameter is wrong value

		function Test:SetGlobalProperties_timeoutPrompt_type_WrongValue_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "Wrong Value"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.23
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.24
	--Description: Check timeoutPrompt: text parameter is missed

		function Test:SetGlobalProperties_timeoutPrompt_text_IsMising_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.24
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.25
	--Description: Check timeoutPrompt: text parameter is wrong type

		function Test:SetGlobalProperties_timeoutPrompt_text_IsWrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = 123,
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.25
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.26
	--Description: Check timeoutPrompt: text parameter is lower bound

		function Test:SetGlobalProperties_timeoutPrompt_text_IsOutLowerBound_0_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title"
			})
		

				--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties")
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)									
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case NegativeRequestCheck.1.26
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.27
	--Description: Check timeoutPrompt: text parameter is out upper bound

		function Test:SetGlobalProperties_timeoutPrompt_text_IsOutUpperBound_501_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_c",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.27
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.28
	--Description: Check timeoutPrompt: text parameter contains escape characters _NewLineCharacter_

		function Test:SetGlobalProperties_timeoutPrompt_text__NewLineCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "\n",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.28
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.29
	--Description: Check timeoutPrompt: text parameter contains escape characters _TabChacracter_

		function Test:SetGlobalProperties_timeoutPrompt_text__TabChacracter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "\t",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.29
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.30
	--Description: Check timeoutPrompt: text parameter contains escape characters _SpaceCharacter_

		function Test:SetGlobalProperties_timeoutPrompt_text__SpaceCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = " ",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.30
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.31
	--Description: Check vrHelpTitle parameter is wrong type

		function Test:SetGlobalProperties_vrHelpTitle_IsWrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = 123,
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.31
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.32
	--Description: Check vrHelpTitle parameter is lower bound

		function Test:SetGlobalProperties_vrHelpTitle_IsOutLowerBound_0_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.32
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.33
	--Description: Check vrHelpTitle parameter is out upper bound

		function Test:SetGlobalProperties_vrHelpTitle_IsOutUpperBound_501_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_c",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.33
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.34
	--Description: Check vrHelpTitle parameter contains escape characters (new line)

		function Test:SetGlobalProperties_vrHelpTitle__NewLineCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "\n",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.34
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.35
	--Description: Check vrHelpTitle parameter contains escape characters (tab)

		function Test:SetGlobalProperties_vrHelpTitle__TabChacracter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "\t",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.35
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.36
	--Description: Check vrHelpTitle parameter contains escape characters (spaces)

		function Test:SetGlobalProperties_vrHelpTitle__SpaceCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = " ",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.36
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.37
	--Description: Check vrHelp parameter is wrong type

		function Test:SetGlobalProperties_vrHelp_Array_WrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 123,
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.37
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.38
	--Description: Check vrHelp parameter is out lower bound

		function Test:SetGlobalProperties_vrHelp_Array_Outminsize_0_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{

				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.38
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.39
	--Description: Check vrHelp parameter is out upper bound

		function Test:SetGlobalProperties_vrHelp_Array_Outmaxsize_101_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_001"
					},
					{
						position = 2,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_002"
					},
					{
						position = 3,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_003"
					},
					{
						position = 4,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_004"
					},
					{
						position = 5,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_005"
					},
					{
						position = 6,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_006"
					},
					{
						position = 7,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_007"
					},
					{
						position = 8,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_008"
					},
					{
						position = 9,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_009"
					},
					{
						position = 10,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_010"
					},
					{
						position = 11,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_011"
					},
					{
						position = 12,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_012"
					},
					{
						position = 13,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_013"
					},
					{
						position = 14,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_014"
					},
					{
						position = 15,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_015"
					},
					{
						position = 16,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_016"
					},
					{
						position = 17,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_017"
					},
					{
						position = 18,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_018"
					},
					{
						position = 19,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_019"
					},
					{
						position = 20,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_020"
					},
					{
						position = 21,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_021"
					},
					{
						position = 22,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_022"
					},
					{
						position = 23,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_023"
					},
					{
						position = 24,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_024"
					},
					{
						position = 25,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_025"
					},
					{
						position = 26,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_026"
					},
					{
						position = 27,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_027"
					},
					{
						position = 28,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_028"
					},
					{
						position = 29,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_029"
					},
					{
						position = 30,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_030"
					},
					{
						position = 31,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_031"
					},
					{
						position = 32,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_032"
					},
					{
						position = 33,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_033"
					},
					{
						position = 34,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_034"
					},
					{
						position = 35,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_035"
					},
					{
						position = 36,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_036"
					},
					{
						position = 37,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_037"
					},
					{
						position = 38,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_038"
					},
					{
						position = 39,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_039"
					},
					{
						position = 40,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_040"
					},
					{
						position = 41,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_041"
					},
					{
						position = 42,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_042"
					},
					{
						position = 43,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_043"
					},
					{
						position = 44,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_044"
					},
					{
						position = 45,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_045"
					},
					{
						position = 46,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_046"
					},
					{
						position = 47,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_047"
					},
					{
						position = 48,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_048"
					},
					{
						position = 49,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_049"
					},
					{
						position = 50,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_050"
					},
					{
						position = 51,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_051"
					},
					{
						position = 52,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_052"
					},
					{
						position = 53,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_053"
					},
					{
						position = 54,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_054"
					},
					{
						position = 55,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_055"
					},
					{
						position = 56,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_056"
					},
					{
						position = 57,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_057"
					},
					{
						position = 58,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_058"
					},
					{
						position = 59,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_059"
					},
					{
						position = 60,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_060"
					},
					{
						position = 61,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_061"
					},
					{
						position = 62,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_062"
					},
					{
						position = 63,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_063"
					},
					{
						position = 64,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_064"
					},
					{
						position = 65,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_065"
					},
					{
						position = 66,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_066"
					},
					{
						position = 67,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_067"
					},
					{
						position = 68,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_068"
					},
					{
						position = 69,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_069"
					},
					{
						position = 70,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_070"
					},
					{
						position = 71,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_071"
					},
					{
						position = 72,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_072"
					},
					{
						position = 73,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_073"
					},
					{
						position = 74,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_074"
					},
					{
						position = 75,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_075"
					},
					{
						position = 76,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_076"
					},
					{
						position = 77,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_077"
					},
					{
						position = 78,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_078"
					},
					{
						position = 79,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_079"
					},
					{
						position = 80,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_080"
					},
					{
						position = 81,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_081"
					},
					{
						position = 82,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_082"
					},
					{
						position = 83,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_083"
					},
					{
						position = 84,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_084"
					},
					{
						position = 85,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_085"
					},
					{
						position = 86,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_086"
					},
					{
						position = 87,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_087"
					},
					{
						position = 88,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_088"
					},
					{
						position = 89,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_089"
					},
					{
						position = 90,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_090"
					},
					{
						position = 91,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_091"
					},
					{
						position = 92,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_092"
					},
					{
						position = 93,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_093"
					},
					{
						position = 94,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_094"
					},
					{
						position = 95,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_095"
					},
					{
						position = 96,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_096"
					},
					{
						position = 97,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_097"
					},
					{
						position = 98,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_098"
					},
					{
						position = 99,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_099"
					},
					{
						position = 100,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_100"
					},
					{
						position = 101,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item_101"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.39
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.40
	--Description: Check vrHelp parameter contains an array with only one empty item

		function Test:SetGlobalProperties_vrHelp_Array_ContainAnEmptyItem_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{

					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.40
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.41
	--Description: Check vrHelp parameter is wrong type

		function Test:SetGlobalProperties_vrHelp_WrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					123
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.41
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.42
	--Description: Check vrHelp: position parameter is missed

		function Test:SetGlobalProperties_vrHelp_position_IsMising_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.42
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.43
	--Description: Check vrHelpposition parameter is wrong type

		function Test:SetGlobalProperties_vrHelp_position_IsWrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = "123",
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.43
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.44
	--Description: Check vrHelpposition parameter is out lower bound

		function Test:SetGlobalProperties_vrHelp_position_IsOutLowerBound_0_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 0,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.44
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.45
	--Description: Check vrHelpposition parameter is out upper bound

		function Test:SetGlobalProperties_vrHelp_position_IsOutUpperBound_101_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 101,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.45
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.46
	--Description: Check vrHelp: text parameter is missed

		function Test:SetGlobalProperties_vrHelp_text_IsMising_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						}
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.46
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.47
	--Description: Check vrHelptext parameter is wrong type

		function Test:SetGlobalProperties_vrHelp_text_IsWrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = 123
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.47
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.48
	--Description: Check vrHelptext parameter is lower bound

		function Test:SetGlobalProperties_vrHelp_text_IsOutLowerBound_0_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = ""
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.48
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.49
	--Description: Check vrHelptext parameter is out upper bound

		function Test:SetGlobalProperties_vrHelp_text_IsOutUpperBound_501_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_c"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.49
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.50
	--Description: Check vrHelptext parameter contains escape characters _NewLineCharacter_

		function Test:SetGlobalProperties_vrHelp_text__NewLineCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "\n"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.50
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.51
	--Description: Check vrHelptext parameter contains escape characters _TabChacracter_

		function Test:SetGlobalProperties_vrHelp_text__TabChacracter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "\t"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.51
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.52
	--Description: Check vrHelptext parameter contains escape characters _SpaceCharacter_

		function Test:SetGlobalProperties_vrHelp_text__SpaceCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = " "
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.52
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.53
	--Description: Check vrHelp: image parameter is missed

		function Test:SetGlobalProperties_vrHelp_image_IsMising_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case NegativeRequestCheck.1.53
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.54
	--Description: Check vrHelpimage parameter is empty (missing all children Items)

		function Test:SetGlobalProperties_vrHelp_image_empty_missingallchildrenItems_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{

						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.54
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.55
	--Description: Check vrHelpimage parameter is wrong type

		function Test:SetGlobalProperties_vrHelp_image_WrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 123,
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.55
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.56
	--Description: Check vrHelpimage: imageType parameter is missed

		function Test:SetGlobalProperties_vrHelp_image_imageType_IsMising_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.56
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.57
	--Description: Check image: imageType parameter is wrong value

		function Test:SetGlobalProperties_vrHelp_image_imageType_WrongValue_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "Wrong Value"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.57
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.58
	--Description: Check vrHelpimage: value parameter is missed

		function Test:SetGlobalProperties_vrHelp_image_value_IsMising_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.58
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.59
	--Description: Check image: value parameter is wrong type

		function Test:SetGlobalProperties_vrHelp_image_value_IsWrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = 123,
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.59
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.60
	--Description: Check image: value parameter is out upper bound

		function Test:SetGlobalProperties_vrHelp_image_value_IsOutUpperBound_65536_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_cB6_vA7_bB8_nA9_mB0_qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_j",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.60
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.61
	--Description: Check image: value parameter contains escape character (new line)

		function Test:SetGlobalProperties_vrHelp_image_value__NewLineCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "\n",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.61
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.62
	--Description: Check image: value parameter contains escape character (tab)

		function Test:SetGlobalProperties_vrHelp_image_value__TabChacracter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "\t",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.62
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.63
	--Description: Check image: value parameter contains escape character (spaces)

		function Test:SetGlobalProperties_vrHelp_image_value__SpaceCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = " ",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.63
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.64
	--Description: Check image: value parameter is not an existing file

		function Test:SetGlobalProperties_vrHelp_image_value_IsNotExist_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "NotExistImage.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.64
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.65
	--Description: Check menuTitle parameter is wrong type

		function Test:SetGlobalProperties_menuTitle_IsWrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = 123,
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.65
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.66
	--Description: Check menuTitle parameter is lower bound

		function Test:SetGlobalProperties_menuTitle_IsOutLowerBound_0_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.66
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.67
	--Description: Check menuTitle parameter is out upper bound

		function Test:SetGlobalProperties_menuTitle_IsOutUpperBound_501_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_c",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.67
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.68
	--Description: Check menuTitle parameter contains escape characters (new line)

		function Test:SetGlobalProperties_menuTitle__NewLineCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "\n",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.68
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.69
	--Description: Check menuTitle parameter contains escape characters (tab)

		function Test:SetGlobalProperties_menuTitle__TabChacracter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "\t",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.69
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.70
	--Description: Check menuTitle parameter contains escape characters (spaces)

		function Test:SetGlobalProperties_menuTitle__SpaceCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = " ",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.70
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.71
	--Description: Check menuIcon parameter is empty (missing all children Items)

		function Test:SetGlobalProperties_menuIcon_empty_missingallchildrenItems_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{

				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.71
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.72
	--Description: Check menuIcon parameter is wrong type

		function Test:SetGlobalProperties_menuIcon_WrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 123,
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.72
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.73
	--Description: Check menuIcon: imageType parameter is missed

		function Test:SetGlobalProperties_menuIcon_imageType_IsMising_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.73
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.74
	--Description: Check menuIcon: imageType parameter is wrong value

		function Test:SetGlobalProperties_menuIcon_imageType_WrongValue_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "Wrong Value"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.74
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.75
	--Description: Check menuIcon: value parameter is missed

		function Test:SetGlobalProperties_menuIcon_value_IsMising_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.75
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.76
	--Description: Check menuIcon: value parameter is wrong type

		function Test:SetGlobalProperties_menuIcon_value_IsWrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = 123,
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.76
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.77
	--Description: Check menuIcon: value parameter is out upper bound

		function Test:SetGlobalProperties_menuIcon_value_IsOutUpperBound_65536_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_cB6_vA7_bB8_nA9_mB0_qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_j",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.77
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.78
	--Description: Check menuIcon: value parameter contains escape character (new line)

		function Test:SetGlobalProperties_menuIcon_value__NewLineCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "\n",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.78
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.79
	--Description: Check menuIcon: value parameter contains escape character (tab)

		function Test:SetGlobalProperties_menuIcon_value__TabChacracter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "\t",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.79
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.80
	--Description: Check menuIcon: value parameter contains escape character (spaces)

		function Test:SetGlobalProperties_menuIcon_value__SpaceCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = " ",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.80
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.81
	--Description: Check menuIcon: value parameter is not an existing file

		function Test:SetGlobalProperties_menuIcon_value_IsNotExist_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "NotExistImage.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.81
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.82
	--Description: Check keyboardProperties parameter is empty (missed all non mandatory child items

		function Test:SetGlobalProperties_keyboardProperties_Empty_MissedAllChildrenItems_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				keyboardProperties = 
				{

				}
			})		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties")
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)
			:ValidIf(function(_,data)
				if 
					data.params.keyboardProperties and
					#data.params.keyboardProperties == 0 then
						return true
				elseif
					data.params.keyboardProperties == nil then
						print( "\27[31m UI.SetGlobalProperties request came without keyboardProperties  \27[0m " )
						return false
				else 
					print( "\27[31m UI.SetGlobalProperties request came with some unexpected values of keyboardProperties, array length is " .. tostring(#data.params.keyboardProperties) .. " \27[0m " )
						return false
				end

			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case NegativeRequestCheck.1.82
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.83
	--Description: Check keyboardProperties parameter is wrong type

		function Test:SetGlobalProperties_keyboardProperties_WrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 123
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.83
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.84
	--Description: Check keyboardProperties: language parameter is missed

		function Test:SetGlobalProperties_keyboardProperties_language_IsMising_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					autoCompleteText = "Daemon, Freedom",
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047
					limitedCharacterList = 
					{
						"a"
					}]=]
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case NegativeRequestCheck.1.84
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.85
	--Description: Check keyboardPropertieslanguage parameter is wrong value

		function Test:SetGlobalProperties_keyboardProperties_language_WrongValue_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "Wrong Value",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.85
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.86
	--Description: Check keyboardProperties: keyboardLayout parameter is missed

		function Test:SetGlobalProperties_keyboardProperties_keyboardLayout_IsMising_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					autoCompleteText = "Daemon, Freedom",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047
					limitedCharacterList = 
					{
						"a"
					}]=]
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case NegativeRequestCheck.1.86
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.87
	--Description: Check keyboardPropertieskeyboardLayout parameter is wrong value

		function Test:SetGlobalProperties_keyboardProperties_keyboardLayout_WrongValue_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "Wrong Value",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.87
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.88
	--Description: Check keyboardProperties: keypressMode parameter is missed

		function Test:SetGlobalProperties_keyboardProperties_keypressMode_IsMising_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom",
					--[=[ TODO: update after resolving APPLINK-16047
					limitedCharacterList = 
					{
						"a"
					}]=]
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case NegativeRequestCheck.1.88
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.89
	--Description: Check keyboardPropertieskeypressMode parameter is wrong value

		function Test:SetGlobalProperties_keyboardProperties_keypressMode_WrongValue_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "Wrong Value",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.89
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.90
	--Description: Check keyboardProperties: limitedCharacterList parameter is missed

		function Test:SetGlobalProperties_keyboardProperties_limitedCharacterList_IsMising_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					autoCompleteText = "Daemon, Freedom",
					language = "EN-US"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case NegativeRequestCheck.1.90
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.91
	--Description: Check limitedCharacterList parameter is wrong type

		function Test:SetGlobalProperties_keyboardProperties_limitedCharacterList_Array_WrongType_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					limitedCharacterList = 123,
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.91
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.92
	--Description: Check limitedCharacterList parameter is out lower bound

		function Test:SetGlobalProperties_keyboardProperties_limitedCharacterList_Array_IsOutLowerBound_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					limitedCharacterList = 
					{

					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.92
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.93
	--Description: Check limitedCharacterList parameter is out upper bound

		function Test:SetGlobalProperties_keyboardProperties_limitedCharacterList_Array_IsOutUpperBound_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					limitedCharacterList = 
					{
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q",
						"q"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.93
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.94
	--Description: Check limitedCharacterList parameter array is zero size

		--It is covered by TC SetGlobalProperties_keyboardProperties_limitedCharacterList_Array_IsOutLowerBound_INVALID_DATA
		
	--End test case NegativeRequestCheck.1.94
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.95
	--Description: Check keyboardPropertieslimitedCharacterList parameter is wrong type

		function Test:SetGlobalProperties_keyboardProperties_limitedCharacterList_IsWrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						123
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.95
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.96
	--Description: Check keyboardPropertieslimitedCharacterList parameter is lower bound

		function Test:SetGlobalProperties_keyboardProperties_limitedCharacterList_IsOutLowerBound_0_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						""
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.96
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.97
	--Description: Check keyboardPropertieslimitedCharacterList parameter is out upper bound

		function Test:SetGlobalProperties_keyboardProperties_limitedCharacterList_IsOutUpperBound_2_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"qA"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.97
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.98
	--Description: Check keyboardPropertieslimitedCharacterList parameter contains escape character (tab)

		function Test:SetGlobalProperties_keyboardProperties_limitedCharacterList__TabChacracter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"\t"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.98
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.99
	--Description: Check keyboardPropertieslimitedCharacterList parameter contains escape character (new line)

		function Test:SetGlobalProperties_keyboardProperties_limitedCharacterList__NewLineCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"\n"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.99
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.100
	--Description: Check keyboardPropertieslimitedCharacterList parameter contains escape character (spaces)

		function Test:SetGlobalProperties_keyboardProperties_limitedCharacterList__SpaceCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						" "
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.100
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.101
	--Description: Check keyboardProperties: autoCompleteText parameter is missed

		function Test:SetGlobalProperties_keyboardProperties_autoCompleteText_IsMising_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")			
		end

	--End test case NegativeRequestCheck.1.101
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.102
	--Description: Check keyboardPropertiesautoCompleteText parameter is wrong type

		function Test:SetGlobalProperties_keyboardProperties_autoCompleteText_IsWrongType_123_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = 123
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.102
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.103
	--Description: Check keyboardPropertiesautoCompleteText parameter is lower bound

		function Test:SetGlobalProperties_keyboardProperties_autoCompleteText_IsOutLowerBound_0_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = ""
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.103
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.104
	--Description: Check keyboardPropertiesautoCompleteText parameter is out upper bound

		function Test:SetGlobalProperties_keyboardProperties_autoCompleteText_IsOutUpperBound_1001_INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_jA1_kB2_lA3_zB4_xA5_cB6_vA7_bB8_nA9_mB0_qA1_wB2_eA3_rB4_tA5_yB6_uA7_iB8_oA9_pB0_aA1_sB2_dA3_fB4_gA5_hB6_jA7_kB8_lA9_zB0_xA1_cB2_vA3_bB4_nA5_mB6_qA7_wB8_eA9_rB0_tA1_yB2_uA3_iB4_oA5_pB6_aA7_sB8_dA9_fB0_gA1_hB2_jA3_kB4_lA5_zB6_xA7_cB8_vA9_bB0_nA1_mB2_qA3_wB4_eA5_rB6_tA7_yB8_uA9_iB0_oA1_pB2_aA3_sB4_dA5_fB6_gA7_hB8_jA9_kB0_lA1_zB2_xA3_cB4_vA5_bB6_nA7_mB8_qA9_wB0_eA1_rB2_tA3_yB4_uA5_iB6_oA7_pB8_aA9_sB0_dA1_fB2_gA3_hB4_jA5_kB6_lA7_zB8_xA9_cB0_vA1_bB2_nA3_mB4_qA5_wB6_eA7_rB8_tA9_yB0_uA1_iB2_oA3_pB4_aA5_sB6_dA7_fB8_gA9_hB0_j"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.104
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.105
	--Description: Check keyboardPropertiesautoCompleteText parameter contains escape characters (new line)

		function Test:SetGlobalProperties_keyboardProperties_autoCompleteText__NewLineCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "\n"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.105
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.106
	--Description: Check keyboardPropertiesautoCompleteText parameter contains escape characters (tab)

		function Test:SetGlobalProperties_keyboardProperties_autoCompleteText__TabChacracter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "\t"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.106
	-----------------------------------------------------------------------------------------

	--Begin test case NegativeRequestCheck.1.107
	--Description: Check keyboardPropertiesautoCompleteText parameter contains escape characters (spaces)

		function Test:SetGlobalProperties_keyboardProperties_autoCompleteText__SpaceCharacter__INVALID_DATA()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = " "
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case NegativeRequestCheck.1.107
	-----------------------------------------------------------------------------------------

--End test case NegativeRequestCheck.1


----------------------------------------------------------------------------------------------
----------------------------------------IV TEST BLOCK-----------------------------------------
---------------------------------------Result codes check--------------------------------------
----------------------------------------------------------------------------------------------

		--------Checks-----------
		-- check all pairs resultCode+success
		-- check should be made sequentially (if it is possible):
		-- case resultCode + success true
		-- case resultCode + success false
			--For example:
				-- first case checks ABORTED + true
				-- second case checks ABORTED + false
			    -- third case checks REJECTED + true
				-- fourth case checks REJECTED + false




	--Begin test case ResultCodeCheck.1
	--Description: resultCode APPLICATION_NOT_REGISTERED

		--Requirement id in JAMA: SDLAQ-CRS-388
		
		--Verification criteria: SDL sends APPLICATION_NOT_REGISTERED result code when the app sends SetGlobalProperties request within the same connection before RegisterAppInterface has been yet performed.

		--Precondition: Create new session
		commonSteps:precondition_AddNewSession()
					
		function Test:SetGlobalProperties_resultCode_APPLICATION_NOT_REGISTERED()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession2:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			self.mobileSession2:ExpectResponse(cid, { success = false, resultCode = "APPLICATION_NOT_REGISTERED"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			self.mobileSession2:ExpectNotification("OnHashChange",{})
			:Times(0)
		end

	--End test case ResultCodeCheck.1
	-----------------------------------------------------------------------------------------

	--Begin test case ResultCodeCheck.2
	--Description: resultCode REJECTED

		--Requirement id in JAMA: SDLAQ-CRS-389

		--Verification criteria:
			--1. In case SDL receives REJECTED result code for the RPC from HMI, SDL must transfer REJECTED resultCode with adding "success:false" to mobile app.
			--2. SDL rejects the request with REJECTED resultCode when vrHelpItems are omitted and the vrHelpTitle is provided at the same time.
			--3. SDL rejects the request with REJECTED resultCode when vrHelpTitle is omitted and the vrHelpItems are provided at the same time.
			--4. SDL rejects the request with REJECTED resultCode in case the list of VR Help Items contains non-sequential or not started from 1 positions

		--Begin test case ResultCodeCheck.2.1
		--Description: "1. In case SDL receives REJECTED result code for the RPC from HMI, SDL must transfer REJECTED resultCode with adding "success:false" to mobile app."

			--UI responses REJECTED
			function Test:SetGlobalProperties_UI_ResultCode_REJECTED()
			
				--mobile side: sending SetGlobalProperties request
				local cid = self.mobileSession:SendRPC("SetGlobalProperties",
				{
					menuTitle = "Menu Title",
					timeoutPrompt = 
					{
						{
							text = "Timeout prompt",
							type = "TEXT"
						}
					},
					vrHelp = 
					{
						{
							position = 1,
							image = 
							{
								value = "action.png",
								imageType = "DYNAMIC"
							},
							text = "VR help item"
						}
					},
					menuIcon = 
					{
						value = "action.png",
						imageType = "DYNAMIC"
					},
					helpPrompt = 
					{
						{
							text = "Help prompt",
							type = "TEXT"
						}
					},
					vrHelpTitle = "VR help title",
					keyboardProperties = 
					{
						keyboardLayout = "QWERTY",
						keypressMode = "SINGLE_KEYPRESS",
						limitedCharacterList = 
						{
							"a"
						},
						language = "EN-US",
						autoCompleteText = "Daemon, Freedom"
					}
				})
			

				--hmi side: expect TTS.SetGlobalProperties request
				EXPECT_HMICALL("TTS.SetGlobalProperties",
				{
					timeoutPrompt = 
					{
						{
							text = "Timeout prompt",
							type = "TEXT"
						}
					},
					helpPrompt = 
					{
						{
							text = "Help prompt",
							type = "TEXT"
						}
					}
				})
				:Timeout(iTimeout)
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)

			

				--hmi side: expect UI.SetGlobalProperties request
				EXPECT_HMICALL("UI.SetGlobalProperties",
				{
					menuTitle = "Menu Title",
					vrHelp = 
					{
						{
							position = 1,
							--[=[ TODO: update after resolving APPLINK-16052

							image = 
							{
								imageType = "DYNAMIC",
								value = strAppFolder .. "action.png"
							},]=]
							text = "VR help item"
						}
					},
					menuIcon = 
					{
						imageType = "DYNAMIC",
						value = strAppFolder .. "action.png"
					},
					vrHelpTitle = "VR help title",
					keyboardProperties = 
					{
						keyboardLayout = "QWERTY",
						keypressMode = "SINGLE_KEYPRESS",
						--[=[ TODO: update after resolving APPLINK-16047

						limitedCharacterList = 
						{
							"a"
						},]=]
						language = "EN-US",
						autoCompleteText = "Daemon, Freedom"
					}
				})
				:Timeout(iTimeout)
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "REJECTED", {})
				end)

			

				--mobile side: expect SetGlobalProperties response
				EXPECT_RESPONSE(cid, { success = false, resultCode = "REJECTED"})
				:Timeout(iTimeout)				
				
				--mobile side: expect OnHashChange notification
				EXPECT_NOTIFICATION("OnHashChange")
				:Times(0)

				DelayedExp(2000)
			end

			--TTS responses REJECTED
			function Test:SetGlobalProperties_TTS_ResultCode_REJECTED()
			
				--mobile side: sending SetGlobalProperties request
				local cid = self.mobileSession:SendRPC("SetGlobalProperties",
				{
					menuTitle = "Menu Title",
					timeoutPrompt = 
					{
						{
							text = "Timeout prompt",
							type = "TEXT"
						}
					},
					vrHelp = 
					{
						{
							position = 1,
							image = 
							{
								value = "action.png",
								imageType = "DYNAMIC"
							},
							text = "VR help item"
						}
					},
					menuIcon = 
					{
						value = "action.png",
						imageType = "DYNAMIC"
					},
					helpPrompt = 
					{
						{
							text = "Help prompt",
							type = "TEXT"
						}
					},
					vrHelpTitle = "VR help title",
					keyboardProperties = 
					{
						keyboardLayout = "QWERTY",
						keypressMode = "SINGLE_KEYPRESS",
						limitedCharacterList = 
						{
							"a"
						},
						language = "EN-US",
						autoCompleteText = "Daemon, Freedom"
					}
				})
			

				--hmi side: expect TTS.SetGlobalProperties request
				EXPECT_HMICALL("TTS.SetGlobalProperties",
				{
					timeoutPrompt = 
					{
						{
							text = "Timeout prompt",
							type = "TEXT"
						}
					},
					helpPrompt = 
					{
						{
							text = "Help prompt",
							type = "TEXT"
						}
					}
				})
				:Timeout(iTimeout)
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "REJECTED", {})
				end)

			

				--hmi side: expect UI.SetGlobalProperties request
				EXPECT_HMICALL("UI.SetGlobalProperties",
				{
					menuTitle = "Menu Title",
					vrHelp = 
					{
						{
							position = 1,
							--[=[ TODO: update after resolving APPLINK-16052

							image = 
							{
								imageType = "DYNAMIC",
								value = strAppFolder .. "action.png"
							},]=]
							text = "VR help item"
						}
					},
					menuIcon = 
					{
						imageType = "DYNAMIC",
						value = strAppFolder .. "action.png"
					},
					vrHelpTitle = "VR help title",
					keyboardProperties = 
					{
						keyboardLayout = "QWERTY",
						keypressMode = "SINGLE_KEYPRESS",
						--[=[ TODO: update after resolving APPLINK-16047

						limitedCharacterList = 
						{
							"a"
						},]=]
						language = "EN-US",
						autoCompleteText = "Daemon, Freedom"
					}
				})
				:Timeout(iTimeout)
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)

			

				--mobile side: expect SetGlobalProperties response
				EXPECT_RESPONSE(cid, { success = false, resultCode = "REJECTED"})
				:Timeout(iTimeout)
						
				--mobile side: expect OnHashChange notification is not send to mobile
				EXPECT_NOTIFICATION("OnHashChange")
				:Times(0)
			end

		--End test case ResultCodeCheck.2.1
		-----------------------------------------------------------------------------------------		

		--Begin test case ResultCodeCheck.2.2
		--Description: "2. SDL rejects the request with REJECTED resultCode when vrHelpItems are omitted and the vrHelpTitle is provided at the same time."


			function Test:SetGlobalProperties_resultCode_REJECTED_omitted_vrHelpItems()
			
				--mobile side: sending SetGlobalProperties request
				local cid = self.mobileSession:SendRPC("SetGlobalProperties",
				{
					menuTitle = "Menu Title",
					timeoutPrompt = 
					{
						{
							text = "Timeout prompt",
							type = "TEXT"
						}
					},
					menuIcon = 
					{
						value = "action.png",
						imageType = "DYNAMIC"
					},
					helpPrompt = 
					{
						{
							text = "Help prompt",
							type = "TEXT"
						}
					},
					vrHelpTitle = "VR help title",
					keyboardProperties = 
					{
						keyboardLayout = "QWERTY",
						keypressMode = "SINGLE_KEYPRESS",
						limitedCharacterList = 
						{
							"a"
						},
						language = "EN-US",
						autoCompleteText = "Daemon, Freedom"
					}
				})
			

				--mobile side: expect SetGlobalProperties response
				EXPECT_RESPONSE(cid, { success = false, resultCode = "REJECTED"})
				:Timeout(iTimeout)
						
				--mobile side: expect OnHashChange notification is not send to mobile
				EXPECT_NOTIFICATION("OnHashChange")
				:Times(0)
			end
		
		
		--End test case ResultCodeCheck.2.2
		-----------------------------------------------------------------------------------------		

		--Begin test case ResultCodeCheck.2.3
		--Description: "3. SDL rejects the request with REJECTED resultCode when vrHelpTitle is omitted and the vrHelpItems are provided at the same time."


			function Test:SetGlobalProperties_resultCode_REJECTED_omitted_vrHelpTitle()
			
				--mobile side: sending SetGlobalProperties request
				local cid = self.mobileSession:SendRPC("SetGlobalProperties",
				{
					menuTitle = "Menu Title",
					timeoutPrompt = 
					{
						{
							text = "Timeout prompt",
							type = "TEXT"
						}
					},
					vrHelp = 
					{
						{
							position = 1,
							image = 
							{
								value = "action.png",
								imageType = "DYNAMIC"
							},
							text = "VR help item"
						}
					},
					menuIcon = 
					{
						value = "action.png",
						imageType = "DYNAMIC"
					},
					helpPrompt = 
					{
						{
							text = "Help prompt",
							type = "TEXT"
						}
					},
					keyboardProperties = 
					{
						keyboardLayout = "QWERTY",
						keypressMode = "SINGLE_KEYPRESS",
						limitedCharacterList = 
						{
							"a"
						},
						language = "EN-US",
						autoCompleteText = "Daemon, Freedom"
					}
				})
			


				--mobile side: expect SetGlobalProperties response
				EXPECT_RESPONSE(cid, { success = false, resultCode = "REJECTED"})
				:Timeout(iTimeout)
						
				--mobile side: expect OnHashChange notification is not send to mobile
				EXPECT_NOTIFICATION("OnHashChange")
				:Times(0)
			end
		
				
		--End test case ResultCodeCheck.2.3
		-----------------------------------------------------------------------------------------		


		--Begin test case ResultCodeCheck.2.4
		--Description: "4. SDL rejects the request with REJECTED resultCode in case the list of VR Help Items contains non-sequential or not started from 1 positions"


			function Test:SetGlobalProperties_resultCode_REJECTED_nonsequential_vrHelpItems()
			
				--mobile side: sending SetGlobalProperties request
				local cid = self.mobileSession:SendRPC("SetGlobalProperties",
				{
					menuTitle = "Menu Title",
					timeoutPrompt = 
					{
						{
							text = "Timeout prompt",
							type = "TEXT"
						}
					},
					vrHelp = 
					{
						{
							position = 1,
							image = 
							{
								value = "action.png",
								imageType = "DYNAMIC"
							},
							text = "VR help item"
						},
						{
							position = 3,
							image = 
							{
								value = "action.png",
								imageType = "DYNAMIC"
							},
							text = "VR help item 3"
						}
					},
					menuIcon = 
					{
						value = "action.png",
						imageType = "DYNAMIC"
					},
					helpPrompt = 
					{
						{
							text = "Help prompt",
							type = "TEXT"
						}
					},
					vrHelpTitle = "VR help title",
					keyboardProperties = 
					{
						keyboardLayout = "QWERTY",
						keypressMode = "SINGLE_KEYPRESS",
						limitedCharacterList = 
						{
							"a"
						},
						language = "EN-US",
						autoCompleteText = "Daemon, Freedom"
					}
				})
			

				--mobile side: expect SetGlobalProperties response
				EXPECT_RESPONSE(cid, { success = false, resultCode = "REJECTED"})
				:Timeout(iTimeout)
						
				--mobile side: expect OnHashChange notification is not send to mobile
				EXPECT_NOTIFICATION("OnHashChange")
				:Times(0)
			end
		
				
		--End test case ResultCodeCheck.2.4
		-----------------------------------------------------------------------------------------		

		
	--End test case ResultCodeCheck.2
	-----------------------------------------------------------------------------------------



	--Begin test case ResultCodeCheck.3
	--Description: Check resultCode WARNINGS (true)

		--Requirement id in JAMA: SDLAQ-CRS-1330

		--Verification criteria: 
			--When "ttsChunks" are sent within the request but the type is different from "TEXT" , WARNINGS is returned as a result of request. Info parameter provides additional information about the case. General request result success=true in case of no errors from other components. 

			--When "ttsChunks" are sent within the request but the type is different from "TEXT", WARNINGS is returned as a result of request. Info parameter provides additional information about the case. General request result success=false in case of TTS is the only component which processes in the request. 		

		function Test:SetGlobalProperties_resultCode_WARNINGS_true()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "PRE_RECORDED" 
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "PRE_RECORDED"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending TTS.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "WARNINGS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "WARNINGS"})
			:Timeout(iTimeout)			
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case ResultCodeCheck.3
	-----------------------------------------------------------------------------------------
	
	
	--Begin test case ResultCodeCheck.4
	--Description: Check resultCode UNSUPPORTED_RESOURCE

		--Requirement id in JAMA: SDLAQ-CRS-1329

		--Verification criteria: SDL forwards UNSUPPORTED_RESOURCE to mobile

		--UI responses UNSUPPORTED_RESOURCE to SDL
		function Test:SetGlobalProperties_UI_ResultCode_UNSUPPORTED_RESOURCE()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "UNSUPPORTED_RESOURCE", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "UNSUPPORTED_RESOURCE"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")			
		end

		--TTS responses UNSUPPORTED_RESOURCE to SDL
		function Test:SetGlobalProperties_TTS_ResultCode_UNSUPPORTED_RESOURCE()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "UNSUPPORTED_RESOURCE", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "WARNINGS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case ResultCodeCheck.4
	-----------------------------------------------------------------------------------------


	--Begin test case ResultCodeCheck.5
	--Description: Check resultCode DISALLOWED

		--Requirement id in JAMA: SDLAQ-CRS-392

		--Verification criteria: 
			 --1. SDL must return "resultCode: DISALLOWED, success:false" to the RPC in case this RPC is omitted in the PolicyTable group(s) assigned to the app that requests this RPC.

			--2. SDL must return "resultCode: DISALLOWED, success:false" to the RPC in case this RPC is included to the PolicyTable group(s) assigned to the app that requests this RPC and the group has not yet received user's consents.

		
		--Begin test case ResultCodeCheck.5.1
		--Description: RPC is omitted in the PolicyTable group(s) assigned to the app

--[[TODO: check after resolving APPLINK-13101				
			--Description: Disallowed SetGlobalProperties
			
			--Precondition: Build policy table file
			local PTName = testCasesForPolicyTable:createPolicyTableWithoutAPI(APIName)
			
			--Precondition: Update policy table
			testCasesForPolicyTable:updatePolicy(PTName)
			
			function Test:SetGlobalProperties_resultCode_DISALLOWED()
			
				--mobile side: sending SetGlobalProperties request
				local cid = self.mobileSession:SendRPC("SetGlobalProperties",
				{
					menuTitle = "Menu Title",
					timeoutPrompt = 
					{
						{
							text = "Timeout prompt",
							type = "PRE_RECORDED" 
						}
					},
					vrHelp = 
					{
						{
							position = 1,
							image = 
							{
								value = "action.png",
								imageType = "DYNAMIC"
							},
							text = "VR help item"
						}
					},
					menuIcon = 
					{
						value = "action.png",
						imageType = "DYNAMIC"
					},
					helpPrompt = 
					{
						{
							text = "Help prompt",
							type = "TEXT"
						}
					},
					vrHelpTitle = "VR help title",
					keyboardProperties = 
					{
						keyboardLayout = "QWERTY",
						keypressMode = "SINGLE_KEYPRESS",
						limitedCharacterList = 
						{
							"a"
						},
						language = "EN-US",
						autoCompleteText = "Daemon, Freedom"
					}
				})
			

				--mobile side: expect SetGlobalProperties response
				EXPECT_RESPONSE(cid, { success = false, resultCode = "DISALLOWED"})
				:Timeout(iTimeout)
						
				--mobile side: expect OnHashChange notification is not send to mobile
				EXPECT_NOTIFICATION("OnHashChange")
				:Times(0)
			end

			
		--End test case ResultCodeCheck.5.1
		-----------------------------------------------------------------------------------------
		
		--Begin test case ResultCodeCheck.5.2
		--Description: RPC is included to the PolicyTable group(s) assigned to the app. And the group has not yet received user's consents.

			--Precondition: Build policy table file
			local HmiLevels = {"FULL", "LIMITED", "BACKGROUND"}
			local PTName = testCasesForPolicyTable:createPolicyTable(APIName, HmiLevels)
			
			--Precondition: Update policy table
			local groupID = testCasesForPolicyTable:updatePolicy(PTName, "group1")
			
			--Precondition: User does not allow function group
			testCasesForPolicyTable:userConsent(groupID, "group1", false)		
		
			--Description: Send SetGlobalProperties when user not allowed
			function Test:SetGlobalProperties_resultCode_USER_DISALLOWED()
			
				--mobile side: sending SetGlobalProperties request
				local cid = self.mobileSession:SendRPC("SetGlobalProperties",
				{
					menuTitle = "Menu Title",
					timeoutPrompt = 
					{
						{
							text = "Timeout prompt",
							type = "PRE_RECORDED" 
						}
					},
					vrHelp = 
					{
						{
							position = 1,
							image = 
							{
								value = "action.png",
								imageType = "DYNAMIC"
							},
							text = "VR help item"
						}
					},
					menuIcon = 
					{
						value = "action.png",
						imageType = "DYNAMIC"
					},
					helpPrompt = 
					{
						{
							text = "Help prompt",
							type = "TEXT"
						}
					},
					vrHelpTitle = "VR help title",
					keyboardProperties = 
					{
						keyboardLayout = "QWERTY",
						keypressMode = "SINGLE_KEYPRESS",
						limitedCharacterList = 
						{
							"a"
						},
						language = "EN-US",
						autoCompleteText = "Daemon, Freedom"
					}
				})
			

				--mobile side: expect SetGlobalProperties response
				EXPECT_RESPONSE(cid, { success = false, resultCode = "USER_DISALLOWED"})
				:Timeout(iTimeout)
						
				--mobile side: expect OnHashChange notification is not send to mobile
				EXPECT_NOTIFICATION("OnHashChange")
				:Times(0)
			end

			
			--Postcondition: User allows function group
			testCasesForPolicyTable:userConsent(groupID, "group1", true)	
		
		--End test case ResultCodeCheck.5.2
		-----------------------------------------------------------------------------------------
]]	

	
	--End test case ResultCodeCheck.5
	-----------------------------------------------------------------------------------------




----------------------------------------------------------------------------------------------
-----------------------------------------V TEST BLOCK-----------------------------------------
---------------------------------------HMI negative cases-------------------------------------
----------------------------------------------------------------------------------------------

		--------Checks-----------
		-- requests without responses from HMI
		-- invalid structure of response
		-- several responses from HMI to one request
		-- fake parameters
		-- HMI correlation id check
		-- wrong response with correct HMI correlation id


--Begin test case HMINegativeCheck
--Description: Check HMI negative cases

	--Requirement id in JAMA: SDLAQ-CRS-12

	--Verification criteria: The response contains 2 mandatory parameters "success" and "resultCode", "info" is sent if there is any additional information about the resultCode.

	
	--Begin test case HMINegativeCheck.1
	--Description: Check SetGlobalProperties requests without UI responses from HMI

		function Test:SetGlobalProperties_RequestWithoutUIResponsesFromHMI()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)


			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				--self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "GENERIC_ERROR", info = nil})
			:Timeout(12000)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
			:Timeout(12000)
		end

	--End test case HMINegativeCheck.1
	-----------------------------------------------------------------------------------------

	--Begin test case HMINegativeCheck.2
	--Description: Check SetGlobalProperties requests without TTS responses from HMI

		function Test:SetGlobalProperties_RequestWithoutTTSResponsesFromHMI()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})



			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				--self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)


			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "GENERIC_ERROR", info = nil})
			:Timeout(12000)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
			:Timeout(12000)
		end

	--End test case HMINegativeCheck.2
	-----------------------------------------------------------------------------------------

	--Begin test case HMINegativeCheck.3
	--Description: Check SetGlobalProperties requests without responses from HMI

		function Test:SetGlobalProperties_RequestWithoutResponsesFromHMI()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "GENERIC_ERROR", info = nil})
			:Timeout(12000)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
			:Timeout(12000)
		end

	--End test case HMINegativeCheck.3
	-----------------------------------------------------------------------------------------

	--Begin test case HMINegativeCheck.4
	--Description: Check responses from HMI (UI) with invalid structure

--[[TODO update after resolving APPLINK-14765

		--Requirement id in JAMA:
			--SDLAQ-CRS-11

		--Verification criteria:

		function Test:SetGlobalProperties_UI_InvalidStructureOfResponse()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:Send('{"id":'..tostring(data.id)..',"jsonrpc":"2.0", "code":0, "result":{"method":"UI.SetGlobalProperties"}}')
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case HMINegativeCheck.4
	-----------------------------------------------------------------------------------------

	--Begin test case HMINegativeCheck.5
	--Description: Check responses from HMI (TTS) with invalid structure

		--Requirement id in JAMA:
			--SDLAQ-CRS-11

		--Verification criteria:

		function Test:SetGlobalProperties_TTS_InvalidStructureOfResponse()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:Send('{"id":'..tostring(data.id)..',"jsonrpc":"2.0", "code":0, "result":{"method":"TTS.SetGlobalProperties"}}')
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case HMINegativeCheck.5
	]]
	-----------------------------------------------------------------------------------------

	--Begin test case HMINegativeCheck.6
	--Description: Check several responses from HMI (UI) to one request

		function Test:SetGlobalProperties_UI_SeveralResponseToOneRequest()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "INVALID_DATA", {})
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case HMINegativeCheck.6
	-----------------------------------------------------------------------------------------

	--Begin test case HMINegativeCheck.7
	--Description: Check several responses from HMI (TTS) to one request

		function Test:SetGlobalProperties_TTS_SeveralResponseToOneRequest()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "INVALID_DATA", {})
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case HMINegativeCheck.7
	-----------------------------------------------------------------------------------------
--[[TODO: update after resolving APPLINK-14765
	--Begin test case HMINegativeCheck.8
	--Description: Check responses from HMI (UI) with fake parameter

		--Requirement id in JAMA:
			--SDLAQ-CRS-11

		--Verification criteria:
			--SetGlobalProperties request ...

		function Test:SetGlobalProperties_UI_ResponseWithFakeParamater()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:Send('{"id":'..tostring(data.id)..',"jsonrpc":"2.0","result":{"code":0, "fakeParam":0, "method":"UI.SetGlobalProperties"}}')
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

	--End test case HMINegativeCheck.8
	-----------------------------------------------------------------------------------------

	--Begin test case HMINegativeCheck.9
	--Description: Check responses from HMI (TTS) with fake parameter

		--Requirement id in JAMA:
			--SDLAQ-CRS-11

		--Verification criteria:
			--SetGlobalProperties request ...

		function Test:SetGlobalProperties_TTS_ResponseWithFakeParamater()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:Send('{"id":'..tostring(data.id)..',"jsonrpc":"2.0","result":{"code":0, "fakeParam":0, "method":"TTS.SetGlobalProperties"}}')
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "INVALID_DATA"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

	--End test case HMINegativeCheck.9
	-----------------------------------------------------------------------------------------

]]--
	--Begin test case HMINegativeCheck.10
	--Description: Check UI wrong response with correct HMI correlation id

		--Requirement id in JAMA: SDLAQ-CRS-12

		--Verification criteria: The response contains 2 mandatory parameters "success" and "resultCode", "info" is sent if there is any additional information about the resultCode.

		function Test:SetGlobalProperties_UI_WrongResponse_WithCorrectHMICorrelationID()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending TTS.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, "UI.Show", "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "GENERIC_ERROR"})
			:Timeout(12000)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
			:Timeout(12000)
		end

	--End test case HMINegativeCheck.10
	-----------------------------------------------------------------------------------------

	--Begin test case HMINegativeCheck.11
	--Description: Check TTS wrong response with correct HMI correlation id

		--Requirement id in JAMA: SDLAQ-CRS-12

		--Verification criteria: The response contains 2 mandatory parameters "success" and "resultCode", "info" is sent if there is any additional information about the resultCode.

		function Test:SetGlobalProperties_TTS_WrongResponse_WithCorrectHMICorrelationID()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, "TTS.Speak", "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "GENERIC_ERROR"})
			:Timeout(12000)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
			:Timeout(12000)
		end

	--End test case HMINegativeCheck.11
	-----------------------------------------------------------------------------------------

	
	--Begin test case HMINegativeCheck.12
	--Description: Check UI wrong response with wrong HMI correlation id

		function Test:SetGlobalProperties_UI_Response_WithWrongHMICorrelationID_GENERIC_ERROR()
		

			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id + 1, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "GENERIC_ERROR"})
			:Timeout(12000)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
			:Timeout(12000)
		end

	--End test case CommonRequestCheck.12
	-----------------------------------------------------------------------------------------


	--Begin test case HMINegativeCheck.13
	--Description: Check TTS wrong response with wrong HMI correlation id

		--Requirement id in JAMA: SDLAQ-CRS-12

		--Verification criteria: The response contains 2 mandatory parameters "success" and "resultCode", "info" is sent if there is any additional information about the resultCode.

		function Test:SetGlobalProperties_TTS_Response_WithWrongHMICorrelationID_GENERIC_ERROR()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id + 1, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "GENERIC_ERROR"})
			:Timeout(12000)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
			:Timeout(12000)
		end

	--End test case HMINegativeCheck.13
	-----------------------------------------------------------------------------------------



----------------------------------------------------------------------------------------------
-----------------------------------------VI TEST BLOCK----------------------------------------
-------------------------Sequence with emulating of user's action(s)------------------------
----------------------------------------------------------------------------------------------


--Begin test suit SequenceCheck
--Description: TC's checks SDL behavior by processing
	-- different request sequence with timeout
	-- with emulating of user's actions

	--Begin test case SequenceCheck.1
	--Description: When registering the app as soon as the app gets HMI Level NONE, SDL sends TTS.SetGlobalProperties(helpPrompt[]) with an empty array of helpPrompts (just helpPrompts, no timeoutPrompt).


		function Test:Begin_TC_SetGlobalProperties_01()
			print("--------------------------------------------------------")
		end

		commonSteps:UnregisterApplication()	
		commonSteps:StartSession()

		function Test:Step_RegisterAppAndVerifyTTSGetProperties()
			
			self.mobileSession:StartService(7)
			:Do(function()	
					local CorIdRegister = self.mobileSession:SendRPC("RegisterAppInterface", config.application1.registerAppInterfaceParams)
					EXPECT_HMINOTIFICATION("BasicCommunication.OnAppRegistered", 
					{
					  application = 
					  {
						appName = config.application1.registerAppInterfaceParams.appName				
					  }
					})
					:Do(function(_,data)
					  self.applications[data.params.application.appName] = data.params.application.appID
						end)

					self.mobileSession:ExpectResponse(CorIdRegister, { success = true, resultCode = "SUCCESS" })
					:Timeout(2000)

					self.mobileSession:ExpectNotification("OnHMIStatus", {hmiLevel = "NONE", audioStreamingState = "NOT_AUDIBLE", systemContext = "MAIN"})
				end)
				
				
					
				--Verify_ helpPrompt _isEmpty()	
				--hmi side: expect TTS.SetGlobalProperties request
				EXPECT_HMICALL("TTS.SetGlobalProperties")
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)
				:ValidIf(function(_,data)
					if 
						data.params.timeoutPrompt then
						print( "\27[31m TTS.SetGlobalProperties request came with unexpected timeoutPrompt parameter. \27[0m " )
							return false
					elseif
						data.params.helpPrompt and
						#data.params.helpPrompt == 0 then
							return true
					elseif
						data.params.helpPrompt == nil then
							print( "\27[31m UI.SetGlobalProperties request came without helpPrompt  \27[0m " )
							return false
					else 
						print( "\27[31m UI.SetGlobalProperties request came with some unexpected values of helpPrompt, array length is " .. tostring(#data.params.helpPrompt) .. " \27[0m " )
							return false
					end

				end)
			
		end

		function Test:End_TC_SetGlobalProperties_01()
			print("--------------------------------------------------------")
		end

		--End test case SequenceCheck.1
		-----------------------------------------------------------------------------------------

		--Begin test case SequenceCheck.2
		--Description: When registering the app as soon as the app gets HMI Level BACKGROUND, SDL sends TTS.SetGlobalProperties(helpPrompt[]) with an empty array of helpPrompts (just helpPrompts, no timeoutPrompt).

		function Test:Begin_TC_SetGlobalProperties_02()
			print("--------------------------------------------------------")
		end

		commonSteps:UnregisterApplication()	
		commonSteps:StartSession()

		function Test:Step_RegisterAppAndVerifyTTSGetProperties_background()
			local RegisterParameters = copy_table(config.application1.registerAppInterfaceParams)
			RegisterParameters.appID = "background"
			RegisterParameters.appName = "background"
			
			self.mobileSession:StartService(7)
			:Do(function()	
					local CorIdRegister = self.mobileSession:SendRPC("RegisterAppInterface", RegisterParameters)
					EXPECT_HMINOTIFICATION("BasicCommunication.OnAppRegistered", 
					{
					  application = 
					  {
						appName = "background"			
					  }
					})
					:Do(function(_,data)
					  self.applications[data.params.application.appName] = data.params.application.appID
						end)

					self.mobileSession:ExpectResponse(CorIdRegister, { success = true, resultCode = "SUCCESS" })
					:Timeout(2000)

					self.mobileSession:ExpectNotification("OnHMIStatus", {hmiLevel = "BACKGROUND", audioStreamingState = "NOT_AUDIBLE", systemContext = "MAIN"})
				end)
				
				
					
				--Verify_ helpPrompt _isEmpty()	
				--hmi side: expect TTS.SetGlobalProperties request
				EXPECT_HMICALL("TTS.SetGlobalProperties")
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)
				:ValidIf(function(_,data)
					if 
						data.params.timeoutPrompt then
						print( "\27[31m TTS.SetGlobalProperties request came with unexpected timeoutPrompt parameter. \27[0m " )
							return false
					elseif
						data.params.helpPrompt and
						#data.params.helpPrompt == 0 then
							return true
					elseif
						data.params.helpPrompt == nil then
							print( "\27[31m UI.SetGlobalProperties request came without helpPrompt  \27[0m " )
							return false
					else 
						print( "\27[31m UI.SetGlobalProperties request came with some unexpected values of helpPrompt, array length is " .. tostring(#data.params.helpPrompt) .. " \27[0m " )
							return false
					end

				end)
			
		end

		function Test:End_TC_SetGlobalProperties_02()
			print("--------------------------------------------------------")
		end

		--End test case SequenceCheck.2
		-----------------------------------------------------------------------------------------

		--Begin test case SequenceCheck.3
		--Description: Check for manual test case TC_SetGlobalProperties_02: SDL sends TTS.SetGlobalProperties request in 20 seconds from activation to FULL with the default list of HelpPrompts is a list of TTSChunks ( UI commands) defined as �TEXT� type, which are the list of the commands.

		function Test:Begin_TC_SetGlobalProperties_03()
			print("--------------------------------------------------------")
		end

		commonSteps:UnregisterApplication()	
		commonSteps:StartSession()

		function Test:Step_RegisterApp()

			self.mobileSession:StartService(7)
			:Do(function()	
					local CorIdRegister = self.mobileSession:SendRPC("RegisterAppInterface", config.application1.registerAppInterfaceParams)
					EXPECT_HMINOTIFICATION("BasicCommunication.OnAppRegistered", 
					{
					  application = 
					  {
						appName = config.application1.registerAppInterfaceParams.appName				
					  }
					})
					:Do(function(_,data)
					  self.applications[data.params.application.appName] = data.params.application.appID
						end)

					self.mobileSession:ExpectResponse(CorIdRegister, { success = true, resultCode = "SUCCESS" })
					:Timeout(2000)

					self.mobileSession:ExpectNotification("OnHMIStatus", {hmiLevel = "BACKGROUND", audioStreamingState = "NOT_AUDIBLE", systemContext = "MAIN"})
				end)
		end

		local TimeOfActivation
		function Test:ActivationApp()
			--hmi side: sending SDL.ActivateApp request
			local RequestId = self.hmiConnection:SendRequest("SDL.ActivateApp", { appID = self.applications[config.application1.registerAppInterfaceParams.appName]})

			EXPECT_HMIRESPONSE(RequestId)
			:Do(function(_,data)
				if
					data.result.isSDLAllowed ~= true then
					local RequestId = self.hmiConnection:SendRequest("SDL.GetUserFriendlyMessage", {language = "EN-US", messageCodes = {"DataConsent"}})
					
					--hmi side: expect SDL.GetUserFriendlyMessage message response
					--TODO: update after resolving APPLINK-16094.
					--EXPECT_HMIRESPONSE(RequestId,{result = {code = 0, method = "SDL.GetUserFriendlyMessage"}})
					EXPECT_HMIRESPONSE(RequestId)
					:Do(function(_,data)						
						--hmi side: send request SDL.OnAllowSDLFunctionality
						self.hmiConnection:SendNotification("SDL.OnAllowSDLFunctionality", {allowed = true, source = "GUI", device = {id = config.deviceMAC, name = "127.0.0.1"}})

						--hmi side: expect BasicCommunication.ActivateApp request
						EXPECT_HMICALL("BasicCommunication.ActivateApp")
						:Do(function(_,data)
							--hmi side: sending BasicCommunication.ActivateApp response
							self.hmiConnection:SendResponse(data.id,"BasicCommunication.ActivateApp", "SUCCESS", {})
						end)
						:Times(AnyNumber())
					end)

				end
			end)
		
			--mobile side: expect notification
			EXPECT_NOTIFICATION("OnHMIStatus", {hmiLevel = "FULL", systemContext = "MAIN"})
				:Do(function(_,data)
					TimeOfActivation = timestamp()
				end)
		end

		function Test:Step_AddCommand_Policies_Test()
			local cid = self.mobileSession:SendRPC("AddCommand",
			{
				cmdID = 11,
				menuParams = 	
				{ 
					--parentID = 1,
					--position = 0,
					menuName ="Policies Test"
				}, 
				vrCommands = 
				{ 
					"Policies Test",
					"Policies"
				}
			})
			
			--/* UI */
			EXPECT_HMICALL("UI.AddCommand", 
			{ 
				cmdID = 11,
				menuParams = 
				{ 
					--parentID = 1,	
					--position = 0,
					menuName ="Policies Test"
				}
			})
			:Do(function(_,data)
			self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)
			
			--/* VR */
			EXPECT_HMICALL("VR.AddCommand", 
			{ 
				cmdID = 11,
				vrCommands = 
				{
					"Policies Test",
					"Policies"
				}
			})
			:Do(function(_,data)
			self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)			
			
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS" })
			EXPECT_NOTIFICATION("OnHashChange")
		end 

		function Test:Step_AddCommand_XML_Test()
			local cid = self.mobileSession:SendRPC("AddCommand",
			{
				cmdID = 12,
				menuParams = 	
				{ 
					--parentID = 1,
					--position = 0,
					menuName ="XML Test"
				}, 
				vrCommands = 
				{ 
					"XML Test",
					"XML"
				}
			})
			
			--/* UI */
			EXPECT_HMICALL("UI.AddCommand", 
			{ 
				cmdID = 12,
				menuParams = 
				{ 
					--parentID = 1,	
					--position = 0,
					menuName ="XML Test"
				}
			})
			:Do(function(_,data)
			self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)
			
			--/* VR */
			EXPECT_HMICALL("VR.AddCommand", 
			{ 
				cmdID = 12,
				vrCommands = 
				{
					"XML Test",
					"XML"
				}
			})
			:Do(function(_,data)
			self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)			
			
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS" })
			EXPECT_NOTIFICATION("OnHashChange")
		end 

		function Test:Step_Verify_TTS_SetGlobalProperties_after_activation_in_Full()
			local TimeOfPropRequest

			EXPECT_HMICALL("TTS.SetGlobalProperties", 
				{
					helpPrompt = 
					{
						{
							text = "Policies Test",
							type = "TEXT"
						},
						{
							text = "XML Test",
							type = "TEXT"
						}
					}
				})
			:Timeout(25000)
			:Do(function(_,data)
			  	self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)
			:ValidIf(function(_,data)

				local TimeOfPropRequest = timestamp()
				local TimeToSetPropReqAfterActivation = TimeOfPropRequest - TimeOfActivation

				if
					TimeToSetPropReqAfterActivation > 20500 and
					TimeToSetPropReqAfterActivation < 19500 then
						print( "\27[31m TTS.SetGlobalProperties came after activation in " .. tostring(TimeToSetPropReqAfterActivation) .. " ms, expected time 20 sec \27[0m " )
						return false
				else
					print( "\27[32m TTS.SetGlobalProperties came after activation in " .. tostring(TimeToSetPropReqAfterActivation) .. " ms, expected time 20 sec \27[0m " )
						return true
				end
			end)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")			
			:Timeout(27000)		
			:Times(0)

			DelayedExp(2000)		
		end 

		function Test:End_TC_SetGlobalProperties_03()
			print("--------------------------------------------------------")
		end		
	--End test case SequenceCheck.3
	-----------------------------------------------------------------------------------------


	--Begin test case SequenceCheck.4
	--Description: Check for manual test case TC_SetGlobalProperties_03: SDL does not send TTS.SetGlobalProperties request in 20 seconds from activation if mobile sends SetGlobalProperties request to SDL

		function Test:Begin_TC_SetGlobalProperties_04()
			print("--------------------------------------------------------")
		end
		
		commonSteps:UnregisterApplication()	
		commonSteps:StartSession()
		
		function Test:Step_RegisterAppAndVerifyTTSGetProperties()
			--RegisterAppAndVerifyTTSGetProperties()	
			
			self.mobileSession:StartService(7)
			:Do(function()	
					local CorIdRegister = self.mobileSession:SendRPC("RegisterAppInterface", config.application1.registerAppInterfaceParams)
					EXPECT_HMINOTIFICATION("BasicCommunication.OnAppRegistered", 
					{
					  application = 
					  {
						appName = config.application1.registerAppInterfaceParams.appName				
					  }
					})
					:Do(function(_,data)
					  self.applications[data.params.application.appName] = data.params.application.appID
						end)

					self.mobileSession:ExpectResponse(CorIdRegister, { success = true, resultCode = "SUCCESS" })
					:Timeout(2000)

					self.mobileSession:ExpectNotification("OnHMIStatus", {hmiLevel = "NONE", audioStreamingState = "NOT_AUDIBLE", systemContext = "MAIN"})
				end)
				
				
					
				--Verify_ helpPrompt _isEmpty()	
				--hmi side: expect TTS.SetGlobalProperties request
				EXPECT_HMICALL("TTS.SetGlobalProperties")
				:Timeout(iTimeout)
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)
				:ValidIf(function(_,data)
					if 
						data.params.timeoutPrompt then
						print( "\27[31m TTS.SetGlobalProperties request came with unexpected timeoutPrompt parameter. \27[0m " )
							return false
					elseif
						data.params.helpPrompt and
						#data.params.helpPrompt == 0 then
							return true
					elseif
						data.params.helpPrompt == nil then
							print( "\27[31m UI.SetGlobalProperties request came without helpPrompt  \27[0m " )
							return false
					else 
						print( "\27[31m UI.SetGlobalProperties request came with some unexpected values of helpPrompt, array length is " .. tostring(#data.params.helpPrompt) .. " \27[0m " )
							return false
					end

				end)
		end

		commonSteps:ActivationApp()
		
		function Test:Step_PutFile()
			
			local cid = self.mobileSession:SendRPC(
				"PutFile",
				{
					syncFileName = "action.png",
					fileType = "GRAPHIC_PNG"
				}, 
				"files/action.png"
			) 
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS" })
			
		end

		function Test:Step_SendSetGlobalPropertiesRequest()

			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})


			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)



			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)



			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
			
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")
		end

		function Test:Step_Verify_TTS_SetGlobalProperties_IsNotSend()
			EXPECT_HMICALL("TTS.SetGlobalProperties")
			:Times(0)

			DelayedExp(22000)

		end 

		function Test:End_TC_SetGlobalProperties_04()
			print("--------------------------------------------------------")
		end		

	--End test case SequenceCheck.4
	-----------------------------------------------------------------------------------------




	--Begin test case SequenceCheck.5
	--Description: Check for manual test case TC_SetGlobalProperties_04: SDL does not send TTS.SetGlobalProperties request in 20 seconds from activation if mobile sends ResetGlobalProperties request to SDL


		function Test:Begin_TC_SetGlobalProperties_05()
			print("--------------------------------------------------------")
		end
		
		commonSteps:UnregisterApplication()	
		commonSteps:StartSession()

		function Test:Step_RegisterAppAndVerifyTTSGetProperties()
			--RegisterAppAndVerifyTTSGetProperties()	
			
			self.mobileSession:StartService(7)
			:Do(function()	
					local CorIdRegister = self.mobileSession:SendRPC("RegisterAppInterface", config.application1.registerAppInterfaceParams)
					EXPECT_HMINOTIFICATION("BasicCommunication.OnAppRegistered", 
					{
					  application = 
					  {
						appName = config.application1.registerAppInterfaceParams.appName				
					  }
					})
					:Do(function(_,data)
					  self.applications[data.params.application.appName] = data.params.application.appID
						end)

					self.mobileSession:ExpectResponse(CorIdRegister, { success = true, resultCode = "SUCCESS" })
					:Timeout(2000)

					self.mobileSession:ExpectNotification("OnHMIStatus", {hmiLevel = "NONE", audioStreamingState = "NOT_AUDIBLE", systemContext = "MAIN"})
				end)
				
				
					
				--Verify_ helpPrompt _isEmpty()	
				--hmi side: expect TTS.SetGlobalProperties request
				EXPECT_HMICALL("TTS.SetGlobalProperties")
				-- {
				-- 	helpPrompt =  {}
				-- })
				:Timeout(iTimeout)
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)
				:ValidIf(function(_,data)
					if 
						data.params.helpPrompt and
						#data.params.helpPrompt == 0 then
							return true
					elseif
						data.params.helpPrompt == nil then
							print( "\27[31m UI.SetGlobalProperties request came without helpPrompt  \27[0m " )
							return false
					else 
						print( "\27[31m UI.SetGlobalProperties request came with some unexpected values of helpPrompt, array length is " .. tostring(#data.params.helpPrompt) .. " \27[0m " )
							return false
					end

				end)

			
			
		end

		commonSteps:ActivationApp()
		
		function Test:Step_SendResetGlobalProperties()
			local cid = self.mobileSession:SendRPC("ResetGlobalProperties",
				{
					properties = 	
					{ 
						"HELPPROMPT",
						"TIMEOUTPROMPT",
						"VRHELPTITLE",
						"VRHELPITEMS",
						"MENUICON",
						"MENUNAME",
						"KEYBOARDPROPERTIES"
					}
				})
		  
				--/* UI */
				EXPECT_HMICALL("UI.SetGlobalProperties", 
				{ 
					keyboardProperties = 
					{
						autoCompleteText = "",
						keyboardLayout = "QWERTY",
						language = "EN-US"
					},
					menuTitle = "",
					vrHelpTitle	= config.application1.registerAppInterfaceParams.appName
				})
				:Do(function(_,data)
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)	

				--/* TTS */
				EXPECT_HMICALL("TTS.SetGlobalProperties", 
				{ 
					-- helpPrompt = {},
					timeoutPrompt = 
					{
						{
							text = "Please speak one of the following commands,", 
							type = "TEXT"
						},
						{
							text = "Please say a command,",
							type = "TEXT"
						}			
					}
				})
				:Do(function(_,data)
					self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)
				:ValidIf(function(_,data)
					if 
						data.params.helpPrompt and
						#data.params.helpPrompt == 0 then
							return true
					elseif
						data.params.helpPrompt == nil then
							print( "\27[31m UI.SetGlobalProperties request came without helpPrompt  \27[0m " )
							return false
					else 
						print( "\27[31m UI.SetGlobalProperties request came with some unexpected values of helpPrompt, array length is " .. tostring(#data.params.helpPrompt) .. " \27[0m " )
							return false
					end

				end)


				EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS" })
				EXPECT_NOTIFICATION("OnHashChange")	
			
		end

		function Test:Step_Verify_TTS_SetGlobalProperties_IsNotSend()
			EXPECT_HMICALL("TTS.SetGlobalProperties")
				:Times(0)

			DelayedExp(22000)
		end 
		
		function Test:End_TC_SetGlobalProperties_05()
			print("--------------------------------------------------------")
		end
	--End test case SequenceCheck.5
	-----------------------------------------------------------------------------------------

	--Begin test case SequenceCheck.6
	--Description:Check for manual test case TC_SetGlobalProperties_02: SDL sends TTS.SetGlobalProperties request in 20 seconds from activation to LIMITED with the default list of HelpPrompts is a list of TTSChunks ( UI commands) defined as �TEXT� type, which are the list of the commands.


		function Test:Begin_TC_SetGlobalProperties_06()
			print("--------------------------------------------------------")
		end
		
		commonSteps:UnregisterApplication()	
		commonSteps:StartSession()

		local RegisterParams
		function Test:Step_RegisterAppAndVerifyTTSGetProperties_limited()
			RegisterParams = copy_table(config.application1.registerAppInterfaceParams)
			RegisterParams.isMediaApplication = true
			
			self.mobileSession:StartService(7)
			:Do(function()	
					local CorIdRegister = self.mobileSession:SendRPC("RegisterAppInterface", RegisterParams)
					EXPECT_HMINOTIFICATION("BasicCommunication.OnAppRegistered", 
					{
					  application = 
					  {
						appName = config.application1.registerAppInterfaceParams.appName				
					  }
					})
					:Do(function(_,data)
					  self.applications[data.params.application.appName] = data.params.application.appID
					end)

					self.mobileSession:ExpectResponse(CorIdRegister, { success = true, resultCode = "SUCCESS" })
					:Timeout(2000)

					self.mobileSession:ExpectNotification("OnHMIStatus", {hmiLevel = "NONE", audioStreamingState = "NOT_AUDIBLE", systemContext = "MAIN"})
			end)
			
		end

		commonSteps:ActivationApp()

		function Test:Step_AddCommand_Policies_Test_limited()
			local cid = self.mobileSession:SendRPC("AddCommand",
			{
				cmdID = 11,
				menuParams = 	
				{ 
					--parentID = 1,
					--position = 0,
					menuName ="Policies Test"
				}, 
				vrCommands = 
				{ 
					"Policies Test",
					"Policies"
				}
			})
			
			--/* UI */
			EXPECT_HMICALL("UI.AddCommand", 
			{ 
				cmdID = 11,
				menuParams = 
				{ 
					--parentID = 1,	
					--position = 0,
					menuName ="Policies Test"
				}
			})
			:Do(function(_,data)
			self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)
			
			--/* VR */
			EXPECT_HMICALL("VR.AddCommand", 
			{ 
				cmdID = 11,
				vrCommands = 
				{
					"Policies Test",
					"Policies"
				}
			})
			:Do(function(_,data)
			self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)			
			
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS" })
			EXPECT_NOTIFICATION("OnHashChange")
				:Do(function(_,data)
					self.hashId = data.payload.hashID
				end)
		end 

		function Test:Step_AddCommand_XML_Test_limited()
			local cid = self.mobileSession:SendRPC("AddCommand",
			{
				cmdID = 12,
				menuParams = 	
				{ 
					--parentID = 1,
					--position = 0,
					menuName ="XML Test"
				}, 
				vrCommands = 
				{ 
					"XML Test",
					"XML"
				}
			})
			
			--/* UI */
			EXPECT_HMICALL("UI.AddCommand", 
			{ 
				cmdID = 12,
				menuParams = 
				{ 
					--parentID = 1,	
					--position = 0,
					menuName ="XML Test"
				}
			})
			:Do(function(_,data)
			self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)
			
			--/* VR */
			EXPECT_HMICALL("VR.AddCommand", 
			{ 
				cmdID = 12,
				vrCommands = 
				{
					"XML Test",
					"XML"
				}
			})
			:Do(function(_,data)
			self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)			
			
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS" })
			EXPECT_NOTIFICATION("OnHashChange")
				:Do(function(_,data)
					self.hashId = data.payload.hashID
				end)
		end 

		function Test:SetAppToLimitedCloseSession()

			self.hmiConnection:SendNotification("BasicCommunication.OnAppDeactivated", {appID = self.applications[RegisterParams.appName]})


            EXPECT_NOTIFICATION("OnHMIStatus",
            {hmiLevel = "LIMITED", audioStreamingState = "AUDIBLE", systemContext = "MAIN"})
            	:Do(function()
            		self.mobileSession:Stop()
            	end)

            EXPECT_HMINOTIFICATION("BasicCommunication.OnAppUnregistered", {unexpectedDisconnect = true})

		end

		commonSteps:StartSession()

		local TimeActivationToLimited
		function Test:Step_RegisterAppAndVerifyTTSGetProperties_Resumption_to_limited()
			
			RegisterParams.hashID = self.hashId

			self.mobileSession:StartService(7)
			:Do(function()	
				local CorIdRegister = self.mobileSession:SendRPC("RegisterAppInterface", RegisterParams)
				EXPECT_HMINOTIFICATION("BasicCommunication.OnAppRegistered", 
				{
				  application = 
				  {
					appName = config.application1.registerAppInterfaceParams.appName				
				  }
				})
				:Do(function(_,data)
				  self.applications[data.params.application.appName] = data.params.application.appID
				end)

				self.mobileSession:ExpectResponse(CorIdRegister, { success = true, resultCode = "SUCCESS" })
				:Timeout(2000)

				self.mobileSession:ExpectNotification("OnHMIStatus", 
					{hmiLevel = "NONE", audioStreamingState = "NOT_AUDIBLE", systemContext = "MAIN"},
					{hmiLevel = "LIMITED", audioStreamingState = "AUDIBLE", systemContext = "MAIN"})
					:Times(2)
					:Do(function(_,data)
						if data.payload.hmiLevel == "LIMITED" then
							TimeActivationToLimited = timestamp()
						end
					end)

				EXPECT_HMICALL("UI.AddCommand")
					:Do(function(_,data)
						self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
					end)
					:Times(2)


				EXPECT_HMICALL("VR.AddCommand")
					:Do(function(_,data)
						self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
					end)
					:Times(2)

				--Verify_ helpPrompt _isEmpty()	
				--hmi side: expect TTS.SetGlobalProperties request
				EXPECT_HMICALL("TTS.SetGlobalProperties")
				:Timeout(iTimeout)
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)
				:ValidIf(function(_,data)
					if 
						data.params.helpPrompt and
						#data.params.helpPrompt == 0 then
							return true
					elseif
						data.params.helpPrompt == nil then
							print( "\27[31m UI.SetGlobalProperties request came without helpPrompt  \27[0m " )
							return false
					else 
						print( "\27[31m UI.SetGlobalProperties request came with some unexpected values of helpPrompt, array length is " .. tostring(#data.params.helpPrompt) .. " \27[0m " )
							return false
					end
				end)
			end)
			
		end


		function Test:Step_Verify_TTS_SetGlobalProperties_after_activation_in_Limited()
			local TimeOfPropRequest

			EXPECT_HMICALL("TTS.SetGlobalProperties", 
				{
					helpPrompt = 
					{
						{
							text = "Policies Test",
							type = "TEXT"
						},
						{
							text = "XML Test",
							type = "TEXT"
						}
					}
				})
			:Timeout(25000)
			:Do(function(_,data)
			  	self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)
			:ValidIf(function(_,data)

				local TimeOfPropRequest = timestamp()
				local TimeToSetPropReqAfterActivation = TimeOfPropRequest - TimeActivationToLimited

				if
					TimeToSetPropReqAfterActivation > 20500 and
					TimeToSetPropReqAfterActivation < 19500 then
						print( "\27[31m TTS.SetGlobalProperties came after activation in " .. tostring(TimeToSetPropReqAfterActivation) .. " ms, expected time 20 sec \27[0m " )
						return false
				else
					print( "\27[32m TTS.SetGlobalProperties came after activation in " .. tostring(TimeToSetPropReqAfterActivation) .. " ms, expected time 20 sec \27[0m " )
						return true
				end
			end)
						
			--mobile side: expect OnHashChange notification
			EXPECT_NOTIFICATION("OnHashChange")			
			:Timeout(27000)		
			:Times(0)

			DelayedExp(2000)		
		end 
		
		
		function Test:End_TC_SetGlobalProperties_06()
			print("--------------------------------------------------------")
		end
	--End test case SequenceCheck.5
	-----------------------------------------------------------------------------------------

	
--End test suit SequenceCheck


----------------------------------------------------------------------------------------------
-----------------------------------------VII TEST BLOCK----------------------------------------
--------------------------------------Different HMIStatus-------------------------------------
----------------------------------------------------------------------------------------------
--Description: processing of request/response in different HMIlevels, SystemContext, AudioStreamingState

--Begin test suit DifferentHMIlevel
--Description: processing API in different HMILevel

	--Requirement id in JAMA: SDLAQ-CRS-764

	--Verification criteria: SDL allows request in FULL, LIMITED, BACKGROUND HMI levels


	--Begin test case DifferentHMIlevel.1
	--Description: Check SetGlobalProperties request when application is in NONE HMI level

		commonSteps:UnregisterApplication()	

		commonSteps:StartSession()

		function Test:RegisterApp_forTestingDiffHMIlevels()
			--RegisterAppAndVerifyTTSGetProperties()	
			
			self.mobileSession:StartService(7)
			:Do(function()	
					local CorIdRegister = self.mobileSession:SendRPC("RegisterAppInterface", config.application1.registerAppInterfaceParams)
					EXPECT_HMINOTIFICATION("BasicCommunication.OnAppRegistered", 
					{
					  application = 
					  {
						appName = config.application1.registerAppInterfaceParams.appName				
					  }
					})
					:Do(function(_,data)
					  self.applications[data.params.application.appName] = data.params.application.appID
						end)

					self.mobileSession:ExpectResponse(CorIdRegister, { success = true, resultCode = "SUCCESS" })
					:Timeout(2000)

					self.mobileSession:ExpectNotification("OnHMIStatus", {hmiLevel = "NONE", audioStreamingState = "NOT_AUDIBLE", systemContext = "MAIN"})
				end)
			
		end

		commonSteps:ActivationApp()
	
		-- Precondition: Change app to NONE HMI level
		commonSteps:DeactivateAppToNoneHmiLevel()
			
		--Precondition: PutFile "action.png"
		function Test:Step_PutFile()
			
			local cid = self.mobileSession:SendRPC(
				"PutFile",
				{
					syncFileName = "action.png",
					fileType = "GRAPHIC_PNG"
				}, 
				"files/action.png"
			) 
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS" })
			
		end

		function Test:SetGlobalProperties_HMILevelNONE_DISALLOWED()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		
			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = false, resultCode = "DISALLOWED"})
			:Timeout(12000)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end

		--Postcondition: Activate app
		commonSteps:ActivationApp()
			
	--End test case DifferentHMIlevel.1
	-----------------------------------------------------------------------------------------


	--Begin test case DifferentHMIlevel.2
	--Description: Check SetGlobalProperties request when application is in LIMITTED HMI level

		if commonFunctions:isMediaApp() then
				
			-- Precondition: Change app to LIMITED
			commonSteps:ChangeHMIToLimited()	
				
			function Test:SetGlobalProperties_HMILevelLimitted_SUCCESS()
			
				--mobile side: sending SetGlobalProperties request
				local cid = self.mobileSession:SendRPC("SetGlobalProperties",
				{
					menuTitle = "Menu Title",
					timeoutPrompt = 
					{
						{
							text = "Timeout prompt",
							type = "TEXT"
						}
					},
					vrHelp = 
					{
						{
							position = 1,
							image = 
							{
								value = "action.png",
								imageType = "DYNAMIC"
							},
							text = "VR help item"
						}
					},
					menuIcon = 
					{
						value = "action.png",
						imageType = "DYNAMIC"
					},
					helpPrompt = 
					{
						{
							text = "Help prompt",
							type = "TEXT"
						}
					},
					vrHelpTitle = "VR help title",
					keyboardProperties = 
					{
						keyboardLayout = "QWERTY",
						keypressMode = "SINGLE_KEYPRESS",
						limitedCharacterList = 
						{
							"a"
						},
						language = "EN-US",
						autoCompleteText = "Daemon, Freedom"
					}
				})
			

				--hmi side: expect TTS.SetGlobalProperties request
				EXPECT_HMICALL("TTS.SetGlobalProperties",
				{
					timeoutPrompt = 
					{
						{
							text = "Timeout prompt",
							type = "TEXT"
						}
					},
					helpPrompt = 
					{
						{
							text = "Help prompt",
							type = "TEXT"
						}
					}
				})
				:Timeout(iTimeout)
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)

			

				--hmi side: expect UI.SetGlobalProperties request
				EXPECT_HMICALL("UI.SetGlobalProperties",
				{
					menuTitle = "Menu Title",
					vrHelp = 
					{
						{
							position = 1,
							--[=[ TODO: update after resolving APPLINK-16052

							image = 
							{
								imageType = "DYNAMIC",
								value = strAppFolder .. "action.png"
							},]=]
							text = "VR help item"
						}
					},
					menuIcon = 
					{
						imageType = "DYNAMIC",
						value = strAppFolder .. "action.png"
					},
					vrHelpTitle = "VR help title",
					keyboardProperties = 
					{
						keyboardLayout = "QWERTY",
						keypressMode = "SINGLE_KEYPRESS",
						--[=[ TODO: update after resolving APPLINK-16047

						limitedCharacterList = 
						{
							"a"
						},]=]
						language = "EN-US",
						autoCompleteText = "Daemon, Freedom"
					}
				})
				:Timeout(iTimeout)
				:Do(function(_,data)
					--hmi side: sending UI.SetGlobalProperties response
					self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
				end)

			

				--mobile side: expect SetGlobalProperties response
				EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
				:Timeout(iTimeout)
						
				--mobile side: expect OnHashChange notification is not send to mobile
				EXPECT_NOTIFICATION("OnHashChange")
				:Times(0)
			end
		
		end
	--End test case DifferentHMIlevel.2
	-----------------------------------------------------------------------------------------

	--Begin test case DifferentHMIlevel.3
	--Description: Check SetGlobalProperties request when application is in BACKGOUND HMI level


		-- Precondition 1: Change app to BACKGOUND HMI level
		commonTestCases:ChangeAppToBackgroundHmiLevel()
			
		function Test:SetGlobalProperties_HMILevelBACKGOUND_SUCCESS()
		
			--mobile side: sending SetGlobalProperties request
			local cid = self.mobileSession:SendRPC("SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				vrHelp = 
				{
					{
						position = 1,
						image = 
						{
							value = "action.png",
							imageType = "DYNAMIC"
						},
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					value = "action.png",
					imageType = "DYNAMIC"
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					limitedCharacterList = 
					{
						"a"
					},
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
		

			--hmi side: expect TTS.SetGlobalProperties request
			EXPECT_HMICALL("TTS.SetGlobalProperties",
			{
				timeoutPrompt = 
				{
					{
						text = "Timeout prompt",
						type = "TEXT"
					}
				},
				helpPrompt = 
				{
					{
						text = "Help prompt",
						type = "TEXT"
					}
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--hmi side: expect UI.SetGlobalProperties request
			EXPECT_HMICALL("UI.SetGlobalProperties",
			{
				menuTitle = "Menu Title",
				vrHelp = 
				{
					{
						position = 1,
						--[=[ TODO: update after resolving APPLINK-16052

						image = 
						{
							imageType = "DYNAMIC",
							value = strAppFolder .. "action.png"
						},]=]
						text = "VR help item"
					}
				},
				menuIcon = 
				{
					imageType = "DYNAMIC",
					value = strAppFolder .. "action.png"
				},
				vrHelpTitle = "VR help title",
				keyboardProperties = 
				{
					keyboardLayout = "QWERTY",
					keypressMode = "SINGLE_KEYPRESS",
					--[=[ TODO: update after resolving APPLINK-16047

					limitedCharacterList = 
					{
						"a"
					},]=]
					language = "EN-US",
					autoCompleteText = "Daemon, Freedom"
				}
			})
			:Timeout(iTimeout)
			:Do(function(_,data)
				--hmi side: sending UI.SetGlobalProperties response
				self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
			end)

		

			--mobile side: expect SetGlobalProperties response
			EXPECT_RESPONSE(cid, { success = true, resultCode = "SUCCESS"})
			:Timeout(iTimeout)
						
			--mobile side: expect OnHashChange notification is not send to mobile
			EXPECT_NOTIFICATION("OnHashChange")
			:Times(0)
		end
		
	--End test case DifferentHMIlevel.3
	-----------------------------------------------------------------------------------------

--End test suit DifferentHMIlevel

return Test