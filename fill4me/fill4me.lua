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

	Fill4Me.lua

Fill4Me is a script to place fuel & ammo into entities when you place them.

Inspired by AutoFill, but disappointed by the newer version of AutoFill, I set
out to create a replacement.  The functionality of AutoFill(v1) was great for
vanilla, but suffered when given mods.  It also required manual updates in the
event that new entities were added.  Fill4Me's goals (through a complete rewrite)
include:
- performing fuel/ammo filling of entities upon placement;
- learning and discarding entity data as mods change (or when told);
- being able to be turned on/off per-player (though, most love it); and
- being easy to maintain.

--]]

require 'stdlib/event/event'
require 'lib/event_extend'

require 'fill4me/ammo'
require 'fill4me/fuel'
require 'fill4me/loadable_entities'
require 'lib/fb_util'

-- production score is used in lieu of being able to evaluate the damage of
-- smoke-based entities/items.  There is a failing in the code exposed to lua
-- which prevents being able to identify the base damage of things like 
-- poison-capsule (item) / poison-cloud (entity)
require 'util' -- needed by 'production-score' (below)

fill4me = {}

---@param event EventData | table
function fill4me.initMod(event)
	if not storage.fill4me then
		storage.fill4me = {
			initialized = false,
			fuels = {},
			ammos = {},
			loadable_entities = {},
			players = {},
		}
	end
	-- Need this to happen after, since it could be part of a mod upgrade.
	if not storage.fill4me.maximum_values then
		storage.fill4me.maximum_values = {
			fuel = 0,
			ammo = 0,
		}
	end
	if not storage.fill4me.initialized then
		fill4me.loadModSettings()
		fill4me.evaluate_items()
		fill4me.evaluate_entities()
		fill4me.reset_players_loadables()
		storage.fill4me.initialized = true
	end
	-- Sync each existing player's shortcut button to their real enable state.
	-- on_player_created covers brand-new players, but when the mod is added to
	-- an existing save that event never fires for current players, leaving the
	-- button visually "off" while the mod is actually enabled -- so the first
	-- click would silently turn the working mod off instead of on.
	fill4me.sync_player_shortcuts()
end
---@param event EventData | table
function fill4me.initPlayer(event)
	fill4me.player(event.player_index)
	local player = playerFromIndex(event.player_index)
	if player then
		player.set_shortcut_toggled("fill4me-shortcut-toggle", true)
	end
end
--- Make every existing player's shortcut button reflect their actual enable
--- state. Safe to call when no players exist yet (e.g. on_init): it's a no-op.
function fill4me.sync_player_shortcuts()
	for _, player in pairs(game.players) do
		local pldata = fill4me.player(player.index)
		player.set_shortcut_toggled("fill4me-shortcut-toggle", pldata.enable)
	end
end
---@param event EventData | table
function fill4me.reInitMod(event)
	if storage.fill4me then
		storage.fill4me.initialized = false
	end
	-- Item prices can change when mods are added/removed/updated, so drop the
	-- cached production-score price list and let it rebuild on re-evaluation.
	-- Otherwise ammo craft_value (the damage tiebreaker) goes stale.
	if storage.fill4me_internal then
		storage.fill4me_internal.price_list = nil
	end
	fill4me.initMod(event)
end
---@param event EventData | table
function fill4me.runtimeModSettingChanged(event)
	local idx, edx, matches = string.find(event.setting, "fill4me")
	if idx ~= 1 then
		return
	end
	if event.setting_type == "runtime-per-user" then
		fill4me.loadModPlayerSettings(event.player_index)
	elseif event.setting_type == "runtime-global" then
		fill4me.loadModSettings()
		fill4me.evaluate_items()
		fill4me.evaluate_entities()
	end
end
function fill4me.reset_players_loadables()
	local f4mdata = storage.fill4me
	for idx, pldata in pairs(f4mdata.players) do
		fill4me.reset_player_lists(idx)
		fill4me.loadModPlayerSettings(idx)
	end
	game.print({'fill4me.prefix', {'fill4me.players_reset'}})
