type handler = bytes -> bytes
(** Type of a user-provided handler. It receives a payload (decoded from the
    socket) and must return the response payload. *)

val run : string -> handler -> unit
