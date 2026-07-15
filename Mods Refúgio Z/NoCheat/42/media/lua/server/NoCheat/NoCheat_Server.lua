if not isServer() then
    return
end

require "NoCheat/00_NoCheat_Shared"

if _G.__NoCheatServerLoaded then
    return
end
_G.__NoCheatServerLoaded = true

local NoCheatServer = {}
-- Public server-only integration surface for trusted mods.  Clients cannot
-- invoke this table; integrations must call it after their own validation and
-- authoritative mutation have completed.
_G.NoCheatServer = NoCheatServer
NoCheatServer.SkillSnapshots = {}
NoCheatServer.PositionSnapshots = {}
NoCheatServer.ClientCooldowns = {}
NoCheatServer.InsertEvents = {}
NoCheatServer.RecentSignals = {}
NoCheatServer.TeleportLastLogged = {}
NoCheatServer.PowerSnapshots = {}
NoCheatServer.PendingPowerReports = {}
NoCheatServer.PowerLastTransitions = {}
NoCheatServer.VehicleLastEvents = {}
NoCheatServer.ClientIntegrity = {}
NoCheatServer.LastTick = {
    adminPower = 0,
    skill = 0,
    teleport = 0,
    integrity = 0
}
NoCheatServer.SuppressedLogUsernames = {
    adm = true,
    adm1 = true,
    adm2 = true,
    adm3 = true,
    adm4 = true
}

local PowerCapabilities = {
    Invisible = Capability.ToggleInvisibleHimself,
    GodMod = Capability.ToggleGodModHimself,
    NoClip = Capability.ToggleNoclipHimself,
    FastMove = Capability.UseFastMoveCheat,
    TimedActionInstant = Capability.UseTimedActionInstantCheat,
    UnlimitedCarry = Capability.ToggleUnlimitedCarry,
    UnlimitedEndurance = Capability.ToggleUnlimitedEndurance,
    UnlimitedAmmo = Capability.ToggleUnlimitedAmmo,
    KnowAllRecipes = Capability.ToggleKnowAllRecipes,
    BuildCheat = Capability.UseBuildCheat,
    FarmingCheat = Capability.UseFarmingCheat,
    FishingCheat = Capability.UseFishingCheat,
    HealthCheat = Capability.UseHealthCheat,
    MechanicsCheat = Capability.UseMechanicsCheat,
    MoveableCheat = Capability.UseMovablesCheat,
    CanSeeAll = Capability.CanSeeAll,
    CanHearAll = Capability.CanHearAll,
    ZombiesDontAttack = Capability.ManipulateZombie,
    BrushTool = Capability.UseBrushToolManager,
    LootZed = Capability.UseLootZed,
    LootLog = Capability.UseLootLog,
    AnimalCheat = Capability.AnimalCheats,
    AnimalExtraValues = Capability.AnimalCheats
}

local VehicleCommandActions = {
    repair = "repair_vehicle",
    repairPart = "repair_part",
    setPartCondition = "set_part_condition",
    setContainerContentAmount = "set_content_amount",
    setRust = "set_rust",
    remove = "remove_vehicle",
    cheatHotwire = "hotwire",
    getKey = "get_key"
}

local DangerousClientKinds = {
    ether_detected = true,
    ether_panel_open = true,
    ether_globals_detected = true,
    ether_api_detected = true,
    avoid_damage_persistent = true,
    admin_item_spawn = true,
    admin_teleport_ui = true,
    vehicle_cheat = true
}

local function now()
    return os.time()
end

local function timeText(timestamp)
    return os.date("%Y-%m-%d %H:%M:%S", timestamp or now())
end

local function dayText(timestamp)
    return os.date("%Y-%m-%d", timestamp or now())
end

local function playerName(playerObj)
    if not playerObj then
        return "unknown"
    end
    local ok, value = pcall(function() return playerObj:getUsername() end)
    if ok and value and tostring(value) ~= "" then
        return NoCheat.safeText(value, 80)
    end
    return "unknown"
end

local function suppressLogsForPlayer(playerObj)
    if not playerObj then
        return false
    end
    local ok, username = pcall(function() return playerObj:getUsername() end)
    if not ok or not username then
        return false
    end
    return NoCheatServer.SuppressedLogUsernames[tostring(username):lower()] == true
end

local function playerAccess(playerObj)
    if not playerObj then
        return "none"
    end
    local ok, value = pcall(function() return playerObj:getAccessLevel() end)
    if ok and value then
        return NoCheat.safeText(value, 40):lower()
    end
    return "none"
end

