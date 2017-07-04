local dprint = townchest.dprint_off --debug

files = {}

-----------------------------------------------
-- get files
-- no input parameters
-- returns a table containing buildings
-----------------------------------------------
function files.get()
	local files = minetest.get_dir_list(townchest.modpath..'/buildings/', false) or {}
	local i, t = 0, {}
	for _,filename in ipairs(files) do
		if filename ~= "." and filename ~= ".." then
			i = i + 1
			t[i] = filename
		end
	end

	table.sort(t,function(a,b) return a<b end)
	return t
end

-----------------------------------------------
-- read file
-- filename - the building file to load
-- return - WE-Shema, containing the pos and nodes to build
-----------------------------------------------
function files.readfile(filename)
	local file = townchest.hsl.save_restore.file_access(townchest.modpath.."/buildings/"..filename, "r")
	if not file then
		dprint("[townchest] error: could not open file \"" .. filename .. "\"")
		return
	end

	local building_info

	-- different file types
	if string.find( filename, '.mts',  -4 ) then
		return townchest.hsl.analyze_mts.analyze_mts_file(file)
	end
	if string.find( filename, '.we',   -3 ) or string.find( filename, '.wem',  -4 ) then
		return townchest.hsl.analyze_we.analyze_we_file(file)
	end
end

------------------------------------------
-- return the files methods to the caller
return files
