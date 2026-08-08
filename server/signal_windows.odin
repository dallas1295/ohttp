#+build windows

package server

import "core:sys/windows"

on_signal :: proc "c" (ctrl_type: windows.DWORD) -> windows.BOOL {
	shutdown = true
	return 1
}

register_signal_handler :: proc() {
	SetConsoleCtrlHandler(handler, 1)
}
