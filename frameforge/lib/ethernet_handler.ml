let hex_of_bytes(b: bytes) : string =
  let _ = b in
  "TODO: print bytes as hex string"

let handle (payload : bytes) : bytes =
  Printf.printf "%s\n" (hex_of_bytes payload);
  Bytes.of_string "TODO: parse ethernet frame\n"
