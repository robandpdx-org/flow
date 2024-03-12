(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

type t =
  | Identifier
  | ArrayPattern
  | ObjectPattern
  | FunctionReturn
  | Property of { name: string }
  | VariableDefinition of { name: string }
[@@deriving show]

val to_string : t -> string
