; REQUIRES: x86

; --unified-lto=3 retains each input's own pre-link mode, but performs
; the final full-LTO optimization after the optimized ThinLTO IR is merged.
; RUN: opt -module-summary %s -o %t.thin.bc
; RUN: opt %S/Inputs/mixed-two-stage-full-full.ll -o %t.full.bc
; RUN: ld.lld --unified-lto=3 --save-temps -e main %t.thin.bc %t.full.bc -o %t.out
; RUN: llvm-dis %t.out.2.5.precodegen.bc -o - | FileCheck %s
;
; --unified-lto=2 runs the full ThinLTO pipeline on their merged optimized IR.
; RUN: ld.lld --unified-lto=2 --save-temps -e main %t.thin.bc %t.full.bc -o %t.thin-out
; RUN: llvm-dis %t.thin-out.3.5.precodegen.bc -o - | FileCheck %s --check-prefix=THIN
; RUN: not test -e %t.thin-out.4.5.precodegen.bc
; RUN: not test -e %t.thin-out.0.5.precodegen.bc
; RUN: not test -e %t.thin-out.1.5.precodegen.bc

; CHECK-LABEL: define dso_local noundef i32 @main()
; CHECK-NEXT: entry:
; CHECK-NEXT:   ret i32 42
; CHECK-NOT: call i32 @force_target
; THIN-LABEL: define dso_local noundef i32 @main()
; THIN-NEXT: entry:
; THIN-NEXT: ret i32 42
; THIN-NOT: call i32 @force_target

target triple = "x86_64-unknown-linux-gnu"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"

define i32 @main() {
entry:
  %v = call i32 @force_target(i32 41)
  ret i32 %v
}

declare i32 @force_target(i32)
