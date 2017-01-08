local dprint = townchest.dprint_off --debug
--local dprint = townchest.dprint--debug

townchest.plan = {}

townchest.plan.new = function( chest )
	local self = {}
	self.chest = chest

	-- helper: get scm entry for position
	function self.get_scm_node(self, pos)
		assert(pos.x, "pos without xyz")
		if self.data.scm_data_cache[pos.y] == nil then
			return nil
		end
		if self.data.scm_data_cache[pos.y][pos.x] == nil then
			return nil
		end
		if self.data.scm_data_cache[pos.y][pos.x][pos.z] == nil then
			return nil
		end
		return self.data.scm_data_cache[pos.y][pos.x][pos.z]
	end

-- "node" = {x=,y=,z=,name_id=,param2=}
	function self.add_node(self, node)
		-- insert new
		if self.data.scm_data_cache[node.y] == nil then
			self.data.scm_data_cache[node.y] = {}
		end
		if self.data.scm_data_cache[node.y][node.x] == nil then
			self.data.scm_data_cache[node.y][node.x] = {}
		end
		self.data.nodecount = self.data.nodecount + 1
		self.data.scm_data_cache[node.y][node.x][node.z] = node
	end


	function self.flood_with_air(self)
		self.data.ground_y =  math.floor(self.data.ground_y)
		local add_max = 5
		local additional = 0

		-- define nodename-ID for air
		local air_id = #self.data.nodenames + 1
		self.data.nodenames[ air_id ] = "air"

		dprint("create flatting plan")
		for y = self.data.min_pos.y, self.data.max_pos.y + 5 do -- with additional 5 on top
			--calculate additional grounding
			if y > self.data.ground_y then --only over ground
				local high = y-self.data.ground_y
				additional = high + 1
				if additional > add_max then --set to max
					additional = add_max
				end
			end

			dprint("flat level:", y)

			for x = self.data.min_pos.x - additional, self.data.max_pos.x + additional do
				for z = self.data.min_pos.z - additional, self.data.max_pos.z + additional do
					local airnode = {x=x, y=y, z=z, name_id=air_id}
					if self:get_scm_node(airnode) == nil then
						self:add_node(airnode)
					end
				end
			end
		end
		dprint("flatting plan done")
	end


	function self.get_world_pos(self,pos)
		return {	x=pos.x+self.chest.pos.x,
						y=pos.y+self.chest.pos.y - self.data.ground_y - 1,
						z=pos.z+self.chest.pos.z
					}
	end

	-- revert get_world_pos
	function self.get_plan_pos(self,pos)
		return {	x=pos.x-self.chest.pos.x,
						y=pos.y-self.chest.pos.y + self.data.ground_y + 1,
						z=pos.z-self.chest.pos.z
					}
	end


