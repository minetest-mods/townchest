local dprint = townchest.dprint --debug


townchest.specwidgets = {}


-----------------------------------------------
-- Select file dialog
-----------------------------------------------
local _spec_select_file_form = function(this)

	this.chest.meta:set_string("infotext", "please select a building")
	
	local formspec = "size[12,10]"
	if not this.info.files then
		this.info.files = townchest.files.get()
	end

	local x,y = 0,0
	local file

	if not this.info.firstpage then
		this.info.firstpage = 1
	end

	local firstfile = (this.info.firstpage - 1) * 30 + 1  -- 1, 31, 61, ...

	local lastfile = #this.info.files
	if lastfile >= firstfile + 30 then
		lastfile = firstfile + 30 -1
	end

	for i = firstfile,lastfile,1 do
		file = this.info.files[i]
		if x == 12 then
			y = y+1
			x = 0
		end
		formspec = formspec .."button["..(x)..","..(y)..";4,0.5;building;"..file.."]"
		x = x+4
	end
	if #this.info.files == 0 then
		formspec = formspec
			.."label[4,4.5; no files found in buildings folder:]"
			.."label[4,5.0; "..townchest.modpath.."/buildings".."]"
	end
	local nav = {}
	nav.back = 0 --initialized for nav.next calculation
	if this.info.firstpage > 1 then
		if this.info.firstpage - 30 < 1 then
			nav.back = 1
		else
			nav.back = this.info.firstpage - 1
		end
		formspec = formspec .."button[1,10;2,0.5;prev;page "..nav.back.."]"
	end
	if #this.info.files >= firstfile + 30 then
		nav.next = this.info.firstpage + 1
		formspec = formspec .."button[9,10;2,0.5;next;page "..nav.next.."]"
	end
	return formspec
end
-----------------------------------------------
-- Select file dialog action
-----------------------------------------------
local _spec_select_file_action = function(this, pos, formname, fields, sender)

	if fields.building then
		dprint("building selected:", fields.building)
		this.chest:prepare_building_plan(fields.building)
	elseif fields.prev then
		dprint("prev page")
		this.info.firstpage = this.info.firstpage - 1 --just navigation
	elseif fields.next then
		dprint("next page")
		this.info.firstpage = this.info.firstpage + 1 --just navigation
	end
end


-----------------------------------------------
-- Status dialog
-----------------------------------------------
local _spec_status_form = function(this)

	local message = "no message"
	if this.chest.statusmessage then
		message = this.chest.statusmessage
	end
	local formspec = "size[10,3]"
	formspec = formspec.."label[1,1; "..message
	this.chest.meta:set_string("infotext", message)
	return formspec
end

-----------------------------------------------
-- Customization dialog
-----------------------------------------------
local _spec_build_status_form = function(this)
	this.chest.meta:set_string("infotext", "Nodes in plan: "..this.chest.plan.building_size)
	local relative = this.chest.plan.relative
	
	local formspec = "size[12,10]"
	formspec = formspec.."label[1,0.5; Building "..this.chest.info.filename.." selected]"
	formspec = formspec.."label[1,1; Size: "..(relative.max_x-relative.min_x).." x "..(relative.max_z-relative.min_z).."]"
	formspec = formspec.."label[1,1.5; Building high: "..(relative.max_y-relative.min_y).."  Ground high: "..relative.ground_y-relative.min_y.."]"
	formspec = formspec.."label[1,2; Nodes to do: "..this.chest.plan.building_size.."]"

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

