local handle_schematics = {}

-- receive parameter modpath
local modpath = ...

-- deserialize worldedit savefiles
local worldedit_file = dofile(modpath.."worldedit_file.lua")


handle_schematics.analyze_we_file = function(file)
	-- returning parameters
	local nodenames = {}
	local scm = {}
	local all_meta = {}
	local min_pos = {}
	local max_pos = {}
	local ground_y = -1 --if nothing defined, it is under the building
	local nodecount = 0

	-- helper
	local nodes = worldedit_file.load_schematic(file:read("*a"))
	local nodenames_id = {}
	local ground_id = {}
	local groundnode_count = 0

	-- analyze the file
	for i, ent in ipairs( nodes ) do
		-- get nodename_id and analyze ground elements
		local name_id = nodenames_id[ent.name]
		if not name_id then
			name_id = #nodenames + 1
			nodenames_id[ent.name] = name_id
			nodenames[name_id] = ent.name
			if string.sub(ent.name, 1, 18) == "default:dirt_with_" or
					ent.name == "farming:soil_wet" then
				ground_id[name_id] = true
			end
		end

		-- calculate ground_y value
		if ground_id[name_id] then
			groundnode_count = groundnode_count + 1
			if groundnode_count == 1 then
				ground_y = ent.y
			else
				ground_y = ground_y + (ent.y - ground_y) / groundnode_count
			end
		end

		-- adjust position information
		if not max_pos.x or ent.x > max_pos.x then
			max_pos.x = ent.x
		end
		if not max_pos.y or ent.y > max_pos.y then
			max_pos.y = ent.y
		end
		if not max_pos.z or ent.z > max_pos.z then
			max_pos.z = ent.z
		end
		if not min_pos.x or ent.x < min_pos.x then
			min_pos.x = ent.x
		end
		if not min_pos.y or ent.y < min_pos.y then
			min_pos.y = ent.y
		end
		if not min_pos.z or ent.z < min_pos.z then
			min_pos.z = ent.z
		end

		-- build to scm data tree
		if scm[ent.y] == nil then
			scm[ent.y] = {}
		end
		if scm[ent.y][ent.x] == nil then
			scm[ent.y][ent.x] = {}
		end
		if ent.param2 == nil then
			ent.param2 = 0
		end

		-- metadata is only of intrest if it is not empty
		if( ent.meta and (ent.meta.fields or ent.meta.inventory)) then
			local has_meta = false
			for _,v in pairs( ent.meta.fields ) do
				has_meta = true
				break
			end
			for _,v in pairs(ent.meta.inventory) do
				has_meta = true
				break
			end
			if has_meta ~= true then
				ent.meta = nil
			end
		else
			ent.meta = nil
		end

		scm[ent.y][ent.x][ent.z] = {name_id = name_id, param2 = ent.param2, meta = ent.meta}

		nodecount = nodecount + 1
	end

	return {	min_pos   = min_pos,    -- minimal {x,y,z} vector
				max_pos   = max_pos,    -- maximal {x,y,z} vector
				nodenames = nodenames,  -- nodenames[1] = "default:sample"
				scm_data_cache = scm,   -- scm[y][x][z] = { name_id=, param2=, meta= }
				nodecount = nodecount,  -- integer, count
				ground_y  = ground_y }  -- average ground high
end

return handle_schematics