local function playerSteam(playerObj)
    if not playerObj then
        return "unknown"
    end

    local function exactSteamText(value)
        if value == nil then
            return nil
        end
        local text = tostring(value)
        if text == "" or text == "0" or text:find("[eE]") or not text:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d$") then
            return nil
        end
        return NoCheat.safeText(text, 80)
    end

    if playerObj.getSteamIDString then
        local ok, value = pcall(function() return playerObj:getSteamIDString() end)
        local steam = ok and exactSteamText(value) or nil
        if steam then
            return steam
        end
    end

    local usernameOk, username = pcall(function() return playerObj:getUsername() end)
    if usernameOk and username and tostring(username) ~= "" and _G.getSteamIDFromUsername then
        local ok, value = pcall(function() return _G.getSteamIDFromUsername(username) end)
        local steam = ok and exactSteamText(value) or nil
        if steam then
            return steam
        end
    end

    if playerObj.getSteamID then
        local ok, value = pcall(function() return playerObj:getSteamID() end)
        local steam = ok and exactSteamText(value) or nil
        if steam then
            return steam
        end
    end

    return "unknown"
end

local function playerKey(playerObj)
    local steam = playerSteam(playerObj)
    if steam ~= "unknown" then
        return steam
    end
    return playerName(playerObj)
end

local function isStaff(playerObj)
    if not playerObj then
        return false
    end
    local ok, allowed = pcall(function()
        local role = playerObj:getRole()
        return role and role:hasAdminPower()
    end)
    return ok and allowed == true
end

local function hasCapability(playerObj, capability)
    if not playerObj or not capability then
        return false
    end
    local ok, allowed = pcall(function()
        local role = playerObj:getRole()
        return role and role:hasCapability(capability)
    end)
    return ok and allowed == true
end

local function canUseTeleportPower(playerObj)
    return isStaff(playerObj)
        or hasCapability(playerObj, Capability.TeleportToCoordinates)
        or hasCapability(playerObj, Capability.TeleportToPlayer)
        or hasCapability(playerObj, Capability.TeleportPlayerToAnotherPlayer)
end

local function applySandboxConfig()
    if not SandboxVars or not SandboxVars.NoCheat then
        return
    end

    local vars = SandboxVars.NoCheat
    if vars.InsertWarnCount then
        NoCheat.Const.InsertWarnCount = tonumber(vars.InsertWarnCount) or NoCheat.Const.InsertWarnCount
    end
    if vars.TeleportWarnDistance then
        NoCheat.Const.TeleportWarnDistance = tonumber(vars.TeleportWarnDistance) or NoCheat.Const.TeleportWarnDistance
    end
    if vars.SkillHighTotalDelta then
        NoCheat.Const.SkillHighTotalDelta = tonumber(vars.SkillHighTotalDelta) or NoCheat.Const.SkillHighTotalDelta
    end
end

local function writeLine(category, line)
    category = NoCheat.categoryOrSystem(category)
    local path = "/" .. NoCheat.Log.Root .. "/" .. dayText() .. "/" .. NoCheat.safeFilePart(category, 40) .. ".log"
    local okWriter, writer = pcall(getFileWriter, path, true, true)
    if not okWriter or not writer then
        print("[NoCheat][ERROR] Unable to open log file '" .. path .. "': " .. tostring(writer))
        return false
    end

    local okWrite, writeError = pcall(function()
        writer:write(line .. "\r\n")
        writer:close()
    end)
    if not okWrite then
        pcall(function() writer:close() end)
        print("[NoCheat][ERROR] Unable to write log file '" .. path .. "': " .. tostring(writeError))
        return false
    end
    return true
end

local function shouldWriteAlert(category, kind, severity, fields)
    if category == "teleport" and kind == "fast_position_jump" then
        return false
    end
    return severity == "high" or severity == "critical" or severity == "evidence" or fields.alert == true
end

local function shouldWriteField(value)
    if value == nil or value == false then
        return false
    end
    return NoCheat.safeText(value, 180) ~= ""
end

