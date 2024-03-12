(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

module Ast = Flow_ast
open Base.Result
open Ty
module T = Flow_ast.Type

module Let_syntax = struct
  let bind x ~f = x >>= f

  let map x ~f = x >>| f
end

type options = { exact_by_default: bool }

let mapM f ts = all (Base.List.map ~f ts)

let opt f t =
  match t with
  | Some t -> f t >>| fun t -> Some t
  | _ -> return None

let id_from_string x = Flow_ast_utils.ident_of_source (Loc.none, x)

let id_from_symbol x =
  let { sym_name; sym_anonymous; _ } = x in
  if sym_anonymous then
    Error (Utils_js.spf "Cannot output anonymous elements.")
  else
    (* TODO consider issuing an error when we encounter an internal name *)
    Ok (id_from_string (Reason.display_string_of_name sym_name))

let mk_generic x targs =
  { T.Generic.id = T.Generic.Identifier.Unqualified x; targs; comments = None }

let mk_targs arguments = (Loc.none, { T.TypeArgs.arguments; comments = None })

let mk_generic_type x targs = (Loc.none, T.Generic (mk_generic x targs))

let mk_typeof_expr x = T.Typeof.Target.Unqualified x

let builtin_from_string ?targs x =
  let x = id_from_string x in
  mk_generic_type x targs

let variance_ = function
  | Neutral -> None
  | Positive -> Some (Loc.none, { Ast.Variance.kind = Ast.Variance.Plus; comments = None })
  | Negative -> Some (Loc.none, { Ast.Variance.kind = Ast.Variance.Minus; comments = None })

let type_ options =
  let rec type_ t =
    let just t = return (Loc.none, t) in
    let just' t = (Loc.none, t) in
    match t with
    | Bound (_, name) -> Ok (builtin_from_string name)
    | Generic (x, _, ts) -> generic_type x ts
    | Any _ -> just (T.Any None)
    | Top -> just (T.Mixed None)
    | Bot _ -> just (T.Empty None)
    | Void -> just (T.Void None)
    | Null -> just (T.Null None)
    | Symbol -> just (T.Symbol None)
    | Num (Some lit) ->
      return
        (builtin_from_string
           "$TEMPORARY$number"
           ~targs:(mk_targs [(Loc.none, T.NumberLiteral (num_lit lit))])
        )
    | Num None -> just (T.Number None)
    | Str (Some lit) ->
      return
        (builtin_from_string
           "$TEMPORARY$string"
           ~targs:
             (mk_targs [(Loc.none, T.StringLiteral (str_lit (Reason.display_string_of_name lit)))])
        )
    | Str None -> just (T.String None)
    | Bool (Some lit) ->
      return
        (builtin_from_string
           "$TEMPORARY$boolean"
           ~targs:(mk_targs [(Loc.none, T.BooleanLiteral (bool_lit lit))])
        )
    | Bool None -> just (T.Boolean { raw = `Boolean; comments = None })
    | BigInt (Some lit) ->
      return
        (builtin_from_string
           "$TEMPORARY$bigint"
           ~targs:(mk_targs [(Loc.none, T.BigIntLiteral (bigint_lit lit))])
        )
    | BigInt None -> just (T.BigInt None)
    | NumLit lit -> just (T.NumberLiteral (num_lit lit))
    | StrLit lit -> just (T.StringLiteral (str_lit (Reason.display_string_of_name lit)))
    | BoolLit lit -> just (T.BooleanLiteral (bool_lit lit))
    | BigIntLit lit -> just (T.BigIntLiteral (bigint_lit lit))
    | Fun f ->
      let%map f = function_ f in
      (Loc.none, T.Function f)
    | Obj o -> obj_ o
    | Arr a -> arr a
    | Tup elements ->
      let%map els =
        all
          (Base.List.mapi
             ~f:
               (fun i -> function
                 | TupleElement { name; t; polarity; optional } ->
                   let%map annot = type_ t in
                   let el =
                     match (name, polarity) with
                     | (Some name, _) ->
                       T.Tuple.LabeledElement
                         {
                           T.Tuple.LabeledElement.name = id_from_string name;
                           annot;
                           variance = variance_ polarity;
                           optional;
                         }
                     | (None, Neutral) -> T.Tuple.UnlabeledElement annot
                     | _ ->
                       (* No label, but has polarity - e.g. `$ReadOnly<[string, number]>`
                          We must make up a name. *)
                       let name = id_from_string (Printf.sprintf "element_%d" i) in
                       T.Tuple.LabeledElement
                         {
                           T.Tuple.LabeledElement.name;
                           annot;
                           variance = variance_ polarity;
                           optional;
                         }
                   in
                   (Loc.none, el)
                 | TupleSpread { name; t } ->
                   let%map annot = type_ t in
                   let name = Base.Option.map ~f:id_from_string name in
                   let el = T.Tuple.SpreadElement { T.Tuple.SpreadElement.name; annot } in
                   (Loc.none, el))
             elements
          )
      in
      (Loc.none, T.Tuple { T.Tuple.elements = els; comments = None })
    | Union (from_bounds, t0, t1, ts) as t -> union t (from_bounds, t0, t1, ts)
    | Inter (t0, t1, ts) -> intersection (t0, t1, ts)
    | Utility s -> utility s
    | IndexedAccess { _object; index; optional } ->
      let%bind _object = type_ _object in
      let%map index = type_ index in
      let indexed_access = { T.IndexedAccess._object; index; comments = None } in
      if optional then
        (Loc.none, T.OptionalIndexedAccess { T.OptionalIndexedAccess.indexed_access; optional })
      else
        (Loc.none, T.IndexedAccess indexed_access)
    | InlineInterface i -> inline_interface i
    | CharSet s ->
      let id = id_from_string "CharSet" in
      return (mk_generic_type id (Some (mk_targs [(Loc.none, T.StringLiteral (str_lit s))])))
    | Conditional { check_type; extends_type; true_type; false_type } ->
      let%bind check_type = type_ check_type in
      let%bind extends_type = type_ extends_type in
      let%bind true_type = type_ true_type in
      let%map false_type = type_ false_type in
      just'
        (T.Conditional
           { T.Conditional.check_type; extends_type; true_type; false_type; comments = None }
        )
    | Infer (s, b) ->
      let%bind id = id_from_symbol s in
      let%map bound =
        match b with
        | None -> return (T.Missing Loc.none)
        | Some b ->
          let%map bound = type_ b in
          T.Available (just' bound)
      in
      let tparam =
        just'
          {
            T.TypeParam.name = id;
            bound;
            bound_kind = T.TypeParam.Extends;
            variance = None;
            default = None;
          }
      in
      just' (T.Infer { T.Infer.tparam; comments = None })
    | TypeOf (TSymbol name, targs) ->
      let%bind id = id_from_symbol name in
      let%map targs = opt type_arguments targs in
      just' (T.Typeof { T.Typeof.argument = mk_typeof_expr id; targs; comments = None })
    | TypeOf _
    | Renders _ ->
      (* Renders AST representation is not yet committed *)
      Error (Utils_js.spf "Unsupported type constructor `%s`." (Ty_debug.string_of_ctor_t t))
  and generic x targs =
    let%bind id = id_from_symbol x in
    let%map targs = opt type_arguments targs in
    mk_generic id targs
  and generic_type x targs =
    let%bind id = id_from_symbol x in
    let%map targs = opt type_arguments targs in
    mk_generic_type id targs
  and union t (from_bounds, t0, t1, rest) =
    let ts = bk_union t |> Nel.to_list in
    if List.mem Null ts && List.mem Void ts then
      match List.filter (fun t -> not (t = Null || t = Void)) ts with
      | [] ->
        return
          ( Loc.none,
            T.Union
              {
                T.Union.types = ((Loc.none, T.Null None), (Loc.none, T.Void None), []);
                comments = None;
              }
          )
      | hd :: tl ->
        let%map ts = type_ (mk_union ~from_bounds (hd, tl)) in
        (Loc.none, T.Nullable { T.Nullable.argument = ts; comments = None })
    else
      let%bind t0 = type_ t0 in
      let%bind t1 = type_ t1 in
      let%map rest = mapM type_ rest in
      (Loc.none, T.Union { T.Union.types = (t0, t1, rest); comments = None })
  and intersection (t0, t1, rest) =
    let%bind t0 = type_ t0 in
    let%bind t1 = type_ t1 in
    let%map rest = mapM type_ rest in
    (Loc.none, T.Intersection { T.Intersection.types = (t0, t1, rest); comments = None })
  and function_ f =
    let%bind return = fun_return_t f.fun_return in
    let%bind params = fun_params f.fun_params f.fun_rest_param in
    let%map tparams = opt type_params f.fun_type_params in
    { T.Function.params; return; tparams; hook = f.fun_hook; comments = None }
  and fun_params params rest_param =
    let%bind params = mapM fun_param params in
    let%map rest = opt fun_rest_param rest_param in
    ( Loc.none,
      {
        T.Function.Params.params;
        rest;
        (* TODO: handle `this` constraints *)
        this_ = None;
        comments = None;
      }
    )
  and fun_param (name, t, { prm_optional }) =
    let name = Base.Option.map ~f:id_from_string name in
    let%map annot = type_ t in
    (Loc.none, { T.Function.Param.name; annot; optional = prm_optional })
  and fun_rest_param (name, t) =
    let%map argument = fun_param (name, t, { prm_optional = false }) in
    (Loc.none, { T.Function.RestParam.argument; comments = None })
  and fun_return_t = function
    | ReturnType t ->
      let%map t = type_ t in
      Ast.Type.Function.TypeAnnotation t
    | TypeGuard (x, t) ->
      let%map t = type_ t in
      T.Function.TypeGuard
        ( Loc.none,
          { T.TypeGuard.asserts = false; guard = (id_from_string x, Some t); comments = None }
        )
  and obj_ o =
    let%bind properties = mapM obj_prop o.obj_props in
    let%map (exact, inexact, properties) =
      match o.obj_kind with
      | ExactObj -> return (not options.exact_by_default, false, properties)
      | InexactObj -> return (false, true, properties)
      | IndexedObj d ->
        let%map p = obj_index_prop d in
        let properties = T.Object.Indexer (Loc.none, p) :: properties in
        (false, false, properties)
      | MappedTypeObj -> return (false, false, properties)
    in
    let t = (Loc.none, T.Object { T.Object.exact; inexact; properties; comments = None }) in
    match o.obj_literal with
    | Some true -> mk_generic_type (id_from_string "$TEMPORARY$object") (Some (mk_targs [t]))
    | None
    | Some false ->
      t
  and obj_prop = function
    | NamedProp { name; prop; _ } ->
      let%map p = obj_named_prop name prop in
      T.Object.Property (Loc.none, p)
    | CallProp f ->
      let%map p = obj_call_prop f in
      T.Object.CallProperty (Loc.none, p)
    | SpreadProp t ->
      let%map p = obj_spread_prop t in
      T.Object.SpreadProperty p
    | MappedTypeProp { key_tparam; source; prop; flags; homomorphic } ->
      let%map p = obj_mapped_type_prop key_tparam source prop flags homomorphic in
      T.Object.MappedType p
  and obj_named_prop =
    let to_key x =
      if Ty_printer.property_key_quotes_needed x then
        let quote = Ty_printer.better_quote ~prefer_single_quotes:false x in
        let raw = quote ^ Ty_printer.utf8_escape ~quote x ^ quote in
        Ast.Expression.Object.Property.StringLiteral
          (Loc.none, { Ast.StringLiteral.value = x; raw; comments = None })
      else
        Ast.Expression.Object.Property.Identifier (id_from_string x)
    in
    fun x prop ->
      match prop with
      | Field { t; polarity; optional } ->
        let%map t = type_ t in
        {
          (* TODO consider making it an error to try to serialize an internal name *)
          T.Object.Property.key = to_key (Reason.display_string_of_name x);
          value = T.Object.Property.Init t;
          optional;
          static = false;
          proto = false;
          _method = false;
          variance = variance_ polarity;
          comments = None;
        }
      | Method f ->
        let%map fun_t = function_ f in
        {
          T.Object.Property.key = to_key (Reason.display_string_of_name x);
          value = T.Object.Property.Init (Loc.none, T.Function fun_t);
          optional = false;
          static = false;
          proto = false;
          _method = true;
          variance = None;
          comments = None;
        }
      | Get t ->
        let%map t = getter t in
        {
          T.Object.Property.key = to_key (Reason.display_string_of_name x);
          value = T.Object.Property.Get (Loc.none, t);
          optional = false;
          static = false;
          proto = false;
          _method = false;
          variance = None;
          comments = None;
        }
      | Set t ->
        let%map t = setter t in
        {
          T.Object.Property.key = to_key (Reason.display_string_of_name x);
          value = T.Object.Property.Set (Loc.none, t);
          optional = false;
          static = false;
          proto = false;
          _method = false;
          variance = None;
          comments = None;
        }
  and obj_index_prop d =
    let id = Base.Option.map ~f:id_from_string d.dict_name in
    let%bind key = type_ d.dict_key in
    let%map value = type_ d.dict_value in
    {
      T.Object.Indexer.id;
      key;
      value;
      static = false;
      variance = variance_ d.dict_polarity;
      comments = None;
    }
  and obj_call_prop f =
    let%map value = function_ f in
    { T.Object.CallProperty.value = (Loc.none, value); static = false; comments = None }
  and obj_spread_prop t =
    let%map t = type_ t in
    (Loc.none, { T.Object.SpreadProperty.argument = t; comments = None })
  and obj_mapped_type_prop key_tparam source prop { optional; polarity } homomorphic =
    let%bind source_type = type_ source in
    let%bind source_type =
      match homomorphic with
      | Homomorphic -> return (Loc.none, T.Keyof { T.Keyof.argument = source_type; comments = None })
      | SemiHomomorphic selected_keys -> type_ selected_keys
      | Unspecialized -> return source_type
    in
    let%bind prop_type = type_ prop in
    let%map key_tparam = type_param key_tparam in
    let optional =
      T.Object.MappedType.(
        match optional with
        | KeepOptionality -> NoOptionalFlag
        | RemoveOptional -> MinusOptional
        | MakeOptional -> Optional
      )
    in
    let variance = variance_ polarity in
    ( Loc.none,
      {
        T.Object.MappedType.key_tparam;
        prop_type;
        source_type;
        variance;
        optional;
        comments = None;
      }
    )
  and arr { arr_readonly; arr_elt_t; arr_literal; _ } =
    let%map t = type_ arr_elt_t in
    if arr_readonly then
      builtin_from_string "$ReadOnlyArray" ~targs:(mk_targs [t])
    else
      match arr_literal with
      | Some true -> mk_generic_type (id_from_string "$TEMPORARY$array") (Some (mk_targs [t]))
      | None
      | Some false ->
        builtin_from_string "Array" ~targs:(mk_targs [t])
  and type_params ts =
    let%map ts = mapM type_param ts in
    (Loc.none, { T.TypeParams.params = ts; comments = None })
  and type_param tp =
    let%bind bound = opt annotation tp.tp_bound in
    let%map default = opt type_ tp.tp_default in
    ( Loc.none,
      {
        T.TypeParam.name = id_from_string tp.tp_name;
        bound =
          (match bound with
          | Some t -> T.Available t
          | None -> T.Missing Loc.none);
        bound_kind = T.TypeParam.Colon;
        variance = variance_ tp.tp_polarity;
        default;
      }
    )
  and type_arguments ts =
    let%map ts = mapM type_ ts in
    mk_targs ts
  and str_lit lit =
    let quote = Ty_printer.better_quote ~prefer_single_quotes:false lit in
    let raw_lit = Ty_printer.utf8_escape ~quote lit in
    let raw = quote ^ raw_lit ^ quote in
    { Ast.StringLiteral.value = lit; raw; comments = None }
  and num_lit lit =
    {
      Ast.NumberLiteral.value =
        (try Base.Float.of_string lit with
        | Failure _ -> 0.);
      raw = lit;
      comments = None;
    }
  and bool_lit lit = { Ast.BooleanLiteral.value = lit; comments = None }
  and bigint_lit lit =
    { Ast.BigIntLiteral.value = Int64.of_string_opt lit; raw = lit; comments = None }
  and getter t =
    function_
      {
        fun_params = [];
        fun_rest_param = None;
        fun_return = ReturnType t;
        fun_type_params = None;
        fun_static = Ty.Top;
        fun_hook = false;
      }
  and setter t =
    function_
      {
        fun_params = [(None, t, { prm_optional = false })];
        fun_rest_param = None;
        fun_return = ReturnType Void;
        fun_type_params = None;
        fun_static = Ty.Top;
        fun_hook = false;
      }
  and interface_extends e =
    let (x, _, ts) = e in
    let%map gen = generic x ts in
    (Loc.none, gen)
  and inline_interface i =
    let { if_extends; if_props; if_dict } = i in
    let%bind extends = mapM interface_extends if_extends in
    let%bind properties = mapM obj_prop if_props in
    let%bind properties =
      match if_dict with
      | Some d ->
        let%bind p = obj_index_prop d in
        return (T.Object.Indexer (Loc.none, p) :: properties)
      | None -> return properties
    in
    let body =
      (Loc.none, { T.Object.exact = false; inexact = false; properties; comments = None })
    in
    return (Loc.none, T.Interface { T.Interface.body; extends; comments = None })
  and utility u =
    let ctor = Ty.string_of_utility_ctor u in
    let ts = Ty.types_of_utility u in
    let id = id_from_string ctor in
    let%map ts = opt type_arguments ts in
    mk_generic_type id ts
  and annotation t =
    let%map t = type_ t in
    (Loc.none, t)
  in
  (fun t -> type_ t)
