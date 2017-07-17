--local dprint = townchest.dprint
local dprint = townchest.dprint_off --debug

local smartfs = townchest.smartfs

local ASYNC_WAIT=0.05  -- schould be > 0 to restrict performance consumption
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
		smartfs.get("townchest:"..formname):attach_to_node(self.pos)
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
		self.plan = schemlib.plan.new(minetest.pos_to_string(self.pos), self.pos)
		self.plan.chest = self
		self.plan.on_status = townchest.npc.plan_update_hook

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
			self.plan:read_from_schem_file(townchest.modpath.."/buildings/"..self.info.filename)

			if self.plan.data.nodecount == 0 then
				self.infotext = "No building found in ".. self.info.filename
				self:set_form("status")
				self.current_stage = "select"
				self.info.filename = nil
				self:persist_info()
				minetest.after(3, self.set_form, self, "file_open") --back to file selection
				return
			end

		elseif self.info.taskname == "generate" then
			-- set directly instead of counting each step
			self.plan.data.min_pos = { x=1, y=1, z=1 }
			self.plan.data.max_pos = { x=self.info.genblock.x, y=self.info.genblock.y, z=self.info.genblock.z}
			self.plan.data.ground_y = 0
			local filler_node = {name = "default:cobble"}
			if self.info.genblock.variant == 1 then
				-- nothing special, just let fill them with air

			elseif self.info.genblock.variant == 2 then
				-- Fill with stone
				for x = 1, self.info.genblock.x do
					for y = 1, self.info.genblock.y do
						for z = 1, self.info.genblock.z do
							self.plan:add_node({x=x,y=y,z=z}, schemlib.node.new(filler_node))
						end
					end
				end

			elseif self.info.genblock.variant == 3 then
				-- Build a box
				for x = 1, self.info.genblock.x do
					for y = 1, self.info.genblock.y do
						for z = 1, self.info.genblock.z do
							if x == 1 or x == self.info.genblock.x or
									y == 1 or y == self.info.genblock.y or
									z == 1 or z == self.info.genblock.z then
								self.plan:add_node({x=x,y=y,z=z}, schemlib.node.new(filler_node))
							end
						end
					end
				end

				-- build ground level under chest
				self.plan.data.ground_y = 1

			-- Build a plate
			elseif self.info.genblock.variant == 4 then
				local y = self.plan.data.min_pos.y
				self.plan.data.max_pos.y = self.plan.data.min_pos.y
				for x = 1, self.info.genblock.x do
					for z = 1, self.info.genblock.z do
						self.plan:add_node({x=x,y=y,z=z}, schemlib.node.new(filler_node))
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
		self.plan:apply_flood_with_air(3, 0, 5) --(add_max, add_min, add_top)
		self.plan:del_node(self.plan:get_plan_pos(self.pos)) -- Do not override the chest node
		self.current_stage = "ready"
		self:set_form("build_status")
		if self.info.npc_build == true then
			self.plan:set_status("build")
			townchest.npc.enable_build(self.plan)
		end
		if self.info.instantbuild == true then
			self.plan:set_status("build")
			self:run_async(self.instant_build_chunk)
		end
	end

	--------------------------------------
	-- Async Task: Do a instant build step
	--------------------------------------
	function self.instant_build_chunk(self)
		dprint("chunk processing called", self.info.instantbuild)
		if not self.info.instantbuild == true then --instantbuild disabled
			return
		end
		dprint("--- Instant build is running")

		local random_pos = self.plan:get_random_plan_pos()
		if not random_pos then
			self.info.instantbuild = false
			return false
		end

		dprint("---build chunk", minetest.pos_to_string(random_pos))

--		self.plan:do_add_chunk(random_pos)
		self.plan:do_add_chunk_voxel(random_pos)
		-- chunk done handle next chunk call
		dprint("instant nodes left:", self.plan.data.nodecount)
		if self.plan:get_status() == "build" then
			self:update_info("build_status")
			--start next plan chain
			return true
		else
			-- finished. disable processing
			self.info.npc_build = false
			self.info.instantbuild = false
			self:update_info("build_status")
			return false
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
