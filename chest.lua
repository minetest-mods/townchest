local dprint = townchest.dprint --debug
local smartfs = townchest.smartfs

local preparing_plan_chunk = 10000



--------------------------------------
-- class attributes and methods
--------------------------------------
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

	-- update chest info
	this.info = minetest.deserialize(this.meta:get_string("chestinfo")) --get add info
	if not this.info then
		this.info = {}
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
	this.info = nil
	dprint("cleaned chest object", this)
	return this
end

townchest.chest = {
	list = {}, -- cached chest list
	create = __create,
	get = __get,
}

--------------------------------------
-- object definition / constructor
--------------------------------------
townchest.chest.new = function()
	local chest = {}
	--attributes
	chest.infotext = nil --used in spec_status_form  to display short status


	function chest.persist_info(this) -- the read info is in get method
		this.meta:set_string("chestinfo", minetest.serialize(this.info))
	end

	--------------------------------------
	-- set_infotext - Update node infotext
	--------------------------------------
	function chest.set_infotext (this, formname)
		local infotext
		if formname == "file_open" then
			infotext = "please select a building"
		elseif formname == "build_status" then
			infotext = "Nodes in plan: "..this.plan.building_size
		else
			infotext = this.infotext
		end
		if infotext then
			this.meta:set_string("infotext", infotext)
		else
			this.meta:set_string("infotext", "")
		end
	end

	--------------------------------------
	-- set_form - set formspec to specific widget
	--------------------------------------
	function chest.set_form(this, formname)
		this:set_infotext(formname)
		this:persist_info() -- the form read data from persistance handler
		smartfs:__call(formname):attach_nodemeta(this.pos, nil)
	end

	--------------------------------------
	-- Take postprocess after prepare building plan
	--------------------------------------
	function chest.prepare_building_plan_chain_postprocess(this)
		this.plan:prepare()
		this.current_stage = "ready"
		this:set_form("build_status")
		this:persist_info()
		minetest.after(1, this.instant_build, this ) -- check if instant build already active
	end

	--------------------------------------
	-- read plan from file in chunk
	--------------------------------------
	function chest.prepare_building_plan_chain(this, we,startpos)

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
		this.infotext = "Reading file "..this.info.filename.." done, preparing "
		this:set_form("status")
		minetest.after(0,chest.prepare_building_plan_chain_postprocess, this) --next stage
	end

	--------------------------------------
	-- mark file reading as the next chest task
	--------------------------------------
	function chest.prepare_building_plan(this, filename)

		this.current_stage = "reading"
		this.info.filename = filename
		this.infotext = "Reading file "..filename
		this:set_form("status")

		this.plan = townchest.plan.new(this)

	-- check if file could be read
		local we = townchest.files.readfile(this.info.filename)
		if not we or #we == 0 then
			this.infotext = "No building found in ".. filename
			this:set_form("status")
			this.current_stage = "select"
			this:persist_info()
			minetest.after(3, this.set_form, this, "select_file") --back to file selection
			return
		end
		--start first processing chunk
		this:persist_info()
		minetest.after(0, this.prepare_building_plan_chain, this, we, 1) --start file processing chain
	end

	--------------------------------------
	-- Do a instant build step
	--------------------------------------
	function chest.instant_build(this)
		dprint("Entering instant build")
		-- check if the chest was destroyed in the meantime (for minetest.after started chunks
		local chestinfo = minetest.deserialize(this.meta:get_string("chestinfo")) --get add info
		if not chestinfo then
			dprint("no chestinfo - asume the chest is removed")
			return -- chest removed during the load
		end

		if not this.info.instantbuild then --instantbuild disabled
			return
		end
		dprint("Instant build is running")

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

	--------------------------------------
	-- Check if the chest is ready to build something
	--------------------------------------
	function chest.npc_build_allowed(this)
		if this.current_stage == "ready" and
				this.info.npc_build then
			return true
		else
			return false
		end
	end


	function chest.update_statistics(this)
		if this.current_stage == "ready" then --update building status in case of ready (or build in process after ready)
			this:set_form("build_status")
		end
	end

	--------------------------------------
	-- restore chest state after shutdown (and maybe suspend if implemented)
	--------------------------------------
	function chest.restore(this)
		local chestinfo = minetest.deserialize(this.meta:get_string("chestinfo")) --get add info
		if not chestinfo then
			dprint("no chestinfo - asume the chest is removed")
			return -- chest removed during the load
		end

		dprint("restoral info", dump(chestinfo))
		if chestinfo.filename and not this.current_stage then -- file selected but no plan. Restore the plan
			this.current_stage = "restore"
			this:prepare_building_plan(chestinfo.filename)
		elseif not chestinfo.filename then
			this:set_form("file_open")
		end
	end

	-- retrun the chest object in townchest.chest.new()
	return chest
end
