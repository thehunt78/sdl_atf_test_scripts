Test = require('connecttest')
require('cardinalities')
local events = require('events')
local mobile_session = require('mobile_session')

require('user_modules/AppTypes')


local successRequests = 0

local function DelayedExp(time)
  local event = events.Event()
  event.matches = function(self, e) return self == e end
  EXPECT_EVENT(event, "Delayed event")
    :Timeout(time + 1000)
  RUN_AFTER(function()
              RAISE_EVENT(event, event)
            end, time)
end

local function AddCommand(self)

	local CorIdAddCommand = self.mobileSession:SendRPC("AddCommand",
							{
								cmdID = 1,
								vrCommands = {"vrCommand"},
								menuParams = 	
								{
									position = 1,
									menuName ="Command"
								}
							})
							
	--hmi side: expect UI.AddCommand request 
	EXPECT_HMICALL("UI.AddCommand", 
					{ 
						cmdID = 1,		
						menuParams = 
						{
							position = 1,
							menuName ="Command"
						}
					})
		:Do(function(_,data)
			--hmi side: sending UI.AddCommand response 
			self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
		end)

	--hmi side: expect VR.AddCommand request 
	EXPECT_HMICALL("VR.AddCommand", 
					{ 
						cmdID = 1,		
						vrCommands = {"vrCommand"},
						type = "Command"
					})
		:Do(function(_,data)
			--hmi side: sending VR.AddCommand response 
			self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
		end)
	
	--mobile side: expect AddCommand response 
	EXPECT_RESPONSE(CorIdAddCommand, {  success = true, resultCode = "SUCCESS"  })

end

local function AddSubMenu(self)

	--mobile side: sending AddSubMenu request
	local CorIdAddSubMenu = self.mobileSession:SendRPC("AddSubMenu",
											{
												menuID = 1000,
												position = 500,
												menuName ="SubMenupositive"
											})
	--hmi side: expect UI.AddSubMenu request
	EXPECT_HMICALL("UI.AddSubMenu", 
					{ 
						menuID = 1000,
						menuParams = {
							position = 500,
							menuName ="SubMenupositive"
						}
					})
		:Do(function(_,data)
			--hmi side: sending UI.AddSubMenu response
			self.hmiConnection:SendResponse(data.id, data.method, "SUCCESS", {})
		end)
		
	--mobile side: expect AddSubMenu response
	EXPECT_RESPONSE(CorIdAddSubMenu, { success = true, resultCode = "SUCCESS" })

end

local function SubscribeButton(self)

	--mobile side: sending SubscribeButton request
	local corIDSubBut = self.mobileSession:SendRPC("SubscribeButton",
										{
											buttonName = "PRESET_0"
										})

	--mobile side: expect SubscribeButton response
	EXPECT_RESPONSE(corIDSubBut, { success = true, resultCode = "SUCCESS" })

end

local function RegisterApplication(self) 

	--mobile side: RegisterAppInterface request 
	local CorIdRAI = self.mobileSession:SendRPC("RegisterAppInterface",
												config.application1.registerAppInterfaceParams)
	

 		--hmi side: expected  BasicCommunication.OnAppRegistered
		EXPECT_HMINOTIFICATION("BasicCommunication.OnAppRegistered")
			:Do(function(_,data)
				self.appID = data.params.application.appID
			end)

	--mobile side: RegisterAppInterface response 
	EXPECT_RESPONSE(CorIdRAI, { success = true, resultCode = "SUCCESS"})
		:Timeout(2000)
		:Do(function(_,data)
			
			EXPECT_NOTIFICATION("OnHMIStatus", {hmiLevel = "NONE", systemContext = "MAIN"})

		end)

	EXPECT_NOTIFICATION("OnPermissionsChange")
end

