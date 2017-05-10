(*
########
Copyright (c) 2017, Nicolas ASSOUAD <nicolas.assouad@ens.fr>
########
*)

open Printf;;

module type OrderedType = sig
  type t;;
  val compare : t -> t -> int;;
  val hash_t : t -> t;;
  val str : t -> string;;
end;;

module type S = sig
  type key;;
  type 'a t;;
  val create  : unit -> 'a t;;
  val search : 'a t -> key -> 'a option;;
  val insert : 'a t -> key -> 'a -> unit;;
  val delete : 'a t -> key -> unit;;
  val to_list : 'a t -> (key * key * 'a) list;;
  val heigh : 'a t -> int;;
  val still_bst :'a t -> bool;;
end;;

module Make(Ord : OrderedType) : S with type key = Ord.t = struct

  type key = Ord.t;;

  type real_key =
    |Key of key
    |KMin
    |KMax
  ;;

  let keystr k =
    match k with
    |KMin -> "KMin"
    |KMax -> "KMax"
    |Key(k) -> Ord.str k
  ;;

  type 'a vmap =
    |Value of 'a
    |VMin
    |VMax
  ;;

  type direction =
    |LEFT
    |RIGHT
  ;;

  let dirstr dir =
    match dir with
    |LEFT -> "LEFT"
    |RIGHT -> "RIGHT"
  ;;

  type 'a t = 'a node Kcas.ref
  and 'a edge = direction * 'a t
  and 'a node = {
    value      : 'a vmap;
    key        : real_key;
    true_key   : real_key;
    child      : 'a edge list;
  };;

  let compare x y =
    match x, y with
    |KMin, KMin |KMax, KMax -> 0
    |KMin, KMax |KMin, Key(_) |Key(_), KMax -> -1
    |Key(_), KMin |KMax, KMin |KMax, Key(_) -> 1
    |Key(a), Key(b) -> Ord.compare a b
  ;;

  let hash k =
    match k with
    |Key(v) -> Key(Ord.hash_t v)
    |_ -> k
  ;;

  let get_value v =
    match v with
    |Value(out) -> Some(out)
    |_ -> None
  ;;

  let get_vmin_of t = t;;

  let get_vmax_of t = List.assoc RIGHT (Kcas.get (get_vmin_of t)).child;;

  let create_node hk k v child = {
      value    = v;
      key      = hk;
      true_key = k;
      child    = child;
  };;

  let create () =
    let sentinelle1 = create_node KMax KMax VMax [] in
    let sentinelle2 = create_node KMin KMin VMin [(RIGHT, Kcas.ref sentinelle1)] in
    Kcas.ref sentinelle2
  ;;

  let seek t k =
    let sent1 = get_vmin_of t in
    let sent2 = get_vmax_of t in
    let rec do_seek k anchor gparent gdir parent dir t =
      let vt = Kcas.get t in
      if compare vt.key k = 0 then
        (anchor, gparent, gdir, parent, dir, (t, vt))
      else try
        if compare vt.key k < 0 then
          do_seek k anchor parent dir (t, vt) LEFT (List.assoc LEFT vt.child)
        else
          do_seek k t parent dir (t, vt) RIGHT (List.assoc RIGHT vt.child)
      with Not_found -> (anchor, gparent, gdir, parent, dir, (t, vt))
    in do_seek k sent2 (sent1, Kcas.get sent1) RIGHT (sent1, Kcas.get sent1) RIGHT sent2
  ;;

  let search t k =
    let do_search t k hk =
      let (_, _, _, _, _, (term, vterm)) = seek t hk in
      match vterm.value with
      |Value(out) when compare vterm.true_key k = 0 -> Some(out)
      |_ -> None
    in do_search t (Key(k)) (hash (Key(k)))
  ;;

  let insert t k v =
    let rec do_insert t k hk v =
      let (_, _, _, (parent, vparent), dir, (term, vterm)) = seek t hk in
      (*print_endline (sprintf "INSERT : Seek found (%s %s) %s (%s %s)" (keystr vparent.true_key) (keystr vparent.key) (dirstr dir) (keystr vterm.true_key) (keystr vterm.key));*)
      let new_node = create_node hk k v [] in
      print_endline (sprintf "seek_key = %s ?= %s = new_key" (keystr vterm.key) (keystr hk));
      if compare vterm.key hk = 0 then
        ()
      else
        let nvterm =
          if compare vterm.key hk < 0 then
            create_node vterm.key vterm.true_key vterm.value ((LEFT, Kcas.ref new_node)::(vterm.child))
          else
            create_node vterm.key vterm.true_key vterm.value ((RIGHT, Kcas.ref new_node)::(vterm.child))
        in
        if Kcas.kCAS [Kcas.mk_cas parent vparent vparent ; Kcas.mk_cas term vterm nvterm] then begin
          ()
        end else
          do_insert t k hk v
    in do_insert t (Key(k)) (hash (Key(k))) (Value(v))
  ;;

  let rec min_tree gparent parent t =
    let vt = Kcas.get t in
    try
      min_tree parent (t, vt) (List.assoc LEFT vt.child)
    with Not_found -> (gparent, parent, (t, vt))
  ;;

  let rec max_tree parent t =
    let vt = Kcas.get t in
    try
      max_tree (t, vt) (List.assoc RIGHT vt.child)
    with Not_found -> (parent, (t, vt))
  ;;

  let rec do_delete t k hk =
    let (anchor, (gparent, vgparent), gdir, (parent, vparent), dir, (term, vterm)) = seek t hk in
    print_endline (sprintf "TH%d : DELETE : Seek found (%s %s) %s (%s %s) %s (%s %s)" (Domain.self ()) (keystr vgparent.true_key) (keystr vgparent.key) (dirstr gdir) (keystr vparent.true_key) (keystr vparent.key) (dirstr dir) (keystr vterm.true_key) (keystr vterm.key));
    if compare vterm.key hk = 0 then try
      let ((min_gparent, vmin_gparent), (min_parent, vmin_parent), (min_term, vmin_term)) =
        min_tree (parent, vparent) (term, vterm) (List.assoc RIGHT vterm.child)
      in
      if min_parent = term then (* Direct child to the RIGHT *)
        let new_child = List.append (List.remove_assoc RIGHT vterm.child) vmin_term.child in
        let nvterm = create_node vmin_term.key vmin_term.true_key vmin_term.value new_child in
        print_endline (sprintf "TH%d : BREAK1" (Domain.self ()));
        if Kcas.kCAS [Kcas.mk_cas parent vparent vparent ;
                      Kcas.mk_cas min_term vmin_term vmin_term ;
                      Kcas.mk_cas term vterm nvterm] then
          ()
        else
          do_delete t k hk
      else
        try (* General case *)
          let nvterm = create_node vmin_term.key vmin_term.true_key vmin_term.value vterm.child in
          let nvmin_term = Kcas.get (List.assoc RIGHT vmin_term.child) in
        print_endline (sprintf "TH%d : BREAK2" (Domain.self ()));
          if Kcas.kCAS [Kcas.mk_cas parent vparent vparent ;
                        Kcas.mk_cas term vterm nvterm ;
                        Kcas.mk_cas min_parent vmin_parent vmin_parent ;
                        Kcas.mk_cas min_term vmin_term nvmin_term] then
            ()
          else
            do_delete t k hk
        with Not_found -> (* The replacement node is a leef *)
          let nvterm = create_node vmin_term.key vmin_term.true_key vmin_term.value vterm.child in
          let nvmin_parent_child = List.remove_assoc LEFT vmin_parent.child in
          let nvmin_parent = create_node vmin_parent.key vmin_parent.true_key vmin_parent.value nvmin_parent_child in
        print_endline (sprintf "TH%d : BREAK3" (Domain.self ()));
          if min_gparent = term && Kcas.kCAS [Kcas.mk_cas parent vparent vparent ;
                                              Kcas.mk_cas term vterm nvterm ;
                                              Kcas.mk_cas min_parent vmin_parent nvmin_parent] then
            ()
          else if min_gparent <> term && Kcas.kCAS [Kcas.mk_cas parent vparent vparent ;
                                                    Kcas.mk_cas term vterm nvterm ;
                                                    Kcas.mk_cas min_gparent vmin_gparent vmin_gparent ;
                                                    Kcas.mk_cas min_parent vmin_parent nvmin_parent] then
            ()
          else
            do_delete t k hk
    with Not_found -> (* No node to the right *)
      try
        let n = List.assoc LEFT vterm.child in
        let vn = Kcas.get n in
        print_endline (sprintf "TH%d : BREAK4" (Domain.self ()));
        if Kcas.kCAS [Kcas.mk_cas parent vparent vparent ;
                      Kcas.mk_cas term vterm vn ;
                      Kcas.mk_cas n vn vn] then
          ()
        else
          do_delete t k hk
      with Not_found -> (* The node to delete is a leef *)
        let nvparent_child = List.remove_assoc dir vparent.child in
        let nvparent = create_node vparent.key vparent.true_key vparent.value nvparent_child in
        print_endline (sprintf "TH%d : BREAK5     nombre enfant : %d   ( ==> %d)" (Domain.self ()) (List.length vterm.child) (List.length nvparent_child));
        if Kcas.kCAS [Kcas.mk_cas gparent vgparent vgparent ;
                      Kcas.mk_cas parent vparent nvparent ;
                      Kcas.mk_cas term vterm vterm] then begin
          ()
        end else begin
