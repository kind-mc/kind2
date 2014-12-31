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

open Lib

type input = 
  | Lustre of LustreNode.t list 
  | Native 

type pred_def = (UfSymbol.t * (Var.t list * Term.t)) 

type prop_status =

  (* Status of property is unknown *)
  | PropUnknown

  (* Property is true for at least k steps *)
  | PropKTrue of int

  (* Property is true in all reachable states *)
  | PropInvariant 

  (* Property is false at some step *)
  | PropFalse of (StateVar.t * Term.t list) list


(* Return the length of the counterexample *)
let length_of_cex = function 

  (* Empty counterexample has length zero *)
  | [] -> 0

  (* Length of counterexample from first state variable *)
  | (_, l) :: _ -> List.length l


let pp_print_prop_status_pt ppf = function 
  | PropUnknown -> Format.fprintf ppf "unknown"
  | PropKTrue k -> Format.fprintf ppf "true-for %d" k
  | PropInvariant -> Format.fprintf ppf "invariant"
  | PropFalse [] -> Format.fprintf ppf "false"
  | PropFalse cex -> Format.fprintf ppf "false-at %d" (length_of_cex cex)


(* Property status is known? *)
let prop_status_known = function 

  (* Property may become invariant or false *)
  | PropUnknown
  | PropKTrue _ -> false

  (* Property is invariant or false *)
  | PropInvariant
  | PropFalse _ -> true


type t = 

  {

    (* Definitions of uninterpreted function symbols for initial state
       constraint and transition relation *)
    uf_defs : (pred_def * pred_def) list;

    (* State variables of top node *)
    state_vars : StateVar.t list;

    (* Topmost predicate definition for initial state with map of
       formal to actual parameters *)
    init_top : UfSymbol.t * (Var.t * Term.t) list;

    (* Topmost predicate definition for transition relation with
       map of formal to actual parameters *)
    trans_top : UfSymbol.t * (Var.t * Term.t) list;

    (* Properties to prove invariant *)
    props : (string * Term.t) list; 

    (* The input which produced this system. *)
    input : input;

    (* Invariants *)
    mutable invars : Term.t list;

    (* Status of property *)
    mutable prop_status : (string * prop_status) list;
    
  }


let get_invars t =
  t.invars

(* Return the term for the initial state constraint *)
let init_term t = 

  (* Get symbol and map from formal to actual parameters *)
  let init_uf_symbol, params_map = t.init_top in
  
  (* Call to top node *)
  Term.mk_uf init_uf_symbol (List.map snd params_map)


(* Return the term for the transition relation *)
let trans_term t = 

  (* Get symbol and map from formal to actual parameters *)
  let trans_uf_symbol, params_map = t.trans_top in
  
  (* Call to top node *)
  Term.mk_uf trans_uf_symbol (List.map snd params_map)


(* Return topmost predicate definition for initial state constraint
   with map of formal to actual parameters *)
let init_top { init_top } = init_top


(* Return topmost predicate definition for transition relation with
   map of formal to actual parameters *)
let trans_top { trans_top } = trans_top


let pp_print_state_var ppf state_var = 

  Format.fprintf ppf
    "@[<hv 1>(%a %a)@]" 
    StateVar.pp_print_state_var state_var
    Type.pp_print_type (StateVar.type_of_state_var state_var)

  
let pp_print_var ppf var = 

  Format.fprintf ppf
    "@[<hv 1>(%a %a)@]" 
    Var.pp_print_var var
    Type.pp_print_type (Var.type_of_var var)
  

let pp_print_uf_def ppf (uf_symbol, (vars, term)) =

  Format.fprintf 
    ppf   
    "@[<hv 1>(%a@ @[<hv 1>(%a)@]@ %a)@]"
    UfSymbol.pp_print_uf_symbol uf_symbol
    (pp_print_list pp_print_var "@ ") vars
    Term.pp_print_term term


let pp_print_prop ppf (prop_name, prop_term) = 

  Format.fprintf 
    ppf
    "@[<hv 1>(%s@ %a)@]"
    prop_name
    Term.pp_print_term prop_term

let pp_print_prop_status ppf (p, s) =
  Format.fprintf ppf "@[<hv 2>(%s %a)@]" p pp_print_prop_status_pt s


let pp_print_uf_defs 
    ppf
    ((init_uf_symbol, (init_vars, init_term)), 
     (trans_uf_symbol, (trans_vars, trans_term))) = 

  Format.fprintf ppf
    "@[<hv 2>(define-pred-init@ %a@ @[<hv 2>(%a)@]@ %a)@]@,\
     @[<hv 2>(define-pred-trans@ %a@ @[<hv 2>(%a)@]@ %a)@]"
    UfSymbol.pp_print_uf_symbol init_uf_symbol
    (pp_print_list pp_print_var "@ ") init_vars
    Term.pp_print_term init_term
    UfSymbol.pp_print_uf_symbol trans_uf_symbol
    (pp_print_list pp_print_var "@ ") trans_vars
    Term.pp_print_term trans_term


