module streamer

import freeflowuniverse.herolib.clients.mycelium
import os
import json

// TODO: Replace with ourdb.
const internal_db_file_path = os.dir(@FILE) + '/internal.db.json'
const max_workers = 10

// Streamer represents the entire network, including master and workers
pub struct Streamer {
pub mut:
	name        string = 'streamer'
	port        int    = 8080
	master      StreamerMasterNode
	workers     []StreamerWorkerNode
	internal_db string
	events      StreamerEvents
}

// InternalDBEntry represents the JSON structure stored in internal.db
struct InternalDBEntry {
pub mut:
	master  StreamerMasterNode
	workers []StreamerWorkerNode
}

// NewStreamerParams for creating a new streamer
@[params]
pub struct NewStreamerParams {
pub mut:
	name string = 'streamer'
	port int    = 8080
}

// Creates a new streamer instance
pub fn new_streamer(params NewStreamerParams) !Streamer {
	println('Creating a new streamer...')
	if !os.exists(internal_db_file_path) {
		os.create(internal_db_file_path)!
	}

	return Streamer{
		name:        params.name
		port:        params.port
		internal_db: '{}' // Initialize with empty JSON
		events:      new_streamer_events()
	}
}

// ConnectStreamerParams for connecting to an existing streamer
@[params]
pub struct ConnectStreamerParams {
pub mut:
	master_addr string @[required] // Master public key
}

// Connects to an existing streamer by loading from internal.db
pub fn connect_streamer(params ConnectStreamerParams) !Streamer {
	println('Connecting to an existing streamer...')

	file_content := os.read_file(internal_db_file_path) or {
		return error('Internal DB file does not exist: ${err}')
	}

	if file_content.len == 0 {
		return error('Internal DB file is empty!')
	}

	// Decode the internal DB content into a map of master public keys to InternalDBEntry
	mut content := json.decode(map[string]InternalDBEntry, file_content) or {
		return error('Failed to decode internal DB: ${err}')
	}

	if content.len == 0 {
		return error('Internal DB file is empty!')
	}

	// Find the master node matching the provided master_addr
	if entry := content[params.master_addr] {
		mut s := Streamer{
			name:        'streamer'
			port:        8080
			master:      entry.master  // Directly load the saved master
			workers:     entry.workers // Directly load the saved workers
			internal_db: file_content
			events:      new_streamer_events()
		}

		if s.workers.len > max_workers {
			return error('Too many workers!')
		}

		return s
	}

	return error('Master node with public key ${params.master_addr} not found!')
}

// StreamerMasterParams for creating a new master node
@[params]
pub struct StreamerNodeParams {
pub mut:
	public_key string @[required]
	address    string @[required]
}

// Create a new master node
fn (self Streamer) new_master_node(params StreamerNodeParams) !StreamerMasterNode {
	// Initialize Mycelium client (pseudo-code; adjust based on Mycelium API)
	mut mycelium_client := mycelium.get()!
	mycelium_client.server_url = 'http://localhost:${self.port}'
	mycelium_client.name = 'streamer_master'

	return StreamerMasterNode{
		address:         params.address
		public_key:      params.public_key
		mycelium_client: mycelium_client
	}
}

// Create a new worker node
fn (self Streamer) new_worker_node(params StreamerNodeParams) !StreamerWorkerNode {
	// Initialize Mycelium client (pseudo-code; adjust based on Mycelium API)
	mut mycelium_client := mycelium.get()!
	mycelium_client.server_url = 'http://localhost:${self.port}'
	mycelium_client.name = 'streamer_worker'

	return StreamerWorkerNode{
		address:         params.address
		public_key:      params.public_key
		mycelium_client: mycelium_client
	}
}

// Adds a master node to the streamer
pub fn (mut self Streamer) add_master(params StreamerNodeParams) !StreamerMasterNode {
	// Ensure internal DB file exists, or initialize it with an empty JSON object
	if !os.exists(internal_db_file_path) {
		return error('Internal DB file does not exist!')
	}

	// Prevent multiple master nodes
	if self.master.public_key.len != 0 {
		return error('Streamer already has a master node!')
	}

	// Read and decode the DB content safely
	mut content := os.read_file(internal_db_file_path) or { '{}' } // Default to empty JSON
	mut running_masters := map[string]InternalDBEntry{}
	if content.len != 0 {
		running_masters = json.decode(map[string]InternalDBEntry, content) or {
			eprintln('Failed to decode internal DB: ${err}')
			return error('Corrupted internal DB file: ${err}')
		}
	}

	// Check if the master already exists
	if params.public_key in running_masters {
		return error('Master with public key ${params.public_key} already exists!')
	}

	// Create the new master node
	new_master := self.new_master_node(
		public_key: params.public_key
		address:    params.address
	)!

	// Add the new master to the running_masters map
	running_masters[params.public_key] = InternalDBEntry{
		master:  new_master
		workers: [] // Initially no workers
	}

	// Save updated DB back to the file
	string_content := json.encode(running_masters) + '\n'
	os.write_file(internal_db_file_path, string_content) or {
		return error('Failed to write to internal DB file: ${err}')
	}

	self.master = new_master
	self.internal_db = string_content
	return self.master
}

