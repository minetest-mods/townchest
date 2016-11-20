local dprint = townchest.dprint --debug
local smartfs = townchest.smartfs

local preparing_plan_chunk = 10000

--------------------------------------
-- class attributes and methods
--------------------------------------
townchest.chest = {
	-- chest list
	list = {},
	-- get current chest
	get = function(pos)
		local key = minetest.pos_to_string(pos)
		local self = nil
		if townchest.chest.list[key] then
			self = townchest.chest.list[key]
		else
			self = townchest.chest.new()
			self.key = key
			self.pos = pos
			self.meta = minetest.env:get_meta(pos) --just pointer
			townchest.chest.list[key] = self
		end

		-- update chest info
		self.info = minetest.deserialize(self.meta:get_string("chestinfo")) --get add info
		if not self.info then
			self.info = {}
		end

		return self
	end,
	-- create - initial cleaned up chest after is placed
	create = function(pos)
		local key = minetest.pos_to_string(pos)
		dprint("clean key", key)
		townchest.chest.list[key] = nil --delete old reference
		local self = townchest.chest.get(pos)
		self.info = nil
		dprint("cleaned chest object", self)
		return self
	end,
}


--------------------------------------
-- object definition / constructor
--------------------------------------
townchest.chest.new = function()
	local self = {}
	--------------------------------------
	-- save persistant chest info to the chest metadata
	--------------------------------------
	function self.persist_info(self) -- the read info is in get method
		self.meta:set_string("chestinfo", minetest.serialize(self.info))
	end

	--------------------------------------
	-- set_infotext - Update node infotext
	--------------------------------------
	function self.set_infotext(self, formname)
		local infotext
		if formname == "file_open" then
			infotext = "please select a building"
		elseif formname == "build_status" then
			infotext = "Nodes in plan: "..self.plan.building_size
		else
			infotext = self.infotext or ""
		end
		self.meta:set_string("infotext", infotext)
	end

	--------------------------------------
	-- set_form - set formspec to specific widget
	--------------------------------------
	function self.set_form(self, formname)
		self:set_infotext(formname)
		self:persist_info() -- the form read data from persistance handler
		smartfs.get(formname):attach_to_node(self.pos)
	end

	--------------------------------------
	-- update informations on formspecs
	--------------------------------------
	function self.update_info(self, formname)
		self:set_infotext(formname)
		self:persist_info()
		-- send no data, but triger onInput
		smartfs.nodemeta_on_receive_fields(self.pos, formname, {})
	end

	--------------------------------------
	-- Create the task that should be managed by chest
	--------------------------------------
	function self.set_rawdata(self, taskname)
		self.plan = townchest.plan.new(self)
		local we = {}

		if taskname then
			self.info.taskname = taskname
		end

		if self.info.taskname == "file" then
		-- check if file could be read
			we = townchest.files.readfile(self.info.filename)
			if not we or #we == 0 then
				self.infotext = "No building found in ".. self.info.filename
				self:set_form("status")
				self.current_stage = "select"
				self.info.filename = nil
				self:persist_info()
				minetest.after(3, self.set_form, self, "file_open") --back to file selection
				return
			end

		elseif self.info.taskname == "generate" then
			if self.info.genblock.variant == 1 then
				-- Fill with air
				for x = 0, self.info.genblock.x-1 do
					for y = 0, self.info.genblock.y-1 do
						for z = 0, self.info.genblock.z-1 do
							table.insert(we, {x=x,y=y,z=z, name = "air"})
						end
					end
				end
			elseif self.info.genblock.variant == 2 then
				-- Fill with stone
				for x = 0, self.info.genblock.x-1 do
					for y = 0, self.info.genblock.y-1 do
						for z = 0, self.info.genblock.z-1 do
							table.insert(we, {x=x,y=y,z=z, name = "default:cobble"})
						end
					end
				end

			elseif self.info.genblock.variant == 3 then
				-- Build a box
				for x = 0, self.info.genblock.x-1 do
					for y = 0, self.info.genblock.y-1 do
						for z = 0, self.info.genblock.z-1 do
							if x == 0 or x == self.info.genblock.x-1 or
									y == 0 or y == self.info.genblock.y-1 or
									z == 0 or z == self.info.genblock.z-1 then
								table.insert(we, {x=x,y=y,z=z, name = "default:cobble"})
							end
						end
					end
				end

				-- build ground level under chest
				self.plan.relative.ground_y = 1

			-- Build a plate
			elseif self.info.genblock.variant == 4 then
				local y = 0
				for x = 0, self.info.genblock.x-1 do
					for z = 0, self.info.genblock.z-1 do
						table.insert(we, {x=x,y=y,z=z, name = "default:cobble"})
					end
				end
				-- build ground level under chest
				self.plan.relative.ground_y = 1
			end
		end

		self.rawdata = we

		self:run_async(self.prepare_building_plan_chain)
	end


	--------------------------------------
	-- Call a task semi-async trough minetest.after()
	--------------------------------------
	function self.run_async(self, func)
		local function async_call(pos)
			local chest = townchest.chest.get(pos)
			chest.info = minetest.deserialize(chest.meta:get_string("chestinfo")) --get add info
			if not chest.info then -- chest removed during the load, stop processing
				townchest.chest.list[chest.key] = nil
				return
			end
			if func(chest) then --call the next chain / repeat function call
				chest:run_async(func)
			end
		end

		self:persist_info()
		minetest.after(0.2, async_call, self.pos)
	end

	--------------------------------------
	-- Async task: create building plan from rawdata
	--------------------------------------
	function self.prepare_building_plan_chain(self)
		local chunksize, lastchunk
		-- go trough all file entries
		if #self.rawdata > preparing_plan_chunk then
			chunksize = preparing_plan_chunk
			lastchunk = true
		else
			chunksize = #self.rawdata
		end

		for i=#self.rawdata, #self.rawdata-chunksize+1, -1 do
			-- map to the internal node format
			local wenode = self.rawdata[i]
			if wenode and wenode.x and wenode.y and wenode.z and wenode.name then
				self.plan:adjust_flatting_requrement(wenode)
				local node = townchest.nodes.new(self.rawdata[i]):map() --mapped
				if node and node.x and node.y and node.z then
					self.plan:add_node(node)
				end
			end
			self.rawdata[i] = nil
		end

		if lastchunk then
			dprint("next processing chunk")
			self.infotext = "Preparing, nodes left: "..#self.rawdata
			self:set_form("status")
			return true --repeat async call
		else
			dprint("reading of building done. Save them to the chest metadata")
			self.infotext = "Reading done, preparing"
			self:set_form("status")
			self:run_async(self.prepare_building_plan_chain_postprocess)
			return false
		end
	end

	--------------------------------------
	-- Async task: Post-processing of plan preparation
	--------------------------------------
	function self.prepare_building_plan_chain_postprocess(self)
		self.plan:prepare()
		self.current_stage = "ready"
		self:set_form("build_status")
		self:persist_info()
		self:run_async(self.instant_build_chain) --just trigger, there is a check if active
	end

	--------------------------------------
	-- Async Task: Do a instant build step
	--------------------------------------
	function self.instant_build_chain(self)
		if not self.info.instantbuild == true then --instantbuild disabled
			return
		end
		dprint("Instant build is running")

		local startingnode = self.plan:get_nodes(1)
		-- go trough all file entries
		if startingnode[1] then -- the one node given
			dprint("start building chunk for", minetest.pos_to_string(startingnode[1]))
			minetest.forceload_block(self.plan:get_world_pos(startingnode[1]))
			for idx, node in ipairs(self.plan:get_nodes_from_chunk(startingnode[1])) do
				local wpos = self.plan:get_world_pos(node)
				if wpos.x ~= self.pos.x or wpos.y ~= self.pos.y or wpos.z ~= self.pos.z then --skip chest pos
					--- Place node
					minetest.env:add_node(wpos, node)
					if node.meta then
						minetest.env:get_meta(wpos):from_table(node.meta)
					end
				end
				self.plan:set_node_processed(node)
			end
			minetest.forceload_free_block(self.plan:get_world_pos(startingnode[1]))
		end
		self:update_info("build_status")
		if self.plan.building_size > 0 then
			--start next plan chain
			return true
		else
			-- finished. disable processing
			self.instantbuild = false
			return false
		end
	end

	--------------------------------------
	-- Check if the chest is ready to build something
	--------------------------------------
	function self.npc_build_allowed(self)
		if self.current_stage ~= "ready" then
			return false
		else
			return self.info.npc_build
		end
	end

	function self.update_statistics(self)
		if self.current_stage == "ready" then --update building status in case of ready (or build in process after ready)
			self:update_info("build_status")
		end
	end

	--------------------------------------
	-- restore chest state after shutdown (and maybe suspend if implemented)
	--------------------------------------
	function self.restore(self)
		local chestinfo = minetest.deserialize(self.meta:get_string("chestinfo")) --get add info
		if not chestinfo then
			dprint("no chestinfo - asume the chest is removed")
			return -- chest removed during the load
		end
		dprint("restoral info", dump(chestinfo))
		if self.current_stage then
			dprint("restoral not necessary, current stage is", self.current_stage)
			return
		end
		if chestinfo.taskname then -- file selected but no plan. Restore the plan
			self.current_stage = "restore"
			self:set_rawdata(chestinfo.taskname)
		else
			self:set_form("file_open")
		end
	end

	-- retrun the chest object in townchest.chest.new()
	return self
end
