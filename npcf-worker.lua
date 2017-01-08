local dprint = townchest.dprint_off --debug
--local dprint = townchest.dprint

local MAX_SPEED = 5
local BUILD_DISTANCE = 3
local HOME_RANGE = 10


townchest.npc = {
	spawn_nearly = function(pos, owner)
		local npcid = tostring(math.random(10000))
		npcf.index[npcid] = owner --owner
		local ref = {
			id = npcid,
			pos = {x=(pos.x+math.random(0,4)-4),y=(pos.y + 0.5),z=(pos.z+math.random(0,4)-4)},
			yaw = math.random(math.pi),
			name = "townchest:npcf_builder",
			owner = owner,
		}
		local npc = npcf:add_npc(ref)
		npcf:save(ref.id)
		if npc then
			npc:update()
		end
	end
}

local function get_speed(distance)
	local speed = distance * 0.5
	if speed > MAX_SPEED then
		speed = MAX_SPEED
	end
	return speed
end


local select_chest = function(self)
	-- do nothing if the chest not ready
	if not self.metadata.chestpos
			or not townchest.chest.list[minetest.pos_to_string(self.metadata.chestpos)] --chest position not valid
			or not self.chest
			or not self.chest:npc_build_allowed() then --chest buid not ready

		local npcpos = self.object:getpos()
		local selectedchest = nil
		for key, chest in pairs(townchest.chest.list) do
			if (not selectedchest or vector.distance(npcpos, chest.pos) < vector.distance(npcpos, selectedchest.pos)) and chest:npc_build_allowed() then
				selectedchest = chest
			end
		end
		if selectedchest then
			self.metadata.chestpos = selectedchest.pos
			self.chest = selectedchest
			dprint("Now I will build for chest",self.chest)

			-- the chest is the new home of npc
			if vector.distance(self.origin.pos, selectedchest.pos) > HOME_RANGE then
				self.origin.pos = selectedchest.pos
				self.origin.yaw = npcf:get_face_direction(npcpos, selectedchest.pos)
			end

		else --stay if no chest assigned
			self.metadata.chestpos = nil
			self.chest = nil
			self.chestpos = nil
		end
	end
end


local get_if_buildable = function(self, realpos, node_prep)
	local pos = self.chest.plan:get_plan_pos(realpos)
	local node
	if node_prep then
		node = node_prep
	else
		node = self.chest.plan:prepare_node_for_build(pos, realpos)
	end

	if not node then
		-- remove something crufty
		self.chest.plan:remove_node(pos)
		return nil
	end

	-- skip the chest position
	if realpos.x == self.chest.pos.x and realpos.y == self.chest.pos.y and realpos.z == self.chest.pos.z then --skip chest pos
		self.chest.plan:remove_node(pos)
		return nil
	end

	-- get info about placed node to compare
	local orig_node = minetest.get_node(realpos)
	if orig_node.name == "ignore" then
		minetest.get_voxel_manip():read_from_map(realpos, realpos)
		orig_node = minetest.get_node(realpos)
	end

	if not orig_node or orig_node.name == "ignore" then --not loaded chunk. can be forced by forceload_block before check if buildable
		dprint("ignore node at", minetest.pos_to_string(realpos))
		return nil
	end

	-- check if already built
	if orig_node.name == node.name or orig_node.name == minetest.registered_nodes[node.name].name then 
		-- right node is at the place. there are no costs to touch them. Check if a touch needed
		if (node.param2 ~= orig_node.param2 and not (node.param2 == nil and orig_node.param2  == 0)) then
			--param2 adjustment
--			node.matname = townchest.mapping.c_free_item -- adjust params for free
			return node
		elseif not node.meta then
			--same item without metadata. nothing to do
			self.chest.plan:remove_node(pos)
			return nil
		elseif townchest.mapping.is_equal_meta(minetest.get_meta(realpos):to_table(), node.meta) then
			--metadata adjustment
			self.chest.plan:remove_node(pos)
			return nil
		elseif node.matname == townchest.mapping.c_free_item then
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


