--[[
Copyright 2017-2018 "Kovus" <kovus@soulless.wtf>

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
	
	Initialization Event for softmods (not actual game init)
	
	Create an on-player initialization point for soft mods.
	
	Files which initialize data should register a new event:
	Event.register(Event.def("softmod_init"), function(event) ... end)
	
	Then instead of trying to initialize the softmod on game init, the softmod
	is initialized when the first player is created/joins.
	This lets the softmods be added to an existing map.
--]]

require 'stdlib/event/event'

--[[
	Returns a UINT based on the name passed, for use in event operations.
	If the name is not already registered, then a new UINT value is generated
--]]
-- function Event.def(name)
-- 	if not Event._name_registry then
-- 		Event._name_registry = {}
-- 	end
-- 	local reg = Event._name_registry
-- 	if not reg[name] then
-- 		local val = script.generate_event_name()
-- 		reg[name] = val
-- 	end
-- 	return reg[name]
-- end

-- local mod_rel = 1

-- function event_softmod_init(event)
-- 	if not global.softmod_cur then
-- 		global.softmod_cur = 0
-- 		global.mod_rel = mod_rel
-- 	end
-- 	if not global.kevents then
-- 		global.kevents = {}
-- 	end
-- 	if not global.kevents.on_next_tick then
-- 		global.kevents.on_next_tick = {}
-- 	end
-- 	if global.softmod_cur < global.mod_rel then
-- 		global.softmod_cur = global.mod_rel
-- 		Event.dispatch({name = Event.def("softmod_init"), tick = game.tick})
-- 	end
-- end

kevents = {on_next_tick = {}}

---@param event EventData | table
function event_on_next_tick(event)
	if kevents and #kevents.on_next_tick > 0 then
		-- clone and wipe the on_next_tick list, in case we generate a new
		-- `on_next_tick` event.
		local events = table.deepcopy(kevents.on_next_tick)
		kevents.on_next_tick = {}
		for _, event in pairs(events) do
			if event.func and type(event.func) == "function" then
				event.func(event.params)
			end
		end
	end
end

---@param in_func function
---@param in_params ... any
function Event.on_next_tick(in_func, in_params)
	table.insert(kevents.on_next_tick, {
		func = in_func,
		params = in_params,
	})
end

-- Event.register({
-- 	Event.core_events.init,
-- 	defines.events.on_player_joined_game,
-- 	defines.events.on_player_created,
-- 	Event.core_events.configuration_changed,
-- }, event_softmod_init)

Event.register(defines.events.on_tick, event_on_next_tick)
