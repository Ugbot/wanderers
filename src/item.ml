(*           Wanderers - open world adventure game.
            Copyright (C) 2013-2014  Alexey Nikolaev.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>. *)


open Base

type mat = Leather | Wood | Steel | DmSteel | RustySteel | Gold 

type eff = [ `Heal ]

(* unified quality measure *)
type qm = float
let qm_min = 0.0 (* extremely bad, poor quality *)
let qm_max = 1.0 (* perfect, flawless *)

module Ranged = struct
  type t = {force: float; projmass: float; dmgmult: float}
end

module Melee = struct
  type t = {attrate: float; duration: float;}

  let join_simple {attrate=ar1; duration=d1} {attrate=ar2; duration=d2} = 
    {attrate=ar1 +. ar2; duration = max d1 d2}
  
  let join_max {attrate=ar1; duration=d1} {attrate=ar2; duration=d2} = 
    {attrate = max ar1 ar2; duration = max d1 d2}
end

type prop = [ `Melee of Melee.t | `Defense of float | `Weight of float | `Material of mat 
  | `Consumable of eff | `Wearable |  `Headgear | `Wieldable | `Quality of qm | `Ranged of Ranged.t | `Money]

let upgrade_prop (m0,m1) prop =
  match m1 with
  | DmSteel -> 
      ( let c = 1.4 in
        match prop with
        | `Weight x -> `Weight (x *. 0.90)
        | `Defense x -> `Defense (x *. c)
        | `Melee {Melee.attrate=att; Melee.duration=dur} -> 
            `Melee Melee.({attrate = att *. c; duration = dur})
        | `Ranged {Ranged.force=frc; Ranged.projmass=m; Ranged.dmgmult=dmg} -> 
            `Ranged Ranged.({force = frc; projmass = m; dmgmult = dmg *. c})
        | `Material _ -> `Material m1
        | x -> x
      )
  | RustySteel -> 
      ( let c = 0.65 in
        match prop with
        | `Weight x -> `Weight (x *. 1.0)
        | `Defense x -> `Defense (x *. c)
        | `Melee {Melee.attrate=att; Melee.duration=dur} -> 
            `Melee Melee.({attrate = att *. c; duration = dur})
        | `Ranged {Ranged.force=frc; Ranged.projmass=m; Ranged.dmgmult=dmg} -> 
            `Ranged Ranged.({force = frc; projmass = m; dmgmult = dmg *. c})
        | `Material _ -> `Material m1
        | x -> x
      )
  | _ -> prop

module PS = Set.Make(struct type t = prop let compare = compare end)

(* kind size mat variant *)
type barcode = {bc_kind: int; bc_size: int; bc_mat: mat; bc_var: int}

type t = { name: string; prop: PS.t; imgindex:int; price: int; stackable: int option; barcode:barcode; }
(* the parameter 'stackable' tells you the max size of the stack of such objects *)

type item_type = t

let upgrade_item (m0,m1) item =
  let prop_u = 
    PS.fold (fun p acc -> PS.add (upgrade_prop (m0,m1) p) acc) item.prop PS.empty
  in
  let price_u = match m1 with 
    | DmSteel -> 50 + item.price * 4
    | RustySteel -> (item.price+1) / 2
    | x -> item.price in
  {item with prop = prop_u; price = price_u; barcode = {item.barcode with bc_mat = m1}}


(* item obj has property p*)
let is p obj = PS.mem p obj.prop

let get_melee obj =
  PS.fold (fun prop acc -> 
      match prop with
        `Melee x -> Some x 
      | _ -> acc
    ) obj.prop None

let get_defense obj =
  PS.fold (fun prop acc -> 
      match prop with
        `Defense x -> acc +. x 
      | _ -> acc
    ) obj.prop 0.0

let get_ranged obj =
  PS.fold (fun prop acc -> 
      match prop with
        `Ranged x -> Some x 
      | _ -> acc
    ) obj.prop None

let get_mat obj =
  PS.fold (fun prop acc -> 
      match prop with
        `Material x -> Some x 
      | _ -> acc
    ) obj.prop None

