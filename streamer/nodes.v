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
fn (node &StreamerNode) is_running() bool {
	ping_result := osal.ping(address: node.address, retry: 2) or { return false }
	return ping_result == .ok
}

// connect_to_master connects the worker node to its master
fn (mut worker StreamerNode) connect_to_master() ! {
	if worker.is_master {
		return error('Master nodes cannot connect to other master nodes')
	}

	worker_json := json.encode(worker)
	worker_base64 := base64.encode(worker_json.bytes())

	log_event(
		event_type: 'connection'
		message:    'Connecting worker ${worker.public_key} to master ${worker.master_public_key}'
	)

	worker.mycelium_client.send_msg(
		topic:      'connect'
		payload:    worker_base64
		public_key: worker.master_public_key
	) or { return error('Failed to send connect message: ${err}') }
}

// add_worker creates and registers a new worker node under the master
pub fn (mut node StreamerNode) add_worker(params StreamerNodeParams) !StreamerNode {
	if node.workers.len >= max_workers {
		return error('Maximum worker limit reached')
	}

	mut client := new_mycelium_client(name: 'streamer_worker_node', port: node.port)!
	mut db := ourdb.new(
		record_nr_max:    16777216 - 1
		record_size_max:  1024
		path:             params.db_dir
		reset:            params.reset
		incremental_mode: params.incremental_mode
	)!

	new_worker := StreamerNode{
		address:           params.address
		public_key:        params.public_key
		mycelium_client:   client
		is_master:         false
		db:                &db
		master_public_key: node.public_key
		last_synced_index: 0
	}

	node.workers << new_worker
	return new_worker
}

// start_and_listen runs the node's main event loop
pub fn (mut node StreamerNode) start_and_listen() ! {
	log_event(
		event_type: 'logs'
		message:    'Starting node at ${node.address} with public key ${node.public_key}'
	)
	for {
		time.sleep(2 * time.second)
		node.handle_log_messages() or {}
		node.handle_connect_messages() or {}
		node.ping_nodes() or {}
	}
}

// WriteParams defines parameters for writing to the database
@[params]
pub struct WriteParams {
pub mut:
	key   u32 // Key to write (optional in non-incremental mode)
	value string @[required] // Value to write
}

// write adds data to the database and propagates it to all nodes
pub fn (mut node StreamerNode) write(params WriteParams) !u32 {
	if node.db.incremental_mode && params.key != 0 {
		return error('Incremental mode enabled; key must be omitted')
	}
	if !node.is_master {
		return error('Only master nodes can initiate database writes')
	}

	// data := params.value.bytes()
	// encoded_data := base64.encode(data)
	// mut targets := node.workers.map(it.public_key)
	// targets << node.public_key

	// for target_key in targets {
	// 	node.mycelium_client.send_msg(
	// 		topic:      'db_write'
	// 		payload:    encoded_data
	// 		public_key: target_key
	// 	)!
	// }

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
@[params]
struct LogEventParams {
	message    string @[required] // Event message
	event_type string @[required] // Event type (e.g., "info", "warning", "error")
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

// handle_connect_messages processes connect messages to add workers
fn (mut node StreamerNode) handle_connect_messages() ! {
	message := node.mycelium_client.receive_msg(wait: false, peek: true, topic: 'connect')!
	if message.payload.len > 0 {
		worker_json := base64.decode(message.payload).bytestr()
		worker := json.decode(StreamerNode, worker_json) or {
			return error('Failed to decode worker node: ${err}')
		}
		if !node.workers.any(it.public_key == worker.public_key) {
			node.workers << worker
			log_event(
				event_type: 'connection'
				message:    'Master ${node.public_key} connected worker ${worker.public_key}'
			)
		}
	}
}

// ping_nodes pings all workers or the master, removing unresponsive workers
pub fn (mut node StreamerNode) ping_nodes() ! {
	if node.is_master {
		mut i := 0
		for i < node.workers.len {
			worker := &node.workers[i]
			if !worker.is_running() {
				log_event(event_type: 'logs', message: 'Worker ${worker.address} is not running')
				log_event(event_type: 'logs', message: 'Removing worker ${worker.public_key}')
				node.workers.delete(i)
			} else {
				node.mycelium_client.send_msg(
					topic:      'logs'
					payload:    'Master ${node.public_key} is pinging worker ${worker.public_key}'
					public_key: worker.public_key
				)!
				i++
			}
		}
	} else {
		if !node.is_running() {
			return error('Worker node is not running')
		}
		if node.master_public_key.len == 0 {
			return error('Master public key is not set')
		}
		node.mycelium_client.send_msg(
			topic:      'logs'
			payload:    'Worker ${node.public_key} is pinging master ${node.master_public_key}'
			public_key: node.master_public_key
		)!
	}
}
