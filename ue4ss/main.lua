local json = require("dkjson")
local KismetText = nil
local UEHelpers = require("UEHelpers")

local flyerRecipients = {}
local hookRegistered = false
local pendingEmployeeNames = {}
local pipeWarned = false
local updatingEmployeeSticker = false

local PIPE_PATH = "\\\\.\\pipe\\RetroRewindCompanion"

local function Log(message)
    print(string.format("[TwitchIntegration] %s\n", message))
end

local function PopQueue()
    local osPipe = io.open(PIPE_PATH, "r+")

    if not osPipe then
        return nil, "PipeUnavailable"
    end

    osPipe:write("POP\n")
    osPipe:flush()

    local rawResponse = osPipe:read("*l")
    osPipe:close()

    if not rawResponse or rawResponse == "" then
        return nil, "QueueEmpty"
    end

    local queueEntry, _, err = json.decode(rawResponse)

    if err then
        Log(string.format("Failed to parse queue response: %s", err))
        return nil, "ParseError"
    end

    return queueEntry
end

NotifyOnNewObject(
    "/Game/VideoStore/core/ai/pawn/AI_Base_Character.AI_Base_Character_C",
    function()
        if not hookRegistered then
            hookRegistered = true
            KismetText = UEHelpers.GetKismetTextLibrary()

            RegisterHook(
                "/Game/VideoStore/core/ai/pawn/AI_Base_Character.AI_Base_Character_C:Return Random Name based on Genre",
                function(context, Genre, Client_Name, Client_Membership_Number)
                    local ai = context:get()

                    if ai['Type of AI'] == 1 then
                        local queueEntry, errorReason = PopQueue()

                        if queueEntry then
                            local chatterName = queueEntry.displayName
                            local membershipNumber = Client_Membership_Number:get()
                            local showNameAboveHead = queueEntry.showNameAboveHead

                            Client_Membership_Number:set(membershipNumber)
                            Client_Name:set(KismetText:Conv_StringToText(chatterName))

                            if showNameAboveHead then
                                local titleComponent = ai['Title_Name']
                                titleComponent.bHiddenInGame = false
                                titleComponent:SetText(KismetText:Conv_StringToText(chatterName))
                            end

                            Log(string.format("Customer named: %s (membership: %s)", chatterName,
                                tostring(membershipNumber)))
                            pipeWarned = false
                        elseif errorReason == "PipeUnavailable" and not pipeWarned then
                            Log("Companion app is not running, customers will use default names.")
                            pipeWarned = true
                        end
                    end
                end
            )

            RegisterHook(
                "/Game/VideoStore/core/ai/pawn/AI_Employee_Character.AI_Employee_Character_C:Return Random Name based on Genre",
                function(context, Genre, Client_Name, Client_Membership_Number)
                    local ai = context:get()
                    local aiAddress = tostring(ai:GetAddress())
                    local queueEntry, errorReason = PopQueue()

                    if queueEntry then
                        local chatterName = queueEntry.displayName
                        local membershipNumber = Client_Membership_Number:get()
                        local showNameAboveHead = queueEntry.showNameAboveHead

                        Client_Membership_Number:set(membershipNumber)
                        Client_Name:set(KismetText:Conv_StringToText(chatterName))

                        if showNameAboveHead then
                            local titleComponent = ai['Title_Name']
                            titleComponent.bHiddenInGame = false
                            titleComponent:SetText(KismetText:Conv_StringToText(chatterName))
                        end

                        pendingEmployeeNames[aiAddress] = chatterName
                        Log(string.format("Employee named: %s. Waiting for name badge to update...", chatterName))
                        pipeWarned = false
                    elseif errorReason == "PipeUnavailable" and not pipeWarned then
                        Log("Companion app is not running, employees will use default names.")
                        pipeWarned = true
                    end
                end
            )

            RegisterHook("/Game/VideoStore/core/ai/pawn/staff/Staff_NameSticker.Staff_NameSticker_C:Update Staff Name",
                function(context, Staff_Name)
                    if updatingEmployeeSticker then
                        return
                    end

                    local stickerComponent = context:get()
                    local ownerComponent = stickerComponent:GetAttachParentActor()

                    if not ownerComponent or not ownerComponent:IsValid() then
                        return
                    end

                    local ownerAddress = tostring(ownerComponent:GetAddress())
                    local chatterName = pendingEmployeeNames[ownerAddress]

                    if chatterName then
                        updatingEmployeeSticker = true
                        stickerComponent['Update Staff Name'](stickerComponent, FName(chatterName))
                        Log(string.format("Name badge updated for: %s", chatterName))
                        pendingEmployeeNames[ownerAddress] = nil
                        updatingEmployeeSticker = false
                    end
                end
            )

            RegisterHook(
                "/Game/VideoStore/asset/prop/Flyers/Flyer.Flyer_C:Give the Object",
                function(context, Object_to_store, ref_to_Player, AI)
                    local flyerAddress = tostring(context:get():GetAddress())
                    local aiRef = AI:get()
                    flyerRecipients[flyerAddress] = aiRef
                    Log("Flyer handed to a passerby, waiting for their decision...")
                end
            )

            RegisterHook(
                "/Game/VideoStore/asset/prop/Flyers/Flyer.Flyer_C:Walkby - Flyers End_Event",
                function(context, Convert_into_client)
                    local converted = Convert_into_client:get()
                    local flyerAddress = tostring(context:get():GetAddress())
                    local ai = flyerRecipients[flyerAddress]

                    flyerRecipients[flyerAddress] = nil

                    if not converted then
                        Log("Passerby declined the flyer.")
                        return
                    end

                    if not ai then
                        Log("Passerby accepted but reference was lost, skipping.")
                        return
                    end

                    local queueEntry, errorReason = PopQueue()

                    if queueEntry then
                        local chatterName = queueEntry.displayName
                        local showNameAboveHead = queueEntry.showNameAboveHead

                        ai['Client Name'] = KismetText:Conv_StringToText(chatterName)

                        if showNameAboveHead then
                            local titleComp = ai['Title_Name']
                            titleComp.bHiddenInGame = false
                            titleComp:SetText(KismetText:Conv_StringToText(chatterName))
                        end

                        Log(string.format("Flyer convert named: %s", chatterName))
                    elseif errorReason == "PipeUnavailable" and not pipeWarned then
                        Log("Companion app is not running, customers will use default names.")
                        pipeWarned = true
                    else
                        Log("Passerby accepted but the queue is empty, using default name.")
                    end
                end
            )

            Log("Hooks registered, ready for customers!")
        end
    end
)

Log("Waiting for game to load...")
