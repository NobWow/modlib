local schema = getfenv(1)

function new(def)
    -- TODO type inference, sanity checking etc.
    return setmetatable(def, {__index = schema})
end

local function field_name_to_title(name)
    local title = modlib.text.split(name, "_")
    title[1] = modlib.text.upper_first(title[1])
    return table.concat(title, " ")
end

function generate_settingtypes(self)
    local type = self.type
    local settingtype, type_args
    self.title = self.title or field_name_to_title(self.name)
    self._level = self._level or 0
    local default = self.default
    if type == "boolean" then
        settingtype = "bool"
        default = default and "true" or "false"
    elseif type == "string" then
        settingtype = "string"
    elseif type == "number" then
        settingtype = self.int and "int" or "float"
        if self.min or self.max then
            -- TODO handle exclusive min/max
            type_args = (self.int and "%d %d" or "%f %f"):format(self.min or (2 ^ -30), self.max or (2 ^ 30))
        end
    elseif type == "table" then
        local handled = {}
        local settings = {"[" .. table.concat(modlib.table.repetition("*", self._level)) .. self.name .. "]"}
        local function setting(key, value_scheme)
            if handled[key] then
                return
            end
            handled[key] = true
            assert(not key:find("[=%.%s]"))
            value_scheme.name = self.name .. "." .. key
            value_scheme.title = value_scheme.title or self.title .. " " .. field_name_to_title(key)
            value_scheme._level = self._level + 1
            table.insert(settings, generate_settingtypes(value_scheme))
        end
        local keys = {}
        for key in pairs(self.entries or {}) do
            table.insert(keys, key)
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            setting(key, self.entries[key])
        end
        return table.concat(settings, "\n")
    end
    if not type then
        return ""
    end
    local description = self.description
    -- TODO extend description by range etc.?
    -- TODO enum etc. support
    if description then
        if type(description) ~= "table" then
            description = {description}
        end
        description = "# " .. table.concat(description, "\n# ") .. "\n"
    else
        description = ""
    end
    return description .. self.name .. " (" .. self.title  .. ") " .. settingtype .. " " .. (default or "") .. (type_args and (" " .. type_args) or "")
end

function generate_markdown(self)
    -- TODO address redundancies
    local typ = self.type
    self.title = self.title or field_name_to_title(self._md_name)
    self._level = self._level or 1
    if typ == "table" then
        local handled = {}
        local settings = {}
        local function setting(key, value_scheme)
            if handled[key] then
                return
            end
            handled[key] = true
            value_scheme._md_name = key
            value_scheme.title = value_scheme.title or self.title .. " " .. field_name_to_title(key)
            value_scheme._level = self._level + 1
            table.insert(settings, table.concat(modlib.table.repetition("#", self._level)) .. " `" .. key .. "`")
            table.insert(settings, generate_markdown(value_scheme))
            table.insert(settings, "")
        end
        local keys = {}
        for key in pairs(self.entries or {}) do
            table.insert(keys, key)
        end
        table.sort(keys)
        for _, key in ipairs(keys) do
            setting(key, self.entries[key])
        end
        return table.concat(settings, "\n")
    end
    if not typ then
        return ""
    end
    local lines = {}
    local function line(text)
        table.insert(lines, "* " .. text)
    end
    local description = self.description
    if description then
        modlib.table.append(lines, type(description) == "table" and description or {description})
    end
    table.insert(lines, "")
    line("Type: " .. self.type)
    if self.default ~= nil then
        line("Default: `" .. tostring(self.default) .. "`")
    end
    if self.int then
        line"Integer"
    elseif self.list then
        line"List"
    end
    if self.infinity then
        line"Infinities allowed"
    end
    if self.nan then
        line"Not-a-Number (NaN) allowed"
    end
    if self.range then
        if self.range.min then
            line("> " .. self.range.min)
        elseif self.range.min_exclusive then
            line(">= " .. self.range.min_exclusive)
        end
        if self.range.max then
            line("< " .. self.range.max)
        elseif self.range.max_exclusive then
            line("<= " .. self.range.max_exclusive)
        end
    end
    if self.values then
        line("Possible values:")
        for value in pairs(self.values) do
            table.insert(lines, "  * " .. value)
        end
    end
    return table.concat(lines, "\n")
