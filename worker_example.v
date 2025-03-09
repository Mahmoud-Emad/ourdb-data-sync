module main

import streamer

fn main() {
	println('Strating the streamer first!')
	mut streamer_ := streamer.connect_streamer(
		address:    '4ff:3da9:f2b2:4103:fa6e:7ea:7cbe:8fef'
		public_key: '570c1069736786f06c4fd2a6dc6c17cd88347604593b60e34b5688c369fa1b39'
		port:       8080
	)!

	mut master_node := streamer_.get_master()
	mut worker_node := master_node.add_worker(
		public_key: '46a9f9cee1ce98ef7478f3dea759589bbf6da9156533e63fed9f233640ac072c'
		address:    '59c:28ee:8597:6c20:3b2f:a9ee:2e18:9d4f'
	)!

	worker_node.start()!
}
