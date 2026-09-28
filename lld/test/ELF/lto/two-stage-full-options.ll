; REQUIRES: x86
; RUN: rm -rf %t && split-file %s %t
; RUN: opt %t/caller.ll -o %t/full.bc
; RUN: opt -module-summary %t/callee.ll -o %t/thin.bc
;
; Ordinary mixed mode retains the cross-boundary call.
; RUN: ld.lld --save-temps -e main %t/full.bc %t/thin.bc -o %t/default
; RUN: llvm-dis %t/default.0.5.precodegen.bc -o - | FileCheck %s --check-prefix=CALL
;
; Reverse direction from mixed-two-stage-full.ll. The final stage uses one
; module/task even when the original link reserves multiple LTO partitions.
; RUN: ld.lld --two-stage-lto=full --lto-partitions=2 --save-temps \
; RUN:   -e main %t/full.bc %t/thin.bc -o %t/out
; RUN: llvm-dis %t/out.0.4.opt.bc -o - | FileCheck %s --check-prefix=CALL
; RUN: llvm-dis %t/out.3.0.preopt.bc -o - | FileCheck %s --check-prefix=CALL
; RUN: llvm-dis %t/out.3.4.opt.bc -o - | FileCheck %s --check-prefix=FINAL
; RUN: llvm-dis %t/out.3.5.precodegen.bc -o - | FileCheck %s --check-prefix=FINAL
; RUN: not test -e %t/out.4.5.precodegen.bc
;
; Bare spelling selects the same full-LTO final stage, not ThinLTO or ordinary LTO.
; RUN: ld.lld --two-stage-lto %t/full.bc %t/thin.bc --lto-partitions=2 \
; RUN:   --save-temps -e main -o %t/bare
; RUN: llvm-dis %t/bare.3.5.precodegen.bc -o - | FileCheck %s --check-prefix=FINAL
; RUN: not test -e %t/bare.4.5.precodegen.bc
; RUN: cmp %t/out %t/bare
;
; RUN: ld.lld --two-stage-lto=thin --lto-partitions=2 --save-temps \
; RUN:   -e main %t/full.bc %t/thin.bc -o %t/thin-out
; RUN: llvm-dis %t/thin-out.4.0.preopt.bc -o - | FileCheck %s --check-prefix=CALL
; RUN: llvm-dis %t/thin-out.4.5.precodegen.bc -o - | FileCheck %s --check-prefix=FINAL
; RUN: not test -e %t/thin-out.5.5.precodegen.bc
; RUN: llvm-nm %t/out | FileCheck %s --check-prefix=OBJECT
; RUN: not test -e %t/out.lto.o
; RUN: not test -e %t/out.lto.1.o
; RUN: not test -e %t/out.lto.thin.o
;
; Final-stage pre-codegen hooks also work for bitcode-only output.
; RUN: ld.lld --two-stage-lto=full --lto-emit-llvm -e main \
; RUN:   %t/full.bc %t/thin.bc -o %t/emit.bc
; RUN: llvm-dis %t/emit.bc -o - | FileCheck %s --check-prefix=EMIT
; RUN: ld.lld --two-stage-lto=thin --lto-emit-llvm -e main \
; RUN:   %t/full.bc %t/thin.bc -o %t/thin-emit.bc
; RUN: llvm-dis %t/thin-emit.bc -o - | FileCheck %s --check-prefix=EMIT
;
; Unsupported combinations fail explicitly, not with incomplete output.
; RUN: not ld.lld --two-stage-lto=full --thinlto-cache-dir=%t/cache -e main \
; RUN:   %t/full.bc %t/thin.bc -o %t/error 2>&1 | FileCheck %s --check-prefix=CACHE
; RUN: not ld.lld --two-stage-lto=full --thinlto-index-only -e main \
; RUN:   %t/full.bc %t/thin.bc -o %t/error 2>&1 | FileCheck %s --check-prefix=CONFIG
;
; Only --two-stage-lto selects the second stage. Neither the legacy backend
; option nor its position changes the result for ordinary mixed inputs.
; RUN: ld.lld --lto=full --two-stage-lto=thin --lto-partitions=2 \
; RUN:   -e main %t/full.bc %t/thin.bc -o %t/thin-with-full
; RUN: cmp %t/thin-out %t/thin-with-full
; RUN: ld.lld --two-stage-lto=thin --lto=thin --lto-partitions=2 \
; RUN:   -e main %t/full.bc %t/thin.bc -o %t/thin-with-thin
; RUN: cmp %t/thin-out %t/thin-with-thin
; RUN: ld.lld --two-stage-lto=full --lto=full --lto-partitions=2 \
; RUN:   -e main %t/full.bc %t/thin.bc -o %t/full-with-full
; RUN: cmp %t/out %t/full-with-full
; RUN: ld.lld --lto=thin --two-stage-lto=full --lto-partitions=2 \
; RUN:   -e main %t/full.bc %t/thin.bc -o %t/full-with-thin
; RUN: cmp %t/out %t/full-with-thin
;
; Unified LTO input also works, but the merged module has an ld-temp.o FILE symbol.
; RUN: opt -thinlto-bc -thinlto-split-lto-unit -unified-lto %t/unified.ll -o %t/unified.bc
; RUN: ld.lld --two-stage-lto=thin %t/unified.bc -o %t/unified
; RUN: llvm-readelf -s %t/unified | FileCheck %s --check-prefix=UNIFIED
;
; CALL-LABEL: define dso_local i32 @main()
; CALL: call i32 @callee(i32 41)
; FINAL-LABEL: define dso_local noundef i32 @main()
; FINAL-NEXT: entry:
; FINAL-NEXT: ret i32 42
; EMIT-LABEL: define dso_local noundef i32 @main()
; EMIT-NEXT: ret i32 42
; OBJECT: T main
; CACHE: two-stage full LTO does not yet support the native object cache
; CONFIG: two-stage full LTO requires an in-process backend and complete first-stage optimization
;
; UNIFIED:      Symbol table '.symtab' contains 3 entries:
; UNIFIED-NEXT: Num:    Value          Size Type    Bind   Vis       Ndx Name
; UNIFIED-NEXT: 0: 0000000000000000     0 NOTYPE  LOCAL  DEFAULT   UND
; UNIFIED-NEXT: 1: 0000000000000000     0 FILE    LOCAL  DEFAULT   ABS ld-temp.o
; UNIFIED-NEXT: 2: 0000000000201120     1 FUNC    GLOBAL DEFAULT     1 _start
;
;--- caller.ll
target triple = "x86_64-unknown-linux-gnu"
define i32 @main() {
entry:
  %v = call i32 @callee(i32 41)
  ret i32 %v
}
declare i32 @callee(i32)

;--- callee.ll
target triple = "x86_64-unknown-linux-gnu"
define i32 @callee(i32 %x) {
  %v = add i32 %x, 1
  ret i32 %v
}

;--- unified.ll
target triple = "x86_64-unknown-linux-gnu"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"

define void @_start() {
  ret void
}