end

---@param event EventData | table
function fill4me.reset_player_from_event(event)
	local player = playerFromIndex(event.player_index)
	if player then
		fill4me.reset_player_lists(player.index)
	end
end

--- split string by comma (ignores whitespace) to table/list
---@param str string
local function csv_string_to_list(str)
	local items = {}
	for item in string.gmatch(str,'[^,%s]+') do
		table.insert(items,item)
	end
	return items
end

--- Remove every entry named `item_name` from the player's per-player `section`
--- ("fuels" or "ammos"). With quality, one item name maps to several entries
--- (one per quality level), so we iterate in reverse and strip all of them in
--- a single pass -- otherwise table.remove() shifts indices and leaves some
--- quality variants behind (the cause of "blacklist still adds it").
---@param plidx integer
---@param section string
---@param item_name string
local function exclude_named_from_section(plidx, section, item_name)
	local sectiondata = fill4me.for_player(plidx, section)
	if not sectiondata then
		return
	end
	for _, entries in pairs(sectiondata) do
		for index = #entries, 1, -1 do
			if entries[index].name == item_name then
				table.remove(entries, index)
			end
		end
	end
end

--- Function to apply blacklist settings to current player
--- @param plidx integer
function fill4me.load_blacklist(plidx)
	local player = playerFromIndex(plidx)
	if player == nil then
		log("[ERR] Unable to find player for `load_blacklist()`")
		return
	end
	-- Rebuild the player's fuel/ammo lists from the global defaults, then strip
	-- every blacklisted item (all quality variants) back out of them.
	fill4me.reset_player_from_event({ player_index = plidx })

	---@diagnostic disable-next-line: param-type-mismatch
	local exclusion_fuel = csv_string_to_list(player.mod_settings["fill4me-blacklist-fuel"].value)
	for _, fuel in pairs(exclusion_fuel) do
		exclude_named_from_section(plidx, "fuels", fuel)
	end

	---@diagnostic disable-next-line: param-type-mismatch
	local exclusion_ammo = csv_string_to_list(player.mod_settings["fill4me-blacklist-ammo"].value)
	for _, ammo in pairs(exclusion_ammo) do
		exclude_named_from_section(plidx, "ammos", ammo)
	end
end

-- Entity built by player.  Evaluate for inserting fuel & ammo.
---@param event EventData | table
function fill4me.built_entity(event)
	local pldata = fill4me.player(event.player_index)
	if pldata and pldata.enable and event.entity and event.entity.valid then
		local entity = event.entity
		fill4me.fill_entity(entity, event.player_index, nil, pldata)
	end
end

-- Scan through entities, finding those that take fuel & ammo.
function fill4me.evaluate_entities()
	storage.fill4me.loadable_entities = {}
	local lent = storage.fill4me.loadable_entities
	for _, entdata in pairs(LoadEnts.list_of_fireables()) do
		lent[entdata.name] = table.merge(lent[entdata.name] or {}, entdata)
	end
	for _, entdata in pairs(LoadEnts.list_of_fuelables()) do
		lent[entdata.name] = table.merge(lent[entdata.name] or {}, entdata)
	end
end

-- Scan through items, finding fuels & ammos
function fill4me.evaluate_items()
	local gs = storage.fill4me
	gs.fuels = {}
	gs.ammos = {}
	
	-- evaluate fuel items
	local fuels = gs.fuels
	local fcategories = Fuel.categories()
	for idx, name in pairs(fcategories) do
		fuels[name] = {}
	end
	for idx, fuel in pairs(Fuel.list()) do
		if not(gs.maximum_values.fuel > 0 and fuel.value > gs.maximum_values.fuel) then
			table.insert(fuels[fuel.category], fuel)
		end
	end
	for idx, fuellist in pairs(fuels) do
		table.sort(fuellist, fill4me.fuel_sort_high)
	end
	
	-- evaluate ammunition items
	local ammos = storage.fill4me.ammos
	for idx, name in pairs(Ammo.categories()) do
		ammos[name] = {}
	end
	for idx, ammo in pairs(Ammo.list()) do
		if not(gs.maximum_values.ammo > 0 and ammo.damage and ammo.damage > gs.maximum_values.ammo) then
			table.insert(ammos[ammo.category], ammo)
		end
	end
	for name, itemlist in pairs(ammos) do
		table.sort(itemlist, fill4me.item_dmg_sort_high)
	end
