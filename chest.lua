local dprint = townchest.dprint_off --debug
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

--------------------------------------
-- Class attributes
--------------------------------------
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

	--------------------------------------
	-- save persistant chest info to the chest metadata
	--------------------------------------
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
	-- update informations on formspecs
	--------------------------------------
	function chest.update_info(this, formname)
		this:set_infotext(formname)
		this:persist_info()
		smartfs.nodemeta_on_receive_fields(this.pos, formname, {}) -- send no data, but triiger onReceive
	end

	--------------------------------------
	-- Create the task that should be managed by chest
	--------------------------------------
	function chest.set_rawdata(this, taskname)
		if taskname == "file" then
		-- check if file could be read
			local we = townchest.files.readfile(this.info.filename)
			if not we or #we == 0 then
				this.infotext = "No building found in ".. this.info.filename
				this:set_form("status")
				this.current_stage = "select"
				this.info.filename = nil
				this:persist_info()
				minetest.after(3, this.set_form, this, "file_open") --back to file selection
				return
			end
			this.rawdata = we

		elseif taskname == "generate" then
			local we = {}
			if this.info.genblock.fill == "true" then
--[[				for x = -math.floor(this.info.genblock.x/2), math.floor(this.info.genblock.x/2) do
					for y = -1, this.info.genblock.y -2 do -- 1 under the chest
						for z = -math.floor(this.info.genblock.z/2), math.floor(this.info.genblock.z/2) do
							table.insert(we, {x=x,y=y,z=z, name = "default:cobble"})
						end
					end
				end
]]
				for x = -math.floor(this.info.genblock.x/2), math.floor(this.info.genblock.x/2) do
					for y = -1, this.info.genblock.y -2 do -- 1 under the chest
						for z = -math.floor(this.info.genblock.z/2), math.floor(this.info.genblock.z/2) do
							if x == -math.floor(this.info.genblock.x/2) or x == math.floor(this.info.genblock.x/2) or
									y == -1 or y == this.info.genblock.y -2 or
									z == -math.floor(this.info.genblock.z/2) or z == math.floor(this.info.genblock.z/2) then
								table.insert(we, {x=x,y=y,z=z, name = "default:cobble"})
							end
						end
					end
				end
			else
				table.insert(we, {x=-math.floor(this.info.genblock.x/2),y=0,z=-math.floor(this.info.genblock.z/2), name = "air"})
				table.insert(we, {x=math.floor(this.info.genblock.x/2),y=this.info.genblock.y -1,z=math.floor(this.info.genblock.z/2), name = "air"})
			end
			this.rawdata = we
		end

		this.info.taskname = taskname
		this.plan = townchest.plan.new(this)
		chest:run_async(this.prepare_building_plan_chain)
	end


	--------------------------------------
	-- Call a task semi-async trough minetest.after()
	--------------------------------------
	function chest.run_async(this, func)
		local function async_call(pos)
			local chest = townchest.chest.get(pos)
			this.info = minetest.deserialize(this.meta:get_string("chestinfo")) --get add info
			if not this.info then -- chest removed during the load, stop processing
				townchest.chest.list[this.key] = nil
				return
			end
			if func(chest) then --call the next chain / repeat function call
				chest:run_async(func)
			end
		end

		this:persist_info()
		minetest.after(0.2, async_call, this.pos)
	end

	--------------------------------------
	-- Async task: create building plan from rawdata
	--------------------------------------
	function chest.prepare_building_plan_chain(this)
		local chunksize, lastchunk
		-- go trough all file entries
		if #this.rawdata > preparing_plan_chunk then
			chunksize = preparing_plan_chunk
			lastchunk = true
		else
			chunksize = #this.rawdata
		end

		for i=#this.rawdata, #this.rawdata-chunksize+1, -1 do
			-- map to the internal node format
			local wenode = this.rawdata[i]
			if wenode and wenode.x and wenode.y and wenode.z and wenode.name then
				this.plan:adjust_flatting_requrement(wenode)
				local node = townchest.nodes.new(this.rawdata[i]):map() --mapped
				if node and node.x and node.y and node.z then
					this.plan:add_node(node)
				end
			end
			this.rawdata[i] = nil
		end

		if lastchunk then
			dprint("next processing chunk")
			this.infotext = "Preparing, nodes left: "..#this.rawdata
			this:set_form("status")
			return true --repeat async call
		else
			dprint("reading of building done. Save them to the chest metadata")
			this.infotext = "Reading done, preparing"
			this:set_form("status")
			this:run_async(chest.prepare_building_plan_chain_postprocess)
			return false
		end
	end

	--------------------------------------
	-- Async task: Post-processing of plan preparation
	--------------------------------------
	function chest.prepare_building_plan_chain_postprocess(this)
		this.plan:prepare()
		this.current_stage = "ready"
		this:set_form("build_status")
		this:persist_info()
		this:run_async(chest.instant_build_chain) --just trigger, there is a check if active
	end

	--------------------------------------
	-- Async Task: Do a instant build step
	--------------------------------------
	function chest.instant_build_chain(this)
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
		this:update_info("build_status")
		if this.plan.building_size > 0 then --report and restart next plan chain
			return true
		else
			this.instantbuild = nil --disable instant build
			return false
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
			this:update_info("build_status")
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
		if chestinfo.taskname and not this.current_stage then -- file selected but no plan. Restore the plan
			this.current_stage = "restore"
			chest:set_rawdata(this.info.taskname)
		elseif not chestinfo.filename then
			this:set_form("file_open")
		end
	end

	-- retrun the chest object in townchest.chest.new()
	return chest
end