-- get nodes for selection which one should be build
-- skip parameter is randomized
	function self.get_random_node_pos(self)
		dprint("get something from list")

		-- get random existing y
		local keyset = {}
		for k in pairs(self.data.scm_data_cache) do table.insert(keyset, k) end
		if #keyset == 0 then --finished
			return nil
		end
		local y = keyset[math.random(#keyset)]

		-- get random existing x
		keyset = {}
		for k in pairs(self.data.scm_data_cache[y]) do table.insert(keyset, k) end
		local x = keyset[math.random(#keyset)]

		-- get random existing z
		keyset = {}
		for k in pairs(self.data.scm_data_cache[y][x]) do table.insert(keyset, k) end
		local z = keyset[math.random(#keyset)]

		if z ~= nil then
			return {x=x,y=y,z=z}
		end
	end

-- to be able working with forceload chunks
	function self.get_nodes_for_chunk(self, node)

	-- calculate the begin of the chunk
		--local BLOCKSIZE = core.MAP_BLOCKSIZE
		local BLOCKSIZE = 16
		local wpos = self:get_world_pos(node)
		local minp = {}
		minp.x = (math.floor(wpos.x/BLOCKSIZE))*BLOCKSIZE
		minp.y = (math.floor(wpos.y/BLOCKSIZE))*BLOCKSIZE
		minp.z = (math.floor(wpos.z/BLOCKSIZE))*BLOCKSIZE
		local maxp = vector.add(minp, 16)

		dprint("nodes for chunk (real-pos)", minetest.pos_to_string(minp), minetest.pos_to_string(maxp))

		local minv = self:get_plan_pos(minp)
		local maxv = self:get_plan_pos(maxp)
		dprint("nodes for chunk (plan-pos)", minetest.pos_to_string(minv), minetest.pos_to_string(maxv))

		local ret = {}
		for y = minv.y, maxv.y do
			if self.data.scm_data_cache[y] ~= nil then
				for x = minv.x, maxv.x do
					if self.data.scm_data_cache[y][x] ~= nil then
						for z = minv.z, maxv.z do
							if self.data.scm_data_cache[y][x][z] ~= nil then
								local pos = {x=x,y=y,z=z}
								local wpos = self:get_world_pos(pos)
								table.insert(ret, {pos = pos, wpos = wpos, node=self:prepare_node_for_build(pos, wpos)})
							end
						end
					end
				end
			end
		end
		dprint("nodes in chunk to build", #ret)
		return ret
	end

	function self.remove_node(self, pos)
		-- cleanup raw data
		if self.data.scm_data_cache[pos.y] ~= nil then
			if self.data.scm_data_cache[pos.y][pos.x] ~= nil then
				if self.data.scm_data_cache[pos.y][pos.x][pos.z] ~= nil then
					self.data.nodecount = self.data.nodecount - 1
					self.data.scm_data_cache[pos.y][pos.x][pos.z] = nil
				end
				if next(self.data.scm_data_cache[pos.y][pos.x]) == nil then
					self.data.scm_data_cache[pos.y][pos.x] = nil
				end
			end
			if next(self.data.scm_data_cache[pos.y]) == nil then
				self.data.scm_data_cache[pos.y] = nil
			end
		end

		-- remove cached mapping data
		if self.data.prepared_cache and self.data.prepared_cache[pos.y] ~= nil then
			if self.data.prepared_cache[pos.y][pos.x]then
				if self.data.prepared_cache[pos.y][pos.x][pos.z] ~= nil then
					self.data.prepared_cache[pos.y][pos.x][pos.z] = nil
				end
				if next(self.data.prepared_cache[pos.y][pos.x]) == nil then
					self.data.prepared_cache[pos.y][pos.x] = nil
				end
			end
			if next(self.data.prepared_cache[pos.y]) == nil then
				self.data.prepared_cache[pos.y] = nil
			end
		end
	end


	-- prepare node for build
	function self.prepare_node_for_build(self, pos, wpos)
		-- first run, generate mapping data
		if self.data.mappednodes == nil then
			townchest.mapping.do_mapping(self.data)
		end

		-- get from cache
		if self.data.prepared_cache ~= nil and
				self.data.prepared_cache[pos.y] ~= nil and
				self.data.prepared_cache[pos.y][pos.x] ~= nil and
				self.data.prepared_cache[pos.y][pos.x][pos.z] ~= nil then
			return self.data.prepared_cache[pos.y][pos.x][pos.z]
		end

		-- get scm data
		local scm_node = self:get_scm_node(pos)
		if scm_node == nil then
			return nil
		end

		--get mapping data
		local map = self.data.mappednodes[scm_node.name_id]
		if map == nil then
			return nil
		end

		local node = townchest.mapping.merge_map_entry(map, scm_node)

		if node.custom_function ~= nil then
			node.custom_function(node, pos, wpos)
		end

		-- maybe node name is changed in custom function. Update the content_id in this case
		node.content_id = minetest.get_content_id(node.name)
		node.node_def = minetest.registered_nodes[node.name]

		-- store the mapped node info in cache
		if self.data.prepared_cache == nil then
			self.data.prepared_cache = {}
		end
		if self.data.prepared_cache[pos.y] == nil then
			self.data.prepared_cache[pos.y] = {}
		end
		if self.data.prepared_cache[pos.y][pos.x] == nil then
			self.data.prepared_cache[pos.y][pos.x] = {}
		end
		self.data.prepared_cache[pos.y][pos.x][pos.z] = node

		return node
	end

--------------------
--------------------
	return self -- the plan object
end
