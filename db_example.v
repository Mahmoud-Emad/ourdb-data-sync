module main

import streamer
// import time

fn main() {
	println('Strating the streamer first!')
	mut streamer_ := streamer.connect_streamer(
		// address:    '4ff:3da9:f2b2:4103:fa6e:7ea:7cbe:8fef'
		master_public_key: '570c1069736786f06c4fd2a6dc6c17cd88347604593b60e34b5688c369fa1b39'
		worker_public_key: '46a9f9cee1ce98ef7478f3dea759589bbf6da9156533e63fed9f233640ac072c'
		port:              8080
	)!

	println('streamer_: ${streamer_}')

	// mut master_node := streamer_.get_master()
	// mut worker_node := master_node.add_worker(
	// 	public_key: '46a9f9cee1ce98ef7478f3dea759589bbf6da9156533e63fed9f233640ac072c'
	// 	address:    '59c:28ee:8597:6c20:3b2f:a9ee:2e18:9d4f'
	// )!

	// println('Writing to the master node')
	// mut nm := 0
	// for {
	// 	println('Set 5 records...')
	// 	time.sleep(2 * time.second)
	// 	if nm == 5 {
	// 		break
	// 	}
	// 	id := master_node.write(
	// 		// In incremental mode the first ID will be 0
	// 		value: 'value${nm + 1}'
	// 	)!
	// 	println('Set value with ID ${id}')
	// 	nm += 1
	// }

	// println('Reading from the worker node')
	// value := worker_node.read(
	// 	key: id
	// )!

	// println('Value: ${value}')
}
