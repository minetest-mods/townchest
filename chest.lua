local dprint = townchest.dprint --debug
local smartfs = townchest.smartfs

local preparing_plan_chunk = 10000

--------------------------------------
-- get - get chest reference of existing (or new+not initialized) chest
--------------------------------------
local __get = function(pos)
	local key = pos.x..","..pos.y..","..pos.z
	local this = nil
	if townchest.chest.list[key] then
		this = townchest.chest.list[key]
		dprint("get key from list", this)
	else		
		this = townchest.chest.new()
		this.key = key
		this.pos = pos
		this.meta = minetest.env:get_meta(pos) --just pointer
		townchest.chest.list[key] = this
		dprint("get new key", this)
	end
	return this
end

--------------------------------------
-- create - initial cleaned up chest after is placed
--------------------------------------
local __create = function(pos)
	local key = pos.x..","..pos.y..","..pos.z
	dprint("clean key", key)
	townchest.chest.list[key] = nil --delete old reference
	local this = __get(pos)
	dprint("cleaned chest object", this)
	return this
end

--------------------------------------
-- set_form - set formspec to specific widget
--------------------------------------
local __set_form = function(this, formname)

	local params = {}
	if formname = "file_open" then
		params.infotext = "please select a building"
	elseif formname = "build_status" then
		params.infotext = "Nodes in plan: "..this.plan.building_size
		params.relative = this.plan.relative
	else
		params.infotext = this.infotext
	end
	smartfs:__call(formname):attach_nodemeta(this.pos, nil, params)

	if this.infotext then
		this.meta:set_string("infotext", this.infotext)
	else
		this.meta:set_string("infotext", "")
	end
--[[	local info = minetest.deserialize(this.meta:get_string("specwidget")) --get add info
	if info then --dont overwrite {} from new
		this.specwidget.info = info
	end

	this.meta:set_string("formspec", this.specwidget:get_spec(specname))            --swap page
	this.meta:set_string("specwidget", minetest.serialize(this.specwidget.info))    --set add info
]]--
end

--[[
--------------------------------------
-- set_specwidget - set formspec to specific widget actions
--------------------------------------
local __set_specwidget_receive_fields = function(this, pos, formname, fields, sender)
	local ret_fields = nil
	if not this.specwidget then
		this.specwidget = townchest.specwidgets.new(this)
	end
	this.specwidget.info = minetest.deserialize(this.meta:get_string("specwidget")) --get add info
	if not this.specwidget.receive_fields then
--		this.specwidget:get_spec() --restore last spec receive_fields
		return nil --wait til restoring done
	end

	dprint("receive fields")
	if this.specwidget.receive_fields then
		ret_fields = this.specwidget:receive_fields(pos, formname, fields, sender)
	end

	this.meta:set_string("formspec", this.specwidget:get_spec())            --update page
	this.meta:set_string("specwidget", minetest.serialize(this.specwidget.info))    --set add info

	return ret_fields
end
]]--

--------------------------------------
-- read plan from file in chunk
--------------------------------------
local __prepare_building_plan_chain = function(this, we,startpos)

	-- check if the chest was destroyed in the meantime
	local chestinfo = minetest.deserialize(this.meta:get_string("chestinfo")) --get add info
	if not chestinfo then
		return -- chest removed during the load
	end

	-- go trough all file entries
	for i=startpos, #we do
		-- map to the internal node format
		local node = townchest.nodes.new(we[i]):map() --mapped
		if node and node.x and node.y and node.z then
			this.plan:add_node(node)
			this.plan:adjust_flatting_requrement(node)
		end

		if i % preparing_plan_chunk == 0 then --report and restart plan chain each 1000 node
			dprint("next processing chunk")
			this.infotext = "Reading node "..i.." of "..#we
			this:set_form("status")
			-- save current state

			minetest.after(0.5, this.prepare_building_plan_chain, this, we, i+1 ) --start next file processing chain
			return
		end
	end

-- loop finished, all nodes processed
	dprint("reading of building done. Save them to the chest metadata")
	this.meta:set_string("chestinfo", minetest.serialize(this.info))

	this.plan:prepare()

	if this.restore_started then -- Restore the start status
		this.started = true
		this.restore_started = nil
	end

	this:set_form("build_status")
	 -- TODO: maybe different formspec for building status (if started) and customizing
