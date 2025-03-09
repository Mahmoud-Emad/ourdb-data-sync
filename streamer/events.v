module streamer

import freeflowuniverse.herolib.clients.mycelium
import time

struct StreamerEvents {
}

pub fn new_streamer_events() StreamerEvents {
	return StreamerEvents{}
}

struct NewEventParams {
mut:
	sender          string             // Mycelium public key
	message         string             // Event message
	receivers       []string           // Mycelium public keys
	mycelium_client &mycelium.Mycelium // Mycelium client
}

fn (self StreamerEvents) new_log_event(params_ NewEventParams) ! {
	mut params := params_
	topic := 'logs'
	now := time.now()
	payload := '${now} | ${params.message}'
	params.mycelium_client.send_msg(
		public_key: params.sender
		topic:      topic
		payload:    payload
	)!

	for receiver in params.receivers {
		params.mycelium_client.send_msg(
			public_key: receiver
			topic:      topic
			payload:    payload
		)!
	}
}

fn (self StreamerEvents) on_join_worker(worker StreamerWorkerNode) string {
	return 'Worker ${worker.public_key} joined the network'
}
