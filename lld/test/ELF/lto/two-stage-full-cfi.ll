; REQUIRES: x86
; RUN: split-file %s %t
; RUN: opt -module-summary %t/full.ll -o %t/full.o
; RUN: opt -thinlto-bc -thinlto-split-lto-unit %t/thin.ll -o %t/thin.o
; RUN: ld.lld --unified-lto=3 --save-temps --export-dynamic -e main \
; RUN:   %t/full.o %t/thin.o -o %t/out
; RUN: llvm-dis %t/out.0.4.opt.bc -o - | FileCheck %s --check-prefix=LOWERED
; RUN: llvm-dis %t/out.2.5.precodegen.bc -o - | FileCheck %s --check-prefix=FINAL
; RUN: llvm-nm %t/out | FileCheck %s --check-prefix=NM
;
; RUN: ld.lld --unified-lto=2 --save-temps --export-dynamic -e main \
; RUN:   %t/full.o %t/thin.o -o %t/thin-out
; RUN: llvm-dis %t/thin-out.0.4.opt.bc -o - | FileCheck %s --check-prefix=LOWERED
; RUN: llvm-dis %t/thin-out.3.5.precodegen.bc -o - | FileCheck %s --check-prefix=FINAL
; RUN: llvm-nm %t/thin-out | FileCheck %s --check-prefix=NM2
;
; A real split ThinLTO container, not merely a splitting flag. Its regular
; companion coordinates CFI lowering with the ThinLTO function body. The
; final IR link must preserve the check, jump table, and referenced definition.
; LOWERED: define {{.*}}i32 @checked(
; LOWERED: call i32 @typed.cfi
; FINAL: define {{.*}}i32 @checked(
; FINAL: ret i32 42
; FINAL: !llvm.module.flags
; NM: T main
; NM: T typed
; NM2: T main
; NM2: t typed.cfi
;
;--- full.ll
target triple = "x86_64-unknown-linux-gnu"
define i32 @checked(ptr %f) noinline {
  %ok = call i1 @llvm.type.test(ptr %f, metadata !"id")
  br i1 %ok, label %cont, label %trap
cont:
  %v = call i32 %f(i32 41)
  ret i32 %v
trap:
  call void @llvm.trap()
  unreachable
}
define i32 @main() {
  %v = call i32 @checked(ptr @typed)
  ret i32 %v
}
declare i32 @typed(i32)
declare i1 @llvm.type.test(ptr, metadata)
declare void @llvm.trap()
!llvm.module.flags = !{!0, !1}
!0 = !{i32 1, !"ThinLTO", i32 0}
!1 = !{i32 1, !"EnableSplitLTOUnit", i32 1}

;--- thin.ll
target triple = "x86_64-unknown-linux-gnu"
define i32 @typed(i32 %x) !type !0 {
  %v = add i32 %x, 1
  ret i32 %v
}
!0 = !{i64 0, !"id"}
