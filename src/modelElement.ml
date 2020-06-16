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

module TS = TransSys
module SMT  : SolverDriver.S = GenericSMTLIBDriver

module SyMap = UfSymbol.UfSymbolMap
module SySet = UfSymbol.UfSymbolSet
module ScMap = Scope.Map
module ScSet = Scope.Set
module SVSet = StateVar.StateVarSet
module SVMap = StateVar.StateVarMap
module SVSMap = Map.Make(SVSet)

module Position = struct
  type t = Lib.position
  let compare = Lib.compare_pos
end
module PosMap = Map.Make(Position)
module PosSet = Set.Make(Position)

module A = LustreAst
module AstID = struct
  type t = A.ident
  let compare = compare
end
module IdMap = Map.Make(AstID)

(* Represents an equation of the transition system.
   It is not specific to the 'equation' model elements
   of the source lustre program
   (any model element can be represented by this 'equation' type) *)
type ts_equation = {
  init_opened: Term.t ;
  init_closed: Term.t ;
  trans_opened: Term.t ;
  trans_closed: Term.t ;
}

type core = UfSymbol.t ScMap.t * (ts_equation * StateVar.t) SyMap.t

module Equation = struct
  type t = ts_equation
  let compare t1 t2 =
    match Term.compare t1.trans_opened t2.trans_opened with
    | 0 -> Term.compare t1.init_opened t2.init_opened
    | n -> n
  let equal t1 t2 = compare t1 t2 = 0
end
module EqMap = Map.Make(Equation)
module EqSet = Set.Make(Equation)

let scmap_size c =
  ScMap.fold (fun _ lst acc -> acc + (List.length lst)) c 0

(* ---------- PRETTY PRINTING ---------- *)

let aux_vars sys =
  let usr_name =
    assert (List.length LustreIdent.user_scope = 1) ;
    List.hd LustreIdent.user_scope
  in
  List.filter
    (fun sv ->
      not ( List.mem usr_name (StateVar.scope_of_state_var sv) )
    )
    (TS.state_vars sys)

let compute_var_map in_sys sys =
  let aux_vars = TS.fold_subsystems ~include_top:true (fun acc sys -> (aux_vars sys)@acc) [] sys in
  InputSystem.mk_state_var_to_lustre_name_map in_sys aux_vars

let lustre_name_of_sv var_map sv =
  let usr_name =
    assert (List.length LustreIdent.user_scope = 1) ;
    List.hd LustreIdent.user_scope
  in
  if List.mem usr_name (StateVar.scope_of_state_var sv)
  then StateVar.name_of_state_var sv
  else StateVar.StateVarMap.find sv var_map

type term_print_data = {
  name: string ;
  category: string ;
  position: Lib.position ;
}

type core_print_data = {
  core_class: string ;
  property: string option ; (* Only for MCSs *)
  counterexample: ((StateVar.t * Model.value list) list) option ; (* Only for MCSs *)
  time: float option ;
  size: int ;
  elements: term_print_data list ScMap.t ;
}

let pp_print_locs_short =
  Lib.pp_print_list (
    fun fmt {pos} ->
      Format.fprintf fmt "%a" Lib.pp_print_pos pos
  ) ""

(* The last position is the main one (the first one added) *)
let last_position_of_locs locs =
  (List.hd (List.rev locs)).pos

let print_data_of_loc_equation var_map (eq, locs, cat) =
  if locs = []
  then None
  else
    match cat with
    | Unknown -> None
    | NodeCall (name, _) ->
      Some {
        name = name ;
        category = "Node Call" ;
        position = last_position_of_locs locs ;
      }
    | Equation sv ->
      (
        try
          Some {
            name = lustre_name_of_sv var_map sv ;
            category = "Equation" ;
            position = last_position_of_locs locs ;
          }
        with Not_found -> None
      )
    | Assertion sv ->
      Some {
        name = Format.asprintf "assertion%a" pp_print_locs_short locs ;
        category = "Assertion" ;
        position = last_position_of_locs locs ;
      }
    | ContractItem (_, svar, typ) ->
      let (kind, category) = 
        match typ with
        | LustreNode.WeakAssumption -> ("weakly_assume", "Assumption")
        | LustreNode.WeakGuarantee -> ("weakly_guarantee", "Guarantee")
        | LustreNode.Assumption -> ("assume", "Assumption")
        | LustreNode.Guarantee -> ("guarantee", "Guarantee")
        | LustreNode.Require -> ("require", "Require")
        | LustreNode.Ensure -> ("ensure", "Ensure")
      in
      Some {
        name = LustreContract.prop_name_of_svar svar kind "" ;
        category ;
        position = last_position_of_locs locs ;
      }

