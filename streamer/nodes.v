module streamer

import time
import freeflowuniverse.herolib.clients.mycelium
import freeflowuniverse.herolib.data.ourdb
import freeflowuniverse.herolib.osal
import encoding.base64
import json

// TODO: Replace with ourdb.
const max_workers = 10

// StreamerMasterNode represents the master node in the streamer network
pub struct StreamerNode {
pub mut:
	public_key      string // Mycelium public key of the master
	address         string // Network address of the master (e.g., "127.0.0.1:8080")
	mycelium_client &mycelium.Mycelium = unsafe { nil } // Mycelium client
	workers         []StreamerNode // List of connected workers
	port            int = 8080 // HTTP server port
	is_master       bool // Flag to indicate if the node is a master
	db              &ourdb.OurDB @[skip; str: skip] // Embedded key-value database
}

// Check if a master node is running
fn (mut node StreamerNode) is_running() bool {
	ping_result := osal.ping(address: node.address, retry: 2) or { return false }
	if ping_result == .ok {
		return true
	}
	return false
}

// Adds a worker node to the streamer
pub fn (mut node StreamerNode) add_worker(params StreamerNodeParams) !StreamerNode {
	// Ensure worker count is within limits
	if node.workers.len >= max_workers {
		return error('Too many workers!')
	}

	mut mycelium_client := mycelium.get()!
	mycelium_client.server_url = 'http://localhost:${node.port}'
	mycelium_client.name = 'streamer_worker'

	mut db := ourdb.new(
		record_nr_max:    16777216 - 1 // max size of records
		record_size_max:  1024
		path:             params.db_dir
		reset:            params.reset
		incremental_mode: params.incremental_mode
	)!

	new_node := StreamerNode{
		address:         params.address
		public_key:      params.public_key
		mycelium_client: mycelium_client
		is_master:       false
		db:              &db
	}

	decoded_node_to_json := json.encode(new_node)
	decoded_node_to_base64 := base64.encode(decoded_node_to_json.bytes())

	node.mycelium_client.send_msg(
		topic:      'connect'
		payload:    decoded_node_to_base64
		public_key: node.public_key
	) or { return error('Failed to send connect message: ${err}') }

	node.workers << new_node
	return new_node
}

// Method to stop a master node
fn (mut node StreamerNode) stop() ! {}

// Method to start a master node
pub fn (mut node StreamerNode) start() ! {
	println('Starting master node at ${node.address} with public key ${node.public_key}')

	// Main loop for printing blobs
	for {
		println('Connected workers: ${node.workers.len}')
		time.sleep(2 * time.second)
		node.handle_log_messages() or {}
		node.handle_connect_messages() or {}
		node.ping_workers() or {}
		node.sync_db() or {}
	}
}

fn (mut node StreamerNode) handle_log_messages() ! {
	message := node.mycelium_client.receive_msg(wait: false, peek: true, topic: 'logs')!
	decoded_message := base64.decode(message.payload).bytestr()
	if decoded_message.len != 0 {
		println(decoded_message)
	}
}

fn (mut node StreamerNode) sync_db() ! {
	last_index := node.db.get_last_index()!
	println('last_index: ${last_index}')
	// data := node.db.push_updates(last_index)!
	// encoded_data := base64.encode(data)

	// for mut worker in node.workers {
	// 	node.mycelium_client.send_msg(
	// 		topic:      'db_sync'
	// 		payload:    encoded_data
	// 		public_key: worker.public_key
	// 	)!
	// }

	// message := node.mycelium_client.receive_msg(wait: false, peek: true, topic: 'db_sync')!
	// decoded_message := base64.decode(message.payload).bytestr()
	// if decoded_message.len != 0 {
	// 	println('Received sync message: ${decoded_message}')
	// }
}

fn (mut node StreamerNode) handle_connect_messages() ! {
	message := node.mycelium_client.receive_msg(wait: false, peek: true, topic: 'connect')!
	decoded_message := base64.decode(message.payload)
	if decoded_message.len > 0 {
		to_json_str := base64.decode(decoded_message.bytestr()).bytestr()
		worker := json.decode(StreamerNode, to_json_str) or {
			return error('Failed to decode worker node: ${err}')
		}
		node.workers << worker
		println('Worker ${worker.address} connected')
	}
}

// Gets the list of workers
pub fn (mut node StreamerNode) get_workers() []StreamerNode {
	return node.workers
}

// Pings the workers, if node is not responding, remove it
pub fn (mut node StreamerNode) ping_workers() ! {
	for mut worker in node.workers {
		if !worker.is_running() {
			println('Worker ${worker.address} is not running, removing...')
			idx := node.workers.index(worker)
			node.workers.delete(idx)
		} else {
			if !node.workers.contains(worker) {
				println('Adding worker ${worker.address}')
				node.workers << worker
			}

			// Send ping message to worker
			node.mycelium_client.send_msg(
				topic:      'logs'
				payload:    'Master node is alive'
				public_key: worker.public_key
			)!
		}
	}
}

@[params]
pub struct WriteParams {
pub mut:
	key   u32 // Key to write
	value string @[required] // Value to write
}

// Method to write to the database
pub fn (mut node StreamerNode) write(params WriteParams) !u32 {
	if node.db.incremental_mode && params.key != 0 {
		return error('Incremental mode is enabled, remove the key parameter')
	}

	if !node.is_master {
		return error('Only master nodes can write to the database')
	}

	data_bytes := params.value.bytes()
	id := node.db.set(data: data_bytes) or { return error('Failed to write to database: ${err}') }
	return id
}

@[params]
pub struct ReadParams {
pub mut:
	key u32 @[required] // Key to write
}

// Method to read from the database
pub fn (mut node StreamerNode) read(params ReadParams) !string {
	if node.is_master {
		return error('Only worker nodes can read from the database')
	}

	value := node.db.get(params.key) or { return error('Failed to write to database: ${err}') }
	return value.bytestr()
}
