local controller_bindings = {}
local keyboard_bindings = {}
local bindings = {}

-- How long to wait between checking the current input
bindings.delay = 0.1

-- Just helper variables to make device numbers easier
local CONTROLLER = 1
local KEYBOARD = 2
local PLAYSTATION = 1
local XBOX = 2

local function generate_enum(typename)
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

-- Generate the enums for the bindings

-- ======= Listeners ==========
local listeners = {}

-- ========== Example usage ============
-- local listen = bindings.listener.create("hotkey")

-- listen.on_complete(function()
--     print("Complete")
-- end)

-- if imgui.button("Listen") then
--     listen.start()
-- end

local listener = {}

-- Create a new listener
function listener.create(id)
    local self = {}
    self.id = id
    self.listening = false
    self.device = 0
    self.inputs = {}
    self.complete = function() end

    setmetatable(self, {
        __index = listener
    })

    if not listeners[id] then
        listeners[id] = self
        return self
    else
        return listeners[id]
    end
end

-- Start the listener
function listener.start()
    listener.listening = true
    listener.inputs = {}
end

-- Stop the listener
function listener.stop()
    listener.listening = false
end

-- Clear the listener's inputs
function listener.clear()
    listener.inputs = {}
end

-- Check if the listener is listening
function listener.is_listening()
    return listener.listening
end

-- Call back when listener is complete
function listener.on_complete(callback)
    listener.complete = callback
end

-- Get the inputs
function listener.get_inputs()
    return listener.inputs
end

function listener.get_device()
    return listener.device
end

-- Update the listener
function listener.update()

    if not listener.listening then
        return
    end

    local current = bindings.get_current()
    if not current then return end

    if #current > 0 then
        listener.inputs = current
        listener.device = bindings.get_current_device()

    elseif #current == 0 and listener.inputs and #listener.inputs > 0 then
        listener.listening = false
        listener.complete()
    end
end

bindings.listeners = listeners
bindings.listener = listener

-- ======= Keyboard Manager ==========
local keyboard_enum = generate_enum("via.hid.KeyboardKey")
local native_keyboard = sdk.get_native_singleton("via.hid.Keyboard")
local type_keyboard = sdk.find_type_definition("via.hid.Keyboard")

keyboard_bindings.current = {}
keyboard_bindings.current_last_check = nil
keyboard_bindings.previous = {}

keyboard_bindings.bindings = {}

-- Check if the keyboard is currently in use
function keyboard_bindings.is_currently_in_use()
    return #keyboard_bindings.get_current() > 0
end

-- Get the previous keys
function keyboard_bindings.get_previous()
    return keyboard_bindings.previous
end

-- Get the current keys in an array with the names
--- Will return the current_table table if not enough time has passed since the last check
function keyboard_bindings.get_current()

    local keyboard = sdk.call_native_func(native_keyboard, type_keyboard, "get_Device")

    -- Cache the keys for the delay - allows for easier setting/reading of binds
    if keyboard_bindings.current ~= nil and keyboard_bindings.current_last_check ~= nil and
        keyboard_bindings.current_last_check + bindings.delay > os.clock() then
        return keyboard_bindings.current
    end

    local current = {}
    for key_name, key_code in pairs(keyboard_enum) do
        if keyboard:isDown(key_code) then
            table.insert(current, key_name)
        end
    end

    keyboard_bindings.current = current
    keyboard_bindings.current_last_check = os.clock()
    return current
end

-- Return true or false depending on if the items in the passed table were just triggered
function keyboard_bindings.is_triggered(data)

    local current = keyboard_bindings.get_current()
    local previous = keyboard_bindings.get_previous()

    -- Check if in current all keys are pressed, and in previous either none or all but one
    local matches = 0
    local previous_matches = 0
    for _, name in pairs(data) do
        for _, current_name in pairs(current) do
            if current_name == name then
                matches = matches + 1
            end
        end
        for _, previous_name in pairs(previous) do
            if previous_name == name then
                previous_matches = previous_matches + 1
            end
        end
    end

    -- If not all current keys match the trigger
    if matches ~= #data then return false end

    -- If no previous keys were found
    if #keyboard_bindings.previous == 0 then return true end

    -- Previous has less matches than the current
    return previous_matches < #data
end

