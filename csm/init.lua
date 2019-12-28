--
-- SSCSM: Server-Sent Client-Side Mods proof-of-concept
--
-- Copyright © 2019 by luk3yx
--

-- For debugging, this can be a global variable.
local sscsm = {}

-- Load the Env class
-- Mostly copied from https://stackoverflow.com/a/26367080
-- Don't copy metatables
local function copy(obj, s)
    if s and s[obj] ~= nil then return s[obj] end
    if type(obj) ~= 'table' then return obj end
    s = s or {}
    local res = {}
    s[obj] = res
    for k, v in pairs(obj) do res[copy(k, s)] = copy(v, s) end
    return res
end

-- Safe functions
local Env = {}
local safe_funcs = {}

-- No getmetatable()
if rawget(_G, 'getmetatable') then
    safe_funcs[getmetatable] = function() end
end

-- Get the current value of string.rep in case other CSMs decide to break
do
    local rep = string.rep
    safe_funcs[string.rep] = function(str, n)
        if #str * n > 1048576 then
            error('string.rep: string length overflow', 2)
        end
        return rep(str, n)
    end

    local show_formspec = minetest.show_formspec
    safe_funcs[show_formspec] = function(formname, ...)
        if type(formname) == 'string' and formname:sub(1, 6) ~= 'sscsm:' then
            return show_formspec(formname, ...)
        end
    end

    local after = minetest.after
    safe_funcs[after] = function(n, ...)
        if type(n) == 'number' then return after(n, pcall, ...) end
    end

    local on_fs_input = minetest.register_on_formspec_input
    safe_funcs[on_fs_input] = function(func)
        on_fs_input(function(formname, fields)
            if formname:sub(1, 6) ~= 'sscsm:' then
                pcall(func, formname, copy(fields))
            end
        end)
    end

    local deserialize = minetest.deserialize
    safe_funcs[deserialize] = function(str)
        return deserialize(str, true)
    end

    local wrap = function(n)
        local orig = minetest[n] or minetest[n .. 's']
        if type(orig) == 'function' then
            return function(func)
                orig(function(...)
                    local r = {pcall(func, ...)}
                    if r[1] then
                        table.remove(r, 1)
                        return (table.unpack or unpack)(r)
                    else
                        minetest.log('error', '[SSCSM] ' .. tostring(r[2]))
                    end
                end)
            end
        end
    end

    for _, k in ipairs({'register_globalstep', 'register_on_death',
            'register_on_hp_modification', 'register_on_damage_taken',
            'register_on_dignode', 'register_on_punchnode',
            'register_on_placenode', 'register_on_item_use',
            'register_on_modchannel_message', 'register_on_modchannel_signal',
            'register_on_inventory_open', 'register_on_sending_chat_message',
            'register_on_receiving_chat_message'}) do
        safe_funcs[minetest[k]] = wrap(k)
    end
end

-- Environment
function Env.new_empty()
    local self = {_raw = {}, _seen = copy(safe_funcs)}
    self._raw['_G'] = self._raw
    return setmetatable(self, {__index = Env}) or self
end
function Env:get(k) return self._raw[self._seen[k] or k] end
function Env:set(k, v) self._raw[copy(k, self._seen)] = copy(v, self._seen) end
function Env:set_copy(k, v)
    self:set(k, v)
    self._seen[k] = nil
    self._seen[v] = nil
end
function Env:add_globals(...)
    for i = 1, select('#', ...) do
        local var = select(i, ...)
        self:set(var, _G[var])
    end
end
function Env:update(data) for k, v in pairs(data) do self:set(k, v) end end
function Env:del(k)
    if self._seen[k] then
        self._raw[self._seen[k]] = nil
        self._seen[k] = nil
    end
    self._raw[k] = nil
end

function Env:copy()
    local new = {_seen = copy(safe_funcs)}
    new._raw = copy(self._raw, new._seen)
    return setmetatable(new, {__index = Env}) or new
end

-- Load code into a callable function.
function Env:loadstring(code)
    if code:byte(1) == 27 then return nil, 'Invalid code!' end
    local f, msg = loadstring(code)
    if not f then return nil, msg end
    setfenv(f, self._raw)
    return function(...)
        local good, msg = pcall(f, ...)
        if good then
            return msg
        else
            minetest.log('error', '[SSCSM] ' .. tostring(msg))
        end
    end
end

function Env:exec(code)
    local f, msg = self:loadstring(code)
    if not f then
        minetest.log('error', '[SSCSM] Syntax error: ' .. tostring(msg))
        return false
    end
    f()
    return true
end

-- Create the "base" environment
local base_env = Env:new_empty()
function Env.new() return base_env:copy() end

