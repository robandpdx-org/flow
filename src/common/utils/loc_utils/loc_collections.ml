(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

module LocSet = Loc_sig.LocS.LSet
module LocMap = Loc_sig.LocS.LMap
module ALocSet = Loc_sig.ALocS.LSet
module ALocMap = Loc_sig.ALocS.LMap

module ALocIDS = struct
  type t = ALoc.id

  let compare (t1 : t) (t2 : t) = ALoc.quick_compare (t1 :> ALoc.t) (t2 :> ALoc.t)
end

module ALocIDSet = Flow_set.Make (ALocIDS)
module ALocIDMap = Flow_map.Make (ALocIDS)

module ALocFuzzy = struct
  type t = ALoc.t

  let compare = ALoc.quick_compare
end

(* For ALocMaps that may contain both keyed and concrete locations. We call it fuzzy because
 * locations that are "equal" but represented differently would be considered unequal. *)
module ALocFuzzyMap = Flow_map.Make (ALocFuzzy)
module ALocFuzzySet = Flow_set.Make (ALocFuzzy)
