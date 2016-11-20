-- expose api
townchest = {}
townchest.modpath = minetest.get_modpath(minetest.get_current_modname())


-- debug. Used for debug messages. In production the function should be empty
local dprint = function(...)
-- debug print. Comment out the next line if you don't need debug out
	print(unpack(arg))
end
local dprint_off = function(...)
end
townchest.dprint = dprint
townchest.dprint_off = dprint_off

-- UI tools/ formspec
townchest.smartfs = dofile(townchest.modpath.."/".."smartfs.lua")
dofile(townchest.modpath.."/".."smartfs-forms.lua")

local smartfs = townchest.smartfs

-- The Chest
dofile(townchest.modpath.."/".."chest.lua")

-- Reading building files (WorldEdit)
dofile(townchest.modpath.."/".."files.lua")

-- Nodes mapping
dofile(townchest.modpath.."/".."nodes.lua")

-- building plan
dofile(townchest.modpath.."/".."plan.lua")

-- NPC's
dofile(townchest.modpath.."/".."npcf-worker.lua")


-----------------------------------------------
-- __cheststep - triggered building step
-----------------------------------------------
--[[
local __cheststep = function(pos)
	local chest = townchest.chest.get(pos)
	chest:do_cheststep()
end
]]

-----------------------------------------------
-- on_construct - if the chest is placed
-----------------------------------------------
local __on_construct = function(pos)
	local chest = townchest.chest.create(pos) --create new chest utils instance
	chest:set_form("file_open")
end

-----------------------------------------------
-- on_destruct - if the chest destroyed
-----------------------------------------------
local __on_destruct = function(pos)
	dprint("on_destruct")
	-- remove all cached chest references
	local key = minetest.pos_to_string(pos)
	townchest.chest.list[key] = nil --delete old reference
end

-----------------------------------------------
-- restore - called in lbm, restore chest internal data if the server was restarted
-----------------------------------------------
local __restore = function(pos, node)
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
	on_receive_fields = function(pos, formname, fields, sender)
		local chest = townchest.chest.get(pos)
		smartfs.nodemeta_on_receive_fields(pos, formname, fields, sender)
		chest.meta:set_string("chestinfo", minetest.serialize(chest.info)) --save chest data
	end,
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
	interval = 1,
	chance = 1,
	action = __cheststep,
})
]]

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
