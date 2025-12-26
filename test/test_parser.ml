open Docdriven.Parser

(* Test parse_source_ref *)

let test_parse_codeblock_ref () =
  let ref_opt = parse_source_ref "file.md[python][0]" in
  match ref_opt with
  | Some { file; language; index } ->
      Alcotest.(check string) "file" "file.md" file;
      Alcotest.(check (option string)) "language" (Some "python") language;
      Alcotest.(check (option int)) "index" (Some 0) index
  | None -> Alcotest.fail "Expected Some, got None"

let test_parse_whole_file () =
  let ref_opt = parse_source_ref "config.json" in
  match ref_opt with
  | Some { file; language; index } ->
      Alcotest.(check string) "file" "config.json" file;
      Alcotest.(check (option string)) "language" None language;
      Alcotest.(check (option int)) "index" None index
  | None -> Alcotest.fail "Expected Some, got None"

let test_parse_with_path () =
  let ref_opt = parse_source_ref "path/to/file.md[typescript][5]" in
  match ref_opt with
  | Some { file; language; index } ->
      Alcotest.(check string) "file" "path/to/file.md" file;
      Alcotest.(check (option string)) "language" (Some "typescript") language;
      Alcotest.(check (option int)) "index" (Some 5) index
  | None -> Alcotest.fail "Expected Some, got None"

let test_parse_invalid_format () =
  let ref_opt = parse_source_ref "file.md[python]" in
  Alcotest.(check (option reject)) "invalid format" None ref_opt

let test_parse_missing_brackets () =
  let ref_opt = parse_source_ref "file.md[python" in
  Alcotest.(check (option reject)) "missing bracket" None ref_opt

(* Test extract_codeblocks *)

let sample_markdown = {|# Test Doc

Some text here.

```python
def test():
    pass
```

More text.

```python
def another():
    return 1
```

```javascript
function hello() {}
```
|}

let test_extract_multiple_blocks () =
  let blocks = extract_codeblocks sample_markdown in
  let python_blocks = List.assoc "python" blocks in
  let js_blocks = List.assoc "javascript" blocks in
  Alcotest.(check int) "python blocks count" 2 (List.length python_blocks);
  Alcotest.(check int) "javascript blocks count" 1 (List.length js_blocks)

let test_extract_block_content () =
  let blocks = extract_codeblocks sample_markdown in
  let python_blocks = List.assoc "python" blocks in
  let first_block = List.nth python_blocks 0 in
  Alcotest.(check string) "content" "def test():\n    pass\n" first_block.content;
  Alcotest.(check string) "language" "python" first_block.language;
  Alcotest.(check int) "index" 0 first_block.index

let test_extract_block_indices () =
  let blocks = extract_codeblocks sample_markdown in
  let python_blocks = List.assoc "python" blocks in
  let indices = List.map (fun b -> b.index) python_blocks in
  Alcotest.(check (list int)) "indices" [0; 1] indices

let test_extract_empty_markdown () =
  let blocks = extract_codeblocks "" in
  Alcotest.(check int) "empty" 0 (List.length blocks)

let test_extract_no_codeblocks () =
  let blocks = extract_codeblocks "Just plain text without code blocks" in
  Alcotest.(check int) "no blocks" 0 (List.length blocks)

(* Test get_codeblock integration *)

let test_get_whole_file () =
  let fixture_dir = "test/fixtures" in
  let source_ref = { file = "whole_file.txt"; language = None; index = None } in
  match get_codeblock fixture_dir source_ref with
  | Some content ->
      Alcotest.(check bool) "contains expected text" true 
        (String.starts_with ~prefix:"This is a complete file" content)
  | None -> Alcotest.fail "Expected to read whole file"

let test_get_codeblock_by_ref () =
  let fixture_dir = "test/fixtures" in
  let source_ref = { file = "sample.md"; language = Some "python"; index = Some 0 } in
  match get_codeblock fixture_dir source_ref with
  | Some content ->
      Alcotest.(check bool) "contains def hello" true 
        (String.contains content (String.sub "def hello" 0 9))
  | None -> Alcotest.fail "Expected to extract codeblock"

let test_get_nonexistent_index () =
  let fixture_dir = "test/fixtures" in
  let source_ref = { file = "sample.md"; language = Some "python"; index = Some 99 } in
  match get_codeblock fixture_dir source_ref with
  | Some _ -> Alcotest.fail "Should return None for invalid index"
  | None -> ()

let test_get_nonexistent_language () =
  let fixture_dir = "test/fixtures" in
  let source_ref = { file = "sample.md"; language = Some "rust"; index = Some 0 } in
  match get_codeblock fixture_dir source_ref with
  | Some _ -> Alcotest.fail "Should return None for missing language"
  | None -> ()

(* Custom testable for option types *)
let reject = Alcotest.testable (fun ppf _ -> Fmt.pf ppf "<rejected>") (fun _ _ -> false)

(* Test suite *)
let () =
  Alcotest.run "Parser Tests" [
    "parse_source_ref", [
      Alcotest.test_case "parse codeblock reference" `Quick test_parse_codeblock_ref;
      Alcotest.test_case "parse whole file reference" `Quick test_parse_whole_file;
      Alcotest.test_case "parse with path" `Quick test_parse_with_path;
      Alcotest.test_case "reject invalid format" `Quick test_parse_invalid_format;
      Alcotest.test_case "reject missing brackets" `Quick test_parse_missing_brackets;
    ];
    "extract_codeblocks", [
      Alcotest.test_case "extract multiple blocks" `Quick test_extract_multiple_blocks;
      Alcotest.test_case "extract block content" `Quick test_extract_block_content;
      Alcotest.test_case "extract block indices" `Quick test_extract_block_indices;
      Alcotest.test_case "handle empty markdown" `Quick test_extract_empty_markdown;
      Alcotest.test_case "handle no codeblocks" `Quick test_extract_no_codeblocks;
    ];
    "get_codeblock", [
      Alcotest.test_case "get whole file" `Quick test_get_whole_file;
      Alcotest.test_case "get codeblock by ref" `Quick test_get_codeblock_by_ref;
      Alcotest.test_case "nonexistent index returns None" `Quick test_get_nonexistent_index;
      Alcotest.test_case "nonexistent language returns None" `Quick test_get_nonexistent_language;
    ];
  ]
