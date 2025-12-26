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
  Lwt.catch
    (fun () ->
      let%lwt resp, body = Cohttp_lwt_unix.Client.put ~headers ~body:(Cohttp_lwt.Body.of_string body) uri in
      let code = Cohttp.Response.status resp |> Cohttp.Code.code_of_status in
      let%lwt body_str = Cohttp_lwt.Body.to_string body in
      if code = 201 then
        Lwt.return_ok ()
      else
        Lwt.return_error (Printf.sprintf "Failed to upload %s: %d - %s" path code body_str)
    )
    (fun exn ->
      Lwt.return_error (Printf.sprintf "Network error uploading %s: %s" path (Printexc.to_string exn))
    )

let rec upload_structure config config_dir doc_owner allowed_files prefix = function
  | Config.File source ->
      if List.mem prefix allowed_files then begin
        let sources, content = match source with
          | Config.Single s -> [s], Generator.extract_content config_dir s
          | Config.Multiple sources ->
              sources, (sources |> List.map (Generator.extract_content config_dir) |> String.concat "\n\n")
        in
        let header = Comments.generate_header prefix doc_owner sources in
        let full_content = header ^ content in
        upload_file config prefix full_content
      end else
        Lwt.return_ok ()
  | Config.Directory items ->
      let rec upload_items remaining_items successful_count failed_files =
        match remaining_items with
        | [] -> 
            if failed_files = [] then
              Lwt.return_ok ()
            else
              Lwt.return_error (Printf.sprintf "%d files failed to upload: %s" 
                (List.length failed_files) (String.concat ", " failed_files))
        | (name, node) :: rest ->
            let path = if prefix = "" then name else prefix ^ "/" ^ name in
            let%lwt result = upload_structure config config_dir doc_owner allowed_files path node in
            match result with
            | Ok () -> 
                upload_items rest (successful_count + 1) failed_files
            | Error msg ->
                Printf.eprintf "Warning: %s (continuing with remaining files)\n" msg;
                upload_items rest successful_count (path :: failed_files)
      in
      upload_items items 0 []

let push config tree config_dir doc_owner allowed_files =
  let%lwt create_result = create_repo config in
  match create_result with
  | Error msg -> Lwt.return_error msg
  | Ok () ->
      match tree with
      | Config.Directory items ->
          let rec push_items remaining_items successful_count failed_files =
            match remaining_items with
            | [] ->
                if failed_files = [] then
                  Lwt.return_ok ()
                else
                  Lwt.return_error (Printf.sprintf "Partially completed: %d succeeded, %d failed (%s)" 
                    successful_count (List.length failed_files) (String.concat ", " failed_files))
            | (name, node) :: rest ->
                let%lwt result = upload_structure config config_dir doc_owner allowed_files name node in
                match result with
                | Ok () ->
                    push_items rest (successful_count + 1) failed_files
                | Error msg ->
                    Printf.eprintf "Warning: %s (continuing with remaining files)\n" msg;
                    push_items rest successful_count (name :: failed_files)
          in
          push_items items 0 []
      | Config.File _ -> Lwt.return_error "Config root must be a directory"
