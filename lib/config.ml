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
      let github_config = try
        match List.assoc "github" items with
        | gh -> parse_github gh
        with Not_found -> { token = None; owner = None; repo = None; description = None }
      in
      let tree_items = List.filter (fun (k, _) -> k <> "github") items in
      let tree = Directory (List.map (fun (name, value) -> (name, parse_node value)) tree_items) in
      { name; tree; github = github_config }
  | _ -> failwith (Printf.sprintf "Repo config '%s' must be a JSON object" name)

let parse_config json_string config_dir =
  let json = Yojson.Basic.from_string json_string in
  match json with
  | `Assoc items ->
      let repos = List.map (fun (name, value) -> parse_repo_config name value) items in
      { repos; config_dir }
  | _ -> failwith "Config must be a JSON object"
tree = Directory (List.map (fun (name, value) -> (name, parse_node value)) items) in
      { name; tree