let pp_print_trans_sys 
    ppf
    ({ uf_defs; 
       state_vars; 
       init_top; 
       trans_top; 
       props;
       invars;
       prop_status } as trans_sys) = 

  Format.fprintf 
    ppf
    "@[<v>@[<hv 2>(state-vars@ (@[<v>%a@]))@]@,\
          %a@,\
          @[<hv 2>(init@ (@[<v>%a@]))@]@,\
          @[<hv 2>(trans@ (@[<v>%a@]))@]@,\
          @[<hv 2>(props@ (@[<v>%a@]))@]@,\
          @[<hv 2>(invar@ (@[<v>%a@]))@]@,\
          @[<hv 2>(status@ (@[<v>%a@]))@]@."
    (pp_print_list pp_print_state_var "@ ") state_vars
    (pp_print_list pp_print_uf_defs "@ ") uf_defs
    Term.pp_print_term (init_term trans_sys)
    Term.pp_print_term (trans_term trans_sys)
    (pp_print_list pp_print_prop "@ ") props
    (pp_print_list Term.pp_print_term "@ ") invars
    (pp_print_list pp_print_prop_status "@ ") prop_status


(* Create a transition system *)
let mk_trans_sys uf_defs state_vars init_top trans_top props input = 

  (* Create constraints for integer ranges *)
  let invars_of_types = 
    
    List.fold_left 
      (fun accum state_var -> 

         (* Type of state variable *)
         match StateVar.type_of_state_var state_var with
           
           (* Type is a bounded integer *)
           | sv_type when Type.is_int_range sv_type -> 
             
             (* Get lower and upper bounds *)
             let l, u = Type.bounds_of_int_range sv_type in

             (* Add equation l <= v[0] <= u to invariants *)
             Term.mk_leq 
               [Term.mk_num l; 
                Term.mk_var
                  (Var.mk_state_var_instance state_var Numeral.zero); 
                Term.mk_num u] :: 
             accum
           | _ -> accum)
      []
      state_vars
  in

  { uf_defs = uf_defs;
    state_vars = List.sort StateVar.compare_state_vars state_vars;
    init_top = init_top;
    trans_top = trans_top;
    props = props;
    input = input;
    prop_status = List.map (fun (n, _) -> (n, PropUnknown)) props;
    invars = invars_of_types }


(* Determine the required logic for the SMT solver 

   TODO: Fix this to QF_UFLIA for now, dynamically determine later *)
let get_logic _ = ((Flags.smtlogic ()) :> SMTExpr.logic)


(* Return the state variables of the transition system *)
let state_vars t = t.state_vars

(* Return the input used to create the transition system *)
let get_input t = t.input

(* Return the variables of the transition system between given instants *)
let rec vars_of_bounds' trans_sys lbound ubound accum = 

  (* Return when upper bound below lower bound *)
  if Numeral.(ubound < lbound) then accum else

    (* Add state variables at upper bound instant  *)
    let accum' = 
      List.fold_left
        (fun accum sv -> 
           Var.mk_state_var_instance sv ubound :: accum)
        accum
        trans_sys.state_vars
    in

    (* Recurse to next lower bound *)
    vars_of_bounds' trans_sys lbound (Numeral.pred ubound) accum'

let vars_of_bounds trans_sys lbound ubound = 
  vars_of_bounds' trans_sys lbound ubound []



(* Instantiate the initial state constraint to the bound *)
let init_of_bound t i = 

  (* Get term of initial state constraint *)
  let init_term = init_term t in

  (* Bump bound if greater than zero *)
  if Numeral.(i = zero) then init_term else Term.bump_state i init_term


(* Instantiate the transition relation to the bound *)
let trans_of_bound t i = 

  (* Get term of initial state constraint *)
  let trans_term = trans_term t in

  (* Bump bound if greater than zero *)
  if Numeral.(i = one) then 
    trans_term 
  else 
    Term.bump_state (Numeral.(i - one)) trans_term


(* Instantiate the initial state constraint to the bound *)
let invars_of_bound t i = 

  (* Create conjunction of property terms *)
  let invars_0 = Term.mk_and t.invars in 

  (* Bump bound if greater than zero *)
  if Numeral.(i = zero) then invars_0 else Term.bump_state i invars_0


