local dprint = townchest.dprint_off --debug
local smartfs = townchest.smartfs

townchest.specwidgets = {}

-----------------------------------------------
-- Header shown on all forms
-----------------------------------------------
local function allform_header(state)
	state:size(16,10)
	state:button(0,0,2,1,"allform_sel_plan", "Building Plan"):onClick(function(self)
		local chest = townchest.chest.get(state.location.pos)
		if not chest.plan then
			smartfs.get("townchest:plan"):attach_to_node(chest.pos)
		else
			smartfs.get("townchest:build_status"):attach_to_node(chest.pos)
		end
	end)

	if minetest.global_exists("schemlib_builder_npcf") then
		state:button(2,0,2,1,"allform_sel_npc", "NPC / Builder"):onClick(function(self)
			local chest = townchest.chest.get(state.location.pos)
			smartfs.get("townchest:npc_form"):attach_to_node(chest.pos)
		end)
	end
	state:label(4,0.25,"allform_head","Building chest at "..minetest.pos_to_string(state.location.pos))


	state:button(14,0,2,0.5,"Cancel","Cancel", true)
end

-----------------------------------------------
-- file open dialog form / (tabbed)
-----------------------------------------------
local function plan_form(state)
	allform_header(state)
	state:get("allform_sel_plan"):setBackground("default_gold_block.png")
	local chest = townchest.chest.get(state.location.pos)

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
	tab1.button = state:button(0,2,2,1,"tab1_btn","Buildings")
	tab1.button:onClick(function(self)
		tab_controller:set_active("tab1")
	end)
	tab1.view = state:container(2,1,"tab1_view")
	tab1.viewstate = tab1.view:getContainerState()
	tab1.viewstate:label(0,0,"header","Please select a building")
	local listbox = tab1.viewstate:listbox(0,0.5,6,5.5,"fileslist")
	for idx, file in ipairs(townchest.files_get()) do
		listbox:addItem(file)
	end
	tab_controller:tab_add("tab1", tab1)

-----------------------------------------------
-- Simple form building tab
-----------------------------------------------
	if not chest.info.genblock then
		chest.info.genblock = {}
	end

	local tab2 = {}
	tab2.button = state:button(0,3,2,1,"tab2_btn","Tasks")
	tab2.button:onClick(function(self)
		tab_controller:set_active("tab2")
	end)
	tab2.view = state:container(2,1,"tab2_view")
	tab2.viewstate = tab2.view:getContainerState()
	tab2.viewstate:label(0,0,"header","Build simple form")

	local variant = tab2.viewstate:dropdown(3,0,4,0.5,"variant", 1)
	variant:addItem("Fill with air") -- 1
	variant:addItem("Fill with stone") -- 2
	variant:addItem("Build a box") -- 3
	variant:addItem("Build a plate") -- 4
	variant:setSelected(chest.info.genblock.variant or 1)

	tab2.viewstate:field(1,2,2,0.5,"x","width (x)"):setText(tostring(chest.info.genblock.x or 1))
	tab2.viewstate:field(3,2,2,0.5,"y","high (y)"):setText(tostring(chest.info.genblock.y or 1))
	tab2.viewstate:field(5,2,2,0.5,"z","width (z)"):setText(tostring(chest.info.genblock.z or 1))

	tab2.viewstate:onInput(function(state, fields)
		chest.info.genblock.x = tonumber(state:get("x"):getText())
		chest.info.genblock.y = tonumber(state:get("y"):getText())
		chest.info.genblock.z = tonumber(state:get("z"):getText())
		chest.info.genblock.variant = state:get("variant"):getSelected()
		chest.info.genblock.variant_name = state:get("variant"):getSelectedItem()
		chest:persist_info()
	end)
	tab_controller:tab_add("tab2", tab2)

-- Run Button (both tabls)
	state:button(0,8.5,2,0.5,"load","Load"):onClick(function(self)
		local selected_tab = tab_controller:get_active_name()
		if selected_tab == "tab1" then
			chest.info.filename = state:get("tab1_view"):getContainerState():get("fileslist"):getSelectedItem()
			if chest.info.filename then
				chest:set_rawdata("file")
			end
		elseif selected_tab == "tab2" then
			chest:set_rawdata("generate")
		end
	end)

	-- set default values
	tab_controller:set_active("tab1") --default tab
end
smartfs.create("townchest:plan", plan_form)

-----------------------------------------------
-- Status dialog
-----------------------------------------------
local function status_form(state)
	local chest = townchest.chest.get(state.location.pos)
	if not chest.infotext then
		print("BUG: no infotext for status dialog!")
		return false -- no update
	end
	state:size(7,1)
	state:label(0,0,"info", chest.infotext)
end
smartfs.create("townchest:status", status_form)