end

function settingtypes(self)
    self.settingtypes = self.settingtypes or generate_settingtypes(self)
    return self.settingtypes
end

function load(self, override, params)
    local converted
    if params.convert_strings and type(override) == "string" then
        converted = true
        if self.type == "boolean" then
            if override == "true" then
                override = true
            elseif override == "false" then
                override = false
            end
        elseif self.type == "number" then
            override = tonumber(override)
        else
            converted = false
        end
    end
    if override == nil and not converted then
        if self.default ~= nil then
            return self.default
        elseif self.type == "table" then
            override = {}
        end
    end
    local _error = error
    local function format_error(type, ...)
        if type == "type" then
            return "mismatched type: expected " .. self.type ..", got " .. type(override) .. (converted and " (converted)" or "")
        end
        if type == "range" then
            local conditions = {}
            local function push(condition, bound)
                if self.range[bound] then
                    table.insert(conditions, " " .. condition .. " " .. minetest.write_json(self.range[bound]))
                end
            end
            push(">", "min_exclusive")
            push(">=", "min")
            push("<", "max_exclusive")
            push("<=", "max")
            return "out of range: expected value " .. table.concat(conditions, "and")
        end
        if type == "int" then
            return "expected integer"
        end
        if type == "infinity" then
            return "expected no infinity"
        end
        if type == "nan" then
            return "expected no nan"
        end
        if type == "required" then
            local key = ...
            return "required field " .. minetest.write_json(key) .. " missing"
        end
        if type == "additional" then
            local key = ...
            return "superfluous field " .. minetest.write_json(key)
        end
        if type == "list" then
            return "not a list"
        end
        if type == "values" then
            return "expected one of " .. minetest.write_json(modlib.table.keys(self.values)) .. ", got " .. minetest.write_json(override)
        end
        _error("unknown error type")
    end
    local function error(type, ...)
        if params.error_message then
            local formatted = format_error(type, ...)
            settingtypes(self)
            _error("Invalid value: " .. self.name .. ": " .. formatted)
        end
        _error{
            type = type,
            self = self,
            override = override,
            converted = converted
        }
    end
    local function assert(value, ...)
        if not value then
            error(...)
        end
        return value
    end
    assert(self.type == type(override), "type")
    if self.type == "number" or self.type == "string" then
        if self.range then
            if self.range.min then
                assert(self.range.min <= override, "range")
            elseif self.range.min_exclusive then
                assert(self.range.min_exclusive < override, "range")
            end
            if self.range.max then
                assert(self.range.max >= override, "range")
            elseif self.range.max_exclusive then
                assert(self.range.max_exclusive > override, "range")
            end
        end
        if self.type == "number" then
            assert((not self.int) or (override % 1 == 0), "int")
            assert(self.infinity or math.abs(override) ~= math.huge, "infinity")
            assert(self.nan or override == override, "nan")
        end
    elseif self.type == "table" then
        if self.entries then
            for key, schema in pairs(self.entries) do
                if schema.required and override[key] == nil then
                    error("required", key)
                end
                override[key] = load(schema, override[key], params)
            end
            if self.additional == false then
                for key in pairs(override) do
                    if self.entries[key] == nil then
                        error("additional", key)
                    end
                end
            end
        end
        if self.keys then
            for key, value in pairs(override) do
                override[load(self.keys, key, params)], override[key] = value, nil
            end
        end
        if self.values then
            for key, value in pairs(override) do
                override[key] = load(self.values, value, params)
            end
        end
        assert((not self.list) or modlib.table.count(override) == #override, "list")
    else
        assert((not self.values) or self.values[override], "values")
    end
    if self.func then self.func(override) end
    return override
end