(* *********************************************************************)
(*                                                                     *)
(*              The Compcert verified compiler                         *)
(*                                                                     *)
(*          Xavier Leroy, INRIA Paris-Rocquencourt                     *)
(*                                                                     *)
(*  Copyright Institut National de Recherche en Informatique et en     *)
(*  Automatique.  All rights reserved.  This file is distributed       *)
(*  under the terms of the INRIA Non-Commercial License Agreement.     *)
(*                                                                     *)
(* *********************************************************************)

(** Function calling conventions and other conventions regarding the use of 
    machine registers and stack slots. *)

Require Import Coqlib.
Require Import AST.
Require Import Locations.

(** * Classification of machine registers *)

(** Machine registers (type [mreg] in module [Locations]) are divided in
  the following groups:
- Temporaries used for spilling, reloading, and parallel move operations.
- Allocatable registers, that can be assigned to RTL pseudo-registers.
  These are further divided into:
-- Callee-save registers, whose value is preserved across a function call.
-- Caller-save registers that can be modified during a function call.

  We follow the PowerPC/EABI application binary interface (ABI) in our choice
  of callee- and caller-save registers.
*)

Definition int_caller_save_regs :=
  R3 :: R4 :: R5 :: R6 :: R7 :: R8 :: R9 :: R10 :: nil.

Definition float_caller_save_regs :=
  F1 :: F2 :: F3 :: F4 :: F5 :: F6 :: F7 :: F8 :: F9 :: F10 :: nil.

Definition int_callee_save_regs :=
  R13 :: R14 :: R15 :: R16 :: R17 :: R18 :: R19 :: R20 :: R21 :: R22 :: 
  R23 :: R24 :: R25 :: R26 :: R27 :: R28 :: R29 :: R30 :: R31 :: nil.

Definition float_callee_save_regs :=
  F14 :: F15 :: F16 :: F17 :: F18 :: F19 :: F20 :: F21 :: F22 :: 
  F23 :: F24 :: F25 :: F26 :: F27 :: F28 :: F29 :: F30 :: F31 :: nil.

Definition destroyed_at_call_regs :=
  int_caller_save_regs ++ float_caller_save_regs.

Definition destroyed_at_call :=
  List.map R destroyed_at_call_regs.

Definition int_temporaries := IT1 :: IT2 :: nil.

Definition float_temporaries := FT1 :: FT2 :: FT3 :: nil.
  
Definition temporaries := 
  R IT1 :: R IT2 :: R FT1 :: R FT2 :: R FT3 :: nil.

(** The [index_int_callee_save] and [index_float_callee_save] associate
  a unique positive integer to callee-save registers.  This integer is
  used in [Stacking] to determine where to save these registers in
  the activation record if they are used by the current function. *)

Definition index_int_callee_save (r: mreg) :=
  match r with
  | R13 => 0  | R14 => 1  | R15 => 2  | R16 => 3
  | R17 => 4  | R18 => 5  | R19 => 6  | R20 => 7
  | R21 => 8  | R22 => 9  | R23 => 10 | R24 => 11
  | R25 => 12 | R26 => 13 | R27 => 14 | R28 => 15
  | R29 => 16 | R30 => 17 | R31 => 18 | _ => -1
  end.

Definition index_float_callee_save (r: mreg) :=
  match r with
  | F14 => 0  | F15 => 1  | F16 => 2  | F17 => 3
  | F18 => 4  | F19 => 5  | F20 => 6  | F21 => 7
  | F22 => 8  | F23 => 9  | F24 => 10 | F25 => 11
  | F26 => 12 | F27 => 13 | F28 => 14 | F29 => 15
  | F30 => 16 | F31 => 17 | _ => -1
  end.

Ltac ElimOrEq :=
  match goal with
  |  |- (?x = ?y) \/ _ -> _ =>
       let H := fresh in
       (intro H; elim H; clear H;
        [intro H; rewrite <- H; clear H | ElimOrEq])
  |  |- False -> _ =>
       let H := fresh in (intro H; contradiction)
  end.

Ltac OrEq :=
  match goal with
  | |- (?x = ?x) \/ _ => left; reflexivity
  | |- (?x = ?y) \/ _ => right; OrEq
  | |- False => fail
  end.

