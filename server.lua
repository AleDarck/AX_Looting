-- ============================================================
--  AX_Looting - server.lua
--  Framework: New ESX 1.13.4 | oxmysql | lua54
-- ============================================================

local ESX = exports['es_extended']:getSharedObject()

-- ============================================================
--  ESTADO DE CUERPOS
--
--  bodyStates[netIdStr] = {
--    inUseBy = playerId | nil   => quien lo esta looteando ahora
--    items   = { {name,count} } => items que quedan en el cuerpo
--    isEmpty = bool             => si ya no quedan items
--  }
-- ============================================================

local bodyStates = {}

-- ============================================================
--  ESTADO DE PROPS (cooldown global en memoria)
--
--  propStates[propKey] = {
--    lastLooted = os.time()   => timestamp del ultimo saqueo
--    items      = { ... }     => loot generado (persiste durante el cooldown)
--  }
--  propKey = "modelName_x_y_z" redondeado a 1 decimal
-- ============================================================

local propStates = {}

local function getPropKey(modelName, x, y, z)
    return string.format('%s_%.1f_%.1f_%.1f', modelName, x, y, z)
end

-- ============================================================
--  FUNCION: Generar loot segun Config.Types
-- ============================================================

local function generateLoot(lootType)
    local typeData = Config.Types[lootType]
    if not typeData then return {} end

    local result = {}

    if typeData.fixedLoots then
        for _, lootItem in ipairs(typeData.fixedLoots) do
            table.insert(result, { name = lootItem.name, count = lootItem.count })
        end
    end

    if typeData.probabilityLoots and typeData.probabilityLoots.items then
        local loopCount = typeData.probabilityLoots.loop or 1

        for _ = 1, loopCount do
            local roll       = math.random(1, 100)
            local cumulative = 0
            local chosen     = nil

            for _, itemGroup in ipairs(typeData.probabilityLoots.items) do
                cumulative = cumulative + itemGroup.probability
                if roll <= cumulative then
                    chosen = itemGroup
                    break
                end
            end

            if chosen then
                local name  = chosen.names[math.random(1, #chosen.names)]
                local count = math.random(chosen.minValue, chosen.maxValue)
                local found = false
                for _, existing in ipairs(result) do
                    if existing.name == name then
                        existing.count = existing.count + count
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(result, { name = name, count = count })
                end
            end
        end
    end

    return result
end

local function enrichWithLabels(items)
    local enriched = {}
    for _, item in ipairs(items) do
        local label = item.name
        local oxItem = exports['ox_inventory']:Items(item.name)
        if oxItem and oxItem.label then
            label = oxItem.label
        end
        table.insert(enriched, { name = item.name, count = item.count, label = label })
    end
    return enriched
end

-- ============================================================
--  HELPER: liberar bloqueo de un cuerpo
-- ============================================================

local function releaseBody(netIdStr, src)
    local state = bodyStates[netIdStr]
    if not state then return end
    if state.inUseBy == src then
        state.inUseBy = nil
    end
end

-- Limpiar bloqueos cuando un jugador se desconecta
AddEventHandler('playerDropped', function()
    local src = source
    for _, state in pairs(bodyStates) do
        if state.inUseBy == src then
            state.inUseBy = nil
        end
    end
end)

-- ============================================================
--  EVENTO: Pedir loot de un cuerpo
-- ============================================================

RegisterNetEvent('AX_Looting:server:requestLoot', function(netId, lootType)
    local src      = source
    local player   = ESX.GetPlayerFromId(src)
    if not player then return end

    local netIdStr = tostring(netId)
    local state    = bodyStates[netIdStr]

    if state and state.isEmpty then
        TriggerClientEvent('AX_Looting:client:bodyEmpty', src)
        return
    end

    -- Si lleva mas de 30 segundos bloqueado, liberarlo automaticamente
    if state and state.inUseBy and state.inUseBy ~= src then
        local now = os.time()
        if state.lockedAt and (now - state.lockedAt) > 30 then
            state.inUseBy  = nil
            state.lockedAt = nil
        else
            TriggerClientEvent('AX_Looting:client:bodyInUse', src)
            return
        end
    end

    if not state then
        local loot = generateLoot(lootType)
        if #loot == 0 then
            TriggerClientEvent('AX_Looting:client:noLoot', src)
            return
        end
        bodyStates[netIdStr] = {
            inUseBy  = src,
            lockedAt = os.time(),
            items    = loot,
            isEmpty  = false,
        }
        TriggerClientEvent('AX_Looting:client:openLootUI', src, enrichWithLabels(loot), netId)
        return
    end

    state.inUseBy  = src
    state.lockedAt = os.time()
    TriggerClientEvent('AX_Looting:client:openLootUI', src, enrichWithLabels(state.items), netId)
end)

-- ============================================================
--  EVENTO: Jugador cerro la UI (libera el bloqueo del cuerpo)
-- ============================================================

RegisterNetEvent('AX_Looting:server:leaveBody', function(netId)
    local src = source
    releaseBody(tostring(netId), src)
end)

-- ============================================================
--  EVENTO: Recoger un item individual
-- ============================================================

RegisterNetEvent('AX_Looting:server:collectItem', function(netId, itemName, itemCount)
    local src    = source
    local player = ESX.GetPlayerFromId(src)
    if not player then return end

    local netIdStr = tostring(netId)
    local state    = bodyStates[netIdStr]
    if not state or state.isEmpty then return end

    -- Sanitizar
    itemName  = tostring(itemName):lower():gsub('[^%a%d_%-]', '')
    itemCount = math.floor(tonumber(itemCount) or 1)
    if itemCount <= 0 or itemName == '' then return end

    -- Verificar que el item existe en el estado del servidor y eliminar
    local found = false
    for i, item in ipairs(state.items) do
        if item.name == itemName and item.count == itemCount then
            table.remove(state.items, i)
            found = true
            break
        end
    end
    if not found then return end

    -- Dar al jugador
    if itemName == 'money' then
        player.addMoney(itemCount)
        TriggerClientEvent('esx:showNotification', src, 'Recogiste $' .. itemCount)
    else
        player.addInventoryItem(itemName, itemCount)
        TriggerClientEvent('esx:showNotification', src, 'Recogiste ' .. itemCount .. 'x ' .. itemName)
    end

    -- Si el cuerpo quedo vacio, marcarlo y pedir al cliente que borre el ped
    if #state.items == 0 then
        state.isEmpty = true
        state.inUseBy = nil
        TriggerClientEvent('AX_Looting:client:deletePed', src, netId)
    end
end)

-- ============================================================
--  EVENTO: Recoger todos los items
-- ============================================================

RegisterNetEvent('AX_Looting:server:collectAll', function(netId, items)
    local src    = source
    local player = ESX.GetPlayerFromId(src)
    if not player then return end

    local netIdStr = tostring(netId)
    local state    = bodyStates[netIdStr]
    if not state or state.isEmpty then return end

    if type(items) ~= 'table' or #items > 30 then return end

    -- Validar que no se envian mas items de los que hay en el servidor
    if #items > #state.items then return end

    for _, item in ipairs(items) do
        if type(item) == 'table' and item.name and item.count then
            local name  = tostring(item.name):lower():gsub('[^%a%d_%-]', '')
            local count = math.floor(tonumber(item.count) or 1)
            if count > 0 and name ~= '' then
                if name == 'money' then
                    player.addMoney(count)
                else
                    player.addInventoryItem(name, count)
                end
            end
        end
    end

    -- Marcar cuerpo como vacio
    state.items   = {}
    state.isEmpty = true
    state.inUseBy = nil

    TriggerClientEvent('esx:showNotification', src, 'Recogiste todos los items')
    TriggerClientEvent('AX_Looting:client:deletePed', src, netId)
end)

-- ============================================================
--  MALETIN DE JUGADOR ABATIDO
-- ============================================================

local bagStates  = {}
local bagCounter = 0

local function sendDiscordLog(title, color, fields)
    if not Config.DiscordWebhook or Config.DiscordWebhook == 'TU_WEBHOOK_AQUI' then return end

    local embeds = {{
        title       = title,
        color       = color,
        fields      = fields,
        footer      = { text = 'AX_Looting • ' .. os.date('%d/%m/%Y %H:%M:%S') },
    }}

    PerformHttpRequest(Config.DiscordWebhook, function() end, 'POST',
        json.encode({ username = 'AX Looting', embeds = embeds }),
        { ['Content-Type'] = 'application/json' }
    )
end

local function isProtected(itemName)
    for _, v in ipairs(Config.PlayerBag.protectedItems) do
        if v == itemName then return true end
    end
    return false
end

-- ============================================================
--  EVENTO: Pedir loot de un prop
-- ============================================================

RegisterNetEvent('AX_Looting:server:requestPropLoot', function(lootType, x, y, z, modelName)
    local src    = source
    local player = ESX.GetPlayerFromId(src)
    if not player then return end

    -- Validar lootType
    if not Config.Types[lootType] then return end

    local propKey = getPropKey(modelName, x, y, z)
    local now     = os.time()
    local state   = propStates[propKey]

    -- Verificar cooldown global
    if state and state.lastLooted then
        local elapsed = now - state.lastLooted
        if elapsed < Config.PropLoot.cooldown then
            TriggerClientEvent('AX_Looting:client:propOnCooldown', src, Config.PropLoot.cooldown - elapsed)
            return
        end
    end

    -- Generar loot fresco (cooldown expirado o primer saqueo)
    local loot = generateLoot(lootType)
    if #loot == 0 then
        TriggerClientEvent('AX_Looting:client:noLoot', src)
        return
    end

    propStates[propKey] = {
        lastLooted = now,
        items      = loot,
        inUseBy    = src,
    }

    TriggerClientEvent('AX_Looting:client:openPropLootUI', src, enrichWithLabels(loot), propKey)
end)

-- ============================================================
--  EVENTO: Recoger item individual de prop
--  (el cliente manda activeNetId = "prop_<propKey>")
-- ============================================================

RegisterNetEvent('AX_Looting:server:collectPropItem', function(propKey, itemName, itemCount)
    local src    = source
    local player = ESX.GetPlayerFromId(src)
    if not player then return end

    local state = propStates[propKey]
    if not state then return end

    itemName  = tostring(itemName):lower():gsub('[^%a%d_%-]', '')
    itemCount = math.floor(tonumber(itemCount) or 1)
    if itemCount <= 0 or itemName == '' then return end

    local found = false
    for i, item in ipairs(state.items) do
        if item.name == itemName and item.count == itemCount then
            table.remove(state.items, i)
            found = true
            break
        end
    end
    if not found then return end

    if itemName == 'money' then
        player.addMoney(itemCount)
        TriggerClientEvent('esx:showNotification', src, 'Recogiste $' .. itemCount)
    else
        player.addInventoryItem(itemName, itemCount)
        TriggerClientEvent('esx:showNotification', src, 'Recogiste ' .. itemCount .. 'x ' .. itemName)
    end
end)

-- ============================================================
--  EVENTO: Recoger todos los items de prop
-- ============================================================

RegisterNetEvent('AX_Looting:server:collectAllProp', function(propKey, items)
    local src    = source
    local player = ESX.GetPlayerFromId(src)
    if not player then return end

    local state = propStates[propKey]
    if not state then return end
    if type(items) ~= 'table' or #items > 30 then return end
    if #items > #state.items then return end

    for _, item in ipairs(items) do
        if type(item) == 'table' and item.name and item.count then
            local name  = tostring(item.name):lower():gsub('[^%a%d_%-]', '')
            local count = math.floor(tonumber(item.count) or 1)
            if count > 0 and name ~= '' then
                if name == 'money' then
                    player.addMoney(count)
                else
                    player.addInventoryItem(name, count)
                end
            end
        end
    end

    state.items = {}
    TriggerClientEvent('esx:showNotification', src, 'Recogiste todos los items')
    TriggerClientEvent('AX_Looting:client:closePropUI', src)  -- <-- línea nueva
end)

RegisterNetEvent('esx:onPlayerDeath', function(data)
    local src    = source
    local player = ESX.GetPlayerFromId(src)
    if not player then return end

    local identifier = player.identifier

    -- Leer inventario directamente desde la base de datos
    local result = MySQL.query.await('SELECT inventory FROM users WHERE identifier = ?', { identifier })
    if not result or not result[1] then return end

    local dbInventory = json.decode(result[1].inventory) or {}
    local items = {}

    for _, item in ipairs(dbInventory) do
        local count = item.count or item.amount or 0
        if count > 0 and not isProtected(item.name) and item.name ~= 'money' then
            table.insert(items, { name = item.name, count = count })
        end
    end

    local money = player.getMoney()
    if money > 0 then
        table.insert(items, { name = 'money', count = money })
    end

    if #items == 0 then return end

    -- Remover items del jugador
    for _, item in ipairs(items) do
        if item.name == 'money' then
            player.removeMoney(item.count)
        else
            player.removeInventoryItem(item.name, item.count)
        end
    end

    bagCounter = bagCounter + 1
    local bagId = 'bag_' .. bagCounter

    bagStates[bagId] = {
        inUseBy = nil,
        items   = items,
        isEmpty = false,
        ownerId = src,
    }

    -- Log Discord
    local itemsList = ''
    for _, item in ipairs(items) do
        itemsList = itemsList .. '• ' .. item.name .. ' x' .. item.count .. '\n'
    end
    sendDiscordLog('💀 Maletín creado por muerte', 15548997, {
        { name = '👤 Jugador abatido', value = player.getName() .. ' (' .. identifier .. ')', inline = true  },
        { name = '🆔 ID Servidor',     value = tostring(src),                                  inline = true  },
        { name = '💼 ID Maletín',      value = bagId,                                          inline = true  },
        { name = '📦 Contenido',       value = itemsList ~= '' and itemsList or 'Vacío',       inline = false },
    })

    TriggerClientEvent('AX_Looting:client:spawnPlayerBag', -1, bagId, player.getName(), src)

    SetTimeout(Config.PlayerBag.despawnMinutes * 60 * 1000, function()
        if bagStates[bagId] and not bagStates[bagId].isEmpty then
            bagStates[bagId] = nil
            TriggerClientEvent('AX_Looting:client:removeBag', -1, bagId)
        end
    end)
end)

RegisterNetEvent('AX_Looting:server:requestBagLoot', function(bagId)
    local src    = source
    local player = ESX.GetPlayerFromId(src)
    if not player then return end

    local state  = bagStates[bagId]
    local isDead = Player(src).state.isDead or false

    if state and state.ownerId == src and isDead then
        TriggerClientEvent('esx:showNotification', src, 'No puedes registrar tu propio maletin mientras estas abatido')
        return
    end

    if not state or state.isEmpty then
        TriggerClientEvent('AX_Looting:client:bodyEmpty', src)
        return
    end

    if state.inUseBy and state.inUseBy ~= src then
        TriggerClientEvent('AX_Looting:client:bodyInUse', src)
        return
    end

    state.inUseBy = src
    TriggerClientEvent('AX_Looting:client:openBagUI', src, enrichWithLabels(state.items), bagId)
end)

RegisterNetEvent('AX_Looting:server:leaveBag', function(bagId)
    local src   = source
    local state = bagStates[bagId]
    if state and state.inUseBy == src then
        state.inUseBy = nil
    end
end)

RegisterNetEvent('AX_Looting:server:collectBagItem', function(bagId, itemName, itemCount)
    local src    = source
    local player = ESX.GetPlayerFromId(src)
    if not player then return end

    local state = bagStates[bagId]
    if not state or state.isEmpty then return end

    itemName  = tostring(itemName):lower():gsub('[^%a%d_%-]', '')
    itemCount = math.floor(tonumber(itemCount) or 1)
    if itemCount <= 0 or itemName == '' then return end

    local found = false
    for i, item in ipairs(state.items) do
        if item.name == itemName and item.count == itemCount then
            table.remove(state.items, i)
            found = true
            break
        end
    end
    if not found then return end

    if itemName == 'money' then
        player.addMoney(itemCount)
        TriggerClientEvent('esx:showNotification', src, 'Recogiste $' .. itemCount)
    else
        player.addInventoryItem(itemName, itemCount)
        TriggerClientEvent('esx:showNotification', src, 'Recogiste ' .. itemCount .. 'x ' .. itemName)
    end

    -- Log Discord
    sendDiscordLog('🎒 Item recogido del maletín', 3447003, {
        { name = '👤 Jugador',           value = player.getName() .. ' (' .. player.identifier .. ')', inline = true  },
        { name = '🆔 ID Servidor',       value = tostring(src),                                         inline = true  },
        { name = '💼 Maletín',           value = tostring(bagId),                                       inline = true  },
        { name = '📦 Item',              value = itemName,                                               inline = true  },
        { name = '🔢 Cantidad',          value = tostring(itemCount),                                    inline = true  },
        { name = '👻 Dueño del maletín', value = tostring(state.ownerId),                               inline = true  },
    })

    if #state.items == 0 then
        state.isEmpty = true
        state.inUseBy = nil
        TriggerClientEvent('AX_Looting:client:deleteBag', -1, bagId)
    end
end)

RegisterNetEvent('AX_Looting:server:collectAllBag', function(bagId, items)
    local src    = source
    local player = ESX.GetPlayerFromId(src)
    if not player then return end

    local state = bagStates[bagId]
    if not state or state.isEmpty then return end
    if type(items) ~= 'table' or #items > 50 then return end
    if #items > #state.items then return end

    -- Log antes de vaciar
    local itemsList = ''
    for _, item in ipairs(state.items) do
        itemsList = itemsList .. '• ' .. item.name .. ' x' .. item.count .. '\n'
    end
    sendDiscordLog('🎒 Maletín vaciado completo', 15158332, {
        { name = '👤 Jugador',           value = player.getName() .. ' (' .. player.identifier .. ')', inline = true  },
        { name = '🆔 ID Servidor',       value = tostring(src),                                         inline = true  },
        { name = '💼 Maletín',           value = tostring(bagId),                                       inline = true  },
        { name = '👻 Dueño del maletín', value = tostring(state.ownerId),                               inline = true  },
        { name = '📦 Items recogidos',   value = itemsList ~= '' and itemsList or 'Ninguno',            inline = false },
    })

    for _, item in ipairs(items) do
        if type(item) == 'table' and item.name and item.count then
            local name  = tostring(item.name):lower():gsub('[^%a%d_%-]', '')
            local count = math.floor(tonumber(item.count) or 1)
            if count > 0 and name ~= '' then
                if name == 'money' then
                    player.addMoney(count)
                else
                    player.addInventoryItem(name, count)
                end
            end
        end
    end

    state.items   = {}
    state.isEmpty = true
    state.inUseBy = nil

    TriggerClientEvent('esx:showNotification', src, 'Recogiste todos los items')
    TriggerClientEvent('AX_Looting:client:deleteBag', -1, bagId)
end)

RegisterNetEvent('AX_Looting:server:pickupBag', function(bagId)
    local src    = source
    local state  = bagStates[bagId]
    local isDead = Player(src).state.isDead or false

    if state and state.ownerId == src and isDead then
        TriggerClientEvent('esx:showNotification', src, 'No puedes tomar tu maletin mientras estas abatido')
        return
    end

    if state then
        state.carriedBy = src

        local player = ESX.GetPlayerFromId(src)
        if player then
            sendDiscordLog('🏃 Maletín recogido y cargado', 10181046, {
                { name = '👤 Jugador',     value = player.getName() .. ' (' .. player.identifier .. ')', inline = true },
                { name = '🆔 ID Servidor', value = tostring(src),                                         inline = true },
                { name = '💼 ID Maletín',  value = tostring(bagId),                                       inline = true },
                { name = '👻 Dueño',       value = tostring(state.ownerId),                               inline = true },
            })
        end
    end
end)

RegisterNetEvent('AX_Looting:server:dropBag', function(bagId)
    local state = bagStates[bagId]
    if state then state.carriedBy = nil end
end)