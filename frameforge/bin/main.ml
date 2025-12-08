let () =
  let open Frameforge in
  Server.run "/tmp/frameforge.socket" Ethernet_handler.handle
