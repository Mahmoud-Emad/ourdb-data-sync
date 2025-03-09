module streamer

import time
import freeflowuniverse.herolib.clients.mycelium
import freeflowuniverse.herolib.osal
import encoding.base64

// StreamerMasterNode represents the master node in the streamer network
pub struct StreamerMasterNode {
pub mut:
	public_key      string // Mycelium public key of the master
	address         string // Network address of the master (e.g., "127.0.0.1:8080")
	running         bool   // Indicates if the master is running
	log_state       string // Log state of the master node
	mycelium_client &mycelium.Mycelium = unsafe { nil } // Mycelium client
}

fn (mut node StreamerMasterNode) write_blob(blob string) ! {
	node.log_state = blob
	node.mycelium_client.send_msg(
		public_key: node.public_key
		topic:      'register_worker'
		payload:    blob
	)!
}

fn (mut node StreamerMasterNode) read_blob() string {
	state := node.log_state
	return state
}

pub fn (mut node StreamerMasterNode) is_running() bool {
	ping_result := osal.ping(address: node.address, retry: 2) or { return false }
	if ping_result == .ok {
		return true
	}
	return false
}

// Placeholder method to start a master node
fn (mut node StreamerMasterNode) start() ! {
	println('Starting master node at ${node.address} with public key ${node.public_key}')
	node.running = true

	// Start listening for registration messages in a separate thread
	// spawn node.listen_for_registrations()

	// Main loop for printing blobs
	for {
		node.handle_log_messages()!
		time.sleep(2 * time.second)
		// println('Listening for messages...')
		// logs_msg := node.mycelium_client.receive_msg(wait: false, peek: true, topic: 'logs')!
		// println('Received message: ${logs_msg.payload}')

		// blob := node.read_blob()
		// if blob.len != 0 {
		// 	println(blob)
		// }
	}
}

fn (mut node StreamerMasterNode) handle_log_messages() ! {
	message := node.mycelium_client.receive_msg(wait: false, peek: true, topic: 'logs')!
	decoded_message := base64.decode(message.payload)
	if decoded_message.len != 0 {
		println(decoded_message)
	}
}

// fn (mut node StreamerMasterNode) listen_for_registrations() ! {
// 		msg := node.mycelium_client.receive_msg() or { continue } // Receive Mycelium message
// 	for {
// 		println('Received message: ${msg.payload}')
// 		// if msg.topic == 'register_worker' {
// 		// data := json.decode(map[string]string, msg.payload) or { continue }
// 		// worker := StreamerWorkerNode{
// 		// 	public_key: data['public_key']
// 		// 	address:    data['address']
// 		// }
// 		// // Trigger on_join manually (assuming access to events; adjust as needed)
// 		// mut events := new_streamer_events()
// 		// message := events.on_join_worker(worker)
// 		// node.write_blob(message)!
// 		// }
// 	}
// }