-----------------------------------------------
-- Building status dialog
-----------------------------------------------
local build_status_form = function(state)
	allform_header(state)
	state:get("allform_sel_plan"):setBackground("default_gold_block.png")

	-- connect to chest data
	local chest = townchest.chest.get(state.location.pos)

	if not chest.plan then
		print("BUG: no plan in build_status dialog!")
		return false -- no update
	end

	-- set dynamic values after actions
	local function set_dynamic_values(state)
		local chest = townchest.chest.get(state.location.pos)
		state:get("l4"):setText("Nodes to do: "..chest.plan.data.nodecount)
		if townchest.npc.supported then
			if chest.info.npc_build == true then
				state:get("npc_tg"):setId(2)
			else
				state:get("npc_tg"):setId(1)
			end
		end
		if chest.info.instantbuild == true then
			state:get("inst_tg"):setId(2)
		else
			state:get("inst_tg"):setId(1)
		end

		if chest.info.npc_build == true or chest.info.instantbuild == true then
			state:get("reload_bt"):setVisible(false)
		else
			state:get("reload_bt"):setVisible(true)
		end
	end

	local l1_text
	local building_size = vector.add(vector.subtract(chest.plan.data.max_pos, chest.plan.data.min_pos),1)
	if chest.info.taskname == "file" then
		l1_text = "Building "..chest.info.filename.." selected"
	elseif chest.info.taskname == "generate" then
		l1_text = "Simple task: "..chest.info.genblock.variant_name
	end

	state:label(1,1.5,"l1",l1_text)
	state:label(1,2.0,"l2","Size: "..building_size.x.." x "..building_size.z)
	state:label(1,2.5,"l3","Building high: "..building_size.y.."  Ground high: "..(chest.plan.data.ground_y-chest.plan.data.min_pos.y))
	state:label(1,3.0,"l4","<<<set in set_dynamic_values>>>")

	-- instant build toggle
	state:toggle(1,4,3,0.5,"inst_tg",{ "Start instant build", "Stop instant build"}):onToggle(function(self, state, player)
		if self:getId() == 2 then
			chest.info.instantbuild = true
			chest.plan:set_status("build")
			chest:run_async(chest.instant_build_chunk)
		else
			chest.info.instantbuild = false
		end
		set_dynamic_values(state)
		chest:persist_info()
	end)

	-- refresh building button
	state:button(5,4,3,0.5,"reload_bt", "Reload nodes"):onClick(function(self, state, player)
		chest:set_rawdata(chest.info.taskname)
	end)

	-- NPC build button
	if townchest.npc.supported then
		state:toggle(9,4,3,0.5,"npc_tg",{ "Start NPC build", "Stop NPC build"}):onToggle(function(self, state, player)
			if self:getId() == 2 then
				chest.info.npc_build = true
				chest.plan:set_status("build")
				townchest.npc.enable_build(chest.plan)
			else
				chest.info.npc_build = false
				townchest.npc.disable_build(chest.plan)
			end
			set_dynamic_values(state)
			chest:persist_info()
		end)
	end

	-- update data each input
	state:onInput(function(self, fields)
		set_dynamic_values(self)
	end)

	-- update data once at init
	set_dynamic_values(state)
end
smartfs.create("townchest:build_status", build_status_form)

-----------------------------------------------
-- file open dialog form / (tabbed)
-----------------------------------------------
local function npc_form(state)
	-- allform header
	allform_header(state)
	state:get("allform_sel_npc"):setBackground("default_gold_block.png")
	local chest = townchest.chest.get(state.location.pos)

	state:label(0,1,"header","Configure the NPC mod settings")
	state:label(0,1.5,"header2","0 = disabled, 1 = enabled >1 enabled with rarity")
	state:field(1,3,3,1,"pause","Pause duration (in sec):"):setText(tostring(schemlib_builder_npcf.max_pause_duration))
	state:field(1,4,3,1,"arch","Own buildings creation:"):setText(tostring(schemlib_builder_npcf.architect_rarity))
	state:field(4,3,3,1,"walkaround","Walk direction change:"):setText(tostring(schemlib_builder_npcf.walk_around_rarity))
	state:field(4,4,3,1,"plan_distance","Max plan distance :"):setText(tostring(schemlib_builder_npcf.plan_max_distance))
	state:button(0.7,5,2,1,"apply","Apply"):onClick(function(self)
		schemlib_builder_npcf.max_pause_duration = tonumber(state:get("pause"):getText()) or schemlib_builder_npcf.max_pause_duration
		schemlib_builder_npcf.architect_rarity = tonumber(state:get("arch"):getText()) or schemlib_builder_npcf.architect_rarity
		schemlib_builder_npcf.walk_around_rarity = tonumber(state:get("walkaround"):getText()) or schemlib_builder_npcf.walk_around_rarity
		schemlib_builder_npcf.plan_max_distance = tonumber(state:get("plan_distance"):getText()) or schemlib_builder_npcf.plan_max_distance
	end)

	-- spawn NPC button
	state:button(3.7,5,2,1,"spawn_bt", "Spawn NPC"):onClick(function(self, state, player)
		townchest.npc.spawn_nearly(state.location.pos, chest, player )
	end)
end


smartfs.create("townchest:npc_form", npc_form)
