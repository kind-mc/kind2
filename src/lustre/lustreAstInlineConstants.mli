(* This file is part of the Kind 2 model checker.

   Copyright (c) 2020 by the Board of Trustees of the University of Iowa

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

(** Inlining constants throughout the program
  
    @author Apoorv Ingle *)

module TC = TypeCheckerContext
module LA = LustreAst

type 'a inline_result = ('a, Lib.position * string) result           
(** Result of inlining a constant *)

val inline_constants: TC.tc_context -> LA.declaration list -> (TC.tc_context * LA.declaration list) inline_result
(** Best effort at inlining constants *)

val eval_int_expr: TC.tc_context -> LA.expr -> int inline_result
(** try to evaluate an expression to an int *)