// Adds a worker node to the streamer
pub fn (mut self Streamer) add_worker(params StreamerNodeParams) !StreamerWorkerNode {
	// Ensure worker count is within limits
	if self.workers.len >= max_workers {
		return error('Too many workers!')
	}

	// Ensure the internal DB file exists, or initialize it with an empty JSON structure
	if !os.exists(internal_db_file_path) {
		os.write_file(internal_db_file_path, '{}') or {
			return error('Failed to initialize internal DB file: ${err}')
		}
	}

	// Check if worker already exists in self.workers
	if self.workers.any(it.public_key == params.public_key) {
		return error('Worker with public key ${params.public_key} already exists!')
	}

	// Decode internal DB safely
	mut db_content := json.decode(map[string]InternalDBEntry, self.internal_db) or {
		eprintln('Failed to decode internal DB: ${err}')
		return error('Corrupted internal DB file: ${err}')
	}

	// Ensure master public key exists
	if self.master.public_key.len == 0 {
		return error('No master node is set for this streamer!')
	}

	if self.master.public_key !in db_content {
		return error('Master with public key ${self.master.public_key} does not exist!')
	}

	// Check if worker already exists in master's worker list
	if db_content[self.master.public_key] or { InternalDBEntry{} }.workers.any(it.public_key == params.public_key) {
		return error('Worker with public key ${params.public_key} already exists under this master!')
	}

	// Create the new worker node
	new_worker := self.new_worker_node(
		public_key: params.public_key
		address:    params.address
	)!

	// Add new worker to master's worker list in the DB
	mut entry := db_content[self.master.public_key] or { InternalDBEntry{} }
	entry.workers << new_worker
	db_content[self.master.public_key] = entry

	// Save updated DB back to the file
	string_content := json.encode(db_content) + '\n'
	os.write_file(internal_db_file_path, string_content) or {
		return error('Failed to write to internal DB file: ${err}')
	}

	// Add the worker to the streamer's workers list
	self.workers << new_worker
	self.internal_db = string_content

	if self.master.running {
		message := self.events.on_join_worker(new_worker)
		self.events.new_log_event(
			mycelium_client: new_worker.mycelium_client
			sender:          new_worker.public_key
			message:         message
			receivers:       [
				self.master.public_key,
			]
		)!
	}

	return new_worker
}

// Gets the list of workers
pub fn (self Streamer) get_workers() []StreamerWorkerNode {
	return self.workers
}

// Gets the master node
pub fn (self Streamer) get_master() StreamerMasterNode {
	return self.master
}

// Starts only the master node
pub fn (mut self Streamer) start_master() ! {
	println('Starting streamer master node...')
	self.update_master_running(true) or {
		eprintln('Failed to update master running status: ${err}')
		return
	}
	self.master.start()!
}

pub fn (mut self Streamer) stop_master() {
	self.update_master_running(false) or {
		eprintln('Failed to update master running status: ${err}')
		return
	}
	// Additional stop logic here
}

// Updates the running status of the master node in the internal database
pub fn (mut self Streamer) update_master_running(running bool) ! {
	// Ensure a master node is set
	if self.master.public_key.len == 0 {
		return error('No master node is set for this streamer!')
	}

	// Update the in-memory master's running status
	self.master.running = running

	// Read the current internal DB content
	file_content := os.read_file(internal_db_file_path) or {
		return error('Failed to read internal DB file: ${err}')
	}

	// Decode the internal DB content into a map
	mut db_content := json.decode(map[string]InternalDBEntry, file_content) or {
		return error('Failed to decode internal DB: ${err}')
	}

	// Find and update the entry for the current master
	if mut entry := db_content[self.master.public_key] {
		// Update the master's running status in the entry
		entry.master.running = running
		db_content[self.master.public_key] = entry

		// Encode the updated map back to JSON
		updated_content := json.encode(db_content)

		// Write the updated content back to the file
		os.write_file(internal_db_file_path, updated_content + '\n') or {
			return error('Failed to write to internal DB file: ${err}')
		}

		// Update the internal_db field in the streamer
		self.internal_db = updated_content
	} else {
		return error('Master node with public key ${self.master.public_key} not found in internal DB!')
	}
}