end

---@param entity LuaEntity
---@param player_index integer
---@param player LuaPlayer?
---@param pldata table?
function fill4me.fill_entity(entity, player_index, player, pldata)
	if pldata == nil then
		pldata = fill4me.player(player_index)
	end
	local loadable_entity = fill4me.for_player(pldata, "loadable_entities")[entity.name]
	if loadable_entity then
		if player == nil then
			player = playerFromIndex(player_index)
		end
		if player == nil then
			log("[ERR] fill_entity was unable to find an active player.")
			return
		end
		local unlimited_range = settings.global["fill4me-refill-ignores-range-limit"].value
		if unlimited_range or player.can_reach_entity(entity) then
			if loadable_entity.fuel_categories then
				fill4me.load_fuel(entity, loadable_entity, player_index)
			end
			if loadable_entity.guns or loadable_entity.ammo_categories then
				fill4me.load_ammo(entity, loadable_entity, player_index)
			end
		else
			player.create_local_flying_text({
				text = {'cant-reach'},
				position = entity.position,
			})
		end
	end
end

---@param a table
---@param b table
function fill4me.fuel_sort_high(a, b)
	return a.value > b.value
end

---@param player LuaPlayer
---@param item_name string
---@param quality string
---@param max_size integer
---@param ammo_or_fuel string
function fill4me.getFromInventory(player, item_name, quality, max_size, ammo_or_fuel)
	local function max_load(pldata, ammo_or_fuel)
		if ammo_or_fuel == "ammo" then
			return pldata.max_ammo_load
		end
		return pldata.max_fuel_load
	end
	local function max_load_percent(pldata, ammo_or_fuel)
		if ammo_or_fuel == "ammo" then
			return pldata.max_ammo_load_percent
		end
		return pldata.max_fuel_load_percent
	end
	local pldata = fill4me.player(player.index)
	local inventory = player.get_main_inventory()
	if not inventory then
		return 0
	end
	local available = inventory.get_item_count({name=item_name, quality=quality})
	local removed = 0
	if available > 0 then
		removed = math.min(max_load(pldata, ammo_or_fuel), math.ceil(available*max_load_percent(pldata, ammo_or_fuel)))
		removed = math.min(removed, available)
		inventory.remove({name=item_name, quality=quality, count=removed})
	end
	return removed
end

---@param player LuaPlayer
---@param item_name string
---@param quality string
---@param amount integer
---@param ammo_or_fuel? any
function fill4me.returnToInventory(player, item_name, quality, amount, ammo_or_fuel)
	local pldata = fill4me.player(player.index)
	local inventory = player.get_main_inventory()
	if not inventory then
		return 0
	end
	inventory.insert({name=item_name, quality=quality, count=amount})
	return amount
end

---@param a table
---@param b table
function fill4me.item_dmg_sort_high(a, b)
	if a.damage == b.damage then
		return a.craft_value > b.craft_value
	end
	return a.damage > b.damage
end

-- Not sure which prototype it is we're using here.  Yikes.
---@param prototype LuaEntityPrototype | LuaItemPrototype
---@param ammo table
---@param playerdata table
local function ammo_radius_is_ok(prototype, ammo, playerdata)
	if playerdata.ignore_ammo_radius then
		return true
	elseif prototype.attack_parameters and prototype.attack_parameters.min_range < ammo.radius then
		return false
	end
	return true
end