Ltac NotOrEq :=
  match goal with
  | |- (?x = ?y) \/ _ -> False =>
       let H := fresh in (
       intro H; elim H; clear H; [intro; discriminate | NotOrEq])
  | |- False -> False =>
       contradiction
  end.

Lemma index_int_callee_save_pos:
  forall r, In r int_callee_save_regs -> index_int_callee_save r >= 0.
Proof.
  intro r. simpl; ElimOrEq; unfold index_int_callee_save; omega.
Qed.

Lemma index_float_callee_save_pos:
  forall r, In r float_callee_save_regs -> index_float_callee_save r >= 0.
Proof.
  intro r. simpl; ElimOrEq; unfold index_float_callee_save; omega.
Qed.

Lemma index_int_callee_save_pos2:
  forall r, index_int_callee_save r >= 0 -> In r int_callee_save_regs.
Proof.
  destruct r; simpl; intro; omegaContradiction || OrEq.
Qed.

Lemma index_float_callee_save_pos2:
  forall r, index_float_callee_save r >= 0 -> In r float_callee_save_regs.
Proof.
  destruct r; simpl; intro; omegaContradiction || OrEq.
Qed.

Lemma index_int_callee_save_inj:
  forall r1 r2, 
  In r1 int_callee_save_regs ->
  In r2 int_callee_save_regs ->
  r1 <> r2 ->
  index_int_callee_save r1 <> index_int_callee_save r2.
Proof.
  intros r1 r2. 
  simpl; ElimOrEq; ElimOrEq; unfold index_int_callee_save;
  intros; congruence.
Qed.

Lemma index_float_callee_save_inj:
  forall r1 r2, 
  In r1 float_callee_save_regs ->
  In r2 float_callee_save_regs ->
  r1 <> r2 ->
  index_float_callee_save r1 <> index_float_callee_save r2.
Proof.
  intros r1 r2. 
  simpl; ElimOrEq; ElimOrEq; unfold index_float_callee_save;
  intros; congruence.
Qed.

(** The following lemmas show that
    (temporaries, destroyed at call, integer callee-save, float callee-save)
    is a partition of the set of machine registers. *)

Lemma int_float_callee_save_disjoint:
  list_disjoint int_callee_save_regs float_callee_save_regs.
Proof.
  red; intros r1 r2. simpl; ElimOrEq; ElimOrEq; discriminate.
Qed.

Lemma register_classification:
  forall r, 
  (In (R r) temporaries \/ In (R r) destroyed_at_call) \/
  (In r int_callee_save_regs \/ In r float_callee_save_regs).
Proof.
  destruct r; 
  try (left; left; simpl; OrEq);
  try (left; right; simpl; OrEq);
  try (right; left; simpl; OrEq);
  try (right; right; simpl; OrEq).
Qed.

Lemma int_callee_save_not_destroyed:
  forall r, 
    In (R r) temporaries \/ In (R r) destroyed_at_call ->
    ~(In r int_callee_save_regs).
Proof.
  intros; red; intros. elim H.
  generalize H0. simpl; ElimOrEq; NotOrEq.
  generalize H0. simpl; ElimOrEq; NotOrEq.
Qed.

Lemma float_callee_save_not_destroyed:
  forall r, 
    In (R r) temporaries \/ In (R r) destroyed_at_call ->
    ~(In r float_callee_save_regs).
Proof.
  intros; red; intros. elim H.
  generalize H0. simpl; ElimOrEq; NotOrEq.
  generalize H0. simpl; ElimOrEq; NotOrEq.
Qed.

Lemma int_callee_save_type:
  forall r, In r int_callee_save_regs -> mreg_type r = Tint.
Proof.
  intro. simpl; ElimOrEq; reflexivity.
Qed.

Lemma float_callee_save_type:
  forall r, In r float_callee_save_regs -> mreg_type r = Tfloat.
Proof.
  intro. simpl; ElimOrEq; reflexivity.
Qed.

Ltac NoRepet :=
  match goal with
  | |- list_norepet nil =>
      apply list_norepet_nil
  | |- list_norepet (?a :: ?b) =>
      apply list_norepet_cons; [simpl; intuition discriminate | NoRepet]
  end.

Lemma int_callee_save_norepet:
  list_norepet int_callee_save_regs.
Proof.
  unfold int_callee_save_regs; NoRepet.
