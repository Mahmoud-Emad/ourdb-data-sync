module streamer

import time
import freeflowuniverse.herolib.clients.mycelium
import freeflowuniverse.herolib.data.ourdb
import freeflowuniverse.herolib.osal
import encoding.base64
import json

// Maximum number of workers allowed
const max_workers = 10

// StreamerNode represents either a master or worker node in the streamer network
pub struct StreamerNode {
pub mut:
	name              string = 'streamer_node' // Name of the node
	public_key        string // Mycelium public key of the node
	address           string // Network address (e.g., "127.0.0.1:8080")
	mycelium_client   &mycelium.Mycelium = unsafe { nil } // Mycelium client instance
	workers           []StreamerNode // List of connected workers (for master nodes)
	port              int = 8080 // HTTP server port
	is_master         bool // Flag indicating if this is a master node
	db                &ourdb.OurDB @[skip; str: skip] // Embedded key-value database
	master_public_key string // Public key of the master node (for workers)
	last_synced_index u32    // Last synchronized index for workers
}

// is_running checks if the node is operational by pinging its address
fn (mut node StreamerNode) is_running() bool {
	ping_result := osal.ping(address: node.address, retry: 2) or { return false }
	return ping_result == .ok
}

fn (mut worker StreamerNode) connect_to_master() ! {
	if worker.is_master {
		return error('Master nodes cannot connect to other master nodes')
	}

	// Q: Do we need to push the whole master node with its workers?
	worker_json := json.encode(worker)
	worker_base64 := base64.encode(worker_json.bytes())

	log_event(
		event_type: 'connection'
		message:    'Trying to connect worker node: ${worker.public_key} to master node: ${worker.master_public_key}'
	)

	// Send connect message to master
	worker.mycelium_client.send_msg(
		topic:      'connect'
		payload:    worker_base64
		public_key: worker.master_public_key
	) or { return error('Failed to send connect message: ${err}') }
}

// add_worker creates and registers a new worker node under the master
pub fn (mut node StreamerNode) add_worker(params StreamerNodeParams) !StreamerNode {
	if node.workers.len >= max_workers {
		return error('Too many workers!')
	}

	mut mycelium_client := new_mycelium_client(
		name: 'streamer_worker_node'
		port: node.port
	)!

	mut db := ourdb.new(
		record_nr_max:    16777216 - 1
		record_size_max:  1024
		path:             params.db_dir
		reset:            params.reset
		incremental_mode: params.incremental_mode
	)!

	new_worker_node := StreamerNode{
		address:           params.address
		public_key:        params.public_key
		mycelium_client:   mycelium_client
		is_master:         false
		db:                &db
		master_public_key: node.public_key
		last_synced_index: 0
	}

	node.workers << new_worker_node
	return new_worker_node
}

// start runs the node's main loop
pub fn (mut node StreamerNode) start_and_listen() ! {
	log_event(
		event_type: 'logs'
		message:    'Starting node at ${node.address} with public key ${node.public_key}'
	)
	for {
		// if node.is_master {
		// 	last_synced_index := node.db.get_last_index()!
		// 	println('last_synced_index: ${last_synced_index}')

		// 	// node.set_master_state() or {}
		// 	node.master_sync() or {} // Master syncs with workers
		// } else {
		// 	node.handle_sync_master() or {}
		// }

		time.sleep(2 * time.second)
		node.handle_log_messages() or {}
		node.handle_connect_messages() or {}
		node.ping_nodes() or {}
		node.handle_db_write() or {}
	}
}

fn (mut node StreamerNode) handle_db_write() ! {
	message := node.mycelium_client.receive_msg(wait: false, peek: true, topic: 'db_write')!
	if message.payload.len > 0 {
		encoded_index := base64.decode(message.payload)
		println('Write data ${encoded_index.bytestr()}')
		node.db.set(data: encoded_index)!
	}
}

// WriteParams defines parameters for writing to the database
@[params]
pub struct WriteParams {
pub mut:
	key   u32 // Key to write (optional in non-incremental mode)
	value string @[required] // Value to write
}

// write adds data to the database and triggers sync (master only)
pub fn (mut node StreamerNode) write(params WriteParams) !u32 {
	if node.db.incremental_mode && params.key != 0 {
		return error('Incremental mode is enabled, remove the key parameter')
	}

	if !node.is_master {
		return error('Only master nodes can write to the database')
	}

	mut keys := []string{}
	keys << node.public_key

	for worker in node.workers {
		keys << worker.public_key
	}

	for key in keys {
		node.mycelium_client.send_msg(
			topic:      'db_write'
			payload:    base64.encode(params.value.bytes())
			public_key: key
		)!
	}

	return 0
}

