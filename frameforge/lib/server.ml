type handler = Bytes.t -> Bytes.t

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
  set header 0 (Char.chr (size land 0xff));
  set header 1 (Char.chr ((size lsr 8) land 0xff));
  set header 2 (Char.chr ((size lsr 16) land 0xff));
  set header 3 (Char.chr ((size lsr 24) land 0xff));
  header

(** Read exactly n bytes or return 0 if client is disconnected *)
let rec read_exact fd buf offset len =
  if len = 0 then 1
  else
    match Unix.read fd buf offset len with
    | 0 -> 0
    | n -> read_exact fd buf (offset + n) (len - n)

(** handle one client connection *)
let handle_client fd handler =
  let rec aux () =
    (* --- Read the first 4 bytes first to get the size *)
    let header = Bytes.create 4 in
    match read_exact fd header 0 4 with
    | 0 -> () (* client disconnected, so quit *)
    | _ -> (
        let data_size = decode_header header in
        Printf.printf "FRAMEFORGE: Data size: %d\n" data_size;
        (* --- Read payload *)
        let payload = Bytes.create data_size in
        match read_exact fd payload 0 data_size with
        | 0 ->
            Printf.printf
              "FRAMEFORGE: client disconnected before sending payload\n%!";
            ()
        | _ ->
            (* --- Call the handler *)
            let response = handler payload in
            (* --- Send response *)
            let response_size = Bytes.length response in
            let header = encode_header response_size in
            ignore @@ Unix.write fd header 0 4;
            ignore @@ Unix.write fd response 0 response_size;
            flush Out_channel.stdout;
            aux ())
  in
  aux ()

let run socket_path (handler : handler) =
  (* Add the signal handler to cleanly shutdown the server *)
  Sys.(set_signal sigint (Signal_handle (fun _ -> ())));
  let open Unix in
  (* Start by removing the old socket, ignore errors *)
  (try Unix.unlink socket_path with _ -> ());
  let sock = socket PF_UNIX SOCK_STREAM 0 in
  bind sock (ADDR_UNIX socket_path);
  (* just allow one connection for now *)
  listen sock 1;
  Printf.printf "FrameForge listening on %s\n%!" socket_path;
  (* Handle one connected client until it disconnects *)
  let rec accept_loop () =
    try
      let fd, _ = accept sock in
      Printf.printf "FRAMEFORGE: Client connected\n%!";
      handle_client fd handler;
      close fd;
      Printf.printf "FRAMEFORGE: client disconnected\n%!";
      accept_loop ()
    with
    | Unix_error (EINTR, _, _) ->
        (* The handler does nothing but allow us to reach this point that is why it is required.
           Without the signal handler we just quit directly.*)
        print_endline "FRAMEFORGE: Server ends cleanly"
    | exn ->
        Printf.printf "FRAMEFORGE: Got error: %s\n%!" (Printexc.to_string exn)
  in
  accept_loop ();
  close sock;
  Printf.printf "FRAMEFORGE: Connection closed\n%!"
