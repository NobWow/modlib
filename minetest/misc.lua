-- Localize globals
local assert, minetest, modlib, next, pairs, string, setmetatable, table, type, unpack
	= assert, minetest, modlib, next, pairs, string, setmetatable, table, type, unpack
-- Set environment
local _ENV = ...
setfenv(1, _ENV)

max_wear = 2 ^ 16 - 1

function override(function_name, function_builder)
	local func = minetest[function_name]
	minetest["original_" .. function_name] = func
	minetest[function_name] = function_builder(func)
end

local jobs = modlib.heap.new(function(a, b)
	return a.time < b.time
end)
local job_metatable = {
	__index = {
		cancel = function(self)
			self.cancelled = true
		end
	}
}
local time = 0
function after(seconds, func, ...)
	local job = setmetatable({
		time = time + seconds,
		func = func,
		...
	}, job_metatable)
	jobs:push(job)
	return job
end
minetest.register_globalstep(function(dtime)
	time = time + dtime
	local job = jobs[1]
	while job and job.time <= time do
		if not job.cancelled then
			job.func(unpack(job))
		end
		jobs:pop()
		job = jobs[1]
	end
end)

function register_globalstep(interval, callback)
	if type(callback) ~= "function" then
		return
	end
	local time = 0
	minetest.register_globalstep(function(dtime)
		time = time + dtime
		if time >= interval then
			callback(time)
			-- TODO ensure this breaks nothing
			time = time % interval
		end
	end)
end

form_listeners = {}

function register_form_listener(formname, func)
	local current_listeners = form_listeners[formname] or {}
	table.insert(current_listeners, func)
	form_listeners[formname] = current_listeners
end

local icall = modlib.table.icall
minetest.register_on_player_receive_fields(function(player, formname, fields)
	icall(form_listeners[formname] or {})
end)

function texture_modifier_inventorycube(face_1, face_2, face_3)
	return "[inventorycube{" .. string.gsub(face_1, "%^", "&")
			.. "{" .. string.gsub(face_2, "%^", "&")
			.. "{" .. string.gsub(face_3, "%^", "&")
end
function get_node_inventory_image(nodename)
	local n = minetest.registered_nodes[nodename]
	if not n then
		return
	end
	local tiles = {}
	for l, tile in pairs(n.tiles or {}) do
		tiles[l] = (type(tile) == "string" and tile) or tile.name
	end
	local chosen_tiles = { tiles[1], tiles[3], tiles[5] }
	if #chosen_tiles == 0 then
		return false
	end
	if not chosen_tiles[2] then
		chosen_tiles[2] = chosen_tiles[1]
	end
	if not chosen_tiles[3] then
		chosen_tiles[3] = chosen_tiles[2]
	end
	local img = minetest.registered_items[nodename].inventory_image
	if string.len(img) == 0 then
		img = nil
	end
	return img or texture_modifier_inventorycube(chosen_tiles[1], chosen_tiles[2], chosen_tiles[3])
end
function check_player_privs(playername, privtable)
	local privs=minetest.get_player_privs(playername)
	local missing_privs={}
	local to_lose_privs={}
	for priv, expected_value in pairs(privtable) do
		local actual_value=privs[priv]
		if expected_value then
			if not actual_value then
				table.insert(missing_privs, priv)
			end
		else
			if actual_value then
				table.insert(to_lose_privs, priv)
			end
		end
	end
	return missing_privs, to_lose_privs
end

minetest.register_globalstep(function(dtime)
	for k, v in pairs(delta_times) do
		local v=dtime+v
		if v > delays[k] then
			callbacks[k](v)
			v=0
		end
		delta_times[k]=v
	end
end)

form_listeners = {}
function register_form_listener(formname, func)
	local current_listeners = form_listeners[formname] or {}
	table.insert(current_listeners, func)
	form_listeners[formname] = current_listeners
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	local handlers = form_listeners[formname]
	if handlers then
		for _, handler in pairs(handlers) do
			handler(player, fields)
		end
	end
end)

--+ Improved base64 decode removing valid padding
function decode_base64(base64)
	local len = base64:len()
	local padding_char = base64:sub(len, len) == "="
	if padding_char then
		if len % 4 ~= 0 then
			return
		end
		if base64:sub(len-1, len-1) == "=" then
			base64 = base64:sub(1, len-2)
		else
			base64 = base64:sub(1, len-1)
		end
	end
	return minetest.decode_base64(base64)
end

local object_refs = minetest.object_refs
--+ Objects inside radius iterator. Uses a linear search.
function objects_inside_radius(pos, radius)
	radius = radius^2
	local id, object, object_pos
	return function()
		repeat
			id, object = next(object_refs, id)
			object_pos = object:get_pos()
		until (not object) or ((pos.x-object_pos.x)^2 + (pos.y-object_pos.y)^2 + (pos.z-object_pos.z)^2) <= radius
		return object
	end
end

--+ Objects inside area iterator. Uses a linear search.
function objects_inside_area(min, max)
	local id, object, object_pos
	return function()
		repeat
			id, object = next(object_refs, id)
			object_pos = object:get_pos()
		until (not object) or (
			(min.x <= object_pos.x and min.y <= object_pos.y and min.z <= object_pos.z)
			and
			(max.y >= object_pos.x and max.y >= object_pos.y and max.z >= object_pos.z)
		)
		return object
	end
end

--: node_or_groupname "modname:nodename", "group:groupname[,groupname]"
--> function(nodename) -> whether node matches
function nodename_matcher(node_or_groupname)
	if modlib.text.starts_with(node_or_groupname, "group:") then
		-- TODO consider using modlib.text.split instead of Minetest's string.split
		local groups = node_or_groupname:sub(("group:"):len() + 1):split(",")
		return function(nodename)
			for _, groupname in pairs(groups) do
				if minetest.get_item_group(nodename, groupname) == 0 then
					return false
				end
			end
			return true
		end
	else
		return function(nodename)
			return nodename == node_or_groupname
		end
	end
end
