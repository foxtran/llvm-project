; REQUIRES: x86-registered-target
; RUN: split-file %s %t
; RUN: opt -module-summary %t/full.ll -o %t/full.bc
; RUN: opt -module-summary %t/thin.ll -o %t/thin.bc
; RUN: opt -module-summary %t/helper.ll -o %t/helper.bc
; RUN: llvm-lto2 run -unified-lto=3 -save-temps -o %t/out \
; RUN:   %t/full.bc %t/thin.bc %t/helper.bc \
; RUN:   -r=%t/full.bc,main,px -r=%t/full.bc,thin, \
; RUN:   -r=%t/thin.bc,thin,p -r=%t/thin.bc,helper, -r=%t/helper.bc,helper,p
; RUN: llvm-dis %t/out.0.4.opt.bc -o - | FileCheck %s --check-prefix=FULL
; RUN: llvm-dis %t/out.1.3.import.bc -o - | FileCheck %s --check-prefix=IMPORT
; RUN: llvm-dis %t/out.1.4.opt.bc -o - | FileCheck %s --check-prefix=THIN
; RUN: llvm-dis %t/out.3.0.preopt.bc -o - | FileCheck %s --check-prefix=FULL
; RUN: llvm-dis %t/out.3.5.precodegen.bc -o - | FileCheck %s --check-prefix=FINAL
; RUN: llvm-nm %t/out.3 | FileCheck %s --check-prefix=OBJECT
; RUN: not test -e %t/out.0
; RUN: not test -e %t/out.1
; RUN: not test -e %t/out.2
;
; RUN: llvm-lto2 run -unified-lto=2 -save-temps -o %t/thin-out \
; RUN:   %t/full.bc %t/thin.bc %t/helper.bc \
; RUN:   -r=%t/full.bc,main,px -r=%t/full.bc,thin, \
; RUN:   -r=%t/thin.bc,thin,p -r=%t/thin.bc,helper, -r=%t/helper.bc,helper,p
; RUN: llvm-dis %t/thin-out.0.4.opt.bc -o - | FileCheck %s --check-prefix=FULL
; RUN: llvm-dis %t/thin-out.1.3.import.bc -o - | FileCheck %s --check-prefix=IMPORT
; RUN: llvm-dis %t/thin-out.1.4.opt.bc -o - | FileCheck %s --check-prefix=THIN
; RUN: llvm-dis %t/thin-out.4.0.preopt.bc -o - | FileCheck %s --check-prefixes=FULL,MERGED
; RUN: llvm-dis %t/thin-out.4.1.promote.bc -o - | FileCheck %s --check-prefix=RESOLVED
; RUN: llvm-dis %t/thin-out.4.2.internalize.bc -o - | FileCheck %s --check-prefix=INTERNALIZED
; RUN: llvm-dis %t/thin-out.4.3.import.bc -o - | FileCheck %s --check-prefix=INTERNALIZED
; RUN: llvm-dis %t/thin-out.4.5.precodegen.bc -o - | FileCheck %s --check-prefix=FINAL
; RUN: llvm-nm %t/thin-out.4 | FileCheck %s --check-prefix=OBJECT
; RUN: not test -e %t/thin-out.0
; RUN: not test -e %t/thin-out.1
; RUN: not test -e %t/thin-out.2
; RUN: not test -e %t/thin-out.3
; RUN: not test -e %t/thin-out.5
; RUN: llvm-dis %t/thin-out.index.bc -o - | FileCheck %s --check-prefix=INDEX1
; RUN: llvm-dis %t/thin-out.stage2.index.bc -o - | FileCheck %s --check-prefix=INDEX2
;
; INDEX1: path: "{{.*}}thin.bc"
; INDEX1-NOT: ld-temp.stage2
; INDEX2: ^0 = module: (path: "ld-temp.stage2.merged"
; INDEX2-NOT: = module:
; INDEX2: ^1 = gv:
;
; Full input has a summary: its deferred linking must happen exactly once.
; Clang sets EnableSplitLTOUnit=1 on such full-LTO modules even though they
; are not split containers. Accept this alongside unsplit ThinLTO modules.
; The ThinLTO stage really imports from a second ThinLTO module, then optimizes
; the imported body. The second stage sees both main and thin in one module.
; FULL-LABEL: define i32 @main()
; FULL: call i32 @thin(i32 41)
; MERGED: define i32 @thin(i32 %x)
; MERGED-NOT: call i32 @helper
; MERGED: add i32 %x, 1
; MERGED: define i32 @helper(i32 %x)
;
; Prove that the fresh thin link actually resolves liveness/internalization,
; rather than just running a ThinLTO optimization pipeline on merged IR.
; RESOLVED: define i32 @main()
; RESOLVED: define i32 @thin(i32 %x)
; RESOLVED-NOT: define {{.*}}@helper(
; INTERNALIZED: define i32 @main()
; INTERNALIZED: define internal i32 @thin(i32 %x)
; INTERNALIZED-NOT: define {{.*}}@helper(
; IMPORT: define available_externally i32 @helper(
; THIN-LABEL: define i32 @thin(i32 %x)
; THIN-NOT: call
; THIN: add i32 %x, 1
; THIN: ret i32
; FINAL-LABEL: define noundef i32 @main()
; FINAL-NEXT: entry:
; FINAL-NEXT: ret i32 42
; OBJECT: T main
;
;--- full.ll
source_filename = "full.c"
target triple = "x86_64-unknown-linux-gnu"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
define i32 @main() {
entry:
  %v = call i32 @thin(i32 41)
  ret i32 %v
}
declare i32 @thin(i32)
!llvm.module.flags = !{!0, !1}
!0 = !{i32 1, !"ThinLTO", i32 0}
!1 = !{i32 1, !"EnableSplitLTOUnit", i32 1}

;--- thin.ll
source_filename = "thin.c"
target triple = "x86_64-unknown-linux-gnu"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
define i32 @thin(i32 %x) {
  %v = call i32 @helper(i32 %x)
  ret i32 %v
}
declare i32 @helper(i32)

;--- helper.ll
source_filename = "helper.c"
target triple = "x86_64-unknown-linux-gnu"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
define i32 @helper(i32 %x) {
  %v = add i32 %x, 1
  ret i32 %v
}
