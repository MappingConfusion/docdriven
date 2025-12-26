type validation_error =
  | MissingFile of string * string  (* source_ref, file_path *)
  | MissingCodeblock of string * string * int  (* source_ref, language, index *)
  | InvalidReference of string  (* source_ref *)
  | UnreadableFile of string * string  (* file_path, error *)
  | OwnershipConflict of string * string * string  (* file_path, existing_owner, new_owner *)
  | ThisRepoHasGithubConfig of string  (* repo_name *)

let string_of_error = function
  | MissingFile (ref, file) ->
      Printf.sprintf "❌ Missing file: %s (referenced as: %s)" file ref
  | MissingCodeblock (ref, lang, idx) ->
      Printf.sprintf "❌ Missing codeblock: [%s][%d] (referenced as: %s)" lang idx ref
  | InvalidReference ref ->
      Printf.sprintf "❌ Invalid reference format: %s" ref
  | UnreadableFile (file, err) ->
      Printf.sprintf "❌ Cannot read file: %s (%s)" file err
  | OwnershipConflict (file, existing, new_owner) ->
      Printf.sprintf "⚠️  Ownership conflict: %s (existing: %s, attempting: %s)" file existing new_owner
  | ThisRepoHasGithubConfig repo ->
      Printf.sprintf "⚠️  Invalid config: '%s' (THIS repo) should not have DOCDRIVEN_THIS_GITHUB_REPO in .env" repo

let validate_source_ref config_dir source_ref =
  match Parser.parse_source_ref source_ref with
  | None -> [InvalidReference source_ref]
  | Some parsed ->
      let full_path = Filename.concat config_dir parsed.file in
      if not (Sys.file_exists full_path) then
        [MissingFile (source_ref, full_path)]
      else
        try
          let content = In_channel.with_open_text full_path In_channel.input_all in
          match parsed.language, parsed.index with
          | None, None -> []  (* Whole file reference - always valid if file exists *)
          | Some language, Some index ->
              let blocks = Parser.extract_codeblocks content in
              (match List.assoc_opt language blocks with
               | None -> [MissingCodeblock (source_ref, language, index)]
               | Some lang_blocks ->
                   if index >= List.length lang_blocks then
                     [MissingCodeblock (source_ref, language, index)]
                   else
                     [])
          | _ -> [InvalidReference source_ref]
        with
        | Sys_error msg -> [UnreadableFile (full_path, msg)]
        | e -> [UnreadableFile (full_path, Printexc.to_string e)]

let rec validate_node config_dir rel_path = function
  | Config.File source ->
      (match source with
       | Config.Single s -> validate_source_ref config_dir s
       | Config.Multiple sources ->
           List.concat_map (validate_source_ref config_dir) sources)
  | Config.Directory items ->
      List.concat_map (fun (name, node) ->
        let new_rel_path = if rel_path = "" then name else rel_path ^ "/" ^ name in
        validate_node config_dir new_rel_path node
      ) items

let validate_repo config_dir repo =
  validate_node config_dir "" repo.Config.tree

let validate_this_repo_config env repos =
  (* Check that THIS repo doesn't have GitHub configuration *)
  List.filter_map (fun repo ->
    if Dotenv.is_this_repo repo.Config.name then
      match Dotenv.get_github_repo env repo.name with
      | Some _ -> Some (ThisRepoHasGithubConfig repo.name)
      | None -> None
    else
      None
  ) repos

let validate_config config =
  List.concat_map (validate_repo config.Config.config_dir) config.Config.repos

let print_results errors =
  if errors = [] then begin
    Printf.printf "✅ Validation passed! All references are valid.\n";
    0
  end else begin
    Printf.printf "❌ Validation failed with %d error(s):\n\n" (List.length errors);
    List.iter (fun err ->
      Printf.printf "%s\n" (string_of_error err)
    ) errors;
    Printf.printf "\n";
    1
  end

let check_ownership_conflicts config output_dir =
  let rec collect_files owner rel_path acc = function
    | Config.File _ ->
        if rel_path = "" then acc
        else (rel_path, owner) :: acc
    | Config.Directory items ->
        List.fold_left (fun acc (name, node) ->
          let new_rel_path = if rel_path = "" then name else rel_path ^ "/" ^ name in
          collect_files owner new_rel_path acc node
        ) acc items
  in
  
  let planned_files = List.concat_map (fun repo ->
    collect_files config.Config.owner "" [] repo.Config.tree
  ) config.Config.repos in
  
  List.filter_map (fun (rel_path, new_owner) ->
    let full_path = Filename.concat output_dir rel_path in
    match Comments.extract_owner_from_file full_path with
    | Some existing_owner when existing_owner <> new_owner ->
        Some (OwnershipConflict (rel_path, existing_owner, new_owner))
    | _ -> None
  ) planned_files
