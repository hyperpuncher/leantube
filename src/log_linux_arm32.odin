package main

import "core:fmt"
import "core:os"
import "core:sys/posix"

setup_logging :: proc() {
	log := posix.open(APP_TEMP_PREFIX + ".log", {.WRONLY, .CREAT, .TRUNC}, {.IRUSR, .IWUSR})
	if log >= 0 {
		posix.dup2(log, posix.STDOUT_FILENO)
		posix.dup2(log, posix.STDERR_FILENO)
		posix.close(log)
	}
	pid := fmt.aprintf("%d\n", posix.getpid())
	defer delete(pid)
	_ = os.write_entire_file(APP_TEMP_PREFIX + ".pid", pid)
}
