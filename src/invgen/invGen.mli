(* This file is part of the Kind 2 model checker.

   Copyright (c) 2015 by the Board of Trustees of the University of Iowa

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


(** Generic invariant generation.

Invariant generation is written as a functor and is instantiated to create
boolean, integer and real invariant generation.

For more details, refer to the paper about invariant generation that I need to
write but haven't yet.
*)



(** Temporary entry point for boolean invariant generation. *)
val main_bool :
  bool -> 'a InputSystem.t -> Analysis.param -> TransSys.t -> unit

(** Temporary entry point for integer invariant generation. *)
val main_int :
  bool -> 'a InputSystem.t -> Analysis.param -> TransSys.t -> unit

(** Temporary entry point for real invariant generation. *)
val main_real :
  bool -> 'a InputSystem.t -> Analysis.param -> TransSys.t -> unit

(** Temporary exit point for boolean invariant generation. *)
val exit : 'a -> unit


(** Signature of the module returned by the [Make] invariant generation functor
when given a module with signature [In]. *)
module type Out = sig
  (** Runs the invariant generator. *)
  val main :
    Numeral.t option -> bool -> bool -> bool -> 'a InputSystem.t ->
    Analysis.param -> TransSys.t -> (
      TransSys.t * Term.TermSet.t * Term.TermSet.t
    ) list
  (** Clean exit for the invariant generator. *)
  val exit : 'a -> unit
end


(** Boolean invariant generation module. *)
module BoolInvGen : Out

(** Int invariant generation module. *)
module IntInvGen : Out

(** Real invariant generation module. *)
module RealInvGen : Out



(** Graph modules for equivalence-only invgen. *)
module EqOnly : sig

  (** Graph of booleans. *)
  module BoolInvGen : Out

  (** Graph of integers. *)
  module IntInvGen : Out

  (** Graph of reals. *)
  module RealInvGen : Out

end


(* 
   Local Variables:
   compile-command: "make -C .. -k"
   tuareg-interactive-program: "./kind2.top -I ./_build -I ./_build/SExpr"
   indent-tabs-mode: nil
   End: 
*)