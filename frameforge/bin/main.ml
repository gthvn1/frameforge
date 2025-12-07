let () =
  let open Frameforge in
  let run_once = Array.mem "--once" Sys.argv in
  (* Currently only pong is available but later we will have another one *)
  let handler =
    if Array.mem "--pong" Sys.argv then
      Pong_handler.handle
    else
      Ethernet_handler.handle
  in

  Server.run ~run_once "/tmp/frameforge.socket" handler
