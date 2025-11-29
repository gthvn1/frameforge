(* TODO: use args to set test or not *)
let () =
  let is_test = Array.mem  "--test" Sys.argv in
  Frameforge.Server.ping_pong ~is_test "/tmp/frameforge.socket"
