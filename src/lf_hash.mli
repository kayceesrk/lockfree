(*
########
Copyright (c) 2017, Nicolas ASSOUAD <nicolas.assouad@ens.fr>
########
*)

module type S = sig
  type 'a t;;

  val still_split_order : 'a t -> bool;;

  val equal : 'a t -> 'a t -> bool;;

  val to_string : 'a t -> string;;

  val to_string_clean : 'a t -> string;;

  val create : unit -> 'a t;;

  val find : 'a t -> int -> 'a option;;

  val mem : 'a t -> int -> bool;;

  val add : 'a t -> int -> 'a -> unit;;

  val remove : 'a t -> int -> unit;;
end;;

module M : S;;