let printable_elements_of_core in_sys sys core =
  let var_map = compute_var_map in_sys sys in
  let aux lst =
    lst
    |> List.map (print_data_of_loc_equation var_map)
    |> List.filter (function Some _ -> true | None -> false)
    |> List.map (function Some x -> x | None -> assert false)
  in
  core
  |> ScMap.map aux (* Build map *)
  |> ScMap.filter (fun _ lst -> lst <> []) (* Remove empty entries *)

let loc_core_to_print_data in_sys sys core_class time lc =
  let elements = printable_elements_of_core in_sys sys lc in
  {
    core_class ;
    property = None ;
    counterexample = None ;
    time ;
    elements ;
    size = scmap_size elements ;
  }

let attach_counterexample_to_print_data data cex =
  { data with counterexample = Some cex }

let attach_property_to_print_data data prop =
  { data with property = Some property.Property.prop_name }

let print_mcs_counterexample in_sys param sys typ fmt (prop, cex) =
  try
    if Flags.MCS.print_mcs_counterexample ()
    then
      match typ with
      | `PT ->
        KEvent.pp_print_counterexample_pt L_warn in_sys param sys prop true fmt cex
      | `XML ->
        KEvent.pp_print_counterexample_xml in_sys param sys prop true fmt cex
      | `JSON ->
        KEvent.pp_print_counterexample_json in_sys param sys prop true fmt cex
  with _ -> ()

let format_name_for_pt str =
  String.capitalize_ascii (String.lowercase_ascii str)

let format_name_for_json_xml = Str.global_replace (Str.regexp " ") ""

let pp_print_core_data in_sys param sys fmt cpd =
  let print_elt elt =
    Format.fprintf fmt "%s @{<blue_b>%s@} at position %a@ "
      (format_name_for_pt elt.category) elt.name
      Lib.pp_print_pos elt.position
  in
  let print_node scope lst =
    Format.fprintf fmt "@{<b>Node@} @{<blue>%s@}@ " (Scope.to_string scope) ;
    Format.fprintf fmt "  @[<v>" ;
    List.iter print_elt lst ;
    Format.fprintf fmt "@]@ "
  in
  (match cpd.property with
  | None -> Format.fprintf fmt "@{<b>%s (%i elements):@}@."
    (String.uppercase_ascii cpd.core_class) cpd.size
  | Some n -> Format.fprintf fmt "@{<b>%s (%i elements)@} for property @{<blue_b>%s@}:@."
    (String.uppercase_ascii cpd.core_class) cpd.size n
  ) ;
  Format.fprintf fmt "  @[<v>" ;
  ScMap.iter print_node cpd.elements ;
  (match cpd.counterexample, cpd.property with
  | Some cex, Some p ->
    print_mcs_counterexample in_sys param sys `PT fmt (p,cex)
  | _, _ -> ()
  ) ;
  Format.fprintf fmt "@]@."

let pp_print_json fmt json =
  Yojson.Basic.pretty_to_string json
  |> Format.fprintf fmt "%s"

