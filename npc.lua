local dprint = townchest.dprint --debug

--[[
local __die = function(this)
	dprint("npc:die")
	townchest.npc.entity_list[this.lua.npc_key] = nil --not needed, already no this
	this.entity:remove()
end
]]--



	-- API
	-- self: the lua entity
	-- pos: the position to move to
	-- range: the distance within pos the npc will go to
	-- range_y: the height within pos the npc will go to
	-- speed: the speed at which the npc will move
	-- after: callback function(self) which is triggered when the npc gets within range of pos
local __moveto = function(self, pos)
--	self.target = pos
	self.target = {} --independend table/reference
	self.target.x = pos.x
	self.target.y = pos.y + 1.5 --always try to be over the working place
	self.target.z = pos.z
	self.speed = 1
	self.range = 0.5
	self.range_y = 0.5
	self.speed = 1
end


local __get_staticdata = function(this)
	if this.data then
		return minetest.serialize(this.data)
	end
end


local __on_activate = function(this, staticdata)

	dprint("npc: on_activate")
	this.data = minetest.deserialize(staticdata)

	if not this.data then
		this.data = {}
	end
	local data = this.data
end


local __on_punch = function(this)
--[[
	-- remove npc from the list of npcs when they die
	if self.object:get_hp() <= 0 and self.npc_pos then
		townchest.npc.entity_list[self.npc_pos] = nil
	end
]]--
end

local __select_chest = function(this)
	-- do nothing if the chest not ready
	if not this.data.chestpos
			or not townchest.chest.list[this.data.chestpos.x..","..this.data.chestpos.y..","..this.data.chestpos.z] --chest position not valid
			or not this.chest
			or not this.chest:npc_build_allowed() then --chest buid not ready

		local npcpos = this.object:getpos()
		local selectedchest = nil
		for key, chest in pairs(townchest.chest.list) do
			if (not selectedchest or vector.distance(npcpos, chest.pos) < vector.distance(npcpos, selectedchest.pos)) and chest:npc_build_allowed() then
				selectedchest = chest
			end
		end
		if selectedchest then
			this.data.chestpos = selectedchest.pos
			this.chest = selectedchest
			dprint("Now I will build for chest",this.chest)
		else --stay if no chest assigned
			this.chest = nil
			this.chestpos = nil
			this.target = nil
			this.speed = nil
		end
	else
		dprint("Chest ok:",this.chest)
	end
end

local __get_if_buildable = function(this, realpos)
	local pos = this.chest.plan:get_plan_pos(realpos)
--	dprint("in plan", pos.x.."/"..pos.y.."/"..pos.z)
	local node = this.chest.plan.building_full[pos.x..","..pos.y..","..pos.z]
	if not node then
		return nil
	end
	-- skip the chest position
	if realpos.x == this.chest.pos.x and realpos.y == this.chest.pos.y and realpos.z == this.chest.pos.z then --skip chest pos
		this.chest.plan:set_node_processed(node)
		return nil
	end

	-- check if already build (skip the most air)
	local success = minetest.forceload_block(realpos) --keep the target node loaded
	if not success then
		dprint("error forceloading:", realpos.x.."/"..realpos.y.."/"..realpos.z)
	end
	local orig_node = minetest.get_node(realpos)
	minetest.forceload_free_block(realpos)
	if orig_node.name == "ignore" then
		minetest.get_voxel_manip():read_from_map(realpos, realpos)
		orig_node = minetest.get_node(realpos)
	end
	
	if orig_node.name == "ignore" then --not loaded chunk. can be forced by forceload_block before check if buildable
		dprint("check ignored")
		return nil
	end

	if orig_node.name == node.name or orig_node.name == minetest.registered_nodes[node.name].name then 
		-- right node is at the place. there are no costs to touch them. Check if a touch needed
		if (node.param2 ~= orig_node.param2 and not (node.param2 == nil and orig_node.param2  == 0)) then
			--param2 adjustment
--			node.matname = townchest.nodes.c_free_item -- adjust params for free
			return node
		elseif not node.meta then
			--same item without metadata. nothing to do
			this.chest.plan:set_node_processed(node)
			return nil
		elseif townchest.nodes.is_equal_meta(minetest.get_meta(realpos):to_table(), node.meta) then
			--metadata adjustment
			this.chest.plan:set_node_processed(node)
			return nil
		elseif node.matname == townchest.nodes.c_free_item then
			-- TODO: check if nearly nodes are already built
			return node
		else
			return node
		end
	else
		-- no right node at place
		return node
	end
