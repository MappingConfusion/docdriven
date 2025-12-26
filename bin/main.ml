open Cmdliner

let get_selected_files config repo_names interactive only_patterns exclude_patterns =
  let all_files = Docdriven.Selector.collect_all_repos_files config.Docdriven.Config.repos in
  let repo_filtered = Docdriven.Selector.filter_by_repos all_files repo_names in
  let filtered = Docdriven.Selector.filter_files repo_filtered only_patterns exclude_patterns in
  if interactive && filtered <> [] then
    Docdriven.Interactive.select_files filtered
  else
    filtered

let find_repo config repo_name =
  try
    List.find (fun r -> r.Docdriven.Config.name = repo_name) config.Docdriven.Config.repos
  with Not_found ->
    failwith (Printf.sprintf "Repo '%s' not found in config" repo_name)

let push_local config_file repo_names output_dir interactive only exclude =
  try
    let config_dir = Filename.dirname config_file in
    let env = Docdriven.Dotenv.load config_dir in
    let owner = Docdriven.Dotenv.get_owner env in
    let config = Docdriven.Config.load_config config_file owner in
    let selected = get_selected_files config repo_names interactive only exclude in
    if selected = [] then begin
      Printf.printf "No files selected.\n";
      0
    end else begin
      (* Group selected files by repo *)
      let by_repo = List.fold_left (fun acc (repo_name, path) ->
        let existing = try List.assoc repo_name acc with Not_found -> [] in
        (repo_name, path :: existing) :: (List.remove_assoc repo_name acc)
      ) [] selected in
      
      (* Generate for each repo *)
      List.iter (fun (repo_name, paths) ->
        let repo = find_repo config repo_name in
        let dir = match output_dir with
          | Some d -> d
          | None -> match Docdriven.Dotenv.get_local_path env repo_name with
            | Some d -> d
            | None -> failwith (Printf.sprintf "DOCDRIVEN_%s_LOCAL not found in .env" repo_name)
        in
        Docdriven.Generator.generate dir config.config_dir config.owner repo.tree paths;
        Printf.printf "[%s] Generated %d files in: %s\n" repo_name (List.length paths) dir
      ) by_repo;
      0
    end
  with
  | Failure msg ->
      Printf.eprintf "Error: %s\n" msg;
      1
  | Sys_error msg ->
      Printf.eprintf "System error: %s\n" msg;
      1

let push_github config_file repo_names token interactive only exclude =
  try
    let config_dir = Filename.dirname config_file in
    let env = Docdriven.Dotenv.load config_dir in
    let owner = Docdriven.Dotenv.get_owner env in
    let config = Docdriven.Config.load_config config_file owner in
    let selected = get_selected_files config repo_names interactive only exclude in
    if selected = [] then begin
      Printf.printf "No files selected.\n";
      0
    end else begin
      (* Group selected files by repo *)
      let by_repo = List.fold_left (fun acc (repo_name, path) ->
        let existing = try List.assoc repo_name acc with Not_found -> [] in
        (repo_name, path :: existing) :: (List.remove_assoc repo_name acc)
      ) [] selected in
      
      (* Push each repo to GitHub *)
      List.iter (fun (repo_name, paths) ->
        let repo = find_repo config repo_name in
        let gh_token = match token with 
          | Some t -> t 
          | None -> match Docdriven.Dotenv.get_github_token env repo_name with
            | Some t -> t
            | None -> failwith (Printf.sprintf "GitHub token not found. Set DOCDRIVEN_%s_GITHUB or DOCDRIVEN_GITHUB in .env, or use --token" repo_name)
        in
        let owner, repo_gh = match Docdriven.Dotenv.get_github_repo env repo_name with
          | Some (o, r) -> (o, r)
          | None -> failwith (Printf.sprintf "GitHub repo not found. Set DOCDRIVEN_%s_GITHUB_REPO=owner/repo in .env" repo_name)
        in
        let gh_config = { Docdriven.Github.token = gh_token; owner; repo = repo_gh } in
        match Lwt_main.run (Docdriven.Github.push gh_config repo.tree config.config_dir config.owner paths) with
        | Ok () ->
            Printf.printf "[%s] Pushed %d files to GitHub: https://github.com/%s/%s\n" repo_name (List.length paths) owner repo_gh
        | Error msg ->
            Printf.eprintf "[%s] Error: %s\n" repo_name msg
      ) by_repo;
      0
    end
  with
  | Failure msg ->
      Printf.eprintf "Error: %s\n" msg;
      1
  | Sys_error msg ->
      Printf.eprintf "System error: %s\n" msg;
      1

