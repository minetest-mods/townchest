local dprint = townchest.dprint --debug


townchest.specwidgets = {}


--- temporary provide smartfs as builtin, till the needed changes are upstream
local smartfs = townchest.smartfs
--- temporary end


local _file_open_dialog = function(state)


	local chest = townchest.chest.get(state.location.pos)

	state:size(10,7)
	state:label(0,0,"header","Please select a building")
-- Listbox
	local listbox = state:listbox(0,0.5,10,5,"fileslist")
	for idx, file in ipairs(townchest.files.get()) do
		listbox:addItem(file)
	end

-- Run Button 
	local runbutton = state:button(1,6.5,3,0.5,"open","Load File")
	runbutton:onClick(function(self)
		local file = listbox:getSelectedItem() 
		if file then
			chest:prepare_building_plan(file)
		end
	end)
	
	state:button(5,6.5,2,0.5,"Cancel","Cancel", true)

	return true --successfull build, update needed
end
smartfs.create("file_open", _file_open_dialog)


-----------------------------------------------
-- Status dialog
-----------------------------------------------
local _status = function(state)
	local chest = townchest.chest.get(state.location.pos)
	if not chest.infotext then
		print("BUG: no infotext for status dialog!")
		return false -- no update
	end
	state:size(7,1)
	state:label(0,0,"info",chest.infotext)
	return true --successfull build, update needed
end
smartfs.create("status", _status)



-----------------------------------------------
-- Building status dialog
-----------------------------------------------
local _build_status = function(state)

	-- connect to chest data
	local chest = townchest.chest.get(state.location.pos)

	if not chest.plan then
		print("BUG: no plan in build_status dialog!")
		return false -- no update
	end
	local relative = chest.plan.relative

	-- helper function - disable something if build is in process
	local function set_processing_visibility(the_element)
		if chest.info.npc_build or chest.info.instantbuild then
			the_element:setIsHidden(true)
		else
			the_element:setIsHidden(false)
		end
	end

	-- create screen
	state:size(10,5)
	state:label(1,0.5,"l1","Building "..chest.info.filename.." selected")
	state:label(1,1.0,"l2","Size: "..(relative.max_x-relative.min_x).." x "..(relative.max_z-relative.min_z))
	state:label(1,1.5,"l3","Building high: "..(relative.max_y-relative.min_y).."  Ground high: "..(relative.ground_y-relative.min_y))
	state:label(1,2.0,"l4","Nodes to do: "..chest.plan.building_size)

	-- refresh building button
	local reload_bt = state:button(5,4,3,0.5,"reload_bt", "Reload nodes")
	reload_bt:onClick(function(self, state, player)
		chest:prepare_building_plan(chest.info.filename)
	end)

	set_processing_visibility(reload_bt)

	--Instand build button
	local inst_tg = state:toggle(1,3,3,0.5,"inst_tg",{ "Start instant build", "Stop instant build"})
	inst_tg:onToggle(function(self, state, player)
		if self:getId() == 2 then
			chest.info.instantbuild = true
			chest:instant_build()
		else
			chest.info.instantbuild = nil
		end
		chest:persist_info()
		set_processing_visibility(reload_bt)
	end)
	if chest.info.instantbuild then
		inst_tg:setId(2)
	else
		inst_tg:setId(1)
	end

	-- NPC build button
	local npc_tg = state:toggle(5,3,3,0.5,"npc_tg",{ "Start NPC build", "Stop NPC build"})
	npc_tg:onToggle(function(self, state, player)
		if self:getId() == 2 then
			chest.info.npc_build = true      --is used by NPC
		else
			chest.info.npc_build = nil
		end
		set_processing_visibility(reload_bt)
		chest:persist_info()
	end)
	if chest.info.npc_build then
		npc_tg:setId(2)
	else
		npc_tg:setId(1)
	end

	-- spawn NPC button
	local spawn_bt = state:button(1,4,3,0.5,"spawn_bt", "Spawn NPC")
	spawn_bt:onClick(function(self, state, player)
		local pos = state.location.pos
		minetest.add_entity({x=(pos.x+math.random(0,4)-2),y=(pos.y+math.random(0,2)),z=(pos.z+math.random(0,4)-2)}, "townchest:builder")
	end)

	return true --successfull build, update needed
end
smartfs.create("build_status", _build_status)
