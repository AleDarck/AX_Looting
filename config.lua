Config = {}

-- ============================================================
--  CONFIGURACION GENERAL
-- ============================================================

Config.DrawDistance        = 3.0          -- distancia maxima para interactuar con el cadaver (metros)
Config.SearchCooldown      = 0.5          -- segundos de espera entre deteccion de cuerpos
Config.LootedRespawnTime   = 300          -- segundos antes de que un cadaver looteado pueda volver a ser looteado (solo en memoria)

Config.ProgressBar = {
    duration = 4000,
    label    = 'Buscando...',
    animDict = 'missheistdockssetup1clipboard@base',
    anim     = 'base',
    flags    = 49,
}

Config.CardRevealDelay = 180  -- milisegundos entre aparicion de cada card en la UI

-- ============================================================
--  IMAGENES DEL INVENTARIO (ox_inventory)
-- ============================================================

Config.InventoryImagePath = 'nui://ox_inventory/web/images/'  -- ruta base para imagenes

-- ============================================================
--  TIPOS DE LOOT
--  fixedLoots      => siempre se otorgan al lootear
--  probabilityLoots => se eligen aleatoriamente segun probabilidad
--    loop    = cuantas veces se recorre la tabla de items
--    items   = lista de posibles drops
--      names       = lista de items posibles (se elige uno al azar del grupo)
--      minValue    = cantidad minima
--      maxValue    = cantidad maxima
--      probability = probabilidad en % (la suma NO puede superar 100)
-- ============================================================

Config.Types = {

    -- -------------------------------------------------------
    --  ZOMBIES
    -- -------------------------------------------------------
    ['zombie_default'] = {
        fixedLoots = {},
        probabilityLoots = {
            loop = 5,
            items = {
                { names = { 'card_id', 'bank_card', 'iphone', 'samsungphone', 'tablet', 'battery' },  minValue = 1, maxValue = 2, probability = 20 },
                { names = { 'card_bank', 'driver_license', 'laptop', 'phone', 'gps' },               minValue = 1, maxValue = 2, probability = 20 },
                { names = { 'tela' },                                                                   minValue = 1, maxValue = 3, probability = 10 },
                { names = { 'map' },                                                                    minValue = 1, maxValue = 1, probability = 1  },
                { names = { 'money' },                                                                  minValue = 5, maxValue = 50, probability = 15 },
            }
        },
    },

    ['zombie_boss'] = {
        fixedLoots = {
            { name = 'bandage', count = 1 },
        },
        probabilityLoots = {
            loop = 4,
            items = {
                { names = { 'bpminismg', 'bpsnspistol' },                  minValue = 1, maxValue = 1, probability = 10  },
                { names = { 'ammo-9', 'ammo-rifle', 'ammo-shotgun' },       minValue = 10, maxValue = 30, probability = 40 },
                { names = { 'money' },                                       minValue = 50, maxValue = 200, probability = 25 },
                { names = { 'bandage', 'medkit' },                           minValue = 1, maxValue = 2, probability = 25 },
            }
        },
    },

    -- -------------------------------------------------------
    --  ANIMALES
    -- -------------------------------------------------------
    ['animal_default'] = {
        fixedLoots = {},
        probabilityLoots = {
            loop = 2,
            items = {
                { names = { 'cuero_crudo', 'bonefragments' },  minValue = 1, maxValue = 2, probability = 35 },
                { names = { 'retales_de_cuero', 'fatanimal' }, minValue = 1, maxValue = 3, probability = 20 },
            }
        },
    },

    ['pig_loot'] = {
        fixedLoots = {
            { name = 'bearmeat', count = 1 },
        },
        probabilityLoots = {
            loop = 1,
            items = {
                { names = { 'cuero_crudo' }, minValue = 1, maxValue = 2, probability = 50 },
                { names = { 'fatanimal' },   minValue = 1, maxValue = 2, probability = 30 },
            }
        },
    },

    ['dog_loot'] = {
        fixedLoots = {
            { name = 'wolfmeat', count = 1 },
        },
        probabilityLoots = {
            loop = 1,
            items = {
                { names = { 'bonefragments' }, minValue = 1, maxValue = 2, probability = 40 },
            }
        },
    },

    ['bird_loot'] = {
        fixedLoots = {
            { name = 'horsemeatcooked', count = 1 },
        },
    },

    ['deer_loot'] = {
        fixedLoots = {
            { name = 'dearmeatcooked', count = 1 },
        },
        probabilityLoots = {
            loop = 1,
            items = {
                { names = { 'cuero_crudo', 'bonefragments' }, minValue = 1, maxValue = 3, probability = 60 },
            }
        },
    },

    ['cow_loot'] = {
        fixedLoots = {
            { name = 'dearmeatcooked', count = 2 },
        },
        probabilityLoots = {
            loop = 1,
            items = {
                { names = { 'cuero_crudo' }, minValue = 2, maxValue = 4, probability = 70 },
            }
        },
    },

    ['rabbit_loot'] = {
        fixedLoots = {
            { name = 'horsemeatcooked', count = 1 },
        },
    },

    ['rat_loot'] = {
        fixedLoots = {
            { name = 'horsemeatcooked', count = 1 },
        },
    },
}

-- ============================================================
--  MAPEO MODEL => TIPO DE LOOT
--  Si el modelo del ped/animal no esta aqui se usara el tipo
--  'zombie_default' para peds y 'animal_default' para animales
-- ============================================================

Config.LootByModel = {
    -- Zombies especiales
    ['nc_zombie_a']   = 'zombie_boss',

    -- Animales
    ['a_c_boar']      = 'pig_loot',
    ['a_c_pig']       = 'pig_loot',
    ['a_c_cat_01']    = 'dog_loot',
    ['a_c_chickenhawk'] = 'bird_loot',
    ['a_c_crow']      = 'bird_loot',
    ['a_c_pigeon']    = 'bird_loot',
    ['a_c_hen']       = 'bird_loot',
    ['a_c_seagull']   = 'bird_loot',
    ['a_c_chop']      = 'dog_loot',
    ['a_c_shepherd']  = 'dog_loot',
    ['a_c_coyote']    = 'dog_loot',
    ['a_c_husky']     = 'dog_loot',
    ['a_c_poodle']    = 'dog_loot',
    ['a_c_pug']       = 'dog_loot',
    ['a_c_retriever'] = 'dog_loot',
    ['a_c_westy']     = 'dog_loot',
    ['a_c_rottweiler'] = 'dog_loot',
    ['a_c_cow']       = 'cow_loot',
    ['a_c_deer']      = 'deer_loot',
    ['a_c_mtlion']    = 'deer_loot',
    ['a_c_rabbit_01'] = 'rabbit_loot',
    ['a_c_rat']       = 'rat_loot',
}

-- ============================================================
--  MALETIN DE JUGADOR ABATIDO
-- ============================================================

Config.PlayerBag = {
    prop            = 'prop_cash_bag_01',
    despawnMinutes  = 5,          -- minutos hasta que desaparece si nadie lo recoge
    protectedItems  = {           -- items que NUNCA caen al maletin
        'map',
    },
}

for typeName, typeData in pairs(Config.Types) do
    if typeData.probabilityLoots and typeData.probabilityLoots.items then
        local total = 0
        for _, item in ipairs(typeData.probabilityLoots.items) do
            total = total + item.probability
        end
        if total > 100 then
            print(string.format('[^3AX_Looting^7] ADVERTENCIA: La suma de probabilidades en "%s" supera el 100%% (%d%%)', typeName, total))
        end
    end
end