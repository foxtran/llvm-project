//===- TwoStageLTO.cpp - Two-stage LTO implementation --------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "llvm/LTO/TwoStageLTO.h"
#include "llvm/LTO/LTOBackend.h"
#include "llvm/ADT/ScopeExit.h"
#include "llvm/Analysis/ModuleSummaryAnalysis.h"
#include "llvm/Analysis/ProfileSummaryInfo.h"
#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/Linker/Linker.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Transforms/Utils/AssignGUID.h"

#include <mutex>

namespace llvm {
extern cl::opt<bool> CodeGenDataThinLTOTwoRounds;
} // namespace llvm

using namespace llvm;
using namespace lto;

#define DEBUG_TYPE "lto"

Error TwoStageLTO::prepare() {
  IsThinLTO = Conf.TwoStageLTO == Config::TwoStageLTOKind::Thin;
  // This prototype requires every backend to run locally and invoke our IR
  // hooks. Native cache hits, index-only and remote backends cannot do that.
  if (!ThinLTO.Backend.supportsModuleHooks() || Conf.CodeGenOnly ||
      !Conf.ThinLTOModulesToCompile.empty() || CodeGenDataThinLTOTwoRounds)
    return createStringError(
        inconvertibleErrorCode(),
        IsThinLTO
            ? "two-stage ThinLTO requires an in-process backend and complete "
              "first-stage optimization"
            : "two-stage full LTO requires an in-process backend and complete "
              "first-stage optimization");

  ThinTaskOffset = RegularLTO.ParallelCodeGenParallelismLevel;
  FinalTaskOffset = ThinTaskOffset + ThinLTO.ModuleMap.size();
  ExpectRegular =
      !RegularLTO.EmptyCombinedModule || Conf.AlwaysEmitRegularLTOObj;
  Modules.resize(FinalTaskOffset);
  if (Conf.TwoStageLTO == Config::TwoStageLTOKind::Thin) {
    // Remember external visibility and prevailing decisions before runThinLTO
    // releases the resolution state. There is no second-stage module ownership
    // to reconstruct: all surviving definitions will be in the merged module.
    for (const auto &R : GlobalResolutions) {
      SavedResolutions.try_emplace(
          R.first,
          SavedResolution{R.second.Prevailing, R.second.VisibleOutsideSummary,
                          R.second.ExportDynamic});
    }
  }

  OldPreOptHook = std::move(Conf.PreOptModuleHook);
  OldPostPromoteHook = std::move(Conf.PostPromoteModuleHook);
  OldPostInternalizeHook = std::move(Conf.PostInternalizeModuleHook);
  OldPostImportHook = std::move(Conf.PostImportModuleHook);
  OldPostOptHook = std::move(Conf.PostOptModuleHook);
  OldPreCodeGenHook = std::move(Conf.PreCodeGenModuleHook);
  OldCombinedIndexHook = std::move(Conf.CombinedIndexHook);

  Conf.PreOptModuleHook = [this](unsigned Task, const Module &M) {
    // CrossDSOCFI replaces __cfi_check's body each time it runs. Repeating it
    // after the original type tests have been lowered can change the checks.
    // Ordinary (non-cross-DSO) CFI does not have this replay problem.
    if (M.getModuleFlag("Cross-DSO CFI")) {
      std::lock_guard<std::mutex> Lock(ModulesMutex);
      CaptureError = IsThinLTO
                         ? "two-stage ThinLTO cannot yet replay cross-DSO CFI"
                         : "two-stage full LTO cannot yet replay cross-DSO CFI";
      return false;
    }
    return !OldPreOptHook || OldPreOptHook(Task, M);
  };
  Conf.PostOptModuleHook = [this](unsigned Task, const Module &M) {
    if (OldPostOptHook && !OldPostOptHook(Task, M))
      return false;
    std::string Buffer;
    raw_string_ostream OS(Buffer);
    WriteBitcodeToFile(M, OS);
    std::lock_guard<std::mutex> Lock(ModulesMutex);
    if (Task >= Modules.size() || Modules[Task])
      CaptureError = "unexpected or duplicate first-stage LTO task";
    else
      Modules[Task] = std::move(Buffer);
    // The hook's documented false result stops BOTH backends before codegen.
    return false;
  };
  HooksPrepared = true;
  return Error::success();
}