---------------------------------------------------------------------------------------------
-----------------------------------------I TEST BLOCK----------------------------------------
--------------------------------------CommonRequestCheck: Check of mandatory/conditional request's parameters (mobile protocol)-----------------------------------
---------------------------------------------------------------------------------------------

	--Begin Test suit CommonRequestCheck
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

    	--Begin Test case CommonRequestCheck.1
		--Description: Success resultCode

			--Requirement id in JAMA/or Jira ID: 
				-- SDLAQ-CRS-1273,
				-- SDLAQ-CRS-10,
				-- SDLAQ-CRS-370

			--Verification criteria:
				-- UnregisterAppInterface disconnects the application from SDL. Connection is NOT closed.
				-- The request for unregistering is sent and executed successfully. Connection is not closed. The response code SUCCESS is returned. 

			function Test:UnregisterAppInterface_Success() 

				--mobile side: UnregisterAppInterface request 
				local CorIdURAI = self.mobileSession:SendRPC("UnregisterAppInterface", {})

				--hmi side: expected  BasicCommunication.OnAppUnregistered
				EXPECT_HMINOTIFICATION("BasicCommunication.OnAppUnregistered", {appID = self.appID, unexpectedDisconnect = false})

				--mobile side: UnregisterAppInterface response 
				EXPECT_RESPONSE("UnregisterAppInterface", {success = true , resultCode = "SUCCESS"})

			end

		--End Test suit CommonRequestCheck.1

		--Begin Test case CommonRequestCheck.2
		--Description: Check processing UnregisterAppInterface request with fake parameter

			--Requirement id in JAMA/or Jira ID: 
				-- SDLAQ-CRS-1273,
				-- SDLAQ-CRS-10,
				-- SDLAQ-CRS-370,
				-- APPLINK-4518

			--Verification criteria:
				--According to xml tests by Ford team all fake params should be ignored by SDL

			--Precondition: App registration
			function Test:RegisterAppInterface_Success()
				RegisterApplication(self)
			end

			function Test:UnregisterAppInterface_FakeParam() 

				--mobile side: UnregisterAppInterface request 
				local CorIdURAI = self.mobileSession:SendRPC("UnregisterAppInterface", { fakeParam = "fakeParam"})

				--hmi side: expected  BasicCommunication.OnAppUnregistered
				EXPECT_HMINOTIFICATION("BasicCommunication.OnAppUnregistered", {appID = self.appID, unexpectedDisconnect = false})

				--mobile side: UnregisterAppInterface response 
				EXPECT_RESPONSE("UnregisterAppInterface", {success = true , resultCode = "SUCCESS"})
					:Do(function(_,data)
						if data.payload.fakeParam then
							print(" \27[36m UnregisterAppInterface response came with fakeParam parameter \27[0m")
							return false
						else 
							return true
						end

					end)

			end

		--End Test suit CommonRequestCheck.2

		--Begin Test case CommonRequestCheck.3
		--Description: Check processing UnregisterAppInterface request with parameters from another request

			--Requirement id in JAMA/or Jira ID: 
				-- SDLAQ-CRS-1273,
				-- SDLAQ-CRS-10,
				-- SDLAQ-CRS-370,
				-- APPLINK-11906

			--Verification criteria: If SDL gets request which includes parameters from other API (function) then SDL must consider them as fake params (= cut off these parameters) and process only parameters valid for named request

			--Precondition: App registration
			function Test:RegisterAppInterface_Success()
				RegisterApplication(self)
			end

			function Test:UnregisterAppInterface_AnotherRequest() 

				--mobile side: UnregisterAppInterface request 
				local CorIdURAI = self.mobileSession:SendRPC("UnregisterAppInterface", { menuName = " fake parameter" })

				--hmi side: expected  BasicCommunication.OnAppUnregistered
				EXPECT_HMINOTIFICATION("BasicCommunication.OnAppUnregistered", {appID = self.appID, unexpectedDisconnect = false})

				--mobile side: UnregisterAppInterface response 
				EXPECT_RESPONSE("UnregisterAppInterface", {success = true , resultCode = "SUCCESS"})
					:Do(function(_,data)
						if data.payload.menuName then
							print(" \27[36m UnregisterAppInterface response came with menuName parameter \27[0m")
							return false
						else 
							return true
						end
					end)

			end

		--End Test suit CommonRequestCheck.3

		--Begin Test case CommonRequestCheck.4
		--Description: Check processing invalid JSON of UnregisterAppInterface request

			--Requirement id in JAMA/or Jira ID: 
				-- SDLAQ-CRS-1273,
				-- SDLAQ-CRS-10,
				-- SDLAQ-CRS-371

			--Verification criteria: he request is sent with wrong JSON syntax, the response comes with INVALID_DATA result code.

			--Precondition: App registration 
			function Test:RegisterAppInterface_Success()
				RegisterApplication(self)
			end

			function Test:UnregisterAppInterface_InvalidJSON() 

				self.mobileSession.correlationId = self.mobileSession.correlationId + 1

				--mobile side: UnregisterAppInterface request 
				local msg = 
				{
				    serviceType      = 7,
				    frameInfo        = 0,
				    rpcType          = 0,
				    rpcFunctionId    = 2,
				    rpcCorrelationId = self.mobileSession.correlationId,
				--<<!-- extra ','
				    payload          = '{,}'
				  }
				  self.mobileSession:Send(msg)

				  --mobile side: UnregisterAppInterface response 
				  self.mobileSession:ExpectResponse(self.mobileSession.correlationId, { success = false, resultCode = "INVALID_DATA" })


			end

		--End Test suit CommonRequestCheck.4

		--Begin Test case CommonRequestCheck.5
			--Description: Check processing requests with duplicate correlationID