end

--------------------------------------
-- mark file reading as the next chest task
--------------------------------------
local __prepare_building_plan = function(this, filename)
	this.infotext = "Reading file "..filename
	this:set_form("status")

-- create the info object if not exisits
	if not this.info then
		this.info = {}
		if this.restore_started then
			this.info.started = true
			this.restore_started = nil
		end
	end
	this.info.filename = filename

	this.plan = townchest.plan.new(this)

-- check if file could be read
	local we = townchest.files.readfile(this.info.filename)
	if not we or #we == 0 then
		this.infotext = "No building found in ".. filename
		this:set_form("status")
		this.info.filename = nil
		this.meta:set_string("chestinfo", minetest.serialize(this.info))
--		minetest.after(3, this.set_specwidget, this, "select_file") --back to file selection (not needed with smarfts
		return
	end
	--start first processing chunk
	this.meta:set_string("chestinfo", minetest.serialize(this.info))
	minetest.after(1, this.prepare_building_plan_chain, this, we, 1) --start file processing chain
end


--[[
--------------------------------------
-- Do a chest task
--------------------------------------
local __do_cheststep = function(this)
--	dprint("object in cheststep", this)
end
]]--


local __instant_build = function(this)
	-- check if the chest was destroyed in the meantime (for minetest.after started chunks
	local chestinfo = minetest.deserialize(this.meta:get_string("chestinfo")) --get add info
	if not chestinfo then
		dprint("no chestinfo - asume the chest is removed")
		return -- chest removed during the load
	end

	if not this.instantbuild then --instantbuild disabled
		return
	end
	
	local startingnode = this.plan:get_nodes(1)
	-- go trough all file entries
	if startingnode[1] then -- the one node given
		dprint("start building chunk for", startingnode[1].x.."/"..startingnode[1].y.."/"..startingnode[1].z)
		minetest.forceload_block(this.plan:get_world_pos(startingnode[1]))
		for idx, node in ipairs(this.plan:get_nodes_from_chunk(startingnode[1])) do
--	for idx, node in ipairs(this.plan:get_nodes(instant_build_chunk)) do

			local wpos = this.plan:get_world_pos(node)
			if wpos.x ~= this.pos.x or wpos.y ~= this.pos.y or wpos.z ~= this.pos.z then --skip chest pos
				--- Place node
				minetest.env:add_node(wpos, node)
				if node.meta then
					minetest.env:get_meta(wpos):from_table(node.meta)
				end
			end
			this.plan:set_node_processed(node)
		end
		minetest.forceload_free_block(this.plan:get_world_pos(startingnode[1]))
	end

	this:set_form("build_status") -- building status

	if this.plan.building_size > 0 then --report and restart next plan chain
		dprint("next building chunk")
		this.infotext = "Nodes left to build "..this.plan.building_size
		minetest.after(1, this.instant_build, this ) --start next file processing chain
	else
		this.instantbuild = nil --disable instant build
	end
end


local __restore = function(this)
--[[
	local chestinfo = minetest.deserialize(this.meta:get_string("chestinfo")) --get add info
	if not chestinfo then
		dprint("no chestinfo - asume the chest is removed")
		return -- chest removed during the load
	end

	dprint("restoral info", dump(chestinfo))
	if chestinfo.filename and not this.plan then -- file selected but no plan. Restore the plan
		if chestinfo.started then
			this.restore_started = true
		end
		this:prepare_building_plan(chestinfo.filename)
	elseif not chestinfo.filename then
		this:set_specwidget("file_open")
	end
]]--
end

--------------------------------------
-- class attributes and methods
--------------------------------------
townchest.chest = {
	list = {}, -- cached chest list
	create = __create,
	get = __get,
	restore = __restore
}

--------------------------------------
-- object definition / constructor
--------------------------------------
townchest.chest.new = function()
	local this = {}
	--attributes
	this.infotext = nil --used in spec_status_form  to display short status
	
	--methods
	this.set_form = __set_form -- wrapper around smarfts():attach
	this.prepare_building_plan = __prepare_building_plan
--	this.do_cheststep = __do_cheststep
	this.prepare_building_plan_chain = __prepare_building_plan_chain
	this.instant_build = __instant_build
	this.restore = __restore
	return this
end
