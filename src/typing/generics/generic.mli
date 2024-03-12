(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

type generic = {
  id: ALoc.id;
  name: Subst_name.t;
}

type id

type bound = {
  generic: generic;
  super: id option;
}

type spread_id = bound list

type sat_result =
  | Satisfied
  | Lower of id
  | Upper of id

val to_string : id -> string

val subst_name_of_id : id -> Subst_name.t

val equal_id : id -> id -> bool

val collapse : id -> id -> id option

val spread_empty : spread_id

val make_spread : id -> spread_id

val make_bound_id : ALoc.id -> Subst_name.t -> id

val make_op_id : Subst_name.op_kind -> spread_id -> id option

val spread_subtract : spread_id -> spread_id -> spread_id

val spread_append : spread_id -> spread_id -> spread_id

val spread_exists : spread_id -> bool

val fold_ids : f:(ALoc.id -> Subst_name.t -> 'a -> 'a) -> acc:'a -> id -> 'a

val satisfies : printer:(string list Lazy.t -> unit) -> id -> id -> sat_result

module ArraySpread : sig
  type ro_status =
    | NonROSpread
    | ROSpread

  type t =
    | Bottom
    | Top
    | Generic of (id * ro_status)

  val merge : printer:(string list Lazy.t -> unit) -> t -> id option -> ro_status -> t

  val to_option : t -> id option
end
