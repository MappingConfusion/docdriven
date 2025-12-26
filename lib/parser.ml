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
