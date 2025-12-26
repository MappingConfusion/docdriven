let parse_env_file path =
  if not (Sys.file_exists path) then []
  else
    In_channel.with_open_text path (fun ic ->
      let rec read_lines acc =
        match In_channel.input_line ic with
        | None -> List.rev acc
        | Some line ->
          let trimmed = String.trim line in
          if trimmed = "" || String.starts_with ~prefix:"#" trimmed then
            read_lines acc
          else
            match String.split_on_char '=' trimmed with
            | key :: rest ->
                let value = String.concat "=" rest |> String.trim in
                read_lines ((String.trim key, value) :: acc)
            | _ -> read_lines acc
      in
      read_lines []
    )

let load config_dir =
  let env_path = Filename.concat config_dir ".env" in
  parse_env_file env_path

let get env key =
  try Some (List.assoc key env)
  with Not_found -> None

let get_local_path env repo_name =
  let key = Printf.sprintf "DOCDRIVEN_%s_LOCAL" repo_name in
  get env key

let get_github_token env repo_name =
  let key = Printf.sprintf "DOCDRIVEN_%s_GITHUB" repo_name in
  match get env key with
  | Some t -> Some t
  | None -> 
      (* Fallback to shared token *)
      match get env "DOCDRIVEN_GITHUB" with
      | Some t -> Some t
      | None -> get env "GITHUB_TOKEN"

let get_github_repo env repo_name =
  let key = Printf.sprintf "DOCDRIVEN_%s_GITHUB_REPO" repo_name in
  match get env key with
  | Some repo_string ->
      (* Parse "owner/repo" format *)
      (match String.split_on_char '/' repo_string with
      | [owner; repo] -> Some (String.trim owner, String.trim repo)
      | _ -> None)
  | None -> None