--TODO: fill Requirement, Verification criteria
				--Requirement id in JAMA/or Jira ID: 

				--Verification criteria:

					function Test:UnregisterAppInterface_correlationIdDuplicateValue()

						--mobile side: UnregisterAppInterface request 
						local CorIdURAI = self.mobileSession:SendRPC("UnregisterAppInterface",{})

						self.mobileSession.correlationId = CorIdURAI 

						--mobile side: UnregisterAppInterface response 
						EXPECT_RESPONSE(CorIdURAI, 
							{ success = true, resultCode = "SUCCESS"},
							{ success = false, resultCode = "APPLICATION_NOT_REGISTERED"})
							:Times(2)
							:Do(function(exp,data)

								if exp.occurences == 1 then

									--mobile side: UnregisterAppInterface request 
									  local msg = 
									  {
									    serviceType      = 7,
									    frameInfo        = 0,
									    rpcType          = 0,
									    rpcFunctionId    = 2,
									    rpcCorrelationId = self.mobileSession.correlationId,
									    payload          = '{}'
									  }
									  self.mobileSession:Send(msg)
								end

							end)

					end


		--End Test case CommonRequestCheck.5

		--Begin Test case CommonRequestCheck.6
			--Description: Check absence added data after unregistration
--TODO: fill Requirement, Verification criteria
				--Requirement id in JAMA/or Jira ID: 

				--Verification criteria:

					--Precondition: App registration 
					function Test:RegisterAppInterface_Success()
						RegisterApplication(self)
					end

					--Precondition: Activation of application
					function Test:ActivationApp()

						--hmi side: sending SDL.ActivateApp request
					  	local RequestId = self.hmiConnection:SendRequest("SDL.ActivateApp", { appID = self.appID})

					  	--hmi side: expect SDL.ActivateApp response
						EXPECT_HMIRESPONSE(RequestId)
							:Do(function(_,data)
								--In case when app is not allowed, it is needed to allow app
						    	if
						        	data.result.isSDLAllowed ~= true then

						        		--hmi side: sending SDL.GetUserFriendlyMessage request
						            	local RequestId = self.hmiConnection:SendRequest("SDL.GetUserFriendlyMessage", 
													        {language = "EN-US", messageCodes = {"DataConsent"}})

						            	--hmi side: expect SDL.GetUserFriendlyMessage response
					    			  	--TODO: Update after resolving APPLINK-16094 EXPECT_HMIRESPONSE(RequestId,{result = {code = 0, method = "SDL.GetUserFriendlyMessage"}})
					    			  	EXPECT_HMIRESPONSE(RequestId)
							              	:Do(function(_,data)

							    			    --hmi side: send request SDL.OnAllowSDLFunctionality
							    			    self.hmiConnection:SendNotification("SDL.OnAllowSDLFunctionality", 
							    			    	{allowed = true, source = "GUI", device = {id = config.deviceMAC, name = "127.0.0.1"}})

							    			    --hmi side: expect BasicCommunication.ActivateApp request
									            EXPECT_HMICALL("BasicCommunication.ActivateApp")
									            	:Do(function(_,data)

									            		--hmi side: sending BasicCommunication.ActivateApp response
											          	self.hmiConnection:SendResponse(data.id,"BasicCommunication.ActivateApp", "SUCCESS", {})

											        end)
											        :Times(2)

							              	end)

								end
						      end)

						--mobile side: expect OnHMIStatus notification
					  	EXPECT_NOTIFICATION("OnHMIStatus", {hmiLevel = "FULL", systemContext = "MAIN"})	

					end

					function Test:Precondition_AddCommandSubMenuSubscribeButton()
						AddCommand(self)
						AddSubMenu(self)
						SubscribeButton(self)
					end

					function Test:UnregisterAppInterface_CheckAddingtheSameDataAfterUnregister()

						--mobile side: UnregisterAppInterface request 
						local CorIdURAI = self.mobileSession:SendRPC("UnregisterAppInterface",{})


						--mobile side: UnregisterAppInterface response 
						EXPECT_RESPONSE(CorIdURAI, { success = true, resultCode = "SUCCESS"})
							:Do(function(exp,data)
								--mobile side: RegisterAppInterface request 
								local CorIdRAI = self.mobileSession:SendRPC("RegisterAppInterface",
										config.application1.registerAppInterfaceParams)

						 		--hmi side: expected  BasicCommunication.OnAppRegistered
								EXPECT_HMINOTIFICATION("BasicCommunication.OnAppRegistered")
									:Do(function(_,data)
										self.appID = data.params.application.appID
									end)

								--mobile side: RegisterAppInterface response 
								EXPECT_RESPONSE(CorIdRAI, { success = true, resultCode = "SUCCESS"})
									:Timeout(2000)
										
								EXPECT_NOTIFICATION("OnHMIStatus", 
										{hmiLevel = "NONE", systemContext = "MAIN"},
										{hmiLevel = "FULL", systemContext = "MAIN"})
									:Times(2)
									:Do(function(exp,data)
										if exp.occurences == 1 then 
											--hmi side: sending SDL.ActivateApp request
										  	local RequestId = self.hmiConnection:SendRequest("SDL.ActivateApp", { appID = self.appID})
									  	elseif
									     	exp.occurences == 2 then

									     		AddCommand(self)
												AddSubMenu(self)
												SubscribeButton(self)

												local function UnregisterAppInterface2()
													--mobile side: UnregisterAppInterface request 
													local CorIdURAI2 = self.mobileSession:SendRPC("UnregisterAppInterface",{})

													EXPECT_RESPONSE(CorIdURAI2, { success = true, resultCode = "SUCCESS"})
												end

												RUN_AFTER(UnregisterAppInterface2, 2000)

									  	end

									end)
							end)

						DelayedExp(5000)

					end


		--End Test case CommonRequestCheck.6


	--End Test suit CommonRequestCheck