(*          print_endline "RECURSION 5";*)
          do_delete t k hk
        end
  ;;

  let delete t k = do_delete t (Key(k)) (hash (Key(k)));;

  let to_list t =
    let rec loop t out =
      let vt = Kcas.get t in
      let out1 = try
        let left = List.assoc LEFT vt.child in
        loop left out
      with Not_found -> out in
      let out2 =
        print_endline (sprintf "Val examine %s" (keystr vt.true_key));
        match vt.key, vt.true_key, vt.value with
        |Key(hk), Key(k), Value(v) -> (hk, k, v)::out1
        |_ -> out1
      in
      let out3 = try
        let right = List.assoc RIGHT vt.child in
        loop right out2
      with Not_found -> out2 in
      out3
    in loop t []
  ;;

  let heigh t =
    let rec loop t out =
      let vt = Kcas.get t in
      let h_left = try
        let left = List.assoc LEFT vt.child in loop left (out+1)
      with Not_found -> out in
      let h_right = try
        let right = List.assoc RIGHT vt.child in loop right (out+1)
      with Not_found -> out in
      if h_left > h_right then
        h_left
      else
        h_right
    in loop t 0
  ;;

  let still_bst t =
    let l = to_list t in
    let rec loop p l =
      match l with
      |(hk, k, v)::t ->
        if Ord.compare p hk < 0 then
          loop hk t
        else begin
          print_endline (sprintf "Not a BST because : %s > %s" (Ord.str p) (Ord.str hk));
          false
        end
      |[] -> true
    in
    match l with
    |(hk, k, v)::t -> loop hk t
    |[] -> true
  ;;
end;;
