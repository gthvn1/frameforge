let () =
  let open Frameforge in
  Server.run "/tmp/frameforge.sock" Ethernet_handler.handle
