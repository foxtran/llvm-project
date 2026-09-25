; REQUIRES: x86-registered-target

; The two-stage mode runs the complete ThinLTO and regular-LTO optimization
; pipelines, serializes their optimized IR, merges it, and runs a final
; regular-LTO pipeline before code generation.
;
; RUN: opt -module-summary %s -o %t.thin.o
; RUN: opt %p/Inputs/mixed_lto_two_stage_full_full.ll -o %t.full.o
; RUN: llvm-lto2 run -unified-lto=3 -save-temps -o %t.out \
; RUN:   %t.thin.o %t.full.o \
; RUN:   -r=%t.thin.o,main,px \
; RUN:   -r=%t.thin.o,force_target, \
; RUN:   -r=%t.thin.o,thin_only,px \
; RUN:   -r=%t.full.o,force_target,px \
; RUN:   -r=%t.full.o,full_only,px
; RUN: llvm-dis %t.out.0.4.opt.bc -o - | FileCheck %s --check-prefix=FULL-STAGE
; RUN: llvm-dis %t.out.1.4.opt.bc -o - | FileCheck %s --check-prefix=THIN-STAGE
; RUN: llvm-dis %t.out.2.5.precodegen.bc -o - | FileCheck %s --check-prefix=FINAL
;
; Mode 2 merges the optimized modules, rebuilds one summary, and runs the
; full ThinLTO pipeline. Both bodies are present BEFORE second-stage import.
; RUN: llvm-lto2 run -unified-lto=2 -save-temps -o %t.thin-final \
; RUN:   %t.thin.o %t.full.o \
; RUN:   -r=%t.thin.o,main,px \
; RUN:   -r=%t.thin.o,force_target, \
; RUN:   -r=%t.thin.o,thin_only,px \
; RUN:   -r=%t.full.o,force_target,px \
; RUN:   -r=%t.full.o,full_only,px
; RUN: llvm-dis %t.thin-final.0.4.opt.bc -o - | FileCheck %s --check-prefix=FULL-STAGE
; RUN: llvm-dis %t.thin-final.1.4.opt.bc -o - | FileCheck %s --check-prefix=THIN-STAGE
; RUN: llvm-dis %t.thin-final.3.0.preopt.bc -o - | FileCheck %s --check-prefix=MERGED
; RUN: llvm-dis %t.thin-final.3.1.promote.bc -o - | FileCheck %s --check-prefix=MERGED
; RUN: llvm-dis %t.thin-final.3.2.internalize.bc -o - | FileCheck %s --check-prefix=MERGED
; RUN: llvm-dis %t.thin-final.3.3.import.bc -o - | FileCheck %s --check-prefix=MERGED
; RUN: llvm-dis %t.thin-final.3.5.precodegen.bc -o - | FileCheck %s --check-prefix=FINAL
; RUN: not test -e %t.thin-final.2
; RUN: not test -e %t.thin-final.4
; RUN: not test -e %t.thin-final.0
; RUN: not test -e %t.thin-final.1
; RUN: not test -e %t.thin-final.0.5.precodegen.bc
; RUN: not test -e %t.thin-final.1.5.precodegen.bc

; FULL-STAGE-LABEL: define i32 @force_target(i32 %x)
; FULL-STAGE: %y = add i32 %x, 1
; FULL-STAGE-LABEL: define noundef i32 @full_only()
; FULL-STAGE-NEXT: entry:
; FULL-STAGE-NEXT: ret i32 42
;
; THIN-STAGE-LABEL: define i32 @main()
; THIN-STAGE: call i32 @force_target
; THIN-STAGE-LABEL: define noundef i32 @thin_only()
; THIN-STAGE-NEXT: entry:
; THIN-STAGE-NEXT: ret i32 42
;
; MERGED-LABEL: define i32 @force_target(i32 %x)
; MERGED: %y = add i32 %x, 1
; MERGED-LABEL: define i32 @main()
; MERGED: call i32 @force_target
; MERGED: !{i32 1, !"ThinLTO", i32 1}
;
; FINAL-LABEL: define noundef i32 @main()
; FINAL-NEXT: entry:
; FINAL-NEXT: ret i32 42
; FINAL-NOT: call i32 @force_target

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i32 @main() {
entry:
  %v = call i32 @force_target(i32 41)
  ret i32 %v
}

declare i32 @force_target(i32)

define i32 @thin_only() {
entry:
  %v = add i32 40, 2
  ret i32 %v
}
