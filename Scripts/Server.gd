extends Node

var network = NetworkedMultiplayerENet.new()
var port = 1909
var max_players = 100

func _ready():
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
