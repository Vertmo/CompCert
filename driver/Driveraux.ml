(* *********************************************************************)
(*                                                                     *)
(*              The Compcert verified compiler                         *)
(*                                                                     *)
(*          Xavier Leroy, INRIA Paris-Rocquencourt                     *)
(*      Bernhard Schommer, AbsInt Angewandte Informatik GmbH           *)
(*                                                                     *)
(*  Copyright Institut National de Recherche en Informatique et en     *)
(*  Automatique.  All rights reserved.  This file is distributed       *)
(*  under the terms of the INRIA Non-Commercial License Agreement.     *)
(*                                                                     *)
(* *********************************************************************)

open Printf
open Clflags

(* Is this a gnu based tool chain *)
let gnu_system = Configuration.system <> "diab"

(* Sage removale of files *)
let safe_remove file =
  try Sys.remove file with Sys_error _ -> ()

(* Invocation of external tools *)

let rec waitpid_no_intr pid =
  try Unix.waitpid [] pid
  with Unix.Unix_error (Unix.EINTR, _, _) -> waitpid_no_intr pid

let command stdout args =
  if !option_v then begin
    eprintf "+ %s" (String.concat " " args);
    begin match stdout with
    | None -> ()
    | Some f -> eprintf " > %s" f
    end;
    prerr_endline ""
  end;
  let argv = Array.of_list args in
  assert (Array.length argv > 0);
  try
    let fd_out =
      match stdout with
      | None -> Unix.stdout
      | Some f ->
          Unix.openfile f [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC] 0o666 in
    let pid =
      Unix.create_process argv.(0) argv Unix.stdin fd_out Unix.stderr in
    let (_, status) =
      waitpid_no_intr pid in
    if stdout <> None then Unix.close fd_out;
    match status with
    | Unix.WEXITED rc -> rc
    | Unix.WSIGNALED n | Unix.WSTOPPED n ->
        eprintf "Command '%s' killed on a signal.\n" argv.(0); -1
  with Unix.Unix_error(err, fn, param) ->
    eprintf "Error executing '%s': %s: %s %s\n"
            argv.(0) fn (Unix.error_message err) param;
    -1

(* This function reimplements quoting of writeargv from libiberty *)
let gnu_quote arg =
  let len = String.length arg in
  let buf = Buffer.create len in
  String.iter (fun c -> match c with
    | ' ' | '\t' | '\r' | '\n' | '\\' | '\'' | '"' ->
        Buffer.add_char buf '\\'
    | _ -> ();
    Buffer.add_char buf c) arg;
  Buffer.contents buf

let re_quote = Str.regexp ".*[ \t\n\r\"]"

let diab_quote arg =
  let buf = Buffer.create ((String.length arg) + 8) in
  let doublequote = Str.string_match re_quote arg 0 in
  if doublequote then begin
    Buffer.add_char buf '"';
    String.iter (fun c ->
      if c = '"' then Buffer.add_char buf '\\';
      Buffer.add_char buf c) arg;
    if doublequote then Buffer.add_char buf '"';
    Buffer.contents buf
  end else
    arg

let command ?stdout args =
  let resp = Sys.win32 && Configuration.response_file_style <> Configuration.Unsupported in
  if resp && List.fold_left (fun len arg -> len + String.length arg + 1) 0 args > 7000 then
    let quote = match Configuration.response_file_style with
    | Configuration.Unsupported -> assert false
    | Configuration.Gnu -> gnu_quote
    | Configuration.Diab -> diab_quote in
    let file,oc = Filename.open_temp_file "compcert" "" in
    let cmd,args = match args with
    | cmd::args -> cmd,args
    | [] -> assert false (* Should never happen *) in
    List.iter (fun a -> Printf.fprintf oc "%s " (quote a)) args;
    close_out oc;
    let arg = if gnu_system then "@"^file else "-@"^file in
    let ret = command stdout [cmd;arg] in
    safe_remove file;
    ret
  else
    command stdout args

let command_error n exc =
  eprintf "Error: %s command failed with exit code %d (use -v to see invocation)\n" n exc


(* Determine names for output files.  We use -o option if specified
   and if this is the final destination file (not a dump file).
   Otherwise, we generate a file in the current directory. *)

let output_filename ?(final = false) source_file source_suffix output_suffix =
  match !option_o with
  | Some file when final -> file
  | _ ->
    Filename.basename (Filename.chop_suffix source_file source_suffix)
    ^ output_suffix

(* A variant of [output_filename] where the default output name is fixed *)

let output_filename_default default_file =
  match !option_o with
  | Some file -> file
  | None -> default_file

(* All input files should exist *)

let ensure_inputfile_exists name =
  if not (Sys.file_exists name) then begin
    eprintf "error: no such file or directory: '%s'\n" name;
    exit 2
  end
(* Printing of error messages *)

let print_error oc msg =
  let print_one_error = function
  | Errors.MSG s -> output_string oc (Camlcoq.camlstring_of_coqstring s)
  | Errors.CTX i -> output_string oc (Camlcoq.extern_atom i)
  | Errors.POS i -> fprintf oc "%ld" (Camlcoq.P.to_int32 i)
  in
    List.iter print_one_error msg;
    output_char oc '\n'

(* Command-line parsing *)
let explode_comma_option s =
  match Str.split (Str.regexp ",") s with
  | [] -> assert false
  | _ :: tl -> tl

(* Record actions to be performed after parsing the command line *)

let actions : ((string -> string) * string) list ref = ref []

let push_action fn arg =
  actions := (fn, arg) :: !actions

let push_linker_arg arg =
  push_action (fun s -> s) arg

let perform_actions () =
  let rec perform = function
  | [] -> []
  | (fn, arg) :: rem -> let res = fn arg in res :: perform rem
  in perform (List.rev !actions)
