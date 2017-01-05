--[[ handle_schematics library
	extracted from https://github.com/Sokomine/handle_schematics
	see https://github.com/Sokomine/handle_schematics/issues/7
]]


local hsl = {}

-- temporary path assignment till the hsl is own mod
local modpath = minetest.get_modpath(minetest.get_current_modname())
modpath = modpath..'/libs/hsl/'

-- adds worldedit_file.* namespace
-- deserialize worldedit savefiles
 dofile(modpath.."worldedit_file.lua")

-- uses handle_schematics.* namespace
-- reads and analyzes .mts files (minetest schematics)
dofile(modpath.."/analyze_mts_file.lua") 

-- reads and analyzes worldedit files
dofile(modpath.."/analyze_we_file.lua")

-- reads and analyzes Minecraft schematic files
dofile(modpath.."/translate_nodenames_for_mc_schematic.lua")
dofile(modpath.."/analyze_mc_schematic_file.lua")

-- handles rotation and mirroring
dofile(modpath.."/rotate.lua")

-- count nodes, take param2 into account for rotation etc.
dofile(modpath.."/handle_schematics_misc.lua") 

-- store and restore metadata
dofile(modpath.."/save_restore.lua");
dofile(modpath.."/handle_schematics_meta.lua");