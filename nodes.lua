local dprint = townchest.dprint_off --debug

local _c_free_item = "default:cloud"

-- Fallback nodes replacement of unknown nodes
-- Maybe it is beter to use aliases for unknown notes. But anyway
-- TODO: should be editable in game trough a nice gui, to customize the building before build
local __map_unknown = function(self)

	local map = townchest.nodes.unknown_nodes_data[self.name]
	if not map or map.name == self.name then -- no fallback mapping. don't use the node
		dprint("mapping failed:", self.name, dump(map))
		print("unknown node in building", self.name)
		return nil
	end

	dprint("mapped", self.name, "to", self.name)
	local mappednode = townchest.nodes.new(self)
		mappednode.name = map.name -- must be there!

	if map.meta then
		if not mappednode.meta then
			mappednode.meta = {}
		end
		for k, v in pairs(map.meta) do
			mappednode.meta[k] = v
		end
	end

	if map.param1 then
		if type(map.param1) == "function" then
			dprint("map param1 by function")
			mappednode.param1 = map.param1(node)
		else
			mappednode.param1 = map.param1
			dprint("map param1 by value")
		end
	end

	if map.param2 then
		if type(map.param2) == "function" then
			dprint("map param2 by function")
			mappednode.param2 = map.param2(map)
		else
			dprint("map param2 by value")
			mappednode.param2 = map.param2
		end
	end

	return mappednode
end


-- Nodes replacement to customizie buildings
-- TODO: should be editable in game trough a nice gui, to customize the building before build
local __customize = function(self)
	local map = townchest.nodes.customize_data[self.name]
	if not map then -- no mapping. return unchanged
		return self
	end
--	dprint("map", self.name, "to", map.name, map.matname)
	local mappednode = townchest.nodes.new(self)
	if map.name then
		mappednode.name = map.name
	end
	if map.matname then
		mappednode.matname = map.matname
	end

	if map.meta then
		if not mappednode.meta then
			mappednode.meta = {}
		end
		for k, v in pairs(map.meta) do
			mappednode.meta[k] = v
		end
	end
	return mappednode
end



-----------------------------------------------
-- towntest_chest.mapping.mapnode Take filters and actions on nodes before building. Currently the payment item determination and check for registred node only
-- node - Node (from file) to check if buildable and payable
-- return - node with enhanced informations
-----------------------------------------------
local __map = function(self)

	local node_chk = minetest.registered_nodes[self.name]

	if not node_chk then
		local fallbacknode = self:map_unknown()
		if fallbacknode then
			return fallbacknode:map()
		end
	else
		-- known node Map them?
		local customizednode = self:customize()

		if customizednode.name == "" then --disabled by mapping
			return nil
		end

		if not customizednode.matname then --no matname override customizied.

			--Check for price or if it is free
			local recipe = minetest.get_craft_recipe(node_chk.name)
			if (node_chk.groups.not_in_creative_inventory and --not in creative
			    not (node_chk.groups.not_in_creative_inventory == 0) and
			   (not recipe or not recipe.items))              --and not craftable
			 or
			   (not node_chk.description or node_chk.description == "") then -- no description
				if node_chk.drop and node_chk.drop ~= "" then
				-- use possible drop as payment
					if type(node_chk.drop) == "table" then -- drop table
						customizednode.matname = node_chk.drop[1]  -- use the first one
					else
						customizednode.matname = node_chk.drop
					end
				else --something not supported, but known
					customizednode.matname = _c_free_item -- will be build for free. they are something like doors:hidden or second part of coffee lrfurn:coffeetable_back
				end
			else -- build for payment the 1:1
				customizednode.matname = customizednode.name
			end
		end
		return customizednode
	end
end

-----------------------------------------------
-- is_equal_meta - compare meta information of 2 nodes
-- name - Node name to check and map
-- return - item name used as payment
-----------------------------------------------
local __is_equal_meta = function(a,b)
	local typa = type(a)
	local typb = type(b)
	if typa ~= typb then
		return false
	end

	if typa == "table" then
		if #a ~= #b then
			return false
		else
			for i,v in ipairs(a) do
				if not is_equal_meta(a[i],b[i]) then
					return false
				end
			end
			return true
		end
	else
		if a == b then
			return true
		end
	end
end

-- door compatibility. Seems the old doors was facedir and now the wallmounted values should be used
local __param2_wallmounted_to_facedir = function(self)
	if self.param2 == 0 then     -- +y?
		return 0
	elseif self.param2 == 1 then -- -y?
		return 1
	elseif self.param2 == 2 then --unsure
		return 3
	elseif self.param2 == 3 then --unsure
		return 1
	elseif self.param2 == 4 then --unsure
		return 2
	elseif self.param2 == 5 then --unsure
		return 0
	end
end


local __id = function(this)
	return this.x..","..this.y..","..this.z
end



local u = {}
-- Fallback nodes replacement of unknown nodes
-- Maybe it is beter to use aliases for unknown notes. But anyway
u["xpanes:pane_glass_10"] = { name = "xpanes:pane_10" }
u["xpanes:pane_glass_5"]  = { name = "xpanes:pane_5" }
u["beds:bed_top_blue"]    = { name = "beds:bed_top" }
u["beds:bed_bottom_blue"] = { name = "beds:bed_bottom" }

