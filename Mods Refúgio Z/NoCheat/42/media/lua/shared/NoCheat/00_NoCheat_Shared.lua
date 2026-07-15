NoCheat = NoCheat or {}

NoCheat.Net = {
    Module = "nocheat",
    ReportCommand = "report"
}

NoCheat.Log = {
    Root = "NoCheatLogs",
    AlertFile = "alerts",
    Categories = {
        alerts = true,
        insert = true,
        ether = true,
        godmode = true,
        admin_power = true,
        skill_level = true,
        teleport = true,
        item_spawn = true,
        vehicle_repair = true,
        system = true
    }
}

NoCheat.Const = {
    InsertKeyCode = 210,
    InsertCooldownSeconds = 10,
    InsertWindowSeconds = 300,
    InsertWarnCount = 3,
    InsertCorrelationSeconds = 600,
    EtherMenuKeyCode = 59,
    EtherMenuKeyCooldownSeconds = 10,

    ClientHeartbeatSeconds = 60,
    ClientHeartbeatGraceSeconds = 180,
    ClientHeartbeatRepeatSeconds = 600,

    AvoidDamageSampleSeconds = 1,
    AvoidDamageConsecutiveSamples = 3,

    SkillSampleSeconds = 60,
    SkillMaxSampleGapSeconds = 300,
    SkillMinSingleDelta = 2,
    SkillHighSingleDelta = 4,
    SkillHighTotalDelta = 6,

    TeleportSampleSeconds = 20,
    TeleportWarnDistance = 180,
    TeleportHighDistance = 500,
    TeleportStaffLogDistance = 75,
    TeleportReconnectGraceSeconds = 60,
    TeleportRepeatSeconds = 60,

    AdminPowerSampleSeconds = 10,
    AdminPowerClientFallbackSeconds = 15,

    ClientReportCooldownSeconds = 2,
    ClientReportMaxText = 220
}

NoCheat.ClientKinds = {
    insert_pressed = true,
    ether_detected = true,
    ether_panel_open = true,
    ether_globals_detected = true,
    ether_api_detected = true,
    ether_menu_key_pressed = true,
    avoid_damage_persistent = true,
    client_ready = true,
    client_heartbeat = true,
    admin_power_toggle = true,
    admin_item_spawn = true,
    admin_teleport_ui = true,
    vehicle_cheat = true
}

NoCheat.AdminPowerSpecs = {
    Invisible = {
        getter = "isInvisible",
        capability = "ToggleInvisibleHimself",
        category = "admin_power"
    },
    GodMod = {
        getter = "isGodMod",
        capability = "ToggleGodModHimself",
        category = "godmode",
        alertWhenAuthorized = true
    },
    NoClip = {
        getter = "isNoClip",
        capability = "ToggleNoclipHimself",
        category = "admin_power",
        alertWhenAuthorized = true
    },
    GhostMode = {
        getter = "isGhostMode",
        category = "admin_power",
        alertWhenAuthorized = true
    },
    Invincible = {
        getter = "isInvincible",
        category = "godmode",
        alertWhenAuthorized = true
    },
    FastMove = {
        getter = "isFastMoveCheat",
        capability = "UseFastMoveCheat",
        category = "admin_power",
        alertWhenAuthorized = true
    },
    TimedActionInstant = {
        getter = "isTimedActionInstantCheat",
        capability = "UseTimedActionInstantCheat",
        category = "admin_power"
    },
    UnlimitedCarry = {
        getter = "isUnlimitedCarry",
        capability = "ToggleUnlimitedCarry",
        category = "admin_power"
    },
    UnlimitedEndurance = {
        getter = "isUnlimitedEndurance",
        capability = "ToggleUnlimitedEndurance",
        category = "admin_power"
    },
    UnlimitedAmmo = {
        getter = "isUnlimitedAmmo",
        capability = "ToggleUnlimitedAmmo",
        category = "admin_power"
    },
    KnowAllRecipes = {
        getter = "isKnowAllRecipes",
        capability = "ToggleKnowAllRecipes",
        category = "admin_power"
    },
    BuildCheat = {
        getter = "isBuildCheat",
        capability = "UseBuildCheat",
        category = "admin_power"
    },
    FarmingCheat = {
        getter = "isFarmingCheat",
        capability = "UseFarmingCheat",
        category = "admin_power"
    },
    FishingCheat = {
        getter = "isFishingCheat",
        capability = "UseFishingCheat",
        category = "admin_power"
    },
    HealthCheat = {
        getter = "isHealthCheat",
        capability = "UseHealthCheat",
        category = "admin_power"
    },
    MechanicsCheat = {
        getter = "isMechanicsCheat",
        capability = "UseMechanicsCheat",
        category = "vehicle_repair",
        alertWhenAuthorized = true
    },
    MoveableCheat = {
        getter = "isMovablesCheat",
        capability = "UseMovablesCheat",
        category = "admin_power"
    },
    CanSeeAll = {
        getter = "canSeeAll",
        capability = "CanSeeAll",
        category = "admin_power"
    },
    CanHearAll = {
        getter = "canHearAll",
        capability = "CanHearAll",
        category = "admin_power"
    },
    ZombiesDontAttack = {
        getter = "isZombiesDontAttack",
        capability = "ManipulateZombie",
        category = "admin_power"
    },
    BrushTool = {
        getter = "isCanUseBrushTool",
        capability = "UseBrushToolManager",
        category = "admin_power"
    },
    LootZed = {
        getter = "canUseLootZed",
        capability = "UseLootZed",
        category = "admin_power"
    },
    LootLog = {
        getter = "canUseLootLog",
        capability = "UseLootLog",
        category = "admin_power"
    },
    AnimalCheat = {
        getter = "isAnimalCheat",
        capability = "AnimalCheats",
        category = "admin_power"
    },
    AnimalExtraValues = {
        getter = "isAnimalExtraValuesCheat",
        capability = "AnimalCheats",
        category = "admin_power"
    }
}