Qed.

Lemma float_callee_save_norepet:
  list_norepet float_callee_save_regs.
Proof.
  unfold float_callee_save_regs; NoRepet.
Qed.

(** * Acceptable locations for register allocation *)

(** The following predicate describes the locations that can be assigned
  to an RTL pseudo-register during register allocation: a non-temporary
  machine register or a [Local] stack slot are acceptable. *)

Definition loc_acceptable (l: loc) : Prop :=
  match l with
  | R r => ~(In l temporaries)
  | S (Local ofs ty) => ofs >= 0
  | S (Incoming _ _) => False
  | S (Outgoing _ _) => False
  end.

Definition locs_acceptable (ll: list loc) : Prop :=
  forall l, In l ll -> loc_acceptable l.

Lemma temporaries_not_acceptable:
  forall l, loc_acceptable l -> Loc.notin l temporaries.
Proof.
  unfold loc_acceptable; destruct l.
  simpl. intuition congruence.
  destruct s; try contradiction. 
  intro. simpl. tauto.
Qed.
Hint Resolve temporaries_not_acceptable: locs.

Lemma locs_acceptable_disj_temporaries:
  forall ll, locs_acceptable ll -> Loc.disjoint ll temporaries.
Proof.
  intros. apply Loc.notin_disjoint. intros.
  apply temporaries_not_acceptable. auto. 
Qed.

Lemma loc_acceptable_noteq_diff:
  forall l1 l2,
  loc_acceptable l1 -> l1 <> l2 -> Loc.diff l1 l2.
Proof.
  unfold loc_acceptable, Loc.diff; destruct l1; destruct l2;
  try (destruct s); try (destruct s0); intros; auto; try congruence.
  case (zeq z z0); intro. 
  compare t t0; intro.
  subst z0; subst t0; tauto.
  tauto. tauto.
  contradiction. contradiction.
Qed.

Lemma loc_acceptable_notin_notin:
  forall r ll,
  loc_acceptable r ->
  ~(In r ll) -> Loc.notin r ll.
Proof.
  induction ll; simpl; intros.
  auto.
  split. apply loc_acceptable_noteq_diff. assumption. 
  apply sym_not_equal. tauto. 
  apply IHll. assumption. tauto. 
Qed.

(** * Function calling conventions *)

(** The functions in this section determine the locations (machine registers
  and stack slots) used to communicate arguments and results between the
  caller and the callee during function calls.  These locations are functions
  of the signature of the function and of the call instruction.  
  Agreement between the caller and the callee on the locations to use
  is guaranteed by our dynamic semantics for Cminor and RTL, which demand 
  that the signature of the call instruction is identical to that of the
  called function.

  Calling conventions are largely arbitrary: they must respect the properties
  proved in this section (such as no overlapping between the locations
  of function arguments), but this leaves much liberty in choosing actual
  locations.  To ensure binary interoperability of code generated by our
  compiler with libraries compiled by another PowerPC compiler, we
  implement the standard conventions defined in the PowerPC/EABI
  application binary interface. *)

(** ** Location of function result *)

(** The result value of a function is passed back to the caller in
  registers [R3] or [F1], depending on the type of the returned value.
  We treat a function without result as a function with one integer result. *)

Definition loc_result (s: signature) : mreg :=
  match s.(sig_res) with
  | None => R3
  | Some Tint => R3
  | Some Tfloat => F1
  end.

(** The result location has the type stated in the signature. *)

Lemma loc_result_type:
  forall sig,
  mreg_type (loc_result sig) =
  match sig.(sig_res) with None => Tint | Some ty => ty end.
Proof.
  intros; unfold loc_result.
  destruct (sig_res sig). 
  destruct t; reflexivity.
  reflexivity.
Qed.

(** The result location is acceptable. *)

Lemma loc_result_acceptable:
  forall sig, loc_acceptable (R (loc_result sig)).
Proof.
  intros. unfold loc_acceptable. red.
  unfold loc_result. destruct (sig_res sig).
  destruct t; simpl; NotOrEq.
  simpl; NotOrEq.
Qed.

(** The result location is a caller-save register. *)

Lemma loc_result_caller_save:
  forall (s: signature), In (R (loc_result s)) destroyed_at_call.
