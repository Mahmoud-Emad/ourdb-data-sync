module streamer

import time
import freeflowuniverse.herolib.clients.mycelium
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
	workers         []StreamerNode
	port            int = 8080
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

	new_node := StreamerNode{
		address:         params.address
		public_key:      params.public_key
		mycelium_client: mycelium_client
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
fn (mut node StreamerNode) start() ! {
	println('Starting master node at ${node.address} with public key ${node.public_key}')

	// Main loop for printing blobs
	for {
		time.sleep(2 * time.second)
		node.handle_log_messages() or {}
		node.handle_connect_messages() or {}
	}
}

fn (mut node StreamerNode) handle_log_messages() ! {
	message := node.mycelium_client.receive_msg(wait: false, peek: true, topic: 'logs')!
	decoded_message := base64.decode(message.payload)
	if decoded_message.len != 0 {
		println(decoded_message)
	}
}

fn (mut node StreamerNode) handle_connect_messages() ! {
	message := node.mycelium_client.receive_msg(wait: false, peek: true, topic: 'connect')!
	// node.
	decoded_message := base64.decode(message.payload)
	println('decoded_message: ${decoded_message}')
	if decoded_message.len != 0 {
		worker := json.decode(StreamerNode, decoded_message.bytestr()) or {
			return error('Failed to decode worker node: ${err}')
		}
		println('worker: ${worker}')
		node.workers << worker
		println('Added worker node: ${worker.address}')
	}
}

// Gets the list of workers
pub fn (mut node StreamerNode) get_workers() []StreamerNode {
	return node.workers
}
