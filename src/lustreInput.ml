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

module A = LustreAst
module I = LustreIdent

(* Parse from input channel *)
let of_channel in_ch = 

  (* Create lexing buffer *)
  let lexbuf = Lexing.from_function LustreLexer.read_from_lexbuf_stack in

  (* Initialize lexing buffer with channel *)
  LustreLexer.lexbuf_init in_ch (Filename.dirname (Flags.input_file ()));

  (* Lustre file is a list of declarations *)
  let declarations = 

    try 

      (* Parse file to list of declarations *)
      LustreParser.main LustreLexer.token lexbuf 

    with 

      | LustreParser.Error ->

        let lexer_pos = 
          Lexing.lexeme_start_p lexbuf 
        in

        LustreSimplify.fail_at_position
          (A.position_of_lexing lexer_pos)
          "Syntax error"

  in

  (* Simplify declarations to a list of nodes *)
  let nodes = LustreSimplify.declarations_to_nodes declarations in
  
  (* Find main node by annotation *)
  let main_node = 

    match Flags.lustre_main () with 

      | None -> 

        (try 
          
          LustreNode.find_main nodes 
            
        with Not_found -> 
          
          raise (Invalid_argument "No main node defined in input"))

      | Some s -> LustreIdent.mk_string_ident s

  in

  debug lustreInput
    "@[<v>Before slicing@,%a@]"
    (pp_print_list (LustreNode.pp_print_node false) "@,") nodes
  in

  (* Consider only nodes called by main node *)
  let nodes_coi = 
    LustreNode.reduce_to_property_coi nodes main_node
  in

  debug lustreInput
    "@[<v>After slicing@,%a@]"
    (pp_print_list (LustreNode.pp_print_node false) "@,") nodes_coi
  in

  (* Create transition system of Lustre nodes

     TODO: Split definitions into init and trans part *)
  let fun_defs_init, fun_defs_trans, state_vars, init, trans = 
    LustreTransSys.trans_sys_of_nodes main_node nodes_coi
  in

  (* Extract properties from nodes *)
  let props = 
    LustreTransSys.props_of_nodes main_node nodes_coi
  in
  

  (* Create Kind transition system *)
  let trans_sys = 
    TransSys.mk_trans_sys 
      fun_defs_init
      fun_defs_trans
      state_vars
      init
      trans
      props
      (TransSys.LustreInput nodes_coi)
  in

  (debug lustreInput 
      "%a"
      TransSys.pp_print_trans_sys trans_sys
   in

   debug lustreInput 
      "@[<v>%a@]"
      (pp_print_list
         (fun ppf sv -> 
            Format.fprintf ppf
              "@[<h>%a: %a@]"
              StateVar.pp_print_state_var sv
              LustreExpr.pp_print_state_var_source 
              (LustreExpr.get_state_var_source sv))
         "@,")
      state_vars
   in

   Event.log
     Event.L_info
     "Lustre main node is %a"
     (I.pp_print_ident false) main_node;

(*
  Format.printf 
    "%a@."
    (pp_print_list 
       (fun ppf state_var -> 
          Format.fprintf ppf "%a=%a"
            StateVar.pp_print_state_var state_var
            LustreExpr.pp_print_state_var_source 
            (LustreExpr.get_state_var_source state_var))
       ",@ ")
    state_vars);
*)
  trans_sys)


(* Open and parse from file *)
let of_file filename = 

    (* Open the given file for reading *)
    let use_file = open_in filename in
    let in_ch = use_file in

    of_channel in_ch



(* 
   Local Variables:
   compile-command: "make -C .. -k"
   indent-tabs-mode: nil
   End: 
*)