---@param entity LuaEntity
---@param player LuaPlayer
---@param ammo table
local function try_ammo_load(entity, player, ammo)
	local count = fill4me.getFromInventory(player, ammo.name, ammo.quality, ammo.max_size, "ammo")
	if count > 0 then
		local loaded = fill4me.loadAmmoInto(entity, ammo.name, ammo.quality, count)
		if loaded > 0 then
			fill4me.textRemove(player, entity, ammo, loaded)
			if loaded < count then
				fill4me.loadInto(player, ammo.name, ammo.quality, count - loaded)
			end
			return true
		else
			fill4me.returnToInventory(player, ammo.name, ammo.quality, count, "ammo")
		end
	end
	return false
end

---@param entity LuaEntity
---@param lent table
---@param plidx integer
function fill4me.load_ammo(entity, lent, plidx)
	local player = playerFromIndex(plidx)
	if player == nil then
		-- Everything here depends on player being legitimate, so abandon early on weirdness.
		return
	end
	local pldata = fill4me.player(plidx)
	local proto = prototypes.entity[entity.name]
	if lent.ammo_categories then
		for _, category in pairs(lent.ammo_categories) do
			for _, ammo in pairs(fill4me.for_player(plidx, "ammos")[category]) do
				if ammo_radius_is_ok(proto, ammo, pldata) then
					if try_ammo_load(entity, player, ammo) then
						break
					end
				end
			end
		end
	end
	if lent.guns then
		for _, gun in pairs(lent.guns) do
			for _, category in pairs(gun.ammo_categories) do
				for _, ammo in pairs(fill4me.for_player(plidx, "ammos")[category]) do
					if try_ammo_load(entity, player, ammo) then
						break
					end
				end
			end
		end
	end
end

---@param entity LuaEntity
---@param player LuaPlayer
---@param fuel table
local function try_fuel_load(entity, player, fuel)
	local count = fill4me.getFromInventory(player, fuel.name, fuel.quality, fuel.max_size, "fuel")
	if count > 0 then
		local loaded = fill4me.loadFuelInto(entity, fuel.name, fuel.quality, count)
		if loaded > 0 then
			fill4me.textRemove(player, entity, fuel, loaded)
			if loaded < count then
				fill4me.loadInto(player, fuel.name, fuel.quality, count - loaded)
			end
			return true
		else
			fill4me.returnToInventory(player, fuel.name, fuel.quality, count, "fuel")
		end
	end
	return false
end

---@param entity LuaEntity
---@param lent table
---@param plidx integer
function fill4me.load_fuel(entity, lent, plidx)
	-- Load fuel from player's inventory into the entity.
	local player = playerFromIndex(plidx)
	if player == nil then
		-- Everything here depends on player being legitimate, so abandon early on weirdness.
		return
	end
	local found_fuel = false
	for name, t in pairs(lent.fuel_categories) do
		-- Prevent nil errors when no candidate fuels are available for given entity
		-- This will fall through to the next available type of fuel.
		local fuel_names = fill4me.for_player(plidx, "fuels")[name]
		if fuel_names then
			for _, fuel in pairs(fuel_names) do
				if try_fuel_load(entity, player, fuel) then
					found_fuel = true
					break
				end
			end
			if found_fuel then
				break
			end
		end
	end
end

---@param entity LuaEntity
---@param item_name string
---@param quantity integer
function fill4me.loadAmmoInto(entity, item_name, quality, quantity)
	-- try both car & turret inventories.
	local inv = entity.get_inventory(defines.inventory.car_ammo)
	local itemstack = { name = item_name, quality = quality, count = quantity }
	if not (inv and inv.valid) then
		inv = entity.get_inventory(defines.inventory.turret_ammo)
	end
	if inv and inv.valid and inv.can_insert(itemstack) then
		return inv.insert(itemstack)
	end
	return 0
end

---@param entity LuaEntity
---@param item_name string
---@param quantity integer
function fill4me.loadFuelInto(entity, item_name, quality, quantity)
	local inv = entity.get_inventory(defines.inventory.fuel)
	local itemstack = { name = item_name, quality = quality, count = quantity }
	if inv and inv.valid and inv.can_insert(itemstack) then
		return inv.insert(itemstack)
	end
	return 0
