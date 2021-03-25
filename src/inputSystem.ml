(* This file is part of the Kind 2 model checker.

   Copyright (c) 2014 by the Board of Trustees of the University of Iowa

   Licensed under the Apache License, Version 2.0 (the "License"); you
   may not use this file except in compliance with the License.  You
   may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0 

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
   implied. See the License for the specific language governing
   permissions and limitations under the License. 

*)

exception UnsupportedFileFormat of string

module S = SubSystem
module N = LustreNode

module SVar = StateVar

module SVM = SVar.StateVarMap

type _ t =
| Lustre : (LustreNode.t S.t * LustreGlobals.t * LustreAst.t) -> LustreNode.t t
| Native : TransSys.t S.t -> TransSys.t t
| Horn : unit S.t -> unit t

let read_input_lustre input_file = Lustre (LustreInput.of_file input_file)

let translate_contracts_lustre = ContractsToProps.translate_file

let read_input_native input_file = Native (NativeInput.of_file input_file)

let read_input_horn input_file = assert false

let silent_contracts_of (type s) : s t -> (Scope.t * string list) list
= function
  | Lustre (subsystem, _, _) ->
    S.all_subsystems subsystem
    |> List.fold_left (
      fun acc { S.scope ; S.source = { N.silent_contracts } } ->
        (scope, silent_contracts) :: acc
    ) []

  | Native subsystem -> raise (UnsupportedFileFormat "Native")

  | Horn subsystem -> raise (UnsupportedFileFormat "Horn")

let ordered_scopes_of (type s) : s t -> Scope.t list = function
  | Lustre (subsystem, _, _) ->
    S.all_subsystems subsystem
    |> List.map (fun { S.scope } -> scope)

  | Native subsystem ->
    S.all_subsystems subsystem
    |> List.map (fun { S.scope } -> scope)

  | Horn subsystem -> assert false

let analyzable_subsystems (type s) : s t -> s SubSystem.t list = function
  | Lustre (subsystem, _, _) ->
    if Flags.modular () then (
      S.all_subsystems subsystem
      |> List.filter (fun s ->
        Strategy.is_candidate_for_analysis (S.strategy_info_of s))
    ) else (
      [subsystem]
    )

  | Native subsystem ->
    if Flags.modular () then (
      S.all_subsystems subsystem
      |> List.filter (fun s ->
        Strategy.is_candidate_for_analysis (S.strategy_info_of s))
    ) else (
      [subsystem]
    )

  | Horn subsystem -> assert false

(* Uid generator for test generation params.

/!\
    This is _wrong_.
    There's gonna be collision with the UIDs for regular analysis. Right now
    analyses and testgen are separate so that's fine, but be careful in the
    future.
/!\

*)
let testgen_uid_ref = ref 1
let get_testgen_uid () =
  let uid = !testgen_uid_ref in
  testgen_uid_ref := uid + 1 ;
  uid

(** Returns the analysis param for [top] that abstracts all its abstractable
    subsystems if [top] has a contract. *)
