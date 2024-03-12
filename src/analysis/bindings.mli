(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

module Ast = Flow_ast

type kind =
  | Var
  | Let
  | ThisAnnot
  | Const
  | DeclaredVar
  | DeclaredLet
  | DeclaredConst
  | Type of {
      imported: bool;
      type_only_namespace: bool;
    }
  | Enum
  | Function
  | Class
  | DeclaredClass
  | DeclaredNamespace
  | Parameter
  | CatchParameter
  | Import
  | DeclaredFunction of { predicate: bool }
  | Internal
  | GeneratorNext
  | Component
  | ComponentParameter
[@@deriving show]

type 'loc t

type 'loc entry = ('loc, 'loc) Ast.Identifier.t * kind

val empty : 'loc t

val singleton : 'loc entry -> 'loc t

val add : 'loc entry -> 'loc t -> 'loc t

val push : 'loc t -> 'loc t -> 'loc t

val exists : ('loc entry -> bool) -> 'loc t -> bool

val to_assoc : 'loc t -> (string * (kind * 'loc Nel.t)) list

val to_map : 'loc t -> (kind * 'loc Nel.t) SMap.t

val allow_forward_ref : kind -> bool

val allow_redeclaration : kind -> bool
