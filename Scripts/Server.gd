extends Node

var network = NetworkedMultiplayerENet.new()
var port = 1909
var max_players = 100

var rng = RandomNumberGenerator.new()

var grid_width : int = 20 # in units
var grid_depth : int = 20 # in units
var cell_size : float = 1 # in meters
var grid = []

var max_head = 1

func _ready():
	rng.randomize()
	create_grid()
	start_server()

func start_server():
	network.create_server(port, max_players)
	get_tree().set_network_peer(network)
	print("Server started!")

	network.connect("peer_connected", self, "user_connected")
	network.connect("peer_disconnected", self, "user_disconnected")

func user_connected(player_id):
	print("User " + str(player_id) + " connected!")

func user_disconnected(player_id):
	print("User " + str(player_id) + " disconnected!")

remote func serve_join(requester):
	var player_id =  get_tree().get_rpc_sender_id()
	var jgarden = to_json(grid)
	rpc_id(player_id,"return_garden",requester, jgarden)

remote func serve_interaction(requester, pos: Vector3):
	var gridpos = world2grid(pos)

	var name = grid[gridpos.x][gridpos.z]
	if name.empty():
		var plant_data = generate_plant()
		register_plant(requester,gridpos, plant_data)
	else:
		grid[gridpos.x][gridpos.z] = ""
		rpc_id(0,"return_remove",requester, gridpos)

# Works with just 1 head 
remote func serve_cross(requester, parent_poss, pos):
	var plant_data = []
	var mean_function = ""
	var mean_length = 0
	var mean_color = [0.0,0.0,0.0]
	var size = parent_poss.size()

	var stalk_data = generate_stalk()
	plant_data.append(stalk_data[0])
	plant_data.append(stalk_data[1])
	plant_data.append_array(generate_color_values(.3,.4,.75,.95,.7,.85))

	for i in range(size):
		var gridpos = world2grid(parent_poss[i])

		var name = grid[gridpos.x][gridpos.z]
		if name.empty():
			push_error("Bad Request. Cant cross a non-existing plant.")
			return
		else:
			var p = JSON.parse(name)
			if typeof(p.result) == TYPE_ARRAY:
				var data = p.result
				if(i == 0):
					mean_function += "("
				else:
					mean_function += " + "
				mean_function += data[5]
				mean_length += data[6]
				mean_color = [mean_color[0] + data[7], mean_color[1] + data[8], mean_color[2] + data[9]]
			else:
				push_error("Parse error. Unexpected type.")
				return

	mean_function += ") / %f" % size
	mean_length = mean_length / size
	mean_color = [mean_color[0] / size, mean_color[1] / size, mean_color[2] / size]
	plant_data.append(mean_function)
	plant_data.append(mean_length)
	plant_data.append_array(mean_color)
	var gridpos = world2grid(pos)
	register_plant(requester, gridpos, plant_data)

func world2grid(pos):
	var x = clamp(floor(pos.x), 0, grid_width-1)
	var z = clamp(floor(pos.z), 0, grid_depth-1)
	var gridpos = Vector3(x,0,z)
	return gridpos

func register_plant(requester, gridpos, plant_data):
	var jplant_data = to_json(plant_data)
	grid[gridpos.x][gridpos.z] = jplant_data
	rpc_id(0,"return_add",requester, jplant_data, gridpos)

func create_grid():
	# make grid matrix
	for x in range(grid_width):
		grid.append([])
		for _y in range(grid_depth):
			grid[x].append("")

func generate_color_values(h_lower: float, h_upper: float, s_lower: float, s_upper: float, v_lower: float, v_upper: float):
	var color = [rng.randf_range(h_lower,h_upper),rng.randf_range(s_lower,s_upper),rng.randf_range(v_lower,v_upper)]
	return color


func generate_plant(head_count:= 0):

	if(head_count == 0):
		head_count = rng.randi_range(1,max_head)

	var plant_data = []

	var stalk_data = generate_stalk()
	plant_data.append(stalk_data[0])
	plant_data.append(stalk_data[1])
	plant_data.append_array(generate_color_values(.3,.4,.75,.95,.7,.85))

	for _i in range(1,head_count + 1):
		var head_data = generate_head()
		plant_data.append(head_data[0])
		plant_data.append(head_data[1])
		plant_data.append_array(generate_color_values(0,1,.75,.95,.8,.9))

	return plant_data

