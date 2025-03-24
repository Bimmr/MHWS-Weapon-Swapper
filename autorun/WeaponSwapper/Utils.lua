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
    player = player:get_Character()
    return player
end


-- Check if the player is in battle
function utils.is_in_battle()
    if battle_music_manager == nil then
        battle_music_manager = sound_manager:get_BattleMusic()
    end
    if battle_music_manager == nil then return false end
    return battle_music_manager:get_IsBattle()
end

-- Generate an enum from a type name
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

return utils