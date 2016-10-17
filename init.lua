-- expose api
townchest = {}
townchest.modpath = minetest.get_modpath(minetest.get_current_modname())


-- debug. Used for debug messages. In production the function should be empty
local dprint = function(...)
-- debug print. Comment out the next line if you don't need debug out
--	print(unpack(arg))
end
townchest.dprint = dprint


-- The Chest
dofile(townchest.modpath.."/".."chest.lua")

-- UI tools/ formspec
dofile(townchest.modpath.."/".."specwidgets.lua")

-- Reading building files (WorldEdit)
dofile(townchest.modpath.."/".."files.lua")

-- Nodes mapping
dofile(townchest.modpath.."/".."nodes.lua")

-- building plan
dofile(townchest.modpath.."/".."plan.lua")

-- NPC's
dofile(townchest.modpath.."/".."npc.lua")

--[[
-----------------------------------------------
-- __cheststep - triggered building step
-----------------------------------------------
local __cheststep = function(pos)
	local chest = townchest.chest.get(pos)
	chest:do_cheststep()
end
]]--

-----------------------------------------------
-- on_receive_fields - called when a chest button is submitted
-----------------------------------------------
local __on_receive_fields = function(pos, formname, fields, sender)
	local chest = townchest.chest.get(pos)
	chest:set_specwidget_receive_fields(pos, formname, fields, sender)
end

-----------------------------------------------
-- on_construct - if the chest is placed
-----------------------------------------------
local __on_construct = function(pos)
	local chest = townchest.chest.create(pos) --create new chest utils instance
	chest:set_specwidget("select_file")       -- set formspec to "select file"
end

-----------------------------------------------
-- on_destruct - if the chest destroyed
-----------------------------------------------
local __on_destruct = function(pos)
	dprint("on_destruct")
	-- remove all cached chest references
	local key = pos.x..","..pos.y..","..pos.z
	townchest.chest.list[key] = nil --delete old reference
end

-----------------------------------------------
-- restore - called in lbm, restore chest internal data if the server was restarted
-----------------------------------------------
local __restore = function(pos, node)
	dprint("check and restore chest")
	local chest = townchest.chest.get(pos)
	chest:restore()
end

-----------------------------------------------
-- on_punch
-----------------------------------------------
local __on_punch = function(pos)
	dprint("on_punch")
end

-----------------------------------------------
-- on_metadata_inventory_put
-----------------------------------------------
local __on_metadata_inventory_put = function(pos)
	return 0
end

-----------------------------------------------
-- allow_metadata_inventory_move
-----------------------------------------------
local __allow_metadata_inventory_move = function(pos, from_list, from_index, to_list, to_index, count, player)
	return 0
end


-----------------------------------------------
-- allow_metadata_inventory_put
-----------------------------------------------
local __allow_metadata_inventory_put = function(pos, listname, index, stack, player)
	return 0
end

-----------------------------------------------
-- allow_metadata_inventory_take
-----------------------------------------------
local __allow_metadata_inventory_take = function(pos, listname, index, stack, player)
	return 0
end

-----------------------------------------------
-- register_node - the chest where you put the items
-----------------------------------------------
minetest.register_node("townchest:chest", {
	description = "Building Chest",
	tiles = {"default_chest_top.png", "default_chest_top.png", "default_chest_side.png",
		"default_chest_side.png", "default_chest_side.png", "default_chest_front.png"},
	paramtype2 = "facedir",
	groups = {snappy=2,choppy=2,oddly_breakable_by_hand=2},
	legacy_facedir_simple = true,
	sounds = default.node_sound_wood_defaults(),
	on_construct = __on_construct,
	on_receive_fields = __on_receive_fields,
	after_dig_node = __on_destruct,
	on_punch = __on_punch,
	on_metadata_inventory_put = __on_metadata_inventory_put,
	allow_metadata_inventory_move = __allow_metadata_inventory_move,
	allow_metadata_inventory_put = __allow_metadata_inventory_put,
	allow_metadata_inventory_take = __allow_metadata_inventory_take,
})

--[[
-----------------------------------------------
-- register_abm - builds the building
-----------------------------------------------
minetest.register_abm({
	nodenames = {"townchest:chest"},
	interval = 0.1, --TODO: 0.5
	chance = 1,
	action = __cheststep,
})
]]--


-----------------------------------------------
-- register_lbm - restore all chestinfo
-----------------------------------------------
minetest.register_lbm({
	name = "townchest:chest",
	nodenames = {"townchest:chest"},
	run_at_every_load = true,
	action = __restore
})


-----------------------------------------------
-- register craft recipe for the chest
-----------------------------------------------
minetest.register_craft({
	output = 'townchest:chest',
	recipe = {
		{'default:mese_crystal', 'default:chest_locked', 'default:mese_crystal'},
		{'default:book', 'default:diamond', 'default:book'},
		{'default:mese_crystal', 'default:chest_locked', 'default:mese_crystal'},
	}
})

-- log that we started
minetest.log("action", "[MOD]"..minetest.get_current_modname().." -- loaded from "..townchest.modpath)
