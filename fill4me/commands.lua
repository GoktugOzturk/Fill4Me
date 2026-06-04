--[[
Copyright 2018 "Kovus" <kovus@soulless.wtf>

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation and/or
other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors
may be used to endorse or promote products derived from this software without
specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

	commands.lua

Commands for Fill4Me.  (Precursor to a UI)

--]]

require 'lib/fb_util'

fill4me_cmd = {}

---@param event EventData | table
function fill4me_cmd.exclude(event)
	local player = playerFromIndex(event.player_index)
	if player == nil then
		log("[ERR] unable to find player")
		return
	end
	local f4mplayer = fill4me.player(player.index)
	if event.parameter then
		local fuel_list = fill4me.for_player(player.index, "fuels")
		local removed = false
		for name, data in pairs(fuel_list) do
			-- Iterate in reverse so table.remove() doesn't shift entries we
			-- haven't checked yet (which would skip duplicates).
			for index = #data, 1, -1 do
				local fuel = data[index]
				if fuel.name == event.parameter then
					table.remove(data, index)
					player.print({'fill4me.cmd.exclude.excluding', fuel.i18n})
					table.insert(f4mplayer.exclusions, fuel.name)
					removed = true
				end
			end
		end
		if not removed then
			player.print({'fill4me.cmd.error_exclude', event.parameter})
		end
	else
		-- display error
		player.print({'fill4me.prefix', {'fill4me.cmd.error_in_command'}})
		player.print({'fill4me.cmd.usage_exclude'})
		player.print({'fill4me.cmd.example', {'fill4me.cmd.example_exclude'}})
	end
end

---@param event EventData | table
function fill4me_cmd.include(event)
	local player = playerFromIndex(event.player_index)
	if player == nil then
		log("[ERR] unable to find player")
		return
	end
	if event.parameter then
		local fuel_list = storage.fill4me.fuels
		local cat = nil
		local fuel_to_add = nil
		for catname, data in pairs(fuel_list) do
			for index, fuel in pairs(data) do
				if fuel.name == event.parameter then
					cat = catname
					fuel_to_add = fuel
				end
			end
		end	
		if fuel_to_add == nil then
			player.print({'fill4me.cmd.error_include_not_found', event.parameter})
			return
		end
		local player_fuel_list = fill4me.for_player(player.index, "fuels")[cat]
		local already_included = false
		for index, fuel in pairs(player_fuel_list) do
			if fuel.name == fuel_to_add.name then
				already_included = true
			end
		end
		if not already_included then
			table.insert(player_fuel_list, table.deepcopy(fuel_to_add))
			table.sort(player_fuel_list, fill4me.fuel_sort_high)
		end
		player.print({'fill4me.cmd.include_fuel.including', fuel_to_add.i18n})
	else
		-- display error
		player.print({'fill4me.prefix', {'fill4me.cmd.error_in_command'}})
		player.print({'fill4me.cmd.usage_include'})
		player.print({'fill4me.cmd.example', {'fill4me.cmd.example_include'}})
	end
end

---@param event EventData | table
function fill4me_cmd.max_percent(event)
	local player = playerFromIndex(event.player_index)
	if player == nil then
		log("[ERR] unable to find player")
		return
	end
	if event.parameter then
		local percent = tonumber(event.parameter)
		if percent and percent > 0 and percent <= 100 then
			local pldata = fill4me.player(event.player_index)
			pldata.max_ammo_load_percent = percent / 100
			pldata.max_fuel_load_percent = percent / 100
			player.print({'fill4me.prefix', {'fill4me.cmd.set_max_percent', percent}})
		else
			-- display error
			player.print({'fill4me.prefix', {'fill4me.cmd.error_max_percent'}})
			player.print({'fill4me.cmd.usage_max_percent'})
			player.print({'fill4me.cmd.example', {'fill4me.cmd.example_max_percent'}})
		end
	else
		-- display error, provide help text.
		player.print({'fill4me.prefix', {'fill4me.cmd.error_max_percent'}})
		player.print({'fill4me.cmd.usage_max_percent'})
		player.print({'fill4me.cmd.example', {'fill4me.cmd.example_max_percent'}})
	end
end

---@param event EventData | table
function fill4me_cmd.list_fuel(event)
	local player = playerFromIndex(event.player_index)
	if player == nil then
		log("[ERR] unable to find player")
		return
	end
	local fuel_list = fill4me.for_player(player.index, "fuels")
	for index, name in pairs(Fuel.categories()) do
		local fuels = {}
		for _, fuel in pairs(fuel_list[name]) do
			table.insert(fuels, fuel.name)
		end
		player.print({'', name, ': ', serpent.line(fuels) })
	end
end

