local dprint = townchest.dprint --debug

-- get worldedit parser load_schematic from worldedit mod
dofile(townchest.modpath.."/".."worldedit-serialization.lua")


-----------------------------------------------
-- get files
-- no input parameters
-- returns a table containing buildings
-----------------------------------------------
local __get = function()
	local files = {}
	if os.getenv('HOME')~=nil then
		dprint("use GNU tools to get files")
---		files = io.popen('ls -a "'..townchest.modpath..'/buildings/"'):lines() -- linux/mac native "ls -a"
		files = io.popen('cd "'..townchest.modpath..'/buildings/"; find * -type f'):lines() -- linux/mac native "find"
	else
		dprint("use DOS to get files")
		files = io.popen('dir "'..townchest.modpath..'\\buildings\\*.*" /b'):lines() --windows native "dir /b"
	end

	local i, t = 0, {}
	for filename in files do
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
local __readfile = function(filename)
	local filepath = townchest.modpath.."/buildings/"..filename
	local file, err = io.open(filepath, "rb")
	if err ~= nil then
		dprint("[townchest] error: could not open file \"" .. filepath .. "\"")
		return
	end
	-- load the building starting from the lowest y
	local building_plan = townchest.we_load_schematic(file:read("*a"))
	return building_plan
end


townchest.files = {
	get = __get,
	readfile = __readfile
}