Proof.
  intros; unfold loc_result.
  destruct (sig_res s). 
  destruct t; simpl; OrEq.
  simpl; OrEq.
Qed.

(** The result location is not a callee-save register. *)

Lemma loc_result_not_callee_save:
  forall (s: signature),
  ~(In (loc_result s) int_callee_save_regs \/ In (loc_result s) float_callee_save_regs).
Proof.
  intros. generalize (loc_result_caller_save s).
  generalize (int_callee_save_not_destroyed (loc_result s)).
  generalize (float_callee_save_not_destroyed (loc_result s)).
  tauto.
Qed.

(** ** Location of function arguments *)

(** The PowerPC EABI states the following convention for passing arguments
  to a function:
- The first 8 integer arguments are passed in registers [R3] to [R10].
- The first 8 float arguments are passed in registers [F1] to [F8].
- Extra arguments are passed on the stack, in [Outgoing] slots, consecutively
  assigned (1 word for an integer argument, 2 words for a float),
  starting at word offset 0.
- No stack space is reserved for the arguments that are passed in registers.
*)

Fixpoint loc_arguments_rec
    (tyl: list typ) (iregl: list mreg) (fregl: list mreg)
    (ofs: Z) {struct tyl} : list loc :=
  match tyl with
  | nil => nil
  | Tint :: tys =>
      match iregl with
      | nil =>
          S (Outgoing ofs Tint) :: loc_arguments_rec tys nil fregl (ofs + 1)
      | ireg :: iregs =>
          R ireg :: loc_arguments_rec tys iregs fregl ofs
      end
  | Tfloat :: tys =>
      match fregl with
      | nil =>
          S (Outgoing ofs Tfloat) :: loc_arguments_rec tys iregl nil (ofs + 2)
      | freg :: fregs =>
          R freg :: loc_arguments_rec tys iregl fregs ofs
      end
  end.

Definition int_param_regs :=
  R3 :: R4 :: R5 :: R6 :: R7 :: R8 :: R9 :: R10 :: nil.
Definition float_param_regs :=
  F1 :: F2 :: F3 :: F4 :: F5 :: F6 :: F7 :: F8 :: nil.

(** [loc_arguments s] returns the list of locations where to store arguments
  when calling a function with signature [s].  *)

Definition loc_arguments (s: signature) : list loc :=
  loc_arguments_rec s.(sig_args) int_param_regs float_param_regs 0.

(** [size_arguments s] returns the number of [Outgoing] slots used
  to call a function with signature [s]. *)

Fixpoint size_arguments_rec
    (tyl: list typ) (iregl: list mreg) (fregl: list mreg)
    (ofs: Z) {struct tyl} : Z :=
  match tyl with
  | nil => ofs
  | Tint :: tys =>
      match iregl with
      | nil => size_arguments_rec tys nil fregl (ofs + 1)
      | ireg :: iregs => size_arguments_rec tys iregs fregl ofs
      end
  | Tfloat :: tys =>
      match fregl with
      | nil => size_arguments_rec tys iregl nil (ofs + 2)
      | freg :: fregs => size_arguments_rec tys iregl fregs ofs
      end
  end.

Definition size_arguments (s: signature) : Z :=
  size_arguments_rec s.(sig_args) int_param_regs float_param_regs 0.

(** A tail-call is possible for a signature if the corresponding
    arguments are all passed in registers. *)

Definition tailcall_possible (s: signature) : Prop :=
  forall l, In l (loc_arguments s) ->
  match l with R _ => True | S _ => False end.

(** Argument locations are either non-temporary registers or [Outgoing] 
  stack slots at nonnegative offsets. *)

Definition loc_argument_acceptable (l: loc) : Prop :=
  match l with
  | R r => ~(In l temporaries)
  | S (Outgoing ofs ty) => ofs >= 0
  | _ => False
  end.

