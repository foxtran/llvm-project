; REQUIRES: x86
; RUN: opt -thinlto-bc %s -o %t.o
;
; These checks only exercise option parsing, not the two-stage backend.
; RUN: ld.lld %t.o -o %t
; RUN: ld.lld --two-stage-lto=thin %t.o -o %t.thin
; RUN: ld.lld --two-stage-lto=full %t.o -o %t.full
;
; Bare spelling selects full and must not consume the next input.
; RUN: ld.lld --two-stage-lto %t.o -o %t.bare
; RUN: cmp %t.full %t.bare
;
; Reject empty or invalid explicit values.
; RUN: not ld.lld --two-stage-lto= %t.o -o %t 2>&1 | FileCheck %s --check-prefix=EMPTY
; RUN: not ld.lld --two-stage-lto=default %t.o -o %t 2>&1 | FileCheck %s --check-prefix=INVALID -DVALUE=default
; RUN: not ld.lld --two-stage-lto=foo %t.o -o %t 2>&1 | FileCheck %s --check-prefix=INVALID -DVALUE=foo
; RUN: not ld.lld --two-stage-lto=two-stage-thin %t.o -o %t 2>&1 | FileCheck %s --check-prefix=INVALID -DVALUE=two-stage-thin
; RUN: not ld.lld --two-stage-lto=two-stage-full %t.o -o %t 2>&1 | FileCheck %s --check-prefix=INVALID -DVALUE=two-stage-full
;
; EMPTY: error: invalid two-stage LTO mode:{{ *}}{{$}}
; INVALID: error: invalid two-stage LTO mode: [[VALUE]]{{$}}

target triple = "x86_64-unknown-linux-gnu"

define void @_start() {
  ret void
}
