; REQUIRES: x86-registered-target
; RUN: split-file %s %t
; RUN: opt -module-summary %t/thin.ll -o %t/thin.bc
; RUN: opt -passes=assign-guid %t/full.ll -o %t/full.bc
; RUN: llvm-lto2 run -unified-lto=3 -save-temps -o %t/out \
; RUN:   %t/thin.bc %t/full.bc \
; RUN:   -r=%t/thin.bc,thin_addr,plx -r=%t/thin.bc,choice,l \
; RUN:   -r=%t/thin.bc,odr,plx \
; RUN:   -r=%t/full.bc,full_addr,plx -r=%t/full.bc,full_alias,plx \
; RUN:   -r=%t/full.bc,choice,plx -r=%t/full.bc,odr,l
; RUN: llvm-dis %t/out.2.5.precodegen.bc -o - | FileCheck %s
; RUN: llvm-nm %t/out.2 | FileCheck %s --check-prefix=NM
;
; RUN: llvm-lto2 run -unified-lto=2 -save-temps -o %t/thin-out \
; RUN:   %t/thin.bc %t/full.bc \
; RUN:   -r=%t/thin.bc,thin_addr,plx -r=%t/thin.bc,choice,l \
; RUN:   -r=%t/thin.bc,odr,plx \
; RUN:   -r=%t/full.bc,full_addr,plx -r=%t/full.bc,full_alias,plx \
; RUN:   -r=%t/full.bc,choice,plx -r=%t/full.bc,odr,l
; RUN: llvm-dis %t/thin-out.3.5.precodegen.bc -o - | FileCheck %s
; RUN: llvm-nm %t/thin-out.3 | FileCheck %s --check-prefix=NM
; RUN: not test -e %t/thin-out.4
;
; Each original module has a different internal global with the same name.
; Exported accessors make their identity observable. They must remain distinct
; after the fresh merge, and the alias must still refer to the full accessor.
; The strong full-LTO definition prevails over the weak ThinLTO definition.
; The ODR COMDAT is emitted exactly once (ThinLTO copy prevails).
; Both source filenames are intentionally identical: the initial GUIDs of the
; two local slots collide. The fresh merged ThinLTO unit must distinguish them.
;
; CHECK-DAG: @[[FULL_SLOT:[^ ]+]] = internal global i32 2
; CHECK-DAG: @[[THIN_SLOT:[^ ]+]] = internal global i32 1
; CHECK: @full_alias = {{.*}}alias ptr (), ptr @full_addr
; CHECK-LABEL: define {{.*}}ptr @full_addr()
; CHECK: ret ptr @[[FULL_SLOT]]
; CHECK-LABEL: define {{.*}}i32 @choice()
; CHECK: ret i32 22
; CHECK-LABEL: define {{.*}}ptr @thin_addr()
; CHECK: ret ptr @[[THIN_SLOT]]
; CHECK-LABEL: define {{.*}}i32 @odr()
; CHECK: ret i32 7
; CHECK-NOT: define {{.*}}@odr(
; NM: T choice
; NM: T full_addr
; NM: T full_alias
; NM: W odr
; NM: T thin_addr
;
;--- thin.ll
source_filename = "same.c"
target triple = "x86_64-unknown-linux-gnu"
@slot = internal global i32 1
$odr = comdat any

define ptr @thin_addr() { ret ptr @slot }
define weak i32 @choice() { ret i32 11 }
define linkonce_odr i32 @odr() noinline comdat { ret i32 7 }

;--- full.ll
source_filename = "same.c"
target triple = "x86_64-unknown-linux-gnu"
@slot = internal global i32 2
@full_alias = alias ptr (), ptr @full_addr
$odr = comdat any

define ptr @full_addr() { ret ptr @slot }
define i32 @choice() { ret i32 22 }
define linkonce_odr i32 @odr() noinline comdat { ret i32 7 }
