--local dprint = townchest.dprint
local dprint = townchest.dprint_off --debug

local smartfs = townchest.smartfs

local ASYNC_WAIT=0.05  -- schould be > 0 to restrict performance consumption

--------------------------------------
-- Chest class and interface
--------------------------------------
local chest = {
	list = {},
}
townchest.chest = chest
local chest_class = {}
chest_class.__index = chest_class

--------------------------------------
-- Get or create new chest for position
--------------------------------------
function chest.get(pos)
	local key = minetest.pos_to_string(pos)
	local self = nil
	if chest.list[key] then
		self = chest.list[key]
		self.info = minetest.deserialize(self.meta:get_string("chestinfo")) or {}
	else
		self = chest.new()
		self.key = key
		self.pos = pos
		self.meta = minetest.get_meta(pos) --just pointer
		self.info = minetest.deserialize(self.meta:get_string("chestinfo")) or {}
		if not self.info.anchor_pos then
			self.info.anchor_pos = pos
			self:persist_info()
		end
		if not self.info.chest_facedir then
			local chestnode = minetest.get_node(pos)
			self.info.chest_facedir = chestnode.param2
		end
		townchest.chest.list[key] = self
		self:restore()
	end
	return self
end

--------------------------------------
-- Initialize new chest object
--------------------------------------
function chest.create(pos)
	local key = minetest.pos_to_string(pos)
	dprint("clean key", key)
	chest.list[key] = nil --delete old reference
	minetest.get_meta(pos):set_string("chestinfo","")
	local self = chest.get(pos)
	self.info.stage = "select"
	dprint("created chest object", self)
	return self
end

--------------------------------------
-- object constructor
--------------------------------------
function chest.new()
	local self = setmetatable({}, chest_class)
	self.__index = chest_class
	return self
end


--------------------------------------
-- save persistant chest info to the chest metadata
--------------------------------------
function chest_class:persist_info() -- the read info is in get method
	self.meta:set_string("chestinfo", minetest.serialize(self.info))
end

--------------------------------------
-- set_plan_form - set formspec to specific widget in plan processing chaing
--------------------------------------
function chest_class:set_plan_form()
	self:persist_info()
	if self.info.stage == "finished" then -- no updates if finished
		smartfs.get("townchest:build_finished"):attach_to_node(self.pos)
		self.meta:set_string("infotext", "Building finished")
	elseif not self.plan then
		smartfs.get("townchest:plan"):attach_to_node(self.pos)
		self.meta:set_string("infotext", "please select a building plan")
	elseif self.plan:get_status() == "new" then
		smartfs.get("townchest:configure"):attach_to_node(self.pos)
		self.meta:set_string("infotext", "Configure - Plan size:"..self.plan.data.nodecount)
	else
		smartfs.get("townchest:build_status"):attach_to_node(self.pos)
		self.meta:set_string("infotext", "Plan size:"..self.plan.data.nodecount)
	end
end

--------------------------------------
-- Show message - set formspec to specific widget
--------------------------------------
function chest_class:show_message(message)
	self.infotext = message
	self:persist_info()
	smartfs.get("townchest:status"):attach_to_node(self.pos)
	self.meta:set_string("infotext", message)
	minetest.after(1.5, self.set_plan_form, self)
end


--------------------------------------
-- update informations on formspecs
--------------------------------------
function chest_class:update_info()
	if self.info.stage == "ready" then
		self.meta:set_string("infotext", "Build in process - nodes left:"..self.plan.data.nodecount)
	elseif self.infotext then
		self.meta:set_string("infotext", self.infotext)
	end
	self:persist_info()
	-- send no data / do not change form, but triger onInput to update fields
	smartfs.nodemeta_on_receive_fields(self.pos, "", {})
end

--------------------------------------
-- Create the task that should be managed by chest
--------------------------------------
function chest_class:set_rawdata(taskname)
	self.plan = schemlib.plan.new(minetest.pos_to_string(self.pos), self.pos)
	self.plan.chest = self
	self.plan.on_status = townchest.npc.plan_update_hook
	self.info.taskname = taskname or self.info.taskname

	if self.info.taskname == "file" then
	-- check if file could be read
		if not self.info.filename then
			-- something wrong, back to file selection
			self:show_message("No file selected")
			return
		end
		self.plan:read_from_schem_file(townchest.modpath.."/buildings/"..self.info.filename)
		if self.plan.data.nodecount == 0 then
			self:persist_info()
			self:show_message("No building found in ".. self.info.filename)
			return
		end
		self.info.stage = self.restore_stage or "loaded" -- do not override the restoral stage
		self:show_message("Building Plan loaded ".. self.info.filename)

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
		self.info.stage = self.restore_stage or "loaded"
		self:show_message("Simple form loaded")
	else
		self:show_message("Unknown task")
	end

	if not self.restore_stage or self.restore_stage == "loaded" then
		self.restore_stage = nil
	else
		self:run_async(self.seal_building_plan)
	end
end


--------------------------------------
-- Call a task semi-async trough minetest.after()
--------------------------------------
function chest_class:run_async(func)
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
-- Post-processing of plan preparation
--------------------------------------
function chest_class:seal_building_plan()
	-- apply configuration to the building
	self.plan.anchor_pos = self.info.anchor_pos
	self.plan.facedir = self.info.chest_facedir

	self.plan:apply_flood_with_air()
	self.plan:del_node(self.plan:get_plan_pos(self.pos)) -- Do not override the chest node
	self.info.stage = "ready"
	self.restore_stage = nil
	self.plan:set_status("build")
	if self.info.npc_build == true then
		townchest.npc.enable_build(self.plan)
	end
	if self.info.instantbuild == true then
		self:run_async(self.instant_build_chunk)
	end
	self:set_plan_form()
end

--------------------------------------
-- Async Task: Do a instant build step
--------------------------------------
function chest_class:instant_build_chunk()
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
		self:update_info()
		--start next plan chain
		return true
	else
		self:set_finished()
		return false
	end
end

--------------------------------------
-- restore chest state after shutdown (and maybe suspend if implemented)
--------------------------------------
function chest_class:restore()
	dprint("restoral info", dump(self.info))
	if self.info.stage and self.info.stage ~= "select"
			and self.info.stage ~= "finished" then -- do not restore finished plans
		self.restore_stage = self.info.stage
		self:persist_info()
		self:set_rawdata()
	else
		self:set_plan_form()
	end
end

--------------------------------------
-- Disable all and set the plan finished
--------------------------------------
function chest_class:set_finished()
	self.info.stage = "finished"
	self.info.npc_build = false
	self.info.instantbuild = false
	self:set_plan_form()
	townchest.npc.disable_build(self.plan)
end
