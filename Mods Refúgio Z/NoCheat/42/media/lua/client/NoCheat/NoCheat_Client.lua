if not isClient() then
    return
end

require "NoCheat/00_NoCheat_Shared"

if _G.__NoCheatClientLoaded then
    return
end
_G.__NoCheatClientLoaded = true

local NoCheatClient = {}
NoCheatClient.LastInsertAt = 0
NoCheatClient.LastMenuKeyAt = 0
NoCheatClient.LastHeartbeatAt = 0
NoCheatClient.LastAvoidDamageInspectAt = 0
NoCheatClient.AvoidDamageSamples = 0
NoCheatClient.AvoidDamageReported = false
NoCheatClient.LastReportAt = {}
NoCheatClient.ReportedEther = {}
NoCheatClient.Hooks = {}
NoCheatClient.PowerSnapshot = nil
NoCheatClient.LastPowerInspectAt = 0
NoCheatClient.CommandContext = nil

local function now()
    return os.time()
end

local function localPlayer()
    if getPlayer then
        return getPlayer()
    end
    return nil
end

local function reportKey(kind, fields)
    fields = fields or {}
    return tostring(kind)
        .. ":" .. tostring(fields.signature or fields.power or fields.action or fields.item or "")
        .. ":" .. tostring(fields.enabled or "")
end

local function canReport(kind, fields, cooldown)
    cooldown = cooldown or NoCheat.Const.ClientReportCooldownSeconds
    local at = now()
    local key = reportKey(kind, fields)
    local last = NoCheatClient.LastReportAt[key] or 0
    if (at - last) < cooldown then
        return false
    end
    return true
end

local function playerPositionText()
    return NoCheat.getPositionText(localPlayer())
end

local function sendReport(kind, fields, cooldown)
    if not NoCheat.isEnabled() then
        return false
    end
    fields = fields or {}
    local playerObj = localPlayer()
    if not playerObj or not sendClientCommand then
        return false
    end
    if not canReport(kind, fields, cooldown) then
        return false
    end
    fields.kind = kind
    fields.clientPos = playerPositionText()
    local ok = pcall(function()
        sendClientCommand(playerObj, NoCheat.Net.Module, NoCheat.Net.ReportCommand, fields)
    end)
    if not ok then
        return false
    end
    NoCheatClient.LastReportAt[reportKey(kind, fields)] = now()
    return true
end

local function safeString(value, maxLen)
    return NoCheat.safeText(value, maxLen or NoCheat.Const.ClientReportMaxText)
end

local function boolValue(value)
    return value == true or tostring(value) == "true"
end

local function getAccessText()
    local playerObj = localPlayer()
    if not playerObj then
        return "none"
    end
    local ok, value = pcall(function() return playerObj:getAccessLevel() end)
    if ok and value then
        return safeString(value, 40)
    end
    return "none"
end