// ReadParams defines parameters for reading from the database
@[params]
pub struct ReadParams {
pub mut:
	key u32 @[required] // Key to read
}

// read retrieves data from the database (worker only)
pub fn (mut node StreamerNode) read(params ReadParams) !string {
	if node.is_master {
		return error('Only worker nodes can read from the database')
	}
	value := node.db.get(params.key) or { return error('Failed to read from database: ${err}') }
	return value.bytestr()
}

// LogEventParams defines parameters for logging events
struct LogEventParams {
pub mut:
	message    string @[required] // Event message
	event_type string @[required] // Event type eg. "info", "warning", "error"
}

// log_event logs an event with a timestamp
pub fn log_event(params LogEventParams) {
	now := time.now().format()
	println('${now}| ${params.event_type}: ${params.message}')
}

// handle_log_messages processes incoming log messages
fn (mut node StreamerNode) handle_log_messages() ! {
	message := node.mycelium_client.receive_msg(wait: false, peek: true, topic: 'logs')!
	if message.payload.len > 0 {
		msg := base64.decode(message.payload).bytestr()
		log_event(event_type: 'logs', message: msg)
	}
}

// // handle_log_messages processes incoming log messages
// fn (mut node StreamerNode) handle_sync_master() ! {
// 	message := node.mycelium_client.receive_msg(wait: false, peek: true, topic: 'master_sync')!
// 	if message.payload.len > 0 {
// 		mut master_json := base64.decode(message.payload).bytestr()
// 		if master_json.len != 0 {
// 			master_json = base64.decode(master_json).bytestr()
// 		}

// 		master := json.decode(StreamerNode, master_json) or {
// 			return error('Failed to decode worker node: ${err}')
// 		}

// 		// Sync specific fields instead of overwriting node
// 		if master.public_key == node.master_public_key {
// 			// node.db = master.db // We need to fix the invalid memory access bug here.
// 			log_event(
// 				event_type: 'logs'
// 				message:    'Synced state from master node: ${master.public_key}'
// 			)
// 		}
// 	}
// }

// handle_connect_messages processes connect messages to add workers
fn (mut node StreamerNode) handle_connect_messages() ! {
	message := node.mycelium_client.receive_msg(wait: false, peek: true, topic: 'connect')!
	if message.payload.len > 0 {
		mut worker_json := base64.decode(message.payload).bytestr()
		if worker_json.len != 0 {
			worker_json = base64.decode(worker_json).bytestr()
		}

		worker := json.decode(StreamerNode, worker_json) or {
			return error('Failed to decode worker node: ${err}')
		}

		if !node.workers.any(it.public_key == worker.public_key) {
			node.workers << worker
			log_event(
				event_type: 'connection'
				message:    'Master ${node.public_key} connected worker node: ${worker.public_key}'
			)
		}
	}
}

// ping_nodes pings all workers and removes unresponsive ones (master only)
pub fn (mut node StreamerNode) ping_nodes() ! {
	if node.is_master {
		for mut worker in node.workers {
			if !worker.is_running() {
				log_event(event_type: 'logs', message: 'Worker ${worker.address} is not running')
				log_event(event_type: 'logs', message: 'Removing worker node: ${worker.public_key}')
				idx := node.workers.index(worker)
				node.workers.delete(idx)
			} else {
				node.mycelium_client.send_msg(
					topic:      'logs'
					payload:    'Master ${node.public_key} is pinging worker node: ${worker.public_key}'
					public_key: worker.public_key
				)!
			}
		}
	} else {
		if !node.is_running() {
			return error('Node is not running')
		}
		if node.master_public_key.len == 0 {
			return error('Master public key is not set')
		}
		node.mycelium_client.send_msg(
			topic:      'logs'
			payload:    'Worker ${node.public_key} is pinging master node: ${node.master_public_key}'
			public_key: node.master_public_key
		)!
	}
}

// // ping_nodes pings all workers and removes unresponsive ones (master only)
// pub fn (mut node StreamerNode) master_sync() ! {
// 	if node.is_master {
// 		for mut worker in node.workers {
// 			if worker.is_running() {
// 				log_event(
// 					event_type: 'logs'
// 					message:    'Sending master state to worker node: ${worker.public_key}'
// 				)
// 				master_json := json.encode(node)
// 				master_base64 := base64.encode(master_json.bytes())

// 				node.mycelium_client.send_msg(
// 					topic:      'master_sync'
// 					payload:    master_base64
// 					public_key: worker.public_key
// 				)!
// 				log_event(
// 					event_type: 'logs'
// 					message:    'Sent master state to worker node: ${worker.public_key}'
// 				)
// 			}
// 		}
// 	}
// }