-- Return true or false depending on if the items in the passed table are currently pressed
function keyboard_bindings.is_down(data)
    local current = bindings.get_current()
    for _, name in pairs(data) do
        local found = false
        for _, current_name in pairs(current) do
            if current_name == name then
                found = true
            end
        end
        if not found then return false end
    end
    return true
end

-- ======= Controller ==========
local controller_enum = generate_enum("via.hid.GamePadButton")

local controller_types = generate_enum("via.hid.DeviceKindDetails")
local controller_type = 0

local native_controller = sdk.get_native_singleton("via.hid.GamePad")
local type_controller = sdk.find_type_definition("via.hid.GamePad")

controller_bindings.current = {}
controller_bindings.current_last_check = nil
controller_bindings.previous = {}

controller_bindings.bindings = {}

-- Buttons to ignore, can't remove from enum as the code would be wrong then
local ignore_buttons = {"Cancel", "Decide"}

-- Button names to replace [DefaultName] = {"Playstation", "Xbox"}
local to_replace_buttons = {
    ["RRight"] = {"Circle", "B"},
    ["RDown"] = {"X", "A"},
    ["RLeft"] = {"Square", "X"},
    ["RUp"] = {"Triangle", "Y"},
    ["CLeft"] = {"Share", "Back"},
    ["CRight"] = {"Start", "Start"},
    ["CCenter"] = {"Touchpad", "Guide"},
    ["LTrigBottom"] = {"L2", "LT"},
    ["RTrigBottom"] = {"R2", "RT"},
    ["LTrigTop"] = {"L1", "LB"},
    ["RTrigTop"] = {"R1", "RB"},
    ["LStickPush"] = {"L3", "LS"},
    ["RStickPush"] = {"R3", "RS"}
}

-- Get the controller type
local function get_controller_type()
    if controller_type ~= 0 then return controller_type end

    local manager = sdk.get_managed_singleton("ace.PadManager")
    local controller = manager:get_MainPad()
    local type_id = controller:get_DeviceKindDetails()
    local type = {}
    for name, id in pairs(controller_types) do
        if id == type_id then
            type = {
                name = name,
                id = type_id
            }
            break
        end
    end

    if string.find(type.name, "Dual") then
        controller_type = PLAYSTATION
    elseif string.find(type.name, "Xbox") then
        controller_type = XBOX
    else
        controller_type = 0
    end
    return controller_type
end

-- Replace controller_enum keys with the first value from to_replace
for key, values in pairs(to_replace_buttons) do
    if values[get_controller_type()] ~= nil then
        controller_enum[values[get_controller_type()]] = controller_enum[key]
        controller_enum[key] = nil
    end
end

-- Check if the controller is currently in use
function controller_bindings.is_currently_in_use()
    return #controller_bindings.get_current() > 0
end

-- Get the previous buttons
function controller_bindings.get_previous()
    return controller_bindings.previous
end

-- This function will return an array of {name, code} for each button
local function get_button_names(code)
    local init_code = code

    -- If the code is a single btn
    local btns = {}
    while code > 0 do
        local largest = {
            code = 0
        }

        for btn_name, btn_code in pairs(controller_enum) do
            if btn_code <= code and btn_code > largest.code then
                largest = {
                    name = btn_name,
                    code = btn_code
                }
            end
        end

        -- If we couldn't find a bigger code, then we must have all the possible ones
        if largest.code == 0 then break end

        -- Remove the largest and add it to the list of btns as long as it's not in the ignore list
        code = code - largest.code
        local ignore = false
        for _, ignore_name in pairs(ignore_buttons) do
            if largest.name == ignore_name then
                ignore = true
            end
        end
        if not ignore then table.insert(btns, largest.name) end
    end
    if #btns > 0 then
        return btns
    elseif code ~= 0 and code ~= -1 then
        table.insert(btns, "Unknown")
        return btns
    else
        return btns
    end
end

-- Get current buttons pressed as code
function controller_bindings.get_current()

    local controller = sdk.call_native_func(native_controller, type_controller, "get_MergedDevice")

    -- Cache the buttons for the delay - allows for easier setting/reading of binds
    if controller_bindings.current ~= nil and controller_bindings.current_last_check ~= nil and
        controller_bindings.current_last_check + bindings.delay > os.clock() then
        return controller_bindings.current
    end

    local current_code = controller:get_Button()

    if current_code == 0 then current_code = -1 end

    local current = get_button_names(current_code)

    controller_bindings.current = current
    controller_bindings.current_last_check = os.clock()
    return current
end

