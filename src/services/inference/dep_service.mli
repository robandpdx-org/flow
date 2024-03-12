(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open Utils_js

val calc_unchanged_dependents :
  blocking_worker_communication:bool ->
  MultiWorkerLwt.worker list option ->
  Modulename.Set.t ->
  FilenameSet.t Lwt.t

val calc_dependency_info :
  reader:Mutator_state_reader.t ->
  blocking_worker_communication:bool ->
  MultiWorkerLwt.worker list option ->
  parsed:(* workers *)
         FilenameSet.t ->
  Dependency_info.t Lwt.t

val calc_partial_dependency_graph :
  reader:Mutator_state_reader.t ->
  blocking_worker_communication:bool ->
  MultiWorkerLwt.worker list option ->
  (* workers *)
  FilenameSet.t ->
  parsed:(* files *)
         FilenameSet.t ->
  Dependency_info.partial_dependency_graph Lwt.t