local function emit(playerObj, category, kind, severity, detail, fields)
    if suppressLogsForPlayer(playerObj) then
        return
    end

    category = NoCheat.categoryOrSystem(category)
    severity = NoCheat.safeText(severity or "info", 24):lower()
    kind = NoCheat.safeText(kind or "event", 80)
    detail = NoCheat.safeText(detail or "", NoCheat.Const.ClientReportMaxText)
    fields = fields or {}

    local parts = {
        "[NO_CHEAT]",
        "[" .. timeText() .. "]",
        "[" .. severity:upper() .. "]",
        "[category=" .. category .. "]",
        "[kind=" .. kind .. "]",
        "[actor=" .. playerName(playerObj) .. "]",
        "[access=" .. playerAccess(playerObj) .. "]",
        "[steam=" .. playerSteam(playerObj) .. "]",
        "[pos=" .. NoCheat.getPositionText(playerObj) .. "]"
    }

    for key, value in pairs(fields) do
        if shouldWriteField(value) then
            parts[#parts + 1] = "[" .. NoCheat.safeText(key, 40) .. "=" .. NoCheat.safeText(value, 180) .. "]"
        end
    end

    if detail ~= "" then
        parts[#parts + 1] = "[detail=" .. detail .. "]"
    end

    local line = table.concat(parts, "")
    writeLine(category, line)

    if shouldWriteAlert(category, kind, severity, fields) then
        writeLine(NoCheat.Log.AlertFile, line)
    end
end

local function markSignalAndCorrelate(playerObj, category, kind, severity)
    local key = playerKey(playerObj)
    local at = now()
    NoCheatServer.RecentSignals[key] = NoCheatServer.RecentSignals[key] or {}
    local bucket = NoCheatServer.RecentSignals[key]

    if category == "insert" then
        bucket.lastInsertAt = at
        return
    end

    if category == "ether" and kind == "ether_menu_key_pressed" then
        bucket.lastEtherMenuKeyAt = at
        return
    end

    if bucket.lastInsertAt and (at - bucket.lastInsertAt) <= NoCheat.Const.InsertCorrelationSeconds then
        local correlationKey = tostring(category) .. ":" .. tostring(kind)
        local correlatedAt = tonumber(bucket[correlationKey]) or 0
        if correlatedAt < bucket.lastInsertAt then
            bucket[correlationKey] = at
            emit(playerObj, "insert", "insert_correlated_signal", "high",
                "Insert key was reported before another suspicious event.",
                {
                    correlatedCategory = category,
                    correlatedKind = kind,
                    secondsSinceInsert = at - bucket.lastInsertAt,
                    sourceSeverity = severity,
                    alert = true
                }
            )
        end
    end


    if bucket.lastEtherMenuKeyAt and (at - bucket.lastEtherMenuKeyAt) <= NoCheat.Const.InsertCorrelationSeconds then
        local correlationKey = "menu:" .. tostring(category) .. ":" .. tostring(kind)
        local correlatedAt = tonumber(bucket[correlationKey]) or 0
        if correlatedAt < bucket.lastEtherMenuKeyAt then
            bucket[correlationKey] = at
            emit(playerObj, "ether", "ether_menu_key_correlated_signal", "high",
                "F1 menu key was reported before another suspicious event.",
                {
                    correlatedCategory = category,
                    correlatedKind = kind,
                    secondsSinceMenuKey = at - bucket.lastEtherMenuKeyAt,
                    sourceSeverity = severity,
                    alert = true
                }
            )
        end
    end
end

local function clientCooldownKey(playerObj, kind, args)
    local extra = ""
    if type(args) == "table" then
        extra = tostring(args.signature or args.power or args.action or args.item or "")
        if args.enabled ~= nil then
            extra = extra .. ":" .. tostring(args.enabled)
        end
    end
    return playerKey(playerObj) .. ":" .. tostring(kind) .. ":" .. extra
end

local function clientCooldownOk(playerObj, kind, args)
    local key = clientCooldownKey(playerObj, kind, args)
    local at = now()
    local last = NoCheatServer.ClientCooldowns[key] or 0
    if (at - last) < NoCheat.Const.ClientReportCooldownSeconds then
        return false
    end
    NoCheatServer.ClientCooldowns[key] = at
    return true
end

local function getArgsText(args, key, maxLen)
    if type(args) ~= "table" then
        return ""
    end
    return NoCheat.safeText(args[key], maxLen)
end

local function getArgsBool(args, key)
    if type(args) ~= "table" then
        return false
    end
    return args[key] == true or tostring(args[key]) == "true"
end

local function powerTransitionKey(playerObj, power, enabled)
    return playerKey(playerObj) .. ":" .. tostring(power) .. ":" .. NoCheat.boolText(enabled)
end

local function readPowerState(playerObj, power)
    local spec = NoCheat.AdminPowerSpecs[power]
    local method = spec and spec.getter
    if not playerObj or not method or not playerObj[method] then
        return nil
    end
    local ok, value = pcall(function()
        return playerObj[method](playerObj)
    end)
    if not ok then
        return nil
    end
    return value == true or tostring(value) == "true"
end

local function powerAuthorized(playerObj, power)
    return hasCapability(playerObj, PowerCapabilities[power])
end

local function emitPowerTransition(playerObj, power, enabled, source, serverConfirmed, durationSeconds, clientSource)
    local spec = NoCheat.AdminPowerSpecs[power]
    if not spec then
        return
    end

    local authorized = powerAuthorized(playerObj, power)
    local severity = "info"
    local alert = false
    if enabled then
        if not authorized then
            severity = "critical"
            alert = true
        elseif spec.alertWhenAuthorized then
            severity = "high"
            alert = true
        else
            severity = "warn"
        end
    end

    local kind = enabled and "admin_power_enabled" or "admin_power_disabled"
    emit(playerObj, spec.category, kind, severity,
        enabled and "Admin or cheat power changed to enabled." or "Admin or cheat power changed to disabled.",
        {
            power = power,
            enabled = NoCheat.boolText(enabled),
            authorized = NoCheat.boolText(authorized),
            capability = spec.capability,
            source = source,
            clientSource = clientSource,
            serverConfirmed = NoCheat.boolText(serverConfirmed),
            durationSeconds = durationSeconds,
            alert = alert
        }
    )

    NoCheatServer.PowerLastTransitions[powerTransitionKey(playerObj, power, enabled)] = now()
    if enabled then
        markSignalAndCorrelate(playerObj, spec.category, kind, severity)
    end
end

local function inspectAdminPowers()
    if not getOnlinePlayers then
        return
    end

    local players = getOnlinePlayers()
    local at = now()
    if players then
        for i = 0, players:size() - 1 do
            local playerObj = players:get(i)
            if playerObj then
                local key = playerKey(playerObj)
                local snapshot = NoCheatServer.PowerSnapshots[key] or {
                    states = {},
                    enabledAt = {}
                }

                for power, _ in pairs(NoCheat.AdminPowerSpecs) do
                    local current = readPowerState(playerObj, power)
                    local previous = snapshot.states[power]
                    if current ~= nil then
                        local changed = previous ~= nil and previous ~= current
                        local initiallyEnabled = previous == nil and current == true
                        if changed or initiallyEnabled then
                            local durationSeconds = nil
                            if current then
                                snapshot.enabledAt[power] = at
                            else
                                local enabledAt = snapshot.enabledAt[power]
                                if enabledAt then
                                    durationSeconds = math.max(0, at - enabledAt)
                                end
                                snapshot.enabledAt[power] = nil
                            end

                            local transitionKey = powerTransitionKey(playerObj, power, current)
                            local pending = NoCheatServer.PendingPowerReports[transitionKey]
                            NoCheatServer.PendingPowerReports[transitionKey] = nil
                            emitPowerTransition(
                                playerObj,
                                power,
                                current,
                                initiallyEnabled and "server_initial_state" or "server_state_transition",
                                true,
                                durationSeconds,
                                pending and pending.source or nil
                            )
                        end
                        snapshot.states[power] = current
                    end
                end

                NoCheatServer.PowerSnapshots[key] = snapshot
            end
        end
    end

    local stale = {}
    for transitionKey, pending in pairs(NoCheatServer.PendingPowerReports) do
        if (at - pending.at) >= NoCheat.Const.AdminPowerClientFallbackSeconds then
            stale[#stale + 1] = transitionKey
        end
    end
    for i = 1, #stale do
        local transitionKey = stale[i]
        local pending = NoCheatServer.PendingPowerReports[transitionKey]
        NoCheatServer.PendingPowerReports[transitionKey] = nil
        if pending and pending.playerObj then
            emitPowerTransition(
                pending.playerObj,
                pending.power,
                pending.enabled,
                "client_report_fallback",
                false,
                nil,
                pending.source
            )
        end
    end
end

local function processInsert(playerObj, args)
    local key = playerKey(playerObj)
    local at = now()
    local events = NoCheatServer.InsertEvents[key] or {}
    local fresh = {}
    for i = 1, #events do
        if (at - events[i]) <= NoCheat.Const.InsertWindowSeconds then
            fresh[#fresh + 1] = events[i]
        end
    end
    fresh[#fresh + 1] = at
    NoCheatServer.InsertEvents[key] = fresh

    local severity = "info"
    local alert = false
    if #fresh >= NoCheat.Const.InsertWarnCount then
        severity = "high"
        alert = true
    end

    emit(playerObj, "insert", "insert_pressed", severity,
        "Client reported Insert key.",
        {
            countInWindow = #fresh,
            windowSeconds = NoCheat.Const.InsertWindowSeconds,
            keyCode = getArgsText(args, "keyCode", 20),
            alert = alert
        }
    )
    markSignalAndCorrelate(playerObj, "insert", "insert_pressed", severity)
end

local function processEther(playerObj, kind, args)
    local detail = getArgsText(args, "detail", 220)
    local signature = getArgsText(args, "signature", 120)
    emit(playerObj, "ether", kind, "evidence", detail, {
        signature = signature,
        source = getArgsText(args, "source", 80),
        alert = true
    })
    markSignalAndCorrelate(playerObj, "ether", kind, "evidence")
end

local function processEtherMenuKey(playerObj, args)
    emit(playerObj, "ether", "ether_menu_key_pressed", "info",
        "Client reported the default F1 key used by the referenced menu.", {
            keyCode = getArgsText(args, "keyCode", 20),
            source = getArgsText(args, "source", 80),
            alert = false
        })
    markSignalAndCorrelate(playerObj, "ether", "ether_menu_key_pressed", "info")
end

local function processAvoidDamage(playerObj, args)
    local authorized = hasCapability(playerObj, Capability.ToggleGodModHimself)
    local severity = authorized and "warn"…714 tokens truncated…leport", "admin_teleport_ui", severity,
        "Client teleport UI hook fired.",
        {
            fromPos = getArgsText(args, "fromPos", 80),
            toPos = getArgsText(args, "toPos", 80),
            source = getArgsText(args, "source", 80),
            authorized = NoCheat.boolText(authorized),
            capability = "TeleportToCoordinates",
            alert = alert
        }
    )
    markSignalAndCorrelate(playerObj, "teleport", "admin_teleport_ui", severity)
end

local function canonicalVehicleRef(value)
    local text = NoCheat.safeText(value, 120)
    local id = text:match("id=([%-]?%d+)")
    return id or text
end

local function vehicleActionText(action, vehicle, part)
    local vehicleText = vehicle ~= "" and ("vehicle #" .. vehicle) or "vehicle"
    if action == "repair_vehicle" then
        return "repaired " .. vehicleText
    end
    if action == "repair_part" then
        return "repaired " .. (part ~= "" and part or "part") .. " on " .. vehicleText
    end
    if action == "set_part_condition" then
        return "changed " .. (part ~= "" and part or "part") .. " condition on " .. vehicleText
    end
    if action == "set_content_amount" then
        return "changed container amount on " .. vehicleText
    end
    if action == "set_rust" then
        return "changed rust on " .. vehicleText
    end
    if action == "remove_vehicle" then
        return "removed " .. vehicleText
    end
    if action == "hotwire" then
        return "hotwired " .. vehicleText
    end
    if action == "get_key" then
        return "got key for " .. vehicleText
    end
    return action .. " on " .. vehicleText
end

local function vehicleOriginText(source, serverConfirmed)
    if serverConfirmed == true and tostring(source):find("^OnClientCommand:vehicle%.") then
        return "vanilla_server_command"
    end
    if serverConfirmed == true then
        return "server_confirmed"
    end
    return "client_report_hook"
end

local function emitVehicleAction(playerObj, action, vehicle, part, value, source, serverConfirmed)
    if not NoCheat.VehicleActions[action] then
        return
    end

    vehicle = canonicalVehicleRef(vehicle)
    part = NoCheat.safeText(part, 80)
    local eventKey = playerKey(playerObj) .. ":" .. action .. ":" .. vehicle .. ":" .. part
    local at = now()
    local last = NoCheatServer.VehicleLastEvents[eventKey] or 0
    if (at - last) < NoCheat.Const.ClientReportCooldownSeconds then
        return
    end
    NoCheatServer.VehicleLastEvents[eventKey] = at

    local authorized = hasCapability(playerObj, Capability.UseMechanicsCheat)
    local severity = authorized and "warn" or "critical"
    local alert = not authorized
    local origin = vehicleOriginText(source, serverConfirmed)
    local actionText = vehicleActionText(action, vehicle, part)
    local kind = authorized and "vehicle_admin_action" or "vehicle_cheat"
    local detail = authorized
        and ("Authorized admin " .. actionText .. " via " .. origin .. ".")
        or ("UNAUTHORIZED vehicle action: " .. actionText .. " via " .. origin .. ".")

    emit(playerObj, "vehicle_repair", kind, severity,
        detail,
        {
            action = action,
            vehicle = vehicle,
            part = part,
            value = NoCheat.safeText(value, 80),
            origin = origin,
            authorized = NoCheat.boolText(authorized),
            source = NoCheat.safeText(source, 80),
            alert = alert
        }
    )
    markSignalAndCorrelate(playerObj, "vehicle_repair", kind, severity)
end

local function processVehicleCheat(playerObj, args)
    emitVehicleAction(
        playerObj,
        getArgsText(args, "action", 80),
        getArgsText(args, "vehicle", 120),
        getArgsText(args, "part", 80),
        getArgsText(args, "value", 80),
        getArgsText(args, "source", 80),
        false
    )
end

local function processVanillaVehicleCommand(commandName, playerObj, args)
    local action = VehicleCommandActions[commandName]
    if not action or type(args) ~= "table" then
        return
    end
    local value = args.condition or args.amount or args.rust or args.hotwired or ""
    emitVehicleAction(
        playerObj,
        action,
        args.vehicle,
        args.part,
        value,
        "OnClientCommand:vehicle." .. commandName,
        true
    )
end

local function onClientCommand(moduleName, commandName, playerObj, args)
    if not NoCheat.isEnabled() then
        return
    end
    if moduleName == "vehicle" and playerObj then
        processVanillaVehicleCommand(commandName, playerObj, args)
    end
    if moduleName ~= NoCheat.Net.Module or commandName ~= NoCheat.Net.ReportCommand then
        return
    end
    if not playerObj or type(args) ~= "table" then
        return
    end

    local kind = getArgsText(args, "kind", 80)
    if not NoCheat.ClientKinds[kind] then
        return
    end
    if not clientCooldownOk(playerObj, kind, args) then
        return
    end

    if kind == "insert_pressed" then
        processInsert(playerObj, args)
        return
    end

    if kind == "ether_detected" or kind == "ether_panel_open" or kind == "ether_globals_detected" or kind == "ether_api_detected" then
        processEther(playerObj, kind, args)
        return
    end

    if kind == "ether_menu_key_pressed" then
        processEtherMenuKey(playerObj, args)
        return
    end

    if kind == "avoid_damage_persistent" then
        processAvoidDamage(playerObj, args)
        return
    end

    if kind == "client_ready" or kind == "client_heartbeat" then
        processClientIntegrity(playerObj, kind, args)
        return
    end

    if kind == "admin_power_toggle" then
        processAdminPower(playerObj, args)
        return
    end

    if kind == "admin_item_spawn" then
        processItemSpawn(playerObj, args)
        return
    end

    if kind == "admin_teleport_ui" then
        processTeleportUi(playerObj, args)
        return
    end

    if kind == "vehicle_cheat" then
        processVehicleCheat(playerObj, args)
        return
    end

    if DangerousClientKinds[kind] then
        emit(playerObj, "system", "unhandled_client_report", "warn", "Known report kind was not handled.", {
            kind = kind
        })
    end
end

local function buildSkillSnapshot(playerObj)
    local snapshot = {}
    if not playerObj or not Perks or not PerkFactory then
        return snapshot
    end

    local okMax, maxIndex = pcall(function() return Perks.getMaxIndex() end)
    if not okMax or not maxIndex then
        return snapshot
    end

    for i = 0, maxIndex - 1 do
        local okPerk, perkEnum, perk = pcall(function()
            local enumValue = Perks.fromIndex(i)
            return enumValue, PerkFactory.getPerk(enumValue)
        end)
        if okPerk and perkEnum and perk then
            local okName, name = pcall(function()
                if perk.getType then
                    return tostring(perk:getType())
                end
                if perk.getName then
                    return tostring(perk:getName())
                end
                return tostring(i)
            end)
            local okLevel, level = pcall(function()
                return playerObj:getPerkLevel(perkEnum)
            end)
            if okName and okLevel and name and tonumber(level) then
                snapshot[name] = tonumber(level)
            end
        end
    end

    return snapshot
end

-- Accept a server-authorized bulk skill mutation without creating a blind
-- grace window.  Replacing the baseline immediately means only the mutation
-- that has already been validated by the integrating server mod is ignored.
function NoCheatServer.acceptSkillBaseline(playerObj, details)
    if not playerObj then
        return false
    end

    details = type(details) == "table" and details or {}
    local key = playerKey(playerObj)
    local levels = buildSkillSnapshot(playerObj)
    NoCheatServer.SkillSnapshots[key] = {
        at = now(),
        levels = levels
    }

    emit(playerObj, "skill_level", "authorized_skill_recovery", "info",
        "Server-authorized skill recovery updated the anti-cheat baseline.",
        {
            source = NoCheat.safeText(details.source or "trusted_server_mod", 80),
            action = NoCheat.safeText(details.action or "skill_recovery", 80),
            recoveredXP = NoCheat.safeText(details.recoveredXP or "", 80),
            recoveredSkills = NoCheat.safeText(details.recoveredSkills or "", 80),
            journal = NoCheat.safeText(details.journalUUID or "", 120),
            authorized = "true",
            alert = false
        }
    )
    return true
end

local function inspectSkills()
    if not getOnlinePlayers then
        return
    end

    local players = getOnlinePlayers()
    if not players then
        return
    end

    local at = now()
    for i = 0, players:size() - 1 do
        local playerObj = players:get(i)
        if playerObj then
            local key = playerKey(playerObj)
            local current = buildSkillSnapshot(playerObj)
            local previous = NoCheatServer.SkillSnapshots[key]

            if previous and previous.levels and (at - previous.at) <= NoCheat.Const.SkillMaxSampleGapSeconds then
                local changes = {}
                local totalDelta = 0
                local maxDelta = 0

                for perk, level in pairs(current) do
                    local oldLevel = previous.levels[perk]
                    if oldLevel ~= nil and tonumber(level) and tonumber(oldLevel) then
                        local delta = tonumber(level) - tonumber(oldLevel)
                        if delta > 0 then
                            totalDelta = totalDelta + delta
                            if delta > maxDelta then
                                maxDelta = delta
                            end
                            changes[#changes + 1] = NoCheat.safeText(perk, 60) .. ":" .. tostring(oldLevel) .. "->" .. tostring(level) .. "(+" .. tostring(delta) .. ")"
                        end
                    end
                end

                if maxDelta >= NoCheat.Const.SkillMinSingleDelta or totalDelta >= NoCheat.Const.SkillHighTotalDelta then
                    local severity = "warn"
                    local alert = false
                    if totalDelta >= NoCheat.Const.SkillHighTotalDelta or maxDelta >= NoCheat.Const.SkillHighSingleDelta then
                        severity = "high"
                        alert = true
                    end

                    emit(playerObj, "skill_level", "rapid_skill_level_increase", severity,
                        "Skill level increase detected between server samples.",
                        {
                            totalDelta = totalDelta,
                            maxDelta = maxDelta,
                            sampleSeconds = at - previous.at,
                            changes = table.concat(changes, ", "),
                            alert = alert
                        }
                    )
                    markSignalAndCorrelate(playerObj, "skill_level", "rapid_skill_level_increase", severity)
                end
            end

            NoCheatServer.SkillSnapshots[key] = {
                at = at,
                levels = current
            }
        end
    end
end

local function inspectTeleport()
    if not getOnlinePlayers then
        return
    end

    local players = getOnlinePlayers()
    if not players then
        return
    end

    local at = now()
    for i = 0, players:size() - 1 do
        local playerObj = players:get(i)
        if playerObj then
            local okX, x = pcall(function() return playerObj:getX() end)
            local okY, y = pcall(function() return playerObj:getY() end)
            local okZ, z = pcall(function() return playerObj:getZ() end)
            if okX and okY and x and y then
                local key = playerKey(playerObj)
                local current = {
                    at = at,
                    x = tonumber(x) or 0,
                    y = tonumber(y) or 0,
                    z = okZ and tonumber(z) or 0,
                    inVehicle = false
                }

                local okVehicle, vehicle = pcall(function()
                    if playerObj.getVehicle then
                        return playerObj:getVehicle()
                    end
                    return nil
                end)
                current.inVehicle = okVehicle and vehicle ~= nil

                local previous = NoCheatServer.PositionSnapshots[key]

                if previous
                    and (at - previous.at) <= NoCheat.Const.TeleportReconnectGraceSeconds
                    and previous.inVehicle ~= true
                    and current.inVehicle ~= true then
                    local elapsed = math.max(1, at - previous.at)
                    local distance = NoCheat.distance2d(previous.x, previous.y, current.x, current.y)
                    local staff = canUseTeleportPower(playerObj)
                    local warnDistance = NoCheat.Const.TeleportWarnDistance
                    local highDistance = NoCheat.Const.TeleportHighDistance
                    local shouldLog = false
                    local severity = "warn"
                    local alert = false
                    local kind = "fast_position_jump"

                    if staff and distance >= NoCheat.Const.TeleportStaffLogDistance then
                        shouldLog = true
                        kind = "staff_position_jump"
                        severity = "warn"
                    elseif distance >= highDistance then
                        shouldLog = true
                        severity = "high"
                        alert = true
                    elseif distance >= warnDistance then
                        shouldLog = true
                        severity = "warn"
                    end

                    if shouldLog then
                        local repeatKey = key .. ":" .. kind
                        local lastLogged = NoCheatServer.TeleportLastLogged[repeatKey] or 0
                        if (at - lastLogged) < NoCheat.Const.TeleportRepeatSeconds then
                            shouldLog = false
                        else
                            NoCheatServer.TeleportLastLogged[repeatKey] = at
                        end
                    end

                    if shouldLog then
                        emit(playerObj, "teleport", kind, severity,
                            "Large position delta detected by server sampling.",
                            {
                                fromPos = tostring(NoCheat.roundNumber(previous.x)) .. "," .. tostring(NoCheat.roundNumber(previous.y)) .. "," .. tostring(NoCheat.roundNumber(previous.z)),
                                toPos = tostring(NoCheat.roundNumber(current.x)) .. "," .. tostring(NoCheat.roundNumber(current.y)) .. "," .. tostring(NoCheat.roundNumber(current.z)),
                                distance = string.format("%.1f", distance),
                                sampleSeconds = elapsed,
                                inVehicle = NoCheat.boolText(false),
                                alert = alert
                            }
                        )
                        markSignalAndCorrelate(playerObj, "teleport", kind, severity)
                    end
                end

                NoCheatServer.PositionSnapshots[key] = current
            end
        end
    end
end

local function inspectClientIntegrity()
    if not getOnlinePlayers then
        return
    end
    local players = getOnlinePlayers()
    if not players then
        return
    end
    local at = now()
    for i = 0, players:size() - 1 do
        local playerObj = players:get(i)
        if playerObj then
            local key = playerKey(playerObj)
            local state = NoCheatServer.ClientIntegrity[key]
            if not state then
                state = { firstSeen = at }
                NoCheatServer.ClientIntegrity[key] = state
            end
            local referenceAt = state.lastSeen or state.firstSeen
            if referenceAt and (at - referenceAt) >= NoCheat.Const.ClientHeartbeatGraceSeconds then
                local lastLogged = state.missingLoggedAt or 0
                if (at - lastLogged) >= NoCheat.Const.ClientHeartbeatRepeatSeconds then
                    state.missingLoggedAt = at
                    if state.ready == true then
                        emit(playerObj, "system", "client_logger_heartbeat_missing", "high",
                            "Client logger was ready but stopped sending heartbeats.", {
                                secondsSinceHeartbeat = at - referenceAt,
                                clientReadySeen = "true",
                                serverObserved = "true",
                                serverConfirmed = "false",
                                alert = true
                            })
                    else
                        emit(playerObj, "system", "client_logger_not_ready", "warn",
                            "Client logger readiness or heartbeat was not observed within the grace period.", {
                                secondsSinceFirstSeen = at - referenceAt,
                                clientReadySeen = "false",
                                serverObserved = "true",
                                serverConfirmed = "false",
                                alert = false
                            })
                    end
                end
            end
        end
    end
end

local function onTick()
    if not NoCheat.isEnabled() then
        return
    end

    local at = now()
    if (at - NoCheatServer.LastTick.adminPower) >= NoCheat.Const.AdminPowerSampleSeconds then
        NoCheatServer.LastTick.adminPower = at
        inspectAdminPowers()
    end

    if (at - NoCheatServer.LastTick.skill) >= NoCheat.Const.SkillSampleSeconds then
        NoCheatServer.LastTick.skill = at
        inspectSkills()
    end

    if (at - NoCheatServer.LastTick.teleport) >= NoCheat.Const.TeleportSampleSeconds then
        NoCheatServer.LastTick.teleport = at
        inspectTeleport()
    end


    if (at - NoCheatServer.LastTick.integrity) >= 30 then
        NoCheatServer.LastTick.integrity = at
        inspectClientIntegrity()
    end
end

local function onDisconnect(playerObj)
    if not playerObj then
        return
    end
    local key = playerKey(playerObj)
    NoCheatServer.PositionSnapshots[key] = nil
    NoCheatServer.SkillSnapshots[key] = nil
    NoCheatServer.PowerSnapshots[key] = nil
    NoCheatServer.InsertEvents[key] = nil
    NoCheatServer.RecentSignals[key] = nil
    NoCheatServer.ClientIntegrity[key] = nil

    local prefix = key .. ":"
    local keyedBuckets = {
        NoCheatServer.ClientCooldowns,
        NoCheatServer.TeleportLastLogged,
        NoCheatServer.PowerLastTransitions,
        NoCheatServer.VehicleLastEvents
    }
    for i = 1, #keyedBuckets do
        for bucketKey, _ in pairs(keyedBuckets[i]) do
            if tostring(bucketKey):sub(1, #prefix) == prefix then
                keyedBuckets[i][bucketKey] = nil
            end
        end
    end

    for transitionKey, pending in pairs(NoCheatServer.PendingPowerReports) do
        if pending and pending.playerObj == playerObj then
            NoCheatServer.PendingPowerReports[transitionKey] = nil
        end
    end
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(onTick)
if Events.OnDisconnect then
    Events.OnDisconnect.Add(onDisconnect)
end

applySandboxConfig()
if NoCheat.isEnabled() then
    print("[NoCheat] Server logger 1.2.1 loaded. Logs: Zomboid/Lua/" .. NoCheat.Log.Root .. "/" .. dayText())
    emit(nil, "system", "mod_loaded", "info", "NoCheat server logger loaded.", {
        version = "1.2.1"
    })
end