Remark loc_arguments_rec_charact:
  forall tyl iregl fregl ofs l,
  In l (loc_arguments_rec tyl iregl fregl ofs) ->
  match l with
  | R r => In r iregl \/ In r fregl
  | S (Outgoing ofs' ty) => ofs' >= ofs
  | S _ => False
  end.
Proof.
  induction tyl; simpl loc_arguments_rec; intros.
  elim H.
  destruct a. 
  destruct iregl; elim H; intro. 
  subst l. omega.
  generalize (IHtyl _ _ _ _ H0). destruct l; auto. destruct s; auto. omega.
  subst l. auto with coqlib.
  generalize (IHtyl _ _ _ _ H0). destruct l; auto. simpl; intuition.
  destruct fregl; elim H; intro. 
  subst l. omega.
  generalize (IHtyl _ _ _ _ H0). destruct l; auto. destruct s; auto. omega.
  subst l. auto with coqlib.
  generalize (IHtyl _ _ _ _ H0). destruct l; auto.
  intros [A|B]. left; auto. right; auto with coqlib.
Qed.

Lemma loc_arguments_acceptable:
  forall (s: signature) (r: loc),
  In r (loc_arguments s) -> loc_argument_acceptable r.
Proof.
  unfold loc_arguments; intros.
  generalize (loc_arguments_rec_charact _ _ _ _ _ H).
  destruct r.
  intro H0; elim H0. simpl. unfold not. ElimOrEq; NotOrEq.
  simpl. unfold not. ElimOrEq; NotOrEq.
  destruct s0; try contradiction.
  simpl. omega. 
Qed. 
Hint Resolve loc_arguments_acceptable: locs.

(** Arguments are parwise disjoint (in the sense of [Loc.norepet]). *)

Remark loc_arguments_rec_notin_reg:
  forall tyl iregl fregl ofs r,
  ~(In r iregl) -> ~(In r fregl) ->
  Loc.notin (R r) (loc_arguments_rec tyl iregl fregl ofs).
Proof.
  induction tyl; simpl; intros.
  auto.
  destruct a. 
  destruct iregl; simpl. auto.
  simpl in H. split. apply sym_not_equal. tauto.
  apply IHtyl. tauto. tauto.
  destruct fregl; simpl. auto.
  simpl in H0. split. apply sym_not_equal. tauto.
  apply IHtyl. 
  red; intro. apply H. auto.
  tauto.
Qed.

Remark loc_arguments_rec_notin_local:
  forall tyl iregl fregl ofs ofs0 ty0,
  Loc.notin (S (Local ofs0 ty0)) (loc_arguments_rec tyl iregl fregl ofs).
Proof.
  induction tyl; simpl; intros.
  auto.
  destruct a.
  destruct iregl; simpl; auto.
  destruct fregl; simpl; auto.
Qed.

Remark loc_arguments_rec_notin_outgoing:
  forall tyl iregl fregl ofs ofs0 ty0,
  ofs0 + typesize ty0 <= ofs ->
  Loc.notin (S (Outgoing ofs0 ty0)) (loc_arguments_rec tyl iregl fregl ofs).
Proof.
  induction tyl; simpl; intros.
  auto.
  destruct a.
  destruct iregl; simpl. 
  split. omega. eapply IHtyl. omega.
  auto.
  destruct fregl; simpl. 
  split. omega. eapply IHtyl. omega.
  auto.
Qed.

Lemma loc_arguments_norepet:
  forall (s: signature), Loc.norepet (loc_arguments s).
Proof.
  assert (forall tyl iregl fregl ofs,
    list_norepet iregl ->
    list_norepet fregl ->
    list_disjoint iregl fregl ->
    Loc.norepet (loc_arguments_rec tyl iregl fregl ofs)).
  induction tyl; simpl; intros.
  constructor.
  destruct a. 
  destruct iregl; constructor.
  apply loc_arguments_rec_notin_outgoing. simpl; omega. auto.
  apply loc_arguments_rec_notin_reg. inversion H. auto.
  apply list_disjoint_notin with (m :: iregl); auto with coqlib.
  apply IHtyl. inv H; auto. auto.
  eapply list_disjoint_cons_left; eauto.
  destruct fregl; constructor.
  apply loc_arguments_rec_notin_outgoing. simpl; omega. auto.
  apply loc_arguments_rec_notin_reg.
  red; intro. apply (H1 m m). auto. 
  auto with coqlib. auto. inv H0; auto.
  apply IHtyl. auto.
  inv H0; auto. 
  red; intros. apply H1. auto. auto with coqlib.

  intro. unfold loc_arguments. apply H.
  unfold int_param_regs. NoRepet.
  unfold float_param_regs. NoRepet.
  red; intros x y; simpl. ElimOrEq; ElimOrEq; discriminate.
Qed.

(** The offsets of [Outgoing] arguments are below [size_arguments s]. *)

Remark size_arguments_rec_above:
  forall tyl iregl fregl ofs0,
  ofs0 <= size_arguments_rec tyl iregl fregl ofs0.
Proof.
  induction tyl; simpl; intros.
  omega.
  destruct a.
  destruct iregl. apply Zle_trans with (ofs0 + 1); auto; omega. auto.
  destruct fregl. apply Zle_trans with (ofs0 + 2); auto; omega. auto.
Qed.

Lemma size_arguments_above:
  forall s, size_arguments s >= 0.
Proof.
  intros; unfold size_arguments. apply Zle_ge.  
  apply size_arguments_rec_above.
Qed.

Lemma loc_arguments_bounded:
  forall (s: signature) (ofs: Z) (ty: typ),
  In (S (Outgoing ofs ty)) (loc_arguments s) ->
  ofs + typesize ty <= size_arguments s.
Proof.
  intros.
  assert (forall tyl iregl fregl ofs0,
    In (S (Outgoing ofs ty)) (loc_arguments_rec tyl iregl fregl ofs0) ->
    ofs + typesize ty <= size_arguments_rec tyl iregl fregl ofs0).
  induction tyl; simpl; intros.
  elim H0.
  destruct a. destruct iregl; elim H0; intro.
  inv H1. simpl. apply size_arguments_rec_above. auto.
  discriminate. auto. 
  destruct fregl; elim H0; intro.
  inv H1. simpl. apply size_arguments_rec_above. auto.
  discriminate. auto. 
  unfold size_arguments. eapply H0. unfold loc_arguments in H. eauto.
Qed.

(** Temporary registers do not overlap with argument locations. *)

Lemma loc_arguments_not_temporaries:
  forall sig, Loc.disjoint (loc_arguments sig) temporaries.
Proof.
  intros; red; intros x1 x2 H.
  generalize (loc_arguments_rec_charact _ _ _ _ _ H).
  destruct x1. 
  intro H0; elim H0; simpl; (ElimOrEq; ElimOrEq; congruence).
  destruct s; try contradiction. intro.
  simpl; ElimOrEq; auto.
Qed.
Hint Resolve loc_arguments_not_temporaries: locs.

(** Argument registers are caller-save. *)

Lemma arguments_caller_save:
  forall sig r,
  In (R r) (loc_arguments sig) -> In (R r) destroyed_at_call.
Proof.
  unfold loc_arguments; intros.
  elim (loc_arguments_rec_charact _ _ _ _ _ H); simpl.
  ElimOrEq; intuition.
  ElimOrEq; intuition.
Qed.

(** Callee-save registers do not overlap with argument locations. *)

Lemma arguments_not_preserved:
  forall sig l,
  Loc.notin l destroyed_at_call -> loc_acceptable l ->
  Loc.notin l (loc_arguments sig).
Proof.
  intros. unfold loc_arguments. destruct l.
  apply loc_arguments_rec_notin_reg. 
  generalize (Loc.notin_not_in _ _ H). intro; red; intro.
  apply H1. generalize H2. simpl. ElimOrEq; OrEq. 
  generalize (Loc.notin_not_in _ _ H). intro; red; intro.
  apply H1. generalize H2. simpl. ElimOrEq; OrEq. 
  destruct s; simpl in H0; try contradiction.
  apply loc_arguments_rec_notin_local.
Qed.
Hint Resolve arguments_not_preserved: locs.

(** Argument locations agree in number with the function signature. *)

Lemma loc_arguments_length:
  forall sig,
  List.length (loc_arguments sig) = List.length sig.(sig_args).
Proof.
  assert (forall tyl iregl fregl ofs,
    List.length (loc_arguments_rec tyl iregl fregl ofs) = List.length tyl).
  induction tyl; simpl; intros.
  auto.
  destruct a. 
  destruct iregl; simpl; decEq; auto.
  destruct fregl; simpl; decEq; auto.
  intros. unfold loc_arguments. auto.
Qed.

(** Argument locations agree in types with the function signature. *)

Lemma loc_arguments_type:
  forall sig, List.map Loc.type (loc_arguments sig) = sig.(sig_args).
Proof.
  assert (forall tyl iregl fregl ofs,
    (forall r, In r iregl -> mreg_type r = Tint) ->
    (forall r, In r fregl -> mreg_type r = Tfloat) ->
    List.map Loc.type (loc_arguments_rec tyl iregl fregl ofs) = tyl).
  induction tyl; simpl; intros.
  auto.
  destruct a; [destruct iregl|destruct fregl]; simpl;
  f_equal; eauto with coqlib.

  intros. unfold loc_arguments. apply H. 
  intro; simpl. ElimOrEq; reflexivity.
  intro; simpl. ElimOrEq; reflexivity.
Qed.

(** There is no partial overlap between an argument location and an
  acceptable location: they are either identical or disjoint. *)

Lemma no_overlap_arguments:
  forall args sg,
  locs_acceptable args ->
  Loc.no_overlap args (loc_arguments sg).
Proof.
  unfold Loc.no_overlap; intros.
  generalize (H r H0).
  generalize (loc_arguments_acceptable _ _ H1).
  destruct s; destruct r; simpl.
  intros. case (mreg_eq m0 m); intro. left; congruence. tauto.
  intros. right; destruct s; auto.
  intros. right. auto.
  destruct s; try tauto. destruct s0; tauto.
Qed.

(** Decide whether a tailcall is possible. *)

Definition tailcall_is_possible (sg: signature) : bool :=
  let fix tcisp (l: list loc) :=
    match l with
    | nil => true
    | R _ :: l' => tcisp l'
    | S _ :: l' => false
    end
  in tcisp (loc_arguments sg).

Lemma tailcall_is_possible_correct:
  forall s, tailcall_is_possible s = true -> tailcall_possible s.
Proof.
  intro s. unfold tailcall_is_possible, tailcall_possible.
  generalize (loc_arguments s). induction l; simpl; intros.
  elim H0.
  destruct a. 
  destruct H0. subst l0. auto. apply IHl. auto. auto. discriminate.
Qed.

(** ** Location of function parameters *)

(** A function finds the values of its parameter in the same locations
  where its caller stored them, except that the stack-allocated arguments,
  viewed as [Outgoing] slots by the caller, are accessed via [Incoming]
  slots (at the same offsets and types) in the callee. *)

Definition parameter_of_argument (l: loc) : loc :=
  match l with
  | S (Outgoing n ty) => S (Incoming n ty)
  | _ => l
  end.

Definition loc_parameters (s: signature) :=
  List.map parameter_of_argument (loc_arguments s).

Lemma loc_parameters_type:
  forall sig, List.map Loc.type (loc_parameters sig) = sig.(sig_args).
Proof.
  intros. unfold loc_parameters.
  rewrite list_map_compose. 
  rewrite <- loc_arguments_type.
  apply list_map_exten.
  intros. destruct x; simpl. auto. 
  destruct s; reflexivity.
Qed.

Lemma loc_parameters_length:
  forall sg, List.length (loc_parameters sg) = List.length sg.(sig_args).
Proof.
  intros. unfold loc_parameters. rewrite list_length_map. 
  apply loc_arguments_length.
Qed.

Lemma loc_parameters_not_temporaries:
  forall sig, Loc.disjoint (loc_parameters sig) temporaries.
Proof.
  intro; red; intros.
  unfold loc_parameters in H. 
  elim (list_in_map_inv _ _ _ H). intros y [EQ IN].
  generalize (loc_arguments_not_temporaries sig y x2 IN H0).
  subst x1. destruct x2.
  destruct y; simpl. auto. destruct s; auto.
  byContradiction. generalize H0. simpl. NotOrEq.
Qed.

Lemma no_overlap_parameters:
  forall params sg,
  locs_acceptable params ->
  Loc.no_overlap (loc_parameters sg) params.
Proof.
  unfold Loc.no_overlap; intros.
  unfold loc_parameters in H0. 
  elim (list_in_map_inv _ _ _ H0). intros t [EQ IN].
  rewrite EQ. 
  generalize (loc_arguments_acceptable _ _ IN).
  generalize (H s H1).
  destruct s; destruct t; simpl.
  intros. case (mreg_eq m0 m); intro. left; congruence. tauto.
  intros. right; destruct s; simpl; auto.
  intros; right; auto.
  destruct s; try tauto. destruct s0; try tauto. 
  intros; simpl. tauto.
Qed.
