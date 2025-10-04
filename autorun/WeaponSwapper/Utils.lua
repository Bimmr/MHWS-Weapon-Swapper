local utils = {}

local sound_manager = sdk.get_managed_singleton("app.SoundMusicManager")

local player_manager
local battle_music_manager

-- Get the Master Player
function utils.getMasterPlayerInfo()
    if not player_manager then
        player_manager = sdk.get_managed_singleton("app.PlayerManager")
    end
    local player = player_manager:getMasterPlayerInfo()
    return player
end

-- Get the Master Chacter from the player info
function utils.getMasterCharacter()
    local player = utils.getMasterPlayerInfo()
    if not player then return nil end
    player = player:get_Character()
    return player
end


-- Check if the player is in battle
function utils.is_in_battle()
    local character = utils.getMasterCharacter()
    if not character then return false end
    return character:get_IsCombat()
end

-- Generate an enum from a type name
-- @param typename: The name of the type to generate the enum from
-- @return: A table containing the enum values
function utils.generate_enum(typename)
    local t = sdk.find_type_definition(typename)
    if not t then return {} end
    local fields = t:get_fields()
    local enum = {}
    for i, field in ipairs(fields) do
        if field:is_static() then
            local name = field:get_name()
            local raw_value = field:get_data(nil)
            enum[name] = raw_value
        end
    end
    return enum
end

-- Applies a function to each element in a table and returns a new table with the results
-- @param tbl: The input table
-- @param func: The function to apply to each element
-- @return: A new table with the transformed elements
function utils.map(tbl, func)
    local result = {}
    for i, v in ipairs(tbl) do
        result[i] = func(v)
    end
    return result
end

return utils