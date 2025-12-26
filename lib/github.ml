open Lwt.Syntax

type config = {
  token : string;
  owner : string;
  repo : string;
}

let create_repo config =
  let uri = Uri.of_string "https://api.github.com/user/repos" in
  let body = `Assoc [
    ("name", `String config.repo);
    ("private", `Bool false);
    ("auto_init", `Bool false);
  ] |> Yojson.Basic.to_string in
  let headers = Cohttp.Header.of_list [
    ("Authorization", "Bearer " ^ config.token);
    ("Accept", "application/vnd.github+json");
    ("User-Agent", "docdriven");
    ("X-GitHub-Api-Version", "2022-11-28");
  ] in
  let%lwt resp, body = Cohttp_lwt_unix.Client.post ~headers ~body:(Cohttp_lwt.Body.of_string body) uri in
  let code = Cohttp.Response.status resp |> Cohttp.Code.code_of_status in
  let%lwt body_str = Cohttp_lwt.Body.to_string body in
  if code = 201 || code = 422 then
    Lwt.return_ok ()
  else
    Lwt.return_error (Printf.sprintf "Failed to create repo: %d - %s" code body_str)

let upload_file config path content =
  let encoded_content = Base64.encode_string content in
  let uri = Uri.of_string (Printf.sprintf "https://api.github.com/repos/%s/%s/contents/%s"
    config.owner config.repo path) in
  let body = `Assoc [
    ("message", `String (Printf.sprintf "Add %s via docdriven" path));
    ("content", `String encoded_content);
  ] |> Yojson.Basic.to_string in
  let headers = Cohttp.Header.of_list [
    ("Authorization", "Bearer " ^ config.token);
    ("Accept", "application/vnd.github+json");
    ("User-Agent", "docdriven");
    ("X-GitHub-Api-Version", "2022-11-28");
  ] in
  let%lwt resp, body = Cohttp_lwt_unix.Client.put ~headers ~body:(Cohttp_lwt.Body.of_string body) uri in
  let code = Cohttp.Response.status resp |> Cohttp.Code.code_of_status in
  let%lwt body_str = Cohttp_lwt.Body.to_string body in
  if code = 201 then
    Lwt.return_ok ()
  else
    Lwt.return_error (Printf.sprintf "Failed to upload %s: %d - %s" path code body_str)

let rec upload_structure config config_dir allowed_files prefix = function
  | Config.File source ->
      if List.mem prefix allowed_files then begin
        let sources, content = match source with
          | Config.Single s -> [s], Generator.extract_content config_dir s
          | Config.Multiple sources ->
              sources, (sources |> List.map (Generator.extract_content config_dir) |> String.concat "\n\n")
        in
        let header = Comments.generate_header prefix sources in
        let full_content = header ^ content in
        upload_file config prefix full_content
      end else
        Lwt.return_ok ()
  | Config.Directory items ->
      Lwt_list.iter_s (fun (name, node) ->
        let path = if prefix = "" then name else prefix ^ "/" ^ name in
        let%lwt result = upload_structure config config_dir allowed_files path node in
        match result with
        | Ok () -> Lwt.return_unit
        | Error msg -> Lwt.fail_with msg
      ) items >>= fun () -> Lwt.return_ok ()

let push config tree config_dir allowed_files =
  let%lwt create_result = create_repo config in
  match create_result with
  | Error msg -> Lwt.return_error msg
  | Ok () ->
      match tree with
      | Config.Directory items ->
          Lwt_list.iter_s (fun (name, node) ->
            let%lwt result = upload_structure config config_dir allowed_files name node in
            match result with
            | Ok () -> Lwt.return_unit
            | Error msg -> Lwt.fail_with msg
          ) items >>= fun () -> Lwt.return_ok ()
      | Config.File _ -> Lwt.return_error "Config root must be a directory"
