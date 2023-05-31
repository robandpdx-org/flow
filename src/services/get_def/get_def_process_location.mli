(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

type ('M, 'T) result =
  | OwnDef of 'M * (* name *) string
  | Request of ('M, 'T) Get_def_request.t
  | Empty of string
  | LocNotFound

val process_location :
  loc_of_annot:('T -> 'M) ->
  ast:('M, 'T) Flow_ast.Program.t ->
  is_legit_require:('T -> bool) ->
  covers_target:('M -> bool) ->
  ('M, 'T) result

val process_location_in_ast :
  ast:(Loc.t, Loc.t) Flow_ast.Program.t ->
  is_legit_require:(Loc.t -> bool) ->
  Loc.t ->
  (Loc.t, Loc.t) result

val process_location_in_typed_ast :
  typed_ast:(ALoc.t, ALoc.t * Type.t) Flow_ast.Program.t ->
  is_legit_require:(ALoc.t * Type.t -> bool) ->
  Loc.t ->
  (ALoc.t, ALoc.t * Type.t) result