let push_auto config_file repo_names output_dir token interactive only exclude =
  let config_dir = Filename.dirname config_file in
  let env = Docdriven.Dotenv.load config_dir in
  let owner = Docdriven.Dotenv.get_owner env in
  let config = Docdriven.Config.load_config config_file owner in
  let env = Docdriven.Dotenv.load config.config_dir in
  
  (* Check if we have local or GitHub setup for any of the target repos *)
  let target_repos = if repo_names = [] then 
    List.map (fun r -> r.Docdriven.Config.name) config.repos 
  else 
    repo_names 
  in
  
  let has_local = output_dir <> None || 
    List.exists (fun name -> Docdriven.Dotenv.get_local_path env name <> None) target_repos in
  let has_github = token <> None || 
    List.exists (fun name -> 
      Docdriven.Dotenv.get_github_token env name <> None
    ) target_repos in
  
  match has_local, has_github with
  | true, _ -> push_local config_file repo_names output_dir interactive only exclude
  | false, true -> push_github config_file repo_names token interactive only exclude
  | false, false -> push_local config_file repo_names output_dir interactive only exclude

let list_files config_file repo_names =
  try
    let config = Docdriven.Config.load_config config_file None in
    let all_files = Docdriven.Selector.collect_all_repos_files config.repos in
    let filtered = Docdriven.Selector.filter_by_repos all_files repo_names in
    
    if repo_names = [] then
      Printf.printf "Files in configuration (%d total across %d repos):\n\n" 
        (List.length filtered) (List.length config.repos)
    else
      Printf.printf "Files in selected repos (%d total):\n\n" (List.length filtered);
    
    (* Group by repo for display *)
    let by_repo = List.fold_left (fun acc (repo_name, path) ->
      let existing = try List.assoc repo_name acc with Not_found -> [] in
      (repo_name, path :: existing) :: (List.remove_assoc repo_name acc)
    ) [] filtered in
    
    List.iter (fun (repo_name, paths) ->
      Printf.printf "[%s] (%d files):\n" repo_name (List.length paths);
      List.iter (fun path -> Printf.printf "  %s\n" path) (List.rev paths);
      Printf.printf "\n"
    ) by_repo;
    0
  with
  | Failure msg ->
      Printf.eprintf "Error: %s\n" msg;
      1
  | Sys_error msg ->
      Printf.eprintf "System error: %s\n" msg;
      1

let unassigned_blocks config_file limit =
  try
    let config = Docdriven.Config.load_config config_file None in
    let limit_value = match limit with
      | None -> Some 10
      | Some 0 -> None
      | Some n -> Some n
    in
    let (total, unassigned_count, percentage, blocks) = 
      Docdriven.Parser.find_unassigned config.config_dir config limit_value in
    
    Printf.printf "Codeblock Coverage Analysis:\n";
    Printf.printf "─────────────────────────────────────────────────\n";
    Printf.printf "Total codeblocks:      %d\n" total;
    Printf.printf "Assigned codeblocks:   %d\n" (total - unassigned_count);
    Printf.printf "Unassigned codeblocks: %d (%.1f%%)\n\n" unassigned_count percentage;
    
    if unassigned_count = 0 then begin
      Printf.printf "✓ All codeblocks are assigned!\n";
      0
    end else begin
      let showing = List.length blocks in
      if showing < unassigned_count then
        Printf.printf "Showing first %d unassigned codeblocks:\n\n" showing
      else
        Printf.printf "Unassigned codeblocks:\n\n";
      
      (* Group by file for better readability *)
      let by_file = List.fold_left (fun acc block ->
        let existing = try List.assoc block.Docdriven.Parser.ref_file acc with Not_found -> [] in
        (block.ref_file, block :: existing) :: (List.remove_assoc block.ref_file acc)
      ) [] blocks in
      
      List.iter (fun (file, file_blocks) ->
        Printf.printf "%s:\n" file;
        List.iter (fun block ->
          Printf.printf "  %s[%s][%d]\n" 
            block.Docdriven.Parser.ref_file 
            block.ref_language 
            block.ref_index
        ) (List.rev file_blocks);
        Printf.printf "\n"
      ) (List.rev by_file);
      
      if showing < unassigned_count then
        Printf.printf "Use --limit 0 to show all %d unassigned codeblocks\n" unassigned_count;
      
      0
    end
  with
  | Failure msg ->
      Printf.eprintf "Error: %s\n" msg;
      1
  | Sys_error msg ->
      Printf.eprintf "System error: %s\n" msg;
      1

let validate_config config_file =
  try
    let config = Docdriven.Config.load_config config_file None in
    let errors = Docdriven.Validator.validate_config config in
    Docdriven.Validator.print_results errors
  with
  | Failure msg ->
      Printf.eprintf "Error: %s\n" msg;
      1
  | Sys_error msg ->
      Printf.eprintf "System error: %s\n" msg;
      1