local function prefer_target(npc, t1, t2)
	if not t1 then
		return t2
	end

	local npcpos = npc.object:getpos()
	-- npc is 1.5 blocks over the work
	npcpos.y = npcpos.y - 1.5

	-- variables for preference manipulation
	local t1_c = {x=t1.pos.x, y=t1.pos.y, z=t1.pos.z}
	local t2_c = {x=t2.pos.x, y=t2.pos.y, z=t2.pos.z}
	local prefer = 0

	--prefer same items in building order
	if npc.lastnode then
		if npc.lastnode.name == t1.name then
			prefer = prefer + 2.5
		end
		if npc.lastnode.name == t2.name then
			prefer = prefer - 2.5
		end
	end

	-- prefer the last target node
	if npc.targetnode then
		if t1.pos.x == npc.targetnode.pos.x and
				t1.pos.y == npc.targetnode.pos.y and
				t1.pos.z == npc.targetnode.pos.z then
			prefer = prefer + BUILD_DISTANCE
		end
		if t2.pos.x == npc.targetnode.pos.x and
				t2.pos.y == npc.targetnode.pos.y and
				t2.pos.z == npc.targetnode.pos.z then
			prefer = prefer - BUILD_DISTANCE
		end
	end

	-- prefer air in general
	if t1.name == "air" then
		prefer = prefer + 2
	end
	if t2.name == "air" then
		prefer = prefer - 2
	end

	-- prefer reachable in general
	if vector.distance(npcpos, t1.pos) <= BUILD_DISTANCE then
		prefer = prefer + 2
	end
	if vector.distance(npcpos, t2.pos) <= BUILD_DISTANCE then
		prefer = prefer - 2
	end

	-- prefer lower node if not air
	if t1.name ~= "air" then
		t1_c.y = t1_c.y + 2
	elseif math.abs(npcpos.y - t1.pos.y) <= BUILD_DISTANCE then
		-- prefer higher node if air in reachable distance
		t1_c.y = t1_c.y - 4
	end

	-- prefer lower node if not air
	if t2.name ~= "air" then
		t2_c.y = t2_c.y + 2
	elseif math.abs(npcpos.y - t1.pos.y) <= BUILD_DISTANCE then
		-- prefer higher node if air in reachable distance
		t2_c.y = t2_c.y - 4
	end

	-- avoid build directly under or in the npc
	if math.abs(npcpos.x - t1.pos.x) < 0.5 and
			math.abs(npcpos.y - t1.pos.y) < 3 and
			math.abs(npcpos.z - t1.pos.z) < 0.5 then
		prefer = prefer-1.5
	end
	if math.abs(npcpos.x - t2.pos.x) < 0.5 and
			math.abs(npcpos.y - t1.pos.y) < 3 and
			math.abs(npcpos.z - t2.pos.z) < 0.5 then
		prefer = prefer+1.5
	end

	-- compare
	if vector.distance(npcpos, t1_c) - prefer > vector.distance(npcpos, t2_c) then
		return t2
	else
		return t1
	end

end


