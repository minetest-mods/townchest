local dprint = townchest.dprint_off --debug

townchest.specwidgets = {}

--- temporary provide smartfs as builtin, till the needed changes are upstream
local smartfs = townchest.smartfs
--- temporary end

-----------------------------------------------
-- file open dialog form / (tabbed)
-----------------------------------------------
local _file_open_dialog = function(state)
	--connect to chest object for data
	local chest = townchest.chest.get(state.location.pos)

	--set screen size
	state:size(12,8)

	-- tabbed view controller
	local tab_controller = {
		_tabs = {},
		active_name = nil,
		set_active = function(self, tabname)
			for name, def in pairs(self._tabs) do
				if name == tabname then
					def.button:setBackground("default_gold_block.png")
					def.view:setVisible(true)
				else
					def.button:setBackground(nil)
					def.view:setVisible(false)
				end
			end
			self.active_name = tabname
		end,
		tab_add = function(self, name, def)
			def.viewstate:size(12,6) --size of tab view
			self._tabs[name] = def
		end,
		get_active_name = function(self)
			return self.active_name
		end,
	}

-----------------------------------------------
-- file selection tab
-----------------------------------------------
	local tab1 = {}
	tab1.button = state:button(0,0,2,1,"tab1_btn","Buildings")
	tab1.button:onClick(function(self)
		tab_controller:set_active("tab1")
	end)
	tab1.view = state:container(0,1,"tab1_view")
	tab1.viewstate = tab1.view:getContainerState()
	-- file selection tab view state
	tab1.viewstate:label(0,0,"header","Please select a building")
	local listbox = tab1.viewstate:listbox(0,0.5,6,5.5,"fileslist")
	for idx, file in ipairs(townchest.files_get()) do
		listbox:addItem(file)
	end
	tab_controller:tab_add("tab1", tab1)

-----------------------------------------------
-- Simple form building tab
-----------------------------------------------
	-- Tasks tab button
	local tab2 = {}
	tab2.button = state:button(2,0,2,1,"tab2_btn","Tasks")
	tab2.button:onClick(function(self)
		tab_controller:set_active("tab2")
	end)
	tab2.view = state:container(0,1,"tab2_view")
	tab2.viewstate = tab2.view:getContainerState()
	-- Tasks tab view state
	tab2.viewstate:label(0,0.2,"header","Build simple form")
	local variant = tab2.viewstate:dropdown(3.5,0.2,4,0.5,"variant", 1)
	variant:addItem("Fill with air") -- 1
	variant:addItem("Fill with stone") -- 2
	variant:addItem("Build a box") -- 3
	variant:addItem("Build a plate") -- 4

	local field_x = tab2.viewstate:field(0,2,2,0.5,"x","width (x)")
	local field_y = tab2.viewstate:field(2,2,2,0.5,"y","high (y)")
	local field_z = tab2.viewstate:field(4,2,2,0.5,"z","width (z)")

	tab_controller:tab_add("tab2", tab2)

-----------------------------------------------
-- NPC control tab
-----------------------------------------------
	if minetest.global_exists("schemlib_builder_npcf") then
		local tab3 = {}
		tab3.button = state:button(4,0,2,1,"tab3_btn","NPC-Settings")
		tab3.button:onClick(function(self)
			tab_controller:set_active("tab3")
		end)
		tab3.view = state:container(0,1,"tab3_view")
		tab3.viewstate = tab3.view:getContainerState()
		-- file selection tab view state
		tab3.viewstate:label(0,0,"header","Configure the NPC mod settings")
		tab3.viewstate:label(0,0.5,"header2","0 = disabled, 1 = enabled >1 enabled with rarity")

		local max_pause_duration = tab3.viewstate:field(1,2,2,0.5,"pause","Pause:",schemlib_builder_npcf.max_pause_duration)
		max_pause_duration:setText(tostring(schemlib_builder_npcf.max_pause_duration))
		local architect_rarity = tab3.viewstate:field(1,3,2,0.5,"arch","Own buildings creation:",schemlib_builder_npcf.architect_rarity)
		architect_rarity:setText(tostring(schemlib_builder_npcf.architect_rarity))
		local walk_around_rarity = tab3.viewstate:field(1,4,2,0.5,"walkaround","Walk around:",schemlib_builder_npcf.walk_around_rarity)
		walk_around_rarity:setText(tostring(schemlib_builder_npcf.walk_around_rarity))
		local apply_btn = tab3.viewstate:button(0,5,2,1,"apply","Apply")
		apply_btn:onClick(function(self)
			schemlib_builder_npcf.max_pause_duration = tonumber(max_pause_duration:getText()) or schemlib_builder_npcf.max_pause_duration
			schemlib_builder_npcf.architect_rarity = tonumber(architect_rarity:getText()) or schemlib_builder_npcf.architect_rarity
			schemlib_builder_npcf.walk_around_rarity = tonumber(walk_around_rarity:getText()) or schemlib_builder_npcf.walk_around_rarity
		end)
		tab_controller:tab_add("tab3", tab3)
	end

	--process all inputs
	state:onInput(function(self, fields)
		chest.info.genblock.x = tonumber(field_x:getText())
		chest.info.genblock.y = tonumber(field_y:getText())
		chest.info.genblock.z = tonumber(field_z:getText())
		chest.info.genblock.variant = variant:getSelected()
		chest.info.genblock.variant_name = variant:getSelectedItem()
		chest:persist_info()
	end)


