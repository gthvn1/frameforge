(** Type of a user-provided handler.
    It receives a payload (decoded from the socket)
    and must return the response payload. *)
type handler = Bytes.t -> Bytes.t

val run : string -> handler -> unit
