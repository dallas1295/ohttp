#+build darwin, freebsd

package server

import "core:sys/posix"

on_signal :: proc "c" (sig: posix.Signal) {
	shutdown = true
}

register_signal_handler :: proc() {
	act := posix.sigaction_t {
		sa_handler = on_signal,
	}
	posix.sigaction(.SIGINT, &act, nil)
}
