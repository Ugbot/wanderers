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


(* Organizations *)

(*
 
 - unique persons, 
    transparent incluseion of these uniques in the economic model
 - production of items, technological development
 - spreading of items?
 - shops
 - rumors generation and spreading
 - self-organizing groups
    - defend population
    - collect taxes
    - war with neighbors for territory

 *)

open Base
open Common
open Global


(* generate a random unit core from rm *)
let get_random_unit_core pol rm =
  (* take into account only unallocated movables *)
  let fac_arr = rm.RM.lat.Mov.fac in
 
  let total = Array.fold_left (fun sum v -> sum + v) 0 fac_arr in

  if total <= 0 then None
  else
  ( let facnum = Array.length fac_arr in
    let rec next v fac = 
      if fac < facnum then 
      ( let x = v - fac_arr.(fac) in
        if x <= 0 then fac else next x (fac+1) )
      else
        failwith "Org.random_unit_core: bad number of units"
    in
    let fac = next (Random.int total) 0 in
    let res = rm.RM.lat.Mov.res in
    match any_from_ls pol.Pol.prop.(fac).Pol.speciesls with 
      Some sp -> Some (Unit.Core.make_res fac sp None res)
    | _ -> None
  )


module Actor = struct
  type cl = 
    Merchant of Item.Cnt.t | Craftsman | Defender | Adventurer | Prophet

  type id = int  
  (* notable / actor units *)
  type t = {aid: id; core: Unit.Core.t; rid: region_id; cl: cl;}

  let id_counter = ref 0 
  let gen_id () = 
    let x = !id_counter in
    id_counter := x + 1;
    x

  let make rid fac sp cl = 
    let core = Unit.Core.make fac sp None in
    {aid = gen_id(); core; rid; cl;}
   
  let make_from_core rid core cl =
    {aid = gen_id(); core; rid = rid; cl = cl;}

  let update_core a core = {a with core}

  let decompose a = Unit.Core.decompose a.core
    (* items of a merchant don't get decomposed? *)

  let get_rid a = a.rid
  let get_aid a = a.aid
  let get_core a = a.core

  let make_unit a loc = 
    let u = Unit.make_core (get_core a) None loc in
    Unit.({u with optaid = Some (get_aid a)})
end

module Ma = Map.Make(struct type t = Actor.id let compare = compare end)
module Sa = Set.Make(struct type t = Actor.id let compare = compare end)

(* Bin Weighted Counter - for log-time random selection/update *)
module Bwc = struct
  type t = {sum: float array; cur: float array; total: float}

  (* 8 -> 9 -> 11 -> 15 -> 31 -> ... *)
  let rec next x = if x land 1 = 1 then ((next (x asr 1)) lsl 1 + 1) else x + 1 
  
  let make size = {sum = Array.make size 0.0; cur = Array.make size 0.0; total = 0.0 }

  let rec propagate bwc i wg =
    bwc.sum.(i) <- bwc.sum.(i) +. wg;
    let i' = next i in
    if i' < Array.length bwc.sum then
      propagate bwc i' wg 

  let add i wg bwc = 
    bwc.cur.(i) <- bwc.cur.(i) +. wg;
    propagate bwc i wg;
    {bwc with total = bwc.total +. wg}

  (* locate the bin containing x *)
  let binary_search bwc x =
    let top = Array.length bwc.sum in

    let rec search x di =
      if di < top then
      ( let (i, wg) = search x (di lsl 1 + 1) in
        let i' = (i + 1) lor di in
        if i' < top then
        ( let wg' = wg +. bwc.sum.(i') in
          if wg' -. bwc.cur.(i') < x then
            (i', wg')
          else
            (i, wg)
        ) 
        else
          (i, wg)
      )
      else
        (0, 0.0)
    in
    fst(search x 0)

  let random bwc = binary_search bwc (Random.float bwc.total)
end