Error TwoStageLTO::runFirstStage() {
  auto NoNativeOutput =
      [](unsigned,
         const Twine &) -> Expected<std::unique_ptr<CachedFileStream>> {
    return createStringError(inconvertibleErrorCode(),
                             "unexpected first-stage native output");
  };

  if (Error Err = Owner.runRegularLTO(NoNativeOutput))
    return Err;
  if (!CaptureError.empty())
    return createStringError(inconvertibleErrorCode(), CaptureError);
  // Native caching was rejected by run(): we need every optimized IR module.
  if (Error Err = Owner.runThinLTO(NoNativeOutput, {}, GUIDPreservedSymbols))
    return Err;
  if (!CaptureError.empty())
    return createStringError(inconvertibleErrorCode(), CaptureError);
  if ((ExpectRegular && !Modules[0]) ||
      any_of(drop_begin(Modules, ThinTaskOffset),
             [](const auto &M) { return !M.has_value(); }))
    return createStringError(inconvertibleErrorCode(),
                             "incomplete first-stage IR (a hook stopped LTO)");
  return Error::success();
}

Expected<std::unique_ptr<Module>> TwoStageLTO::merge(LTOLLVMContext &Ctx) {
  // Parse into a new context and let the ordinary IR linker handle locals,
  // COMDATs and surviving available_externally definitions.
  auto Merged = std::make_unique<Module>("ld-temp.o", Ctx);
  Linker IRLinker(*Merged);
  for (auto &Buffer : Modules) {
    if (!Buffer)
      continue;
    auto MOrErr = parseBitcodeFile(MemoryBufferRef(*Buffer, "stage1"), Ctx);
    if (!MOrErr)
      return MOrErr.takeError();
    Module &M = **MOrErr;
    if ((!Merged->getTargetTriple().empty() && !M.getTargetTriple().empty() &&
         !Merged->getTargetTriple().isCompatibleWith(M.getTargetTriple())) ||
        (!Merged->getDataLayout().isDefault() &&
         !M.getDataLayout().isDefault() &&
         Merged->getDataLayout() != M.getDataLayout()))
      return createStringError(inconvertibleErrorCode(),
                               "incompatible first-stage targets or layouts");
    // These dispatch flags describe the pre-link inputs, not the already
    // optimized IR. Stage one has consumed the splitting policy. Both final
    // pipelines start from the same merged IR, without a unified pre-link.
    M.setModuleFlag(Module::Error, "ThinLTO", uint32_t(0));
    M.setModuleFlag(Module::Error, "UnifiedLTO", uint32_t(0));
    M.setModuleFlag(Module::Error, "EnableSplitLTOUnit", uint32_t(0));
    // All optimized IR will be linked together. Use the actual definitions
    // rather than synthesizing duplicates from split-unit cfi.functions.
    if (NamedMDNode *CfiFunctionsMD = M.getNamedMetadata("cfi.functions"))
      M.eraseNamedMetadata(CfiFunctionsMD);
    if (IRLinker.linkInModule(std::move(*MOrErr)))
      return createStringError(inconvertibleErrorCode(),
                               "failed to merge first-stage optimized IR");
  }
  return Merged;
}

