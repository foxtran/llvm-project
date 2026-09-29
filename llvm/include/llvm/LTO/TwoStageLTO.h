//===- TwoStageLTO.h - Two-stage LTO implementation ----------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LTO_TWOSTAGELTO_H
#define LLVM_LTO_TWOSTAGELTO_H

#include "llvm/LTO/LTO.h"

namespace llvm {
namespace lto {

class TwoStageLTO {
public:
  TwoStageLTO(LTO &Owner, AddStreamFn AddStream,
              const DenseSet<GlobalValue::GUID> &GUIDPreservedSymbols)
      : Owner(Owner), AddStream(std::move(AddStream)),
        GUIDPreservedSymbols(GUIDPreservedSymbols), Conf(Owner.Conf),
        RegularLTO(Owner.RegularLTO), ThinLTO(Owner.ThinLTO),
        GlobalResolutions(*Owner.GlobalResolutions),
        BitcodeLibFuncs(Owner.BitcodeLibFuncs) {}
  ~TwoStageLTO() { restoreHooks(); }

  Error prepare();
  Error runFirstStage();
  Expected<std::unique_ptr<Module>> merge(LTOLLVMContext &Ctx);
  Error runSecondStage(Module &Merged);
  bool hasCapturedModules() const {
    return any_of(Modules, [](const auto &M) { return M.has_value(); });
  }

private:
  void restoreHooks() {
    if (!HooksPrepared)
      return;
    Conf.PreOptModuleHook = std::move(OldPreOptHook);
    Conf.PostPromoteModuleHook = std::move(OldPostPromoteHook);
    Conf.PostInternalizeModuleHook = std::move(OldPostInternalizeHook);
    Conf.PostImportModuleHook = std::move(OldPostImportHook);
    Conf.PostOptModuleHook = std::move(OldPostOptHook);
    Conf.PreCodeGenModuleHook = std::move(OldPreCodeGenHook);
    Conf.CombinedIndexHook = std::move(OldCombinedIndexHook);
    HooksPrepared = false;
  }

  LTO &Owner;
  AddStreamFn AddStream;
  const DenseSet<GlobalValue::GUID> &GUIDPreservedSymbols;
  Config &Conf;
  LTO::RegularLTOState &RegularLTO;
  LTO::ThinLTOState &ThinLTO;
  DenseMap<StringRef, LTO::GlobalResolution> &GlobalResolutions;
  SmallVector<StringRef> &BitcodeLibFuncs;

  struct SavedResolution {
    bool Prevailing;
    bool VisibleToRegularObj;
    bool ExportDynamic;
  };
  bool HooksPrepared = false;
  bool IsThinLTO = false;
  unsigned ThinTaskOffset = 0;
  unsigned FinalTaskOffset = 0;
  bool ExpectRegular = false;
  StringMap<SavedResolution> SavedResolutions;
  std::vector<std::optional<std::string>> Modules;
  std::mutex ModulesMutex;
  std::string CaptureError;

  Config::ModuleHookFn OldPreOptHook;
  Config::ModuleHookFn OldPostPromoteHook;
  Config::ModuleHookFn OldPostInternalizeHook;
  Config::ModuleHookFn OldPostImportHook;
  Config::ModuleHookFn OldPostOptHook;
  Config::ModuleHookFn OldPreCodeGenHook;
  Config::CombinedIndexHookFn OldCombinedIndexHook;
};

} // namespace lto
} // namespace llvm

#endif // LLVM_LTO_TWOSTAGELTO_H