local get_target = function(self)
	local npcpos = self.object:getpos()
	local plan = self.chest.plan
	npcpos.y = npcpos.y - 1.5  -- npc is 1.5 blocks over the work

	local npcpos_round = vector.round(npcpos)
	local selectednode

	-- first try: look for nearly buildable nodes
	dprint("search for nearly node")
	for x=npcpos_round.x-5, npcpos_round.x+5 do
		for y=npcpos_round.y-5, npcpos_round.y+5 do
			for z=npcpos_round.z-5, npcpos_round.z+5 do
				local node = get_if_buildable(self,{x=x,y=y,z=z})
				if node then
					node.pos = {x=x,y=y,z=z}
					selectednode = prefer_target(self, selectednode, node)
				end
			end
		end
	end
	if selectednode then
		dprint("nearly found: NPC: "..minetest.pos_to_string(npcpos).." Block "..minetest.pos_to_string(selectednode.pos))
	end

	if not selectednode then
		dprint("nearly nothing found")
		-- get the old target to compare
		if self.targetnode and self.targetnode.pos and
				(self.targetnode.node_id or self.targetnode.name) then
			selectednode = get_if_buildable(self, self.targetnode.pos, self.targetnode)
		end
	end

	-- second try. Check the current chunk
	dprint("search for node in current chunk")

	local chunk_nodes = plan:get_nodes_for_chunk(plan:get_plan_pos(npcpos_round))
	dprint("Chunk loaeded: nodes:", #chunk_nodes)

	for idx, nodeplan in ipairs(chunk_nodes) do
		local node = get_if_buildable(self, nodeplan.wpos, nodeplan.node)
		if node then
			node.pos = nodeplan.wpos
			selectednode = prefer_target(self, selectednode, node)
		end
	end

	if selectednode then
		dprint("found in current chunk: NPC: "..minetest.pos_to_string(npcpos).." Block "..minetest.pos_to_string(selectednode.pos))
	end

	if not selectednode then
		dprint("get random node")

		local random_pos = plan:get_random_node_pos()
		if random_pos then
			dprint("---check chunk", minetest.pos_to_string(random_pos))
			local wpos = plan:get_world_pos(random_pos)
			local node = get_if_buildable(self, wpos)
			if node then
				node.pos = wpos
				selectednode = prefer_target(self, selectednode, node)
			end

			if selectednode then
				dprint("random node: Block "..minetest.pos_to_string(random_pos))
			else
				dprint("random node not buildable, check the whole chunk", minetest.pos_to_string(random_pos))
				local chunk_nodes = plan:get_nodes_for_chunk(random_pos)
				dprint("Chunk loaeded: nodes:", #chunk_nodes)

				for idx, nodeplan in ipairs(chunk_nodes) do
					local node = get_if_buildable(self, nodeplan.wpos, nodeplan.node)
					if node then
						node.pos = nodeplan.wpos
						selectednode = prefer_target(self, selectednode, node)
					end
				end
				if selectednode then
					dprint("found in current chunk: Block "..minetest.pos_to_string(selectednode.pos))
				end
			end
		else
			dprint("something wrong with random_pos")
		end
	end

	if selectednode then
		assert(selectednode.pos, "BUG: a position should exists")
		return selectednode
	else
		dprint("no next node found", plan.data.nodecount)
		if plan.data.nodecount == 0 then
			self.chest.info.npc_build = false
		end
		self.chest:update_statistics()
	end
end

npcf:register_npc("townchest:npcf_builder" ,{
	description = "Townchest Builder NPC",
	textures = {"npcf_builder_skin.png"},
	stepheight = 1.1,
	inventory_image = "npcf_builder_inv.png",
	on_step = function(self)
		if self.timer > 1 then
			self.timer = 0
			select_chest(self)
			self.target_prev = self.targetnode
			if self.chest and self.chest.plan and self.chest.plan.data.nodecount > 0 then
				self.targetnode = get_target(self)
				self.dest_type = "build"
			else
				if self.dest_type ~= "home_reached" then
					self.targetnode = self.origin
					self.dest_type = "home"
				end
			end

-- simple check if target reached
		elseif self.targetnode then
			local pos = self.object:getpos()
			local target_distance = vector.distance(pos, self.targetnode.pos)
			if target_distance < 1 then
				local yaw = self.object:getyaw()
				local speed = 0
				self.object:setvelocity(npcf:get_walk_velocity(speed, self.object:getvelocity().y, yaw))
			end
			return
		end

		local pos = self.object:getpos()
		local yaw = self.object:getyaw()
		local state = NPCF_ANIM_STAND
		local speed = 0
		local acceleration = {x=0, y=-10, z=0}
		if self.targetnode then
			local target_distance = vector.distance(pos, self.targetnode.pos)
			local last_distance = 0
			if self.var.last_pos then
				last_distance = vector.distance(self.var.last_pos, self.targetnode.pos)
			end

			yaw = npcf:get_face_direction(pos, self.targetnode.pos)
			-- target reached build
			if target_distance <= BUILD_DISTANCE and self.dest_type == "build" then
				dprint("target reached - build", self.targetnode.name, minetest.pos_to_string(self.targetnode.pos))
				-- do the build  ---TODO: move outsite of this function
				local soundspec
				if minetest.registered_items[self.targetnode.name].sounds then
					soundspec = minetest.registered_items[self.targetnode.name].sounds.place
				elseif self.targetnode.name == "air" then --TODO: should be determinated on old node, if the material handling is implemented
					soundspec = default.node_sound_leaves_defaults({place = {name = "default_place_node", gain = 0.25}})
				end
				if soundspec then
					soundspec.pos = pos
					minetest.sound_play(soundspec.name, soundspec)
				end
				minetest.env:add_node(self.targetnode.pos, self.targetnode)
				if self.targetnode.meta then
					minetest.env:get_meta(self.targetnode.pos):from_table(self.targetnode.meta)
				end
				self.chest.plan:remove_node(self.targetnode)
				self.chest:update_statistics()

				local cur_pos = {x=pos.x, y=pos.y - 0.5, z=pos.z}
				local cur_node = minetest.registered_items[minetest.get_node(cur_pos).name]
				if cur_node.walkable then
					pos = {x=pos.x, y=pos.y + 1.5, z=pos.z}
					self.object:setpos(pos)
				end

				if target_distance > 2 then
					speed = 1
					state = NPCF_ANIM_WALK_MINE
				else
					speed = 0
					state = NPCF_ANIM_MINE
				end

				self.timer = 0
				self.lastnode = self.targetnode
				self.laststep = "build"
				self.targetnode = nil
				self.path = nil
			-- home reached
			elseif target_distance < HOME_RANGE and self.dest_type == "home" then
--				self.object:setpos(self.origin.pos)
				yaw = self.origin.yaw
				speed = 0
				self.dest_type = "home_reached"
				self.targetnode = nil
				self.path = nil
			else
				--target not reached -- route
				state = NPCF_ANIM_WALK
				-- Big jump / teleport upsite
				if (self.targetnode.pos.y -(pos.y-1.5)) > BUILD_DISTANCE and
						math.abs(self.targetnode.pos.x - pos.x) <= 0.5 and
						math.abs(self.targetnode.pos.z - pos.z) <= 0.5 then
					acceleration = {x=0, y=0, z=0}
					pos = {x=pos.x, y=self.targetnode.pos.y + 1.5, z=pos.z}
					self.object:setpos(pos)
					target_distance = 0 -- to skip the next part and set speed to 0
					state = NPCF_ANIM_STAND
					self.path = nil
					dprint("Big jump to"..minetest.pos_to_string(pos))
				end

				if self.timer == 0 or not self.path then
					self.path = minetest.find_path(pos, self.targetnode.pos, 10, 1, 5, "A*")
				end

				-- teleport in direction in case of stucking
				dprint("check for stuck:", last_distance, target_distance, self.laststep)
				if not self.path and --no stuck if path known
						(last_distance - 0.01) <= target_distance and -- stucking
						self.laststep == "walk" and -- second step stuck
						self.target_prev and
						( minetest.pos_to_string(self.target_prev.pos) == minetest.pos_to_string(self.targetnode.pos)) then -- destination unchanged
					local target_direcion = vector.direction(pos, self.targetnode.pos)
					pos = vector.add(pos, vector.multiply(target_direcion, 2))
					if pos.y < self.targetnode.pos.y then
						pos = {x=pos.x, y=self.targetnode.pos.y + 1.5, z=pos.z}
					end
					self.object:setpos(pos)
					self.laststep = "teleport"
					acceleration = {x=0, y=0, z=0}
					target_distance = 0 -- to skip the next part and set speed to 0
					state = NPCF_ANIM_STAND
					self.path = nil
					dprint("Teleport to"..minetest.pos_to_string(pos))
				end
				self.var.last_pos = pos
				speed = get_speed(target_distance)
				self.laststep = "walk"
			end
		end

		if self.path then
			yaw = npcf:get_face_direction(pos, self.path[1])
		end
		self.object:setacceleration(acceleration)
		self.object:setvelocity(npcf:get_walk_velocity(speed, self.object:getvelocity().y, yaw))
		self.object:setyaw(yaw)
		npcf:set_animation(self, state)
	end,
})

