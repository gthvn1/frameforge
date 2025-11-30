# FrameForge

**A functional OCaml server that decodes and responds to Ethernet frames, working
together with a Zig client handling low-level packet I/O.**

## Overview

* `frameforge` (OCaml): decodes Ethernet frames, applies logic, crafts replies.
* `ethproxy` (Zig): handles raw network sockets, forwards frames to `frameforge` via UNIX socket.

## TODO / Next Steps

* [x] Exchange data between `frameforge` and `ethproxy`
  - [x] create the frameforge server:
    - can be tested using `echo "ping" | nc -U /tmp/frameforge.socket`
  - [x] create the ethproxy client
* [ ] Ethproxy: Setup the network (veth)
* [ ] Ethproxy: Read an ethernet frame from veth-peer and send it to server
* [ ] Frameforge: Parse Ethernet Frame
* [ ] ...

## Usage

- To build the project: `zig build`
- To run it: `zig build run`
- To run the OCaml server frameforge: `./frameforge/_build/default/bin/main.exe`
- To run the Zig client ethproxy: `./zig-out/bin/ethproxy`
