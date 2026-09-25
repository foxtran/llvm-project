; REQUIRES: x86
; RUN: split-file %s %t
; RUN: opt %t/caller.ll -o %t/full.bc
; RUN: opt -module-summary %t/callee.ll -o %t/thin.bc
;
; Ordinary mixed mode retains the cross-boundary call.
; RUN: ld.lld --unified-lto=0 --save-temps -e main %t/full.bc %t/thin.bc -o %t/default
; RUN: llvm-dis %t/default.0.5.precodegen.bc -o - | FileCheck %s --check-prefix=CALL
;
; Bare spelling is an alias for mode 0, and must not consume the next input.
; RUN: ld.lld --unified-lto %t/full.bc %t/thin.bc --save-temps -e main -o %t/bare
; RUN: llvm-dis %t/bare.0.5.precodegen.bc -o - | FileCheck %s --check-prefix=CALL
; RUN: cmp %t/default %t/bare
; RUN: ld.lld --unified-lto=3 --unified-lto %t/full.bc %t/thin.bc -e main -o %t/reset
; RUN: cmp %t/default %t/reset
;
; Reverse direction from mixed-two-stage-full.ll. The final stage uses one
; module/task even when the original link reserves multiple LTO partitions.
; RUN: ld.lld --unified-lto=3 --lto-partitions=2 --save-temps \
; RUN:   -e main %t/full.bc %t/thin.bc -o %t/out
; RUN: llvm-dis %t/out.0.4.opt.bc -o - | FileCheck %s --check-prefix=CALL
; RUN: llvm-dis %t/out.3.0.preopt.bc -o - | FileCheck %s --check-prefix=CALL
; RUN: llvm-dis %t/out.3.4.opt.bc -o - | FileCheck %s --check-prefix=FINAL
; RUN: llvm-dis %t/out.3.5.precodegen.bc -o - | FileCheck %s --check-prefix=FINAL
; RUN: not test -e %t/out.4.5.precodegen.bc
;
; RUN: ld.lld --unified-lto=2 --lto-partitions=2 --save-temps \
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
; RUN: ld.lld --unified-lto=3 --lto-emit-llvm -e main \
; RUN:   %t/full.bc %t/thin.bc -o %t/emit.bc
; RUN: llvm-dis %t/emit.bc -o - | FileCheck %s --check-prefix=EMIT
; RUN: ld.lld --unified-lto=2 --lto-emit-llvm -e main \
; RUN:   %t/full.bc %t/thin.bc -o %t/thin-emit.bc
; RUN: llvm-dis %t/thin-emit.bc -o - | FileCheck %s --check-prefix=EMIT
; RUN: ld.lld --unified-lto --unified-lto=3 --lto-emit-llvm -e main \
; RUN:   %t/full.bc %t/thin.bc -o %t/bare-then-3.bc
; RUN: llvm-dis %t/bare-then-3.bc -o - | FileCheck %s --check-prefix=EMIT
;
; Unsupported combinations fail explicitly, not with incomplete output.
; RUN: not ld.lld --unified-lto=3 --thinlto-cache-dir=%t/cache -e main \
; RUN:   %t/full.bc %t/thin.bc -o %t/error 2>&1 | FileCheck %s --check-prefix=CACHE
; RUN: not ld.lld --unified-lto=3 --thinlto-index-only -e main \
; RUN:   %t/full.bc %t/thin.bc -o %t/error 2>&1 | FileCheck %s --check-prefix=CONFIG
; RUN: not ld.lld --unified-lto=1 -e main \
; RUN:   %t/full.bc %t/thin.bc -o %t/error 2>&1 | FileCheck %s --check-prefix=RESERVED
;
; --lto=full still requires unified bitcode, not arbitrary mixed inputs.
; RUN: not ld.lld --lto=full -e main %t/full.bc %t/thin.bc -o %t/error 2>&1 \
; RUN:   | FileCheck %s --check-prefix=UNIFIED
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
; RESERVED: unified LTO mode 1 is reserved
; UNIFIED: unified LTO compilation must use compatible bitcode modules
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
