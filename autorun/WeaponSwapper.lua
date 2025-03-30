local version = "0.0.4"

-- Cached values
local sdk = sdk
local imgui = imgui
local os = os

-- Other required files
local config = require("WeaponSwapper.Config")
local bindings = require("WeaponSwapper.Bindings")
local utils = require("WeaponSwapper.Utils")

-- Cached values
local action_id_type = sdk.find_type_definition("ace.ACTION_ID")
local facilitymenu_types = utils.generate_enum("app.FacilityMenu.TYPE")

-- Variables related to swapping weapons
local swap_weapon = false
local forced_onto_back = false
local prepare_weapon = false
local current_weapon

local cooldown = 0.5
local last_swap_time = 0
local last_swap_control_time = 0

-- Variables for tracking the last actions performed by the player
local last_actions = {}
local last_action_index = 0
local max_actions = 5

--------------------------------------- Utilities ------------------------------------

-- Create a new ActionID object
-- @param category: The category of the action (0 = no weapon out, 1 = weapon out, 2 = weapon in action)
-- @param index: The index of the action (1 = weapon out, 14 =  idle, 15 = moving, 16 = stopping)
-- @return: A new ActionID object with the specified category and index
local function get_action_id(category, index)
    local action_id = ValueType.new(action_id_type)
    sdk.set_native_field(action_id, action_id_type, "_Category", category)
    sdk.set_native_field(action_id, action_id_type, "_Index", index)
    return action_id
end

-- Check if the player has a facility menu open
-- @return: true if a facility menu is open, false otherwise
local function has_facility_menu_open()
    local gui_manager = sdk.get_managed_singleton("app.GUIManager")
    for key, value in ipairs(facilitymenu_types) do
        if value > 0 and gui_manager:isActiveMenu(value) then
            return true
        end
    end
    return false
end

-- Request to swap the weapon
-- Ensure the player is in the game, has weapon handling available, is not in battle (unless a cheater), has no facility menu open, is not in a tent, and the cooldown has elapsed
-- If all conditions are met, toggle the swap_weapon flag
local function request_swap_weapon()
    if not utils.getMasterCharacter() then return end -- Player is not in the game
    if not utils.getMasterCharacter():get_WeaponHandling() then return end -- No weapon handling available
    if utils.is_in_battle() and not I_AM_A_CHEATER then return end -- In battle and not a cheater
    if has_facility_menu_open() then return end -- Facility menu is open
    if utils.getMasterCharacter():get_IsInAllTent() then return end -- Player is in a tent
    if os.clock() - last_swap_time < cooldown then return end -- Cooldown not yet elapsed

    swap_weapon = not swap_weapon
end

--------------------------------------- Config ------------------------------------
local I_AM_A_CHEATER = config.get("I am a Cheater") or false
config.set("I am a Cheater", I_AM_A_CHEATER)

local binding_config = config.get("swapkey")
if binding_config then
    -- Ensure hotkeys are numeric codes. If not, convert them to numeric codes
    if type(binding_config.hotkeys[1]) ~= "number" then
        local device = binding_config.device
        binding_config.hotkeys = utils.map(binding_config.hotkeys, function(hotkey)
            return bindings.get_code_from_name(device, hotkey)
        end)
        config.set("swapkey", binding_config)
    end

    -- Add the binding
    bindings.add(binding_config.device, binding_config.hotkeys, request_swap_weapon)
end

------------------------------------ Action Tracking ------------------------------------
-- This function is used to keep track of the last 5 actions performed by the player
-- Only every 3rd action seems to be valid so we track the last 5
-- @param action_id: The action ID of the action being performed
local function update_last_actions(action_id)
    last_action_index = (last_action_index % max_actions) + 1
    last_actions[last_action_index] = {
        category = action_id:get_field("_Category"),
        index = action_id:get_field("_Index"),
        type = action_id:get_field("_WeaponType")
    }
end

-- Check if the given action is being performed within the last 5 tracked action updates
-- @param category: The category of the action to check, if nil, ignore this check
-- @param index: The index of the action to check if nil, ignore this check
-- @return: true if the action is being performed, false otherwise
local function is_action_current(category, index)
    for i = 1, max_actions do
        local action = last_actions[i]
        if action and (category == nil or action.category == category) and (index == nil or action.index == index) then
            return true
        end
    end
    return false
end

-- Check if the weapon is doing something (category is not 0)
-- @return: true if the weapon is doing something, false otherwise
local function is_action_weapon_doing_something()
    for i = 1, max_actions do
        local action = last_actions[i]
        if action and action.category ~= 0 then
            return true
        end
    end
    return false
end

------------------------------------ REFramework ------------------------------------

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
    

-- Update Hook to swap the weapon
sdk.hook(sdk.find_type_definition("app.HunterCharacter"):get_method("update"), function(args)
    local hunter = sdk.to_managed_object(args[2])

    -- Skip unnecessary logic if conditions are not met
    if not hunter or not hunter:get_type_definition():is_a("app.HunterCharacter") then return end
    if not hunter:get_IsMaster() then return end
    local base_action_controller = hunter:get_BaseActionController()
    if not base_action_controller or base_action_controller:get_CurrentAction() == nil then return end

    -- Update the last actions performed by the player
    update_last_actions(base_action_controller:get_CurrentActionID())

    -- If weapon was just swapped and forced onto back, pull it back out
    if not swap_weapon and forced_onto_back and os.clock() - last_swap_control_time > 0.05 then
        hunter:changeActionRequest(0, get_action_id(1, 0), false)

        -- Wait until the weapon is pulled back out
        if is_action_current(1, 0) then
            forced_onto_back = false
            prepare_weapon = true
        end
    end

    -- If the weapon needs to be prepared
    if prepare_weapon and os.clock() - last_swap_control_time > 0.1 then
        prepare_weapon = false

        local weapon_type = hunter:get_WeaponType()

        -- Initialize the kinsect if the weapon is the Insect Glaive
        if weapon_type == 10 then
            hunter:get_Wp10Insect():doStart()
        end
    end

    -- If the swap_weapon flag is set, change the weapon
    if swap_weapon then

        -- Check if the weapon is in hand
        local is_weapon_in_hand = hunter:checkWeaponOn()

        if is_weapon_in_hand then

            -- Force the weapon onto the back
            hunter:get_SubActionController():endActionRequest()
            hunter:changeActionRequest(0, get_action_id(0, 1), false)

            forced_onto_back = true
            last_swap_control_time = os.clock()
            return sdk.PreHookResult.CALL_ORIGINAL

        elseif not is_weapon_in_hand and os.clock() - last_swap_control_time > 0.01 then
            
            -- Make sure the weapon swaps
            if not current_weapon then
                current_weapon = hunter:get_Weapon()
            end

            -- Swap the weapons
            hunter:changeWeaponFromReserve(true)

            -- If the weapon is now different
            if hunter:get_Weapon() ~= current_weapon then
                current_weapon = nil
                swap_weapon = false
                last_swap_time = os.clock()
                last_swap_control_time = os.clock()

                -- If the weapon wasn't forced on the back, prepare the weapon right away
                if not forced_onto_back then
                    prepare_weapon = true
                end
            end
        end
    end
end, function(retval)
end)