local function vehicleLabel(vehicle)
    if not vehicle then
        return ""
    end
    local parts = {}
    local okScript, scriptName = pcall(function()
        if vehicle.getScriptName then
            return vehicle:getScriptName()
        end
        return nil
    end)
    if okScript and scriptName then
        parts[#parts + 1] = tostring(scriptName)
    end
    local okId, id = pcall(function()
        if vehicle.getId then
            return vehicle:getId()
        end
        return nil
    end)
    if okId and id then
        parts[#parts + 1] = "id=" .. tostring(id)
    end
    return safeString(table.concat(parts, " "), 120)
end

local function partLabel(part)
    if not part then
        return ""
    end
    local okId, id = pcall(function()
        if part.getId then
            return part:getId()
        end
        return nil
    end)
    if okId and id then
        return safeString(id, 80)
    end
    return safeString(part, 80)
end

local function reportVehicle(action, source, vehicle, part, value)
    sendReport("vehicle_cheat", {
        action = action,
        source = source,
        vehicle = vehicleLabel(vehicle),
        part = partLabel(part),
        value = safeString(value, 80)
    }, 1)
end

local function onKeyPressed(key)
    if not NoCheat.isEnabled() then
        return
    end

    local at = now()
    local keyCode = tonumber(key)

    if keyCode == NoCheat.Const.InsertKeyCode
        and (at - NoCheatClient.LastInsertAt) >= NoCheat.Const.InsertCooldownSeconds then
        NoCheatClient.LastInsertAt = at
        sendReport("insert_pressed", {
            keyCode = tostring(key),
            source = "Events.OnKeyPressed"
        }, NoCheat.Const.InsertCooldownSeconds)
    end

    -- This public Build 42 menu uses F1 (59) by default.  A key press alone is
    -- only an input signal; the server correlates it with stronger evidence.
    if keyCode == NoCheat.Const.EtherMenuKeyCode
        and (at - NoCheatClient.LastMenuKeyAt) >= NoCheat.Const.EtherMenuKeyCooldownSeconds then
        NoCheatClient.LastMenuKeyAt = at
        sendReport("ether_menu_key_pressed", {
            keyCode = tostring(key),
            source = "Events.OnKeyPressed"
        }, NoCheat.Const.EtherMenuKeyCooldownSeconds)
    end
end

-- Keep signatures split in the source.  The public menu can refuse to compile
-- mod Lua files that contain its primary global name as a contiguous string.
local function signature(parts)
    return table.concat(parts, "")
end

local EtherGlobalNameParts = {
    { "Et", "her", "Main" },
    { "Et", "her", "LuaCompiler" },
    { "Et", "her", "HackMenu" },
    { "Et", "her", "AdminMenu" },
    { "Et", "her", "DebugMenu" },
    { "Et", "her", "Panel" },
    { "Et", "her", "VehicleMenu" }
}

local EtherApiNameParts = {
    { "get", "MenuKeyID" },
    { "require", "Extra" },
    { "safePlayer", "Teleport" },
    { "hackAdmin", "Access" },
    { "toggleEnable", "GodMode" },
    { "isEnable", "GodMode" },
    { "toggleEnable", "Noclip" },
    { "toggleEnable", "Invisible" }
}

local function reportEtherOnce(kind, signature, detail, source)
    local key = kind .. ":" .. tostring(signature)
    if NoCheatClient.ReportedEther[key] then
        return
    end
    local sent = sendReport(kind, {
        signature = safeString(signature, 120),
        detail = safeString(detail, 220),
        source = safeString(source, 80)
    }, 1)
    if sent then
        NoCheatClient.ReportedEther[key] = true
    end
end

local function inspectEther()
    for i = 1, #EtherGlobalNameParts do
        local name = signature(EtherGlobalNameParts[i])
        if rawget(_G, name) ~= nil then
            reportEtherOnce("ether_globals_detected", name, "Known Ether global exists in client Lua state.", "global_scan")
        end
    end

    local mainName = signature({ "Et", "her", "Main" })
    local menuRoot = rawget(_G, mainName)
    if menuRoot ~= nil then
        reportEtherOnce("ether_detected", mainName, "Known menu table exists in client Lua state.", "global_scan")
        local okInstance, instance = pcall(function()
            if type(menuRoot) == "table" then
                return menuRoot.instance
            end
            return nil
        end)
        if okInstance and instance ~= nil then
            reportEtherOnce("ether_panel_open", mainName .. ".instance", "Known menu instance exists in client Lua state.", "global_scan")
        end
    end

    local apiMatches = {}
    for i = 1, #EtherApiNameParts do
        local name = signature(EtherApiNameParts[i])
        if type(rawget(_G, name)) == "function" then
            apiMatches[#apiMatches + 1] = name
        end
    end
    if #apiMatches >= 2 then
        reportEtherOnce("ether_api_detected", table.concat(apiMatches, ","),
            "Multiple known menu API functions exist in client Lua state.", "api_global_scan")
    end
end

local function inspectAvoidDamage(playerObj, at)
    if (at - NoCheatClient.LastAvoidDamageInspectAt) < NoCheat.Const.AvoidDamageSampleSeconds then
        return
    end
    NoCheatClient.LastAvoidDamageInspectAt = at

    local enabled = false
    local supported = false
    if playerObj and playerObj.isAvoidDamage then
        local ok, value = pcall(function() return playerObj:isAvoidDamage() end)
        supported = ok
        enabled = ok and boolValue(value)
    end
    if not supported then
        return
    end

    if enabled then
        NoCheatClient.AvoidDamageSamples = NoCheatClient.AvoidDamageSamples + 1
        if NoCheatClient.AvoidDamageSamples >= NoCheat.Const.AvoidDamageConsecutiveSamples
            and not NoCheatClient.AvoidDamageReported then
            if sendReport("avoid_damage_persistent", {
                samples = tostring(NoCheatClient.AvoidDamageSamples),
                sampleSeconds = tostring(NoCheat.Const.AvoidDamageSampleSeconds),
                source = "IsoPlayer.isAvoidDamage"
            }, 30) then
                NoCheatClient.AvoidDamageReported = true
            end
        end
    else
        NoCheatClient.AvoidDamageSamples = 0
        NoCheatClient.AvoidDamageReported = false
    end
end

local function sendHeartbeat(kind, source)
    local at = now()
    if kind ~= "client_ready" and (at - NoCheatClient.LastHeartbeatAt) < NoCheat.Const.ClientHeartbeatSeconds then
        return
    end
    if sendReport(kind, { source = source }, kind == "client_ready" and 10 or NoCheat.Const.ClientHeartbeatSeconds) then
        NoCheatClient.LastHeartbeatAt = at
    end
end

local function hookFunction(tableObj, functionName, hookName, wrapperFactory)
    if not tableObj or not functionName or NoCheatClient.Hooks[hookName] then
        return false
    end
    local original = tableObj[functionName]
    if type(original) ~= "function" then
        return false
    end
    tableObj[functionName] = wrapperFactory(original)
    NoCheatClient.Hooks[hookName] = true
    return true
end

local function detectPowerState(playerObj, power)
    if not playerObj then
        return false
    end
    local spec = NoCheat.AdminPowerSpecs[power]
    local method = spec and spec.getter
    if not method or not playerObj[method] then
        return false
    end
    local ok, value = pcall(function() return playerObj[method](playerObj) end)
    return ok and boolValue(value)
end

local function snapshotPowers(playerObj)
    local snapshot = {}
    for power, _ in pairs(NoCheat.AdminPowers) do
        snapshot[power] = detectPowerState(playerObj, power)
    end
    return snapshot
end

local function reportPowerChanges(before, after, source)
    for power, enabledAfter in pairs(after) do
        local enabledBefore = before and before[power] or false
        if enabledAfter ~= enabledBefore then
            sendReport("admin_power_toggle", {
                power = power,
                enabled = enabledAfter,
                access = getAccessText(),
                source = source
            }, 1)
        end
    end
end

local function inspectPowerStates(source)
    local playerObj = localPlayer()
    if not playerObj then
        return
    end

    local current = snapshotPowers(playerObj)
    if NoCheatClient.PowerSnapshot then
        reportPowerChanges(NoCheatClient.PowerSnapshot, current, source or "client_state_poll")
    else
        local inactive = {}
        reportPowerChanges(inactive, current, source or "client_state_initial")
    end
    NoCheatClient.PowerSnapshot = current
end

local function onPlayerUpdate(playerObj)
    if not NoCheat.isEnabled() or not playerObj or playerObj ~= localPlayer() then
        return
    end
    local at = now()
    inspectAvoidDamage(playerObj, at)
    sendHeartbeat("client_heartbeat", "Events.OnPlayerUpdate")
    if (at - NoCheatClient.LastPowerInspectAt) < NoCheat.Const.AdminPowerSampleSeconds then
        return
    end
    NoCheatClient.LastPowerInspectAt = at
    inspectPowerStates("client_state_poll")
end

local function hookAdminPowerUi()
    if not ISAdminPowerUI then
        pcall(require, "ISUI/AdminPanel/ISAdminPowerUI")
    end
    if not ISAdminPowerUI then
        return
    end

    hookFunction(ISAdminPowerUI, "onClick", "ISAdminPowerUI.onClick", function(original)
        return function(self, button)
            local buttonName = tostring(button and button.internal or "")
            local playerObj = self and self.player or localPlayer()
            local before = nil
            if buttonName == "SAVE" then
                before = snapshotPowers(playerObj)
            end
            local result = original(self, button)
            if buttonName == "SAVE" then
                local after = snapshotPowers(playerObj)
                reportPowerChanges(before, after, "ISAdminPowerUI.onClick")
                NoCheatClient.PowerSnapshot = after
            end
            return result
        end
    end)
end

local function hookItemSpawn()
    if not ISItemsListTable then
        pcall(require, "ISUI/AdminPanel/ISItemsListTable")
    end
    if not ISItemsListTable then
        return
    end

    hookFunction(ISItemsListTable, "onAddItem", "ISItemsListTable.onAddItem", function(original)
        return function(self, button, scriptItem)
            local itemName = ""
            local count = ""
            local target = ""
            pcall(function()
                if scriptItem and scriptItem.getFullName then
                    itemName = tostring(scriptItem:getFullName())
                end
                if button and button.parent and button.parent.entry then
                    count = tostring(button.parent.entry:getText())
                end
                if self.viewer and self.viewer.playerSelect then
                    target = tostring((self.viewer.playerSelect.selected or 1) - 1)
                end
            end)
            local accepted = button and button.internal == "OK" and tonumber(count) ~= nil
            if accepted then
                NoCheatClient.CommandContext = "admin_item_spawn"
            end
            local result = original(self, button, scriptItem)
            NoCheatClient.CommandContext = nil
            if accepted then
                sendReport("admin_item_spawn", {
                    item = safeString(itemName, 120),
                    count = safeString(count, 20),
                    target = safeString(target, 80),
                    source = "ISItemsListTable.onAddItem"
                }, 1)
            end
            return result
        end
    end)

    hookFunction(ISItemsListTable, "onOptionMouseDown", "ISItemsListTable.onOptionMouseDown", function(original)
        return function(self, button, x, y)
            local internal = tostring(button and button.internal or "")
            local countByButton = {
                ADDITEM1 = 1,
                ADDITEM2 = 2,
                ADDITEM5 = 5
            }
            local count = countByButton[internal]
            if count then
                NoCheatClient.CommandContext = "admin_item_spawn"
            end
            local result = original(self, button, x, y)
            NoCheatClient.CommandContext = nil
            if count then
                local itemName = ""
                pcall(function()
                    if button.parent and button.parent.datas and button.parent.datas.selected then
                        local item = button.parent.datas.items[button.parent.datas.selected].item
                        if item and item.getFullName then
                            itemName = tostring(item:getFullName())
                        end
                    end
                end)
                sendReport("admin_item_spawn", {
                    item = safeString(itemName, 120),
                    count = tostring(count),
                    source = "ISItemsListTable.onOptionMouseDown"
                }, 1)
            end
            return result
        end
    end)
end

local function hookVehicleMechanics()
    if not ISVehicleMechanics then
        pcall(require, "Vehicles/ISUI/ISVehicleMechanics")
    end
    if ISVehicleMechanics then
        hookFunction(ISVehicleMechanics, "onCheatRepair", "ISVehicleMechanics.onCheatRepair", function(original)
            return function(playerObj, vehicle)
                local result = original(playerObj, vehicle)
                reportVehicle("repair_vehicle", "ISVehicleMechanics.onCheatRepair", vehicle, nil, "")
                return result
            end
        end)

        hookFunction(ISVehicleMechanics, "onCheatRepairPart", "ISVehicleMechanics.onCheatRepairPart", function(original)
            return function(playerObj, part)
                local vehicle = nil
                pcall(function()
                    if part and part.getVehicle then
                        vehicle = part:getVehicle()
                    end
                end)
                local result = original(playerObj, part)
                reportVehicle("repair_part", "ISVehicleMechanics.onCheatRepairPart", vehicle, part, "")
                return result
            end
        end)

        hookFunction(ISVehicleMechanics, "onCheatGetKey", "ISVehicleMechanics.onCheatGetKey", function(original)
            return function(playerObj, vehicle)
                local result = original(playerObj, vehicle)
                reportVehicle("get_key", "ISVehicleMechanics.onCheatGetKey", vehicle, nil, "")
                return result
            end
        end)

        hookFunction(ISVehicleMechanics, "onCheatHotwire", "ISVehicleMechanics.onCheatHotwire", function(original)
            return function(playerObj, vehicle, hotwired, broken)
                local result = original(playerObj, vehicle, hotwired, broken)
                reportVehicle("hotwire", "ISVehicleMechanics.onCheatHotwire", vehicle, nil, "")
                return result
            end
        end)

        hookFunction(ISVehicleMechanics, "onCheatSetConditionAux", "ISVehicleMechanics.onCheatSetConditionAux", function(original)
            return function(target, button, playerObj, part)
                local value = ""
                pcall(function()
                    if button and button.parent and button.parent.entry then
                        value = tostring(button.parent.entry:getText())
                    end
                end)
                local accepted = button and button.internal == "OK" and tonumber(value) ~= nil
                local result = original(target, button, playerObj, part)
                if not accepted then
                    return result
                end
                local vehicle = nil
                pcall(function()
                    if part and part.getVehicle then
                        vehicle = part:getVehicle()
                    end
                end)
                reportVehicle("set_part_condition", "ISVehicleMechanics.onCheatSetConditionAux", vehicle, part, value)
                return result
            end
        end)

        hookFunction(ISVehicleMechanics, "onCheatSetContentAmountAux", "ISVehicleMechanics.onCheatSetContentAmountAux", function(original)
            return function(target, button, playerObj, part)
                local value = ""
                pcall(function()
                    if button and button.parent and button.parent.entry then
                        value = tostring(button.parent.entry:getText())
                    end
                end)
                local accepted = button and button.internal == "OK" and tonumber(value) ~= nil
                local result = original(target, button, playerObj, part)
                if not accepted then
                    return result
                end
                local vehicle = nil
                pcall(function()
                    if part and part.getVehicle then
                        vehicle = part:getVehicle()
                    end
                end)
                reportVehicle("set_content_amount", "ISVehicleMechanics.onCheatSetContentAmountAux", vehicle, part, value)
                return result
            end
        end)

        hookFunction(ISVehicleMechanics, "onCheatToggle", "ISVehicleMechanics.onCheatToggle", function(original)
            return function(playerObj)
                local before = snapshotPowers(playerObj)
                local result = original(playerObj)
                local after = snapshotPowers(playerObj)
                reportPowerChanges(before, after, "ISVehicleMechanics.onCheatToggle")
                NoCheatClient.PowerSnapshot = after
                return result
            end
        end)

        hookFunction(ISVehicleMechanics, "onCheatRemoveAux", "ISVehicleMechanics.onCheatRemoveAux", function(original)
            return function(dummy, button, playerObj, vehicle)
                local accepted = button and button.internal ~= "NO"
                local result = original(dummy, button, playerObj, vehicle)
                if accepted then
                    reportVehicle("remove_vehicle", "ISVehicleMechanics.onCheatRemoveAux", vehicle, nil, "")
                end
                return result
            end
        end)
    end

    if not ISSpawnVehicleUI then
        pcall(require, "DebugUIs/ISSpawnVehicleUI")
    end
    if ISSpawnVehicleUI then
        hookFunction(ISSpawnVehicleUI, "onClick", "ISSpawnVehicleUI.onClick", function(original)
            return function(self, button)
                local internal = tostring(button and button.internal or "")
                local actionByButton = {
                    SPAWN = "spawn_vehicle",
                    GETKEY = "get_key",
                    REPAIR = "repair_vehicle"
                }
                local action = actionByButton[internal]
                local vehicle = ""
                pcall(function()
                    if action == "spawn_vehicle" and self.getVehicle then
                        vehicle = tostring(self:getVehicle())
                    elseif self.vehicle then
                        vehicle = vehicleLabel(self.vehicle)
                    end
                end)
                if action then
                    NoCheatClient.CommandContext = "vehicle_cheat"
                end
                local result = original(self, button)
                NoCheatClient.CommandContext = nil
                if action then
                    sendReport("vehicle_cheat", {
                        action = action,
                        source = "ISSpawnVehicleUI.onClick",
                        vehicle = safeString(vehicle, 120)
                    }, 1)
                end
                return result
            end
        end)
    end
end

local function hookTeleportUi()
    if not DebugContextMenu then
        pcall(require, "DebugUIs/DebugContextMenu")
    end
    if DebugContextMenu then
        hookFunction(DebugContextMenu, "onTeleportValid", "DebugContextMenu.onTeleportValid", function(original)
            return function(button, worldX, worldY, worldZ)
                sendReport("admin_teleport_ui", {
                    fromPos = playerPositionText(),
                    toPos = tostring(worldX or "") .. "," .. tostring(worldY or "") .. "," .. tostring(worldZ or ""),
                    source = "DebugContextMenu.onTeleportValid"
                }, 1)
                return original(button, worldX, worldY, worldZ)
            end
        end)
    end

    if not ISMiniMapInner then
        pcall(require, "ISUI/Maps/ISMiniMap")
    end
    if ISMiniMapInner then
        hookFunction(ISMiniMapInner, "onTeleport", "ISMiniMapInner.onTeleport", function(original)
            return function(self, worldX, worldY)
                sendReport("admin_teleport_ui", {
                    fromPos = playerPositionText(),
                    toPos = tostring(worldX or "") .. "," .. tostring(worldY or "") .. ",0",
                    source = "ISMiniMapInner.onTeleport"
                }, 1)
                return original(self, worldX, worldY)
            end
        end)
    end

    if not ISWorldMap then
        pcall(require, "ISUI/Maps/ISWorldMap")
    end
    if ISWorldMap then
        hookFunction(ISWorldMap, "onTeleport", "ISWorldMap.onTeleport", function(original)
            return function(self, worldX, worldY)
                sendReport("admin_teleport_ui", {
                    fromPos = playerPositionText(),
                    toPos = tostring(worldX or "") .. "," .. tostring(worldY or "") .. ",0",
                    source = "ISWorldMap.onTeleport"
                }, 1)
                return original(self, worldX, worldY)
            end
        end)
    end
end

local function hookSensitiveServerCommands()
    hookFunction(_G, "SendCommandToServer", "_G.SendCommandToServer", function(original)
        return function(command)
            local text = tostring(command or "")
            local result = original(command)

            local item = text:match('^/additem%s+"[^"]*"%s+"([^"]+)"')
            if item and NoCheatClient.CommandContext ~= "admin_item_spawn" then
                sendReport("admin_item_spawn", {
                    item = safeString(item, 120),
                    count = "1",
                    source = "SendCommandToServer:/additem"
                }, 1)
            end

            local destination = text:match("^/teleportto%s+(.+)$")
            if destination and NoCheatClient.CommandContext ~= "admin_teleport_ui" then
                sendReport("admin_teleport_ui", {
                    fromPos = playerPositionText(),
                    toPos = safeString(destination, 80),
                    source = "SendCommandToServer:/teleportto"
                }, 1)
            end

            local vehicleScript = text:match("^/addvehicle%s+(.+)$")
            if vehicleScript and NoCheatClient.CommandContext ~= "vehicle_cheat" then
                sendReport("vehicle_cheat", {
                    action = "spawn_vehicle",
                    vehicle = safeString(vehicleScript, 120),
                    source = "SendCommandToServer:/addvehicle"
                }, 1)
            end

            return result
        end
    end)
end

local function initHooks()
    if not NoCheat.isEnabled() then
        return
    end

    inspectEther()
    sendHeartbeat("client_ready", "initHooks")
    hookAdminPowerUi()
    hookItemSpawn()
    hookVehicleMechanics()
    hookTeleportUi()
    hookSensitiveServerCommands()
    inspectPowerStates("client_state_initial")
end

Events.OnKeyPressed.Add(onKeyPressed)
Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnGameStart.Add(initHooks)
Events.OnCreatePlayer.Add(function()
    initHooks()
end)
Events.EveryOneMinute.Add(initHooks)