end


local __get_target = function(this)
	local npcpos = this.object:getpos()
	local plan = this.chest.plan
	npcpos.y = npcpos.y - 3  -- npc is 1.5 blocks over the work, so we need to be "lower" in calculation
	                         -- prefer lower building nodes, so we check the distance to the next 1.5 blocks lower
	local selectednode
	
	-- first try: look for nearly buildable nodes
	dprint("search for nearly node")
	for x=math.floor(npcpos.x)-3, math.floor(npcpos.x)+3 do
		for y=math.floor(npcpos.y)-3, math.floor(npcpos.y)+3 do
			for z=math.floor(npcpos.z)-3, math.floor(npcpos.z)+3 do
				local node = __get_if_buildable(this,{x=x,y=y,z=z})
				if node then
					node.pos = plan:get_world_pos(node)
					if not selectednode or vector.distance(npcpos, node.pos) < vector.distance(npcpos, selectednode.pos) then
						selectednode = node
					end
				end
			end
		end
	end
	
	if not selectednode then
	-- get the old target to compare
		if this.targetnode and this.targetnode.pos then -- this.targetnode.pos extra check because on building reload the target is there but the position is away
--			minetest.forceload_block(this.targetnode.pos) --keep the target node loaded
			selectednode = __get_if_buildable(this, this.targetnode.pos)
--			minetest.forceload_free_block(this.targetnode.pos)
		end
		
		-- second try. Check the current chunk
		dprint("search for node in current chunk")
		for idx, nodeplan in ipairs(plan:get_nodes_from_chunk(plan:get_plan_pos(npcpos))) do
			local node = __get_if_buildable(this, plan:get_world_pos(nodeplan))
			if node then
				node.pos = plan:get_world_pos(node)
				if not selectednode or vector.distance(npcpos, node.pos) < vector.distance(npcpos, selectednode.pos) then
					selectednode = node
				end
			end
		end
	
		--get anything - with forceloading, so the NPC can go away
		dprint("get node with random jump")
		local jump = plan.building_size
		if jump > 1000 then
			jump = 1000
		end
		if jump > 1 then
			jump = math.floor(math.random(jump))
		else
			jump = 0
		end
		
		local startingnode = plan:get_nodes(1,jump)
		if startingnode[1] then -- the one node given
			dprint("---check chunk", startingnode[1].x.."/"..startingnode[1].y.."/"..startingnode[1].z)
			for idx, nodeplan in ipairs(plan:get_nodes_from_chunk(startingnode[1])) do
				local node_wp = plan:get_world_pos(nodeplan)
--				minetest.forceload_block(node_wp)
--				dprint("---check node (real)", node_wp.x.."/"..node_wp.y.."/"..node_wp.z)
				local node = __get_if_buildable(this, node_wp)
--				minetest.forceload_free_block(node_wp)
				if node then
					node.pos = node_wp
					if not selectednode or vector.distance(npcpos, node.pos) < vector.distance(npcpos, selectednode.pos) then
						selectednode = node
					end
				end
			end
		else
			dprint("something wrong with startningnode")
		end
	end


	if selectednode then
		selectednode.pos = plan:get_world_pos(selectednode)
		return selectednode
	end
end


local __on_step = function(this, dtime)

	-- handle frequency
	if not this.timer then
		this.timer = 0
	end
	this.timer = this.timer + dtime;
	if this.timer > 1 then
		--it's time to check/get target
		this.timer = 0

		--get the chest assignment
		__select_chest(this)
		if not this.chest then
			dprint("npc: No chest :(" )
			this.object:setvelocity({x=0, y=0, z=0})
			this.target = nil
			this.speed = nil
			return
		end

		if not this.chest.plan or this.chest.plan.building_size == 0 then
			dprint("building done, disable them")
			this.chest.info.npc_build = nil
			return
		end

		this.targetnode = __get_target(this)

		local npcpos = this.object:getpos()
		npcpos.y = npcpos.y - 1.5  -- npc is 1.5 blocks over the work, so we need to be "lower" in calculations

		if this.targetnode then
			dprint("npc: Move to", this.targetnode.pos.x.."/"..this.targetnode.pos.y.."/"..this.targetnode.pos.z  )
			__moveto(this, this.targetnode.pos)
		else
			dprint("npc: No destination :(" )
			this.object:setvelocity({x=0, y=0, z=0})
			this.target = nil
			this.speed = nil
		end
		dprint ("---", this.chest.plan.building_size, "Nodes in building left---")
		
		if this.targetnode and vector.distance(npcpos, this.targetnode.pos) < 2 then
			dprint("target reached. build",this.targetnode.name)
			--- Place node