end

---@param entity LuaEntity | LuaPlayer
---@param item_name string
---@param quantity integer
function fill4me.loadInto(entity, item_name, quality, quantity)
	local itemstack = { name = item_name, quality = quality, count = quantity }
	return entity.insert(itemstack)
end

---@param event EventData | table
function fill4me.loadModSettings(event)
	local gms = settings.global
	local gs = storage.fill4me
	if gms['fill4me-maximum-fuel-value'] then
		---@diagnostic disable-next-line: assign-type-mismatch
		gs['maximum_values'].fuel = gms['fill4me-maximum-fuel-value'].value
	end
	if gms['fill4me-maximum-ammo-value'] then
		---@diagnostic disable-next-line: assign-type-mismatch
		gs['maximum_values'].ammo = gms['fill4me-maximum-ammo-value'].value
	end
end

---@param plidx integer
---@param pldata table
function fill4me.loadModPlayerSettings(plidx, pldata)
	local gmps = settings.get_player_settings(plidx)
	if gmps then
		if not pldata then
			pldata = fill4me.player(plidx)
		end
		pldata.ignore_ammo_radius = gmps["fill4me-ignore-ammo-radius"].value
		pldata.max_ammo_load = gmps["fill4me-ammo-load-count"].value
		pldata.max_ammo_load_percent = gmps["fill4me-ammo-load-percent"].value / 100.0
		if gmps["fill4me-ammo-load-limit"].value == "percent" then
			pldata.max_ammo_load = 1000
		end
		if gmps["fill4me-ammo-load-limit"].value == "count" then
			pldata.max_ammo_load_percent = 100
		end
		fill4me.load_blacklist(plidx)
	end
end

---@param plidx integer
function fill4me.player(plidx)
	if not storage.fill4me.players[plidx] then
		storage.fill4me.players[plidx] = {
			enable = true,
			max_fuel_load = 25,
			max_fuel_load_percent = 0.12,
			max_ammo_load = 25,
			max_ammo_load_percent = 0.12,
			loadable_entities = nil,
			fuels = nil,
			ammos = nil,
			ammo_ignore_radius = false,
			exclusions = {},
		}
		-- overrides from player mod settings (if exists.)
		local gms = settings.get_player_settings(plidx)
		if gms then
			local f4mplayer = storage.fill4me.players[plidx]
			-- always need to pass the f4m player here, otherwise this code
			-- will do an infinite loop, back & forth.
			fill4me.loadModPlayerSettings(plidx, f4mplayer)
		end
	end
	local f4mplayer = storage.fill4me.players[plidx]
	fill4me.try_migrate_player(f4mplayer)
	return f4mplayer
end
---@param f4mplayer table
function fill4me.try_migrate_player(f4mplayer)
	if f4mplayer.max_load then
		f4mplayer.max_fuel_load = f4mplayer.max_load
		f4mplayer.max_ammo_load = f4mplayer.max_load
		f4mplayer.max_fuel_load_percent = f4mplayer.max_load_percent
		f4mplayer.max_ammo_load_percent = f4mplayer.max_load_percent
		f4mplayer.max_load = nil
		f4mplayer.max_load_percent = nil
	end
	if not f4mplayer.exclusions then
		f4mplayer.exclusions = {}
	end
end

---@param player_index integer
function fill4me.reset_player_lists(player_index)
	local player = storage.fill4me.players[player_index]
	if player then
		player.loadable_entities = nil
		player.ammos = nil
		player.fuels = nil
	end
end

---@param player LuaPlayer | table | integer
---@param section string | integer
function fill4me.for_player(player, section)
	-- get the relevent player data for ammo, fuel, etc, or global version.
	local f4m_player = nil
	if type(player) == "number" then
		f4m_player = fill4me.player(player)
	elseif type(player) == "table" then
		if player.online_time then -- factorio player object.  get f4m player.
			f4m_player = fill4me.player(player.index)
		elseif player.max_ammo_load then -- f4m player.  check some field.
			f4m_player = player
		end
	end
	if f4m_player then
		if not storage.fill4me[section] then
			return
		end
		if not (f4m_player[section] and type(f4m_player[section]) == "table") then
			f4m_player[section] = table.deepcopy(storage.fill4me[section])
		end
		return f4m_player[section]
	end
