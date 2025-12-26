let rec collect_files prefix = function
  | Config.File _ ->
      [prefix]
  | Config.Directory items ->
      List.concat_map (fun (name, node) ->
        let path = if prefix = "" then name else prefix ^ "/" ^ name in
        collect_files path node
      ) items

let collect_all_files tree =
  match tree with
  | Config.Directory items ->
      List.concat_map (fun (name, node) ->
        collect_files name node
      ) items
  | Config.File _ -> []

let collect_repo_files repo =
  let files = collect_all_files repo.Config.tree in
  List.map (fun path -> (repo.name, path)) files

let collect_all_repos_files repos =
  List.concat_map collect_repo_files repos

let matches_pattern pattern path =
  let regex_pattern = 
    pattern
    |> Str.quote
    |> Str.global_replace (Str.regexp_string "\\*") ".*"
  in
  try
    let _ = Str.search_forward (Str.regexp regex_pattern) path 0 in
    true
  with Not_found -> false

let should_include path includes excludes =
  let included = match includes with
    | [] -> true
    | patterns -> List.exists (fun p -> matches_pattern p path) patterns
  in
  let excluded = List.exists (fun p -> matches_pattern p path) excludes in
  included && not excluded

let filter_files files includes excludes =
  List.filter (fun (_, path) -> should_include path includes excludes) files

let filter_by_repos files repo_names =
  match repo_names with
  | [] -> files
  | names -> List.filter (fun (repo, _) -> List.mem repo names) files
