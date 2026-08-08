#+build linux

package server

import "core:sys/linux"

on_signal :: proc "c" (sig: linux.Signal) {
	shutdown = true
}

register_signal_handler :: proc() {
	action := linux.Sig_Action {
		handler = on_signal,
	}
	linux.rt_sigaction(.SIGINT, &action, nil)

}
