let clear_screen () =
  Printf.printf "\027[2J\027[H";
  flush stdout

let move_cursor row col =
  Printf.printf "\027[%d;%dH" row col;
  flush stdout

let hide_cursor () =
  Printf.printf "\027[?25l";
  flush stdout

let show_cursor () =
  Printf.printf "\027[?25h";
  flush stdout

let read_key () =
  let termio = Unix.tcgetattr Unix.stdin in
  Unix.tcsetattr Unix.stdin Unix.TCSANOW { termio with
    Unix.c_icanon = false;
    Unix.c_echo = false;
  };
  let buf = Bytes.create 1 in
  let _ = Unix.read Unix.stdin buf 0 1 in
  Unix.tcsetattr Unix.stdin Unix.TCSANOW termio;
  Bytes.get buf 0

let select_files files =
  let selected = Array.make (List.length files) true in
  let files_array = Array.of_list files in
  let cursor = ref 0 in
  let running = ref true in
  
  let draw () =
    clear_screen ();
    move_cursor 1 1;
    Printf.printf "Select files to generate (Space to toggle, Enter to confirm, q to quit):\n\n";
    
    Array.iteri (fun i (repo, file) ->
      let check = if selected.(i) then "[x]" else "[ ]" in
      let marker = if i = !cursor then "> " else "  " in
      Printf.printf "%s%s [%s] %s\n" marker check repo file
    ) files_array;
    
    let count = Array.fold_left (fun acc b -> if b then acc + 1 else acc) 0 selected in
    Printf.printf "\n%d of %d selected\n" count (Array.length files_array);
    flush stdout
  in
  
  hide_cursor ();
  draw ();
  
  while !running do
    match read_key () with
    | ' ' ->
        selected.(!cursor) <- not selected.(!cursor);
        draw ()
    | '\n' | '\r' ->
        running := false
    | 'q' | '\027' ->
        Array.fill selected 0 (Array.length selected) false;
        running := false
    | 'j' ->
        cursor := min (!cursor + 1) (Array.length files_array - 1);
        draw ()
    | 'k' ->
        cursor := max (!cursor - 1) 0;
        draw ()
    | '\027' ->
        let _ = read_key () in
        begin match read_key () with
        | 'A' ->
            cursor := max (!cursor - 1) 0;
            draw ()
        | 'B' ->
            cursor := min (!cursor + 1) (Array.length files_array - 1);
            draw ()
        | _ -> ()
        end
    | _ -> ()
  done;
  
  show_cursor ();
  clear_screen ();
  
  let result = ref [] in
  Array.iteri (fun i file ->
    if selected.(i) then result := file :: !result
  ) files_array;
  List.rev !result