u["homedecor:table_lamp_max"] = { name = "homedecor:table_lamp_white_max" }
u["homedecor:refrigerator"]   = { name = "homedecor:refrigerator_steel" }

u["ethereal:green_dirt"] = { name = "default:dirt_with_grass" }

u["doors:door_wood_b_c"] = {name = "doors:door_wood_b", {["meta"] = {["fields"] = {["state"] = "0"}}},param2 = __param2_wallmounted_to_facedir} --closed
u["doors:door_wood_b_o"] = {name = "doors:door_wood_b", {["meta"] = {["fields"] = {["state"] = "1"}}},param2 = __param2_wallmounted_to_facedir} --open
u["doors:door_wood_b_1"] = {name = "doors:door_wood_b", {["meta"] = {["fields"] = {["state"] = "0"}}}} --closed
u["doors:door_wood_b_2"] = {name = "doors:door_wood_b", {["meta"] = {["fields"] = {["state"] = "3"}}}} --closed / reversed ??
u["doors:door_wood_a_c"] = {name = "doors:hidden" }
u["doors:door_wood_a_o"] = {name = "doors:hidden" }
u["doors:door_wood_t_1"] = {name = "doors:hidden" }
u["doors:door_wood_t_2"] = {name = "doors:hidden" }

u["doors:door_glass_b_c"] = {name = "doors:door_glass_b", {["meta"] = {["fields"] = {["state"] = "0"}}},param2 = __param2_wallmounted_to_facedir} --closed
u["doors:door_glass_b_o"] = {name = "doors:door_glass_b", {["meta"] = {["fields"] = {["state"] = "1"}}},param2 = __param2_wallmounted_to_facedir} --open
u["doors:door_glass_b_1"] = {name = "doors:door_glass_b", {["meta"] = {["fields"] = {["state"] = "0"}}}} --closed
u["doors:door_glass_b_2"] = {name = "doors:door_glass_b", {["meta"] = {["fields"] = {["state"] = "3"}}}} --closed / reversed ??
u["doors:door_glass_a_c"] = {name = "doors:hidden" }
u["doors:door_glass_a_o"] = {name = "doors:hidden" }
u["doors:door_glass_t_1"] = {name = "doors:hidden" }
u["doors:door_glass_t_2"] = {name = "doors:hidden" }

u["doors:door_steel_b_c"] = {name = "doors:door_steel_b", {["meta"] = {["fields"] = {["state"] = "0"}}},param2 = __param2_wallmounted_to_facedir} --closed
u["doors:door_steel_b_o"] = {name = "doors:door_steel_b", {["meta"] = {["fields"] = {["state"] = "1"}}},param2 = __param2_wallmounted_to_facedir} --open
u["doors:door_steel_b_1"] = {name = "doors:door_steel_b", {["meta"] = {["fields"] = {["state"] = "0"}}}} --closed
u["doors:door_steel_b_2"] = {name = "doors:door_steel_b", {["meta"] = {["fields"] = {["state"] = "3"}}}} --closed / reversed ??
u["doors:door_steel_a_c"] = {name = "doors:hidden" }
u["doors:door_steel_a_o"] = {name = "doors:hidden" }
u["doors:door_steel_t_1"] = {name = "doors:hidden" }
u["doors:door_steel_t_2"] = {name = "doors:hidden" }


local c = {}
-- "name" and "matname" are optional.
-- if name is missed it will not be changed
-- if matname is missed it will be determinated as usual (from changed name)
-- a crazy sample is: instead of cobble place goldblock, use wood as payment
-- c["default:cobble"] = { name = "default:goldblock", matname = "default:wood" }

c["beds:bed_top"] = { matname = _c_free_item }  -- the bottom of the bed is payed, so buld the top for free

-- it is hard to get a source in survival, so we use buckets. Note, the bucket is lost after usage by NPC
c["default:lava_source"]        = { matname = "bucket:bucket_lava" }
c["default:river_water_source"] = { matname = "bucket:bucket_river_water" }
c["default:water_source"]       = { matname = "bucket:bucket_water" }

-- does not sense to set flowing water because it flow away without the source (and will be generated trough source)
c["default:water_flowing"]       = { name = "" }
c["default:lava_flowing"]        = { name = "" }
c["default:river_water_flowing"] = { name = "" }

-- pay different dirt types by the sane dirt
c["default:dirt_with_dry_grass"] = { matname = "default:dirt" }
c["default:dirt_with_grass"]     = { matname = "default:dirt" }
c["default:dirt_with_snow"]      = { matname = "default:dirt" }


townchest.nodes = {
-- We need a free item that always available to get visible working on them
	c_free_item = _c_free_item,
	unknown_nodes_data = u,
	customize_data = c,
	is_equal_meta = __is_equal_meta
}

townchest.nodes.new = function(nodelike)
	local this = {}
	if nodelike then
		this = nodelike --!by reference It will remain the same node, but just 
	end
	this.id = __id
	this.map_unknown = __map_unknown
	this.customize = __customize
	this.map = __map
	this.param2_wallmounted_to_facedir = __param2_wallmounted_to_facedir
	return this
end
