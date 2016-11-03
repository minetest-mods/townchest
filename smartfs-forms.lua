local dprint = townchest.dprint --debug


townchest.specwidgets = {}


--- temporary provide smartfs as builtin, till the needed changes are upstream
local smartfs = townchest.smartfs
--- temporary end


local _file_open_dialog = function(state)
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
			local chest = townchest.chest.get(state.location.pos)
			chest:prepare_building_plan(file)
		end
	end)
	
	state:button(5,6.5,2,0.5,"Cancel","Cancel", true)
	return true

end
smartfs.create("file_open", _file_open_dialog)


-----------------------------------------------
-- Status dialog
-----------------------------------------------
local _status = function(state)
	state:size(1,7)
	state:label(0,0,"info",state:getparam("infotext"))
end
smartfs.create("status", _status)



-----------------------------------------------
-- Customization dialog
-----------------------------------------------
local _build_status = function(state)
		state:size(12,10)

	local relative = getparam("relative")
	state:label(1,0.5,"l1","Building "..this.chest.info.filename.." selected")
	state:label(1,1.0,"l2","Size: "..(relative.max_x-relative.min_x).." x "..(relative.max_z-relative.min_z))
	state:label(1,1.5,"l3","Building high: "..(relative.max_y-relative.min_y).."  Ground high: "..(relative.ground_y-relative.min_y))
	state:label(1,2.0,"l4","Nodes to do: "..this.chest.plan.building_size)

--[[
	local current_task = getparam("current_task")
	local inst_tg_id = 1 --stopped
	local inst_npc_id = 1 -- stopped
	
	if current_task ==
]]--
	state:toggle(1,8,3,0.5,"inst_tg",{"Start instant build","Stop instant build"})
	state:toggle(5,8,3,0.5,"npc_tg",{"Start NPC build","Stop NPC build"})

	local 

-- first buttons row
	if this.chest.instantbuild then
		formspec = formspec.."button[1,8;3,0.5;stop_instant;Stop instant build]"
	else
		formspec = formspec.."button[1,8;3,0.5;start_instant;Start instant build]"
	end
	if this.chest.started then
		formspec = formspec.."button[5,8;3,0.5;stop;Stop NPC build]"
	else
		formspec = formspec.."button[5,8;3,0.5;start;Start NPC build]"
	end

	
-- second buttons row
	formspec = formspec.."button[1,9;3,0.5;take_npc;Spawn NPC]"
	-- reload available if nothing started only
	if not this.chest.started and not this.chest.instantbuild then
		formspec = formspec.."button[5,9;3,0.5;reload_file;Reload nodes]"
	end

	return formspec
end


-----------------------------------------------
-- Customization dialog
-----------------------------------------------
local _spec_build_status_action = function(this, pos, formname, fields, sender)
	if fields.start_instant then
		this.chest.instantbuild = true
		this.chest:instant_build()
	elseif fields.stop_instant then
		this.chest.instantbuild = nil

	elseif fields.take_npc then
		minetest.add_entity({x=(pos.x+math.random(0,4)-2),y=(pos.y+math.random(0,2)),z=(pos.z+math.random(0,4)-2)}, "townchest:builder")

	elseif fields.start then
		this.chest.started = true      --is used by NPC
		this.chest.info.started = true --is used by restore
		this.chest.meta:set_string("chestinfo", minetest.serialize(this.chest.info))
	elseif fields.stop then
		this.chest.started = nil
		this.chest.info.started = nil
		this.chest.meta:set_string("chestinfo", minetest.serialize(this.chest.info))
	elseif fields.reload_file then
		this.chest:prepare_building_plan(this.chest.info.filename)
	end
end



local __get_spec = function(this,specname)

	local spec = specname
	if not spec then
		spec = this.info.specname
	end
	this.info.specname = spec

	if spec == "select_file" then
		this.receive_fields = _spec_select_file_action --set function
		return _spec_select_file_form(this)
	elseif spec == "status" then
		this.receive_fields = nil
		return _spec_status_form(this)
	elseif spec == "build_status" then
		this.receive_fields = _spec_build_status_action --set function
		return _spec_build_status_form(this)
	end
end


--------------------------------------
-- object definition / constructor
--------------------------------------
townchest.specwidgets.new = function(chest) 
	local this = {}
	this.info = {} --additional functions
	this.get_spec = __get_spec
	this.chest = chest
	return this
end