-- Return true or false depending on if the items in the passed table were just triggered
function controller_bindings.is_triggered(data)
    local current = controller_bindings.get_current()
    local previous = controller_bindings.get_previous()

    -- Check if in current all keys are pressed, and in previous either none or all but one
    local matches = 0
    local previous_matches = 0
    for _, name in pairs(data) do
        for _, current_name in pairs(current) do
            if current_name == name then
                matches = matches + 1
            end
        end
        for _, previous_name in pairs(previous) do
            if previous_name == name then
                previous_matches = previous_matches + 1
            end
        end
    end

    -- If not all current keys match the trigger
    if matches ~= #data then return false end

    -- If no previous keys were found
    if #controller_bindings.get_previous() == 0 then return true end

    -- Previous has less matches than the current
    return previous_matches < #data
end

-- =========================================

-- Add the keyboard bindings
function bindings.add_keyboard(keys, callback)
    local data = {
        input = keys,
        callback = callback
    }
    table.insert(keyboard_bindings.bindings, data)
end

-- Add the controller bindings
function bindings.add_controller(buttons, callback)
    local data = {
        input = buttons,
        callback = callback
    }
    table.insert(controller_bindings.bindings, data)
end

-- Add the bindings depending on the device
--- Device 1 = Controller
--- Device 2 = Keyboard
function bindings.add(device, input, callback)
    if tonumber(device) == CONTROLLER then
        bindings.add_controller(input, callback)
    elseif tonumber(device) == KEYBOARD then
        bindings.add_keyboard(input, callback)
    end
end

-- Remove the keyboard binding
function bindings.remove_keyboard(keys)
    for i, data in pairs(keyboard_bindings.bindings) do
        if data.input == keys then
            table.remove(keyboard_bindings.bindings, i)
        end
    end
end

-- Remove the controller binding
function bindings.remove_controller(buttons)
    for i, data in pairs(controller_bindings.bindings) do
        if data.input == buttons then
            table.remove(controller_bindings.bindings, i)
        end
    end
end

-- Remove the bindings depending on the device
--- Device 1 = Controller
--- Device 2 = Keyboard
function bindings.remove(device, input)
    if device == CONTROLLER then
        bindings.remove_controller(input)
    elseif device == KEYBOARD then
        bindings.remove_keyboard(input)
    end
end

-- Check if the device is a keyboard
function bindings.is_keyboard()
    return keyboard_bindings.is_currently_in_use()
end

-- Check if the device is a controller
function bindings.is_controller()
    return controller_bindings.is_currently_in_use()
end

-- Get the current device type
--- 0 = None
--- 1 = Controller
--- 2 = Keyboard
function bindings.get_current_device()
    if bindings.is_keyboard() then return KEYBOARD end
    if bindings.is_controller() then return CONTROLLER end
    return 0
end

-- Get the current bindings
function bindings.get_current()
    if bindings.is_keyboard() then
        return keyboard_bindings.get_current()
    end
    if bindings.is_controller() then
        return controller_bindings.get_current()
    end
    return {}
end

-- Get the callback for the keyboard input
function bindings.get_keyboard_callback(input)
    for _, data in pairs(keyboard_bindings.bindings) do
        if data.input == input then
            return data.data
        end
    end
    return nil
end

-- Get the callback for the controller input
function bindings.get_controller_callback(input)
    for _, data in pairs(controller_bindings.bindings) do
        if data.input == input then
            return data.data
        end
    end
    return nil
end

-- Get the callback for the input
function bindings.get_callback(device, input)
    if device == CONTROLLER then
        return bindings.get_controller_callback(input)
    elseif device == KEYBOARD then
        return bindings.get_keyboard_callback(input)
    end
end

-- Update the bindings and run the callback if the input is triggered
function bindings.update()
    if bindings.is_keyboard() then
        for _, data in pairs(keyboard_bindings.bindings) do
            if keyboard_bindings.is_triggered(data.input) then
                data.callback()
            end
        end
    end

    if bindings.is_controller() then
        for _, data in pairs(controller_bindings.bindings) do
            if controller_bindings.is_triggered(data.input) then
                data.callback()
            end
        end
    end

    for _, listener in pairs(bindings.listeners) do
        listener.update()
    end

    -- Update previous data
    controller_bindings.previous = controller_bindings.get_current()
    keyboard_bindings.previous = keyboard_bindings.get_current()
end

return bindings