let decode_header bytes : int =
  (* The first 4 bytes are the lenght *)
  let open Bytes in
  let b0 = get bytes 0 |> Char.code in
  let b1 = get bytes 1 |> Char.code in
  let b2 = get bytes 2 |> Char.code in
  let b3 = get bytes 3 |> Char.code in
  (b3 lsl 24) lor (b2 lsl 16) lor (b1 lsl 8) lor b0

let encode_header size : bytes =
  let open Bytes in
  let header = create 4 in
  set header 0 (Char.chr (size land 0xff)) ;
  set header 1 (Char.chr ((size lsr 8) land 0xff)) ;
  set header 2 (Char.chr ((size lsr 16) land 0xff)) ;
  set header 3 (Char.chr ((size lsr 24) land 0xff)) ;
  header

let ping_pong socket_path =
  let open Unix in
  (* Start by removing the old socket, ignore errors *)
  (try Unix.unlink socket_path with _ -> ()) ;

  let sock = socket PF_UNIX SOCK_STREAM 0 in
  bind sock (ADDR_UNIX socket_path) ;
  (* just allow one connection for now *)
  listen sock 1 ;

  Printf.printf "FrameForge listening on %s\n%!" socket_path ;

  let fd, _ = accept sock in

  (* Read the first 4 bytes first to get the size *)
  let header = Bytes.create 4 in
  let _ = read fd header 0 4 in
  let data_size = decode_header header in
  Printf.printf "FRAMEFORGE: Data size: %d\n" data_size ;

  (* Now we can read the rest of the message *)
  let payload = Bytes.create data_size in
  let _ = read fd payload 0 data_size in

  Printf.printf "FRAMEFORGE: Payload  : %s\n" (Bytes.to_string payload) ;

  (* Now we can reply *)
  let msg = "pong" in
  let msg_size = String.length msg in
  let header = encode_header msg_size in
  ignore @@ write fd header 0 4 ;
  ignore @@ write fd (Bytes.of_string msg) 0 msg_size ;

  close fd ;
  close sock ;

  Printf.printf "Connection closed\n%!"
