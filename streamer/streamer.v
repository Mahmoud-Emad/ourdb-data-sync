module streamer

import freeflowuniverse.herolib.clients.mycelium
import freeflowuniverse.herolib.data.ourdb

// Streamer represents the entire network, including master and workers
pub struct Streamer {
pub mut:
	name             string = 'streamer'
	port             int    = 8080
	master           StreamerNode
	incremental_mode bool = true // Incremental mode
	reset            bool = true // Reset database
}

// NewStreamerParams for creating a new streamer
@[params]
pub struct NewStreamerParams {
pub mut:
	name             string = 'streamer'
	port             int    = 8080
	incremental_mode bool   = true // Incremental mode
	reset            bool   = true // Reset database
}

// Creates a new streamer instance
pub fn new_streamer(params NewStreamerParams) !Streamer {
	println('Creating a new streamer...')
	mut db := ourdb.new(
		incremental_mode: params.incremental_mode
		reset:            params.reset
	)!

	master := StreamerNode{
		db: &db
	}

	return Streamer{
		name:             params.name
		port:             params.port
		master:           master
		incremental_mode: params.incremental_mode
		reset:            params.reset
	}
}

// ConnectStreamerParams for connecting to an existing streamer
@[params]
pub struct ConnectStreamerParams {
pub mut:
	address    string @[required] // Master public key
	public_key string @[required] // Master public key
	port       int    @[required] // Port
	name       string = 'new_streamer'
}

// Connects to an existing streamer master node, workers should call this methods and will be added later
pub fn connect_streamer(params ConnectStreamerParams) !Streamer {
	println('Connecting to an existing streamer...')
	mut streamer_ := new_streamer(
		port: params.port
		name: params.name
		// incremental_mode: params.incremental_mode
		// reset:            params.reset
	)!

	// TODO: Get the running master data instead
	mut master_node := streamer_.new_master_node(
		public_key: params.public_key
		address:    params.address
	) or { return error('Failed to add master node: ${err}') }

	if !master_node.is_running() {
		return error('Master node is not running!')
	}

	streamer_.master = master_node
	return streamer_
}

// StreamerMasterParams for creating a new master node
@[params]
pub struct StreamerNodeParams {
pub mut:
	public_key       string @[required] // Node public key
	address          string @[required] // Node address
	db_dir           string = '/tmp/ourdb' // Database directory
	incremental_mode bool   = true         // Incremental mode
	reset            bool   = true         // Reset database
}

// Create a new master node
fn (self Streamer) new_master_node(params StreamerNodeParams) !StreamerNode {
	// Initialize Mycelium client (pseudo-code; adjust based on Mycelium API)
	mut mycelium_client := mycelium.get()!
	mycelium_client.server_url = 'http://localhost:${self.port}'
	mycelium_client.name = 'streamer_master'

	mut db := ourdb.new(
		record_nr_max:    16777216 - 1 // max size of records
		record_size_max:  1024
		path:             params.db_dir
		reset:            params.reset
		incremental_mode: params.incremental_mode
	)!

	return StreamerNode{
		address:         params.address
		public_key:      params.public_key
		mycelium_client: mycelium_client
		db:              &db
		is_master:       true
	}
}

// Adds a master node to the streamer
pub fn (mut self Streamer) add_master(params StreamerNodeParams) !StreamerNode {
	// Prevent multiple master nodes
	if self.master.public_key.len != 0 {
		return error('Streamer already has a master node!')
	}

	new_master := self.new_master_node(params)!

	self.master = new_master
	return self.master
}

// Gets the master node
pub fn (self Streamer) get_master() StreamerNode {
	return self.master
}

// Starts only the master node
pub fn (mut self Streamer) start_master() ! {
	println('Starting streamer master node...')
	self.master.start()!
}

pub fn (mut self Streamer) stop_master() ! {
	self.master.stop()!
}
