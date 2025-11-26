let () =
  let open Unix in
  (* Remove old socket *)
  let socket_path = "/tmp/frameforge.socket" in

  (* Start by removing the old socket, ignore errors *)
  (try Unix.unlink socket_path with _ -> ()) ;

  let sock = socket PF_UNIX SOCK_STREAM 0 in
  bind sock (ADDR_UNIX socket_path) ;
  listen sock 1 ;

  (* just allow one connection for now *)
  Printf.printf "FrameForge listening on %s\n%!" socket_path ;

  let fd, _ = accept sock in
  let buf = Bytes.create 1024 in
  let n = read fd buf 0 1024 in
  let msg = Bytes.sub_string buf 0 n in

  Printf.printf "Received: %s\n%!" msg ;

  ignore @@ write fd (Bytes.of_string "pong") 0 (String.length "pong") ;

  close fd ;
  close sock ;

  Printf.printf "Connection closed\n%!"
