let handle (payload : bytes) : bytes =
  let payload_size = Bytes.length payload in
  Printf.printf "FRAMEFORGE: payload size %d\n" payload_size ;
  Bytes.of_string "TODO: parse ethernet frame\n"
