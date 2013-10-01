(*
This file is part of the Kind verifier

* Copyright (c) 2007-2013 by the Board of Trustees of the University of Iowa, 
* here after designated as the Copyright Holder.
* All rights reserved.
*
* Redistribution and use in source and binary forms, with or without
* modification, are permitted provided that the following conditions are met:
*     * Redistributions of source code must retain the above copyright
*       notice, this list of conditions and the following disclaimer.
*     * Redistributions in binary form must reproduce the above copyright
*       notice, this list of conditions and the following disclaimer in the
*       documentation and/or other materials provided with the distribution.
*     * Neither the name of the University of Iowa, nor the
*       names of its contributors may be used to endorse or promote products
*       derived from this software without specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER ''AS IS'' AND ANY
* EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
* DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY
* DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
* (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
* LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
* ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
* (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
* SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*)

(** The representation of a transition system 

    @author Christoph Sticksel
*)


(* The transition system *)
type t = 
    { 

      (* INIT: constraints on system variables 

	 A list of formulas over system variables, no previous state
	 variables occur here *)
      mutable init : (StateVar.t * Term.t) list;

      (* CONSTR: global state constraints 

	 A list of formulas describing invariants of the system *)
      mutable constr : Term.t StateVar.StateVarHashtbl.t;

      (* TRANS: guarded transitions

	 A list of guarded rules: pairs of terms and assignments to
	 system variables, where assignments are pairs of terms *)
      mutable trans : (Term.t * (StateVar.t * Term.t) list) list;   

      (** Named properties to be verified *)
      mutable props : (string * Term.t) list;

      (** Invariants and properties proved to be valid *)
      mutable invars : Term.t list;

      (** Properties proved to be valid *)
      mutable props_valid : (string * Term.t) list;

      (** Properties proved to be invalid *)
      mutable props_invalid : (string * Term.t) list;

      (** Variable dependencies in CONSTR *)
      constr_dep : StateVar.StateVarSet.t StateVar.StateVarHashtbl.t;

    }

(** Add pairs of state variable and definition to hash table *)
val constr_of_def_list : Term.t StateVar.StateVarHashtbl.t -> (StateVar.t * Term.t) list -> unit

(** Pretty-print a transition system *)
val pp_print_trans_sys : Format.formatter -> t -> unit

(** Get the required logic for the SMT solver *)
val get_logic : t -> SMTExpr.logic

(** Add to offset of state variable instances

    Negative values are allowed *)
val bump_state : int -> Term.t -> Term.t

(** Return the variables at the given offset occurring in the term *)
val vars_at_offset_of_term : int -> Term.t -> Var.t list

(** Return the stateful variables at the given offset occurring in the term *)
val state_vars_at_offset_of_term : int -> Term.t -> Var.t list

(** Return the variables occurring in the term *)
val vars_of_term : Term.t -> Var.t list

(** Return variables of the transitions system at bounds zero and one *)
val vars : t -> Var.t list

(** Return state variables of the transitions system *)
val state_vars : t -> StateVar.t list 

(** Create invariants of variable declarations *)
val invars_of_types : unit -> Term.t list

(** Instantiate the initial state constraint to the bound *)
val init_of_bound : int -> t -> Term.t

(** Instantiate the transition relation constraint to the bound 

    The bound given is the bound of the state after the transition *)
val constr_of_bound : int -> t -> Term.t

(** Instantiate the properties to the bound *)
val props_of_bound : int -> t -> Term.t

(** Instantiate invariants and valid properties to the bound *)
val invars_of_bound : int -> t -> Term.t

(** Add an invariant to the transition system *)
val add_invariant : t -> Term.t -> unit 

(** {1 Dependency order} *)

(*
(** Order state variables by dependency in CONSTR: a variables is smaller than all the variables is depends on *)
val compare_state_vars_constr_dep : t -> StateVar.t -> StateVar.t -> int 
*)

(** Get all definitions of state variables from CONSTR

    The definitions are returned in reverse dependency order, leaf
    definitions at the end, ready to be applied as let bindings to a term *)
val constr_defs_of_state_vars : t -> StateVar.t list -> (Var.t * Term.t) list

(** {1 Log messages}

    Examples: 
    - [TransSys.log_property_valid ["a"] "BMC"]
    - [TransSys.log_property_invalid ["a", "b"] "BMC"]
    - [TransSys.log_counterexample ["a"; "b"] Format.pp_print_int 1] 
*)

(** Output validity of some properties 

    Given the name of a module and a list of names of properties as in
    the field [props] of the type {!t}, the function outputs
    [Success: properties p1, p2, p3 proved in module]. *)
val log_property_valid : string -> string list -> unit 

(** Output invalidity of some properties 

    Given the name of a module and a list of names of properties as in
    the field [props] of the type {!t}, the function outputs [Failure:
    properties p1, p2, p3 disproved in module]. *)
val log_property_invalid : string -> string list -> unit

(*
(** Output a counterexample to some properties 

    Given the names of the properties as in the field [props] of the
    type {!t} and a pretty-printer for the counterexample as well as
    the arguments to it, the function outputs [Counterexample for p1,
    p2, p3] followed by the counterexample in the next lines. *)
val log_counterexample : string list -> (Format.formatter -> 'a -> unit) -> 'a -> unit
*)

(* 
   Local Variables:
   compile-command: "make -C .. -k"
   tuareg-interactive-program: "./kind2.top -I ./_build -I ./_build/SExpr"
   indent-tabs-mode: nil
   End: 
*)
  