let pp_print_core_data_json in_sys param sys fmt cpd =
  let json_of_elt elt =
    let (file, row, col) = Lib.file_row_col_of_pos elt.position in
    `Assoc ([
      ("category", `String (format_name_for_json_xml elt.category)) ;
      ("name", `String elt.name) ;
      ("line", `Int row) ;
      ("column", `Int col) ;
    ] @
    (if file = "" then [] else [("file", `String file)])
    )
  in
  let assoc = [
    ("objectType", `String "modelElementSet") ;
    ("class", `String cpd.core_class) ;
    ("size", `Int cpd.size) ;
  ] in
  let assoc = assoc @ (
    match cpd.property with
    | None -> []
    | Some n -> [("property", `String n)]
  )
  in
  let assoc = assoc @ (
    match cpd.time with
    | None -> []
    | Some f -> [("runtime", `Assoc [("unit", `String "sec") ; ("value", `Float f)])]
  )
  in
  let assoc = assoc @ ([
    ("nodes", `List (List.map (fun (scope, elts) ->
      `Assoc [
        ("name", `String (Scope.to_string scope)) ;
        ("elements", `List (List.map json_of_elt elts))
      ]
    ) (ScMap.bindings cpd.elements)))
  ])
  in
  let assoc = assoc @
    (match cpd.counterexample, cpd.property with
    | Some cex, Some p ->
      let str = Format.asprintf "%a"
        (print_mcs_counterexample in_sys param sys `JSON) (p, cex) in
      if String.equal str "" then []
      else (
          match Yojson.Basic.from_string ("{"^str^"}") with
          | `Assoc json -> json
          | _ -> assert false
      )
    | _, _ -> []
    )
  in
  pp_print_json fmt (`Assoc assoc)

let pp_print_core_data_xml in_sys param sys fmt cpd =
  let fst = ref true in
  let print_node scope elts =
    if not !fst then Format.fprintf fmt "@ " else fst := false ;
    let fst = ref true in
    let print_elt elt =
      if not !fst then Format.fprintf fmt "@ " else fst := false ;
      let (file, row, col) = Lib.file_row_col_of_pos elt.position in
      Format.fprintf fmt "<Element category=\"%s\" name=\"%s\" line=\"%i\" column=\"%i\"%s>"
        (format_name_for_json_xml elt.category) elt.name row col (if file = "" then "" else Format.asprintf " file=\"%s\"" file)
    in
    Format.fprintf fmt "<Node name=\"%s\">@   @[<v>" (Scope.to_string scope) ;
    List.iter print_elt elts ;
    Format.fprintf fmt "@]@ </Node>"
  in
  Format.fprintf fmt "<ModelElementSet class=\"%s\" size=\"%i\"%s>@.  @[<v>"
    cpd.core_class cpd.size
    (match cpd.property with None -> "" | Some n -> Format.asprintf " property=\"%s\"" n) ;
  (
    match cpd.time with
    | None -> ()
    | Some f -> Format.fprintf fmt "<Runtime unit=\"sec\">%.3f</Runtime>@ " f
  ) ;
  ScMap.iter print_node cpd.elements ;
  (
    match cpd.counterexample, cpd.property with
    | Some cex, Some p ->
      Format.fprintf fmt "@ " ;
      print_mcs_counterexample in_sys param sys `XML fmt (p, cex)
    | _, _ -> ()
  ) ;
  Format.fprintf fmt "@]@.</ModelElementSet>@."

let name_of_wa_cat = function
  | ContractItem (_, svar, LustreNode.WeakAssumption) ->
    Some (LustreContract.prop_name_of_svar svar "weakly_assume" "")
  | ContractItem (_, svar, LustreNode.WeakGuarantee) ->
    Some (LustreContract.prop_name_of_svar svar "weakly_guarantee" "")
  | _ -> None

let all_wa_names_of_mcs scmap =
  ScMap.fold
  (fun _ lst acc ->
    List.fold_left (fun acc (_,_,cat) ->
      match name_of_wa_cat cat with
      | None -> acc
      | Some str -> str::acc
    ) acc lst
  )
  scmap []

let pp_print_mcs_legacy in_sys param sys ((prop, cex), mcs) (_, mcs_compl) =
  let prop_name = prop.Property.prop_name in
  let sys = TS.copy sys in
  let wa_model =
    all_wa_names_of_mcs mcs_compl
    |>  List.map (fun str -> (str, true))
  in
  let wa_model' =
      all_wa_names_of_mcs mcs
    |>  List.map (fun str -> (str, false))
  in
  TS.set_prop_unknown sys prop_name ;
  let wa_model = wa_model@wa_model' in
  KEvent.cex_wam cex wa_model in_sys param sys prop_name

(* ---------- CORES ---------- *)

let actsvs_counter =
  let last = ref 0 in
  (fun () -> last := !last + 1 ; !last)

let fresh_actsv_name () =
  Printf.sprintf "__model_elt_%i" (actsvs_counter ())

let term_of_ts_eq ~init ~closed eq =
  if init && closed then eq.init_closed
  else if init then eq.init_opened
  else if closed then eq.trans_closed
  else eq.trans_opened

let empty_core = (ScMap.empty, SyMap.empty)

let get_actlits_of_scope (scmap, _) scope =
  try ScMap.find scope scmap with Not_found -> []

let get_ts_equation_of_actlit (_, mapping) actlit =
  SyMap.find actlit mapping |> fst

let get_sv_of_actlit (_, mapping) actlit =
  SyMap.find actlit mapping |> snd

let get_actlit_of_sv (_, mapping) sv =
  SyMap.bindings mapping
  |> List.filter (fun (a, (_, sv')) -> StateVar.equal_state_vars sv sv')
  |> List.hd |> fst

let core_size (scmap, _) = scmap_size scmap

let scopes_of_core (scmap, _) =
  ScMap.bindings scmap |> List.map fst

let pick_element_of_core (scmap, mapping) =
  let scmap = ScMap.filter (fun _ lst -> lst <> []) scmap in
  match ScMap.bindings scmap with
  | [] -> None
  | (scope, lst)::_ ->
    Some (scope, List.hd lst, (ScMap.add scope (List.tl lst) scmap, mapping))

  match lst with
  | [] -> assert false
  | hd::lst -> 

let add_new_ts_equation_to_core scope eq ((scmap, mapping) as core) =
  let actlit = Actlit.fresh_actlit () in
  let actlits = actlit::(get_actlits_for_scope core scope) in
  let sv = StateVar.mk_state_var ~is_input:false ~is_const:true
        (fresh_actsv_name ()) [] (Type.mk_bool ()) in
  (ScMap.add scope actlits scmap, SyMap.add actlit (eq, sv) mapping)

let add_from_other_core
  (_, src_mapping) scope actlit ((scmap, mapping) as core) =
  let actlits = get_actlits_for_scope core scope in
  if List.exists (fun a -> UfSymbol.equal_uf_symbols a actlit) actlits
  then core
  else (
    let mapping = SyMap.add actlit (SyMap.find actlit src_mapping) mapping in
    ScMap.add scope (actlit::actlits) scmap, mapping
  )

let sy_union sy1 sy2 =
  SySet.union (SySet.of_list sy1) (SySet.of_list sy2)
  |> SySet.elements

let sy_inter sy1 sy2 =
  SySet.inter (SySet.of_list sy1) (SySet.of_list sy2)
  |> SySet.elements

let sy_diff sy1 sy2 =
  SySet.diff (SySet.of_list sy1) (SySet.of_list sy2)
  |> SySet.elements

let remove_from_core actlit ((scmap, mapping) as core) =
  (ScMap.map (fun actlits -> sy_diff actlits [actlit]) scmap, mapping)

let filter_core actlits ((scmap, mapping) as core) =
  (ScMap.map (fun actlits' -> sy_inter actlits actlits') scmap, mapping)

let filter_core_svs state_vars ((scmap, mapping) as core) =
  let svs = StateVarSet.of_list state_vars in
  let aux actlits =
    List.filter
      (fun a -> StateVarSet.mem (get_sv_of_actlit a) svs)
      actlits
  in
  (ScMap.map aux scmap, mapping)

let core_union (scmap1, mapping1) (scmap2, mapping2) =
  let merge _ eq1 eq2 = match eq1, eq2 with
  | None, None -> None
  | Some e, _ | None, Some e -> Some e
  in
  let mapping = SyMap.merge merge mapping1 mapping2 in
  let merge _ lst1 lst2 = match lst1, lst2 with
  | None, None -> None
  | Some lst, None | None, Some lst -> Some lst
  | Some lst1, Some lst2 -> Some (sy_union lst1 lst2)
  in
  let scmap = ScMap.merge merge scmap1 scmap2 in
  (scmap, mapping)

let core_diff (scmap1, mapping) (scmap2, _) =
  let merge _ lst1 lst2 = match lst1, lst2 with
  | None, _ -> None
  | Some lst, None -> Some lst
  | Some lst1, Some lst2 -> Some (sy_diff lst1 lst2)
  in
  let scmap = ScMap.merge merge scmap1 scmap2 in
  (scmap, mapping)


type eqmap = (equation list) ScMap.t

let core_to_eqmap (scmap, mapping) =
  ScMap.map (fun actlit -> SyMap.find actlit mapping |> fst) scmap

(* ---------- MAPPING BACK ---------- *)

type term_cat =
| NodeCall of string * SVSet.t
| ContractItem of StateVar.t * LustreContract.svar * LustreNode.contract_item_type
| Equation of StateVar.t
| Assertion of StateVar.t
| Unknown

type loc = {
  pos: Lib.position ;
  index: LustreIndex.index ;
}

type model_element = ts_equation * (loc list) * term_cat

type loc_core = model_element list ScMap.t

let equal_model_elements (eq1, _, _) (eq2, _, _) =
  Term.equal eq1.trans_closed eq2.trans_closed
  && Term.equal eq1.init_closed eq2.init_closed

let get_model_elements_of_scope core scope =
  try ScMap.find scope core with Not_found -> []

let loc_core_size = scmap_size

let scopes_of_loc_core core =
  ScMap.bindings core |> List.map fst

let normalize_positions lst =
  List.sort_uniq Lib.compare_pos lst

let get_positions_of_model_element (_,locs,_) =
  List.map (fun loc -> loc.pos) locs |> normalize_positions

let locs_of_node_call in_sys output_svs =
  output_svs
  |> SVSet.elements
  |> List.map (fun sv ->
      InputSystem.lustre_definitions_of_state_var in_sys sv
      |> List.filter (function LustreNode.CallOutput _ -> true | _ -> false)
      |> List.map
        (fun d -> { pos=LustreNode.pos_of_state_var_def d ;
                    index=[](*LustreNode.index_of_state_var_def d*) })
  )
  |> List.flatten

let rec sublist i count lst =
  match i, count, lst with
  | _, 0, _ -> []
  | _, _, [] -> assert false
  | 0, k, hd::lst -> hd::(sublist 0 (k-1) lst)
  | i, k, _::lst -> sublist (i-1) k lst

let name_and_svs_of_node_call in_sys s args =
  (* Retrieve name of node *)
  let regexp = Printf.sprintf "^\\(%s\\|%s\\)_\\(.+\\)_[0-9]+$"
    Lib.ReservedIds.init_uf_string Lib.ReservedIds.trans_uf_string
    |> Str.regexp in
  let name = Symbol.string_of_symbol s in
  let name =
    if Str.string_match regexp name 0 
    then Str.matched_group 2 name
    else name
  in
  (* Retrieve number of inputs/outputs *)
  let node = InputSystem.find_lustre_node (Scope.mk_scope [Ident.of_string name]) in_sys in
  let nb_inputs = LustreIndex.cardinal (node.LustreNode.inputs) in
  let nb_oracles = List.length (node.LustreNode.oracles) in
  let nb_outputs = LustreIndex.cardinal (node.LustreNode.outputs) in
  (* Retrieve output statevars *)
  let svs = sublist (nb_inputs+nb_oracles) nb_outputs args
  |> List.map (fun t -> match Term.destruct t with
    | Var v -> Var.state_var_of_state_var_instance v
    | _ -> assert false
  )
  in
  (name, (*List.sort_uniq StateVar.compare_state_vars*)SVSet.of_list svs)

(* The order matters, for this reason we can't use Term.state_vars_of_term *)
let rec find_vars t =
  match Term.destruct t with
  | Var v -> [v]
  | Const _ -> []
  | App (_, lst) ->
    List.map find_vars lst
    |> List.flatten
  | Attr (t, _) -> find_vars t

let sv_of_term t =
  find_vars t |> List.hd |> Var.state_var_of_state_var_instance

let locs_of_eq_term in_sys t =
  try
    let contract_typ = ref LustreNode.Assumption in
    let contract_items = ref None in
    let set_contract_item svar = contract_items := Some svar in
    let has_asserts = ref false in
    let sv = sv_of_term t in
    InputSystem.lustre_definitions_of_state_var in_sys sv
    |> List.filter (function LustreNode.CallOutput _ -> false | _ -> true)
    |> List.map (fun def ->
      ( match def with
        | LustreNode.Assertion _ -> has_asserts := true
        | LustreNode.ContractItem (_, svar, typ) -> contract_typ := typ ; set_contract_item svar
        | _ -> ()
      );
      let p = LustreNode.pos_of_state_var_def def in
      let i = LustreNode.index_of_state_var_def def in
      { pos=p ; index=i }
    )
    |> (fun locs ->
      match !contract_items with
      | Some svar -> (ContractItem (sv, svar, !contract_typ), locs)
      | None ->
        if !has_asserts then (Assertion sv, locs)
        else (Equation sv, locs)
    )
  with _ -> assert false

let compare_loc {pos=pos;index=index} {pos=pos';index=index'} =
  match Lib.compare_pos pos pos' with
  | 0 -> LustreIndex.compare_indexes index index'
  | n -> n

let normalize_loc lst =
  List.sort_uniq compare_loc lst

let add_loc in_sys eq =
  try
    let term = eq.trans_closed in
    begin match Term.destruct term with
    | Term.T.App (s, ts) when
      (match (Symbol.node_of_symbol s) with `UF _ -> true | _ -> false)
      -> (* Case of a node call *)
      let (name, svs) = name_and_svs_of_node_call in_sys s ts in
      let loc = locs_of_node_call in_sys svs in
      (eq, normalize_loc loc, NodeCall (name,svs))
    | _ ->
      let (cat,loc) = locs_of_eq_term in_sys term in
      (eq, normalize_loc loc, cat)
    end
  with _ -> (* If the input is not a Lustre file, it may fail *)
    (eq, [], Unknown)

let ts_equation_to_model_element = add_loc

let core_to_loc_core in_sys core =
  core_to_eqmap core
  |> ScMap.map (List.map (add_loc in_sys))

let loc_core_to_new_core in_sys loc_core =
  let add_eqs_of_scope scope lst acc =
    List.fold_left
      (fun acc (eq, _, _) -> add_new_ts_equation_to_core scope eq acc)
      acc lst
  in
  ScMap.fold add_eqs_of_scope loc_core empty_core

let empty_loc_core = ScMap.empty

let add_to_loc_core ?(check_already_exists=false) scope elt core =
  let elts = get_model_elements_of_scope core scope in
  if check_already_exists && List.exists (fun e -> equal_model_elements e elt) elts
  then core
  else ScMap.add scope (elt::elts) core

let remove_from_loc_core scope elt core =
  let elts = get_model_elements_of_scope core scope in
  let elts = List.filter (fun e -> equal_model_elements e elt |> not) elts in
  (ScMap.add scope elts core, mapping)

let loc_core_diff core1 core2 =
  ScMap.mapi (fun scope elts ->
    List.filter (fun elt ->
        get_model_elements_of_scope scope core2
        |> List.exists (fun e -> equal_model_elements e elt)
        |> not
      ) elts
  ) core1


let is_model_element_in_categories (_,_,cat) is_main_node cats =
  let cat = match cat with
  | NodeCall _ -> [`NODE_CALL]
  | ContractItem (_, _, LustreNode.WeakAssumption) when is_main_node
  -> [`ANNOTATIONS ; `CONTRACT_ITEM]
  | ContractItem (_, _, LustreNode.WeakGuarantee) when not is_main_node
  -> [`ANNOTATIONS ; `CONTRACT_ITEM]
  | ContractItem (_, _, LustreNode.Assumption) when is_main_node
  -> [`CONTRACT_ITEM]
  | ContractItem (_, _, LustreNode.Guarantee) when not is_main_node
  -> [`CONTRACT_ITEM]
  | ContractItem (_, _, _) -> []
  | Equation _ -> [`EQUATION]
  | Assertion _ -> [`ASSERTION]
  | Unknown -> [(*`UNKNOWN*)]
  in
  List.exists (fun cat -> List.mem cat cats) cat


(* Identify the provenance of a term.
   A 'trans' term and its corresponding 'init' term should have the same TermId. *)
type term_id = SVSet.t * bool (* Is node call *)
module TermId = struct
  type t = term_id
  let is_empty (k,_) = SVSet.is_empty k
  let compare (a,b) (a',b') =
    match compare b b' with
    | 0 -> SVSet.compare a a'
    | n -> n
end
module TIdMap = Map.Make(TermId)

let id_of_term in_sys t =
  match Term.destruct t with
  | Term.T.App (s, ts) when
    (match (Symbol.node_of_symbol s) with `UF _ -> true | _ -> false)
    -> (* Case of a node call *)
    let (_, svs) = name_and_svs_of_node_call in_sys s ts in
    (svs, true)
  | _ ->
    try (SVSet.singleton (sv_of_term t), false)
    with _ -> (SVSet.empty, false)

exception InitTransMismatch of int * int

let rec deconstruct_conj t =
  match Term.destruct t with
  | Term.T.App (s_and, ts) when Symbol.equal_symbols s_and Symbol.s_and ->
    List.map deconstruct_conj ts |> List.flatten
  | _ -> [t]

let extract_toplevel_equations in_sys sys =
  let (_,oinit,otrans) = TS.init_trans_open sys in
  let cinit = TS.init_of_bound None sys Numeral.zero
  and ctrans = TS.trans_of_bound None sys Numeral.zero in
  let oinit = deconstruct_conj oinit
  and otrans = deconstruct_conj otrans
  and cinit = deconstruct_conj cinit
  and ctrans = deconstruct_conj ctrans in
  let init = List.combine oinit cinit
  and trans = List.combine otrans ctrans in

  let mk_map = List.fold_left (fun acc (o,c) ->
    let tid = id_of_term in_sys c in
    if TermId.is_empty tid then acc
    else
      let (o,c) =
        try
          let (o',c') = TIdMap.find tid acc in
          (Term.mk_and [o;o'], Term.mk_and [c;c'])
        with Not_found -> (o,c) in
      TIdMap.add tid (o,c) acc
  ) TIdMap.empty
  in
  let init_bindings = mk_map init |> TIdMap.bindings
  and trans_bindings = mk_map trans |> TIdMap.bindings in
  let init_n = List.length init_bindings
  and trans_n = List.length trans_bindings in
  if init_n <> trans_n then raise (InitTransMismatch (init_n, trans_n)) ;
  List.map2 (fun (ki,(oi,ci)) (kt,(ot,ct)) ->
    if TermId.compare ki kt <> 0
    then raise (InitTransMismatch (init_n, trans_n)) ;
    { init_opened=oi ; init_closed=ci ; trans_opened=ot ; trans_closed=ct }
  ) init_bindings trans_bindings

let full_loc_core_for_sys in_sys sys ~only_top_level =
  let treat_subnode acc sys =
    let scope = TS.scope scope_of_trans_sys sys in
    extract_toplevel_equations in_sys sys
    |> List.map (ts_equation_to_model_element in_sys)
    |> List.fold_left (fun acc elt -> add_to_loc_core scope elt acc) acc
  in
  let res = treat_subnode empty_loc_core sys in
  if only_top_level then res
  else TS.fold_subsystems ~include_top:false treat_subnode res sys

let filter_loc_core_by_categories main_scope cats loc_core =
  let ok =
    ScMap.mapi (fun scope elts ->
      let main = Scope.equal scope main_scope in
      List.filter
        (fun elt -> is_model_element_in_categories elt main cats)
        elts
    ) loc_core in
  let not_ok =
    ScMap.mapi (fun scope elts ->
      let main = Scope.equal scope main_scope in
      List.filter
        (fun elt -> is_model_element_in_categories elt main cats |> not)
        elts
    ) loc_core in
  (ok, not_ok)
