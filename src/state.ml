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
open Common
open Global

module CtrlM = struct
  type invclass = InvGround | InvUnit 
  type invprop = invclass*int*int*Unit.t*(Unit.t list)
  type openatlasprop = region_loc
  type t = 
    | Normal 
    | Target of (Unit.t list)
    | Look of (Unit.t list)
    | Inventory of invprop 
    | WaitInput of (Unit.t list)
    | OpenAtlas of openatlasprop * t    
    | Died of float
end

module Clock = struct
  type t = {full:int; fraction:float;}

  let zero = {full = 0; fraction = 0.0}

  let add dt c = 
    let x = c.fraction +. dt in
    let i = int_of_float (floor x) in
    {full = c.full + i; fraction = x -. float i}

  let get c = float c.full +. c.fraction
end

module Options = struct
  type t = {game_speed: int}

  let default = {game_speed = 0}

  let speedup ({game_speed}) = {game_speed = min (game_speed + 1) 10}
  let slowdown ({game_speed}) = {game_speed = max (game_speed - 1) (-10)}
end

type t =
  { target_cursor : loc;
    look_cursor : loc;
    cm : CtrlM.t;
    geo : G.geo; 
    controller_id: int;

    rem_dt : float;

    top_rem_dt: float;

    pol : Pol.t;

    astr: Org.Astr.t;

    vision : int Area.t;

    atlas : Atlas.t;

    clock : Clock.t;

    clock_last_alive_check : Clock.t;

    opts : Options.t;

    debug : bool
  }

