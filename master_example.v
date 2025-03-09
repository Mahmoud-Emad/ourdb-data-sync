module main

import streamer

fn main() {
	println('Strating the streamer first!')
	master_key := '570c1069736786f06c4fd2a6dc6c17cd88347604593b60e34b5688c369fa1b39'
	worker_key := '46a9f9cee1ce98ef7478f3dea759589bbf6da9156533e63fed9f233640ac072c'

	// Create a new streamer
	mut streamer_ := streamer.new_streamer(
		name: 'streamer'
		port: 8080
	)!

	streamer_.add_master(
		public_key: master_key
		address:    '127.0.0.1:8080'
	)!

	// streamer_.add_worker(
	// 	public_key: worker_key
	// 	address:    '127.0.0.1:8081'
	// )!

	streamer_.start_master()!
}
