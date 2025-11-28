(* TODO: use args to set test or not *)
let () = Frameforge.Server.ping_pong ~is_test:true "/tmp/frameforge.socket"