let get_mass obj = 
  PS.fold (fun prop acc -> 
      match prop with
        `Weight x -> acc +. x 
      | _ -> acc
    ) obj.prop 0.0

let is_wearable obj = PS.mem `Wearable obj.prop 
let is_a_headgear obj = PS.mem `Headgear obj.prop
let is_wieldable obj = PS.mem `Wieldable obj.prop

let string_of_item i =
  Printf.sprintf "[%i,%i] p=%i (%s)" i.barcode.bc_kind i.barcode.bc_size i.price i.name

(* integer map *)
module M = Map.Make(struct type t = int let compare = compare end)

let map_of_list ls = 
  List.fold_left (fun acc (key,obj) -> M.add key obj acc) M.empty ls

(* container *)
module Cnt = struct
  type slot_type = General | Hand | Head | Body | Purse 
  
  let does_fit slt obj = match slt with
    | General -> true
    | Hand -> is `Wieldable obj
    | Head -> is `Headgear obj
    | Body -> is `Wearable obj
    | Purse -> is `Money obj

  type bunch = {item: item_type; amount: int}

  type t = {bunch: bunch M.t; slot: slot_type M.t; caplim: int option;}

  let make slot caplim =
    {bunch = M.empty; slot; caplim}

  let default_coins_slot = 4 
  let empty_nat_human = 
    let ls = [(0,Hand); (1,Body); (2,Hand); (3, Head); (4,Purse)] in
    let len = List.length ls in
    make (map_of_list ls) (Some len)
  
  let empty_only_money = 
    let ls = [(0,Purse)] in
    let len = List.length ls in
    make (map_of_list ls) (Some len)
  
  let empty_only_money_plus = 
    let ls = [(0,Purse); (1,General)] in
    let len = List.length ls in
    make (map_of_list ls) (Some len)
 
  let empty_unlimited = make M.empty None
  
  let empty_limited n = 
    let ls = fold_lim (fun acc i -> (i, General)::acc) [] 0 (n-1) |> List.rev in
    make (map_of_list ls) (Some n)

  let find_empty_slot pred c = 
    let rec search i =
      let enough_space = 
        match c.caplim with
          | Some lim -> i < lim | None -> true in
      
      if enough_space then
      ( if not (M.mem i c.bunch) && 
          (not (M.mem i c.slot) || pred (M.find i c.slot)) then
          Some i
        else
          search (i+1)
      )
      else
        None 
    in
    search 0
  
  let find_matching_half_full_slot obj c = 
    match obj.stackable with
    | Some max_amount ->
        M.fold 
          (fun i b acc ->
            match acc, b with
            | None, {item; amount} when item = obj && amount < max_amount -> Some i
            | _ -> acc
          )
          c.bunch None 
    | None ->
        None

  let put obj c =
    let opt_i = 
      match find_matching_half_full_slot obj c with
      | Some i -> Some i
      | None -> find_empty_slot (fun slt -> does_fit slt obj) c
    in
    match opt_i with
    | Some i -> 
        let {item; amount} = try M.find i c.bunch with Not_found -> {item=obj; amount=0} in
        Some {c with bunch = M.add i {item; amount = amount+1} c.bunch}
    | None -> None

  (* get only one object *)
  let get i c = 
    try 
      let {item; amount} = M.find i c.bunch in
      if amount > 1 then 
        Some (item, {c with bunch = M.add i {item; amount=amount-1} c.bunch})
      else
        Some (item, {c with bunch = M.remove i c.bunch})
    with
    | Not_found -> None
  
  type 'a move_bunch_result = 
    | MoveBunchFailure 
    | MoveBunchPartial of (bunch * 'a)
    | MoveBunchSuccess of 'a
  
  (* put the whole bunch *)
  let put_bunch bunch c =
    let max_amount = match bunch.item.stackable with Some x -> x | _ -> 1 in

    let rec repeat some_success bunch c =
      let {item; amount} = bunch in

      let opt_i = 
        match find_matching_half_full_slot item c with
        | Some i -> Some i
        | None -> find_empty_slot (fun slt -> does_fit slt item) c
      in

      match opt_i with
      | Some i -> 
          let amount_already_there = try (M.find i c.bunch).amount with Not_found -> 0 in

          let amount_to_add = (min (amount+amount_already_there) max_amount) - amount_already_there in
          let amount_remains = amount - amount_to_add in
          let uc = {c with bunch = M.add i {item; amount = amount_already_there + amount_to_add} c.bunch} in
          
          if amount_remains > 0 then
            repeat true {item; amount = amount_remains} uc
          else
            MoveBunchSuccess uc
      | None -> 
          if some_success then MoveBunchPartial (bunch, c) else MoveBunchFailure
    in
    if bunch.amount > 0 then
      repeat false bunch c
    else
      MoveBunchSuccess c
  
  (* get the whole bunch *)
  let get_bunch i c = 
    try 
      let bunch = M.find i c.bunch in
      Some (bunch, {c with bunch = M.remove i c.bunch})
    with
    | Not_found -> None
  
  (* move everything (as much as possible) from csrc to cdst *)
  let put_all csrc cdst =
    let rec next leftovers cs cd =
      if M.is_empty cs.bunch then (leftovers, cd)
      else 
      ( let i, bunch = M.choose cs.bunch in
        let cs1 = { cs with bunch = M.remove i cs.bunch } in 
        match put_bunch bunch cd with
          MoveBunchSuccess cd1 -> next leftovers cs1 cd1
        | MoveBunchFailure -> 
            ( match put_bunch bunch leftovers with
              | MoveBunchSuccess lo -> next lo cs1 cd
              | _ -> failwith "Cnt.put_all : cannot fit an object into the leftovers container" )
        | MoveBunchPartial (b, cd1) -> 
            ( match put_bunch b leftovers with
              | MoveBunchSuccess lo -> next lo cs1 cd1
              | _ -> failwith "Cnt.put_all : cannot fit an object into the leftovers container" )
      )
    in 
    let leftovers = {bunch = M.empty; slot = csrc.slot; caplim = csrc.caplim} in
    next leftovers csrc cdst
  
  let examine i c = 
      try Some (M.find i c.bunch) with
      | Not_found -> None
  
  let fold f acc c =
    M.fold (fun si bunch acc -> f acc si bunch) c.bunch acc

  let remove_everything c = 
    {c with bunch = M.empty}

  exception Compacting_failure

  (* move the items to the beginning of the list when possible *)
  let compact c = 
    try
      M.fold (fun si bunch acc -> 
        match put_bunch bunch acc with 
        | MoveBunchSuccess acc_upd -> acc_upd
        | _ -> raise Compacting_failure
      ) c.bunch (remove_everything c)
    with
      Compacting_failure -> c

  let is_empty c = M.cardinal c.bunch > 0

end

(* Collection of objects *)
module Coll = struct

  let upgrade_mat = function
    | Steel -> DmSteel
    | x -> x
  let downgrade_mat = function
    | Steel -> RustySteel
    | x -> x
  
  let rec prob_change_mat p change mat =
    let mat_upd = change mat in
    if Random.float 1.0 < p then
      (if mat_upd <> mat then prob_change_mat p change mat_upd else mat_upd)
    else mat

  let index kind size = 
    let y = match kind with
      | 0 -> 0
      | 1 -> 1
      | 2 -> 2
      | 3 -> 3
      | 4 -> 4
      | 5 -> 5
      | 6 -> 7
      | 7 -> 8
      | 8 -> 9
      | 9 -> 11
      | _ -> 16
    in
    y * 8 + size
  let stdprice size = max 1 (int_of_float (2.0 *. (4.0 ** float size)))

  let cheap_price = 6
    
  let sw_weight_0 = 0.5 
  let sw_weight_4 = 1.6 
  let sw_weight_power = 1.9
  let sw_weight_a, sw_weight_b = 
    sw_weight_0,
    (sw_weight_4 -. sw_weight_0) /. (4.0**sw_weight_power)

  let coin_barcode = {bc_kind=10; bc_size=0; bc_mat=Gold; bc_var=0;}

  let simple_random opt_kind =
    let kind = match opt_kind with 
      | None -> 
          any_from_rate_ls [(0, 8.0); (1, 8.0); (2, 2.0); (3, 8.0); (4, 7.0); (5, 1.0); 
            (6, 9.0) (* armor *); (7, 6.0) (* helmets *); 
            (8, 8.0); 
            (9, 12.0); (* ranged *)
            (10, 5.0) (* money *)
          ] 
      | Some x -> x 
    in
    let melee x d =
      `Melee Melee.({attrate=1.0 *. (x+.1.0); duration = (2.0 -. 1.0/.(x+.1.0) +. 0.1 *. x) *. d;}) in

    let sword_weight s = sw_weight_a +. sw_weight_b *. (s**sw_weight_power) in
    
    match kind with
      0 -> (* sword *)
        (* knife, dagger, short sword, arming sword, long sword (first two-handed), great sword, x, y*)
        let size = Random.int 8 in
        let price = stdprice size in
        let s = float size in
        (* 2kg for a long (two-handed sword) *)
        (* let weight = 0.5 +. 1.5 *. 0.25 *. 0.25 *. (s*.s) in *)
        let weight = sword_weight s in
        let mat = Steel in
        let barcode = {bc_kind=kind; bc_size=size; bc_mat=mat; bc_var=0;} in
        let prop = PS.empty 
          |> PS.add (melee s 1.0) 
          |> PS.add (`Weight (weight)) 
          |> PS.add `Wieldable
          |> PS.add (`Material mat) in
        {name = "Sword-"^(string_of_int size); prop; imgindex = index kind size; price; stackable = None; barcode }
    | 1 -> (* rogue / backsword *)
        let size = Random.int 8 in
        let price = stdprice size in
        let s = float size in
        let weight = (sword_weight s) *. 1.10 in
        let mat = Steel in 
        let barcode = {bc_kind=kind; bc_size=size; bc_mat=mat; bc_var=0;} in
        let prop = PS.empty 
          |> PS.add (melee (s *. 1.1) 1.0) 
          |> PS.add (`Weight (weight)) 
          |> PS.add `Wieldable 
          |> PS.add (`Material mat) in
        {name = "Backsword-"^(string_of_int size); prop; imgindex = index kind size; price; stackable = None; barcode }
    | 2 -> (* sabre *)
        let size = 2 + Random.int 2 in
        let price = stdprice size in
        let s = float size in
        let weight = (sword_weight s) *. 1.10 in
        let mat = Steel in 
        let barcode = {bc_kind=kind; bc_size=size; bc_mat=mat; bc_var=0;} in
        let prop = PS.empty 
          |> PS.add (melee (s *. 1.05) 1.0) 
          |> PS.add (`Defense (0.05 +. 0.01 *. float (size-2)))
          |> PS.add (`Weight (weight)) 
          |> PS.add `Wieldable 
          |> PS.add (`Material mat) in
        {name = "Sabre-"^(string_of_int size); prop; imgindex = index kind size; price; stackable = None; barcode }
    | 3 -> (* blunt weapons *)
        let size = Random.int 8 in
        let price = stdprice size in
        let s = float size in
        let weight = (sword_weight s) *. 1.2 in
        let mat = if size < 2 then Wood else Steel in 
        let barcode = {bc_kind=kind; bc_size=size; bc_mat=mat; bc_var=0;} in
        let prop = PS.empty 
          |> PS.add (melee (s*.1.1) 1.2)
          |> PS.add (`Weight (weight)) 
          |> PS.add `Wieldable 
          |> PS.add (`Material mat) in
        {name = "Mace-"^(string_of_int size); prop; imgindex = index kind size; price; stackable = None; barcode }
    | 4 -> (* axe *)
        let size = 1 + Random.int 7 in
        let price = stdprice size in
        let s = float size in
        let weight = (sword_weight s) *. 1.3 in
        let mat = Steel in 
        let barcode = {bc_kind=kind; bc_size=size; bc_mat=mat; bc_var=0;} in
        let prop = PS.empty
          |> PS.add (melee (s*.1.2) 1.3)
          |> PS.add (`Weight (weight)) 
          |> PS.add `Wieldable 
          |> PS.add (`Material mat) in
        {name = "Axe-"^(string_of_int size); prop; imgindex = index kind size; price; stackable = None; barcode }
    | 5 -> (* polearm *)
        let size = 4 + Random.int 3 in
        let price = stdprice (size-1) in
        let s = float size in
        let weight = (sword_weight s) *. 1.1 in
        let mat = Steel in 
        let barcode = {bc_kind=kind; bc_size=size; bc_mat=mat; bc_var=0;} in
        let prop = PS.empty
          |> PS.add (melee (s*.1.05) 1.05)
          |> PS.add (`Defense (0.08 +. 0.02 *. float (size-4)))
          |> PS.add (`Weight (weight)) 
          |> PS.add `Wieldable 
          |> PS.add (`Material mat) in
        {name = "Axe-"^(string_of_int size); prop; imgindex = index kind size; price; stackable = None; barcode }
    | 6 -> (* armor *)
        let size = 1 + Random.int 5 in
        let price = stdprice size * 2 in 
        let s = float size in
        let weight = (sword_weight s) *. 6.0 in
        let mat = if size < 2 then Leather else Steel in 
        let barcode = {bc_kind=kind; bc_size=size; bc_mat=mat; bc_var=0;} in
        let prop = PS.empty 
          |> PS.add (`Defense (0.05 +. 0.13 *. float size))
          |> PS.add (`Weight (weight)) 
          |> PS.add `Wearable
          |> PS.add (`Material mat) in
        let name = match size with 0 -> "Leather Armor" | 1 -> "Chain mail" | 2 -> "Plated mail" | 3 -> "Laminar armor" | _ -> "Plate armor" in
        {name; prop; imgindex = index kind size; price; stackable = None; barcode } 
    | 7 -> (* headgear *)
        let size = Random.int 6 in
        let price = stdprice size in 
        let s = float size in
        let weight = (sword_weight s) *. 2.0 in
        let mat = if size < 1 then Leather else Steel in 
        let barcode = {bc_kind=kind; bc_size=size; bc_mat=mat; bc_var=0;} in
        let prop = PS.empty 
          |> PS.add (`Defense (0.07 +. 0.06 *. float size))
          |> PS.add (`Weight (weight)) 
          |> PS.add `Headgear
          |> PS.add (`Material mat) in
        let name = match size with 0 -> "Leather Cap" | _ -> "Helmet" in
        {name; prop; imgindex = index kind size; price; stackable = None; barcode } 
    | 8 -> (* shield *)
        let size = 0 + Random.int 8 in
        let price = stdprice size in
        let s = float size in
        let weight = (sword_weight s) *. 1.1 in
        let mat = Steel in 
        let barcode = {bc_kind=kind; bc_size=size; bc_mat=mat; bc_var=0;} in
        let dd = if size > 1 then 0.05 else 0.0 in
        let prop = PS.empty
          |> PS.add (`Defense (0.08 +. 0.06 *. float size +. dd))
          |> PS.add (`Weight (weight)) 
          |> PS.add `Wieldable 
          |> PS.add (`Material mat) in
        let prop = match size with
          | 0 -> PS.add (melee (s*.0.5) 1.5) prop 
          | 1 -> PS.add (melee (s*.0.25) 1.5) prop 
          | _ -> prop in
        {name = "Shield-"^(string_of_int size); prop; imgindex = index kind size; price; stackable = None; barcode }
    
    | 9 -> (* ranged *)
        let size = Random.int 5 in
        let x = float size in
        let price = stdprice size in
        let s = float size in
        let weight = (sword_weight s) in
        let mat = if size < 1 then Leather else Wood in 
        let barcode = {bc_kind=kind; bc_size=size; bc_mat=mat; bc_var=0;} in
        let prop = PS.empty
          |> PS.add (`Ranged Ranged.(
            {force = 0.85 *. (2.0 +. 0.9 *. x); projmass = 0.13 *. (5.0 +. 2.2 *. x); dmgmult = 1.5 *. ( 2.5 +. 0.2 *. x )}))
          |> PS.add (`Weight (weight)) 
          |> PS.add `Wieldable 
          |> PS.add (`Material mat) in
        {name = "Ranged-"^(string_of_int size); prop; imgindex = index kind size; price; stackable = None; barcode }
    
    | _ -> (* coin *)
        let size = 0 in
        let price = 1 in
        let weight = 0.0 in
        let mat = Gold in
        let barcode = {bc_kind=kind; bc_size=size; bc_mat=mat; bc_var=0;} in
        assert (barcode = coin_barcode);
        let prop = PS.empty |> PS.add (`Money) |> PS.add (`Weight weight) |> PS.add (`Material mat) in
        {name = "Coin"; prop; imgindex = index kind size; price; stackable = Some 999999; barcode }
  
  let random opt_kind =
    let item = simple_random opt_kind in
    match get_mat item with
      Some mat ->
        let mat_u = mat 
          |> prob_change_mat 0.1 upgrade_mat
          |> prob_change_mat 0.4 downgrade_mat in
        if mat_u <> mat then
          upgrade_item (mat,mat_u) item
        else
          item
    | None -> item

  let coin = 
    let coin = random (Some 10) in
    assert (coin.barcode = coin_barcode);
    coin

end

let decompose obj = Resource.make (obj.price)

let decompose_bunch bunch = Resource.make (bunch.Cnt.item.price * bunch.Cnt.amount)

