local version = "0.0.2"

local config = require("WeaponSwapper.Config")
local bindings = require("WeaponSwapper.Bindings")
local utils = require("WeaponSwapper.Utils")

local action_id_type = sdk.find_type_definition("ace.ACTION_ID")

local swap_weapon = false
local I_AM_A_CHEATER = false

local last_swap_time = 0
local cooldown = 0.25

-- Load the binding from the config
local binding_config = config.get("swapkey")

-- Function to stop the current action
local function get_action_id(category, index)
    local action_id = ValueType.new(action_id_type)
    sdk.set_native_field(action_id, action_id_type, "_Category", category)
    sdk.set_native_field(action_id, action_id_type, "_Index", index)
    return action_id
end

-- Function to check if the player has a facility menu open
local function has_facility_menu_open()
    local gui_manager = sdk.get_managed_singleton("app.GUIManager")
    local facilitymenu_types = utils.generate_enum("app.FacilityMenu.TYPE")

    local has_facility_menu_open = false
    for key, value in pairs(facilitymenu_types) do
        if value > 0 then -- No point in checking INVALID
            if gui_manager:isActiveMenu(value) then
                return true
            end
        end
    end
    return false
end

-- Request to swap weapon
local function request_swap_weapon()
    if not utils.getMasterCharacter() then return end -- If the player is not in the game
    if utils.is_in_battle() and not I_AM_A_CHEATER then return end -- If the player is in battle, and not a cheater
    if has_facility_menu_open() then return end -- If the player has a facility menu open
    if os.clock() - last_swap_time < cooldown then return end -- If the player has swapped weapons too quickly

    swap_weapon = true
end

-- Load if you're a cheater (Allows weapon swaps inside of a battle)
I_AM_A_CHEATER = config.get("I am a Cheater")
if I_AM_A_CHEATER == nil then
    config.set("I am a Cheater", false)
end

-- Add the binding to the bindings
if binding_config ~= nil then

    ------------------------------------
    -- check if first element in hotkeys is a number, if it isn't then we need to convert them
    -- Remove this check in the future
    if type(binding_config.hotkeys[1]) ~= "number" then
        local hotkeys_codes = {}
        local device = binding_config.device
        for _, hotkey in ipairs(binding_config.hotkeys) do
            table.insert(hotkeys_codes, bindings.get_code_from_name(device, hotkey))
        end
        binding_config.hotkeys = hotkeys_codes
        config.set("swapkey", binding_config)
    end
    ------------------------------------

    bindings.add(binding_config.device, binding_config.hotkeys, request_swap_weapon)
end

-- On REFramework draw UI
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
            config.set("swapkey", binding_config)
        end)

        -- Create the hotkey string
        local hotkey_string = ""

        if listen.is_listening() then
            -- If listening, and inputs have been started - display the hotkeys being pressed
            if #listen.get_inputs() ~= 0 then
                local inputs = listen.get_inputs()
                inputs = bindings.get_names(listen.get_device(), inputs)
                for _, input in ipairs(inputs) do
                    hotkey_string = hotkey_string .. input.name .. " + "
                end
            else
                -- If listening, but no inputs have been started - display listening
                hotkey_string = "Listening..."
            end
            -- If not listening, display the hotkeys from the config
        elseif binding_config == nil or binding_config.hotkeys == nil then
            hotkey_string = "Not Set"
        else
            local inputs = bindings.get_names(binding_config.device, binding_config.hotkeys)
            for i, input in ipairs(inputs) do
                hotkey_string = hotkey_string .. input.name
                if i < #inputs then
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
        if imgui.is_item_hovered() then
            imgui.set_tooltip("  " .. "Supports both keyboard and controller." .. "  ")
        end

        imgui.spacing()
        imgui.unindent(2)
        imgui.pop_id()
    end
end)

-- On REFramework update
re.on_frame(function()
    -- Update the bindings
    bindings.update()
end)

local skip_movement_end = false
-- Hook the update function of the HunterCharacter
-- This will allow us to swap the weapon when the swap_weapon flag is set
sdk.hook(sdk.find_type_definition("app.HunterCharacter"):get_method("lateUpdate"), function(args)
    local managed = sdk.to_managed_object(args[2])
    if not managed:get_type_definition():is_a("app.HunterCharacter") then return end
    if not managed:get_IsMaster() then return end

    -- If the swap_weapon flag is set, change the weapon
    if swap_weapon then

        -- Get current action
        local action_manager = managed:get_BaseActionController()
        local current_action_id = action_manager:get_CurrentActionID()
        local weapon_on_back = current_action_id:get_field("_Category") == 0

        local function swap_weapon_action()
            managed:changeWeaponFromReserve(true) -- Swap the weapon
            swap_weapon = false
            last_swap_time = os.clock()
        end

        if weapon_on_back then
            print("Swapped weapon on back")
            swap_weapon_action()
        else
            print("Swapped weapon in hand")

            -- End any possible sub-actions (e.g., shooting a bow)
            managed:get_SubActionController():endActionRequest()

            -- Change the action to pulling out the weapon
            managed:changeActionRequest(0, get_action_id(1, 0), false)

            swap_weapon_action()
        end

    end
end, function(retval)
end)

