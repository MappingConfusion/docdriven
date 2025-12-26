(* Diff module for showing preview of changes *)

type change =
  | Added of string
  | Removed of string  
  | Modified of string * string

type file_diff = {
  path: string;
  change: change;
}

let generate_unified_diff old_content new_content =
  let old_lines = String.split_on_char '\n' old_content in
  let new_lines = String.split_on_char '\n' new_content in
  
  let rec compute_diff old_idx new_idx acc =
    match old_idx >= List.length old_lines, new_idx >= List.length new_lines with
    | true, true -> List.rev acc
    | true, false ->
        let remaining = List.filteri (fun i _ -> i >= new_idx) new_lines in
        List.rev_append acc (List.map (fun line -> "+" ^ line) remaining)
    | false, true ->
        let remaining = List.filteri (fun i _ -> i >= old_idx) old_lines in
        List.rev_append acc (List.map (fun line -> "-" ^ line) remaining)
    | false, false ->
        let old_line = List.nth old_lines old_idx in
        let new_line = List.nth new_lines new_idx in
        if old_line = new_line then
          compute_diff (old_idx + 1) (new_idx + 1) ((" " ^ old_line) :: acc)
        else
          compute_diff (old_idx + 1) (new_idx + 1) (("+" ^ new_line) :: ("-" ^ old_line) :: acc)
  in
  
  String.concat "\n" (compute_diff 0 0 [])

let show_file_diff diff =
  match diff.change with
  | Added content ->
      Printf.printf "\n\027[32m+++ %s (new file)\027[0m\n" diff.path;
      let lines = String.split_on_char '\n' content in
      List.iteri (fun i line ->
        Printf.printf "\027[32m%4d + %s\027[0m\n" (i + 1) line
      ) lines
  | Removed content ->
      Printf.printf "\n\027[31m--- %s (deleted)\027[0m\n" diff.path;
      let lines = String.split_on_char '\n' content in
      List.iteri (fun i line ->
        Printf.printf "\027[31m%4d - %s\027[0m\n" (i + 1) line
      ) lines
  | Modified (old_content, new_content) ->
      Printf.printf "\n\027[33m~~~ %s (modified)\027[0m\n" diff.path;
      let diff_lines = String.split_on_char '\n' (generate_unified_diff old_content new_content) in
      List.iteri (fun i line ->
        let color = match String.get line 0 with
          | '+' -> "\027[32m"
          | '-' -> "\027[31m"
          | _ -> "\027[0m"
        in
        Printf.printf "%s%4d %s\027[0m\n" color (i + 1) line
      ) diff_lines

let show_summary diffs =
  let added = List.filter (fun d -> match d.change with Added _ -> true | _ -> false) diffs in
  let removed = List.filter (fun d -> match d.change with Removed _ -> true | _ -> false) diffs in
  let modified = List.filter (fun d -> match d.change with Modified _ -> true | _ -> false) diffs in
  
  Printf.printf "\n\027[1mSummary:\027[0m\n";
  Printf.printf "  \027[32m%d files to be added\027[0m\n" (List.length added);
  Printf.printf "  \027[33m%d files to be modified\027[0m\n" (List.length modified);
  Printf.printf "  \027[31m%d files to be removed\027[0m\n" (List.length removed);
  Printf.printf "  Total: %d changes\n" (List.length diffs)
