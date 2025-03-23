local version = "0.0.1"
local I_AM_A_CHEATER = false

local config = require("WeaponSwapper.Config")
local bindings = require("WeaponSwapper.Bindings")
local soundManager, battleMusicManager

local swap_weapon = false
local config_key = "swapkey"

local function is_in_battle()
    if soundManager == nil then
        soundManager = sdk.get_managed_singleton("app.SoundMusicManager")
    end
    if soundManager == nil then return false end
    if battleMusicManager == nil then
        battleMusicManager = soundManager:get_BattleMusic()
    end
    if battleMusicManager == nil then return false end
    if battleMusicManager:get_IsBattle() then return true end
    return false
end



-- Request to swap weapon
local function request_swap_weapon()
    swap_weapon = true
end

-- Load the binding from the config
local binding_config = config.get(config_key)

-- Add the binding to the bindings
if binding_config ~= nil then
    bindings.add(binding_config.device, binding_config.hotkeys, request_swap_weapon)
end

re.on_draw_ui(function()
    if imgui.collapsing_header("Weapon Swapper") then

        -- Create the binding listener
        local listen = bindings.listener.create("weaponswapper")

        -- On listener complete set the new hotkeys
        listen.on_complete(function()
            
            -- Remove the old binding
            if binding_config ~= nil then
                bindings.remove(binding_config.device, binding_config.hotkeys)
            end

            -- Set the new binding
            binding_config = {
                hotkeys = listen.get_inputs(),
                device = listen.get_device()
            }

            -- Add the new binding, and save it to the config
            bindings.add(binding_config.device, binding_config.hotkeys, request_swap_weapon)
            config.set(config_key, binding_config)
        end)


        -- Create the hotkey string
        local hotkey_string = ""

        if listen.is_listening() then

            -- If listening, and inputs have been started - display the hotkeys being pressed
            if #listen.get_inputs() ~= 0 then
                for i, input in ipairs(listen.get_inputs()) do
                    hotkey_string = hotkey_string .. input
                    hotkey_string = hotkey_string .. " + "
                end
            else
                -- If listening, but no inputs have been started - display listening
                hotkey_string = "Listening..."
            end

        -- If not listening, display the hotkeys from the config
        elseif binding_config == nil or binding_config.hotkeys == nil then
            hotkey_string = "Not Set"
        else
            for i, input in ipairs(binding_config.hotkeys) do
                hotkey_string = hotkey_string .. input
                if i < #binding_config.hotkeys then
                    hotkey_string = hotkey_string .. " + "
                end
            end
        end
        
        -- Display the hotkey string, and the change hotkey button
        imgui.push_id("WeaponSwapper")
        imgui.indent(2)

        imgui.begin_disabled()
        imgui.input_text("", hotkey_string)
        imgui.end_disabled()
        imgui.same_line()

        -- When the change hotkey button is pressed, start listening for a new hotkey
        if imgui.button("Change Hotkey") then
            listen.start()
        end

        imgui.spacing()
        imgui.unindent(2)

        imgui.pop_id()
    end
end)

-- Keybinds
re.on_frame(function()
    bindings.update()
end)

-- Hook the update function of the HunterCharacter
-- This will allow us to swap the weapon when the swap_weapon flag is set
sdk.hook(sdk.find_type_definition("app.HunterCharacter"):get_method("update"), function(args)
    local managed = sdk.to_managed_object(args[2])
    if not managed:get_type_definition():is_a("app.HunterCharacter") then return end
    if not managed:get_IsMaster() then return end

    -- If the swap_weapon flag is set, change the weapon
    if swap_weapon then

        if not is_in_battle() or I_AM_A_CHEATER then
            managed:changeWeaponFromReserve(true)
        end
        swap_weapon = false
    end
end, function(retval)
end)