Error TwoStageLTO::runSecondStage(Module &Merged) {
  auto OffsetHook = [&](Config::ModuleHookFn Hook,
                        bool SkipRegularTask = false) {
    return [Hook, FinalTaskOffset = FinalTaskOffset,
            SkipRegularTask](unsigned Task, const Module &M) {
      // The second link's regular-LTO placeholder has no inputs or output.
      if (SkipRegularTask && Task == 0)
        return true;
      return !Hook || Hook(FinalTaskOffset + Task, M);
    };
  };

  if (IsThinLTO) {
    Merged.setModuleIdentifier("ld-temp.stage2.merged");
    Merged.setModuleFlag(Module::Error, "ThinLTO", uint32_t(1));

    // This is a new ThinLTO unit. First-stage GUIDs describe the old names,
    // linkages and source modules, and may collide for distinct locals after
    // linking. Reassign them using the now-unique merged names; also assign
    // GUIDs to new definitions introduced by first-stage optimization.
    for (GlobalObject &GO : Merged.global_objects())
      GO.eraseMetadata(LLVMContext::MD_guid);
    AssignGUIDPass::runOnModule(Merged);
    ProfileSummaryInfo PSI(Merged);
    ModuleSummaryIndex Index = buildModuleSummaryIndex(Merged, nullptr, &PSI);
    std::string BC;
    raw_string_ostream OS(BC);
    WriteBitcodeToFile(Merged, OS, /*ShouldPreserveUseListOrder=*/false, &Index,
                       /*GenerateHash=*/true);
    // InputFile holds non-owning references into this buffer. Keep it alive
    // until the second link and its backend have finished.
    auto Buffer =
        MemoryBuffer::getMemBufferCopy(BC, Merged.getModuleIdentifier());
    auto InputOrErr = InputFile::create(Buffer->getMemBufferRef());
    if (!InputOrErr)
      return InputOrErr.takeError();

    std::vector<SymbolResolution> Resolutions;
    for (const auto &Sym : (*InputOrErr)->symbols()) {
      SymbolResolution R;
      auto Old = SavedResolutions.find(Sym.getName());
      // Available-externally bodies are undefined in the symbol table and
      // must not become prevailing definitions in this new link.
      R.Prevailing = !Sym.isUndefined() &&
                     (Old == SavedResolutions.end() || Old->second.Prevailing);
      // Preserve new externally linked symbols conservatively, including
      // generated CFI thunks and symbols referenced by opaque assembly.
      R.VisibleToRegularObj =
          Old == SavedResolutions.end() || Old->second.VisibleToRegularObj;
      R.ExportDynamic =
          Old != SavedResolutions.end() && Old->second.ExportDynamic;
      if (const GlobalValue *GV = Merged.getNamedValue(Sym.getIRName()))
        R.FinalDefinitionInLinkageUnit = R.Prevailing && GV->isDSOLocal();
      Resolutions.push_back(R);
    }

    // Run the FULL ThinLTO driver, including the thin link, promotion,
    // internalization and import phase, on one synthetic module. Do not use
    // thinlto-assume-merged or invoke just the optimization pipeline.
    Config SecondConf = std::move(Conf);
    // The nested link is the final stage, not another two-stage pipeline.
    SecondConf.TwoStageLTO = Config::TwoStageLTOKind::None;
    SecondConf.ResolutionFile.reset();
    SecondConf.StatsFile.clear();
    SecondConf.SampleProfile.clear();
    SecondConf.CSIRProfile.clear();
    SecondConf.RunCSIRInstr = false;
    SecondConf.AlwaysEmitRegularLTOObj = false;
    SecondConf.KeepSymbolNameCopies = true;
    if (!SecondConf.RemarksFilename.empty())
      SecondConf.RemarksFilename += ".stage2";
    SecondConf.PreOptModuleHook = OffsetHook(OldPreOptHook, true);
    SecondConf.PostPromoteModuleHook = OffsetHook(OldPostPromoteHook, true);
    SecondConf.PostInternalizeModuleHook =
        OffsetHook(OldPostInternalizeHook, true);
    SecondConf.PostImportModuleHook = OffsetHook(OldPostImportHook, true);
    SecondConf.PostOptModuleHook = OffsetHook(OldPostOptHook, true);
    SecondConf.PreCodeGenModuleHook = OffsetHook(OldPreCodeGenHook, true);
    SecondConf.CombinedIndexHook = SecondConf.SecondStageCombinedIndexHook;
    LTO SecondLTO(std::move(SecondConf),
                  createInProcessThinBackend(ThinLTO.Backend.getParallelism()),
                  /*ParallelCodeGenParallelismLevel=*/1,
                  LTO::LTOK_Default);
    SecondLTO.setBitcodeLibFuncs(BitcodeLibFuncs);
    llvm::scope_exit RestoreConfig([&] {
      Conf = std::move(SecondLTO.Conf);
      Conf.TwoStageLTO = Config::TwoStageLTOKind::Thin;
    });
    if (Error Err = SecondLTO.add(std::move(*InputOrErr), Resolutions))
      return Err;
    auto SecondAddStream = [&](unsigned Task, const Twine &Name) {
      return AddStream(FinalTaskOffset + Task, Name);
    };
    SecondLTO.getMaxTasks();
    return SecondLTO.run(SecondAddStream);
  } else if (Conf.TwoStageLTO == Config::TwoStageLTOKind::Full) {
    // Full-LTO final stage. Keep first-stage artifacts intact and assign
    // distinct task IDs to stage 2.
    Conf.PreOptModuleHook = OffsetHook(OldPreOptHook);
    Conf.PostOptModuleHook = OffsetHook(OldPostOptHook);
    Conf.PostInternalizeModuleHook = OffsetHook(OldPostInternalizeHook);
    Conf.PreCodeGenModuleHook = OffsetHook(OldPreCodeGenHook);
    // The first-stage pipelines already consumed profiles and inserted any
    // requested instrumentation. Use the resulting !prof/!memprof IR, not the
    // original profiles (whose CFG hashes/contexts no longer match), in
    // stage 2.
    auto SampleProfile = std::move(Conf.SampleProfile);
    auto CSIRProfile = std::move(Conf.CSIRProfile);
    bool RunCSIRInstr = Conf.RunCSIRInstr;
    Conf.SampleProfile.clear();
    Conf.CSIRProfile.clear();
    Conf.RunCSIRInstr = false;
    llvm::scope_exit RestoreProfiles([&] {
      Conf.SampleProfile = std::move(SampleProfile);
      Conf.CSIRProfile = std::move(CSIRProfile);
      Conf.RunCSIRInstr = RunCSIRInstr;
    });

    // A fresh export index, as in full LTO without ThinLTO consumers. A
    // per-module analysis index would retain pointers to globals that the full
    // optimizer may delete; neither it nor the old import index belongs here.
    ModuleSummaryIndex FinalIndex(/*HaveGVs=*/false);
    if (ThinLTO.CombinedIndex.withSupportsHotColdNew())
      FinalIndex.setWithSupportsHotColdNew();
    auto FinalStream = [&](unsigned Task, const Twine &Name) {
      return AddStream(FinalTaskOffset + Task, Name);
    };
    // This is a FULL optimization pass, not codegen-only: it sees both
    // families' optimized bodies for the first time and can inline across the
    // boundary.
    auto Remarks = lto::setupLLVMOptimizationRemarks(
        Merged.getContext(),
        Conf.RemarksFilename.empty() ? "" : Conf.RemarksFilename + ".stage2",
        Conf.RemarksPasses, Conf.RemarksFormat, Conf.RemarksWithHotness,
        Conf.RemarksHotnessThreshold);
    if (!Remarks)
      return Remarks.takeError();
    // The merged IR is already resolved and internalized. Run the final hooks
    // without replaying first-stage symbol resolution or visibility decisions.
    if ((!Conf.PreOptModuleHook || Conf.PreOptModuleHook(0, Merged)) &&
        (!Conf.PostInternalizeModuleHook ||
         Conf.PostInternalizeModuleHook(0, Merged))) {
      if (Error Err = backend(Conf, FinalStream,
                              /*ParallelCodeGenParallelismLevel=*/1, Merged,
                              FinalIndex, BitcodeLibFuncs))
        return Err;
    }
    return finalizeOptimizationRemarks(std::move(*Remarks));
  }

  return createStringError(inconvertibleErrorCode(),
                           "invalid two-stage LTO mode");
}
