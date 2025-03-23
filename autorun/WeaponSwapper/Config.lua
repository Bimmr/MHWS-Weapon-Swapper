local configPath = "WeaponSwapper/Config.json"
local config = {}


-- Split a string into an array
local function split(text, delim)
    -- returns an array of fields based on text and delimiter (one character only)
    local result = {}
    local magic = "().%+-*?[]^$"

    if delim == nil then
        delim = "%s"
    elseif string.find(delim, magic, 1, true) then
        delim = "%" .. delim
    end

    local pattern = "[^" .. delim .. "]+"
    for w in string.gmatch(text, pattern) do table.insert(result, w) end
    return result
end


-- Get the config file - return config as JSON or nil if not found
function config.get_config()
    if json ~= nil then return json.load_file(configPath) end
    return nil
end

-- Set a single key and value into the config
-- If a key with a . is given, it will update it in the section
function config.set(key, value)
    local current_config = config.get_config() or {}
    if string.find(key, ".") == nil then
        current_config[key] = value
    else
        local keys = split(key, ".")
        local config_section = current_config
        for i = 1, #keys do
            if i == #keys then
                config_section[keys[i]] = value
            else
                if config_section[keys[i]] == nil then config_section[keys[i]] = {} end
                config_section = config_section[keys[i]]
            end
        end
    end
    json.dump_file(configPath, current_config)
end

-- Get a single value from the config from the provided key
-- If a key with a . is given, it will return the value from the section
function config.get(key)
    local current_config = config.get_config()
    if current_config == nil then return nil end
    if string.find(key, ".") == nil then
        return current_config[key]
    else
        local keys = split(key, ".")
        local value = current_config
        for i = 1, #keys do
            value = value[keys[i]]
            if value == nil then return nil end
        end
        return value
    end
end

return config
