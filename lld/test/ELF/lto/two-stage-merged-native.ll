; REQUIRES: x86
; RUN: split-file %s %t
; RUN: opt %t/full.ll -o %t/full.bc
; RUN: opt -module-summary %t/thin.ll -o %t/thin.bc
; RUN: llc -filetype=obj %t/native.ll -o %t/native.o
;
; A native object both references main and overrides a weak IR definition.
; The merged second stage must preserve main and the call to the native
; definition, while inlining across the original Full/Thin boundary.
; RUN: ld.lld --unified-lto=2 --save-temps -e entry \
; RUN:   %t/full.bc %t/thin.bc %t/native.o -o %t/thin-out
; RUN: llvm-dis %t/thin-out.3.5.precodegen.bc -o - | FileCheck %s
; RUN: llvm-nm %t/thin-out | FileCheck %s --check-prefix=NM
; RUN: ld.lld --unified-lto=3 --save-temps -e entry \
; RUN:   %t/full.bc %t/thin.bc %t/native.o -o %t/full-out
; RUN: llvm-dis %t/full-out.2.5.precodegen.bc -o - | FileCheck %s
; RUN: llvm-nm %t/full-out | FileCheck %s --check-prefix=NM
;
; Deterministic output regardless of first-stage backend concurrency.
; RUN: ld.lld --unified-lto=2 --thinlto-jobs=1 -e entry \
; RUN:   %t/full.bc %t/thin.bc %t/native.o -o %t/serial
; RUN: cmp %t/thin-out %t/serial
;
; CHECK-NOT: define {{.*}}@override(
; CHECK-LABEL: define dso_local i32 @main()
; CHECK: %[[V:.*]] = {{(tail )?}}call i32 @override()
; CHECK: add i32 %[[V]], 42
; CHECK-NOT: define {{.*}}@override(
; NM: T entry
; NM: T main
; NM: T override
;
;--- full.ll
; Deliberately omit GUIDs, as in older bitcode and freshly generated IR.
target triple = "x86_64-unknown-linux-gnu"
define i32 @main() {
  %a = call i32 @callee(i32 41)
  %b = call i32 @override()
  %sum = add i32 %a, %b
  ret i32 %sum
}
declare i32 @callee(i32)
declare i32 @override()
;
;--- thin.ll
target triple = "x86_64-unknown-linux-gnu"
define i32 @callee(i32 %x) {
  %y = add i32 %x, 1
  ret i32 %y
}
define weak i32 @override() { ret i32 7 }
;
;--- native.ll
target triple = "x86_64-unknown-linux-gnu"
define i32 @entry() {
  %v = call i32 @main()
  ret i32 %v
}
define i32 @override() { ret i32 100 }
declare i32 @main()
