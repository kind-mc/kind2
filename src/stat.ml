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

open Lib

(* A generic statistics item *)
type 'a item =
  { display : string;
    mutable value : 'a;
    default : 'a; 
    mutable temp : 'a }

(* An integer statistics item *)
type int_item = int item

(* A float statistics item *)
type float_item = float item 

(* An integer statistics list *)
type int_list_item = int list item

(* A statistics item of a certain type *)
type stat_item = 
  | I of int_item
  | F of float_item
  | L of int_list_item

(* Create a statistics item *)  
let empty_item display default = 
  { display = display; value = default; default = default; temp = default }


(* ********************************************************************** *)
(* Accessors                                                              *)
(* ********************************************************************** *)

(* Set the value of a generic statistics item *)
let set_value value item = item.value <- value

(* Set an integer statistics item *)
let set = set_value

(* Set a float statistics item *)
let set_float = set_value

(* Set an integer statistics list *)
let set_int_list = set_value

(* Increment an integers statistics item *)
let incr ?(by = 1) ({ value } as item) = set_value (value + by) item

(* Increment the last element of an integers statistics list *)
let incr_last ?(by = 1) ({ value } as item) = 

  let rec aux = 
    function 
      | [] -> []
      | [l] -> [l + by]
      | h :: tl -> h :: aux tl
  in

  set_value (aux value) item


(* Increment an integers statistics item *)
let incr_float by ({ value } as item) = set_value (value +. by) item

(* Append at the end of an integers statistics list *)
let append elem ({ value } as item) = set_value (value @ [elem]) item

(* Reset the value of a generic statistics item *)
let reset_value item = item.value <- item.default

(* Reset the value of an integer statistics item *)
let reset item = reset_value item

(* Reset a float statistics item to its initial value *)
let reset_float item = reset_value item

(* Reset an integer list statistics item to its initial value *)
let reset_int_list item = reset_value item

(* Get the value of a generic statistics item *)
let get_value { value } = value

(* Get the value of an integer statistics item *)
let get item = get_value item

(* Get the value of a float statistics item *)
let get_float item = get_value item

(* Get the value of an integer statistics list *)
let get_int_list item = get_value item

(* Start the timer for the statistics item *)
let start_timer item = 

  item.temp <- (Unix.gettimeofday ())

(* Record the time since the call to {!start_timer} of this item, stop
   the timer *)
let record_time ({ temp } as item) = 

  if temp > 0. then 
    (item.value <- item.value +. (Unix.gettimeofday () -. temp);
     item.temp <- 0.)

(* Record the time since the call to {!start_timer} of this item, do
   not stop the timer *)
let update_time ({ temp } as item) = 

  if temp > 0. then 
    (let t = Unix.gettimeofday () in
     item.value <- item.value +. (t -. temp);
     item.temp <- t)

(* Time a function call and add to the statistics item *)
let time_fun item f = 

  start_timer item;
  
  let res = f () in

  record_time item;

  res


(* Stop and record all timers *)
let stop_all_timers stats = 

  List.iter 
    (function 
      | F i -> record_time i
      | _ -> ())
    stats


(* ********************************************************************** *)
(* Statistics output                                                      *)
(* ********************************************************************** *)

(* Width of display name of statistics item *)
let display_width = function
  | I { display } | F { display } | L { display } -> String.length display

(* Maximal Width of display names *)
let max_display_width stats = 
  List.fold_left (fun a i -> max (display_width i) a) 1 stats 

(* Pretty-print one statistics item *)
let pp_print_item width ppf = function 

  | I { display; value } -> Format.fprintf ppf "%-*s: %d" width display value

  | F { display; value } -> Format.fprintf ppf "%-*s: %.3f" width display value

  | L { display; value } -> 

    Format.fprintf ppf 
      "%-*s: @[<hov>%a@]" 
      width 
      display 
      (Lib.pp_print_list Format.pp_print_int "@ ") 
      value
  
  
(* Pretty-print a group of statistics items *)
let pp_print_stats ppf stats = 

  (* Get the maximal display width *)
  let w = max_display_width stats in

  pp_print_list (pp_print_item w) "@," ppf stats


(* Pretty-print one statistics item *)
let pp_print_item_xml ppf = function 

  | I { display; value } -> 

    Format.fprintf ppf 
      "@[<hv 2><item>@,\
       <name>%s</name>@,\
       <value type=\"int\">%d</value>@;<0 -2>\
       </item>@]" 
      display 
      value

  | F { display; value } -> 

    Format.fprintf ppf
      "@[<hv 2><item>@,\
       <name>%s</name>@,\
       <value type=\"float\">%.3f</value>@;<0 -2>\
       </item>@]" 
      display 
      value

  | L { display; value } -> 

    Format.fprintf ppf 
      "@[<hv 2><item>@,\
       <name>%s</name>@,\
       @[<hv 2><valuelist>@,%a@;<0 -2></valuelist>@]@;<0 -2>\
       </item>@]" 
      display 
      (Lib.pp_print_list 
         (function ppf -> Format.fprintf ppf "<value type=\"int\">%d</value>")
         "@,") 
      value

  
(* Pretty-print a group of statistics items *)
let pp_print_stats_xml ppf stats = 

  pp_print_list pp_print_item_xml "@," ppf stats
    
(* ********************************************************************** *)
(* Statistics items                                                       *)
(* ********************************************************************** *)

(* ********** BMC statistics ********** *)

let bmc_k = 
  empty_item "k" 0

let bmc_total_time = 
  empty_item "Total time" 0.

(* Title for BMC statistics *)
let bmc_stats_title = "BMC"

(* All BMC statistics *)
let bmc_stats = 
  [ I bmc_k;
    F bmc_total_time ] 

(* Stop and record all times *)
let bmc_stop_timers () = stop_all_timers bmc_stats

(* Pretty-print BMC statistics items *)
let pp_print_bmc_stats ppf = 

  Format.fprintf ppf "@[<v>@,[%s]@,%a@]"
    bmc_stats_title
    pp_print_stats bmc_stats


(* ********** Inductive step statistics ********** *)

let ind_k = 
  empty_item "k" 0

let ind_restarts = 
  empty_item "Restarts" 0

let ind_total_time = 
  empty_item "Total time" 0.

(* Title for inductive step statistics *)
let ind_stats_title = "Inductive step"

(* All inductive step statistics *)
let ind_stats = 
  [ I ind_k;
    I ind_restarts;
    F ind_total_time ] 

(* Stop and record all times *)
let ind_stop_timers () = stop_all_timers ind_stats

(* Pretty-print inductive step statistics items *)
let pp_print_ind_stats ppf = 

  Format.fprintf ppf "@[<v>@,[%s]@,%a@]"
    ind_stats_title
    pp_print_stats ind_stats


(* ********** PDR statistics ********** *)

let pdr_k = 
  empty_item "k" 0

let pdr_frame_sizes = 
  empty_item "Frame sizes" []

let pdr_fwd_propagated = 
  empty_item "Forward propagations" 0

let pdr_inductive_blocking_clauses = 
  empty_item "Inductive blocking clauses" 0

let pdr_fwd_fixpoint = 
  empty_item "Fixpoint at" 0

let pdr_counterexamples = 
  empty_item "Counterexamples per frame" []

let pdr_counterexamples_total = 
  empty_item "Counterexamples total" 0

let pdr_total_time = 
  empty_item "Total time" 0.

let pdr_fwd_prop_time = 
  empty_item "Forward propagation time" 0.

let pdr_block_propagated_cex_time = 
  empty_item "Block propagated counterexample time" 0.

let pdr_strengthen_time = 
  empty_item "Frame strengthening time" 0.

let pdr_generalize_time = 
  empty_item "Generalization time" 0.

let pdr_find_cex_time = 
  empty_item "Counterexample search time" 0.

let pdr_inductive_check_time = 
  empty_item "Inductiveness check time" 0.

let pdr_tighten_to_subset_time = 
  empty_item "Tightening to subset time" 0.

let pdr_tightened_blocking_clauses =
  empty_item "Tightened blocking clauses" 0

(* Title for PDR statistics *)
let pdr_stats_title = "PDR"

(* All PDR statistics *)
let pdr_stats = 
  [ I pdr_k; 
    L pdr_frame_sizes; 
    I pdr_fwd_propagated; 
    I pdr_fwd_fixpoint; 
    I pdr_inductive_blocking_clauses; 
    I pdr_tightened_blocking_clauses;
    L pdr_counterexamples; 
    I pdr_counterexamples_total;
    F pdr_total_time;
    F pdr_fwd_prop_time;
    F pdr_block_propagated_cex_time;
    F pdr_strengthen_time;
    F pdr_generalize_time; 
    F pdr_find_cex_time; 
    F pdr_inductive_check_time; 
    F pdr_tighten_to_subset_time; ] 

(* Stop and record all timers *)
let pdr_stop_timers () = stop_all_timers pdr_stats

(* Pretty-print PDR statistics items *)
let pp_print_pdr_stats ppf = 

  Format.fprintf ppf "@[<v>@,[%s]@,%a@]"
    pdr_stats_title
    pp_print_stats pdr_stats


(* ********** SMT statistics ********** *)

let smt_check_sat_time = 
  empty_item "check-sat time" 0.

let smt_get_value_time = 
  empty_item "get-value time" 0.

(* Title for SMT statistics *)
let smt_stats_title = "SMT"

(* All SMT statistics *)
let smt_stats = 
  [ F smt_check_sat_time;
    F smt_get_value_time ] 

(* Stop and record all times *)
let smt_stop_timers () = stop_all_timers smt_stats

(* Pretty-print SMT statistics items *)
let pp_print_smt_stats ppf = 

  Format.fprintf ppf "@[<v>@,[%s]@,%a@]"
    smt_stats_title
    pp_print_stats smt_stats


(* ********** Misc statistics ********** *)

let clause_of_term_time = 
  empty_item "clause_of_term time" 0.

let smtexpr_of_term_time = 
  empty_item "smtexpr_of_term time" 0.

let term_of_smtexpr_time =
  empty_item "term_of_smtexpr time" 0.

let cnf_subsume_time = 
  empty_item "CNF subsumption check time" 0.

let misc_stats_title = "General"

let misc_stats = 
  [ F clause_of_term_time;
    F cnf_subsume_time;
    F smtexpr_of_term_time; 
    F term_of_smtexpr_time ]

(* Stop and record all times *)
let misc_stop_timers () = stop_all_timers misc_stats

(* Pretty-print misc statistics items *)
let pp_print_misc_stats ppf = 

  Format.fprintf ppf "@[<v>%a@]"
    pp_print_stats misc_stats


(* 
   Local Variables:
   compile-command: "make -C .. -k"
   tuareg-interactive-program: "./kind2.top -I ./_build -I ./_build/SExpr"
   indent-tabs-mode: nil
   End: 
*)
