open Core.Std
open Async.Std
open Import

let get_description_exn maybe_archived_feature =
  let%map { description } =
    Feature_description.rpc_to_server_exn maybe_archived_feature
  in
  description
;;

let set_description_exn feature_path description =
  let updates = [ `Set_description description ] in
  let%bind responses =
    Change_feature.rpc_to_server_exn { feature_path; updates }
  in
  List.iter responses ~f:(fun (_, or_error) -> ok_exn or_error);
  return ()
;;

let edit =
  Command.async'
    ~summary:"edit description from your editor"
    (let open Command.Let_syntax in
     let%map_open () = return ()
     and feature_path = feature_path_or_current_bookmark in
     fun () ->
       let open! Deferred.Let_syntax in
       let feature_path = ok_exn feature_path in
       let%bind initial_description =
         get_description_exn { feature_spec = `Feature_path feature_path
                             ; namespace    = `Existing
                             }
       in
       let rec loop previous_description =
         let%bind new_description =
           Editor.invoke_editor previous_description
         in
         let new_description = ok_exn new_description in
         if String.equal new_description initial_description
         then (print_endline "You didn't change the description."; Deferred.unit)
         else (
           let rules = Pdiff4.User_config.get () |> Pdiff4.User_config.diff_config in
           print_endline (Patdiff_lib.Patdiff_core.patdiff ~rules ()
                            ~from_:{ name = "old"; text = initial_description }
                            ~to_:  { name = "new"; text = new_description });
           let module Choice = Interactive.Choice in
           match%bind
             Interactive.ask_dispatch_with_help "Accept the changes?"
               [ Choice.default (Choice.create 'y' `Yes "Accept the changes.")
               ; Choice.create 'n' `No "Decline the changes."
               ; Choice.create 'e' `Edit "Edit the description again."
               ]
           with
           | `No -> return ()
           | `Yes -> set_description_exn feature_path new_description
           | `Edit -> loop new_description)
       in
       loop initial_description)
;;

let set =
  Command.async'
    ~summary:"set description from stdin"
    (let open Command.Let_syntax in
     let%map_open () = return ()
     and feature_path = feature_path_or_current_bookmark in
     fun () ->
       let open! Deferred.Let_syntax in
       let feature_path = ok_exn feature_path in
       let%bind description = Reader.contents stdin in
       set_description_exn feature_path description
    )
;;

let show =
  Command.async'
    ~summary:"output description on stdout"
    (let open Command.Let_syntax in
     let%map_open () = return ()
     and maybe_archived_feature = maybe_archived_feature
     and do_not_show_comments =
       no_arg_flag "do-not-show-comments"
         ~doc:"filter out comments from the description"
     in
     fun () ->
       let open! Deferred.Let_syntax in
       let%map description =
         let%bind feature =
           Command.Param.resolve_maybe_archived_feature_spec_exn
             (ok_exn maybe_archived_feature)
         in
         get_description_exn feature
       in
       let description =
         if do_not_show_comments
         then Cmd_show.render_description description
         else description
       in
       let n = String.length description in
       if n = 0
       then print_string "<no description>\n"
       else (
         print_string description;
         if not (Char.equal description.[ n - 1 ] '\n') then print_newline ()))
;;

let command =
  Command.group ~summary:"manage the description of a feature"
    [ "edit", edit
    ; "set" , set
    ; "show", show
    ]
;;
