; REQUIRES: x86-registered-target
; RUN: rm -rf %t && split-file %s %t
; RUN: opt -module-summary %t/plain.ll -o %t/plain.bc
; RUN: opt -unified-lto -thinlto-bc %t/plain.ll -o %t/unified.bc
; RUN: opt -module-summary %t/split.ll -o %t/split.bc
; RUN: opt -module-summary %t/type.ll -o %t/type.bc
; RUN: opt %t/asm.ll -o %t/asm.bc
; RUN: opt -module-summary %t/mismatch.ll -o %t/mismatch.bc
; RUN: not llvm-lto2 run -two-stage-lto=full -cache-dir=%t/cache -o %t/out \
; RUN:   %t/plain.bc -r=%t/plain.bc,main,px 2>&1 | FileCheck %s --check-prefix=CACHE
; RUN: not llvm-lto2 run -two-stage-lto=full -thinlto-distributed-indexes -o %t/out \
; RUN:   %t/plain.bc -r=%t/plain.bc,main,px 2>&1 | FileCheck %s --check-prefix=CONFIG
; RUN: llvm-lto2 run -two-stage-lto=full -opt-pipeline=default\<O2\> -save-temps -o %t/custom \
; RUN:   %t/plain.bc -r=%t/plain.bc,main,px
; RUN: llvm-dis %t/custom.2.5.precodegen.bc -o - | FileCheck %s --check-prefix=CUSTOM
; RUN: llvm-lto2 run -two-stage-lto=full -aa-pipeline=basic-aa -save-temps -o %t/aa \
; RUN:   %t/plain.bc -r=%t/plain.bc,main,px
; RUN: llvm-dis %t/aa.2.5.precodegen.bc -o - | FileCheck %s --check-prefix=CUSTOM
;
; Omitting the option preserves the ordinary ThinLTO pipeline.
; RUN: llvm-lto2 run %t/plain.bc -save-temps -o %t/default \
; RUN:   -r=%t/plain.bc,main,px
; RUN: llvm-dis %t/default.1.0.preopt.bc -o - | FileCheck %s --check-prefix=DEFAULT
;
; RUN: not llvm-lto2 run -two-stage-lto=full -o %t/out \
; RUN:   %t/plain.bc %t/mismatch.bc \
; RUN:   -r=%t/plain.bc,main,px -r=%t/mismatch.bc,mismatch,px 2>&1 \
; RUN:   | FileCheck %s --check-prefix=TARGET
; RUN: llvm-lto2 run -two-stage-lto=thin -save-temps -o %t/thin \
; RUN:   %t/unified.bc -r=%t/unified.bc,main,px
; RUN: llvm-dis %t/thin.3.5.precodegen.bc -o - | FileCheck %s --check-prefix=THIN
; RUN: not test -e %t/thin.1.5.precodegen.bc
; RUN: not llvm-lto2 run -two-stage-lto=thin -cache-dir=%t/cache -o %t/out \
; RUN:   %t/plain.bc -r=%t/plain.bc,main,px 2>&1 | FileCheck %s --check-prefix=THIN-CACHE
; RUN: not llvm-lto2 run -two-stage-lto=thin -thinlto-distributed-indexes -o %t/out \
; RUN:   %t/plain.bc -r=%t/plain.bc,main,px 2>&1 | FileCheck %s --check-prefix=THIN-CONFIG
; RUN: not llvm-lto2 run -two-stage-lto=thin -o %t/out \
; RUN:   %t/plain.bc %t/mismatch.bc \
; RUN:   -r=%t/plain.bc,main,px -r=%t/mismatch.bc,mismatch,px 2>&1 \
; RUN:   | FileCheck %s --check-prefix=TARGET
; RUN: llvm-lto2 run -two-stage-lto=thin -opt-pipeline=default\<O2\> -aa-pipeline=basic-aa \
; RUN:   -save-temps -o %t/thin-custom %t/plain.bc -r=%t/plain.bc,main,px
; RUN: llvm-dis %t/thin-custom.3.5.precodegen.bc -o - | FileCheck %s --check-prefix=CUSTOM
;
; The upstream Unified LTO option still requires a value.
; RUN: not llvm-lto2 run --unified-lto 2>&1 | FileCheck %s --check-prefix=REQUIRED -DOPTION=unified-lto
;
; Unknown names, default, and all numeric spellings are invalid two-stage modes.
; RUN: not llvm-lto2 run --two-stage-lto=foo 2>&1 | FileCheck %s --check-prefix=INVALID -DVALUE=foo
; RUN: not llvm-lto2 run --two-stage-lto=default 2>&1 | FileCheck %s --check-prefix=INVALID -DVALUE=default
; RUN: not llvm-lto2 run --two-stage-lto=0 2>&1 | FileCheck %s --check-prefix=INVALID -DVALUE=0
; RUN: not llvm-lto2 run --two-stage-lto=1 2>&1 | FileCheck %s --check-prefix=INVALID -DVALUE=1
; RUN: not llvm-lto2 run --two-stage-lto=2 2>&1 | FileCheck %s --check-prefix=INVALID -DVALUE=2
; RUN: not llvm-lto2 run --two-stage-lto=3 2>&1 | FileCheck %s --check-prefix=INVALID -DVALUE=3
;
; Old two-stage mode names are invalid under both options.
; RUN: not llvm-lto2 run --two-stage-lto=two-stage-thin 2>&1 | FileCheck %s --check-prefix=INVALID -DVALUE=two-stage-thin
; RUN: not llvm-lto2 run --two-stage-lto=two-stage-full 2>&1 | FileCheck %s --check-prefix=INVALID -DVALUE=two-stage-full
; RUN: not llvm-lto2 run --unified-lto=two-stage-thin 2>&1 | FileCheck %s --check-prefix=INVALID -DVALUE=two-stage-thin
; RUN: not llvm-lto2 run --unified-lto=two-stage-full 2>&1 | FileCheck %s --check-prefix=INVALID -DVALUE=two-stage-full
;
; CACHE: two-stage full LTO does not yet support the native object cache
; CONFIG: two-stage full LTO requires an in-process backend and complete first-stage optimization
; CUSTOM: define noundef i32 @main()
; DEFAULT: define i32 @main()
; THIN: define noundef i32 @main()
; THIN-CACHE: two-stage ThinLTO does not yet support the native object cache
; THIN-CONFIG: two-stage ThinLTO requires an in-process backend and complete first-stage optimization
; TARGET: incompatible first-stage targets or layouts
; REQUIRED: for the --[[OPTION]] option: requires a value!
; INVALID: Cannot find option named '[[VALUE]]'!
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
