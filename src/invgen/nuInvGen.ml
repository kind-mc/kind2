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


open Lib

module NLsd = NuLockStepDriver




(* |===| IO stuff *)


(* Opens a file in write mode, creating it if needed. *)
let openfile path = Unix.openfile path [
  Unix.O_TRUNC ; Unix.O_WRONLY ; Unix.O_CREAT
] 0o640

(* Formatter of a file descriptor. *)
let fmt_of_file file =
  Unix.out_channel_of_descr file |> Format.formatter_of_out_channel

(* Writes a graph in graphviz to file [<path>/<name>_<suff>.dot]. *)
let write_dot_to path name suff fmt_graph graph =
  mk_dir path ; (* Create directory if needed. *)
  let desc = (* Create descriptor for log file. *)
    Format.sprintf "%s/%s_%s.dot" path name suff |> openfile
  in
  (* Log graph in graphviz. *)
  Format.fprintf (fmt_of_file desc) "%a@.@." fmt_graph graph ;
  (* Close log file descriptor. *)
  Unix.close desc



(* |===| Module and type aliases *)


(* LSD module. *)
module Lsd = LockStepDriver

(* Term hash table. *)
module Map = Term.TermHashtbl
(* Term set. *)
module Set = Term.TermSet
(* module Set = struct
  type t = unit Map.t
  let empty () = Map.create 107
  let remove term set = Map.remove set term ; set
  let add term set = Map.replace set term () ; set
  let of_set set =
    Term.TermSet.cardinal set
    |> Map.create
    |> Term.TermSet.fold (
      fun t set -> add t set
    ) set
  let cardinal = Map.length
  let is_empty set = cardinal set = 0
  let iter f set = Map.iter (fun t _ -> f t) set
  let fold f = Map.fold (fun t _ acc -> f t acc)
  exception Found of Term.t
  let choose set =
    try (
      match fold (fun t _ -> raise (Found t)) set [] with
      | [] -> raise Not_found
      | _ -> failwith "unreachable: choose function over sets"
    ) with Found t -> t
  let union lft rgt =
    (* Want to fold over the smallest set. *)
    let lft, rgt =
      if cardinal rgt > cardinal lft then rgt, lft else lft, rgt
    in
    rgt |> fold (fun t lft -> add t lft) lft
  let elements set = fold (fun e l -> e :: l) set []
  let mem t set = Map.mem set t
  exception NotTrue
  let for_all f set =
    try (
      iter (fun t -> if f t |> not then raise NotTrue) set ;
      true
    ) with NotTrue -> false
end *)

(* Transition system module. *)
module Sys = TransSys
(* System hash table. *)
module SysMap = Sys.Hashtbl

(* Numerals. *)
module Num = Numeral

(* Term. *)
type term = Term.t
(* A representative is just a term. *)
type rep = term

(* Maps terms to something. *)
type 'a map = 'a Map.t
(* Set of terms. *)
type set = Set.t

(* Term formatter. *)
let fmt_term = Term.pp_print_term



(* |===| Communication stuff. *)

(** Name of a transition system. *)
let sys_name sys =
  Sys.scope_of_trans_sys sys |> Scope.to_string

(* Guards a term with init if in two state mode. *)
let sanitize_term two_state sys term =
  if two_state then (
    (* We need to sanitize systematically in two state as it DOES NOT check
    anything in the initial state. That is, even one state "invariants" could
    be false in the initial state, and thus must be guarded. *)
    Term.mk_or [ Sys.init_flag_of_bound sys Num.zero ; term ]
  ) else term

(* Guards a term and certificate with init if in two state mode. *)
let sanitize_term_cert two_state sys =
  if two_state then fun (term, (k, phi)) ->
    let term' = sanitize_term two_state sys term in
    if Term.equal term phi then term', (k, term')
    else term', (k, sanitize_term two_state sys phi)
  else identity



(* |===| Functor stuff *)


(** Signature of the modules describing an order relation over some values. *)
module type In = sig
  (** Short string description of the values, used in the logging prefix. *)
  val name : string
  (** Type of the values of the candidate terms. *)
  type t
  (** Value formatter. *)
  val fmt : Format.formatter -> t -> unit
  (** Equality over values. *)
  val eq : t -> t -> bool
  (** Ordering relation. *)
  val cmp : t -> t -> bool
  (** Creates the term corresponding to the ordering of two terms. *)
  val mk_cmp : Term.t -> Term.t -> Term.t
  (** Evaluates a term. *)
  val eval : Sys.t -> Model.t -> Term.t -> t
  (** Mines a transition system for candidate terms. *)
  val mine : bool -> Analysis.param -> bool -> Sys.t -> (Sys.t * Term.TermSet.t) list
  (** Returns true iff the input term is bottom. *)
  val is_bot: Term.t -> bool
  (** Returns true iff the input term is top. *)
  val is_top: Term.t -> bool
end

(** Signature of the module returned by the [Make] invariant generation functor
when given a module with signature [In]. *)
module type Out = sig
  (** Runs the invariant generator. *)
  val main :
    Num.t option -> bool -> bool -> bool -> 'a InputSystem.t ->
    Analysis.param -> Sys.t -> (
      Sys.t * Set.t * Set.t
    ) list
  (** Clean exit for the invariant generator. *)
  val exit : unit -> unit
end