end

---@param event EventData | table
function fill4me.script_built_entity(event)
	if event.entity and event.player_index then
		-- Work around scripts which dispatch a script event and THEN
		-- insert fuel/ammo into the entity of interest.
		-- Only functions if script included player index as part of event.
		-- Which might be a snowballs chance in hell.
		Event.on_next_tick(fill4me.built_entity, event)
	end
end

---@param player LuaPlayer
---@param entity LuaEntity
---@param item_name string
---@param quantity integer
---@param color? Color | table
function fill4me.textRemove(player, entity, fuel_or_ammo_entry, quantity, color)
	local pos = entity.position
	local pldata = fill4me.player(player.index)
	pos.x = pos.x + 0.75
	pos.y = pos.y - 0.5
	local textcolor = color or {r=1, g=1, b=1, a=1}
	local itemText = "[item=" .. fuel_or_ammo_entry.name .. "]";
	local qualityText = ""
	if fuel_or_ammo_entry.quality_level > 0 then
		itemText = "[item=" .. fuel_or_ammo_entry.name .. ", quality=" .. fuel_or_ammo_entry.quality .. "]";
		qualityText = fuel_or_ammo_entry.quality_i18n
	end
	player.create_local_flying_text({
		text = { 'fill4me.removed', quantity, itemText, fuel_or_ammo_entry.i18n, qualityText },
		icon = fuel_or_ammo_entry.name,
		position = pos,
		color = textcolor,
	})
end

---@param plidx integer
function fill4me.toggle(plidx)
	local pldata = fill4me.player(plidx)
	local player = playerFromIndex(plidx)
	if player == nil then
		log("[ERR] Unable to find player to toggle Fill4Me")
		return
	end
	pldata.enable = not pldata.enable
	
	--fill4me_guib.reset_button_sprite_for(plidx)

	if pldata.enable then
		player.set_shortcut_toggled("fill4me-shortcut-toggle", true)
	else
		player.set_shortcut_toggled("fill4me-shortcut-toggle", false)
	end
	return pldata.enable
end

---@param event EventData | table
function fill4me.on_lua_shortcut(event)
	if event.prototype_name == "fill4me-shortcut-toggle" then
		fill4me.toggle(event.player_index)
	end
end

---@param plidx integer
---@param set_to boolean
function fill4me.set_ignore_ammo_radius(plidx, set_to)
	local player = playerFromIndex(plidx)
	if player == nil then
		return
	end
	local pldata = fill4me.player(plidx)
	pldata.ignore_ammo_radius = set_to

	if pldata.ignore_ammo_radius then
		player.print({'fill4me.prefix', {'fill4me.ammo_radius_ignored'}})
	else
		player.print({'fill4me.prefix', {'fill4me.ammo_radius_checked'}})
	end
end
function fill4me.toggle_ignore_ammo_radius(plidx)
	local set_to = not fill4me.player(plidx).ignore_ammo_radius
	fill4me.set_ignore_ammo_radius(plidx, set_to)
end

Event.register(Event.core_events.configuration_changed, fill4me.reInitMod)
--Event.register(Event.def("softmod_init"), fill4me.initMod)
Event.register(Event.core_events.on_init, fill4me.initMod)
Event.register(defines.events.on_runtime_mod_setting_changed, fill4me.runtimeModSettingChanged)
Event.register(defines.events.on_built_entity, fill4me.built_entity)
Event.register(defines.events.script_raised_built, fill4me.script_built_entity)
Event.register(defines.events.on_player_created, fill4me.initPlayer)
Event.register(defines.events.on_lua_shortcut, fill4me.on_lua_shortcut)
