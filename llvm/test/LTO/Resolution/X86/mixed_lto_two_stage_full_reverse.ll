; REQUIRES: x86-registered-target

; Test the opposite cross-mode direction: the regular/full-LTO module contains
; the caller and the ThinLTO module contains the callee.
;
; RUN: opt %s -o %t.full.o
; RUN: opt -module-summary %p/Inputs/mixed_lto_two_stage_full_reverse_thin.ll \
; RUN:   -o %t.thin.o
; RUN: llvm-lto2 run -unified-lto=3 -save-temps -o %t.out \
; RUN:   %t.full.o %t.thin.o \
; RUN:   -r=%t.full.o,main,px \
; RUN:   -r=%t.full.o,thin_target, \
; RUN:   -r=%t.thin.o,thin_target,px \
; RUN:   -r=%t.thin.o,thin_only,px
; RUN: llvm-dis %t.out.0.4.opt.bc -o - | FileCheck %s --check-prefix=FULL-STAGE
; RUN: llvm-dis %t.out.1.4.opt.bc -o - | FileCheck %s --check-prefix=THIN-STAGE
; RUN: llvm-dis %t.out.2.5.precodegen.bc -o - | FileCheck %s --check-prefix=FINAL
;
; The merged IR becomes one ThinLTO module containing both caller and callee.
; RUN: llvm-lto2 run -unified-lto=2 -save-temps -o %t.thin-final \
; RUN:   %t.full.o %t.thin.o \
; RUN:   -r=%t.full.o,main,px \
; RUN:   -r=%t.full.o,thin_target, \
; RUN:   -r=%t.thin.o,thin_target,px \
; RUN:   -r=%t.thin.o,thin_only,px
; RUN: llvm-dis %t.thin-final.0.4.opt.bc -o - | FileCheck %s --check-prefix=FULL-STAGE
; RUN: llvm-dis %t.thin-final.1.4.opt.bc -o - | FileCheck %s --check-prefix=THIN-STAGE
; RUN: llvm-dis %t.thin-final.3.0.preopt.bc -o - | FileCheck %s --check-prefix=MERGED
; RUN: llvm-dis %t.thin-final.3.3.import.bc -o - | FileCheck %s --check-prefix=MERGED
; RUN: llvm-dis %t.thin-final.3.5.precodegen.bc -o - | FileCheck %s --check-prefix=FINAL
; RUN: not test -e %t.thin-final.0
; RUN: not test -e %t.thin-final.1
; RUN: not test -e %t.thin-final.0.5.precodegen.bc
; RUN: not test -e %t.thin-final.1.5.precodegen.bc

; FULL-STAGE-LABEL: define i32 @main()
; FULL-STAGE: call i32 @thin_target
;
; THIN-STAGE-LABEL: define noundef i32 @thin_only()
; THIN-STAGE-NEXT: entry:
; THIN-STAGE-NEXT: ret i32 42
;
; MERGED-LABEL: define i32 @main()
; MERGED: call i32 @thin_target
; MERGED-LABEL: define i32 @thin_target(i32 %x)
;
; FINAL-LABEL: define noundef i32 @main()
; FINAL-NEXT: entry:
; FINAL-NEXT: ret i32 42
; FINAL-NOT: call i32 @thin_target

target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

define i32 @main() {
entry:
  %v = call i32 @thin_target(i32 41)
  ret i32 %v
}

declare i32 @thin_target(i32)