NoCheat.AdminPowers = {}
for power, _ in pairs(NoCheat.AdminPowerSpecs) do
    NoCheat.AdminPowers[power] = true
end

NoCheat.VehicleActions = {
    repair_vehicle = true,
    repair_part = true,
    set_part_condition = true,
    set_content_amount = true,
    set_rust = true,
    spawn_vehicle = true,
    remove_vehicle = true,
    hotwire = true,
    get_key = true,
    mechanics_cheat_toggle = true
}

function NoCheat.safeText(value, maxLen)
    local text = tostring(value or "")
    text = text:gsub("[\r\n\t]", " ")
    text = text:gsub("%s+", " ")
    text = text:gsub("[%[%]]", "")
    maxLen = maxLen or NoCheat.Const.ClientReportMaxText
    if #text > maxLen then
        text = text:sub(1, maxLen)
    end
    return text
end

function NoCheat.safeFilePart(value, maxLen)
    local text = NoCheat.safeText(value, maxLen or 64)
    text = text:gsub("[/\\:*?\"<>|]", "_")
    text = text:gsub("%s+", "_")
    if text == "" then
        text = "unknown"
    end
    return text
end

function NoCheat.boolText(value)
    if value == true or tostring(value) == "true" then
        return "true"
    end
    return "false"
end

function NoCheat.joinParts(parts, separator)
    local out = {}
    for i = 1, #parts do
        if parts[i] ~= nil and tostring(parts[i]) ~= "" then
            out[#out + 1] = tostring(parts[i])
        end
    end
    return table.concat(out, separator or " ")
end

function NoCheat.roundNumber(value)
    local number = tonumber(value)
    if number == nil then
        return 0
    end
    if number >= 0 then
        return math.floor(number + 0.5)
    end
    return math.ceil(number - 0.5)
end

function NoCheat.getPositionText(playerObj)
    if not playerObj then
        return "unknown"
    end
    local okX, x = pcall(function() return playerObj:getX() end)
    local okY, y = pcall(function() return playerObj:getY() end)
    local okZ, z = pcall(function() return playerObj:getZ() end)
    if not okX or not okY then
        return "unknown"
    end
    return tostring(NoCheat.roundNumber(x)) .. "," .. tostring(NoCheat.roundNumber(y)) .. "," .. tostring(NoCheat.roundNumber(okZ and z or 0))
end

function NoCheat.distance2d(x1, y1, x2, y2)
    local dx = tonumber(x2 or 0) - tonumber(x1 or 0)
    local dy = tonumber(y2 or 0) - tonumber(y1 or 0)
    return math.sqrt((dx * dx) + (dy * dy))
end

function NoCheat.categoryOrSystem(category)
    category = tostring(category or "system")
    if NoCheat.Log.Categories[category] then
        return category
    end
    return "system"
end

function NoCheat.isEnabled()
    if SandboxVars and SandboxVars.NoCheat then
        local enabled = SandboxVars.NoCheat.Enabled
        if enabled == false or tostring(enabled) == "false" then
            return false
        end
    end
    return true
end