----------------------------------------------------------------------------------------------
----------------------------------------IV TEST BLOCK-----------------------------------------
---------------------------------------Result codes check--------------------------------------
----------------------------------------------------------------------------------------------
--Begin Test suit ResultCodeCheck
	--Description:TC's check all resultCodes values in pair with success value

		--Begin Test case ResultCodeCheck.1
		--Description:

			--Requirement id in JAMA: SDLAQ-CRS-10
				--SDLAQ-CRS-374

			--Verification criteria:
				-- SDL returns the APPLICATION_NOT_REGISTERED code when the app sends UnregisteredAppInterface within the same connection before RegisterAppInterface has been sent yet.

			function Test:UnregisterAppInterface_ApplicationNotRegistered() 

				--mobile side: UnregisterAppInterface request 
				local CorIdURAI = self.mobileSession:SendRPC("UnregisterAppInterface", {})

				--mobile side: UnregisterAppInterface response 
				EXPECT_RESPONSE("UnregisterAppInterface", {success = false , resultCode = "APPLICATION_NOT_REGISTERED"})

			end

		--End Test case ResultCodeCheck.1

--End Test suit ResultCodeCheck

----------------------------------------------------------------------------------------------
-----------------------------------------VII TEST BLOCK----------------------------------------
--------------------------------------Different HMIStatus-------------------------------------
----------------------------------------------------------------------------------------------

	--Begin Test suit DifferentHMIlevel
	--Description: processing API in different HMILevel
	
		--Begin Test case DifferentHMIlevel.1
		--Description: processing API in different HMILevel

			--Requirement id in JAMA: SDLAQ-CRS-763

			--Verification criteria: UnregisterAppInterface request is processed correctly when the app has any of HMI Level value (FULL, LIMITED, BACKGROUND, NONE).

			--Begin Test case DifferentHMIlevel.1.1
			--Description:FULL hmiLevel

				--Precondition: App activation
				function Test:RegisterAppInterface_Success()
					RegisterApplication(self)
				end

				--Precondition: Activation of application
				function Test:ActivationApp()

					--hmi side: sending SDL.ActivateApp request
				  	local RequestId = self.hmiConnection:SendRequest("SDL.ActivateApp", { appID = self.appID})

				  	--hmi side: expect SDL.ActivateApp response
					EXPECT_HMIRESPONSE(RequestId)
						:Do(function(_,data)
							--In case when app is not allowed, it is needed to allow app
					    	if
					        	data.result.isSDLAllowed ~= true then

					        		--hmi side: sending SDL.GetUserFriendlyMessage request
					            	local RequestId = self.hmiConnection:SendRequest("SDL.GetUserFriendlyMessage", 
												        {language = "EN-US", messageCodes = {"DataConsent"}})

					            	--hmi side: expect SDL.GetUserFriendlyMessage response
				    			  	--TODO: Update after resolving APPLINK-16094 EXPECT_HMIRESPONSE(RequestIdEXPECT_HMIRESPONSE(RequestId,{result = {code = 0, method = "SDL.GetUserFriendlyMessage"}})
				    			  	EXPECT_HMIRESPONSE(RequestId)
						              	:Do(function(_,data)

						    			    --hmi side: send request SDL.OnAllowSDLFunctionality
						    			    self.hmiConnection:SendNotification("SDL.OnAllowSDLFunctionality", 
						    			    	{allowed = true, source = "GUI", device = {id = 1, name = "127.0.0.1"}})

						              	end)

						            --hmi side: expect BasicCommunication.ActivateApp request
						            EXPECT_HMICALL("BasicCommunication.ActivateApp")
						            	:Do(function(_,data)

						            		--hmi side: sending BasicCommunication.ActivateApp response
								          	self.hmiConnection:SendResponse(data.id,"BasicCommunication.ActivateApp", "SUCCESS", {})

								        end)
							end
					      end)

					--mobile side: expect OnHMIStatus notification
				  	EXPECT_NOTIFICATION("OnHMIStatus", {hmiLevel = "FULL"})	

				end

				--Precondition: App unregistration
				function Test:UnregisterAppInterface_FullHMILevel() 

					--mobile side: UnregisterAppInterface request 
					local CorIdURAI = self.mobileSession:SendRPC("UnregisterAppInterface", {})

					--hmi side: expected  BasicCommunication.OnAppUnregistered
					EXPECT_HMINOTIFICATION("BasicCommunication.OnAppUnregistered", {appID = self.appID, unexpectedDisconnect = false})

					--mobile side: UnregisterAppInterface response 
					EXPECT_RESPONSE("UnregisterAppInterface", {success = true , resultCode = "SUCCESS"})

				end

			--End Test case DifferentHMIlevel.1.1

			--Begin Test case DifferentHMIlevel.1.2
			--Description: LIMITED hmiLevel

			if 
				Test.isMediaApplication == true or 
				Test.appHMITypes["NAVIGATION"] == true or
				Test.appHMITypes["COMMUNICATION"] == true then
				--Precondition: App activation
				function Test:RegisterAppInterface_Success()
					RegisterApplication(self)
				end

				--Precondition: Activation of application
				function Test:ActivationApp()

					--hmi side: sending SDL.ActivateApp request
				  	local RequestId = self.hmiConnection:SendRequest("SDL.ActivateApp", { appID = self.appID})

				  	--hmi side: expect SDL.ActivateApp response
					EXPECT_HMIRESPONSE(RequestId)
						:Do(function(_,data)
							--In case when app is not allowed, it is needed to allow app
					    	if
					        	data.result.isSDLAllowed ~= true then

					        		--hmi side: sending SDL.GetUserFriendlyMessage request
					            	local RequestId = self.hmiConnection:SendRequest("SDL.GetUserFriendlyMessage", 
												        {language = "EN-US", messageCodes = {"DataConsent"}})

					            	--hmi side: expect SDL.GetUserFriendlyMessage response
				    			  	EXPECT_HMIRESPONSE(RequestId,{result = {code = 0, method = "SDL.GetUserFriendlyMessage"}})
						              	:Do(function(_,data)

						    			    --hmi side: send request SDL.OnAllowSDLFunctionality
						    			    self.hmiConnection:SendNotification("SDL.OnAllowSDLFunctionality", 
						    			    	{allowed = true, source = "GUI", device = {id = 1, name = "127.0.0.1"}})

						              	end)

						            --hmi side: expect BasicCommunication.ActivateApp request
						            EXPECT_HMICALL("BasicCommunication.ActivateApp")
						            	:Do(function(_,data)

						            		--hmi side: sending BasicCommunication.ActivateApp response
								          	self.hmiConnection:SendResponse(data.id,"BasicCommunication.ActivateApp", "SUCCESS", {})

								        end)
							end
					      end)

					--mobile side: expect OnHMIStatus notification
				  	EXPECT_NOTIFICATION("OnHMIStatus", {hmiLevel = "FULL"})	

				end

				--PreconditionL Deactivate app to limited HMI level
				function Test:Presondition_DeactivateToLimited()

					--hmi side: sending BasicCommunication.OnAppDeactivated notification
					self.hmiConnection:SendNotification("BasicCommunication.OnAppDeactivated", {appID = self.appID, reason = "GENERAL"})

					EXPECT_NOTIFICATION("OnHMIStatus",
					    { systemContext = "MAIN", hmiLevel = "LIMITED", audioStreamingState = "AUDIBLE"})

				end

				--Precondition: App unregistration
				function Test:UnregisterAppInterface_LimitedHMILevel() 

					--mobile side: UnregisterAppInterface request 
					local CorIdURAI = self.mobileSession:SendRPC("UnregisterAppInterface", {})

					--hmi side: expected  BasicCommunication.OnAppUnregistered
					EXPECT_HMINOTIFICATION("BasicCommunication.OnAppUnregistered", {appID = self.appID, unexpectedDisconnect = false})

					--mobile side: UnregisterAppInterface response 
					EXPECT_RESPONSE("UnregisterAppInterface", {success = true , resultCode = "SUCCESS"})

				end

			--End Test case DifferentHMIlevel.1.2
			end

			--Begin Test case DifferentHMIlevel.1.3
			--Description: BACKGROUND hmiLevel

				--Precondition: App activation
				function Test:RegisterAppInterface_Success()
					RegisterApplication(self)
				end

				--Precondition: Activation of application
				function Test:ActivationApp()

					--hmi side: sending SDL.ActivateApp request
				  	local RequestId = self.hmiConnection:SendRequest("SDL.ActivateApp", { appID = self.appID})

				  	--hmi side: expect SDL.ActivateApp response
					EXPECT_HMIRESPONSE(RequestId)
						:Do(function(_,data)
							--In case when app is not allowed, it is needed to allow app
					    	if
					        	data.result.isSDLAllowed ~= true then

					        		--hmi side: sending SDL.GetUserFriendlyMessage request
					            	local RequestId = self.hmiConnection:SendRequest("SDL.GetUserFriendlyMessage", 
												        {language = "EN-US", messageCodes = {"DataConsent"}})

					            	--hmi side: expect SDL.GetUserFriendlyMessage response
				    			  	EXPECT_HMIRESPONSE(RequestId,{result = {code = 0, method = "SDL.GetUserFriendlyMessage"}})
						              	:Do(function(_,data)

						    			    --hmi side: send request SDL.OnAllowSDLFunctionality
						    			    self.hmiConnection:SendNotification("SDL.OnAllowSDLFunctionality", 
						    			    	{allowed = true, source = "GUI", device = {id = 1, name = "127.0.0.1"}})

						              	end)

						            --hmi side: expect BasicCommunication.ActivateApp request
						            EXPECT_HMICALL("BasicCommunication.ActivateApp")
						            	:Do(function(_,data)

						            		--hmi side: sending BasicCommunication.ActivateApp response
								          	self.hmiConnection:SendResponse(data.id,"BasicCommunication.ActivateApp", "SUCCESS", {})

								        end)
							end
					      end)

					--mobile side: expect OnHMIStatus notification
				  	EXPECT_NOTIFICATION("OnHMIStatus", {hmiLevel = "FULL"})	

				end

				function Test:Presondition_DeactivateToBackgroung()

					--hmi side: sending BasicCommunication.OnAppDeactivated notification
					self.hmiConnection:SendNotification("BasicCommunication.OnAppDeactivated", {appID = self.appID, reason = "AUDIO"})

					EXPECT_NOTIFICATION("OnHMIStatus",{ systemContext = "MAIN", hmiLevel = "BACKGROUND", audioStreamingState = "NOT_AUDIBLE"})

				end

				--Precondition: App unregistration
				function Test:UnregisterAppInterface_BackgroungHMILevel() 

					--mobile side: UnregisterAppInterface request 
					local CorIdURAI = self.mobileSession:SendRPC("UnregisterAppInterface", {})

					--hmi side: expected  BasicCommunication.OnAppUnregistered
					EXPECT_HMINOTIFICATION("BasicCommunication.OnAppUnregistered", {appID = self.appID, unexpectedDisconnect = false})

					--mobile side: UnregisterAppInterface response 
					EXPECT_RESPONSE("UnregisterAppInterface", {success = true , resultCode = "SUCCESS"})

				end

			--End Test case DifferentHMIlevel.1.3
			
		--End Test case DifferentHMIlevel.1

	--End Test suit DifferentHMIlevel
