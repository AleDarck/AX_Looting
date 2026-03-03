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
    local src    = source
    local player = ESX.GetPlayerFromId(src)
    if not player then return end

    local netIdStr = tostring(netId)
    local state    = bodyStates[netIdStr]

    -- Cuerpo ya vacio
    if state and state.isEmpty then
        TriggerClientEvent('AX_Looting:client:bodyEmpty', src)
        return
    end

    -- Cuerpo siendo looteado por otro jugador en este momento
    if state and state.inUseBy and state.inUseBy ~= src then
        TriggerClientEvent('AX_Looting:client:bodyInUse', src)
        return
    end

    -- Primera vez que se lootea: generar items
    if not state then
        local loot = generateLoot(lootType)
        if #loot == 0 then
            TriggerClientEvent('AX_Looting:client:noLoot', src)
            return
        end
        bodyStates[netIdStr] = {
            inUseBy = src,
            items   = loot,
            isEmpty = false,
        }
        TriggerClientEvent('AX_Looting:client:openLootUI', src, loot, netId)
        return
    end

    -- Cuerpo con items restantes y libre: bloquear y abrir
    state.inUseBy = src
    TriggerClientEvent('AX_Looting:client:openLootUI', src, state.items, netId)
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

local function isProtected(itemName)
    for _, v in ipairs(Config.PlayerBag.protectedItems) do
        if v == itemName then return true end
    end
    return false
end

RegisterNetEvent('esx:onPlayerDeath', function(data)
    local src    = source
    local player = ESX.GetPlayerFromId(src)
    if not player then return end

    local items = {}
    for _, item in ipairs(player.getInventory()) do
        local count = item.count or item.amount or 0
        if count > 0 and not isProtected(item.name) then
            table.insert(items, { name = item.name, count = count })
        end
    end

    local money = player.getMoney()
    if money > 0 then
        table.insert(items, { name = 'money', count = money })
    end

    if #items == 0 then return end

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
    }

    TriggerClientEvent('AX_Looting:client:spawnPlayerBag', -1, bagId, player.getName())

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

    local state = bagStates[bagId]
    if not state or state.isEmpty then
        TriggerClientEvent('AX_Looting:client:bodyEmpty', src)
        return
    end

    if state.inUseBy and state.inUseBy ~= src then
        TriggerClientEvent('AX_Looting:client:bodyInUse', src)
        return
    end

    state.inUseBy = src
    TriggerClientEvent('AX_Looting:client:openBagUI', src, state.items, bagId)
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