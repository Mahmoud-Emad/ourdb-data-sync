module streamer

import freeflowuniverse.herolib.clients.mycelium

// StreamerWorkerNode represents a worker node in the streamer network
pub struct StreamerWorkerNode {
pub mut:
	public_key      string // Mycelium public key of the master
	address         string // Network address of the master (e.g., "127.0.0.1:8080")
	running         bool   // Indicates if the master is running
	log_state       string // Log state of the master node
	mycelium_client &mycelium.Mycelium = unsafe { nil } // Mycelium client
}

pub fn (mut node StreamerWorkerNode) start() {
	println('Starting worker node at ${node.address} with public key ${node.public_key}')
	node.running = true
}