func generate_stalk():
	var boundaries = []
	var vals = []
		
	var stalk_eq
	var stalk_base_eq
	var stalk_disturbance_eq
	var stalk_length

	#var stalk_type = rng.randi_range(0, 1)
	var stalk_type = 1

	# CHOOSE STALK TYPE
	match stalk_type:
		# 1 SCREW (t): R → R³, t ↦ ( a·sin(k·t), b·t, c·cos(k·t))
		0:
			# boundaries to values (2 per value)
			boundaries = [
				1,4, # a
				2,8, # b
				4,16, # c
				2,6 # k
			]
			vals = get_valuesf_inrange(boundaries)

			stalk_base_eq = "Vector3(%f*sin(%f*t), %f*t, %f*cos(%f*t))" % [vals[0], vals[3], vals[1], vals[0], vals[3]]
			
			var stalk_factor = 1/(vals[1]*0.3)
			stalk_length = rng.randf_range(8*stalk_factor, 16*stalk_factor)

		# 2 EXP (t): R → R³, t ↦ (a.t, b·ease(c.t, d), c·cos(k·t))
		1:
			# boundaries to values (2 per value)
			boundaries = [
				30,100, # a
				2,8 # b
			]
			vals = get_valuesf_inrange(boundaries)

			stalk_base_eq = "Vector3(0, %f*ease(t/10, 0.2), 0)" % [vals[0]] # REVIEW THIS
			
			stalk_length = rng.randf_range(5, 25)

	# STALK DISTURBANCE

	boundaries = [
		1,4
	]
	vals = get_valuesf_inrange(boundaries)

	stalk_disturbance_eq = "Vector3(sin(%f*t),sin(%f*t),sin(%f*t))" % [vals[0], vals[0], vals[0]]

	stalk_eq = stalk_base_eq + " + " + stalk_disturbance_eq

	return [stalk_eq, stalk_length]

func generate_head():
	var boundaries = []
	var vals = []

	var flower_eq
	var flower_disturbance_eq
	var flower_length

	# CHOOSE FLOWER TYPE
	var flower_type = rng.randi_range(0, 2)
	#var flower_type = 0

	match flower_type:
		# 1 Spherical Rational Polar (cos(t), t, t)
		0:
			boundaries = [
				4,16, # a
				1,20, # n
				1,20 # d
			]
			vals = get_valuesi_inrange(boundaries)

			flower_eq = "spherical2cartesian(Vector3(%f*cos(%f/%f*t), t, t))" % [vals[0], vals[1], vals[2]]
			
			#var p = 2 if ((vals[1]*vals[2]) % 2 == 0) else 1
			#flower_length = PI * vals[2] * p
			flower_length = PI * 2 * vals[2]
		
		# 2 Spherical Rational Polar (abs(cos(t)),t, 1)
		1:
			boundaries = [
				4,16, # a
				1,20, # n
				1,20 # d
			]
			vals = get_valuesi_inrange(boundaries)

			flower_eq = "spherical2cartesian(Vector3(%f*abs(cos(%f/%f*t)), t, 1))" % [vals[0], vals[1], vals[2]]
			
			flower_length = PI * 2 * vals[2]

		# 3 Cone (a.t, t, cos(t))
		2:
			boundaries = [
				0.4,0.7, # a
				50,100 # c
			]
			vals = get_valuesf_inrange(boundaries)

			flower_eq = "spherical2cartesian(Vector3(%f*t, t, cos(t)))" % [vals[0]]
			
			#var p = 2 if ((vals[1]*vals[2]) % 2 == 0) else 1
			#flower_length = PI * vals[2] * p
			flower_length = vals[1]

	# FLOWER DISTURBANCE

	boundaries = [
		1,4
	]
	vals = get_valuesi_inrange(boundaries)

	flower_disturbance_eq = "Vector3(sin(%f*t),sin(%f*t),sin(%f*t))" % [vals[0], vals[0], vals[0]]

	#flower_eq = flower_eq + " + " + flower_disturbance_eq
		
	return [flower_eq, flower_length]

func get_valuesi_inrange(var boundaries):
	var vals = PoolRealArray()
	# Get random values (within the boundaries)
	for i in range(boundaries.size()/2):
		vals.append(rng.randi_range(boundaries[i],boundaries[i+1]))
	return vals

func get_valuesf_inrange(var boundaries):
	var vals = PoolRealArray()
	# Get random values (within the boundaries)
	for i in range(boundaries.size()/2):
		vals.append(rng.randf_range(boundaries[i],boundaries[i+1]))
	return vals