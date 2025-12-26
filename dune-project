(lang dune 3.0)
(name docdriven)
(version 0.1.0)

(generate_opam_files true)

(package
 (name docdriven)
 (synopsis "Generate repository structure from documented codeblocks")
 (license MIT)
 (depends
  (ocaml (>= 4.14))
  dune
  yojson
  re
  cmdliner
  cohttp-lwt-unix
  lwt_ppx
  base64
  (alcotest :with-test)))
