(* Watch module for auto-regenerating on markdown changes using inotify *)

let watch_directory dir callback =
  let inotify = Inotify.create () in
  let rec add_watches path =
    let wd = Inotify.add_watch inotify path [Inotify.S_Modify; Inotify.S_Create; Inotify.S_Move] in
    (* Also watch subdirectories *)
    if Sys.is_directory path then begin
      let entries = Sys.readdir path in
      Array.iter (fun entry ->
        let full_path = Filename.concat path entry in
        if Sys.is_directory full_path && entry <> "." && entry <> ".." then
          ignore (add_watches full_path)
      ) entries
    end;
    wd
  in
  
  let _ = add_watches dir in
  
  (* Event loop *)
  let rec event_loop last_event_time =
    let events = Inotify.read inotify in
    let now = Unix.gettimeofday () in
    
    (* Debounce: ignore events within 0.5 seconds of last event *)
    if now -. last_event_time > 0.5 then begin
      let has_md_changes = List.exists (fun (_, _, _, filename_opt) ->
        match filename_opt with
        | Some filename -> 
            let len = String.length filename in
            len > 3 && String.sub filename (len - 3) 3 = ".md"
        | None -> false
      ) events in
      
      if has_md_changes then begin
        Printf.printf "\n[%s] Markdown file changed, regenerating...\n" 
          (Unix.time () |> Unix.localtime |> fun tm -> 
            Printf.sprintf "%02d:%02d:%02d" tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec);
        flush stdout;
        callback ();
        event_loop now
      end else
        event_loop last_event_time
    end else
      event_loop last_event_time
  in
  
  Printf.printf "👀 Watching for changes in: %s\n" dir;
  Printf.printf "Press Ctrl+C to stop...\n\n";
  flush stdout;
  
  try
    event_loop 0.0
  with
  | Unix.Unix_error (Unix.EINTR, _, _) ->
      Printf.printf "\nWatch stopped.\n";
      Inotify.rm_watch inotify (Inotify.add_watch inotify dir [])

let watch_and_regenerate config_file repo_names output_dir only exclude =
  let config_dir = Filename.dirname config_file in
  
  let regenerate () =
    try
      (* Load config fresh each time to pick up any changes *)
      let env = Dotenv.load config_dir in
      let owner = Dotenv.get_owner env in
      let config = Config.load_config config_file owner in
      let all_files = Selector.collect_all_repos_files config.Config.repos in
      let repo_filtered = Selector.filter_by_repos all_files repo_names in
      let selected = Selector.filter_files repo_filtered only exclude in
      
      if selected = [] then
        Printf.printf "  No files selected.\n"
      else begin
        (* Group selected files by repo *)
        let by_repo = List.fold_left (fun acc (repo_name, path) ->
          let existing = try List.assoc repo_name acc with Not_found -> [] in
          (repo_name, path :: existing) :: (List.remove_assoc repo_name acc)
        ) [] selected in
        
        (* Generate for each repo *)
        List.iter (fun (repo_name, paths) ->
          try
            let repo = List.find (fun r -> r.Config.name = repo_name) config.repos in
            let dir = match output_dir with
              | Some d -> d
              | None -> match Dotenv.get_local_path env repo_name with
                | Some d -> d
                | None -> 
                    if Dotenv.is_this_repo repo_name then "."
                    else failwith (Printf.sprintf "DOCDRIVEN_%s_LOCAL not found in .env" repo_name)
            in
            let output_path = 
              if Dotenv.is_this_repo repo_name && not (Filename.is_relative dir |> not) then
                if dir = "." then config.config_dir else Filename.concat config.config_dir dir
              else dir
            in
            Generator.generate output_path config.config_dir config.owner repo.tree paths;
            Printf.printf "  ✓ [%s] Generated %d files\n" repo_name (List.length paths);
            flush stdout
          with
          | Not_found -> Printf.eprintf "  ✗ Repo '%s' not found in config\n" repo_name
          | Failure msg -> Printf.eprintf "  ✗ [%s] Error: %s\n" repo_name msg
        ) by_repo
      end
    with
    | Failure msg -> Printf.eprintf "  ✗ Error: %s\n" msg
    | Sys_error msg -> Printf.eprintf "  ✗ System error: %s\n" msg
  in
  
  (* Initial generation *)
  Printf.printf "Initial generation...\n";
  regenerate ();
  Printf.printf "\n";
  
  (* Start watching *)
  watch_directory config_dir regenerate
