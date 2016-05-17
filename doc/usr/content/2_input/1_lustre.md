# Lustre Input

Lustre is a functional, synchronous dataflow language. Kind 2 supports most of the Lustre V4 syntax and some elements of Lustre V6. See the file [`./examples/syntax-test.lus`](https://github.com/kind2-mc/kind2/blob/develop/examples/syntax-test.lus) for examples of all supported language constructs.

## Properties and top level node

To specify a property to verify in a Lustre node, add the following in the body (*i.e.* between keywords ```let``` and ```tel```) of the node:

```
--%PROPERTY <bool_expr> ;
```

where `<bool_expr>` is a Boolean Lustre expression.

Kind 2 only analyzes what it calls the *top node*. By default, the top node is the last node in the file. To force a node to be the top node, add

```
--%MAIN ;
```

to the body of that node.

You can also specify the top node in the command line arguments, with

```
kind2 --lustre_main <node_name> ...
```

### Example

The following example declares two nodes ```greycounter``` and ```intcounter```, as well as an *observer* node ```top``` that calls these nodes and verifies that their outputs are the same. The node ```top``` is annotated with ```--%MAIN ;``` which makes it the *top node* (redundant here because it is the last node). The line ```--PROPERTY OK;``` means we want to verify that the Boolean stream ```OK``` is always true.

```
node greycounter (reset: bool) returns (out: bool);
var a, b: bool; 
let
  a = false -> (not reset and not pre b);
  b = false -> (not reset and pre a);
  out = a and b;

tel

node intcounter (reset: bool; const max: int) returns (out: bool);
var t: int; 
let
  t = 0 -> if reset or pre t = max then 0 else pre t + 1;
  out = t = 2;

tel

node top (reset: bool) returns (OK: bool);
var b, d: bool;
let
  b = greycounter(reset);
  d = intcounter(reset, 3);
  OK = b = d;

  --%MAIN ;

  --%PROPERTY OK;

tel
```

Kind 2 produces the following on standard output when run with the default options (```kind2 <file_name.lus>```):

```
kind2 v0.8.0

<Success> Property OK is valid by inductive step after 0.182s.

status of trans sys
------------------------------------------------------------------------------
Summary_of_properties:

OK: valid
```

We can see here that the property ```OK``` has been proven valid for the system (by *k*-induction).


## Contracts

A contract `(A,G,M)`for a node is a set of assumptions `A`, a set of
guarantees `G`, and a set of modes `M`. The semantics of contracts is given
in the
[Contract semantics](./../9_other/2_contract_semantics.md#contract-semantics)
section, here we focus on the input format for contracts. Contracts are
specified either locally, using the *inline syntax*, or externally in a
*contract node*. Both the local and external syntax have a body
composed of *items*, each of which define

* a ghost variable / constant,
* an assumption,
* a guarantee,
* a mode, or
* an import of a contract node.

They are presented in detail below, after the discussion on local and external
syntaxes.


### Inline syntax

A local contract is a special comment between the signature of the node
```
node <id> (...) returns (...) ;
```
and its body. That is, between the `;` of the node signature and the `let`
opening its body.

A local contract is a special block comment of the form

```
(*@contract
  [item]+
*)
```

or

```
/*@contract
  [item]+
*/
```


### External syntax

A contract node is very similar to a traditional lustre node. The two
differences are that

* it starts with `contract` instead of `node`, and
* its body can only mention *contract items*.

A contract node thus has form

```
contract <id> (<in_params>) returns (<out_params>) ;
let
  [item]+
tel
```

To use a contract node one needs to import it through an inline contract. See
the next section for more details.





### Contract items and restrictions


#### Ghost variables and constants

A ghost variable (constant) is a stream that is local to the contract. That is,
it is not accessible from the body of the node specified. Ghost variables
(constants) are defined with the `var` (`const`) keyword. Kind 2 performs type
inference for constants so in most cases type annotations are not necessary.

The general syntax is
```
const <id> [: <type>] = <expr> ;
var   <id>  : <type>  = <expr> ;
```

For instance:
```
const max = 42 ;
var ghost_stream: real = if input > max then max else input ;
```


#### Assumptions

An assumption over a node `n` is a constraint one must respect in order to use
`n` legally. It cannot mention the outputs of `n` in the current state, but
referring to outputs under a `pre` is fine.

The idea is that it does not make sense to ask the caller to respect some
constraints over the outputs of `n`, as the caller has no control over them
other than the inputs it feeds `n` with.
The assumption may however depend on previous values of the outputs produced
by `n`.

Assumptions are given with the `assume` keyword, followed by any legal Boolean
expression:
```
assume <expr> ;
```



#### Guarantees

Unlike assumptions, guarantees do not have any restrictions on the streams
they can mention. They typically mention the outputs in the current state since
they express the behavior of the node they specified under the assumptions of
this node.

Guarantees are given with the `guarantee` keyword, followed by any legal
Boolean expression:
```
guarantee <expr> ;
```



#### Modes

A mode `(R,E)` is a set of *requires* `R` and a set of *ensures* `E`. Requires
have the same restrictions as assumptions: they cannot mention outputs of the
node they specify in the current state. Ensures, like guarantees, have no
restriction.

Modes are named to ease traceability and improve feedback. The general syntax
is
```
mode <id> (
  [require <expr> ;]*
  [ensure  <expr> ;]*
) ;
```

For instance:
```
mode engaging (
  require true -> not pre engage_input ;
  require engage_input ;
  -- No ensure, same as `ensure true ;`.
) ;
mode engaged (
  require engage_input ;
  require false -> pre engage_input ;
  ensure  output <= upper_bound ;
  ensure  lower_bound <= output ;
) ;
```



#### Imports

A contract import *merges* the current contract with the one imported. That
is, if the current contract is `(A,G,M)` and we import `(A',G',M')`, the
resulting contract is `(A U A', G U G', M U M')` where `U` is set union.

When importing a contract, it is necessary to specify how the instantiation of
the contract is performed. This defines a mapping from the input (output)
formal parameters to the actual ones of the import.

When importing contract `c` in the contract of node `n`, it is **illegal** to
mention an output of `n` in the actual input parameters of the import of `c`.
The reason is that the distinction between inputs and outputs lets Kind 2 check
that the assumptions and mode requirements make sense, *i.e.* do not mention
outputs of `n` in the current state.

The general syntax is
```
import <id> ( <expr>,* ) returns ( <expr>,* ) ;
```

For instance:
```
contract spec (engage, disengage: bool) returns (engaged: bool) ;
let ... tel

node my_node (
  -- Flags are "signals" here, but `bool`s in the contract.
  engage, disengage: real
) returns (
  engaged: real
) ;
(*@contract 
  var bool_eng: bool = engage <> 0.0 ;
  var bool_dis: bool = disengage <> 0.0 ;
  var bool_enged: bool = engaged <> 0.0 ;

  var never_triggered: bool = (
    not bool_eng -> not bool_eng and pre never_triggered
  ) ;

  assume not (bool_eng and bool_dis) ;
  guarantee true -> (
    (not engage and not pre bool_eng) => not engaged
  ) ;

  mode init (
    require never_triggered ;
    ensure not bool_enged ;
  ) ;

  import spec (bool_eng, bool_dis) returns (bool_enged) ;
*)
let ... tel
```



#### Mode references

Once a mode has been defined it is possible to *refer* to it with
```
::<scope>::<mode_id>
```
where `<mode_id>` is the name of the mode, and `<scope>` is the path to the
mode in terms of contract imports.

In the example from the previous section for instance, say contract `spec` has
a mode `m`. The inline contract of `my_node` can refer to it by
```
::spec::m
```
To refer to the `init` mode:
```
::init
```

A mode reference is syntactic sugar for the `requires` of the mode in question.
So if mode `m` is
```
mode m (
  require <r_1> ;
  require <r_2> ;
  ...
  require <r_n> ; -- Last require.
  ...
) ;
```
then `::<path>::m` is exactly the same as
```
(<r_1> and <r_1> and ... and <r_n>)
```

**N.B.**: a mode reference
* is a Lustre expression of type `bool` just like any other Boolean expression. 
  It can appear under a `pre`, be used in a node call or a contract import, *etc.*
* is only legal **after** the mode item itself. That is, no
  forward/self-references are allowed.


An interesting use-case for mode references is that of checking properties over
the specification itself. One may want to do so to make sure the specification
behaves as intended. For instance
```
mode m1 (...) ;
mode m2 (...) ;
mode m3 (...) ;

guarantee true -> ( -- `m3` cannot succeed to `m1`.
  (pre ::m1) => not ::m3
) ;
guarantee true -> ( -- `m1`, `m2` and `m3` are exclusive.
  not (::m1 and ::m2 and ::m3)
) ;
```