(* Instantiate terms in association list to the bound *)
let named_terms_list_of_bound l i = 

  (* Bump bound if greater than zero *)
  if
    Numeral.(i = zero)
  then
    l
  else
    List.map (fun (n, t) -> (n, Term.bump_state i t)) l


(* Instantiate all properties to the bound *)
let props_list_of_bound t i = 
  named_terms_list_of_bound t.props i


(* Instantiate all properties to the bound *)
let props_of_bound t i = 
  Term.mk_and (List.map snd (props_list_of_bound t i))

(* Get property by name *)
let prop_of_name t name =
  List.assoc name t.props 

(* Add an invariant to the transition system *)
let add_invariant t invar = t.invars <- invar :: t.invars


(* Return current status of all properties *)
let get_prop_status_all trans_sys = trans_sys.prop_status

(* Return current status of all properties *)
let get_prop_status_all_unknown trans_sys = 

  List.filter
    (fun (_, s) -> not (prop_status_known s))
    trans_sys.prop_status


(* Return current status of property *)
let get_prop_status trans_sys p = 

  try 

    List.assoc p trans_sys.prop_status

  with Not_found -> PropUnknown


(* Mark property as invariant *)
let set_prop_invariant t prop =

  t.prop_status <- 
    
    List.map 

      (fun (n, s) -> if n = prop then 

          match s with
            
            (* Mark property as invariant if it was unknown, k-true or
               invariant *)
            | PropUnknown
            | PropKTrue _
            | PropInvariant -> (n, PropInvariant) 
                               
            (* Fail if property was false or k-false *)
            | PropFalse _ -> raise (Failure "prop_invariant") 

        else (n, s))

      t.prop_status


(* Mark property as k-false *)
let set_prop_false t prop cex =

  t.prop_status <- 

    List.map 

      (fun (n, s) -> if n = prop then 

          match s with

            (* Mark property as k-false if it was unknown, l-true for l <
               k or invariant *)
            | PropUnknown -> (n, PropFalse cex)

            (* Fail if property was invariant *)
            | PropInvariant -> 
              raise (Failure "prop_false")

            (* Fail if property was l-true for l >= k *)
            | PropKTrue l when l > (length_of_cex cex) -> 
              raise (Failure "prop_false")

            (* Mark property as false if it was l-true for l < k *)
            | PropKTrue _ -> (n, PropFalse cex)

            (* Keep if property was l-false for l <= k *)
            | PropFalse cex' when (length_of_cex cex') <= (length_of_cex cex) -> 
              (n, s)

            (* Mark property as k-false *)
            | PropFalse _ -> (n, PropFalse cex) 

        else (n, s))

      t.prop_status


(* Mark property as k-true *)
let set_prop_ktrue t k prop =

  t.prop_status <- 

    List.map 

      (fun (n, s) -> if n = prop then 

          match s with

            (* Mark as k-true if it was unknown *)
            | PropUnknown -> (n, PropKTrue k)

            (* Keep if it was l-true for l > k *)
            | PropKTrue l when l > k -> (n, s)

            (* Mark as k-true if it was l-true for l <= k *)
            | PropKTrue _ -> (n, PropKTrue k)

            (* Keep if it was invariant *)
            | PropInvariant -> (n, s)

            (* Keep if property was l-false for l > k *)
            | PropFalse cex when (length_of_cex cex) > k -> (n, s)

            (* Fail if property was l-false for l <= k *)
            | PropFalse _ -> 
              raise (Failure "prop_kfalse") 

        else (n, s))

      t.prop_status


(* Mark property status *)
let set_prop_status t p = function

  | PropUnknown -> ()

  | PropKTrue k -> set_prop_ktrue t k p

  | PropInvariant -> set_prop_invariant t p

  | PropFalse c -> set_prop_false t p c


(* Return true if the property is proved invariant *)
let is_proved trans_sys prop = 

  try 

    (match List.assoc prop trans_sys.prop_status with
      | PropInvariant -> true
      | _ -> false)
        
  with Not_found -> false


(* Return true if the property is proved not invariant *)
let is_disproved trans_sys prop = 

  try 

    (match List.assoc prop trans_sys.prop_status with
      | PropFalse _ -> true
      | _ -> false)
        
  with Not_found -> false



(* Return true if all properties are either valid or invalid *)
let all_props_proved trans_sys =

  List.for_all
    (fun (p, _) -> 
       try 
         (match List.assoc p trans_sys.prop_status with
           | PropUnknown
           | PropKTrue _ -> false
           | PropInvariant
           | PropFalse _ -> true)
       with Not_found -> false)
    trans_sys.props 
      

