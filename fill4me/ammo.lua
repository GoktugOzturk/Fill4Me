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

	Ammo.lua

Functionality related to the handling of Ammo for Fill4Me.

--]]

Ammo = {}

-- for production_score.generate_price_list()
production_score = require 'production-score'

-- 
-- General-purpose Ammo functions (the ones you probably want to call)
-- 

function Ammo.categories()
	local catlist = {}
	for name, proto in pairs(prototypes.ammo_category) do
		table.insert(catlist, name)
	end
	return catlist
end

-- Get a list of ammunition in the game, along with some properties of interest.
function Ammo.list()
	local ammolist = {}
	local item_craft_values = Ammo.price_list()
	for _, proto in pairs(prototypes.item) do
		-- evaluate ammunition items
		if proto and proto.ammo_category then
			local ammotype = proto.get_ammo_type()
			if ammotype and ammotype.action then
				local damage = Ammo.damage_from_actions(ammotype.action, {})
				local radius = Ammo.radius_from_actions(ammotype.action, {})
				local data = {
					name = proto.name,
					category = proto.ammo_category.name,
					craft_value = item_craft_values[proto.name] or 0,
					damage = damage,
					i18n = proto.localised_name,
					max_size = math.ceil(proto.stack_size / 2),
					radius = radius,
				}
				table.insert(ammolist, data)
			elseif ammotype then
				log("Warning: Ammotype without action: " .. serpent.block(ammotype))
			end
		end
	end
	return ammolist
end

function Ammo.price_list()
	-- get or build & get price list from factorio's pvp code.
	if not storage.fill4me_internal then
		storage.fill4me_internal = {}
	end
	if not storage.fill4me_internal.price_list then
		storage.fill4me_internal.price_list = production_score.generate_price_list()
	end
	return storage.fill4me_internal.price_list
end

--
-- Damage
--
---@param action TriggerItem | TriggerDelivery
---@param stack_names string[]
function Ammo.damage_from_action(action, stack_names)
	local damage = 0
	if action.action_delivery then
		for _, ad in pairs(action.action_delivery) do
			local multiplier = 1
			-- It's derivatives of TriggerItem we're interested in, and those
			-- derivatives will have 'radius' defined.
			---@diagnostic disable-next-line: undefined-field
			if action.radius then
				---@diagnostic disable-next-line: undefined-field
				multiplier = action.radius * action.radius * math.pi
			end
			damage = damage + Ammo.delivery_damage(ad, stack_names) * multiplier
		end
	end
	return damage
end

---@param actionset TriggerItem[]
---@param stack_names string[]
function Ammo.damage_from_actions(actionset, stack_names)

	local damage = 0
	for _, act in pairs(actionset) do
		damage = damage + Ammo.damage_from_action(act, stack_names) * act.repeat_count
	end
	return damage
end

---@param entity_name string
---@param stack_names string[]
function Ammo.entity_attack_damage(entity_name, stack_names)
	-- before adding this to the result, check that it's not a repeating entity.
	-- Note, clone the table, as we can encounter the same effect down the
	-- multiple effects that an entity can have.
	-- Space Exploration has plague loop (rocket -> cloud -> wave -> cloud -> wave)
	if arr_contains(stack_names, entity_name) then
		game.print({"fill4me.loop_in_ammo_damage_calc", stack_names[1]})
		return 0
	end
	table.insert(stack_names, entity_name)

	local ent = prototypes.entity[entity_name]
	local damage = 0
	if ent then
		if ent.attack_result then
			damage = damage + Ammo.damage_from_actions(ent.attack_result, {table.unpack(stack_names)})
		end
		if ent.final_attack_result then
			damage = damage + Ammo.damage_from_actions(ent.final_attack_result, {table.unpack(stack_names)})
		end
	end
	return damage
end

-- The action_delivery (ad) of this has a lot of potential subclasses, all of which are in C,
-- so trying to map them to Lua is ... messy.  Just let `ad` be anything then.
---@param ad any
---@param stack_names string[]
function Ammo.delivery_damage(ad, stack_names)
	damage = 0
	if ad.type == 'instant' then
		if ad.target_effects then
			for _, te in pairs(ad.target_effects) do
				if te.action then
					damage = damage + Ammo.damage_from_actions(te.action, stack_names)
				end
				if te.type == 'damage' then
					damage = damage + te.damage.amount
				end
				if te.type == 'create-entity' and te.entity_name then
					damage = damage + Ammo.entity_attack_damage(te.entity_name, stack_names)
				end
			end
		end
	elseif ad.projectile then
		damage = damage + Ammo.entity_attack_damage(ad.projectile, stack_names)
	elseif ad.stream then
		damage = damage + Ammo.entity_attack_damage(ad.stream, stack_names)
	end
	return damage
end

--
-- Radius
--
---@param action TriggerItem | TriggerDelivery | any
---@param stack_names string[]
function Ammo.radius_from_action(action, stack_names)
	local radius = 0
	if action.action_delivery then
		for _, actdelivery in pairs(action.action_delivery) do
			if action.radius then
				radius = action.radius
			end
			radius = radius + Ammo.radius_of_delivery(actdelivery, stack_names)
		end
	end
	return radius
end

---@param actionset TriggerItem[]
---@param stack_names string[]
function Ammo.radius_from_actions(actionset, stack_names)
	local radius = 0
	for _, act in pairs(actionset) do
		radius = radius + Ammo.radius_from_action(act, stack_names)
	end
	return radius
end

---@param entity_name string
---@param stack_names string[]
function Ammo.radius_from_entity(entity_name, stack_names)
	-- before adding this to the result, check that it's not
	-- a repeating entry of one we've done.
	-- Space Exploration does this with plague
	-- (rocket -> cloud -> wave -> cloud -> wave)
	if arr_contains(stack_names, entity_name) then
		game.print({"fill4me.loop_in_ammo_radius_calc", stack_names[1]})
		return 0
	end
	table.insert(stack_names, entity_name)

	local ent = prototypes.entity[entity_name]
	local radius = 0
	if ent then
		if ent.attack_result then
			radius = radius + Ammo.radius_from_actions(ent.attack_result, {table.unpack(stack_names)})
		end
		if ent.final_attack_result then
			radius = radius + Ammo.radius_from_actions(ent.final_attack_result, {table.unpack(stack_names)})
		end
	end
	return radius
end

function Ammo.radius_of_delivery(adelivery, stack_names)
	radius = 0
	if adelivery.type == 'instant' then
		if adelivery.target_effects then
			for _, te in pairs(adelivery.target_effects) do
				if te.action then
					if te.action.radius then
						radius = radius + te.action.radius
					end
					radius = radius + Ammo.radius_from_actions(te.action, stack_names)
				end
			end
		end
	elseif adelivery.projectile then
		radius = radius + Ammo.radius_from_entity(adelivery.projectile, stack_names)
	elseif adelivery.stream then
		radius = radius + Ammo.radius_from_entity(adelivery.stream, stack_names)
	end
	return radius
end

return Ammo
