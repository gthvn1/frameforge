# FrameForge

**A functional OCaml server that decodes and responds to Ethernet frames, working
together with a Go client handling low-level packet I/O.**

## Overview

* `frameforge` (OCaml): decodes Ethernet frames, applies logic, crafts replies.
* `ethproxy` (Go): handles raw network sockets, forwards frames to `frameforge` via UNIX socket.

## TODO / Next Steps

* [x] Exchange data between `frameforge` and `ethproxy`
  - [x] create the frameforge server:
    - can be tested using `echo "ping" | nc -U /tmp/frameforge.socket`
  - [x] create the ethproxy client
* [ ] ...

## Usage

- To build it: `just build`
- To run the project: `just run`
- To run the OCaml server frameforge: `just run_frameforge`
- To run the Go client ethproxy: `just run_ethproxy`
- All recipes: `just --list`