(** Constructs an invariant generation module from a value module.

The central notion used in the graph splitting algorithm is "chains". A chain
is just a list of representative / value pairs that represent the new nodes
obtained after splitting an old node.

Throughout the different algorithms, a chain is ordered by decreasing values.

Once a node is split, the chain is inserted in all the parents of the old node.
The update algorithm is designed such that a node is split iff all its parents
have already be split (that is, their value is known).

Inserting a chain in the parents consists in extracting the longest prefix from
the chain such that all the values are greater than that of the parent. So for
instance when inserting the chain [7, 3, 2, -1] (omitting the representatives)
for a parent with value 1, then the longest prefix is [7, 3, 2]. The graph is
thus updated by linking the parent to the representative with value 2. The rest
of the chain ([-1]) is inserted in all the parents of the parent. *)
module Make (Value : In) : Out = struct

  (* Reference to base checker for clean exit. *)
  let base_ref = ref None
  (* Reference to step checker for clean exit. *)
  let step_ref = ref None
  (* Reference to pruning checkers for clean exit. *)
  let prune_ref = ref []

  (* Kills the LSD instance. *)
  let no_more_lsd () =
    ( match !base_ref with
      | None -> ()
      | Some lsd -> NLsd.kill_base lsd ) ;
    ( match !step_ref with
      | None -> ()
      | Some lsd -> NLsd.kill_step lsd ) ;
    ! prune_ref |> List.iter (
      fun lsd -> NLsd.kill_pruning lsd
    )

  (* Clean exit. *)
  let exit () =
    no_more_lsd () ;
    exit 0

  (** Prefix used for logging. *)
  let pref = Format.sprintf "[%s Inv Gen]" Value.name
  (** Prefix used for logging. *)
  let prefs two_state =
    if two_state then Format.sprintf "[%s Inv Gen 2]" Value.name
    else Format.sprintf "[%s Inv Gen 1]" Value.name

  let mk_and_invar_certs invariants_certs =
    let invs, certs = List.split invariants_certs in
    Term.mk_and invs, Certificate.merge certs

  (* Instantiates [invariants] for all the systems calling [sys] and
  communicates them to the framework. Also adds invariants to relevant pruning
  checker from the [sys -> pruning_checker] map [sys_map].

  Returns the number of top level invariants sent and the invariants for [sys],
  sanitized. *)
  let communicate_invariants top_sys sys_map two_state sys = function
    | [] -> (0,[])
    | invariants_certs ->

      let sanitized =
        mk_and_invar_certs invariants_certs
        (* Guarding with init if needed. *)
        |> sanitize_term_cert two_state sys
      in

      (* All intermediary invariants and top level ones. *)
      let ((_, top_invariants), intermediary_invariants) =
        if top_sys == sys then
          (
            top_sys,
            List.map (sanitize_term_cert two_state sys) invariants_certs
          ), []
        else
          sanitized
          (* Instantiating at all levels. *)
          |> Sys.instantiate_term_cert_all_levels 
            top_sys Sys.prop_base (Sys.scope_of_trans_sys sys)
      in

      intermediary_invariants |> List.iter (
        fun (sub_sys, term_certs) ->
          (* Adding invariants to the transition system. *)
          term_certs
          |> List.iter (fun (i, c) -> Sys.add_invariant sub_sys i c) ;
          (* Adding invariants to the pruning checker. *)
          (
            try (
              let pruning_checker = SysMap.find sys_map sub_sys in
              NLsd.pruning_add_invariants pruning_checker term_certs
            ) with Not_found -> (
              (* System is abstract, skipping. *)
            )
          ) ;
          (* Broadcasting invariants. *)
          term_certs |> List.iter (
            fun (i, c) -> Event.invariant (Sys.scope_of_trans_sys sub_sys) i c
          )
      ) ;
      
      let _ =
        try (
          let pruning_checker = SysMap.find sys_map top_sys in
          NLsd.pruning_add_invariants pruning_checker top_invariants
        ) with Not_found -> (
          (* System is abstract, skipping. *)
        )
      in

      let top_scope = Sys.scope_of_trans_sys top_sys in

      top_invariants |> List.iter (
        fun (inv, cert) ->
          (* Adding top level invariants to transition system. *)
          Sys.add_invariant top_sys inv cert ;
          (* Communicate invariant. *)
          Event.invariant top_scope inv cert
      ) ;

      (List.length top_invariants, [sanitized])


  (** Communicates some invariants and adds them to the trans sys. *)
  let communicate_and_add
    two_state top_sys sys_map sys k blah non_trivial trivial
  =
    ( match (non_trivial, trivial) with
      | [], [] -> ()
      | _, [] ->
        Format.printf (* L_info *)
          "%s @[<v>\
            On system [%s] at %a: %s@ \
            found %d non-trivial invariants\
          @]@.@."
          (prefs two_state)
          (sys_name sys)
          Num.pp_print_numeral k
          blah
          (List.length non_trivial)
      | [], _ ->
        Format.printf (* L_info *)
          "%s @[<v>\
            On system [%s] at %a: %s@ \
            found %d trivial invariants\
          @]@.@."
          (prefs two_state)
          (sys_name sys)
          Num.pp_print_numeral k
          blah
          (List.length trivial)
      | _, _ ->
        Format.printf (* L_info *)
          "%s @[<v>\
            On system [%s] at %a: %s@ \
            found %d non-trivial invariants and %d trivial ones\
          @]@.@."
          (prefs two_state)
          (sys_name sys)
          Num.pp_print_numeral k
          blah
          (List.length non_trivial)
          (List.length trivial)
    ) ;
    List.map (fun i -> i, (Numeral.to_int k + 1, i)) non_trivial
    |> communicate_invariants top_sys sys_map two_state sys
    (* (* Broadcasting invariants. *)
    non_trivial |> List.iter (
      fun term ->
        Sys.add_invariant sys term ;
        Event.invariant (Sys.scope_of_trans_sys sys) term
    ) *)


  (** Receives messages from the rest of the framework.

  Updates all transition systems through [top_sys].

  Adds the new invariants to the pruning solvers in the transition system /
  pruning solver map [sys_map].

  Returns the new invariants for the system [sys]. *)
  let recv_and_update input_sys aparam top_sys sys_map sys =

    let rec update_pruning_checkers sys_invs = function
      | [] -> sys_invs
      | (_, (scope, inv, cert)) :: tail ->
        let this_sys = Sys.find_subsystem_of_scope top_sys scope in
        (* Retrieving pruning checker for this system. *)
        (
          try (
            let pruning_checker = SysMap.find sys_map this_sys in
            NLsd.pruning_add_invariants pruning_checker [inv, cert]
          ) with Not_found -> (
            (* System is abstract, skipping it. *)
          )
        ) ;
        update_pruning_checkers (
          if this_sys == sys then (inv, cert) :: sys_invs else sys_invs
        ) tail
    in

    (* Receiving messages. *)
    Event.recv ()
    (* Updating transition system. *)
    |> Event.update_trans_sys_sub input_sys aparam top_sys
    (* Only keep new invariants. *)
    |> fst
    (* Update everything. *)
    |> update_pruning_checkers []

  (** Structure storing all the graph information. *)
  type graph = {
    (** Maps representatives [t] to the set [{t_i}] of representatives such
    that, for all models seen so far and for all [t_i]s, [In.cmp t t_i]. *)
    map_up: set map ;
    (** Maps representatives [t] to the set [{t_i}] of representatives such
    that, for all models seen so far and for all [t_i]s, [In.cmp t_i t]. *)
    map_down: set map ;
    (** Maps representatives [t] to the set of terms [{t_i}] they represent.
    That is, for all models seen so far and for all [t_i]s,
    [In.value_eq t t_i]. *)
    classes: set map ;
    (** Maps representatives to the value they evaluate to in the current
    model. Cleared between each iteration ([clear] not [reset]). *)
    values: Value.t map ;
  }

  (* Graph constructor. *)
  let mk_graph rep candidates = {
    map_up = (
      let map = Map.create 107 in
      Map.replace map rep Set.empty ;
      map
    ) ;
    map_down = (
      let map = Map.create 107 in
      Map.replace map rep Set.empty ;
      map
    ) ;
    classes = (
      let map = Map.create 107 in
      Map.replace map rep candidates ;
      map
    ) ;
    values = Map.create 107 ;
  }

  let term_count { classes } =
    Map.fold (
      fun rep cl4ss sum -> sum + 1 + (Set.cardinal cl4ss)
    ) classes 0


  let drop_class_member { classes } rep term =
    try
      Map.find classes rep
      |> Set.remove term
      |> Map.replace classes rep
    with Not_found ->
      Event.log L_fatal
        "%s drop_class_member asked to drop term [%a] for inexistant rep [%a]"
        pref fmt_term term fmt_term rep ;
      exit ()

  (* Formats a graph to graphviz format. *)
  let fmt_graph_dot fmt { map_up ; map_down ; classes ; values } =
    Format.fprintf fmt
      "\
  digraph mode_graph {
    graph [bgcolor=black margin=0.0] ;
    node [
      style=filled
      fillcolor=black
      fontcolor=\"#1e90ff\"
      color=\"#666666\"
    ] ;
    edge [color=\"#1e90ff\" fontcolor=\"#222222\"] ;

    @[<v>" ;

    map_up |> Map.iter (
      fun key ->
        let key_len = 1 + (Set.cardinal (Map.find classes key)) in
        let key_value =
          try Map.find values key |> Format.asprintf "%a" Value.fmt
          with Not_found -> "_mada_"
        in
        Set.iter (
          fun kid ->
            let kid_len = 1 + (Set.cardinal (Map.find classes kid)) in
            let kid_value =
              try Map.find values kid |> Format.asprintf "%a" Value.fmt
              with Not_found -> "_mada_"
            in
            Format.fprintf
              fmt "\"%a (%d, %s)\" -> \"%a (%d, %s)\" [\
                constraint=false\
              ] ;@ "
              fmt_term key key_len key_value
              fmt_term kid kid_len kid_value
        )
    ) ;

    map_down |> Map.iter (
      fun key ->
        let key_len = 1 + (Set.cardinal (Map.find classes key)) in
        let key_value =
          try Map.find values key |> Format.asprintf "%a" Value.fmt
          with Not_found -> "_mada_"
        in
        Set.iter (
          fun kid ->
            let kid_len = 1 + (Set.cardinal (Map.find classes kid)) in
            let kid_value =
              try Map.find values kid |> Format.asprintf "%a" Value.fmt
              with Not_found -> "_mada_"
            in
            Format.fprintf
              fmt "\"%a (%d, %s)\" -> \"%a (%d, %s)\" [\
                color=\"red\"\
              ] ;@ "
              fmt_term key key_len key_value
              fmt_term kid kid_len kid_value
        )
    ) ;

    Format.fprintf fmt "@]@.}@."


  (** Logs the equivalence classes of a graph to graphviz. *)
  let fmt_graph_classes_dot fmt { classes ; values } =
    Format.fprintf fmt
      "\
  digraph mode_graph {
    graph [bgcolor=black margin=0.0] ;
    node [
      style=filled
      fillcolor=black
      fontcolor=\"#1e90ff\"
      color=\"#666666\"
    ] ;
    edge [color=\"#1e90ff\" fontcolor=\"#222222\"] ;

    @[<v>" ;

    classes |> Map.iter (
      fun rep set ->
        let rep_value =
          try Map.find values rep |> Format.asprintf "%a" Value.fmt
          with Not_found -> "_mada_"
        in
        Format.fprintf fmt "\"%a (%s)\" ->\"%a\" ;@ "
          fmt_term rep rep_value
          (pp_print_list
            (fun fmt term -> Format.fprintf fmt "@[<h>%a@]" fmt_term term)
            "\n")
          (Set.elements set)
    ) ;

    Format.fprintf fmt "@]@.}@."

  (* Checks that a graph makes sense. *)
  let check_graph ( { map_up ; map_down ; classes } as graph ) =
    (* Format.printf "Checking graph...@.@." ; *)
    Map.fold (
      fun rep reps ok ->

        let is_ok = ref true in

        if ( (* Fail if [rep] has no kids and is not [true] or [false]. *)
          Set.is_empty reps && rep <> Term.t_false && rep <> Term.t_true
        ) then (
          Event.log L_fatal
            "Inconsistent graph:@   \
            @[<v>representative [%a] has no kids@]"
            Term.pp_print_term rep ;
          is_ok := false
        ) ;

        ( try let _ = Map.find classes rep in ()
          with Not_found -> (
            Event.log L_fatal
              "Inconsistent graph:@   \
              @[<v>representative [%a] has no equivalence class@]"
              Term.pp_print_term rep ;
            is_ok := false
          )
        ) ;

        reps |> Set.iter (
          fun kid ->
            try (
              let kid_parents = Map.find map_down kid in
              if Set.mem rep kid_parents |> not then (
                (* Fail if [rep] is not a parent of [kid]. *)
                Event.log L_fatal
                  "Inconsistent graph:@   \
                  @[<v>representative [%a] is a kid of [%a]@ \
                  but [%a] is not a parent of [%a]@]"
                  Term.pp_print_term kid Term.pp_print_term rep
                  Term.pp_print_term rep Term.pp_print_term kid ;
                is_ok := false
              )
            ) with Not_found -> (
              (* Fail if [kid] does not appear in [map_down]. *)
              Event.log L_fatal
                "Inconsistent graph:@   \
                @[<v>representative [%a] does not appear in [map_down]@]"
                Term.pp_print_term kid ;
              is_ok := false
            )
        ) ;

        ok && ! is_ok
    ) map_up true
    |> function
    | true -> ()
    | false -> (
      Event.log L_fatal
        "Stopping invariant generation due to graph inconsistencies" ;
      no_more_lsd () ;
      let dump_path = "./" in
      Event.log L_fatal
        "Dumping current graph as graphviz in current directory" ;
      write_dot_to
        dump_path "inconsistent" "graph" fmt_graph_dot graph ;
      Event.log L_fatal
        "Dumping current classes as graphviz in current directory" ;
      write_dot_to
        dump_path "inconsistent" "classes" fmt_graph_classes_dot graph ;
      failwith "inconsistent graph"
    )


  (** Clears the [values] field of the graph ([clear] not [reset]). *)
  let clear { values } = Map.clear values

  (** Minimal list of terms encoding the current state of the graph. Contains
  - equality between representatives and their class, and
  - comparison terms between representatives.

  Used when querying the base instance of the LSD (graph stabilization).
  See also [all_terms_of], used for the step instance (induction check). *)
  let terms_of { map_up ; classes } known =
    let cond_cons cand l = if known cand then l else cand :: l in
    let eqs =
      Map.fold (
        fun rep set acc ->
          if Set.is_empty set then acc else
            cond_cons (rep :: Set.elements set |> Term.mk_eq) acc
      ) classes []
    in
    Map.fold (
      fun rep above acc ->
        if Value.is_bot rep then acc else
          above |> Set.elements |> List.fold_left (
            fun acc rep' ->
              if Value.is_top rep' then acc
              else cond_cons (Value.mk_cmp rep rep') acc
          ) acc
    ) map_up eqs

  (** Maximal list of terms encoding the current state of the graph. Contains
  - equality between representatives and their class, and
  - comparison terms between all members of the classes.

  Ignores all terms for which [known] is [true].

  Used when querying the step instance of the LSD (induction check). The idea
  is that while the comparison terms between representatives may not be
  inductive, some comparison terms between member of their respective class
  may be.

  See also [terms_of], used for the base instance (graph stabilization).
  This version produces a much larger number of terms. *)
  let all_terms_of {map_up ; classes} known =
    let cond_cons cand l = if known cand then l else cand :: l in
    (* let eqs =
      Map.fold (
        fun rep set acc ->
          if Set.is_empty set then acc else
            cond_cons (rep :: Set.elements set |> Term.mk_eq) acc
      ) classes []
    in *)
    Map.fold (
      fun rep above acc ->
        Set.fold (
          fun rep' acc ->
            (cond_cons (Value.mk_cmp rep rep') acc, true)
            |> Set.fold (
              fun rep_eq' (acc, fst) ->
                cond_cons (Value.mk_cmp rep rep_eq') acc
                |> Set.fold (
                  fun rep_eq acc ->
                    let acc =
                      if fst then (
                        cond_cons (Value.mk_cmp rep_eq rep') acc
                        |> cond_cons (Term.mk_eq [rep ; rep_eq])
                      ) else acc
                    in
                    cond_cons (Value.mk_cmp rep_eq rep_eq') acc
                ) (Map.find classes rep),
                false
            ) (Map.find classes rep')
            |> fst
        ) above acc
    ) map_up []


  (** Equalities coming from the equivalence classes of a graph. *)
  let equalities_of { classes } known =
    let cond_cons l cand info =
      if known cand then l else (cand, info) :: l
    in

    let rec loop rep pref suff = function
      | term :: tail ->
        let pref =
          cond_cons pref (Term.mk_eq [ rep ; term ]) (rep, term)
        in
        let suff =
          List.fold_left (
            fun suff term' ->
              cond_cons suff (Term.mk_eq [ term ; term' ]) (rep, term')
          ) suff tail
        in
        loop rep pref suff tail
      | [] -> List.rev_append pref suff
    in

    (* For each [rep -> terms] in [classes]. *)
    (* Map.fold (
      fun rep terms acc -> Set.elements terms |> loop rep [] acc
    ) classes [] *)

    Map.fold (
      fun rep terms acc ->
        if Set.cardinal terms < 50 then
          Set.elements terms |> loop rep [] acc
        else
          Set.fold (
            fun term acc ->
              ( Term.mk_eq [rep ; term], (rep, term) ) :: acc
          ) terms acc
    ) classes []


  (** Relations between representatives coming from a graph. *)
  let relations_of { map_up ; classes } acc known =
    let cond_cons l cand =
      if known cand then l else (cand, ()) :: l
    in

    (* For each [rep -> term] in [map_up]. *)
    Map.fold (
      fun rep reps acc ->
        if Value.is_bot rep then acc else
          Set.fold (
            fun rep' acc ->
              if (
                Value.is_bot rep
              ) || (
                Value.is_top rep'
              ) then acc else (
                let acc = Value.mk_cmp rep rep' |> cond_cons acc in
                let cl4ss = Map.find classes rep' in
                Set.fold (
                  fun term acc -> Value.mk_cmp rep term |> cond_cons acc
                ) cl4ss acc
              )
          ) reps acc
    ) map_up acc

  (* Formats a chain. *)
  let fmt_chain fmt =
    Format.fprintf fmt "[%a]" (
      pp_print_list
      (fun fmt (rep, value) ->
        Format.fprintf fmt "<%a, %a>" fmt_term rep Value.fmt value)
      ", "
    )

  (** Applies a function [f] to the value [key] is bound to in [map].

  Optional parameter [not_found] is used if [key] is not bound in [map]:
  - if it's [None], [apply] fails
  - if it's [Some default], then a binding between [key] and [f default] will
    be created
  *)
  let apply ?(not_found=None) f key map =
    try
      Map.find map key |> f |> Map.replace map key
    with Not_found -> (
      match not_found with
      | None ->
        Format.asprintf "could not find %a in map" fmt_term key
        |> failwith
      | Some default -> f default |> Map.replace map key
    )

  (** Transitive closure of the parent relation. *)
  let parent_trc map_down =
    let rec loop to_do set rep =
      let kids = Map.find map_down rep in
      let set, to_do =
        Set.fold (
          fun kid (set, to_do) ->
            if Set.mem kid set then set, to_do
            else Set.add kid set, Set.add kid to_do
        ) kids (Set.add rep set, to_do)
      in
      try (
        let rep = Set.choose to_do in
        loop (Set.remove rep to_do) set rep
      ) with Not_found -> set
    in
    loop Set.empty

  (** Adds an edge to the graph. Updates [map_up] and [map_down]. *)
  let add_up { map_up ; map_down } rep kid =
    apply ~not_found:(Some Set.empty) (Set.add kid) rep map_up ;
    apply ~not_found:(Some Set.empty) (Set.add rep) kid map_down


  (** Splits the class of a representative based on a model. Returns the
  resulting chain sorted in DECREASING order on the values of the reps. *)
  let split sys new_reps { classes ; values ; map_up ; map_down } model rep =
    (* Format.printf "  splitting %a@." fmt_term rep ; *)

    (* Value of the representative. *)
    let rep_val = Value.eval sys model rep in

    (* Class of the representative. Terms evaluating to a different value will
    be removed from this set. *)
    let rep_cl4ss = ref (Map.find classes rep) in

    (* Insertion in a list of triples composed of
    - a representative
    - its value in the model
    - its class (set of terms
    The list is ordered by decreasing values.

    Used to evaluate all the terms in [rep_cl4ss] and create the new classes.

    If a representative for the value we're inserting does not exist, then
    a new triple [term, value, Set.empty] is created at the right place in the
    sorted list. Otherwise, if the value is different from [rep_val], it is
    inserted in the set of the representative with that value.
    In both these cases, the term is removed from [rep_cl4ss].
    If the value is equal to [rep_val], nothing happens.

    The idea is that if all terms evaluate to the representative's value, no
    operation is performed. Once all terms in [rep_cl4ss] have been evaluated
    and "inserted", then the representative is inserted with the remaining
    terms form [rep_cl4ss]. *)
    let rec insert ?(is_rep=false) pref sorted term value =
      if is_rep || value <> rep_val then (
        let default = if is_rep then !rep_cl4ss else Set.empty in
        if not is_rep then rep_cl4ss := Set.remove term !rep_cl4ss ;

        match sorted with

        | [] ->
          (* No more elements, inserting. *)
          (term, value, default) :: pref |> List.rev

        | (rep, value', set) :: tail when value = value' ->
          (* Inserting. *)
          (rep, value', Set.add term set) :: tail |> List.rev_append pref

        | ( ((_, value', _) :: _) as tail) when Value.cmp value' value ->
          (* Found a value lower than [value], inserting. *)
          (term, value, default) :: tail |> List.rev_append pref

        | head :: tail ->
          (* [head] is greater than [value], looping. *)
          insert ~is_rep:is_rep (head :: pref) tail term value

      ) else sorted
    in

    (* Creating new classes if necessary. *)
    let sorted =
      Set.fold (
        fun term sorted -> insert [] sorted term (Value.eval sys model term)
      ) !rep_cl4ss []
    in

    match sorted with

    (* No new class was created, all terms evaluate to the value of the 
    representative. *)
    | [] ->
      (* Format.printf
        "    all terms evaluate to %a@.@." Value.fmt rep_val ; *)
      (* Update values, no need to update classes. *)
      Map.replace values rep rep_val ;
      (* All terms in the class yield the same value. *)
      [ (rep, rep_val) ], new_reps

    (* New classes were created. *)
    | _ ->
      (* Format.printf "    class was split@.@." ; *)
      (* Representative's class was split, inserting [rep] and its updated
      class. *)
      let new_reps = ref new_reps in
      let chain =
        insert ~is_rep:true [] sorted rep rep_val
        |> List.map (
          fun (rep, value, set) ->
            (* TODO: add [is_bot] and [is_top] to input modules and use that
            instead. *)
            let rep, set =
              if Set.mem Term.t_true set
              then Term.t_true, set |> Set.add rep |> Set.remove Term.t_true
              else rep, set
            in
            new_reps := ! new_reps |> Set.add rep ;
            (* Update class map. *)
            Map.replace classes rep set ;
            (* Update values. *)
            Map.replace values rep value ;
            (* Insert with empty kids and parents if not already there. *)
            apply ~not_found:(Some Set.empty) identity rep map_up ;
            apply ~not_found:(Some Set.empty) identity rep map_down ;

            (rep, value)
        )
      in

      chain, ! new_reps


  (** Inserts a chain obtained by splitting [rep] in a graph.

  ASSUMES the chain is in DECREASING order.

  Remember that a node can be split iff all its parents have been split. *)
  let insert ({ map_up ; map_down ; values } as graph) rep chain =
    (* Format.printf "  inserting chain for %a@." fmt_term rep ;
    Format.printf "    chain: %a@." fmt_chain chain ; *)

    (* Nodes above [rep]. *)
    let above = Map.find map_up rep in
    (* Nodes below [rep]. *)
    let below = Map.find map_down rep in

    (* Format.printf
      "    %d above, %d below@." (Set.cardinal above) (Set.cardinal below) ; *)

    (* Greatest value in the chain. *)
    let greatest_rep, greatest_val = List.hd chain in

    (* Break all links to [rep], except if rep is the top of the chain. These
    links will be used to update the kids of [rep] in the future. Remember that
    a node can be split iff all its parents have been split. Hence all the kids
    of the current representative have not been split yet. *)
    if Term.equal rep greatest_rep |> not then (
      (* Format.printf "    breaking all links from %a@." fmt_term rep ; *)
      map_up |> apply (
        fun set ->
          (* Break downlinks. *)
          set |> Set.iter (
            fun rep' ->
              (* Format.printf
                "      breaking %a -> %a@." fmt_term rep fmt_term rep' ; *)
              map_down |> apply (Set.remove rep) rep'
          ) ;
          (* Break uplinks. *)
          Set.empty
      ) rep ;
      (* Format.printf "    linking greatest to above@." ; *)
      above |> Set.iter (
        fun above ->
          map_up |> apply (Set.add above) greatest_rep ;
          map_down |> apply (Set.add greatest_rep) above
      )
    ) else (
      (* Format.printf "    keeping uplinks: (original) %a = %a (greatest)@."
        fmt_term rep fmt_term greatest_rep ; *)
    ) ;

    (* Format.printf "    breaking all links to %a@." fmt_term rep ; *)

    (* Break all links to [rep]. *)
    map_down |> apply (
      fun set ->
        (* Break uplinks. *)
        set |> Set.iter (
          fun rep' ->
            (* Format.printf
              "      breaking %a -> %a@." fmt_term rep' fmt_term rep ; *)
            map_up |> apply (Set.remove rep) rep'
        ) ;
        (* Break uplinks. *)
        Set.empty
    ) rep ;

    (* Format.printf "    creating chain links@." ; *)
    
    (* Create links between the elements of the chain.

    Has to be done after we disconnect [rep], otherwise these links would also
    be disconnected. *)
    let rec link_chain last = function
      | (next, _) :: tail ->
        (* Format.printf
          "      creating %a -> %a@." fmt_term next fmt_term last ; *)
        add_up graph next last ;
        link_chain next tail
      | [] -> ()
    in
    ( match chain with
      | (head, _) :: tail -> link_chain head tail
      (* This case IS unreachable, because of the [List.hd chain] above that
      would crash if [chain] was empty. *)
      | [] -> failwith "unreachable"
    ) ;

    (* Returns the longest subchain above [value'], in INCREASING order.
    Assumes the chain is in DECREASING order. *)
    let rec longest_above pref value' = function
      | (rep, value) :: tail when Value.cmp value' value ->
        (* [value'] lower than the head, looping. *)
        longest_above (rep :: pref) value' tail
      | rest ->
        (* [value'] greaten than the head, done. *)
        pref, rest
    in

    (* Inserts a chain.
    - [known]: nodes below [rep] we have already seen
    - [continuation]: list of (sub)chain / parent left to handle
    - [chain]: (sub)chain we're currently inserting
    - [node]: the node we're trying to link to the chain *)
    let rec insert known continuation chain node =
      (* Format.printf "  inserting for %a@." fmt_term node ;

      Format.printf "  continuation: @[<v>%a@]@."
        (pp_print_list
          (fun fmt (chain, nodes) ->
            Format.fprintf fmt "chain: %a@ nodes: %a" fmt_chain chain (pp_print_list fmt_term ", ") nodes)
          "@ ")
        continuation ; *)

      let value = Map.find values node in

      (* Longest chain above current node. *)
      let chain_above, rest = longest_above [] value chain in

      (* Format.printf "    %d above, %d below@."
        (List.length chain_above) (List.length rest) ; *)

      (* Creating links. *)
      ( match chain_above with
        | [] ->
          (* [value] is greater than the greatest value in the (sub)chain. *)

          (* Linking [node] with [above] if [node] is in [below]. (This means
          [node] is a direct parent of [rep] that's greater than any element of
          the chain.) *)
          if Set.mem node below then (
            (* Format.printf "    linking node to above@." ; *)
            map_up |> apply (Set.union above) node ;
            above |> Set.iter (
              fun above -> map_down |> apply (Set.add node) above
            )
          )
        | lowest :: _ ->
          (* [lowest] is the LOWEST element of the chain above [node]. We thus
          link [node] to [lowest]. *)

          add_up graph node lowest ;

          (* I had this thing at some point, but it should not be needed.
          Keeping it just in case. *)

          (* (* Also linking with [above] is [node] is in [below]. *)
          if Set.mem node below then (
            (* Format.printf "    linking greatest to above@." ; *)
            map_up |> apply (Set.union above) greatest_rep ;
            above |> Set.iter (
              fun above -> map_down |> apply (Set.add greatest_rep) above
            )
          ) *)
      ) ;

      (* Anything left to insert below? *)
      match rest with
      | [] ->
        (* Chain completely inserted, add everything below [node] to
        [known]. *)
        let known = parent_trc map_down known node in
        (* Continuing. *)
        continue known continuation
      | _ ->
        (* Not done inserting the chain. *)
        (rest, Map.find map_down node |> Set.elements) :: continuation
        |> continue known

    (* Continuation for chain insertion. *)
    and continue known = function
      | ( chain, [node]) :: continuation ->
        if Set.mem node known then (
          (* Format.printf "    skipping known rep %a@." fmt_term node ; *)
          continue known continuation
        ) else (
          insert (Set.add node known) continuation chain node
        )
      | ( chain, node :: rest) :: continuation ->
        if Set.mem node known then (
          (* Format.printf "    skipping known rep %a@." fmt_term node ; *)
          continue known ( (chain, rest) :: continuation )
        ) else (
          insert (Set.add node known) (
            (chain, rest) :: continuation
          ) chain node
        )
      | (_, []) :: continuation -> continue known continuation
      | [] -> ()
    in

    match Set.elements below with

    (* Nothing below the node that was split. Linking everything above to
    greatest. Future splits will insert things in the right place. *)
    | [] ->
      (* Format.printf "    linking greatest to above@." ; *)
      map_up |> apply (Set.union above) greatest_rep ;
      above |> Set.iter (
        fun above -> map_down |> apply (Set.add greatest_rep) above
      )

    (* Need to insert the chain. *)
    | node :: rest ->
      (* Format.printf "    below:@[<v>%a%a@]@."
        fmt_term node
        (pp_print_list (fun fmt -> Format.fprintf fmt "@ %a" fmt_term) "")
        rest ; *)
      insert Set.empty [ (chain), rest ] chain node

  (* Finds a node that's not been split, but with all its parents split. *)
  let next_of_continuation { map_down ; values } continuation =
    if Set.is_empty continuation then None else (
      try (
        let next, continuation =
          Set.partition (
            fun rep ->
              try
                Map.find map_down rep
                |> Set.for_all (
                  fun rep -> Map.mem values rep
                )
              with Not_found ->
                Format.asprintf
                  "could not find rep %a in map down" fmt_term rep
                |> failwith
          ) continuation
        in
        Some (next, continuation)
      ) with Not_found ->
        failwith "could not find legal next rep in continuation"
    )

  (* Splits a graph based on the current model.

  Returns the representatives created and modified. *)
  let split_of_model sys new_reps model ({ map_down ; map_up } as graph) =
    let rec loop new_reps continuation next =
      (* Format.printf "@.starting update %d / %d@.@." out_cnt in_cnt ; *)
      (* Format.printf "  nxt is %a@.@." fmt_term nxt ; *)
      let new_reps, continuation =
        Set.fold (
          fun rep (new_reps, continuation) ->
            (* Add nodes above current rep to [continuation].
            These nodes CANNOT be in [nxt] because they had an outdated
            parent: the current rep. *)
            let continuation =
              Map.find map_up rep |> Set.union continuation
            in
            (* Split and insert chain. *)
            let new_reps =
              let chain, new_reps = split sys new_reps graph model rep in
              insert graph rep chain ;
              new_reps
            in
            (* Moving on. *)
            new_reps, continuation
        ) next (new_reps, continuation)
      in
      (* write_dot_to
        "graphs/" "graph" (Format.sprintf "%d_%d" out_cnt in_cnt)
        fmt_graph_dot graph ; *)
      match next_of_continuation graph continuation with
      | None -> new_reps
      | Some (next, continuation) ->
        loop new_reps continuation next
    in

    (* Retrieve all nodes that have no parents. *)
    Map.fold (
      fun rep parents acc ->
        if Set.is_empty parents then Set.add rep acc else acc
    ) map_down Set.empty
    (* And start with that. *)
    |> loop new_reps Set.empty

  (** Stabilizes the equivalence classes.
  Stabilizes classes one by one to send relatively few candidates to lsd. *)
  let update_classes sys known lsd ({ classes } as graph) =

    let rec loop count reps_to_update =
      try (

        (* Checking if we should terminate before doing anything. *)
        Event.check_termination () ;

        (* Will raise `Not_found` if no more reps to update (terminal case). *)
        let rep = Set.choose reps_to_update in
        let reps_to_update = Set.remove rep reps_to_update in

        try (

          (* Retrieve class. *)
          let cl4ss = Map.find classes rep in
          (* Building equalities. *)
          let eqs, _ =
            Set.fold (
              fun rep (acc, last) ->
                (Term.mk_eq [last ; rep]) :: acc, rep
            ) cl4ss ([], rep)
          in
          match
            (* Is this set of equalities falsifiable?. *)
            NLsd.query_base lsd eqs
          with
          | None ->
            (* Stable, moving on. *)
            loop (count + 1) reps_to_update
          | Some model ->
            (* Format.printf "  sat@.@." ; *)
            (* Checking if we should terminate before doing anything. *)
            Event.check_termination () ;
            (* Clear (NOT RESET) the value map for update. *)
            clear graph ;
            (* Stabilize graph. *)
            let reps_to_update =
              split_of_model sys reps_to_update model graph
            in
            (* Loop after adding new representatives (includes old one). *)
            loop (count + 1) reps_to_update
        ) with Not_found ->
          Format.asprintf "could not find rep %a in class map" fmt_term rep
          |> failwith

      ) with Not_found ->
        Event.log_uncond
          "update classes done in %d iterations" count
    in

    (* Retrieve all representatives. *)
    Map.fold ( fun rep _ set -> Set.add rep set ) classes Set.empty
    |> loop 0

  (** Stabilizes the relations. *)
  let rec update_rels sys known lsd count ({ map_up ; classes } as graph) =
    (* Checking if we should terminate before doing anything. *)
    Event.check_termination () ;

    (* Building relations. *)
    let rels =
      Map.fold (
        fun rep reps acc ->
          Set.fold (
            fun rep' acc -> (Value.mk_cmp rep rep') :: acc
          ) reps acc
      ) map_up []
    in

    match
      (* Are these relations falsifiable?. *)
      NLsd.query_base lsd rels
    with
    | None ->
      (* Format.printf "update_rels done after %d iterations@.@." count ; *)
      (* Stable, done. *)
      ()
    | Some model ->
      (* Format.printf "  sat@.@." ; *)
      (* Checking if we should terminate before doing anything. *)
      Event.check_termination () ;
      (* Clear (NOT RESET) the value map for update. *)
      clear graph ;
      (* Stabilize graph. *)
      let reps_to_update =
        split_of_model sys Set.empty model graph
      in
      (
        if Set.is_empty reps_to_update |> not then
          Event.log L_warn
            "[graph splitting] @[<v>\
              Some classes were split during relation stabilization.@ \
              This should not be possible.\
            "
      ) ;
      (* Loop after adding new representatives (includes old one). *)
      update_rels sys known lsd (count + 1) graph

  (** Queries the lsd and updates the graph. Iterates until the graph is
  stable. That is, when the lsd returns unsat. *)
  let rec update_loop
    sys known lsd ({ map_up ; map_down } as graph)
  =

  (* Format.printf "%s check sat@.@." pref ; *)

  match
    terms_of graph known |> NLsd.query_base lsd
  with
  | None ->
    (* Format.printf "%s   unsat@.@." pref ; *)
    ()
  | Some model ->
    (* Format.printf "%s   sat@.@." pref ; *)
    (* Checking if we should terminate before doing anything. *)
    Event.check_termination () ;

    (* Event.log L_info "%s stabilization: check" pref ; *)

    (* Format.printf "@.sat, updating graph: %d@." out_cnt ; *)

    (* Clear (NOT RESET) the value map for update. *)
    clear graph ;
    
    (* Stabilize graph. *)
    split_of_model sys Set.empty model graph |> ignore ;

    (* Checking if we should terminate before looping. *)
    Event.check_termination () ;

    (* Check if new graph is stable. *)
    update_loop sys known lsd graph

  (** Queries the lsd and updates the graph. Iterates until the graph is
  stable. That is, when the lsd returns unsat. *)
  let update sys known lsd graph =
    (* update_loop sys known lsd graph *)
    update_classes sys known lsd graph ;
    (* Format.printf "done stabilizing classes@.@." ; *)
    update_rels sys known lsd 0 graph


  (** Queries step to identify invariants, prunes trivial ones away,
  communicates non-trivial ones and adds them to the transition system. *)
  let find_invariants
    blah two_state lsd sys_map top_sys sys pruner k f candidates
  =
    (* Format.printf "find_invariants (%d)@.@." (List.length candidates) ;
    Format.printf "  query_step@.@." ; *)
    let invs = NLsd.query_step two_state lsd candidates in
    
    (* Applying client function. *)
    let invs = f invs in

    (* Extracting non-trivial invariants. *)
    (* Format.printf "  pruning@.@." ; *)
    let (non_trivial, trivial) = NLsd.query_pruning pruner invs in

    (* Communicating and adding to trans sys. *)
    let top_level_inc, sanitized =
      communicate_and_add
        two_state top_sys sys_map sys k blah non_trivial trivial
    in
    
    (* Adding sanitized non-trivial to pruning checker. *)
    NLsd.pruning_add_invariants pruner sanitized ;
    (* Adding sanitized non-trivial to step checker. *)
    NLsd.step_add_invariants lsd sanitized ;

    non_trivial, trivial, top_level_inc

  let candidate_count = 200

  let rec take res count = function
  | head :: tail when count <= candidate_count ->
    take (head :: res) (count + 1) tail
  | rest -> res, rest

  let controlled_find_invariants
    blah two_state lsd sys_map top_sys sys pruner k f
  =
    let rec loop non_trivial trivial non_invs top_level_inc candidates =
      let candidates, postponed = take non_invs 1 candidates in
      (* Format.printf "find_invariants %d (%d postponed)@.@."
        (List.length candidates) (List.length postponed) ; *)
      let non_trivial', trivial', top_level_inc' =
        find_invariants
          blah two_state lsd sys_map top_sys sys pruner k f candidates
      in
      let non_invs =
        candidates |> List.fold_left (
          fun acc ((eq, _) as pair) ->
            if (
              List.memq eq non_trivial'
            ) || (
              List.memq eq trivial'
            ) then acc else pair :: acc
        ) []
      in
      let non_trivial, trivial, top_level_inc =
        List.rev_append non_trivial' non_trivial,
        List.rev_append trivial' trivial,
        top_level_inc + top_level_inc'
      in
      match postponed with
      | [] -> non_trivial, trivial, non_invs, top_level_inc
      | _ -> loop non_trivial trivial non_invs top_level_inc postponed
    in

    loop [] [] [] 0



  (** Goes through all the (sub)systems for the current [k]. Then loops
  after incrementing [k]. *)
  let rec system_iterator
    max_depth two_state
    input_sys param top_sys memory k sys_map top_level_count
  = function

  | (sys, graph, non_trivial, trivial) :: graphs ->
    let blah = if sys == top_sys then " (top)" else "" in
    Event.log_uncond
      "%s Running on %a%s at %a (%d candidate terms)"
      (prefs two_state) Scope.pp_print_scope (Sys.scope_of_trans_sys sys) blah
      Num.pp_print_numeral k (term_count graph) ;

    (* Receiving messages, don't care about new invariants for now as we
    haven't create the base/step checker yet. *)
    let _ = recv_and_update input_sys param top_sys sys_map sys in

    (* Retrieving pruning checker for this system. *)
    let pruning_checker =
      try SysMap.find sys_map sys with Not_found -> (
        Event.log L_fatal
          "%s could not find pruning checker for system [%s]"
          (prefs two_state) (sys_name sys) ;
        exit ()
      )
    in

    (* Creating base checker. *)
    let lsd = NLsd.mk_base_checker sys k in
    (* Memorizing LSD instance for clean exit. *)
    base_ref := Some lsd ;

    (* Format.printf "LSD instance is at %a@.@." Num.pp_print_numeral (Lsd.get_k lsd sys) ; *)

    (* Prunes known invariants from a list of candidates. *)
    let prune cand =
      Set.mem cand non_trivial || Set.mem cand trivial
    in
    let prune =
      if two_state then (
        fun cand -> prune cand ||  (
          match Term.var_offsets_of_term cand with
          | (Some _, Some hi) when Num.(hi = ~- one) -> true
          | _ -> false
        ) || (
          if max_depth = None then (
            match Term.var_offsets_of_term cand with
            | (Some lo, Some hi) when lo != hi -> false
            | _ -> true
          ) else false
        )
      ) else prune
    in

    (* Checking if we should terminate before doing anything. *)
    Event.check_termination () ;

    (* Format.printf "%s stabilizing graph...@.@." (prefs two_state) ; *)

    (* Stabilize graph. *)
    ( try update sys prune lsd graph with
      | Event.Terminate -> exit ()
      | e -> (
        Event.log L_fatal "caught exception %s" (Printexc.to_string e) ;
        minisleep 0.5 ;
        exit ()
      )
    ) ;
    (* write_dot_to
      "graphs/" "classes" (Format.asprintf "%a" Num.pp_print_numeral k)
      fmt_graph_classes_dot graph ; *)

    (* Format.printf "%s done stabilizing graph@.@." (prefs two_state) ; *)
    
    (* Event.log_uncond
      "%s Done stabilizing graph, checking consistency" (prefs two_state) ;
    check_graph graph ;
    Event.log_uncond "%s Done checking consistency" (prefs two_state) ; *)

    let lsd = NLsd.to_step lsd in
    base_ref := None ;
    step_ref := Some lsd ;

    (* Receiving messages. *)
    let new_invs_for_sys =
      recv_and_update input_sys param top_sys sys_map sys
    in
    NLsd.step_add_invariants lsd new_invs_for_sys ;

    (* Receiving messages. *)
    let new_invs_for_sys =
      recv_and_update input_sys param top_sys sys_map sys
    in
    NLsd.step_add_invariants lsd new_invs_for_sys ;

    (* Check class equivalence first. *)
    let equalities = equalities_of graph prune in
    (* Extract invariants. *)
    (* Format.printf "(equality) checking for invariants (%d)@.@." (List.length equalities) ; *)
    let non_trivial_eqs, trivial_eqs, non_inv_eqs, top_level_inc =
      controlled_find_invariants
        ( Format.asprintf
            "class equalities (%d candidates)"
            (List.length equalities)
        )
        two_state lsd sys_map top_sys sys pruning_checker k
        (List.map
          (fun (eq, (rep, term)) -> drop_class_member graph rep term ; eq)
        )
        equalities
    in

    (* Extract non invariant equality candidates to check with edges
    candidates. *)
    (* let non_inv_eqs =
      equalities |> List.fold_left (
        fun acc (eq, _) ->
          if (
            List.memq eq non_trivial_eqs
          ) || (
            List.memq eq trivial_eqs
          ) then acc else (eq, ()) :: acc
      ) []
    in *)

    (* Updating set of non-trivial invariants for this system. *)
    let non_trivial =
      non_trivial_eqs |> List.fold_left (
        fun non_trivial inv -> Set.add inv non_trivial
      ) non_trivial
    in

    (* Updating set of trivial invariants for this system. *)
    let trivial =
      trivial_eqs |> List.fold_left (
        fun trivial inv -> Set.add inv trivial
      ) trivial
    in

    let top_level_count = top_level_count + top_level_inc in

    (* Checking graph edges now. *)
    let relations =
      relations_of graph (List.map (fun (eq, _) -> eq, ()) non_inv_eqs) prune
    in
    (* Extracting invariants. *)
    (* Format.printf "(relations) checking for invariants@.@." ; *)
    let non_trivial_rels, trivial_rels, _, top_level_inc =
      controlled_find_invariants
        ( Format.asprintf
            "graph relations (%d candidates)"
            (List.length relations)
        )
        two_state lsd sys_map top_sys sys pruning_checker k
        (List.map fst)
        relations
    in

    (* Updating set of non-trivial invariants for this system. *)
    let non_trivial =
      non_trivial_rels |> List.fold_left (
        fun non_trivial inv -> Set.add inv non_trivial
      ) non_trivial
    in

    (* Updating set of trivial invariants for this system. *)
    let trivial =
      trivial_rels |> List.fold_left (
        fun trivial inv -> Set.add inv trivial
      ) trivial
    in

    (* Not adding to lsd, we won't use it anymore. *)
    (* Destroying LSD. *)
    NLsd.kill_step lsd ;
    (* Unmemorizing LSD instance. *)
    step_ref := None ;

    let top_level_count = top_level_count + top_level_inc in


    (* Format.printf "%s non_trivial: @[<v>%a@]@.@."
      pref (pp_print_list fmt_term "@ ") (Set.elements non_trivial) ;

    Format.printf "%s trivial: @[<v>%a@]@.@."
      pref (pp_print_list fmt_term "@ ") (Set.elements trivial) ; *)

    (* write_dot_to "." "graph" "blah" fmt_graph_dot graph ;
    write_dot_to "." "classes" "blah" fmt_graph_classes_dot graph ; *)
    (* minisleep 2.0 ;
    exit () ; *)

    (* Looping. *)
    system_iterator
      max_depth two_state input_sys param top_sys (
        (sys, graph, non_trivial, trivial) :: memory
      ) k sys_map top_level_count graphs

  | [] ->
    (* Done for all systems for this k, incrementing. *)
    let k = Num.succ k in
    match max_depth with
    | Some kay when Num.(k > kay) ->
      Event.log_uncond "%s Reached max depth (%a), stopping."
        (prefs two_state) Num.pp_print_numeral kay ;
        memory |> List.map (fun (sys, _, nt, t) -> sys, nt, t)
    | _ ->
      (* Format.printf
        "%s Looking for invariants at %a (%d)@.@."
        (prefs two_state) Num.pp_print_numeral k
        (List.length memory) ; *)
      List.rev memory
      |> system_iterator
        max_depth two_state
        input_sys param top_sys [] k sys_map top_level_count


  (** Invariant generation entry point. *)
  let main max_depth top_only modular two_state input_sys aparam sys =

    (* Format.printf "Starting@.@." ; *)

    (* Initial [k]. *)
    let k = if two_state then Num.one else Num.zero in

    (* Maps systems to their pruning solver. *)
    let sys_map = SysMap.create 107 in

    (* Generating the candidate terms and building the graphs. Result is a list
    of quadruples: system, graph, non-trivial invariants, trivial
    invariants. *)
    Value.mine top_only aparam two_state sys |> List.fold_left (
      fun acc (sub_sys, set) ->
        let set = Set.add Term.t_true set in
        (* Format.printf "%s candidates: @[<v>%a@]@.@."
          pref (pp_print_list fmt_term "@ ") (Set.elements set) ; *)
        let pruning_checker = NLsd.mk_pruning_checker sub_sys in
        (* Memorizing pruning checker for clean exit. *)
        prune_ref := pruning_checker :: (! prune_ref ) ;
        SysMap.replace sys_map sub_sys pruning_checker ;
        (
          sub_sys,
          mk_graph Term.t_false set,
          Set.empty,
          Set.empty
        ) :: acc
    ) []
    |> (
      if modular then 
        (* If in modular mode, we already ran on the subsystems.
        Might as well start with the current top system since it's new. *)
        List.rev
      else identity
    )
    |> fun syss ->
      (* Format.printf "Running on %d systems@.@." (List.length syss) ; *)
      syss
    |> system_iterator max_depth two_state input_sys aparam sys [] k sys_map 0

end




(* |===| Actual invariant generators. *)


module Bool: In = struct
  (* Evaluates a term to a boolean. *)
  let eval_bool sys model term =
    Eval.eval_term (Sys.uf_defs sys) model term
    |> Eval.bool_of_value

  let name = "Bool"
  type t = bool
  let fmt = Format.pp_print_bool
  let eq lhs rhs = lhs = rhs
  let cmp lhs rhs = rhs || not lhs
  let mk_cmp lhs rhs = Term.mk_implies [ lhs ; rhs ]
  let eval = eval_bool
  let mine top_only param two_state sys =
    Sys.fold_subsystems
      ~include_top:true
      (fun acc sub_sys ->
        let shall_add =
          (sub_sys == sys) || (
            (not top_only) && (
              TransSys.scope_of_trans_sys sub_sys
              |> Analysis.param_scope_is_abstract param
              |> not
            )
          )
        in
        if shall_add then
          (
            sub_sys,
            InvGenCandTermGen.mine_term
              true (* Synthesis. *)
              true (* Mine base. *)
              true (* Mine step. *)
              two_state (* Two step.  *)
              sub_sys
              []
              Term.TermSet.empty
          ) :: acc
        else acc
      )
      []
      sys
    (* InvGenCandTermGen.generate_candidate_terms
      (Flags.Invgen.two_state ()) sys sys
    |> fst *)
  let is_bot term = term = Term.t_false
  let is_top term = term = Term.t_true
end

(** Boolean invariant generation. *)
module BoolInvGen = Make(Bool)


module Integer: In = struct
  (* Evaluates a term to a numeral. *)
  let eval_int sys model term =
    Eval.eval_term (Sys.uf_defs sys) model term
    |> Eval.num_of_value

  let name = "Int"
  type t = Num.t
  let fmt = Num.pp_print_numeral
  let eq = Num.equal
  let cmp = Num.leq
  let mk_cmp lhs rhs = Term.mk_leq [ lhs ; rhs ]
  let eval = eval_int
  let mine _ _ _ _ =
    failwith "integer candidate term mining is unimplemented"
  let is_bot _ = false
  let is_top _ = false
end

(** Integer invariant generation. *)
module IntInvGen = Make(Integer)


module Real: In = struct
  (* Evaluates a term to a decimal. *)
  let eval_real sys model term =
    Eval.eval_term (Sys.uf_defs sys) model term
    |> Eval.dec_of_value

  let name = "Real"
  type t = Decimal.t
  let fmt = Decimal.pp_print_decimal
  let eq = Decimal.equal
  let cmp = Decimal.leq
  let mk_cmp lhs rhs = Term.mk_leq [ lhs ; rhs ]
  let eval = eval_real
  let mine _ _ _ _ =
    failwith "real candidate term mining is unimplemented"
  let is_bot _ = false
  let is_top _ = false
end

(** Real invariant generation. *)
module RealInvGen = Make(Real)





let main two_state in_sys param sys =
  BoolInvGen.main None (Flags.Invgen.top_only ()) (Flags.modular () |> not) two_state in_sys param sys
  |> ignore
let exit _ = BoolInvGen.exit ()




(* 
   Local Variables:
   compile-command: "make -C .. -k"
   tuareg-interactive-program: "./kind2.top -I ./_build -I ./_build/SExpr"
   indent-tabs-mode: nil
   End: 
*)