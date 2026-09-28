; REQUIRES: x86-registered-target
; RUN: opt %s -o %t.full.bc
; RUN: opt -module-summary %s -o %t.thin.bc
;
; Omitting the option preserves ordinary LTO's task IDs and output.
; RUN: llvm-lto2 run -o %t.implicit %t.full.bc -r=%t.full.bc,main,px
; RUN: llvm-nm %t.implicit.0 | FileCheck %s --check-prefix=NM
;
; Missing either first-stage family is valid. No empty placeholder is merged
; or emitted, and the final task IDs still follow getMaxTasks().
; RUN: llvm-lto2 run -two-stage-lto=full -save-temps -o %t.full \
; RUN:   %t.full.bc -r=%t.full.bc,main,px
; RUN: llvm-dis %t.full.0.4.opt.bc -o - | FileCheck %s
; RUN: llvm-dis %t.full.1.5.precodegen.bc -o - | FileCheck %s
; RUN: llvm-nm %t.full.1 | FileCheck %s --check-prefix=NM
; RUN: not test -e %t.full.0
;
; Bare spelling selects full and leaves the next input positional. Check the
; final task as well as its output to distinguish it from ThinLTO and ordinary LTO.
; RUN: rm -f %t.bare.0 %t.bare.1 %t.bare.2
; RUN: llvm-lto2 run --two-stage-lto %t.full.bc -o %t.bare -r=%t.full.bc,main,px
; RUN: cmp %t.full.1 %t.bare.1
; RUN: not test -e %t.bare.0
; RUN: not test -e %t.bare.2
; The optional enum parser also treats an empty value as full.
; RUN: rm -f %t.empty.0 %t.empty.1 %t.empty.2
; RUN: llvm-lto2 run --two-stage-lto= %t.full.bc -o %t.empty -r=%t.full.bc,main,px
; RUN: cmp %t.full.1 %t.empty.1
;
; RUN: llvm-lto2 run -two-stage-lto=full -save-temps -o %t.thin \
; RUN:   %t.thin.bc -r=%t.thin.bc,main,px
; RUN: llvm-dis %t.thin.1.4.opt.bc -o - | FileCheck %s
; RUN: llvm-dis %t.thin.2.5.precodegen.bc -o - | FileCheck %s
; RUN: llvm-nm %t.thin.2 | FileCheck %s --check-prefix=NM
; RUN: not test -e %t.thin.0
; RUN: not test -e %t.thin.1
;
; RUN: llvm-lto2 run -two-stage-lto=thin -save-temps -o %t.full-final-thin \
; RUN:   %t.full.bc -r=%t.full.bc,main,px
; RUN: llvm-dis %t.full-final-thin.0.4.opt.bc -o - | FileCheck %s
; RUN: llvm-dis %t.full-final-thin.2.5.precodegen.bc -o - | FileCheck %s
; RUN: llvm-nm %t.full-final-thin.2 | FileCheck %s --check-prefix=NM
; RUN: not test -e %t.full-final-thin.0
; RUN: not test -e %t.full-final-thin.1
; RUN: not test -e %t.full-final-thin.3
; RUN: llvm-lto2 run -two-stage-lto=thin -save-temps -o %t.thin-final-thin \
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