(* Return declarations for uninterpreted symbols *)
let uf_symbols_of_trans_sys { state_vars } = 
  List.map StateVar.uf_symbol_of_state_var state_vars


(* Return uninterpreted function symbol definitions *)
let uf_defs { uf_defs } = 

  List.fold_left 
    (fun a (i, t) -> i :: t :: a)
    []
    uf_defs

(* Return uninterpreted function symbol definitions as pairs of
    initial state and transition relation definitions *)
let uf_defs_pairs { uf_defs } = uf_defs


(* Return [true] if the uninterpreted symbol is a transition relation *)
let is_trans_uf_def trans_sys uf_symbol = 

  List.exists
    (function (_, (t, _)) -> UfSymbol.equal_uf_symbols uf_symbol t)
    trans_sys.uf_defs
 

(* Return [true] if the uninterpreted symbol is an initial state constraint *)
let is_init_uf_def trans_sys uf_symbol = 

  List.exists
    (function ((i, _), _) -> UfSymbol.equal_uf_symbols uf_symbol i)
    trans_sys.uf_defs
 

(* Apply [f] to all uninterpreted function symbols of the transition
   system *)
let iter_state_var_declarations { state_vars } f = 
  List.iter (fun sv -> f (StateVar.uf_symbol_of_state_var sv)) state_vars
  
(* Apply [f] to all function definitions of the transition system *)
let iter_uf_definitions { uf_defs } f = 
  List.iter 
    (fun ((ui, (vi, ti)), (ut, (vt, tt))) -> f ui vi ti; f ut vt tt) 
      uf_defs
  

(* Extract a path in the transition system, return an association list
   of state variables to a list of their values *)
let path_from_model trans_sys get_model k =

  let rec path_from_model' accum state_vars = function 

    (* Terminate after the base instant *)
    | i when Numeral.(i < zero) -> accum

    | i -> 

      (* Get a model for the variables at instant [i] *)
      let model =
        get_model
          (List.map (fun sv -> Var.mk_state_var_instance sv i) state_vars)
      in

      (* Turn variable instances to state variables and sort list 

         TODO: It is not necessary to sort the list, if the SMT solver
         returns the list in the order it was input. *)
      let model' =
        List.sort
          (fun (sv1, _) (sv2, _) -> StateVar.compare_state_vars sv1 sv2)
          (List.map
             (fun (v, t) -> (Var.state_var_of_state_var_instance v, t))
             model)
      in

      (* Join values of model at current instant to result *)
      let accum' = 
        list_join
          StateVar.equal_state_vars
          model'
          accum
      in

      (* Recurse for remaining instants  *)
      path_from_model'
        accum'
        state_vars
        (Numeral.pred i)

  in

  path_from_model'
    (List.map (fun sv -> (sv, [])) (state_vars trans_sys))
    (state_vars trans_sys)
    k


(* Return true if the value of the term in some instant satisfies [pred] *)
let rec exists_eval_on_path' uf_defs p term k path =

  try 

    (* Create model for current state, shrink path *)
    let model, path' = 
      List.fold_left 
        (function (model, path) -> function 

           (* No more values for one state variable *)
           | (_, []) -> raise Exit

           (* Take the first value for state variable *)
           | (sv, h :: tl) -> 

             let v = Var.mk_state_var_instance sv Numeral.zero in

             debug transSys 
                 "exists_eval_on_path' at k=%a: %a is %a"
                 Numeral.pp_print_numeral k
                 StateVar.pp_print_state_var sv
                 Term.pp_print_term h
             in

             (* Add pair of state variable and value to model, continue
                with remaining value for variable on path *)
             ((v, h) :: model, (sv, tl) :: path)

        )
        ([], [])
        path
    in

    (* Evaluate term in model *)
    let term_eval = Eval.eval_term uf_defs model term in

    debug transSys 
        "exists_eval_on_path' at k=%a: %a is %a"
        Numeral.pp_print_numeral k
        Term.pp_print_term term
        Eval.pp_print_value term_eval
    in

    (* Return true if predicate holds *)
    if p term_eval then true else

      (* Increment instant *)
      let k' = Numeral.succ k in

      (* Continue checking predicate on path *)
      exists_eval_on_path' uf_defs p term k' path'

  (* Predicate has never been true *)
  with Exit -> false 


(* Return true if the value of the term in some instant satisfies [pred] *)
let exists_eval_on_path uf_defs pred term path = 
  exists_eval_on_path' uf_defs pred term Numeral.zero path 
  


(* 
   Local Variables:
   compile-command: "make -C .. -k"
   tuareg-interactive-program: "./kind2.top -I ./_build -I ./_build/SExpr"
   indent-tabs-mode: nil
   End: 
*)
  