let make w h debug = 
  let facnum = default_factions_number in
  let geo_w = 35 in
  let geo_h = 35 in
  let pol = Politics.make_variety facnum in
  let geo = Genmap.make_geo geo_w geo_h facnum in
  let astr = Org.Astr.make_empty (Array.length geo.G.rm) in
  let geo, astr = 
    let simulate speedup steps ga = fold_lim (fun ga _ -> ga |> Top.run speedup pol) ga 0 steps in
    let d = 30 in
    (geo, astr) 
    |> simulate  1.0 d
    |> simulate  2.0 d 
    |> simulate  4.0 d 
    |> simulate 16.0 d 
    |> simulate 32.0 (4*d) 
    |> simulate 16.0 d 
    |> simulate  8.0 d 
    |> simulate  4.0 d 
    |> simulate  2.0 d 
    |> simulate  1.0 d 
  in
  (* add the player *)
  (* find a good region *)
  let player_faction = match Random.int 5 with 0 -> 0 | 1 -> 2 | 2 -> 5 | 3 -> 7 | _ -> 10 in
  let new_currid = 
    let len = geo_w * geo_h in

    (* ok locations *)
    let find_good_rid () =
      let best_rid, best_val =
        let centerxy = 
          let sx,sy,n = 
            fold_lim (fun (sx,sy,n) i ->
              let z,(x,y) = geo.G.loc.(i) in
              if z = 0 then (sx+x, sy+y, n+1) else (sx,sy,n)
            ) (0,0,0) 0 (G.length geo - 1) in
          if n > 0 then
            (sx/n, sy/n)
          else
            (geo_w/2, geo_h/2) 
        in
        let md = loc_manhattan centerxy in
        fold_lim (fun (rid,v) i ->
          let rz,(rxy) = geo.G.loc.(i) in
          let centrality = 
            if rz = 0 then
              10.0 *. float (md - loc_manhattan (rxy -- centerxy)) /. float md
            else 0.0 in
          let friends = float (Global.fget geo i player_faction) in 
          let v' = friends +. centrality in
          if v' > v then
            (
              (*
              Printf.printf "(rid=%i, v=%f) %!" i v';
              *)
              (i,v')
            )
          else (rid,v)
        ) (Random.int len / 2, -1.0) 0 (G.length geo - 1) in
      best_rid
    in
    (*
    match any_from_ls ls with
      Some rid -> rid
    | _ ->
        find_good_rid ()
    *)

    find_good_rid()
  in
  (
    let z, (x,y) = geo.G.loc.(new_currid) in
    Printf.printf "new_currid = %i, z = %i, x = %i, y = %i\n%!" new_currid z x y;
  );
  let geo = {geo with G.currid = new_currid} in
  let geo = geo |> Globalmove.move pol astr South |> Globalmove.move pol astr North in 
  let reg = G.curr geo in
  let controller_id = 0 in
  let location = find_walkable_location_reg reg in
  
  (* player *)
  let player = 
    if false then
    ( (* ranged weapon *)
      let obj = Item.Coll.random (Some 6) in
      let u = Unit.make player_faction Species.(Hum,0) (Some controller_id) location in
      let ucore' = 
        match Inv.put_somewhere obj u.Unit.core.Unit.Core.inv with
          Some inv1 -> {u.Unit.core with Unit.Core.inv=inv1} 
        | _ -> u.Unit.core in
      Unit.adjust_aux_info {u with Unit.core = ucore'}
    )
    else
    ( let u, _ = Unit.make_res (Resource.make 50) player_faction Species.(Hum,0) (Some controller_id) location in
      u )
  in

  let reg' = {reg with R.e = E.upd player reg.R.e} in
  let geo' = G.upd reg' geo in

  let atlas = Atlas.make pol geo' in

  { 
    target_cursor = (w/2,h/2);
    look_cursor = (w/2,h/2);
    cm = CtrlM.Normal;
    geo = geo';
    rem_dt = 0.0;
    top_rem_dt = 0.0;
    controller_id = controller_id;
    pol = pol;
    astr;
    vision = (
      let a = (G.curr geo').R.a in
      Area.make (Area.w a) (Area.h a) 0 
    );
    atlas;
    clock = Clock.zero;
    clock_last_alive_check = Clock.zero;
    opts = Options.default;
    debug;
  }


let init seed b_debug =
  Random.init seed;
  make 25 16 b_debug


let init_full opt_string b_debug =
  let max_seed = 1000000000 in
  let seed =
    match opt_string with
    | Some s -> s
    | None ->

      let rnd_seed_string () =
        let len = 1 + Random.int 6 in
        let s = String.make len 'a' in
        for i = 0 to len-1 do 
          let c = Char.chr (Char.code 'a' + Random.int 26) in 
          (* Going to use String.set until version 4.02 is everywhere and we can move on to String.init *)
          s.[i] <- c
        done;
        Printf.printf "Random seed: %s\n%!" s;
        s
      in
      
      rnd_seed_string()
  in
  let hash_string s =
    Base.fold_lim (fun a i -> (a*256 + Char.code s.[i]) mod (max_seed/512)) 0 0 (String.length s - 1) 
  in
  init (hash_string seed) b_debug


let save_to_file s file = 
  let oc = open_out_bin file in
  output_value oc s;
  flush oc;
  close_out oc


let load_from_file file = 
  let ic = open_in_bin file in
  let s = input_value ic in
  close_in ic;
  s

module Msg = struct
  type t = Left | Right | Up | Down
    | Wait | Attack of int
    | Rest
    | Assign
    | OpenInventory
    | Cancel
    | Confirm
    | Num of int
    | Fire
    | Look
    | UpStairs
    | DownStairs
    | Atlas
    | ScrollForward
    | ScrollBackward

    | OptsSpeedup
    | OptsSlowdown
end

let respond s =
  let reg = G.curr s.geo in
  let validate ij = Area.put_inside reg.R.a ij in
  
  let meta_upd_one utl nue =
    let s' = {s with geo = G.upd {reg with R.e=nue} s.geo} in
    if utl <> [] then
      {s' with cm = CtrlM.WaitInput utl}
    else 
      {s' with cm = CtrlM.Normal}
  in

  let meta_upd_zero_action utl b_wait u' =
    let nue = E.upd u' reg.R.e in
    let s' = {s with geo = G.upd {reg with R.e=nue} s.geo} in
    if b_wait then
    ( if utl <> [] then
        {s' with cm = CtrlM.WaitInput utl}
      else 
        {s' with cm = CtrlM.Normal} )
    else
      {s' with cm = CtrlM.WaitInput (u'::utl)}
  in
  
  let to_normal s = {s with cm = CtrlM.Normal} in
          
  let fire u utl target = 
    let delaytime = Unit.get_default_ranged_wait u in
    meta_upd_one utl (E.upd {u with Unit.ac = 
        [ Timed(Some u.Unit.loc, 0.0, delaytime, Prepare(FireProj target))]
      } reg.R.e) in

  match s.cm with
  | CtrlM.Normal -> 
    ( function
      | _ -> to_normal s )
  | CtrlM.Target (u::utl) ->
    let upd_cursor dloc = {s with target_cursor = validate (s.target_cursor ++ dloc) } in
    ( function
        Msg.Left -> upd_cursor (-1,0)
      | Msg.Right -> upd_cursor (1,0)
      | Msg.Up -> upd_cursor (0,1)
      | Msg.Down -> upd_cursor (0,-1)
      | Msg.Fire when s.target_cursor <> u.Unit.loc -> fire u utl s.target_cursor
      | Msg.Cancel -> {s with cm = CtrlM.WaitInput (u::utl)} 
      | _ -> s
    )
  | CtrlM.Look (u::utl) ->
    let upd_cursor dloc = {s with look_cursor = validate (s.look_cursor ++ dloc) } in
    ( function
        Msg.Left -> upd_cursor (-1,0)
      | Msg.Right -> upd_cursor (1,0)
      | Msg.Up -> upd_cursor (0,1)
      | Msg.Down -> upd_cursor (0,-1)
      | Msg.Fire when s.look_cursor <> u.Unit.loc -> fire u utl s.look_cursor
      
      | Msg.Look | Msg.Confirm when s.look_cursor <> u.Unit.loc -> 

            let delaytime = Unit.get_default_wait u in
            meta_upd_one utl (E.upd {u with Unit.ac = 
                [ Timed(Some u.Unit.loc, 0.0, delaytime, Prepare(OperateObj (s.look_cursor, OpObjOpen)))]
              } reg.R.e) 

      | Msg.Cancel -> {s with cm = CtrlM.WaitInput (u::utl)} 
      | _ -> s
    )
  | CtrlM.Target [] -> ( function _ -> to_normal s )
  | CtrlM.Look [] -> ( function _ -> to_normal s )
  | CtrlM.WaitInput [] -> ( function _ -> to_normal s )
  | CtrlM.WaitInput (u::utl) ->

      (* helpers *)
      let upd_one = meta_upd_one utl in
      let move dl =
        let nloc = u.Unit.loc ++ dl in
        let nac = if true || is_walkable reg.R.a nloc then [Walk ([nloc], 0.0)] else [Wait (u.Unit.loc,0.0)] in
        let nue = E.upd {u with Unit.ac = nac} reg.R.e in
        upd_one nue
      in
      let wait () = 
        upd_one (E.upd {u with Unit.ac = [Wait (u.Unit.loc, 0.0)]} reg.R.e) 
      in

      (* main part *)
      ( function
          Msg.Left -> move (-1,0)
        | Msg.Right -> move (1,0) 
        | Msg.Up -> move (0,1)
        | Msg.Down -> move (0,-1)
        | Msg.Wait -> wait ()
        | Msg.Rest -> 
            upd_one ( E.upd {u with Unit.ac = [Timed (Some u.Unit.loc, 0.0, 10.0, Rest)]} reg.R.e )
        | Msg.Attack dir_index -> 
            let melee = Unit.get_melee u in
            let weapon_duration = melee.Item.Melee.duration in
            let tq = Fencing.get_tq u.Unit.fnctqn in
            let timed_action = Attack (tq, dir_index) in
            let duration = weapon_duration *. tq.Fencing.dur_mult in
            let updated_u = 
              {u with Unit.ac = [Timed (Some u.Unit.loc, 0.0, duration, timed_action)];
                Unit.fnctqn = Fencing.auto_switch u.Unit.fnctqn;
              } in
            upd_one ( E.upd updated_u reg.R.e )
        | Msg.OpenInventory 
        | Msg.Confirm ->
            {s with cm = CtrlM.Inventory (CtrlM.InvGround,0,0,u,utl)}
        | Msg.Fire ->
            {s with cm = CtrlM.Target (u::utl) }
        | Msg.Look ->
            {s with cm = CtrlM.Look (u::utl); look_cursor = u.Unit.loc }
        | Msg.DownStairs 
            when List.mem (R.Obj.StairsDown, u.Unit.loc) reg.R.obj.R.Obj.stairsls ->
              upd_one ( E.upd {u with Unit.ac = [Wait (u.Unit.loc,0.0)]; Unit.transfer = Some Down} reg.R.e )
        | Msg.UpStairs 
            when List.mem (R.Obj.StairsUp, u.Unit.loc) reg.R.obj.R.Obj.stairsls ->
              upd_one ( E.upd {u with Unit.ac = [Wait (u.Unit.loc,0.0)]; Unit.transfer = Some Up} reg.R.e )
        | Msg.ScrollForward -> 
            meta_upd_zero_action utl true 
              {u with Unit.ac = [Wait (u.Unit.loc,0.0)]; 
              Unit.fnctqn = Fencing.scroll_forward (Unit.get_fnctqn u)}
        | Msg.ScrollBackward -> 
            meta_upd_zero_action utl true
              {u with Unit.ac = [Wait (u.Unit.loc,0.0)]; 
              Unit.fnctqn = Fencing.scroll_backward (Unit.get_fnctqn u)}
        | Msg.OptsSpeedup -> {s with opts = Options.speedup s.opts}
        | Msg.OptsSlowdown -> {s with opts = Options.slowdown s.opts}
        | Msg.Atlas -> {s with cm = CtrlM.OpenAtlas (s.atlas.Atlas.curloc, s.cm) }
        | _ -> s
      )

  | CtrlM.Inventory (invclass, ic, ii, u, utl) ->
      (* Controls in the inventory mode *)

      (* finish inventory manipulation and return to 
         WaitInput state or Normal state (if no one is waiting for an input) *)
      let upd_one = meta_upd_one utl in
      let move_cursor (dic, dii) =
        let iirange x = min (max x 0) 11 in
        let upd = 
          let uii = iirange (ii+dii) in
          match invclass with
            CtrlM.InvUnit -> 
              let uic = ic + dic in
              if uic < 0 || uic > 1 then 
                (CtrlM.InvGround, 0, uii, u, utl) 
              else 
                (CtrlM.InvUnit, uic, uii, u, utl)
          | CtrlM.InvGround -> 
              if dic = 0 then (CtrlM.InvGround, 0, uii, u, utl) 
              else if dic > 0 then (CtrlM.InvUnit, 0, uii, u, utl) 
              else (CtrlM.InvUnit, 1, uii, u, utl)
        in
        {s with cm = CtrlM.Inventory upd}
      in
      (* helper *)
      let just_update_unit_inv upd_uinv =
        let upd_u = Unit.upd_inv upd_uinv u in
        let nue = E.upd upd_u reg.R.e in
        { s with geo = G.upd {reg with R.e=nue} s.geo;
            cm = CtrlM.Inventory (invclass, ic, ii, upd_u, utl); }
      in
      (* pickup from the ground *)
      let pickup (gci, gii) uci =
        let try_pickup = 
          let optinv = Area.get reg.R.optinv u.Unit.loc in
            Inv.ground_pickup gci gii optinv
        in
        match try_pickup with
          Some (obj, upd_optinv) ->
            ( match Inv.put obj uci u.Unit.core.Unit.Core.inv with 
                Some upd_uinv ->
                  ( Area.set reg.R.optinv u.Unit.loc upd_optinv;
                    just_update_unit_inv upd_uinv )
              | None -> s
            )
        | None -> s
      in
      (* drop an item *)
      let drop (uci, uii) gci =
        match Inv.get uci uii u.Unit.core.Unit.Core.inv with
          Some (obj, upd_uinv) ->
            ( match Inv.ground_drop obj (Area.get reg.R.optinv u.Unit.loc) with
                Some upd_optinv -> 
                  Area.set reg.R.optinv u.Unit.loc upd_optinv;
                  just_update_unit_inv upd_uinv 
              | None -> s
            )
        | None -> s
      in
      (* move an item within the same inventory *)
      let move (usci, usii) udci =
        match Inv.get usci usii u.Unit.core.Unit.Core.inv with
          Some (obj, upd_uinv) ->
            ( match Inv.put obj udci upd_uinv with
                Some (upd_upd_uinv) -> 
                  just_update_unit_inv upd_upd_uinv 
              | None -> s
            )
        | None -> s
      in
      ( function
          Msg.Left -> move_cursor (0,-1)
        | Msg.Right -> move_cursor (0,1) 
        | Msg.Up -> move_cursor (-1,0)
        | Msg.Down -> move_cursor (1,0)
        | Msg.Num 0 when invclass = CtrlM.InvUnit ->
            drop (ic,ii) 0
        | Msg.Num 1 when invclass = CtrlM.InvGround ->
            pickup (0,ii) 0
        | Msg.Num 1 when invclass = CtrlM.InvUnit && ic <> 0 ->
            move (ic,ii) 0
        | Msg.Num 2 when invclass = CtrlM.InvGround->
            pickup (0,ii) 1
        | Msg.Num 2 when invclass = CtrlM.InvUnit && ic <> 1 ->
            move (ic,ii) 1
        | Msg.Cancel ->
            (* compact the items on the ground *)
            ( match Area.get reg.R.optinv u.Unit.loc with
                Some inv -> 
                  let optinv_upd = Some (Inv.compact (fun _ _ -> true) inv) in
                  Area.set reg.R.optinv u.Unit.loc optinv_upd
              | _ -> () );
            (* compact unit's inventory *)
            let inv_upd = Inv.compact_simple (Unit.get_inv u) in
            let u_upd = Unit.upd_inv inv_upd u in
            upd_one (E.upd {u_upd with Unit.ac = [Wait (u.Unit.loc, 0.0)]} reg.R.e) 
        | _ -> s
      )
  | CtrlM.OpenAtlas ((z,(x,y)) as rloc, prev_cm) ->
      let move (dx,dy,dz) = 
        let rloc1 = (z+dz, (x+dx, y+dy)) in
        match Atlas.visible_rid_of_rloc s.atlas rloc1 with
        | Some rid ->
            {s with cm = CtrlM.OpenAtlas (rloc1, prev_cm)} 
        | None -> s
      in
      ( function
          Msg.Left -> move (-1,0,0)
        | Msg.Right -> move (1,0,0) 
        | Msg.Up -> move (0,1,0)
        | Msg.Down -> move (0,-1,0)
        | Msg.UpStairs -> move (0,0,1)
        | Msg.DownStairs -> move (0,0,-1)
        | Msg.Cancel -> {s with cm = prev_cm}
        | _ -> s
      )
  | CtrlM.Died t -> 
      ( function
          Msg.Confirm -> init_full None s.debug
        | _ -> s )

(* ~ game modes *)
type game_mode = Play of t | Exit

