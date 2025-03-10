module main

import streamer

fn main() {
	println('Strating the streamer first!')
	master_public_key := '570c1069736786f06c4fd2a6dc6c17cd88347604593b60e34b5688c369fa1b39'
	worker_public_key := '46a9f9cee1ce98ef7478f3dea759589bbf6da9156533e63fed9f233640ac072c'

	// Create a new streamer
	mut streamer_ := streamer.connect_streamer(
		name:              'streamer'
		port:              8080
		master_public_key: master_public_key
		worker_public_key: worker_public_key
		master_address:    '4ff:3da9:f2b2:4103:fa6e:7ea:7cbe:8fef'
		worker_address:    '59c:28ee:8597:6c20:3b2f:a9ee:2e18:9d4f'
	)!

	mut worker_node := streamer_.get_worker(public_key: worker_public_key)!

	worker_node.start_and_listen()!
}
