(**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

include Ty_symbol
include Ty_ancestors

type aloc = ALoc.t
[@printer fun fmt loc -> fprintf fmt "%s" (ALoc.to_string_no_source loc)]
[@@deriving show]

type t =
  | TVar of tvar * t list option
  | Bound of aloc * string
  | Generic of symbol * gen_kind * t list option
  | Any of any_kind
  | Top
  | Bot of bot_kind
  | Void | Null
  | Num of string option
  | Str of string option
  | Bool of bool option
  | NumLit of string
  | StrLit of string
  | BoolLit of bool
  | Fun of fun_t
  | Obj of obj_t
  | Arr of arr_t
  | Tup of t list
  | Union of t * t * t list
  | Inter of t * t * t list
  | TypeAlias of type_alias
  | TypeOf of path * string
  | ClassDecl of symbol * type_param list option
  | InterfaceDecl of symbol * type_param list option
  | Utility of utility
  | Module of symbol
  | Mu of int * t

and tvar = RVar of int [@@unboxed]            (* Recursive variable *)

and path = string list

and any_kind =
  | Implicit
  | Explicit

(* The purpose of adding this distinction is to enable normalized types to mimic
 * the behavior of the signature optimizer when exporting types that contain
 * tvars with no lower bounds.
 *)
and upper_bound_kind =
  (* No upper bounds are exported as `any` *)
  | NoUpper
  (* If there is some upper bound (use), this is exported as `MergedT use`. This
   * type is not helpful in a normalized form. So instead we attempt to normalize
   * the use to a type `t`. If this succeeds then we create `SomeKnownUpper t`.
   *)
  | SomeKnownUpper of t
  (* If the above case fails we resort to this last case. *)
  | SomeUnknownUpper of string

and bot_kind =
  (* Type.Empty *)
  | EmptyType
  (* Type.MatchingPropT *)
  | EmptyMatchingPropT
  (* Type.TypeDestructorTriggerT *)
  | EmptyTypeDestructorTriggerT of aloc
  (* A tvar with no lower bounds *)
  | NoLowerWithUpper of upper_bound_kind

and gen_kind =
  | ClassKind
  | InterfaceKind
  | TypeAliasKind

and fun_t = {
  fun_params: (string option * t * fun_param) list;
  fun_rest_param: (string option * t) option;
  fun_return: t;
  fun_type_params: type_param list option;
}

and obj_t = {
  obj_exact: bool;
  obj_frozen: bool;
  obj_literal: bool;
  obj_props: prop list;
}

and arr_t = {
  arr_readonly: bool;
  arr_literal: bool;
  arr_elt_t: t;
}

and type_alias = {
  ta_name: symbol;
  ta_tparams: type_param list option;
  ta_type: t option
}

and fun_param = {
  prm_optional: bool;
}

and prop =
  | NamedProp of string * named_prop
  | IndexProp of dict
  | CallProp of fun_t
  | SpreadProp of t

and named_prop =
  | Field of t * field
  | Method of fun_t
  | Get of t
  | Set of t

and field = {
  fld_polarity: polarity;
  fld_optional: opt;
}

and dict = {
  dict_polarity: polarity;
  dict_name: string option;
  dict_key: t;
  dict_value: t;
}

and type_param = {
  tp_name: string;
  tp_bound: t option;
  tp_polarity: polarity;
  tp_default: t option;
}

and opt = bool

and utility =
  (* https://flow.org/en/docs/types/utilities/ *)
  | Keys of t
  | Values of t
  | ReadOnly of t
  | Exact of t
  | Diff of t * t
  | Rest of t * t
  | PropertyType of t * t
  | ElementType of t * t
  | NonMaybeType of t
  | ObjMap of t * t
  | ObjMapi of t * t
  | TupleMap of t * t
  | Call of t * t list
  | Class of t
  | Shape of t
  | Supertype of t
  | Subtype of t
  | Exists
  (* React utils *)
  | ReactElementPropsType of t
  | ReactElementConfigType of t
  | ReactElementRefType of t
  | ReactConfigType of t * t

and polarity = Positive | Negative | Neutral
[@@deriving visitors {
  name="iter_ty";
  nude=true;
  variety = "iter";
  visit_prefix="on_";
  ancestors=["iter_ty_base"];
}, visitors {
  name="iter2_ty";
  nude=true;
  variety = "iter2";
  visit_prefix="on_";
  ancestors=["iter2_ty_base"];
}, visitors {
  name="reduce_ty";
  variety = "reduce";
  nude = true;
  visit_prefix = "on_";
  ancestors = ["reduce_ty_base"];
}, visitors {
  name="map_ty";
  variety = "map";
  nude = true;
  visit_prefix = "on_";
  ancestors = ["map_ty_base"];
}, visitors {
  name="endo_ty";
  variety = "endo";
  nude = true;
  visit_prefix = "on_";
  ancestors = ["endo_ty_base"];
}, visitors {
  name="mapreduce_ty";
  variety = "mapreduce";
  nude = true;
  visit_prefix = "on_";
  ancestors = ["mapreduce_ty_base"];
}, show
]

exception Difference of int
let assert0 i = if i == 0 then () else raise (Difference i)

(* The prototype of what should happen when overriding fail_* methods *)
let fail_gen: 'env 'x. ('env -> 'x -> int) -> 'env -> 'x -> 'x -> unit =
  fun tag_of env t1 t2 ->
    assert0 ((tag_of env t1) - (tag_of env t2))

(* Compare Ty.t for structural equality
   This class can be overridden to define new forms of equality on types *)
class ['A] comparator_ty = object(this)
  inherit [_] iter2_ty

  method compare (env : 'A) (t1 : t) (t2 : t) =
    try this#on_t env t1 t2 ; 0 with
    | Difference n -> n

  (* Base fields originally handled in the ancestor *)
  method! private on_int _env x y = assert0 (x - y)
  method! private on_string _env x y = assert0 (String.compare x y)
  method! private on_bool _env x y = assert0 (Pervasives.compare x y)
  method! private on_symbol _env x y = assert0 (Pervasives.compare x y)
  method! private on_aloc _env x y = assert0 (ALoc.compare x y)

  method! private fail_option _env x _y =
    match x with
    | None -> raise (Difference (-1))
    | _ -> raise (Difference 1)

  method! private fail_list _env x _y =
    match x with
    | [] -> raise (Difference (-1))
    | _ -> raise (Difference 1)

  (* This class must override all fail_* methods on variant types to be correct. *)
  (* The following methods are ordered respectively with the
     definitions in this file to make it easier to check *)
  method! private fail_t env x y = fail_gen this#tag_of_t env x y
  method! private fail_any_kind env x y = fail_gen this#tag_of_any_kind env x y
  method! private fail_upper_bound_kind env x y = fail_gen this#tag_of_upper_bound_kind env x y
  method! private fail_bot_kind env x y = fail_gen this#tag_of_bot_kind env x y
  method! private fail_gen_kind env x y = fail_gen this#tag_of_gen_kind env x y
  method! private fail_prop env x y = fail_gen this#tag_of_prop env x y
  method! private fail_named_prop env x y = fail_gen this#tag_of_named_prop env x y
  method! private fail_utility env x y = fail_gen this#tag_of_utility env x y

  (* No two elements of each variant can be assigned the same tag *)
  method tag_of_t _ = function
    | TVar _ -> 0
    | Bound _ -> 1
    | Generic _ -> 2
    | Any _ -> 3
    | Top -> 4
    | Bot _ -> 5
    | Void -> 6
    | Null -> 7
    | Num _ -> 8
    | Str _ -> 9
    | Bool _ -> 10
    | NumLit _ -> 11
    | StrLit _ -> 12
    | BoolLit _ -> 13
    | Fun _ -> 14
    | Obj _ -> 15
    | Arr _ -> 16
    | Tup _ -> 17
    | Union _ -> 18
    | Inter _ -> 19
    | TypeAlias _ -> 20
    | TypeOf _ -> 21
    | ClassDecl _ -> 22
    | InterfaceDecl _ -> 23
    | Utility _ -> 24
    | Module _ -> 25
    | Mu _ -> 26

  method tag_of_gen_kind _ = function
    | ClassKind -> 0
    | InterfaceKind -> 1
    | TypeAliasKind -> 2

  method tag_of_any_kind _ = function
    | Implicit -> 0
    | Explicit -> 1

  method tag_of_prop _env = function
    | NamedProp _ -> 0
    | IndexProp _ -> 1
    | CallProp _ -> 2
    | SpreadProp _ -> 3

  method tag_of_named_prop _env = function
    | Field _ -> 0
    | Method _ -> 1
    | Get _ -> 2
    | Set _ -> 3

  method tag_of_utility _ = function
    | Keys _ -> 0
    | Values _ -> 1
    | ReadOnly _ -> 2
    | Exact _ -> 3
    | Diff _ -> 4
    | Rest _ -> 5
    | PropertyType _ -> 6
    | ElementType _ -> 7
    | NonMaybeType _ -> 8
    | ObjMap _ -> 9
    | ObjMapi _ -> 10
    | TupleMap _ -> 11
    | Call _ -> 12
    | Class _ -> 13
    | Shape _ -> 14
    | Supertype _ -> 15
    | Subtype _ -> 16
    | Exists -> 17
    | ReactElementPropsType _ -> 18
    | ReactElementConfigType _ -> 19
    | ReactElementRefType _ -> 20
    | ReactConfigType _ -> 21

  method tag_of_bot_kind _env = function
    | EmptyType -> 0
    | EmptyMatchingPropT -> 1
    | EmptyTypeDestructorTriggerT _ -> 2
    | NoLowerWithUpper _ -> 3

  method tag_of_upper_bound_kind _env = function
    | NoUpper -> 0
    | SomeKnownUpper _ -> 1
    | SomeUnknownUpper _ -> 2
end


(* Type destructors *)

let rec bk_union ?(flattened=false) = function
  | Union (t1,t2,ts) when flattened -> (t1, t2::ts)
  | Union (t1,t2,ts) -> Nel.map_concat bk_union (t1, t2::ts)
  | t -> (t, [])

let rec bk_inter ?(flattened=false) = function
  | Inter (t1,t2,ts) when flattened -> (t1, t2::ts)
  | Inter (t1,t2,ts) -> Nel.map_concat bk_inter (t1, t2::ts)
  | t -> (t, [])


(* Type constructors *)

let mk_union ?(flattened=false) nel_ts =
  let (t, ts) = Nel.map_concat (bk_union ~flattened) nel_ts in
  match ts with
  | [] -> t
  | hd::tl -> Union (t, hd, tl)

let mk_inter ?(flattened=false) nel_ts =
  let (t, ts) = Nel.map_concat (bk_inter ~flattened) nel_ts in
  match ts with
  | [] -> t
  | hd::tl -> Inter (t, hd, tl)

let explicit_any = Any Explicit
let implicit_any = Any Implicit
let is_dynamic = function Any _ -> true | _ -> false
let mk_maybe t =
  mk_union (Null, [Void; t])

let mk_field_props prop_list =
  Core_list.map ~f:(fun (id, t, opt) -> NamedProp (id,
    Field (t, { fld_polarity = Neutral; fld_optional = opt })
  )) prop_list

let mk_object ?(obj_exact=false) ?(obj_frozen=false) ?(obj_literal = false) obj_props =
  Obj { obj_exact; obj_frozen; obj_literal; obj_props }

let mk_generic_class symbol targs =
  Generic (symbol, ClassKind, targs)

let mk_generic_interface symbol targs =
  Generic (symbol, InterfaceKind, targs)

let mk_generic_talias symbol targs =
  Generic (symbol, TypeAliasKind, targs)

let rec mk_exact ty =
  match ty with
  | Obj o -> Obj { o with obj_exact=true }
  | TypeAlias a ->
    let ta_type = Option.map ~f:mk_exact a.ta_type in
    TypeAlias { a with ta_type }
  | Mu (i, t) -> Mu (i, mk_exact t)
  (* Not applicable *)
  | Any _ | Top | Bot _ | Void | Null
  | Num _ | Str _ | Bool _ | NumLit _ | StrLit _ | BoolLit _
  | Fun _ | Arr _ | Tup _ -> ty
  (* Do not nest $Exact *)
  | Utility (Exact _) -> ty
  (* Wrap in $Exact<...> *)
  | Generic _ | TVar _ | Bound _ | Union _ | Inter _
  | TypeOf _ | ClassDecl _ | InterfaceDecl _
  | Utility _ | Module _ ->
    Utility (Exact ty)

let mk_array ~readonly ~literal t =
  Arr { arr_readonly = readonly; arr_literal = literal; arr_elt_t = t }

let named_alias ?ta_tparams ?ta_type name =
  TypeAlias { ta_name=name; ta_tparams; ta_type }

let debug_string_of_provenance_ctor = function
  | Local -> "Local"
  | Remote { imported_as = Some _ } -> "Imported"
  | Remote { imported_as = None } -> "Remote"
  | Library -> "Library"
  | Builtin -> "Builtin"

let debug_string_of_symbol { provenance; def_loc; name; _ } =
  Utils_js.spf "%s (%s:%s)" name (debug_string_of_provenance_ctor provenance)
    (Reason.string_of_aloc def_loc)

let debug_string_of_generic_kind = function
  | ClassKind -> "class"
  | InterfaceKind -> "interface"
  | TypeAliasKind -> "type alias"

let string_of_utility_ctor = function
  | Keys _ -> "$Keys"
  | Values _ -> "$Values"
  | ReadOnly _ -> "$ReadOnly"
  | Exact _ -> "$Exact"
  | Diff _ -> "$Diff"
  | Rest _ -> "$Rest"
  | PropertyType _ -> "$PropertyType"
  | ElementType _ -> "$ElementType"
  | NonMaybeType _ -> "$NonMaybeType"
  | ObjMap _ -> "$ObjMap"
  | ObjMapi _ -> "$ObjMapi"
  | TupleMap _ -> "$TupleMap"
  | Call _ -> "$Call"
  | Class _ -> "Class"
  | Shape _ -> "$Shape"
  | Supertype _ -> "$Supertype"
  | Subtype _ -> "$Subtype"
  | Exists -> "*"
  | ReactElementPropsType _ -> "React$ElementProps"
  | ReactElementConfigType _ -> "React$ElementConfig"
  | ReactElementRefType _ -> "React$ElementRef"
  | ReactConfigType _  -> "React$Config"

let types_of_utility = function
  | Keys t -> Some [t]
  | Values t -> Some [t]
  | ReadOnly t -> Some [t]
  | Exact t -> Some [t]
  | Diff (t1, t2) -> Some [t1; t2]
  | Rest (t1, t2) -> Some [t1; t2]
  | PropertyType (t1, t2) -> Some [t1; t2]
  | ElementType (t1, t2) -> Some [t1; t2]
  | NonMaybeType t -> Some [t]
  | ObjMap (t1, t2) -> Some [t1; t2]
  | ObjMapi (t1, t2) -> Some [t1; t2]
  | TupleMap (t1, t2) -> Some [t1; t2]
  | Call (t, ts) -> Some (t::ts)
  | Class t -> Some [t]
  | Shape t -> Some [t]
  | Supertype t -> Some [t]
  | Subtype t -> Some [t]
  | Exists -> None
  | ReactElementPropsType t -> Some [t]
  | ReactElementConfigType t -> Some [t]
  | ReactElementRefType t -> Some [t]
  | ReactConfigType (t1, t2) -> Some [t1; t2]
