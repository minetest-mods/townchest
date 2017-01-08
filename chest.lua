local dprint = townchest.dprint_off --debug
local smartfs = townchest.smartfs

local ASYNC_WAIT=0.2  -- schould be > 0 to restrict performance consumption
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
			infotext = "Nodes in plan: "..self.plan.data.nodecount
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

		if taskname then
			self.info.taskname = taskname
		end

		if self.info.taskname == "file" then
		-- check if file could be read
			if not self.info.filename then
				-- something wrong, back to file selection
				minetest.after(0, self.set_form, self, "file_open")
				self.current_stage = "select"
				self:persist_info()
				return
			end

			self.plan.data = townchest.files.readfile(self.info.filename)

			if not self.plan.data then
				self.infotext = "No building found in ".. self.info.filename
				self:set_form("status")
				self.current_stage = "select"
				self.info.filename = nil
				self:persist_info()
				minetest.after(3, self.set_form, self, "file_open") --back to file selection
				return
			end

		elseif self.info.taskname == "generate" then
				self.plan.data = {}
				self.plan.data.min_pos = { x=1, y=1, z=1 }
				self.plan.data.max_pos = { x=self.info.genblock.x, y=self.info.genblock.y, z=self.info.genblock.z}
				self.plan.data.nodecount = 0
				self.plan.data.ground_y = 0
				self.plan.data.nodenames = {}
				self.plan.data.scm_data_cache = {}

			if self.info.genblock.variant == 1 then
				-- nothing special, just let fill them with air
			elseif self.info.genblock.variant == 2 then
				table.insert(self.plan.data.nodenames, "default:cobble") -- index 1
				-- Fill with stone
				for x = 1, self.info.genblock.x do
					for y = 1, self.info.genblock.y do
						for z = 1, self.info.genblock.z do
							self.plan:add_node({x=x,y=y,z=z, name_id = 1})
						end
					end
				end

			elseif self.info.genblock.variant == 3 then
				-- Build a box
				table.insert(self.plan.data.nodenames, "default:cobble") -- index 1
				for x = 1, self.info.genblock.x do
					for y = 1, self.info.genblock.y do
						for z = 1, self.info.genblock.z do
							if x == 1 or x == self.info.genblock.x or
									y == 1 or y == self.info.genblock.y or
									z == 1 or z == self.info.genblock.z then
								self.plan:add_node({x=x,y=y,z=z, name_id = 1})
							end
						end
					end
				end

				-- build ground level under chest
				self.plan.data.ground_y = 1

			-- Build a plate
			elseif self.info.genblock.variant == 4 then
				table.insert(self.plan.data.nodenames, "default:cobble") -- index 1
				local y = self.plan.data.min_pos.y
				self.plan.data.max_pos.y = self.plan.data.min_pos.y
				for x = 1, self.info.genblock.x do
					for z = 1, self.info.genblock.z do
						self.plan:add_node({x=x,y=y,z=z, name_id = 1})
					end
				end
				-- build ground level under chest
				self.plan.data.ground_y = 1
			end
		end

-- TODO: go to customizing screen
		self.infotext = "Build preparation"
		self:set_form("status")
		self:run_async(self.prepare_building_plan)
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
		minetest.after(ASYNC_WAIT, async_call, self.pos)
	end

	--------------------------------------
	-- Async task: Post-processing of plan preparation
	--------------------------------------
	function self.prepare_building_plan(self)
		self.plan:flood_with_air()

		-- self.plan:do_mapping() -- on demand called
		self.current_stage = "ready"
		self:set_form("build_status")
		self:run_async(self.instant_build_chunk) --just trigger, there is a check if active
	end

	--------------------------------------
	-- Async Task: Do a instant build step
	--------------------------------------
	function self.instant_build_chunk(self)
		if not self.info.instantbuild == true then --instantbuild disabled
			return
		end
		dprint("--- Instant build is running")

		local startingpos = self.plan:get_random_node_pos()
		if not startingpos then
			self.info.instantbuild = false
			return false
		end

		local chunk_pos = self.plan:get_world_pos(startingpos)
		dprint("---build chunk", minetest.pos_to_string(startingpos))

-- TODO: in customizing switchable implementation
--[[ --- implementation with VoxelArea - bad gameplay responsivity :( - back to per-node update
		-- work on VoxelArea
		local vm = minetest.get_voxel_manip()
		local minp, maxp = vm:read_from_map(chunk_pos, chunk_pos)
		local a = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
		local data = vm:get_data()
		local param2_data = vm:get_param2_data()
		local light_fix = {}
		local meta_fix = {}
--		for idx in a:iterp(vector.add(minp, 8), vector.subtract(maxp, 8)) do -- do not touch for beter light update
		for idx, origdata in pairs(data) do -- do not touch for beter light update
			local wpos = a:position(idx)
			local pos = self.plan:get_plan_pos(wpos)
			if wpos.x ~= self.pos.x or wpos.y ~= self.pos.y or wpos.z ~= self.pos.z then --skip chest pos
				local node = self.plan:prepare_node_for_build(pos, wpos)
				if node and node.content_id then
					-- write to voxel
					data[idx] = node.content_id
					param2_data[idx] = node.param2

					-- mark for light update
					assert(node.node_def, dump(node))
					if node.node_def.light_source and node.node_def.light_source > 0 then
						table.insert(light_fix, {pos = wpos, node = node})
					end
					if node.meta then
						table.insert(meta_fix, {pos = wpos, node = node})
					end
					self.plan:remove_node(node)
				--TODO: metadata
				end
			end
			self.plan:remove_node(pos) --if exists
		end

		-- store the changed map data
		vm:set_data(data)
		vm:set_param2_data(param2_data)
		vm:calc_lighting()
		vm:update_liquids()
		vm:write_to_map()
		vm:update_map()

		-- fix the lights
		dprint("fix lights", #light_fix)
		for _, fix in ipairs(light_fix) do
			minetest.env:add_node(fix.pos, fix.node)
		end

		dprint("process meta", #meta_fix)
		for _, fix in ipairs(meta_fix) do
			minetest.env:get_meta(fix.pos):from_table(fix.node.meta)
		end
]]

		-- implementation using usual "add_node"
		local chunk_nodes = self.plan:get_nodes_for_chunk(self.plan:get_plan_pos(chunk_pos))
		dprint("Instant build of chunk: nodes:", #chunk_nodes)
		for idx, nodeplan in ipairs(chunk_nodes) do
			if nodeplan.wpos.x ~= self.pos.x or nodeplan.wpos.y ~= self.pos.y or nodeplan.wpos.z ~= self.pos.z then --skip chest pos
				if nodeplan.node then
					minetest.env:add_node(nodeplan.wpos, nodeplan.node)
					if nodeplan.node.meta then
						minetest.env:get_meta(nodeplan.wpos):from_table(nodeplan.node.meta)
					end
				end
			end
			self.plan:remove_node(nodeplan.pos)
		end

		-- chunk done handle next chunk call
		dprint("instant nodes left:", self.plan.data.nodecount)
		self:update_info("build_status")
		if self.plan.data.nodecount > 0 then
			--start next plan chain
			return true
		else
			-- finished. disable processing
			self.info.instantbuild = false
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
			self:persist_info()
			self:set_rawdata(chestinfo.taskname)
		else
			self:set_form("file_open")
		end
	end

	-- retrun the chest object in townchest.chest.new()
	return self
end
