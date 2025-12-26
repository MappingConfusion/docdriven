let ensure_directory path =
  let rec mkdir_p path =
    if not (Sys.file_exists path) then begin
      let parent = Filename.dirname path in
      if parent <> path then mkdir_p parent;
      Unix.mkdir path 0o755
    end
  in
  mkdir_p path

let extract_content config_dir source_str =
  match Parser.parse_source_ref source_str with
  | Some source_ref ->
      (match Parser.get_codeblock config_dir source_ref with
       | Some content -> content
       | None -> failwith (Printf.sprintf "Codeblock not found: %s" source_str))
  | None -> failwith (Printf.sprintf "Invalid source reference: %s" source_str)

let generate_file_content config_dir owner output_path source =
  let sources, content = match source with
    | Config.Single s -> 
        [s], extract_content config_dir s
    | Config.Multiple sources ->
        sources, (sources
                  |> List.map (extract_content config_dir)
                  |> String.concat "\n\n")
  in
  let header = Comments.generate_header output_path owner sources in
  header ^ content

let generate_file config_dir owner output_path source =
  let full_content = generate_file_content config_dir owner output_path source in
  let dir = Filename.dirname output_path in
  ensure_directory dir;
  Out_channel.with_open_text output_path (fun oc ->
    Out_channel.output_string oc full_content
  )

let rec collect_file_changes config_dir owner base_path rel_path allowed_files diffs = function
  | Config.File source ->
      if List.mem rel_path allowed_files then
        let new_content = generate_file_content config_dir owner base_path source in
        let change = if Sys.file_exists base_path then
          let old_content = In_channel.with_open_text base_path In_channel.input_all in
          if old_content = new_content then None
          else Some (Diff.Modified (old_content, new_content))
        else
          Some (Diff.Added new_content)
        in
        match change with
        | Some ch -> { Diff.path = base_path; change = ch } :: diffs
        | None -> diffs
      else diffs
  | Config.Directory items ->
      List.fold_left (fun acc (name, node) ->
        let full_path = Filename.concat base_path name in
        let new_rel_path = if rel_path = "" then name else rel_path ^ "/" ^ name in
        collect_file_changes config_dir owner full_path new_rel_path allowed_files acc node
      ) diffs items

let preview_changes output_dir config_dir owner tree allowed_files =
  match tree with
  | Config.Directory items ->
      List.fold_left (fun acc (name, node) ->
        let full_path = Filename.concat output_dir name in
        collect_file_changes config_dir owner full_path name allowed_files acc node
      ) [] items
  | Config.File _ -> failwith "Config root must be a directory"

let rec generate_structure config_dir owner base_path rel_path allowed_files = function
  | Config.File source ->
      if List.mem rel_path allowed_files then
        generate_file config_dir owner base_path source
  | Config.Directory items ->
      List.iter (fun (name, node) ->
        let full_path = Filename.concat base_path name in
        let new_rel_path = if rel_path = "" then name else rel_path ^ "/" ^ name in
        generate_structure config_dir owner full_path new_rel_path allowed_files node
      ) items

let generate output_dir config_dir owner tree allowed_files =
  if not (Sys.file_exists output_dir) then
    Unix.mkdir output_dir 0o755;
  match tree with
  | Config.Directory items ->
      List.iter (fun (name, node) ->
        let full_path = Filename.concat output_dir name in
        generate_structure config_dir owner full_path name allowed_files node
      ) items
  | Config.File _ -> failwith "Config root must be a directory"
