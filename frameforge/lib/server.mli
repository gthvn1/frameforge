(** Type of a user-provided handler.
    It receives a payload (decoded from the socket)
    and must return the response payload. *)
type handler = Bytes.t -> Bytes.t

val pong : handler
(** A simple ping pong handler that always returns "pong" *)

val ethframe : handler
(** A handler that processes Ethernet frames *)

val run : ?run_once:bool -> string -> handler -> unit
(** Runs the server on the given port.
    If [run_once] is [true], the server will listen on the port and
    respond once. Otherwise, it will listen indefinitely. *)
