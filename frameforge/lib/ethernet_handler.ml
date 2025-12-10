let hex_of_bytes (b : bytes) : string list =
  Bytes.fold_left (fun acc c -> Printf.sprintf "%02X" (Char.code c) :: acc) [] b
  |> List.rev

let handle (payload : bytes) : bytes =
  let sl = hex_of_bytes payload in
  (* Insert a new line each 8 elements *)
  List.mapi (fun i s -> if i > 0 && i mod 8 = 0 then "\n" ^ s else s) sl
  |> String.concat " " |> print_endline;
  Bytes.of_string "TODO: parse ethernet frame\n"