---@param event EventData | table
function fill4me_cmd.list_all_fuel(event)
	local player = playerFromIndex(event.player_index)
	local fuel_list = storage.fill4me.fuels
	for index, name in pairs(Fuel.categories()) do
		local fuels = {}
		for _, fuel in pairs(fuel_list[name]) do
			table.insert(fuels, fuel.name)
		end
		if player then
			player.print({'', name, ': ', serpent.line(fuels) })
		end
	end
end

---@param event EventData | table
function fill4me_cmd.reset_me(event)
	fill4me.reset_player_from_event(event)
	local player = playerFromIndex(event.player_index)
	if player ~= nil then
		player.print({'fill4me.prefix', {'fill4me.cmd.reset'}})
	end
end

---@param event EventData | table
function fill4me_cmd.toggle(event)
	fill4me.toggle(event.player_index)
end

---@param event EventData | table
function fill4me_cmd.toggle_ignore_ammo_radius(event)
	fill4me.toggle_ignore_ammo_radius(event.player_index)
end

commands.add_command('f4m.toggle', {'fill4me.gui.enable_tooltip'}, fill4me_cmd.toggle)
commands.add_command('f4m.max_percent', {'fill4me.cmd.help_max_percent'}, fill4me_cmd.max_percent)
commands.add_command('f4m.ignore_ammo_radius', {'fill4me.cmd.ignore_ammo_radius'}, fill4me_cmd.toggle_ignore_ammo_radius)
commands.add_command('f4m.list_fuel',  {'fill4me.cmd.list_fuel'}, fill4me_cmd.list_fuel)
commands.add_command('f4m.list_all_fuel',  {'fill4me.cmd.list_all_fuel'}, fill4me_cmd.list_all_fuel)
commands.add_command('f4m.reset_me',  {'fill4me.cmd.reset_me'}, fill4me_cmd.reset_me)
commands.add_command('f4m.exclude', {'fill4me.cmd.exclude'}, fill4me_cmd.exclude)
commands.add_command('f4m.include', {'fill4me.cmd.include'}, fill4me_cmd.include)

--
-- Debug commands
-- 

---@param event EventData | table
function fill4me_cmd.debug(event)
	local player = playerFromIndex(event.player_index)
	local print = game.print
	if player then print = player.print end
	print(serpent.line(storage.fill4me))
end

---@param event EventData | table
function fill4me_cmd.debug_fuel_type(event)
	local player = playerFromIndex(event.player_index)
	local print = game.print
	if player then print = player.print end
	if event.parameter then
		local params = parseParams(event.parameter)
		print(serpent.line(storage.fill4me))
	else
		print(serpent.line(storage.fill4me.fuels))
	end
end

---@param event EventData | table
function fill4me_cmd.debug_ammo_type(event)
	local player = playerFromIndex(event.player_index)
	local print = game.print
	if player then print = player.print end
	if event.parameter then
		local params = parseParams(event.parameter)
		local ammos = storage.fill4me.ammos[params[1]]
		if ammos then
			for _, data in ipairs(ammos) do
				print(serpent.line(data))
			end
		else
			print("Ammo type `"..params[1].."` not found.")
		end
	else
		local categories = {}
		for catname, data in pairs(storage.fill4me.ammos) do
			table.insert(categories, catname)
		end
		print(serpent.line(categories))
	end
end

---@param event EventData | table
function fill4me_cmd.debug_entity(event)
	local player = playerFromIndex(event.player_index)
	local print = game.print
	if player then print = player.print end
	if event.parameter then
		local params = parseParams(event.parameter)
		print(serpent.line(storage.fill4me))
	else
		print(serpent.line(storage.fill4me.loadable_entities))
	end
end

---@param event EventData | table
function fill4me_cmd.debug_global(event)
	local player = playerFromIndex(event.player_index)
	local print = game.print
	if player then 
		print = player.print
	end
	print(serpent.line(storage.fill4me))
end

---@param event EventData | table
function fill4me_cmd.debug_player(event)
	local player = playerFromIndex(event.player_index)
	local print = game.print
	if player then
		print = player.print
	end
	local pldata = nil
	if event.parameter then
		local params = parseParams(event.parameter)
		pldata = fill4me.player(game.get_player(params[1]))
	else
		pldata = fill4me.player(event.player_index)
	end
	print(serpent.line(pldata))
end

if true == false then -- DEBUG functionality.
	commands.add_command('f4m.debug', '', fill4me_cmd.debug)
	commands.add_command('f4m.debug.ammo', '', fill4me_cmd.debug_ammo_type)
	commands.add_command('f4m.debug.fuel', '', fill4me_cmd.debug_fuel_type)
	commands.add_command('f4m.debug.entity', '', fill4me_cmd.debug_entity)
	commands.add_command('f4m.debug.global', '', fill4me_cmd.debug_global)
	commands.add_command('f4m.debug.player', '', fill4me_cmd.debug_player)
	commands.add_command('f4m.debug.reinit', '', fill4me.reInitMod)
end
