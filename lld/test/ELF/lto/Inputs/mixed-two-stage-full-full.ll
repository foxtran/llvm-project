target triple = "x86_64-unknown-linux-gnu"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"

define i32 @force_target(i32 %x) {
entry:
  %y = add i32 %x, 1
  ret i32 %y
}