-- Clone everything
base_env:add_globals('assert', 'dump', 'dump2', 'error', 'ipairs', 'math',
    'next', 'pairs', 'pcall', 'select', 'setmetatable', 'string', 'table',
    'tonumber', 'tostring', 'type', 'vector', 'xpcall', '_VERSION')

base_env:set_copy('os', {clock = os.clock, difftime = os.difftime,
    time = os.time})

-- Create a slightly locked down "minetest" table
do
    local t = {}
    for _, k in ipairs({"add_particle", "add_particlespawner", "after",
            "camera", "clear_out_chat_queue", "colorize", "compress", "debug",
            "decode_base64", "decompress", "delete_particlespawner",
            "deserialize", "disconnect", "display_chat_message",
            "encode_base64", "explode_scrollbar_event", "explode_table_event",
            "explode_textlist_event", "find_node_near", "formspec_escape",
            "get_background_escape_sequence", "get_color_escape_sequence",
            "get_day_count", "get_item_def", "get_language", "get_meta",
            "get_node_def", "get_node_level", "get_node_max_level",
            "get_node_or_nil", "get_player_names", "get_privilege_list",
            "get_server_info", "get_timeofday", "get_translator",
            "get_us_time", "get_version", "get_wielded_item", "gettext",
            "is_nan", "is_yes", "localplayer", "log",
            "mod_channel_join", "parse_json", "pointed_thing_to_face_pos",
            "pos_to_string", "privs_to_string", "register_globalstep",
            "register_on_damage_taken", "register_on_death",
            "register_on_dignode", "register_on_formspec_input",
            "register_on_hp_modification", "register_on_inventory_open",
            "register_on_item_use", "register_on_modchannel_message",
            "register_on_modchannel_signal", "register_on_placenode",
            "register_on_punchnode", "register_on_receiving_chat_message",
            "register_on_sending_chat_message", "rgba",
            "run_server_chatcommand", "send_chat_message", "send_respawn",
            "serialize", "sha1", "show_formspec", "sound_play", "sound_stop",
            "string_to_area", "string_to_pos", "string_to_privs",
            "strip_background_colors", "strip_colors",
            "strip_foreground_colors", "translate", "ui", "wrap_text",
            "write_json"}) do
        local func = minetest[k]
        t[k] = safe_funcs[func] or func
    end

    base_env:set_copy('minetest', t)
end

-- Add table.unpack
if not table.unpack then
    base_env._raw.table.unpack = unpack
end

-- Make sure copy() worked correctly
assert(base_env._raw.minetest.register_on_sending_chat_message ~=
    minetest.register_on_sending_chat_message, 'Error in copy()!')

-- SSCSM functions
-- When calling these from an SSCSM, make sure they exist first.
local mod_channel = minetest.mod_channel_join('sscsm:exec_pipe')
local loaded_sscsms = {}
base_env:set('join_mod_channel', function()
    if not mod_channel then
        mod_channel = minetest.mod_channel_join('sscsm:exec_pipe')
    end
end)

base_env:set('leave_mod_channel', function()
    if mod_channel then
        mod_channel:leave()
        mod_channel = false
    end
end)

-- Allow other CSMs to access the new Environment type
sscsm.Env = Env

-- exec() code sent by the server.
minetest.register_on_modchannel_message(function(channel_name, sender, message)
    if channel_name ~= 'sscsm:exec_pipe' or (sender and sender ~= '') then
        return
    end

    -- The first character is currently a version code, currently 0.
    -- Do not change unless absolutely necessary.
    local version = message:sub(1, 1)
    local name, code
    if version == '0' then
        local s, e = message:find('\n')
        if not s or not e then return end
        local target = message:sub(2, s - 1)
        if target ~= minetest.localplayer:get_name() then return end
        message = message:sub(e + 1)
        local s, e = message:find('\n')
        if not s or not e then return end
        name = message:sub(1, s - 1)
        code = message:sub(e + 1)
    else
        return
    end

    -- Create the environment
    if not sscsm.env then sscsm.env = Env:new() end

    -- Don't load the same SSCSM twice
    if not loaded_sscsms[name] then
        minetest.log('action', '[SSCSM] Loading ' .. name)
        loaded_sscsms[name] = true
        sscsm.env:exec(code)
    end
end)

-- Send "0"
local function request_csms(c)
    base_env._raw.minetest.localplayer = minetest.localplayer
    c = c or 10
    if c <= 0 then
        if mod_channel then
            mod_channel:leave()
            mod_channel = false
        end
        return
    end
    if minetest.localplayer and mod_channel:is_writeable() then
        mod_channel:send_all('0')
    else
        minetest.after(0.1, request_csms, c - 1)
    end
end
minetest.after(0, request_csms)
