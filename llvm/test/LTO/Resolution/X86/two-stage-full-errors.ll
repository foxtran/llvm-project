; REQUIRES: x86-registered-target
; RUN: rm -rf %t && split-file %s %t
; RUN: opt -module-summary %t/plain.ll -o %t/plain.bc
; RUN: opt -unified-lto -thinlto-bc %t/plain.ll -o %t/unified.bc
; RUN: opt -module-summary %t/split.ll -o %t/split.bc
; RUN: opt -module-summary %t/type.ll -o %t/type.bc
; RUN: opt %t/asm.ll -o %t/asm.bc
; RUN: opt -module-summary %t/mismatch.ll -o %t/mismatch.bc
; RUN: not llvm-lto2 run -unified-lto=3 -cache-dir=%t/cache -o %t/out \
; RUN:   %t/plain.bc -r=%t/plain.bc,main,px 2>&1 | FileCheck %s --check-prefix=CACHE
; RUN: not llvm-lto2 run -unified-lto=3 -thinlto-distributed-indexes -o %t/out \
; RUN:   %t/plain.bc -r=%t/plain.bc,main,px 2>&1 | FileCheck %s --check-prefix=CONFIG
; RUN: llvm-lto2 run -unified-lto=3 -opt-pipeline=default\<O2\> -save-temps -o %t/custom \
; RUN:   %t/plain.bc -r=%t/plain.bc,main,px
; RUN: llvm-dis %t/custom.2.5.precodegen.bc -o - | FileCheck %s --check-prefix=CUSTOM
; RUN: llvm-lto2 run -unified-lto=3 -aa-pipeline=basic-aa -save-temps -o %t/aa \
; RUN:   %t/plain.bc -r=%t/plain.bc,main,px
; RUN: llvm-dis %t/aa.2.5.precodegen.bc -o - | FileCheck %s --check-prefix=CUSTOM
;
; Bare spelling preserves the mode-0 pipeline and leaves the input positional.
; RUN: llvm-lto2 run --unified-lto %t/plain.bc -save-temps -o %t/bare \
; RUN:   -r=%t/plain.bc,main,px
; RUN: llvm-dis %t/bare.1.0.preopt.bc -o - | FileCheck %s --check-prefix=BARE
; RUN: llvm-lto2 run --unified-lto=0 %t/plain.bc -save-temps -o %t/zero \
; RUN:   -r=%t/plain.bc,main,px
; RUN: cmp %t/bare.1.5.precodegen.bc %t/zero.1.5.precodegen.bc
; RUN: cmp %t/bare.1 %t/zero.1
;
; RUN: not llvm-lto2 run -unified-lto=3 -o %t/out \
; RUN:   %t/plain.bc %t/mismatch.bc \
; RUN:   -r=%t/plain.bc,main,px -r=%t/mismatch.bc,mismatch,px 2>&1 \
; RUN:   | FileCheck %s --check-prefix=TARGET
; RUN: llvm-lto2 run -unified-lto=2 -save-temps -o %t/thin \
; RUN:   %t/unified.bc -r=%t/unified.bc,main,px
; RUN: llvm-dis %t/thin.3.5.precodegen.bc -o - | FileCheck %s --check-prefix=THIN
; RUN: not test -e %t/thin.1.5.precodegen.bc
; RUN: not llvm-lto2 run -unified-lto=2 -cache-dir=%t/cache -o %t/out \
; RUN:   %t/plain.bc -r=%t/plain.bc,main,px 2>&1 | FileCheck %s --check-prefix=THIN-CACHE
; RUN: not llvm-lto2 run -unified-lto=2 -thinlto-distributed-indexes -o %t/out \
; RUN:   %t/plain.bc -r=%t/plain.bc,main,px 2>&1 | FileCheck %s --check-prefix=THIN-CONFIG
; RUN: not llvm-lto2 run -unified-lto=2 -o %t/out \
; RUN:   %t/plain.bc %t/mismatch.bc \
; RUN:   -r=%t/plain.bc,main,px -r=%t/mismatch.bc,mismatch,px 2>&1 \
; RUN:   | FileCheck %s --check-prefix=TARGET
; RUN: llvm-lto2 run -unified-lto=2 -opt-pipeline=default\<O2\> -aa-pipeline=basic-aa \
; RUN:   -save-temps -o %t/thin-custom %t/plain.bc -r=%t/plain.bc,main,px
; RUN: llvm-dis %t/thin-custom.3.5.precodegen.bc -o - | FileCheck %s --check-prefix=CUSTOM
; RUN: not llvm-lto2 run -unified-lto=1 -o %t/out \
; RUN:   %t/plain.bc -r=%t/plain.bc,main,px 2>&1 | FileCheck %s --check-prefix=RESERVED
;
; CACHE: two-stage full LTO does not yet support the native object cache
; CONFIG: two-stage full LTO requires an in-process backend and complete first-stage optimization
; CUSTOM: define noundef i32 @main()
; BARE: define i32 @main()
; THIN: define noundef i32 @main()
; THIN-CACHE: two-stage ThinLTO does not yet support the native object cache
; THIN-CONFIG: two-stage ThinLTO requires an in-process backend and complete first-stage optimization
; TARGET: incompatible first-stage targets or layouts
; RESERVED: unified LTO mode 1 is reserved
;
;--- plain.ll
target triple = "x86_64-unknown-linux-gnu"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
define i32 @main() { ret i32 0 }

;--- split.ll
target triple = "x86_64-unknown-linux-gnu"
define i32 @main() { ret i32 0 }
!llvm.module.flags = !{!0}
!0 = !{i32 1, !"EnableSplitLTOUnit", i32 1}

;--- type.ll
target triple = "x86_64-unknown-linux-gnu"
define i32 @main() !type !0 { ret i32 0 }
!0 = !{i64 0, !"typeid"}

;--- asm.ll
target triple = "x86_64-unknown-linux-gnu"
module asm ".text"
define i32 @main() { ret i32 0 }

;--- mismatch.ll
target triple = "x86_64-unknown-linux-gnu"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-n8:16:32:64-S128"
define i32 @mismatch() { ret i32 0 }
