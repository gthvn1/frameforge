package main

import (
	"fmt"
	"net"
)

func main() {
	sockPath := "/tmp/frameforge.socket"

	conn, err := net.Dial("unix", sockPath)
	if err != nil {
		fmt.Printf("failed to connect to %s", sockPath)
		return
	}
	defer conn.Close()

	if _, err := conn.Write([]byte("ping")); err != nil {
		fmt.Printf("failed to write ping")
		return
	}

	buf := make([]byte, 64)

	if n, err := conn.Read(buf); err != nil {
		fmt.Printf("failed to receive data")
	} else {
		fmt.Printf("received: %s", buf[0:n])
	}

}
