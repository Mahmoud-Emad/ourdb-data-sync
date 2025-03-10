module streamer

import freeflowuniverse.herolib.clients.mycelium
import freeflowuniverse.herolib.data.ourdb
// import encoding.base64
// import json
// import time

// Streamer represents the entire network, including master and workers
pub struct Streamer {
pub mut:
	name             string = 'streamer'
	port             int    = 8080
	master           StreamerNode
	incremental_mode bool = true // Incremental mode for database
	reset            bool = true // Reset database
}

// NewStreamerParams defines parameters for creating a new streamer
@[params]
pub struct NewStreamerParams {
pub mut:
	name             string = 'streamer'
	port             int    = 8080
	incremental_mode bool   = true // Incremental mode for database
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

@[params]
struct NewMyCeliumClientParams {
	port int    = 8080              // HTTP server port
	name string = 'streamer_client' // Mycelium client name
}

fn new_mycelium_client(params NewMyCeliumClientParams) !&mycelium.Mycelium {
	mut mycelium_client := mycelium.get()!
	mycelium_client.server_url = 'http://localhost:${params.port}'
	mycelium_client.name = params.name
	return mycelium_client
}

// ConnectStreamerParams defines parameters for connecting to an existing streamer
@[params]
pub struct ConnectStreamerParams {
pub mut:
	master_public_key string @[required] // Public key of the master node
	worker_public_key string @[required] // Public key of the worker node that the user want to join it
	master_address    string @[required] // Public key of the master node
	worker_address    string @[required] // Public key of the worker node that the user want to join it
	port              int    = 8080
	name              string = 'streamer'
}

// Connects to an existing streamer master node; intended for worker nodes
pub fn connect_streamer(params ConnectStreamerParams) !Streamer {
	mut streamer_ := new_streamer(
		port: params.port
		name: params.name
	)!

	streamer_.add_master(
		public_key: params.master_public_key
		address:    params.master_address
	)!

	if !streamer_.master.is_running() {
		return error('Master node is not running')
	}

	mut worker_node := streamer_.master.add_worker(
		public_key: params.worker_public_key
		address:    params.worker_address
	)!

	if !worker_node.is_running() {
		return error('Worker node is not running')
	}

	worker_node.connect_to_master()!
	streamer_.master.mycelium_client = new_mycelium_client(name: params.name, port: params.port)!
	worker_node.mycelium_client = new_mycelium_client(name: params.name, port: params.port)!

	return streamer_
}

// StreamerNodeParams defines parameters for creating a new master or worker node
@[params]
pub struct StreamerNodeParams {
pub mut:
	public_key       string @[required] // Node public key
	address          string @[required] // Node address
	db_dir           string = '/tmp/ourdb' // Database directory
	incremental_mode bool   = true         // Incremental mode for database
	reset            bool   = true         // Reset database
}

// Creates a new master node
fn (self Streamer) new_master_node(params StreamerNodeParams) !StreamerNode {
	mut mycelium_client := mycelium.get()!
	mycelium_client.server_url = 'http://localhost:${self.port}'
	mycelium_client.name = 'streamer_master'

	mut db := ourdb.new(
		record_nr_max:    16777216 - 1
		record_size_max:  1024
		path:             params.db_dir
		reset:            params.reset
		incremental_mode: params.incremental_mode
	)!

	return StreamerNode{
		address:           params.address
		public_key:        params.public_key
		mycelium_client:   mycelium_client
		db:                &db
		is_master:         true
		master_public_key: params.public_key
	}
}

// Adds a master node to the streamer
pub fn (mut self Streamer) add_master(params StreamerNodeParams) !StreamerNode {
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

@[params]
pub struct GetWorkerParams {
pub mut:
	public_key string @[required] // Public key of the worker node
}

// Get worker node
pub fn (self Streamer) get_worker(params GetWorkerParams) !StreamerNode {
	if !self.master.is_master {
		return self.master
	}

	// Find the worker node
	for worker in self.master.workers {
		if params.public_key == worker.public_key {
			return worker
		}
	}

	return error('Worker with public key ${params.public_key} not found')
}
