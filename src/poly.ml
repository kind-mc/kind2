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

type psummand = int * (Var.t option)

type poly = psummand list

type preAtom =
  | GT of poly
  | EQ of poly
  | INEQ of poly
  | DIVISIBLE of (int * poly)
  | INDIVISIBLE of (int * poly)

type cformula = preAtom list

(* Print summand with absolute value of coefficient, the sign is added
   by pp_print_term' and pp_print_term *)
let pp_print_psummand ppf = function 
  | (c, None) -> Format.pp_print_int ppf (abs c)

  | (c, Some x) when c = 1 -> 
    Var.pp_print_var ppf x

  | (c, Some x) when c = -1 -> 
    Var.pp_print_var ppf x

  | (c, Some x) when c >= 0 -> 
    Format.pp_print_int ppf c; 
    Var.pp_print_var ppf x

  | (c, Some x) -> 
    Format.pp_print_int ppf (abs c); 
    Var.pp_print_var ppf x

let rec pp_print_poly' ppf = function 

  | [] -> ()
    
  (* Second or later term *)
  | ((c, _) as s) :: tl -> 

    (* Print as addition or subtraction *)
    Format.pp_print_string ppf (if c > 0 then "+" else "-");
    Format.pp_print_string ppf " ";
    pp_print_psummand ppf s; 
    Format.pp_print_string ppf " ";
    pp_print_poly' ppf tl


let pp_print_poly ppf = function 

  | ((c, _) as s) :: tl -> 
    if c < 0 then 
      Format.pp_print_string ppf "-";
    pp_print_psummand ppf s;
    Format.pp_print_string ppf " ";
    pp_print_poly' ppf tl

  | _ -> Format.pp_print_int ppf 0


let pp_print_preAtom ppf = function 

  | GT pl ->
    pp_print_poly ppf pl;
    Format.pp_print_string ppf "> 0";

  | EQ pl ->
    pp_print_poly ppf pl;
    Format.pp_print_string ppf "= 0";

  | INEQ pl ->
    pp_print_poly ppf pl;
    Format.pp_print_string ppf "!= 0";

  | DIVISIBLE (i, pl) ->
    Format.pp_open_hbox ppf ();
    Format.pp_print_int ppf i;
    Format.pp_print_string ppf " | ";
    pp_print_poly ppf pl;
    Format.pp_close_box ppf ()

  | INDIVISIBLE (i, pl) ->
    Format.pp_open_hbox ppf ();
    Format.pp_print_int ppf i;
    Format.pp_print_string ppf " !| ";
    pp_print_poly ppf pl;
    Format.pp_close_box ppf ()


let rec pp_print_cformula ppf cf = 
  match cf with
  | [] ->
    failwith "pp_print_cformula doesn't handle empty formula."
  
  | [pret] ->
    pp_print_preAtom ppf pret

  | pret::cf' ->
    pp_print_preAtom ppf pret;
    Format.pp_print_newline ppf ();
    Format.pp_print_string ppf " and ";
    pp_print_cformula ppf cf'


(* Compare two presburger summand by the ordering of variables. Used only when polynomials are ordered by the order of variables. *)
let compare_psummands (c: Var.t -> Var.t -> int) (ps1: psummand) (ps2: psummand) : int =

  match ps1, ps2 with
      
    | (_, None), (_, None) -> 0

    | (_, None), (_, Some _) -> 1

    | (_, Some _), (_, None) -> -1

    | (_, Some x1), (_, Some x2) -> c x1 x2



(* Negate a persburger summand. *)
let negate_psummand ((c, v): psummand) : psummand = (-c, v)


(* Negate a presburger term. *)
let negate_poly (pt: poly) : poly =
  List.map negate_psummand pt


(* Multiply a presburger summand with a integer. *)
let psummand_times_int ((c, v): psummand) (i: int) : psummand = (c * i, v)

(*
  match ps with
  | (ps_i, None) ->
    (ps_i * i, None)
 
  | (ps_i, Some v) ->
    (ps_i * i, Some v)
*)

(* Multiply a presburger term with a integer. *)
let poly_times_int (pt: poly) (i: int) : poly =
  List.map (fun x -> psummand_times_int x i) pt


(* Check if a presburger summand ps contains the variable v. 
   Return true when ps contains v.
   Return false otherwise. *)
let psummand_contains_variable (v: Var.t) (ps: psummand) : bool =

  match ps with 

    | (_, None) -> false
      
    | (_, Some ps_v) ->

      if (Var.compare_vars ps_v v = 0) then 
        (true)
      else 
        (false)


(* Check if a presburger is a constant number. *)
let psummand_is_constant (ps: psummand) : bool =

  match ps with 

    | (_, None) -> true
      
    | (_, Some _) -> false


(* Check if a poly is a constant. *)
let poly_is_constant (pl: poly) : bool =

  match pl with

    | [(i, None)] -> true
      
    | _ -> false


(* Get the coefficient of the variable v in a presburger term. *)
let get_coe_in_poly_anyorder (v: Var.t) (pt: poly) : int = 

  try 

    fst(List.find (psummand_contains_variable v) pt) 
      
  with Not_found -> 0
    

(* Get the coefficient of the variable v in a presburger term. Can
   only be used when the polynomial is ordered by *)
let get_coe_in_poly_obv (v: Var.t) (pl: poly) : int = 

  match pl with

    | (i, Some v1) :: pl' ->
      
      if (Var.equal_vars v1 v) then i else 0

    | _ -> 0


let get_coe_in_poly v pl = 

  match (Flags.cooper_order_var_by_elim ()) with
      
    | false -> get_coe_in_poly_anyorder v pl

    | true -> get_coe_in_poly_obv v pl


(* Check if a presburger term pret contains the variable v. 
   Return true when pf contains v.
   Return false otherwise. *)
let preAtom_contains_variable (v: Var.t) (pret: preAtom) : bool =

  match pret with

    | GT pl -> 
      get_coe_in_poly v pl <> 0

    | EQ pl -> 
      get_coe_in_poly v pl <> 0
        
    | INEQ pl -> 
      get_coe_in_poly v pl <> 0

    | DIVISIBLE (i, pl) ->
      get_coe_in_poly v pl <> 0

    | INDIVISIBLE (i, pl) ->
      get_coe_in_poly v pl <> 0


(* Check if a presburger formula cf contains the variable v. 
   Return true when pf contains v.
   Return false otherwise. *)
let cformula_contains_variable (v: Var.t) (cf: cformula) : bool =

  List.exists 
    (preAtom_contains_variable v)
    cf

      

(* Add two presburger summands when they have the same variable.
   Notice that this function don't check if the variables are
   the same. It uses the variable in ps1 anyway. *)
let add_psummands (ps1: psummand) (ps2: psummand) : psummand =
  
  match ps1, ps2 with

    | (i1, Some v1), (i2, Some v2) -> (i1 + i2, Some v1)
        
    | (i1, None), (i2, None) -> (i1 + i2, None)
      
    | _ -> 
      failwith "Trying to add two summands without the same variable."
        

(* Add two presburger terms.
   The arguments must be sorted before calling this function. 

   We simultaneously consume the two polynomials, constructing an
   accumulator of monomials in descending order. At the end we reverse
   the accumulator. This function is tail-recursive and uses only
   tail-recursive functions. *)
let rec add_two_polys (c: Var.t -> Var.t -> int) (accum: poly) (pt1: poly) (pt2: poly) : poly =

  match pt1, pt2 with

    (* At the end of monomials of the first polynomial *)
    | [], _ -> 

      (* Reverse accumulator and append remaining monomials *)
      List.rev_append accum pt2

    (* At the end of monomials of the second polynomial *)
    | _, [] -> 

      (* Reverse accumulator and append remaining monomials *)
      List.rev_append accum pt1

    (* Take head monomials of both polynomials *)
    | ((c1, v1) as ps1) :: tl1, ((c2, v2) as ps2) :: tl2 ->

      (* Compare head monomials of both polynomials *)
      (match (compare_psummands c ps1 ps2) with

        (* Variables are equal or both are constants *)
        | 0 ->

          (* Add coefficients *)
          let new_summand = (c1 + c2, v1) in
          
          if (fst new_summand = 0) then
            
            (* Discard monomial if coefficient is zero *)
            (add_two_polys c accum tl1 tl2)

          else

            (* Add and recurse for the remaining monomials *)
            (add_two_polys c (new_summand :: accum) tl1 tl2)

        (* Head monomial of first polynomial is smaller *)
        | i when i < 0 ->

          (* Add smaller monomial to head of accumulator (will be
             reversed at the end) *)
          (add_two_polys c (ps1 :: accum) tl1 pt2)
            
        (* Head monomial of second polynomial is greater *)
        | _ ->

          (* Add smaller monomial to head of accumulator (will be
             reversed at the end) *)
          (add_two_polys c (ps2 :: accum) pt1 tl2)    

      )
        

(* Add up a list of polynomials *)
let add_poly_list (c: Var.t -> Var.t -> int) (ptl: poly list) : poly = 

  match ptl with

    (* Empty list *)
    | [] -> [(0, None)]
      
    (* Take the head of the list as initial value and add the tail of
       the list *)
    | pt1 :: ptl' -> List.fold_left (add_two_polys c []) pt1 ptl'


(* Multiply two presburger terms when at least one of them is constant. *)
let multiply_two_polys (pt1: poly) (pt2: poly) : poly =

  match pt1, pt2 with

    (* Multiply by zero *)
    | [(0, None)], _ -> [(0, None)]
    | _, [(0, None)] -> [(0, None)]

    (* First polynomial is constant *)
    | [(i, None)], _ -> poly_times_int pt2 i

    (* Second polynomial is constant *)
    | _, [(i, None)] -> poly_times_int pt1 i

    | _ ->
      failwith "Can only multiply two polys when at least one of them is constant."


(* Multiply up a list of presburger terms of at least one element. *)
let multiply_poly_list (ptl: poly list) : poly =

  match ptl with 

    (* Empty list *)
    | [] -> [(1, None)]

    (* Take the head of the list as initial value and multiply with
       the tail of the list *)
    | pt1 :: ptl' -> List.fold_left multiply_two_polys pt1 ptl'


(* Comparison of variables: variables to be eliminated earlier are
   smaller, compare as Var.t if none is to be eliminated *)
let rec compare_variables (l: Var.t list) (v1: Var.t) (v2: Var.t) : int =

  (* Order variables by order of elimination? *)
  match (Flags.cooper_order_var_by_elim ()) with

    (* Use ordering on Var *)
    | false -> Var.compare_vars v1 v2

    (* Make variables to be eliminated earlier smaller *)
    | true -> 

      (match l with 

        (* Fall back to comparison if none of the variable is to be eliminated *)
        | [] -> Var.compare_vars v1 v2
          
        | h :: tl -> 

          (* Compare both variables to the first variable to be eliminated *)
          match Var.equal_vars h v1, Var.equal_vars h v2 with
              
            (* Both variable are equal *)
            | true, true -> 0
              
            (* First variable is to be eliminated first *)
            | true, false -> -1

            (* Second variable is to be eliminated first *)
            | false, true -> 1

            (* Recurse to compare with rest of variables to be eliminated *)
            | false, false -> compare_variables tl v1 v2

      )
      

(* 
   Local Variables:
   compile-command: "make -C .. -k"
   tuareg-interactive-program: "./kind2.top -I ./_build -I ./_build/SExpr"
   indent-tabs-mode: nil
   End: 
*)


      
