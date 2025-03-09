module main

import streamer

fn main() {
	println('Strating the streamer first!')
	master_key := '570c1069736786f06c4fd2a6dc6c17cd88347604593b60e34b5688c369fa1b39'
	worker_key := '46a9f9cee1ce98ef7478f3dea759589bbf6da9156533e63fed9f233640ac072c'

	mut streamer_ := streamer.connect_streamer(
		master_addr: master_key
	)!

	if streamer_.get_master().running {
		streamer_.add_worker(
			public_key: worker_key
			address:    '127.0.0.1:8081'
		)!
	}

	// workers := streamer_.get_workers()

	// println('Workers: ${workers}')

	// streamer_.start_master()
}