--			minetest.forceload_block(this.targetnode.pos)
			minetest.env:add_node(this.targetnode.pos, this.targetnode)
			if this.targetnode.meta then
				minetest.env:get_meta(this.targetnode.pos):from_table(this.targetnode.meta)
			end
			this.chest.plan:set_node_processed(this.targetnode)
			this.chest:update_statistics()
		end
	end

	-- walk to target destination
	if this.target and this.speed then
		local s = this.object:getpos()
		local t = this.target
		local diff = {x=t.x-s.x, y=t.y-s.y, z=t.z-s.z}
		--yaw calculation (http://dev.minetest.net/Player)
		local yaw
		if diff.z<0 then yaw = -math.atan(diff.x/diff.z)
		elseif diff.z>0 then yaw = math.pi-math.atan(diff.x/diff.z) 
		elseif diff.x<0 then yaw = 0 
		else yaw = math.pi end
		--yaw calculation end
		
		this.object:setyaw(yaw) -- turn and look in given direction

		-- check if destination reached, reset target in this case
		if math.abs(diff.x) < this.range and math.abs(diff.y) < this.range_y and math.abs(diff.z) < this.range then
			dprint("npc: destination reached")
			this.object:setvelocity({x=0, y=0, z=0})
			this.target = nil
			this.speed = nil
		else
			local v = this.speed
--			if self.food > 0 then
--				self.food = self.food - dtime
--				v = v*4
--			end
			local amount = (diff.x^2+diff.y^2+diff.z^2)^0.5
			local vec = {x=0, y=0, z=0}
			vec.x = diff.x*v/amount
			vec.y = diff.y*v/amount
			vec.z = diff.z*v/amount
			this.object:setvelocity(vec) -- walk in given direction
		end
	else
		this.object:setvelocity({x=0, y=0, z=0})
		this.target = nil
		this.speed = nil
		-- look around if idle
		if math.random(50) == 1 then
			this.object:setyaw(this.object:getyaw()+((math.random(0,360)-180)/180*math.pi))
		end
	end
end



--------------------------------------
-- class attributes and methods
--------------------------------------
townchest.npc = {
--	entity_list = {}, --global entity list
--	get_npc = __get_npc
}

--------------------------------------
-- object definition / constructor
--------------------------------------
townchest.npc.new = function()
	local this = {}
--	this.die = __die
	return this
end



local function x(val) return ((val -80) / 160) end
local function z(val) return ((val -80) / 160) end
local function y(val) return ((val + 80) / 160) end

minetest.register_node("townchest:builder_box", {
	tiles = {
		"towntest_npc_builder_top.png",
		"towntest_npc_builder_bottom.png",
		"towntest_npc_builder_front.png",
		"towntest_npc_builder_back.png",
		"towntest_npc_builder_left.png",
		"towntest_npc_builder_right.png",
	},
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			--head
			{x(95),y(-10), z(65), x(65), y(-40), z(95)},
			--neck
			{x(90),y(-40),z(70) , x(70), y(-50),z(90) },
			--body
			{x(90),y(-50), z(60), x(70), y(-100), z(100)},
			--legs
			{x(90),y(-100), z(60),x(70), y(-160),z(79) },
			{x(90),y(-100), z(81),x(70), y(-160), z(100)},
			--shoulders
			{x(89),y(-50), z(58), x(71),y(-68),z(60)},
			{x(89),y(-50), z(100),x(71) ,y(-68),z(102)},
			--left arm
			{x(139),y(-50),z(45),x(71),y(-63),z(58)},
			--right arm
			{x(89),y(-50),z(102),x(71),y(-100),z(115)},
			{x(115),y(-87),z(102),x(71),y(-100),z(115)},
		}
	},
})

-- register template (static data) to minetest
minetest.register_entity("townchest:builder", {
	hp_max = 1,
	physical = false,
	makes_footstep_sound = true,
	collisionbox = {-0.4, -1, -0.4, 0.4, 1, 0.4},

	visual_size = nil,
	visual = "wielditem",
	textures = {"townchest:builder_box"},

	target = nil,
	speed = nil,
	range = nil,
	range_y = nil,
	after = nil,
	after_param = nil,
	food = 0,
	get_staticdata = __get_staticdata,
	on_activate = __on_activate,
	on_punch = __on_punch,
	on_step = __on_step,
	moveto = __moveto
})

