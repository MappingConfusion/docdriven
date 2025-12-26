type codeblock = {
  language : string;
  content : string;
  index : int;
}

type source_ref = {
  file : string;
  language : string option;
  index : int option;
}

let parse_source_ref str =
  (* Try parsing codeblock reference: file[language][index] *)
  let codeblock_pattern = Re.Perl.compile_pat {|^(.+?)\[([^\]]+)\]\[(\d+)\]$|} in
  match Re.exec_opt codeblock_pattern str with
  | Some groups ->
      let file = Re.Group.get groups 1 in
      let language = Re.Group.get groups 2 in
      let index = int_of_string (Re.Group.get groups 3) in
      Some { file; language = Some language; index = Some index }
  | None ->
      (* Try parsing whole file reference: file or file? *)
      let file_pattern = Re.Perl.compile_pat {|^(.+?)\??$|} in
      match Re.exec_opt file_pattern str with
      | Some groups ->
          let file = Re.Group.get groups 1 in
          Some { file; language = None; index = None }
      | None -> None

let extract_codeblocks content =
  let fence_pattern = Re.Perl.compile_pat {|```(\w+)\n([\s\S]*?)```|} in
  let matches = Re.all fence_pattern content in
  let blocks = List.mapi (fun idx group ->
    let language = Re.Group.get group 1 in
    let content = Re.Group.get group 2 in
    (language, { language; content; index = idx })
  ) matches in
  List.fold_left (fun acc (lang, block) ->
    let lang_blocks = try List.assoc lang acc with Not_found -> [] in
    (lang, block :: lang_blocks) :: List.remove_assoc lang acc
  ) [] blocks
  |> List.map (fun (lang, blocks) -> (lang, List.rev blocks))

let get_codeblock config_dir source_ref =
  let full_path = Filename.concat config_dir source_ref.file in
  let file_content = In_channel.with_open_text full_path In_channel.input_all in
  match source_ref.language, source_ref.index with
  | None, None ->
      (* Whole file reference *)
      Some file_content
  | Some language, Some index ->
      (* Codeblock reference *)
      let blocks = extract_codeblocks file_content in
      (match List.assoc_opt language blocks with
       | Some lang_blocks ->
           (try Some (List.nth lang_blocks index).content
            with _ -> None)
       | None -> None)
  | _ -> None

type codeblock_ref = {
  ref_file : string;
  ref_language : string;
  ref_index : int;
}

let rec find_markdown_files dir =
  let entries = Sys.readdir dir in
  Array.fold_left (fun acc entry ->
    let path = Filename.concat dir entry in
    if Sys.is_directory path then
      (find_markdown_files path) @ acc
    else if Filename.check_suffix entry ".md" then
      path :: acc
    else
      acc
  ) [] entries

let collect_all_codeblocks config_dir =
  let md_files = find_markdown_files config_dir in
  List.fold_left (fun acc md_file ->
    let content = In_channel.with_open_text md_file In_channel.input_all in
    let blocks_by_lang = extract_codeblocks content in
    let relative_path = 
      if String.starts_with ~prefix:config_dir md_file then
        let len = String.length config_dir in
        let path = String.sub md_file len (String.length md_file - len) in
        if String.length path > 0 && path.[0] = '/' then
          String.sub path 1 (String.length path - 1)
        else
          path
      else
        md_file
    in
    List.fold_left (fun acc (language, lang_blocks) ->
      List.fold_left (fun (idx, acc) _block ->
        (idx + 1, { ref_file = relative_path; ref_language = language; ref_index = idx } :: acc)
      ) (0, acc) lang_blocks |> snd
    ) acc blocks_by_lang
  ) [] md_files

let rec collect_assigned_refs_from_node node =
  match node with
  | Config.File (Config.Single ref_str) ->
      (match parse_source_ref ref_str with
       | Some { file; language = Some lang; index = Some idx } ->
           [{ ref_file = file; ref_language = lang; ref_index = idx }]
       | _ -> [])
  | Config.File (Config.Multiple refs) ->
      List.filter_map (fun ref_str ->
        match parse_source_ref ref_str with
        | Some { file; language = Some lang; index = Some idx } ->
            Some { ref_file = file; ref_language = lang; ref_index = idx }
        | _ -> None
      ) refs
  | Config.Directory items ->
      List.concat_map (fun (_, node) -> collect_assigned_refs_from_node node) items

let collect_assigned_refs config =
  List.concat_map (fun repo ->
    collect_assigned_refs_from_node repo.Config.tree
  ) config.Config.repos

let find_unassigned config_dir config limit =
  let all_blocks = collect_all_codeblocks config_dir in
  let assigned = collect_assigned_refs config in
  
  let is_assigned block =
    List.exists (fun ref ->
      ref.ref_file = block.ref_file && 
      ref.ref_language = block.ref_language && 
      ref.ref_index = block.ref_index
    ) assigned
  in
  
  let unassigned = List.filter (fun block -> not (is_assigned block)) all_blocks in
  let total_count = List.length all_blocks in
  let unassigned_count = List.length unassigned in
  let percentage = 
    if total_count = 0 then 0.0 
    else (float_of_int unassigned_count /. float_of_int total_count) *. 100.0 
  in
  
  let limited = match limit with
    | Some n -> List.filteri (fun i _ -> i < n) unassigned
    | None -> unassigned
  in
  
  (total_count, unassigned_count, percentage, limited)
