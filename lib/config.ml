type file_source =
  | Single of string
  | Multiple of string list

type repo_node =
  | File of file_source
  | Directory of (string * repo_node) list

type repo_config = {
  name : string;
  tree : repo_node;
}

type t = {
  repos : repo_config list;
  config_dir : string;
  owner : string;
}

let rec parse_node = function
  | `String s -> File (Single s)
  | `List lst ->
      let sources = List.filter_map (function
        | `String s -> Some s
        | _ -> None
      ) lst in
      File (Multiple sources)
  | `Assoc items ->
      Directory (List.map (fun (name, value) -> (name, parse_node value)) items)
  | _ -> failwith "Invalid config structure"

let parse_repo_config name json =
  match json with
  | `Assoc items ->
      let tree = Directory (List.map (fun (name, value) -> (name, parse_node value)) items) in
      { name; tree }
  | _ -> failwith (Printf.sprintf "Repo config '%s' must be a JSON object" name)

let derive_owner config_dir =
  (* Get parent folder name as default owner *)
  let normalized = if config_dir = "." then Sys.getcwd () else config_dir in
  Filename.basename normalized

let parse_config json_string config_dir owner_override =
  let json = Yojson.Basic.from_string json_string in
  match json with
  | `Assoc items ->
      let owner = match owner_override with
        | Some o -> o
        | None -> derive_owner config_dir
      in
      let repos = List.map (fun (name, value) -> parse_repo_config name value) items in
      { repos; config_dir; owner }
  | _ -> failwith "Config must be a JSON object"

let load_config config_file owner_override =
  let config_dir = Filename.dirname config_file in
  let json_string = In_channel.with_open_text config_file In_channel.input_all in
  parse_config json_string config_dir owner_override