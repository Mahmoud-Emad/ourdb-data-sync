module main

import streamer
// import time

fn main() {
	master_public_key := '570c1069736786f06c4fd2a6dc6c17cd88347604593b60e34b5688c369fa1b39'
	worker_public_key := '46a9f9cee1ce98ef7478f3dea759589bbf6da9156533e63fed9f233640ac072c'

	// Create a new streamer
	mut streamer_ := streamer.connect_streamer(
		name:              'streamer'
		port:              8080
		master_public_key: master_public_key
		// worker_public_key: worker_public_key
		// master_address:    '4ff:3da9:f2b2:4103:fa6e:7ea:7cbe:8fef'
		// worker_address:    '59c:28ee:8597:6c20:3b2f:a9ee:2e18:9d4f'
	)!

	println('streamer_: ${streamer_}')

	// mut worker_node := streamer_.get_worker(public_key: worker_public_key)!
	// mut master_node := streamer_.get_master()

	// id1 := master_node.write(
	// 	value: 'value1'
	// )!

	// id2 := master_node.write(
	// 	value: 'value2'
	// )!

	// println('Set value with ID ${id1}')
	// println('Set value with ID ${id2}')

	// println('Reading first insertion from the worker node')
	// value1 := worker_node.read(
	// 	key: id1
	// )!
	// println('Value: ${value1}')

	// println('Reading second insertion from the worker node')
	// value2 := worker_node.read(
	// 	key: id2
	// )!
	// println('Value: ${value2}')
}