-- Run Button 
	local runbutton = state:button(0,7.5,2,0.5,"load","Load")
	runbutton:onClick(function(self)
		local selected_tab = tab_controller:get_active_name()
		if selected_tab == "tab1" then
			chest.info.filename = listbox:getSelectedItem() 
			if chest.info.filename then
				chest:set_rawdata("file")
			end
		elseif selected_tab == "tab2" then
			chest:set_rawdata("generate")
		end
	end)

	state:button(10,7.5,2,0.5,"Cancel","Cancel", true)

	-- set default values
	tab_controller:set_active("tab1") --default tab

	if not chest.info.genblock then
		chest.info.genblock = {}
	end
	field_x:setText(tostring(chest.info.genblock.x or 1))
	field_y:setText(tostring(chest.info.genblock.y or 1))
	field_z:setText(tostring(chest.info.genblock.z or 1))
	variant:setSelected(chest.info.genblock.variant or 1)

	--successfull build, update needed
	return true
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
	state:label(0,0,"info", chest.infotext)
	return true --successfull build, update needed
end
smartfs.create("status", _status)

-----------------------------------------------
-- Building status dialog
-----------------------------------------------
local _build_status = function(state)
	-- local reference to function defined at end of this function
	local set_dynamic_values

	-- connect to chest data
	local chest = townchest.chest.get(state.location.pos)

	if not chest.plan then
		print("BUG: no plan in build_status dialog!")
		return false -- no update
	end

	-- create screen
	state:size(10,5)
	local l1 = state:label(1,0.5,"l1","set in set_dynamic_values()")
	local l2 = state:label(1,1.0,"l2","set static at bottom")
	local l3 = state:label(1,1.5,"l3","set static at bottom")
	local l4 = state:label(1,2.0,"l4","set static at bottom")

	--Instand build button
	local inst_tg = state:toggle(1,3,3,0.5,"inst_tg",{ "Start instant build", "Stop instant build"})
	inst_tg:onToggle(function(self, state, player)
		if self:getId() == 2 then
			chest.info.instantbuild = true
			chest.plan:set_status("build")
			chest:run_async(chest.instant_build_chunk)
		else
			chest.info.instantbuild = false
		end
		set_dynamic_values()
		chest:persist_info()
	end)

	-- refresh building button
	local reload_bt = state:button(5,3,3,0.5,"reload_bt", "Reload nodes")
	reload_bt:onClick(function(self, state, player)
		chest:set_rawdata(chest.info.taskname)
	end)

	-- NPC build button
	local npc_tg
	if townchest.npc.supported then
		npc_tg = state:toggle(1,4,3,0.5,"npc_tg",{ "Start NPC build", "Stop NPC build"})
		npc_tg:onToggle(function(self, state, player)
			if self:getId() == 2 then
				chest.info.npc_build = true
				chest.plan:set_status("build")
				townchest.npc.enable_build(chest.plan)
			else
				chest.info.npc_build = false
				townchest.npc.disable_build(chest.plan)
			end
			set_dynamic_values()
			chest:persist_info()
		end)
	-- spawn NPC button
		local spawn_bt = state:button(5,4,3,0.5,"spawn_bt", "Spawn NPC")
		spawn_bt:onClick(function(self, state, player)
			townchest.npc.spawn_nearly(state.location.pos, chest, player )
		end)
	end

	-- update data each input
	state:onInput(function(self, fields)
		set_dynamic_values()
	end)

	-- set semi-dynamic data that is static at state livetime
	if chest.info.taskname == "file" then
		l1:setText("Building "..chest.info.filename.." selected")
	elseif chest.info.taskname == "generate" then
		l1:setText("Simple task: "..chest.info.genblock.variant_name)
	end
	local size = vector.add(vector.subtract(chest.plan.data.max_pos, chest.plan.data.min_pos),1)

	l2:setText("Size: "..size.x.." x "..size.z)
	l3:setText("Building high: "..size.y.."  Ground high: "..(chest.plan.data.ground_y-chest.plan.data.min_pos.y))

	--update data on demand without rebuild the state
	set_dynamic_values = function()
		l4:setText("Nodes to do: "..chest.plan.data.nodecount)
		if townchest.npc.supported then
			if chest.info.npc_build == true then
				npc_tg:setId(2)
			else
				npc_tg:setId(1)
			end
		end
		if chest.info.instantbuild == true then
			inst_tg:setId(2)
		else
			inst_tg:setId(1)
		end

		if chest.info.npc_build == true or chest.info.instantbuild == true then
			reload_bt:setVisible(false)
		else
			reload_bt:setVisible(true)
		end
	end

	-- update data once at init
	set_dynamic_values()
	return true --successfull build, update needed
end
smartfs.create("build_status", _build_status)
