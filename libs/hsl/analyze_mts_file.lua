local handle_schematics = {}

--[[ taken from src/mg_schematic.cpp:
        Minetest Schematic File Format

        All values are stored in big-endian byte order.
        [u32] signature: 'MTSM'
        [u16] version: 3
        [u16] size X
        [u16] size Y
        [u16] size Z
        For each Y:
                [u8] slice probability value
        [Name-ID table] Name ID Mapping Table
                [u16] name-id count
                For each name-id mapping:
                        [u16] name length
                        [u8[] ] name
        ZLib deflated {
        For each node in schematic:  (for z, y, x)
                [u16] content
        For each node in schematic:
                [u8] probability of occurance (param1)
        For each node in schematic:
                [u8] param2
        }

        Version changes:
        1 - Initial version
        2 - Fixed messy never/always place; 0 probability is now never, 0xFF is always
        3 - Added y-slice probabilities; this allows for variable height structures
--]]

--handle_schematics = {}

-- taken from https://github.com/MirceaKitsune/minetest_mods_structures/blob/master/structures_io.lua (Taokis Sructures I/O mod)
-- gets the size of a structure file
-- nodenames: contains all the node names that are used in the schematic
-- on_constr: lists all the node names for which on_construct has to be called after placement of the schematic
handle_schematics.analyze_mts_file = function(file)
	local size = { x = 0, y = 0, z = 0, version = 0 }
	local version = 0;

	-- thanks to sfan5 for this advanced code that reads the size from schematic files
	local read_s16 = function(fi)
		return string.byte(fi:read(1)) * 256 + string.byte(fi:read(1))
	end

	local function get_schematic_size(f)
		-- make sure those are the first 4 characters, otherwise this might be a corrupt file
		if f:read(4) ~= "MTSM" then
			return nil
		end
		-- advance 2 more characters
		local version = read_s16(f); --f:read(2)
		-- the next characters here are our size, read them
		return read_s16(f), read_s16(f), read_s16(f), version
	end

	size.x, size.y, size.z, size.version = get_schematic_size(file)
	
	-- read the slice probability for each y value that was introduced in version 3
	if( size.version >= 3 ) then
		-- the probability is not very intresting for buildings so we just skip it
		file:read( size.y )
	end

	-- this list is not yet used for anything
	local nodenames = {}
	local ground_id = {}
	local is_air = 0

	-- after that: read_s16 (2 bytes) to find out how many diffrent nodenames (node_name_count) are present in the file
	local node_name_count = read_s16( file )

	for i = 1, node_name_count do
		-- the length of the next name
		local name_length = read_s16( file )
		-- the text of the next name
		local name_text = file:read( name_length )
		nodenames[i] = name_text
		if string.sub(name_text, 1, 18) == "default:dirt_with_" or
				name_text == "farming:soil_wet" then
			ground_id[i] = true
		elseif( name_text == 'air' ) then
			is_air = i;
		end
	end

	-- decompression was recently added; if it is not yet present, we need to use normal place_schematic
	if( minetest.decompress == nil) then
		file.close(file);
		return nil; -- normal place_schematic is no longer supported as minetest.decompress is now part of the release version of minetest
	end

	local compressed_data = file:read( "*all" );
	local data_string = minetest.decompress(compressed_data, "deflate" );
	file.close(file)

	local p2offset = (size.x*size.y*size.z)*3;
	local i = 1;

	local scm = {};
	local min_pos = {}
	local max_pos = {}
	local nodecount = 0
	local ground_y = 0
	local groundnode_count = 0

	for z = 1, size.z do
		for y = 1, size.y do
			for x = 1, size.x do
				local id = string.byte( data_string, i ) * 256 + string.byte( data_string, i+1 );
				i = i + 2;
				local p2 = string.byte( data_string, p2offset + math.floor(i/2));
				id = id+1;
				if( id ~= is_air ) then
					-- use node
					if( not( scm[y] )) then
						scm[y] = {};
					end
					if( not( scm[y][x] )) then
						scm[y][x] = {};
					end
					scm[y][x][z] = {name_id = id, param2 = p2};
					nodecount = nodecount + 1

					-- adjust position information
					if not max_pos.x or x > max_pos.x then
						max_pos.x = x
					end
					if not max_pos.y or y > max_pos.y then
						max_pos.y = y
					end
					if not max_pos.z or z > max_pos.z then
						max_pos.z = z
					end
					if not min_pos.x or x < min_pos.x then
						min_pos.x = x
					end
					if not min_pos.y or y < min_pos.y then
						min_pos.y = y
					end
					if not min_pos.z or z < min_pos.z then
						min_pos.z = z
					end

					-- calculate ground_y value
					if ground_id[id] then
						groundnode_count = groundnode_count + 1
						if groundnode_count == 1 then
							ground_y = y
						else
							ground_y = ground_y + (y - ground_y) / groundnode_count
						end
					end
				end
			end
		end
	end

	return {	min_pos   = min_pos,    -- minimal {x,y,z} vector
				max_pos   = max_pos,    -- maximal {x,y,z} vector
				nodenames = nodenames,  -- nodenames[1] = "default:sample"
				scm_data_cache = scm,   -- scm[y][x][z] = { name_id, ent.param2 }
				nodecount = nodecount,  -- integer, count
				ground_y  = ground_y }  -- average ground high
end

return handle_schematics
