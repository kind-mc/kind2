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

(* Do not open the Lib module here, the lib module uses this module *)

(* ********************************************************************* *)
(* Types and hash-consing                                                *)
(* ********************************************************************* *)


(* A private type that cannot be constructed outside this module *)
type string_node = string 


(* Properties of a string *)
type string_prop = unit


(* Hashconsed string *)
type t = (string_node, string_prop) Hashcons.hash_consed


(* Hashing and equality on strings *)
module String_node = struct

  (* String type *)
  type t = string_node

  (* No properties for a string *)
  type prop = string_prop

  (* Test strings for equality *)
  let equal = (=)

  (* Return a hash of a string *)
  let hash = Hashtbl.hash

end


(* Hashconsed strings *)
module HString = Hashcons.Make(String_node)


(* Storage for hashconsed strings *)
let ht = HString.create 251


(* ********************************************************************* *)
(* Hashtables, maps and sets                                             *)
(* ********************************************************************* *)


(* Comparison function on strings *)
let compare = Hashcons.compare


(* Equality function on strings *)
let equal = Hashcons.equal


(* Hashing function on strings *)
let hash = Hashcons.hash 


(* Module as input to functors *)
module HashedString = struct 
    
  (* Dummy type to prevent writing [type t = t] which is cyclic *)
  type z = t
  type t = z

  (* Compare tags of hashconsed terms for equality *)
  let equal = equal
    
  (* Use hash of term *)
  let hash = hash

end


(* Module as input to functors *)
module OrderedString = struct 

  (* Dummy type to prevent writing [type t = t] which is cyclic *)
  type z = t
  type t = z

  (* Compare tags of hashconsed symbols *)
  let compare = compare

end


(* Hashtable *)
module HStringHashtbl = Hashtbl.Make (HashedString)


(* Set *)
module HStringSet = Set.Make (OrderedString)


(* Map *)
module HStringMap = Map.Make (OrderedString)


(* ********************************************************************* *)
(* Pretty-printing                                                       *)
(* ********************************************************************* *)


(* Pretty-print a string *)
let pp_print_string = Format.pp_print_string

(* Pretty-print a hashconsed string *)
let pp_print_hstring ppf { Hashcons.node = n } = pp_print_string ppf n

(* Pretty-print a hashconsed term to the standard formatter *)
let print_hstring = pp_print_hstring Format.std_formatter 

(* Pretty-print a term  to the standard formatter *)
let print_string = pp_print_string Format.std_formatter 

(* Return a string representation of a term *)
let string_of_hstring { Hashcons.node = n } = n


(* ********************************************************************* *)
(* Constructors                                                          *)
(* ********************************************************************* *)


(* Return an initialized property for the string *)
let mk_prop s = ()


(* Return a hashconsed string *)
let mk_hstring s = HString.hashcons ht s (mk_prop s)


(* Import a string from a different instance into this hashcons
   table *)
let import { Hashcons.node = s } = mk_hstring s

(* ********************************************************************* *)
(* String functions                                                      *)
(* ********************************************************************* *)

let length { Hashcons.node = n } = String.length n 

let get { Hashcons.node = n } i = String.get n i

let set { Hashcons.node = n } i c = 

  (* Copy to a fresh string *)
  let n' = String.copy n in 

  String.set n' i c;
  mk_hstring n' 

let create i = mk_hstring (String.create i)

let make i c = mk_hstring (String.make i c)

let sub { Hashcons.node = n } i j = String.sub n i j

let fill { Hashcons.node = n } i j c = 

  (* Copy to a fresh string *)
  let n' = String.copy n in 

  String.fill n' i j c;
  mk_hstring n'

let blit { Hashcons.node = n } i { Hashcons.node = m } j k = 

  (* Copy to a fresh string *)
  let n' = String.copy n in 
  
  String.blit n' i m j k;
  mk_hstring n'

let concat { Hashcons.node = n } l =

  mk_hstring (String.concat n (List.map string_of_hstring l))

let iter f { Hashcons.node = n } = String.iter f n

let iteri f { Hashcons.node = n } = String.iteri f n

let map f { Hashcons.node = n } = mk_hstring (String.map f n)

let trim { Hashcons.node = n } = mk_hstring (String.trim n)

let escaped { Hashcons.node = n } = mk_hstring (String.escaped n)

let index { Hashcons.node = n } c = String.index n c

let rindex { Hashcons.node = n } c = String.rindex n c

let index_from { Hashcons.node = n } i c = String.index_from n i c

let rindex_from { Hashcons.node = n } i c = String.rindex_from n i c
 
let contains { Hashcons.node = n } c = String.contains n c

let contains_from { Hashcons.node = n } i c = String.contains_from n i c

let rcontains_from { Hashcons.node = n } i c = String.rcontains_from n i c

let uppercase { Hashcons.node = n } = mk_hstring (String.uppercase n)

let lowercase { Hashcons.node = n } = mk_hstring (String.lowercase n)

let capitalize { Hashcons.node = n } = mk_hstring (String.capitalize n)

let uncapitalize { Hashcons.node = n } = mk_hstring (String.uncapitalize n)


(* 
   Local Variables:
   compile-command: "make -C .. -k"
   tuareg-interactive-program: "./kind2.top -I ./_build -I ./_build/SExpr"
   indent-tabs-mode: nil
   End: 
*)
