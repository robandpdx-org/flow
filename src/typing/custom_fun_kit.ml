(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open Flow_js_utils
open Reason
open Type
open TypeUtil

module type CUSTOM_FUN = sig
  val run :
    Context.t ->
    Type.trace ->
    use_op:Type.use_op ->
    return_hint:Type.lazy_hint_t ->
    Reason.t ->
    Type.custom_fun_kind ->
    Type.t list ->
    Type.t option ->
    Type.t ->
    unit
end

module Kit (Flow : Flow_common.S) : CUSTOM_FUN = struct
  include Flow
  module PinTypes = Implicit_instantiation.PinTypes (Flow)

  (* Creates the appropriate constraints for the compose() function and its
   * reversed variant. *)
  let rec run_compose cx trace ~use_op reason_op reverse fns spread_fn tin tout =
    match (reverse, fns, spread_fn) with
    (* Call the tail functions in our array first and call our head function
     * last after that. *)
    | (false, fn :: fns, _) ->
      let reason = replace_desc_reason (RCustom "compose intermediate value") (reason_of_t fn) in
      let tvar =
        Tvar.mk_no_wrap_where cx reason (fun tvar ->
            run_compose cx trace ~use_op reason_op reverse fns spread_fn tin tvar
        )
      in
      rec_flow
        cx
        trace
        ( fn,
          CallT
            {
              use_op;
              reason;
              call_action =
                Funcalltype
                  (mk_functioncalltype ~call_kind:RegularCallKind reason_op None [Arg tvar] tout);
              return_hint = Type.hint_unavailable;
            }
        )
    (* If the compose function is reversed then we want to call the tail
     * functions in our array after we call the head function. *)
    | (true, fn :: fns, _) ->
      let reason = replace_desc_reason (RCustom "compose intermediate value") (reason_of_t fn) in
      let tvar = Tvar.mk_no_wrap cx reason in
      rec_flow
        cx
        trace
        ( fn,
          CallT
            {
              use_op;
              reason;
              call_action =
                Funcalltype
                  (mk_functioncalltype
                     ~call_kind:RegularCallKind
                     reason_op
                     None
                     [Arg (OpenT tin)]
                     (reason, tvar)
                  );
              return_hint = Type.hint_unavailable;
            }
        );
      run_compose cx trace ~use_op reason_op reverse fns spread_fn (reason, tvar) tout
    (* If there are no functions and no spread function then we are an identity
     * function. *)
    | (_, [], None) -> rec_flow_t ~use_op:unknown_use cx trace (OpenT tin, OpenT tout)
    | (_, [], Some spread_fn) ->
      Flow_js_utils.add_output
        cx
        Error_message.(
          EUnsupportedSyntax (spread_fn |> TypeUtil.reason_of_t |> loc_of_reason, SpreadArgument)
        );
      rec_flow_t cx ~use_op:unknown_use trace (AnyT.error reason_op, OpenT tin);
      rec_flow_t cx ~use_op:unknown_use trace (AnyT.error reason_op, OpenT tout)

  let run cx trace ~use_op ~return_hint reason_op kind args spread_arg tout =
    match kind with
    | Compose reverse ->
      (* Drop the specific argument reasons since run_compose will emit CallTs
       * with completely unrelated argument reasons. *)
      let use_op =
        match use_op with
        | Op (FunCall { op; fn; args = _; local }) -> Op (FunCall { op; fn; args = []; local })
        | Op (FunCallMethod { op; fn; prop; args = _; local }) ->
          Op (FunCallMethod { op; fn; prop; args = []; local })
        | _ -> use_op
      in
      let tin = (reason_op, Tvar.mk_no_wrap cx reason_op) in
      let tvar = (reason_op, Tvar.mk_no_wrap cx reason_op) in
      run_compose cx trace ~use_op reason_op reverse args spread_arg tin tvar;
      let tin =
        let tin' = (reason_op, Tvar.mk_no_wrap cx reason_op) in
        unify cx (OpenT tin') (PinTypes.pin_type cx ~use_op:unknown_use reason_op (OpenT tin));
        tin'
      in
      let funt =
        FunT
          ( dummy_static reason_op,
            mk_functiontype
              reason_op
              [OpenT tin]
              ~rest_param:None
              ~def_reason:reason_op
              ~predicate:None
              (OpenT tvar)
          )
      in
      rec_flow_t ~use_op:unknown_use cx trace (DefT (reason_op, funt), tout)
    | ReactCreateElement ->
      (match args with
      (* React.createElement(component) *)
      | [component] ->
        let config =
          let r = replace_desc_reason RReactProps reason_op in
          Obj_type.mk_with_proto cx r ~obj_kind:Exact ~frozen:true (ObjProtoT r)
        in
        rec_flow
          cx
          trace
          ( component,
            ReactKitT
              ( use_op,
                reason_op,
                React.CreateElement0
                  { clone = false; config; children = ([], None); tout; return_hint }
              )
          )
      (* React.createElement(component, config, ...children) *)
      | component :: config :: children ->
        rec_flow
          cx
          trace
          ( component,
            ReactKitT
              ( use_op,
                reason_op,
                React.CreateElement0
                  { clone = false; config; children = (children, spread_arg); tout; return_hint }
              )
          )
      (* React.createElement() *)
      | _ ->
        (* If we don't have the arguments we need, add an arity error. *)
        add_output cx ~trace (Error_message.EReactElementFunArity (reason_op, "createElement", 1)))
    | ReactCloneElement ->
      (match args with
      (* React.cloneElement(element) *)
      | [element] ->
        let f elt =
          (* Create the expected type for our element with a fresh tvar in the
           * component position. *)
          let expected_element =
            get_builtin_typeapp cx (reason_of_t element) "React$Element" [Tvar.mk cx reason_op]
          in
          (* Flow the element arg to our expected element. *)
          rec_flow_t ~use_op cx trace (elt, expected_element);
          expected_element
        in
        let expected_element =
          match Flow.singleton_concrete_type_for_inspection cx (reason_of_t element) element with
          | UnionT (reason, rep) -> UnionT (reason, UnionRep.ident_map f rep)
          | _ -> f element
        in
        (* Flow our expected element to the return type. *)
        rec_flow_t ~use_op:unknown_use cx trace (expected_element, tout)
      (* React.cloneElement(element, config, ...children) *)
      | element :: config :: children ->
        let f element =
          (* Create a tvar for our component. *)
          Tvar.mk_where cx reason_op (fun component ->
              let expected_element = get_builtin_typeapp cx reason_op "React$Element" [component] in
              (* Flow the element arg to the element type we expect. *)
              rec_flow_t ~use_op cx trace (element, expected_element)
          )
        in
        let component =
          match Flow.singleton_concrete_type_for_inspection cx (reason_of_t element) element with
          | UnionT (reason, rep) -> UnionT (reason, UnionRep.ident_map f rep)
          | _ -> f element
        in
        (* Create a React element using the config and children. *)
        rec_flow
          cx
          trace
          ( component,
            ReactKitT
              ( use_op,
                reason_op,
                React.CreateElement0
                  { clone = true; config; children = (children, spread_arg); tout; return_hint }
              )
          )
      (* React.cloneElement() *)
      | _ ->
        (* If we don't have the arguments we need, add an arity error. *)
        add_output cx ~trace (Error_message.EReactElementFunArity (reason_op, "cloneElement", 1)))
    | ReactElementFactory component ->
      (match args with
      (* React.createFactory(component)() *)
      | [] ->
        let config =
          let r = replace_desc_reason RReactProps reason_op in
          Obj_type.mk_with_proto cx r ~obj_kind:Exact ~frozen:true (ObjProtoT r)
        in
        rec_flow
          cx
          trace
          ( component,
            ReactKitT
              ( use_op,
                reason_op,
                React.CreateElement0
                  { clone = false; config; children = ([], None); tout; return_hint }
              )
          )
      (* React.createFactory(component)(config, ...children) *)
      | config :: children ->
        rec_flow
          cx
          trace
          ( component,
            ReactKitT
              ( use_op,
                reason_op,
                React.CreateElement0
                  { clone = false; config; children = (children, spread_arg); tout; return_hint }
              )
          ))
    | ObjectAssign
    | ObjectGetPrototypeOf
    | ObjectSetPrototypeOf
    | DebugPrint
    | DebugThrow
    | DebugSleep ->
      failwith "implemented elsewhere"
end
