# FrameForge

**A functional OCaml server that decodes and responds to Ethernet frames, working
together with a Zig client handling low-level packet I/O.**

## Overview

* `frameforge` (OCaml): decodes Ethernet frames, applies logic, crafts replies.
* `ethproxy` (Zig): handles raw network sockets, forwards frames to `frameforge` via UNIX socket.

## Current status

* `frameforge` is listening on the socket and responds by echoing.
* `ethproxy` is able to:
  * Set up the virtual pair.
  * Wait for user input.
  * Send the input to `frameforge`
  * Print the response.
* See the screenshot for a better idea of the current status.

## Debug

- Start the server
- Modified the client to connect to /tmp/frameforge-proxy.socket
- Create a proxy with socat
```
socat -v UNIX-LISTEN:/tmp/frameforge-proxy.sock,fork \
         UNIX-CONNECT:/tmp/frameforge.sock \
  | tee /tmp/frameforge.log
```
- We are able to see messages that are exchanged
- We will able to see the issue where data size is too big on the ethproxy
  side.

## TODO / Next Steps

* [x] Exchange data between `frameforge` and `ethproxy`
  - [x] Create the frameforge server:
    - Can be tested using `echo "ping" | nc -U /tmp/frameforge.sock`
  - [x] Create the ethproxy client
* [x] Ethproxy: Setup the network (veth)
* [x] Ethproxy: Read an ethernet frame from veth-peer and send it to the server
* [ ] Frameforge: Parse Ethernet Frame
  * [ ] Parse the ethertype
  * [ ] handle arping
  * [ ] ...

## Usage

- To build the project: `zig build`
- To run it: `zig build run`
- To run the OCaml server frameforge: `./frameforge/_build/default/bin/main.exe`
- To run the Zig client ethproxy: `./zig-out/bin/ethproxy`

## Screenshot

<img src="https://github.com/gthvn1/frameforge/blob/master/screenshot.png">
