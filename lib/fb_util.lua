--[[
FishBus Gaming permissions system - Utility functionality
These are 'common use' functions

Tick conversion originates from ExplosiveGamings's mod.
--]]

---@return integer
function ticksPerHour()
	return 216000*game.speed
end
---@return integer
function ticksPerMin()
	return 3600*game.speed
end
---@param tick integer
---@return integer
function ticktohour (tick)
    local hour = math.floor(tick/ticksPerHour())
    return hour
end
---@param tick integer
---@return integer
function ticktominutes (tick)
  	local minutes = math.floor(tick/ticksPerMin())
    return minutes
end

---@param tick integer
---@return table
function tick2time(tick)
	-- returns hour & min as table
	local tph = ticksPerHour()
	local tpm = ticksPerMin()
	local hour = math.floor(tick/tph)
	local min = math.floor((tick % tph)/tpm)
	local sec = math.floor(tick % tpm)
	return { 
		hours = hour,
		minutes = min,
		seconds = sec,
	}
end

---@param array any[]
---@param value any
---@return boolean
function arr_contains(array, value)
	for idx, val in pairs(array) do
		if val == value then
			return true
		end
	end
	return false
end
---@param array any[]
---@param value any
function arr_remove(array, value)
	for idx=#array, 1, -1 do
		if array[idx] == value then
			table.remove(array, idx)
		end
	end
end

---@param text string
---@return string[]
function parseParams(text)
	if not text then
		return {}
	end
	-- from https://stackoverflow.com/questions/28664139/lua-split-string-into-words-unless-quoted
	local parts = {}
	local spat, epat, buf, quoted = [=[^(['"])]=], [=[(['"])$]=], nil, nil
	for str in text:gmatch("%S+") do
		local squoted = str:match(spat)
		local equoted = str:match(epat)
		local escaped = str:match([=[(\*)['"]$]=])
		if squoted and not quoted and not equoted then
			buf, quoted = str, squoted
		elseif buf and equoted == quoted and #escaped % 2 == 0 then
			str, buf, quoted = buf .. ' ' .. str, nil, nil
		elseif buf then
			buf = buf .. ' ' .. str
		end
		if not buf then
			table.insert(parts, (str:gsub(spat,""):gsub(epat,"")))
		end
	end
	if buf then
		-- Don't really want to throw here, since it's still data, so just 
		-- append the remainder as one part.
		table.insert(parts, (buf:gsub(spat,'')))
	end
	return parts
end

---@param name string
---@return LuaPlayer?
function getPlayerNamed(name)
	--[[
	game.players[....] is a table lookup by either index or name.
	If the parameter passed is a numeric string (which could be a player name)
	then it is treated like a number, and an incorrect lookup is done.
	This function works around this problem by checking if the name is numeric,
	and if it is, scan through the players to find the correct one.  If it's
	alphanumeric, then we can use the normal lookup.
	-- ]]
	local numname = tonumber(name)
	if numname then
		-- numeric username
		for idx, player in pairs(game.players) do
			if name == player.name then
				return player
			end
		end
	else
		return game.players[name]
	end
	return nil
end

---@param index integer
---@return LuaPlayer?
function playerFromIndex(index)
	--[[
	game.players lookups will apparently search the entire array for a match.
	If a match is found in either player name or index, then it is returned.
	This is undesired behavior if we have an index, and know it's an index.
	So we'll want to verify that the player we get back has the expected index
	and if not, find the player with the correct index by iterating through
	game.players
	-- ]]

	local player = game.players[index]
	if player == nil then
		return nil
	end
	if player.index == index then
		return player
	end
	for idx, gplayer in pairs(game.players) do
		if gplayer.index == index then
			return gplayer
		end
	end
	log("[ERR] Unable to find player by index.  All matching possibilities failed.")
	return nil
end

---@param entityName string
---@param player LuaPlayer
---@param radius number
---@return LuaEntity?
function createEntityNearPlayer(entityName, player, radius)
	--player.print("DEBUG: Creating '"..entityName.."' near '"..player.name.."'")
	local entity = nil
	local location = player.surface.find_non_colliding_position(entityName, player.position, radius, 1)
	if location then
		entity = player.surface.create_entity{
			name=entityName, position=location, force=player.force
		}
	end
	return entity
end
