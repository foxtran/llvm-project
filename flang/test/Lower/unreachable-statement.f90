! RUN: %flang_fc1 -emit-hlfir -fcheck-unreachable    %s -o - | FileCheck %s --check-prefix=CHECK-CHECK
! RUN: %flang_fc1 -emit-hlfir -fno-check-unreachable %s -o - | FileCheck %s --check-prefix=CHECK-NOCHECK

! CHECK-LABEL: unreachable_test
subroutine unreachable_test
  ! CHECK-CHECK-DAG: %[[false:.*]] = arith.constant false
  ! CHECK-CHECK-DAG: %[[c1:.*]] = arith.constant 1 : i32
  ! CHECK-CHECK-DAG: %[[c2:.*]] = arith.constant 2 : i32
  ! CHECK-CHECK: fir.call @_FortranAStopStatement(%[[c1]], %[[c2]], %[[false]]) fastmath<contract> : (i32, i32, i1) -> ()
  ! CHECK-CHECK-NEXT: fir.unreachable
  ! CHECK-NOCHECK-NOT: fir.call @_FortranAStopStatement({{.*}}, {{.*}}, {{.*}}) fastmath<contract> : (i32, i32, i1) -> ()
  ! CHECK-NOCHECK: fir.unreachable
  unreachable
end subroutine unreachable_test

! CHECK-LABEL: unreachable_unchecked_test
subroutine unreachable_unchecked_test
  ! CHECK-CHECK-DAG: %[[false:.*]] = arith.constant false
  ! CHECK-CHECK-DAG: %[[c1:.*]] = arith.constant 1 : i32
  ! CHECK-CHECK-DAG: %[[c2:.*]] = arith.constant 2 : i32
  ! CHECK-CHECK: fir.call @_FortranAStopStatement(%[[c1]], %[[c2]], %[[false]]) fastmath<contract> : (i32, i32, i1) -> ()
  ! CHECK-CHECK-NEXT: fir.unreachable
  ! CHECK-NOCHECK-NOT: fir.call @_FortranAStopStatement({{.*}}, {{.*}}, {{.*}}) fastmath<contract> : (i32, i32, i1) -> ()
  ! CHECK-NOCHECK: fir.unreachable
  unreachable unchecked
end subroutine unreachable_unchecked_test
