local dprint = townchest.dprint_off --debug
--local dprint = townchest.dprint


local mapping = {}
townchest.mapping  = mapping

-- visual for cost_item free for payment
mapping.c_free_item = "default:cloud"


-----------------------------------------------
-- door compatibility. Seems the old doors was facedir and now the wallmounted values should be used
-----------------------------------------------
local function __param2_wallmounted_to_facedir(nodeinfo, pos, wpos)
	if nodeinfo.param2 == 0 then     -- +y?
		nodeinfo.param2 = 0
	elseif nodeinfo.param2 == 1 then -- -y?
		nodeinfo.param2 = 1
	elseif nodeinfo.param2 == 2 then --unsure
		nodeinfo.param2 = 3
	elseif nodeinfo.param2 == 3 then --unsure
		nodeinfo.param2 = 1
	elseif nodeinfo.param2 == 4 then --unsure
		nodeinfo.param2 = 2
	elseif nodeinfo.param2 == 5 then --unsure
		nodeinfo.param2 = 0
	end
end

local u = {}
local unknown_nodes_data = u
-- Fallback nodes replacement of unknown nodes
-- Maybe it is beter to use aliases for unknown notes. But anyway
u["xpanes:pane_glass_10"] = { name = "xpanes:pane_10" }
u["xpanes:pane_glass_5"]  = { name = "xpanes:pane_5" }
u["beds:bed_top_blue"]    = { name = "beds:bed_top" }
u["beds:bed_bottom_blue"] = { name = "beds:bed_bottom" }

u["homedecor:table_lamp_max"] = { name = "homedecor:table_lamp_white_max" }
u["homedecor:refrigerator"]   = { name = "homedecor:refrigerator_steel" }

u["ethereal:green_dirt"] = { name = "default:dirt_with_grass" }

u["doors:door_wood_b_c"] = {name = "doors:door_wood_b", {["meta"] = {["fields"] = {["state"] = "0"}}}, custom_function = __param2_wallmounted_to_facedir } --closed
u["doors:door_wood_b_o"] = {name = "doors:door_wood_b", {["meta"] = {["fields"] = {["state"] = "1"}}}, custom_function = __param2_wallmounted_to_facedir } --open
u["doors:door_wood_b_1"] = {name = "doors:door_wood_b", {["meta"] = {["fields"] = {["state"] = "0"}}}} --closed
u["doors:door_wood_b_2"] = {name = "doors:door_wood_b", {["meta"] = {["fields"] = {["state"] = "3"}}}} --closed / reversed ??
u["doors:door_wood_a_c"] = {name = "doors:hidden" }
u["doors:door_wood_a_o"] = {name = "doors:hidden" }
u["doors:door_wood_t_1"] = {name = "doors:hidden" }
u["doors:door_wood_t_2"] = {name = "doors:hidden" }

u["doors:door_glass_b_c"] = {name = "doors:door_glass_b", {["meta"] = {["fields"] = {["state"] = "0"}}}, custom_function = __param2_wallmounted_to_facedir } --closed
u["doors:door_glass_b_o"] = {name = "doors:door_glass_b", {["meta"] = {["fields"] = {["state"] = "1"}}}, custom_function = __param2_wallmounted_to_facedir } --open
u["doors:door_glass_b_1"] = {name = "doors:door_glass_b", {["meta"] = {["fields"] = {["state"] = "0"}}}} --closed
u["doors:door_glass_b_2"] = {name = "doors:door_glass_b", {["meta"] = {["fields"] = {["state"] = "3"}}}} --closed / reversed ??
u["doors:door_glass_a_c"] = {name = "doors:hidden" }
u["doors:door_glass_a_o"] = {name = "doors:hidden" }
u["doors:door_glass_t_1"] = {name = "doors:hidden" }
u["doors:door_glass_t_2"] = {name = "doors:hidden" }

u["doors:door_steel_b_c"] = {name = "doors:door_steel_b", {["meta"] = {["fields"] = {["state"] = "0"}}}, custom_function = __param2_wallmounted_to_facedir } --closed
u["doors:door_steel_b_o"] = {name = "doors:door_steel_b", {["meta"] = {["fields"] = {["state"] = "1"}}}, custom_function = __param2_wallmounted_to_facedir } --open
u["doors:door_steel_b_1"] = {name = "doors:door_steel_b", {["meta"] = {["fields"] = {["state"] = "0"}}}} --closed
u["doors:door_steel_b_2"] = {name = "doors:door_steel_b", {["meta"] = {["fields"] = {["state"] = "3"}}}} --closed / reversed ??
u["doors:door_steel_a_c"] = {name = "doors:hidden" }
u["doors:door_steel_a_o"] = {name = "doors:hidden" }
u["doors:door_steel_t_1"] = {name = "doors:hidden" }
u["doors:door_steel_t_2"] = {name = "doors:hidden" }


local c = {}
local default_replacements = c
-- "name" and "cost_item" are optional.
-- if name is missed it will not be changed
-- if cost_item is missed it will be determinated as usual (from changed name)
-- a crazy sample is: instead of cobble place goldblock, use wood as payment
-- c["default:cobble"] = { name = "default:goldblock", cost_item = "default:wood" }

