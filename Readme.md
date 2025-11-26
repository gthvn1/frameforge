# FrameForge

**A functional OCaml server that decodes and responds to Ethernet frames, working
together with a Go client handling low-level packet I/O.**

## Overview

* `frameforge` (OCaml): decodes Ethernet frames, applies logic, crafts replies.
* `ethproxy` (Go): handles raw network sockets, forwards frames to `frameforge` via UNIX socket.

## TODO / Next Steps

* [ ] Exchange data between `frameforge` and `ethproxy` 

## Usage

1. Start the OCaml server:

```bash
just run_frameforge
```

2. Start the Go low-level handler:

```bash
just run_ethproxy
```

3. `ethproxy` forwards raw Ethernet frames to `frameforge`, which decodes and optionally replies.