let maximal_abstraction_for_testgen (type s)
: s t -> Scope.t -> Analysis.assumptions -> Analysis.param option = function

  | Lustre (subsystem, _, _) -> (fun top assumptions ->

    (* Collects all subsystems, abstracting them if possible. *)
    let rec collect map = function
      | sub :: tail ->
        collect (Scope.Map.add sub.S.scope sub.S.has_contract map) tail
      | [] -> Some map
    in

    (* Finds [top] in the subsystems, and then calls [collect]. *)
    let rec get_abstraction_for_top = function
      | sub :: tail ->
        if sub.S.scope = top then
          (* Sub is the system we're looking for. *)
          if sub.S.has_contract then
            (* System has contracts, collecting subsystems. *)
            collect (Scope.Map.add sub.S.scope false Scope.Map.empty) tail
          else
            (* System has no contracts. *)
            None
        else
          (* Sub is not the system we're looking for, skipping. *)
          get_abstraction_for_top tail
      | [] ->
        Format.asprintf
          "system %a does not exist, cannot generate param for testgen"
          Scope.pp_print_scope top
        |> failwith
    in

    match
      S.all_subsystems subsystem |> get_abstraction_for_top
    with

    (* Top is not abstractable. *)
    | None -> None

    (* All good. *)
    | Some map -> Some (
      Analysis.First {
        Analysis.top = top ;
        Analysis.uid = get_testgen_uid () ;
        Analysis.abstraction_map = map ;
        Analysis.assumptions = assumptions ;
      }
    )

  )

  | Native subsystem -> assert false
  | Horn subsystem -> assert false

let next_analysis_of_strategy (type s)
: s t -> 'a -> Analysis.param option = function

  | Lustre (subsystem, _, _) -> (
    fun results ->
      let subs_of_scope scope =
        let { S.subsystems } = S.find_subsystem subsystem scope in
        subsystems
        |> List.map (
          fun ({ S.scope } as sub) ->
            scope, S.strategy_info_of sub
        )
      in
      S.all_subsystems subsystem
      |> List.map (
        fun ({ S.scope } as sub) ->
          scope, S.strategy_info_of sub
      )
      |> Strategy.next_analysis results subs_of_scope
  )

  | Native subsystem -> (
    fun results ->
      let subs_of_scope scope =
        let { S.subsystems } = S.find_subsystem subsystem scope in
        subsystems
        |> List.map (
          fun ({ S.scope } as sub) ->
            scope, S.strategy_info_of sub
        )
      in
      S.all_subsystems subsystem
      |> List.map (
        fun ({ S.scope } as sub) ->
          scope, S.strategy_info_of sub
      )
      |> Strategy.next_analysis results subs_of_scope
  )
         
  | Horn subsystem -> (function _ -> assert false)


let mcs_params (type s) (input_system : s t) =
  let param_for_subsystem sub =
    let scope, abstraction_map =
     sub.S.scope, (* Abstraction map *)
      List.fold_left (
        fun abs_map ({ S.scope; S.has_impl; S.has_contract }) ->
          if Flags.Contracts.compositional () then
            Scope.Map.add scope
              ((not has_impl || has_contract)
              && not (Scope.equal sub.S.scope scope))
              abs_map
          else
            Scope.Map.add scope (not has_impl) abs_map
        )
        Scope.Map.empty (S.all_subsystems sub)
    in
    Analysis.First {
      Analysis.top = scope ;
      Analysis.uid = Analysis.get_uid () ;
      Analysis.abstraction_map = abstraction_map ;
      Analysis.assumptions = Scope.Map.empty ;
    }
  in
  match input_system with
  | Lustre (sub, _, _) ->
    if Flags.modular ()
    then
      S.all_subsystems sub
      |> List.rev
      |> List.map param_for_subsystem
    else
      [sub |> param_for_subsystem]
  | Native sub ->
    if Flags.modular ()
    then
      S.all_subsystems sub
      |> List.rev
      |> List.map param_for_subsystem
    else
      [sub |> param_for_subsystem]
  | Horn _ -> raise (UnsupportedFileFormat "Horn")

let interpreter_param (type s) (input_system : s t) =

  let scope, abstraction_map =
    match input_system with
    | Lustre ({S.scope} as sub, _, _) -> (scope,
      List.fold_left (
        fun abs_map ({ S.scope; S.has_impl }) ->
          Scope.Map.add scope (not has_impl) abs_map
        )
        Scope.Map.empty (S.all_subsystems sub)
    )
    | Native ({S.scope} as sub) -> (scope,
      List.fold_left (
        fun abs_map ({ S.scope; S.has_impl }) ->
          Scope.Map.add scope (not has_impl) abs_map
        )
        Scope.Map.empty (S.all_subsystems sub)
    )
    | Horn _ -> raise (UnsupportedFileFormat "Horn")
  in

  Analysis.Interpreter {
    Analysis.top = scope ;
    Analysis.uid = Analysis.get_uid () ;
    Analysis.abstraction_map = abstraction_map ;
    Analysis.assumptions = Scope.Map.empty ;
  }

let retrieve_lustre_nodes (type s) : s t -> LustreNode.t list =
  (function
  | Lustre (subsystem, _, _) -> 
    let subsystems = S.all_subsystems subsystem in
    List.map (fun sb -> sb.S.source) subsystems
  | Native _ -> failwith "Unsupported input system: Native"
  | Horn _ -> failwith "Unsupported input system: Horn"
  )

let find_lustre_node (type s) : Scope.t -> s t -> LustreNode.t =
  (fun scope -> function
  | Lustre (subsystem, _, _) ->
    let subsystem = S.find_subsystem subsystem scope in
    subsystem.S.source
  | Native _ -> failwith "Unsupported input system: Native"
  | Horn _ -> failwith "Unsupported input system: Horn"
  ) 

let pp_print_subsystems_debug (type s) : Format.formatter -> s t -> unit =
  (fun fmt in_sys ->
    let lustre_nodes = retrieve_lustre_nodes in_sys in
    List.iter (Format.fprintf fmt "%a@." LustreNode.pp_print_node_debug) lustre_nodes
  )

let pp_print_state_var_instances_debug (type s) : Format.formatter -> s t -> unit =
  (fun fmt in_sys ->
    let lustre_nodes = retrieve_lustre_nodes in_sys in
    List.iter (
      Format.fprintf fmt "%a@." LustreNode.pp_print_state_var_instances_debug
    ) lustre_nodes
  )

let pp_print_state_var_defs_debug (type s) : Format.formatter -> s t -> unit =
  (fun fmt in_sys ->
    let lustre_nodes = retrieve_lustre_nodes in_sys in
    List.iter (
      Format.fprintf fmt "%a@." LustreNode.pp_print_state_var_defs_debug
    ) lustre_nodes
  )

let lustre_definitions_of_state_var (type s) (input_system : s t) state_var =
  match input_system with
  | Lustre _ -> LustreNode.get_state_var_defs state_var
  | Native _ -> failwith "Unsupported input system: Native"
  | Horn _ -> failwith "Unsupported input system: Horn"

let lustre_source_ast (type s) (input_system : s t) =
  match input_system with
  | Lustre (_,_,ast) -> ast
  | Native _ -> failwith "Unsupported input system: Native"
  | Horn _ -> failwith "Unsupported input system: Horn"

(* Return a transition system with [top] as the main system, sliced to
   abstractions and implementations as in [abstraction_map]. *)
let trans_sys_of_analysis (type s) ?(preserve_sig = false)
?(slice_nodes = Flags.slice_nodes ())
: s t -> Analysis.param -> TransSys.t * s t = function

  | Lustre (subsystem, globals, ast) -> (
    function analysis ->
      let t, s =
        LustreTransSys.trans_sys_of_nodes
          ~preserve_sig ~slice_nodes globals subsystem analysis
      in
      t, Lustre (s, globals, ast)
    )

  | Native sub -> (fun _ -> sub.SubSystem.source, Native sub)
    
  | Horn _ -> assert false



let pp_print_path_pt
(type s) (input_system : s t) trans_sys instances first_is_init ppf model =

  match input_system with 

  | Lustre (subsystem, _, _) ->
    LustrePath.pp_print_path_pt
      trans_sys instances subsystem first_is_init ppf model

  | Native sub ->
    Format.eprintf "pp_print_path_pt not implemented for native input@.";
    ()
    (* assert false *)

  | Horn _ -> assert false


let pp_print_path_xml
(type s) (input_system : s t) trans_sys instances first_is_init ppf model =

  match input_system with 

  | Lustre (subsystem, _, _) ->
    LustrePath.pp_print_path_xml
      trans_sys instances subsystem first_is_init ppf model

  | Native _ ->
    Format.eprintf "pp_print_path_xml not implemented for native input@.";
    assert false;


  | Horn _ -> assert false


let pp_print_path_json
(type s) (input_system : s t) trans_sys instances first_is_init ppf model =

  match input_system with

  | Lustre (subsystem, _, _) ->
    LustrePath.pp_print_path_json
      trans_sys instances subsystem first_is_init ppf model

  | Native _ ->
    Format.eprintf "pp_print_path_json not implemented for native input@.";
    assert false;

  | Horn _ -> assert false


let pp_print_path_in_csv
(type s) (input_system : s t) trans_sys instances first_is_init ppf model =
  match input_system with

  | Lustre (subsystem, _, _) ->
    LustrePath.pp_print_path_in_csv
      trans_sys instances subsystem first_is_init ppf model

  | Native _ ->
    Format.eprintf "pp_print_path_in_csv not implemented for native input";
    assert false

  | Horn _ -> assert false


let reconstruct_lustre_streams (type s) (input_system : s t) state_vars =
  match input_system with 
  | Lustre (subsystem, _, _) ->
    LustrePath.reconstruct_lustre_streams subsystem state_vars
  | Native _ -> assert false
  | Horn _ -> assert false


let mk_state_var_to_lustre_name_map (type s):
  s t -> StateVar.t list -> string StateVar.StateVarMap.t =
fun sys vars ->
  SVM.fold
    (fun sv l acc ->
      (* If there is more than one alias, the first one is used *)
      let sv', path = List.hd l in
      let scope =
        List.fold_left
          (fun acc (lid, n, _) ->
            Format.asprintf "%a[%d]"
              (LustreIdent.pp_print_ident true) lid n :: acc
          )
          []
          path
      in
      let var_name = StateVar.name_of_state_var sv' in
      let full_name =
        String.concat "." (List.rev (var_name :: scope))
      in
      (* Format.printf "%a -> %s@." StateVar.pp_print_state_var sv full_name ; *)
      SVM.add sv full_name acc
    )
    (reconstruct_lustre_streams sys vars)
    SVM.empty


let is_lustre_input (type s) (input_system : s t) =
  match input_system with 
  | Lustre _ -> true
  | Native _ -> false
  | Horn _ -> false


let slice_to_abstraction_and_property
(type s) (input_sys: s t) analysis trans_sys cex prop
: TransSys.t * TransSys.instance list * (SVar.t * _) list * Term.t * s t = 

  (*
  (* Filter values at instants of subsystem. *)
  let filter_out_values = match input_sys with 

    | Lustre (subsystem, _) -> (fun scope { TransSys.pos } cex v -> 
          
      (* Get node cals in subsystem of scope. *)
      let { S.source = { N.calls } } = 
        S.find_subsystem subsystem scope 
      in
    
      (* Get clock of node call identified by its position. *)
      let { N.call_cond } = 
        List.find (fun {
            N.call_node_name; N.call_pos
          } -> call_pos = pos
        ) calls
      in

      (* Node call has an activation condition? *)
      match call_cond with 

        (* State variable for activation condition. *)
        | [_; N.CActivate clock_state_var] 
        | N.CActivate clock_state_var :: _ -> 

          (* Get values of activation condition from model. *)
          let clock_values = List.assq clock_state_var cex in

          (* Need to preserve order of values *)
          List.fold_right2 (fun cv v a -> match cv with

            (* Value of clock at this instant. *)
            | Model.Term t -> 

             (* Clock is true: keep value at instant. *)
             if Term.equal t Term.t_true then 
               v :: a

             (* Clock is false: skip instant. *)
             else if Term.equal t Term.t_false then 
               a

             (* Clock must be Boolean. *)
             else 
               assert false

            (* TODO: models with arrays. *)
            | _ -> assert false
            ) clock_values v []
            
        (* Keep all instants for node calls without activation
           condition. *)
        | _ -> v

    )

    (* Clocked node calls are only in Lustre, no filtering of instants in
       models for native input. *)
    | Native subsystem -> (fun _ _ _ v -> v)

    (* Clocked node calls are only in Lustre, no filtering of instants in
       models for Horn input. *)
    | Horn subsystem -> (fun _ _ _ v -> v)

  in  

  (* Map counterexample and property to S. *)
  let trans_sys', instances, cex', prop' =
    TransSys.map_cex_prop_to_subsystem 
      filter_out_values trans_sys cex prop
  in
  *)
  let trans_sys', instances, cex', prop' =
    trans_sys, [], cex, prop
  in

  (* Replace top system with subsystem for slicing. *)
  let analysis' =
    Analysis.First {
      (Analysis.info_of_param analysis)
      with Analysis.top = TransSys.scope_of_trans_sys trans_sys'
    }
  in

  (* Return subsystem that contains the property *)
  trans_sys', instances, cex', prop'.Property.prop_term, (

    (* Slicing is input-specific *)
    match input_sys with 

    (* Slice Lustre subnode to property term *)
    | Lustre (subsystem, globals, ast) ->

      let vars = match prop'.Property.prop_source with
        | Property.Assumption _ ->
          TransSys.state_vars trans_sys' |> SVar.StateVarSet.of_list
        | _ ->
          Term.state_vars_of_term prop'.Property.prop_term
      in

      let is_prop'_instantiated =
        match prop'.Property.prop_source with
        | Property.Instantiated _ -> true
        | _ -> false
      in

      let subsystem' =
        if is_prop'_instantiated then
          LustreSlicing.slice_to_abstraction
            (Flags.slice_nodes ()) analysis' subsystem
        else
          LustreSlicing.slice_to_abstraction_and_property
            analysis' vars subsystem
      in

      Lustre (subsystem', globals, ast)

    (* No slicing in native input *)
    | Native subsystem -> Native subsystem

    (* No slicing in Horn input *)
    | Horn subsystem -> Horn subsystem
  )


let inval_arg s = invalid_arg (
  Format.sprintf "expected lustre input, got %s input" s
)

let compile_to_rust (type s): s t -> Scope.t -> string -> unit =
fun sys top_scope target ->
  match sys with
  | Lustre (sub, _, _) ->
    LustreToRust.implem_to_rust target (
      fun scope -> (S.find_subsystem sub scope).S.source
    ) sub.S.source
  | Native _ ->
    Format.printf "can't compile from native input: unsupported"
  | Horn _ ->
    Format.printf "can't compile from horn clause input: unsupported"

let compile_oracle_to_rust (type s): s t -> Scope.t -> string -> (
  string *
  (Lib.position * int) list *
  (string * Lib.position * int) list
) =
fun sys top_scope target ->
  match sys with
  | Lustre (sub, _, _) ->
    LustreToRust.oracle_to_rust target (
      fun scope -> (S.find_subsystem sub scope).S.source
    ) sub.S.source
  | Native _ ->
    failwith "can't compile from native input: unsupported"
  | Horn _ ->
    failwith "can't compile from horn clause input: unsupported"

let contract_gen_param (type s): s t -> (Analysis.param * (Scope.t -> N.t)) =
fun sys ->
  match sys with
  | Lustre (sub, _, _) -> (
    match
      S.all_subsystems sub
      |> List.map (fun ({ S.scope } as sub) ->
        scope, S.strategy_info_of sub
      )
      |> Strategy.monolithic
    with
    | None ->
      failwith "could not generate contract generation analysis parameter"
    | Some param ->
      param, (fun scope -> (S.find_subsystem sub scope).S.source)
  )
  | Native _ ->
    failwith "can't generate contracts from native input: unsupported"
  | Horn _ ->
    failwith "can't generate contracts from horn clause input: unsupported"


(* 
   Local Variables:
   compile-command: "make -C .. -k"
   tuareg-interactive-program: "./kind2.top -I ./_build -I ./_build/SExpr"
   indent-tabs-mode: nil
   End: 
*)
  