c["beds:bed_top"] = { cost_item = mapping.c_free_item }  -- the bottom of the bed is payed, so buld the top for free

-- it is hard to get a source in survival, so we use buckets. Note, the bucket is lost after usage by NPC
c["default:lava_source"]        = { cost_item = "bucket:bucket_lava" }
c["default:river_water_source"] = { cost_item = "bucket:bucket_river_water" }
c["default:water_source"]       = { cost_item = "bucket:bucket_water" }

-- does not sense to set flowing water because it flow away without the source (and will be generated trough source)
c["default:water_flowing"]       = { name = "" }
c["default:lava_flowing"]        = { name = "" }
c["default:river_water_flowing"] = { name = "" }

-- pay different dirt types by the sane dirt
c["default:dirt_with_dry_grass"] = { cost_item = "default:dirt" }
c["default:dirt_with_grass"]     = { cost_item = "default:dirt" }
c["default:dirt_with_snow"]      = { cost_item = "default:dirt" }


-----------------------------------------------
-- copy table of mapping entry
-----------------------------------------------
function mapping.merge_map_entry(entry1, entry2)
	if entry2 then
		return {name = entry1.name or entry2.name, --not a typo: used to merge fallback to mapped data. The mapped data is preferred
				node_def = entry1.node_def or entry2.node_def,
				content_id = entry1.content_id or entry2.content_id,
				param2 = entry2.param2 or entry1.param2,
				meta = entry2.meta or entry1.meta,
				custom_function = entry2.custom_function or entry1.custom_function,
				cost_item = entry2.cost_item or entry1.cost_item,
				}
	else
		return {name = entry1.name,
				content_id = entry1.content_id,
				node_def = entry1.node_def,
				param2 = entry1.param2,
				meta = entry1.meta,
				custom_function = entry1.custom_function,
				cost_item = entry1.cost_item}
	end
end

	-----------------------------------------------
	-- is_equal_meta - compare meta information of 2 nodes
	-- name - Node name to check and map
	-- return - item name used as payment
	-----------------------------------------------
function mapping.is_equal_meta(a,b)
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
				if not mapping.is_equal_meta(a[i],b[i]) then
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

-----------------------------------------------
-- Fallback nodes replacement of unknown nodes
-----------------------------------------------
function mapping.map_unknown(name)
	local map = unknown_nodes_data[name]
	if not map or map.name == name then -- no fallback mapping. don't use the node
		dprint("mapping failed:", name, dump(map))
		print("unknown nodes in building", name)
		return nil
	end

	dprint("mapped", name, "to", map.name)
	return mapping.merge_map_entry(map)
end

-----------------------------------------------
-- Take filters and actions on nodes before building
-----------------------------------------------
function mapping.map_name(name)
-- get mapped registred node name for further mappings
	local node_chk = minetest.registered_nodes[name]

	--do fallback mapping if not registred node
	if not node_chk then
		local fallback = mapping.map_unknown(name)
		if fallback then
			dprint("map fallback:", dump(fallback))
			local fbmapped = mapping.map_name(fallback.name)
			if fbmapped then
				return mapping.merge_map_entry(fbmapped, fallback) --merge fallback values into the mapped node
			end
		end
		dprint("unmapped node", name)
		return
	end

	-- get default replacement
	local map = default_replacements[name]
	local mr -- mapped return table
	if not map then
		mr = {}
		mr.name = name
		mr.node_def = node_chk
	else
		mr = mapping.merge_map_entry(map)
		if mr.name == nil then
			mr.name = name
		end
	end

	--disabled by mapping
	if mr.name == "" then
		return nil
	end

	mr.node_def = minetest.registered_nodes[mr.name]

	-- determine cost_item
	dprint("map", name, "to", mr.name, mr.cost_item)
	if not mr.cost_item then

		--Check for price or if it is free
		local recipe = minetest.get_craft_recipe(mr.name)
		if (mr.node_def.groups.not_in_creative_inventory and --not in creative
				not (mr.node_def.groups.not_in_creative_inventory == 0) and
				(not recipe or not recipe.items)) --and not craftable

		 or (not mr.node_def.description or mr.node_def.description == "") then -- no description
			if mr.node_def.drop and mr.node_def.drop ~= "" then
			-- use possible drop as payment
				if type(mr.node_def.drop) == "table" then -- drop table
					mr.cost_item = mr.node_def.drop[1] -- use the first one
				else
					mr.cost_item = mr.node_def.drop
				end
			else --something not supported, but known
				mr.cost_item = mapping.c_free_item -- will be build for free. they are something like doors:hidden or second part of coffee lrfurn:coffeetable_back
			end
		else -- build for payment the 1:1
			mr.cost_item = mr.name
		end
	end

	mr.content_id = minetest.get_content_id(mr.name)
	return mr
end

-----------------------------------------------
-- create a "mappednodes" using the data from analyze_* files
-----------------------------------------------
function mapping.do_mapping(data)
	data.mappednodes = {}
	for node_id, name in ipairs(data.nodenames) do
		data.mappednodes[node_id] = mapping.map_name(name)
	end
end
