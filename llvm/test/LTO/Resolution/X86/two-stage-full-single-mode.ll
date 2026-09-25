; REQUIRES: x86-registered-target
; RUN: opt %s -o %t.full.bc
; RUN: opt -module-summary %s -o %t.thin.bc
;
; Missing either first-stage family is valid. No empty placeholder is merged
; or emitted, and the final task IDs still follow getMaxTasks().
; RUN: llvm-lto2 run -unified-lto=3 -save-temps -o %t.full \
; RUN:   %t.full.bc -r=%t.full.bc,main,px
; RUN: llvm-dis %t.full.0.4.opt.bc -o - | FileCheck %s
; RUN: llvm-dis %t.full.1.5.precodegen.bc -o - | FileCheck %s
; RUN: llvm-nm %t.full.1 | FileCheck %s --check-prefix=NM
; RUN: not test -e %t.full.0
;
; RUN: llvm-lto2 run -unified-lto=3 -save-temps -o %t.thin \
; RUN:   %t.thin.bc -r=%t.thin.bc,main,px
; RUN: llvm-dis %t.thin.1.4.opt.bc -o - | FileCheck %s
; RUN: llvm-dis %t.thin.2.5.precodegen.bc -o - | FileCheck %s
; RUN: llvm-nm %t.thin.2 | FileCheck %s --check-prefix=NM
; RUN: not test -e %t.thin.0
; RUN: not test -e %t.thin.1
;
; RUN: llvm-lto2 run -unified-lto=2 -save-temps -o %t.full-final-thin \
; RUN:   %t.full.bc -r=%t.full.bc,main,px
; RUN: llvm-dis %t.full-final-thin.0.4.opt.bc -o - | FileCheck %s
; RUN: llvm-dis %t.full-final-thin.2.5.precodegen.bc -o - | FileCheck %s
; RUN: llvm-nm %t.full-final-thin.2 | FileCheck %s --check-prefix=NM
; RUN: not test -e %t.full-final-thin.0
; RUN: not test -e %t.full-final-thin.1
; RUN: not test -e %t.full-final-thin.3
; RUN: llvm-lto2 run -unified-lto=2 -save-temps -o %t.thin-final-thin \
; RUN:   %t.thin.bc -r=%t.thin.bc,main,px
; RUN: llvm-dis %t.thin-final-thin.1.4.opt.bc -o - | FileCheck %s
; RUN: llvm-dis %t.thin-final-thin.3.5.precodegen.bc -o - | FileCheck %s
; RUN: llvm-nm %t.thin-final-thin.3 | FileCheck %s --check-prefix=NM
; RUN: not test -e %t.thin-final-thin.0
; RUN: not test -e %t.thin-final-thin.1
; RUN: not test -e %t.thin-final-thin.2
; RUN: not test -e %t.thin-final-thin.4
;
; CHECK-LABEL: define noundef i32 @main()
; CHECK-NEXT: entry:
; CHECK-NEXT: ret i32 42
; NM: T main

target triple = "x86_64-unknown-linux-gnu"
define i32 @main() {
entry:
  %v = add i32 40, 2
  ret i32 %v
}