module Astr = struct
  (* 
   ma is the map aid -> actor
   regsa.(rid) is the set of aid at the region 
  *)
  type t = { ma : Actor.t Ma.t; regsa : Sa.t array; counter: Bwc.t }

  let make_empty regnum = {ma = Ma.empty; regsa = Array.make regnum Sa.empty; counter = Bwc.make regnum}

  let get aid astr = if Ma.mem aid astr.ma then Some (Ma.find aid astr.ma) else None


  let counter_dval = 1.0

  let update a astr =
    match get a.Actor.aid astr with
      Some aold ->
        let ma = Ma.add a.Actor.aid a astr.ma in
        (* update region's aid sets *)
        let counter' =
          if a.Actor.rid <> aold.Actor.rid then
          ( let saold' = Sa.remove aold.Actor.aid astr.regsa.(aold.Actor.rid) in
            astr.regsa.(aold.Actor.rid) <- saold';
            
            let sanew' = Sa.add a.Actor.aid astr.regsa.(a.Actor.rid) in
            astr.regsa.(a.Actor.rid) <- sanew';

            astr.counter 
            |> Bwc.add aold.Actor.rid (-.counter_dval)
            |> Bwc.add a.Actor.rid (counter_dval)
          )
          else
            astr.counter
        in
        {astr with ma; counter = counter'}
    | None ->
        let ma = Ma.add a.Actor.aid a astr.ma in
        let sanew' = Sa.add a.Actor.aid astr.regsa.(a.Actor.rid) in
        astr.regsa.(a.Actor.rid) <- sanew';
        let counter' =
          astr.counter 
          |> Bwc.add a.Actor.rid (counter_dval) in
        {astr with ma; counter = counter'}

  let remove a astr =
    let sa' = Sa.remove a.Actor.aid astr.regsa.(a.Actor.rid) in
    astr.regsa.(a.Actor.rid) <- sa';
    let ma = Ma.remove a.Actor.aid astr.ma in
    let counter' = 
      astr.counter 
      |> Bwc.add a.Actor.rid (-.counter_dval) in
    {astr with ma; counter = counter'}

  let get_actors_num astr = Ma.cardinal astr.ma

  let get_actors_num_at rid astr = Sa.cardinal (astr.regsa.(rid))
  
  let get_random_from rid astr =
    let sa = astr.regsa.(rid) in
    let num = Sa.cardinal sa in
    if num > 0 then
    ( let x = Random.int num in
      let _, res = Sa.fold (fun aid -> function (i, None) when i = x -> (i+1, Some aid) | (i,acc) -> (i+1,acc)) sa (0,None) in
      match res with
        Some aid -> Some (Ma.find aid astr.ma) 
      | None -> None
    )
    else
      None

  let get_random astr = 
    let rid = Bwc.random astr.counter in
    get_random_from rid astr

  (* add a new actor (creation is not guaranteed) *) 
  let add_new_actor pol (g, astr) =
    let rid = Random.int (Array.length g.G.rm) in

    let core_satisfies core =
      let gen, _ = Unit.Core.get_sp core in
      match gen with
        Species.Cow | Species.Horse | Species.Wolf -> false
      | _ -> true
    in

    match Prio.get rid g.G.prio with
      Some _ -> (g, astr)
    | None ->
        let facnum = fnum g in
        let total_pop = fold_lim (fun sum i -> sum + fget g rid i) 0 0 (facnum-1) in
        let total_actors = get_actors_num_at rid astr in
        if total_actors + total_pop > 0 && total_pop > total_actors && 
          Random.int (total_pop) > total_actors then
          (g, astr)
        else
        ( match get_random_unit_core pol (g.G.rm.(rid)) with
          | Some (core, lat_res_left) when core_satisfies core ->
              rset_lat g rid lat_res_left;

              let a = Actor.make_from_core rid core Actor.Adventurer in
              let faction = Unit.Core.get_faction core in
              let pop_lat = fget_lat g rid faction in
              fset_lat g rid faction (max 0 (pop_lat-1));
              (g, update a astr)
          | _ -> (g,astr)
        )

  let fold_at rid f acc astr =
    let sa = astr.regsa.(rid) in
    Sa.fold (fun aid acc -> match get aid astr with Some a -> f acc a | None -> acc) sa acc 


  let move_actor a nrid astr = 
    let a_upd = Actor.({a with rid = nrid}) in
    update a_upd astr

  (* updates only existing actors *)
  let update_from_unit u rid astr =
    match Unit.get_optaid u with
      Some aid ->
        ( match get aid astr with
          | Some a -> 
              let a_upd = Actor.update_core a (Unit.get_core u) in
              move_actor a_upd rid astr
          | None -> 
              (* failwith "Astr.update_from_unit: actor does not exist" *)
              astr
        )
    | None -> astr
  
  let remove_from_unit u astr =
    match Unit.get_optaid u with
    | Some aid ->
        ( match get aid astr with
          | Some a -> remove a astr
          | None -> 
              (* failwith "Astr.remove_from_unit: actor does not exist" *)
              astr
        )
    | None -> astr
end


module UC = Unit.Core
(* fake fight simulation  *)
let fake_fight core1 core2 =
(*
  let msg_melee = [| "  X"; "X  " |] in
  let msg_ranged = [| ">-X"; "X-<" |] in
  let msg_move = [| " >>"; "<< " |] in
*)
  let precomp c =
    let melee_strike_mult_wait = 
      let dur = (UC.get_melee c).Item.Melee.duration in
      ( 0.2 *. UC.get_athletic c *. dur,
        (UC.get_melee c).Item.Melee.attrate,
        UC.get_default_wait c +. dur )
    in
    let ranged_strike_mult_wait = 
      match UC.get_ranged c with 
        Some rng -> 
          true,
          ( rng.Item.Ranged.force *. (0.5 *. (1.0 +. 0.1 *. UC.get_athletic c)), 
            rng.Item.Ranged.dmgmult,
            UC.get_default_ranged_wait c )
      | None -> false, (0.0, 0.0, UC.get_default_wait c)
    in
    let speed = 5.0 *. UC.get_athletic c /. UC.get_total_mass c in
    let step_dur = UC.get_default_wait c in
    (melee_strike_mult_wait, 
     ranged_strike_mult_wait, speed, step_dur) 
  in
  
  let (m1,(has_ranged1,r1),speed1, step_dur1) as params1 = precomp core1 in
  let (m2,(has_ranged2,r2),speed2, step_dur2) as params2 = precomp core2 in

  let do_damage (strk, mult, wait) (cs, ct) = 
    let dtime, ct' = (wait, UC.damage strk mult ct) in
    dtime, (cs, ct') in

  let do_move speed step_dur c = -. speed *. step_dur in

  let do_something i dist (m, (has_ranged, r), speed, step_dur) cs ct =
    if dist > 0.0 then
    ( let (_, choose_melee, _) = m in
      let (_, choose_ranged, _) = r in
      let x = choose_ranged +. choose_melee in
      if has_ranged && Random.float x < choose_ranged then
      ( (* Printf.printf "%s\n" msg_ranged.(i); *)
        (0.0, do_damage r (cs,ct)) )
      else
      ( (* Printf.printf "%s\n" msg_move.(i); *)
        (do_move speed step_dur cs, (step_dur, (cs,ct))) )
    )
    else
    ( (* Printf.printf "%s\n" msg_melee.(i); *)
      (0.0, do_damage m (cs,ct)) )
  in

  let rec next (dist, t1, t2, (c1, c2)) =
    let uall =
      if t1 < t2 then
      ( let (ddist, (dtime, (c1', c2'))) = do_something 0 dist params1 c1 c2 in
        (dist+.ddist, t1+.dtime, t2, (c1', c2')) )
      else
      ( let (ddist, (dtime, (c2', c1'))) = do_something 1 dist params2 c2 c1 in
        (dist+.ddist, t1, t2+.dtime, (c1', c2')) )
    in
    let (_,_,_,(uc1,uc2)) = uall in 
    if UC.is_alive uc1 && UC.is_alive uc2 then next uall else uall
  in

  let t10 = Random.float (UC.get_reaction core1) in 
  let t20 = Random.float (UC.get_reaction core2) in 
  let (_, _, _, cc) = next (Random.float 4.0 +. 4.0, t10, t20, (core1, core2)) in
  cc