let check_conflicts config_file output_dir =
  try
    let config_dir = Filename.dirname config_file in
    let env = Docdriven.Dotenv.load config_dir in
    let owner = Docdriven.Dotenv.get_owner env in
    let config = Docdriven.Config.load_config config_file owner in
    let conflicts = Docdriven.Validator.check_ownership_conflicts config output_dir in
    if conflicts = [] then begin
      Printf.printf "✅ No ownership conflicts found.\n";
      Printf.printf "Owner: %s\n" config.owner;
      0
    end else begin
      Printf.printf "⚠️  Found %d ownership conflict(s):\n\n" (List.length conflicts);
      List.iter (fun err ->
        Printf.printf "%s\n" (Docdriven.Validator.string_of_error err)
      ) conflicts;
      Printf.printf "\n";
      1
    end
  with
  | Failure msg ->
      Printf.eprintf "Error: %s\n" msg;
      1
  | Sys_error msg ->
      Printf.eprintf "System error: %s\n" msg;
      1

let config_arg =
  let doc = "Path to the configuration file (default: docdriven.json)" in
  Arg.(value & pos 0 string "docdriven.json" & info [] ~docv:"CONFIG" ~doc)

let repos_arg =
  let doc = "Repository names to operate on (e.g., BACKEND FRONTEND). If omitted, operates on all repos." in
  Arg.(value & pos_right 0 string [] & info [] ~docv:"REPOS" ~doc)

let output_arg =
  let doc = "Output directory for local generation" in
  Arg.(value & opt (some string) None & info ["o"; "output"] ~docv:"DIR" ~doc)

let token_arg =
  let doc = "GitHub personal access token" in
  Arg.(value & opt (some string) None & info ["t"; "token"] ~docv:"TOKEN" ~doc)

let interactive_arg =
  let doc = "Interactively select files to generate" in
  Arg.(value & flag & info ["i"; "interactive"] ~doc)

let only_arg =
  let doc = "Only generate files matching pattern (can be repeated)" in
  Arg.(value & opt_all string [] & info ["only"] ~docv:"PATTERN" ~doc)

let exclude_arg =
  let doc = "Exclude files matching pattern (can be repeated)" in
  Arg.(value & opt_all string [] & info ["exclude"] ~docv:"PATTERN" ~doc)

let limit_arg =
  let doc = "Limit number of results (0 for unlimited, default: 10)" in
  Arg.(value & opt (some int) None & info ["limit"] ~docv:"N" ~doc)

let push_local_cmd =
  let doc = "generate repository locally" in
  let info = Cmd.info "local" ~doc in
  Cmd.v info Term.(const push_local $ config_arg $ repos_arg $ output_arg $ interactive_arg $ only_arg $ exclude_arg)

let push_github_cmd =
  let doc = "push repository to GitHub" in
  let info = Cmd.info "github" ~doc in
  Cmd.v info Term.(const push_github $ config_arg $ repos_arg $ token_arg $ interactive_arg $ only_arg $ exclude_arg)

let list_cmd =
  let doc = "list all files in configuration" in
  let info = Cmd.info "list" ~doc in
  Cmd.v info Term.(const list_files $ config_arg $ repos_arg)

let unassigned_cmd =
  let doc = "find unassigned codeblocks in documentation" in
  let info = Cmd.info "unassigned" ~doc in
  Cmd.v info Term.(const unassigned_blocks $ config_arg $ limit_arg)

let validate_cmd =
  let doc = "validate all references in configuration" in
  let info = Cmd.info "validate" ~doc in
  Cmd.v info Term.(const validate_config $ config_arg)

let conflicts_cmd =
  let doc = "check for ownership conflicts with existing files" in
  let info = Cmd.info "conflicts" ~doc in
  Cmd.v info Term.(const check_conflicts $ config_arg $ Arg.(required & opt (some string) None & info ["o"; "output"] ~docv:"DIR" ~doc:"Output directory to check"))

let push_group =
  let doc = "push repository to targets" in
  let info = Cmd.info "push" ~doc in
  Cmd.group info [push_local_cmd; push_github_cmd] ~default:(Term.(const push_auto $ config_arg $ repos_arg $ output_arg $ token_arg $ interactive_arg $ only_arg $ exclude_arg))

let default_cmd =
  let doc = "generate repository structures from documented codeblocks" in
  let info = Cmd.info "docdriven" ~version:"0.1.0" ~doc in
  Cmd.group info [push_group; list_cmd; unassigned_cmd; validate_cmd; conflicts_cmd]

let () = exit (Cmd.eval' default_cmd)
