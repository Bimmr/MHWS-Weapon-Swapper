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

return utils