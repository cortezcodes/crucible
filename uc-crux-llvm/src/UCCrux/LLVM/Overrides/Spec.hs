{-
Module       : UCCrux.LLVM.Overrides.Spec
Description  : Overrides for skipping execution of functions with provided specs
Copyright    : (c) Galois, Inc 2022
License      : BSD3
Maintainer   : Langston Barrett <langston@galois.com>
Stability    : provisional

These overrides are useful for describing the behavior of external/library
functions, or for soundly skipping complex functions even when they happen to be
defined.

TODO(lb, #932): Track which specs actually execute and whether they are over- or
under-approximate.
-}

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ImplicitParams #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module UCCrux.LLVM.Overrides.Spec
  ( specOverrides,
    createSpecOverride,
  )
where

{- ORMOLU_DISABLE -}
import           Control.Lens ((^.))
import           Data.IORef (IORef)
import           Data.Map (Map)
import qualified Data.Map as Map
import           Data.Type.Equality ((:~:)(Refl))

-- parameterized-utils
import qualified Data.Parameterized.Context as Ctx

-- what4

-- crucible
import           Lang.Crucible.Backend (IsSymBackend)
import qualified Lang.Crucible.Simulator as Crucible

-- crucible-llvm
import           Lang.Crucible.LLVM.Extension (LLVM)
import           Lang.Crucible.LLVM.MemModel (HasLLVMAnn, Mem, MemOptions)
import           Lang.Crucible.LLVM.Translation (transContext, llvmTypeCtx)
import           Lang.Crucible.LLVM.TypeContext (TypeContext)
import           Lang.Crucible.LLVM.Intrinsics (LLVMOverride(..), basic_llvm_override)

import           Crux.Types (OverM)

-- crux-llvm
import           Crux.LLVM.Overrides (ArchOk)

-- uc-crux-llvm
-- uc-crux-llvm
import           UCCrux.LLVM.Context.Module (ModuleContext, moduleDecls, moduleTranslation)
import           UCCrux.LLVM.FullType.CrucibleType (SomeAssign'(..),  assignmentToCrucibleType, toCrucibleReturnType)
import           UCCrux.LLVM.ExprTracker (ExprTracker)
import           UCCrux.LLVM.FullType.FuncSig (FuncSigRepr(FuncSigRepr))
import qualified UCCrux.LLVM.FullType.FuncSig as FS
import           UCCrux.LLVM.FullType.Type (MapToCrucibleType)
import           UCCrux.LLVM.Module (FuncSymbol, funcSymbol)
import           UCCrux.LLVM.Overrides.Polymorphic (PolymorphicLLVMOverride, makePolymorphicLLVMOverride)
import qualified UCCrux.LLVM.Specs.Apply as Spec
import           UCCrux.LLVM.Specs.Type (SomeSpecs)
import qualified UCCrux.LLVM.Specs.Type as Spec
{- ORMOLU_ENABLE -}

-- | Create specification-based overrides for each function in the 'Map'.
specOverrides ::
  IsSymBackend sym bak =>
  HasLLVMAnn sym =>
  ArchOk arch =>
  (?lc :: TypeContext) =>
  (?memOpts :: MemOptions) =>
  ModuleContext m arch ->
  bak ->
  -- | Origins of created values
  IORef (ExprTracker m sym argTypes) ->
  -- | Specs of each override, see 'Specs'.
  Map (FuncSymbol m) (SomeSpecs m) ->
  OverM personality sym LLVM [PolymorphicLLVMOverride arch (personality sym) sym]
specOverrides modCtx bak tracker specs =
  do let llvmCtx = modCtx ^. moduleTranslation . transContext
     let ?lc = llvmCtx ^. llvmTypeCtx
     let create funcSymb (Spec.SomeSpecs fsRep@FuncSigRepr{} specs') =
           createSpecOverride modCtx bak tracker funcSymb fsRep specs'
     pure $ map (uncurry create) (Map.toList specs)

-- | Boilerplate to create an LLVM override
mkOverride ::
  IsSymBackend sym bak =>
  HasLLVMAnn sym =>
  ArchOk arch =>
  (fs ~ 'FS.FuncSig va mft args) =>
  ModuleContext m arch ->
  proxy bak ->
  -- | Function to be overridden
  FuncSymbol m ->
  -- | Type of function to be overridden
  FS.FuncSigRepr m fs ->
  -- | Implementation
  (forall rtp a r.
   Crucible.GlobalVar Mem ->
   Ctx.Assignment (Crucible.RegEntry sym) (MapToCrucibleType arch args) ->
   Crucible.OverrideSim (personality sym) sym LLVM rtp a r
     (Crucible.RegValue sym (FS.ReturnTypeToCrucibleType arch mft))) ->
  PolymorphicLLVMOverride arch (personality sym) sym
mkOverride modCtx _proxy funcSymb (FuncSigRepr _ argFTys retTy) impl =
  case assignmentToCrucibleType modCtx argFTys of
    SomeAssign' argTys Refl _ ->
      makePolymorphicLLVMOverride $
        basic_llvm_override $
          LLVMOverride
            { llvmOverride_declare = decl,
              llvmOverride_args = argTys,
              llvmOverride_ret = toCrucibleReturnType modCtx retTy,
              llvmOverride_def =
                \mvar _sym args -> impl mvar args
            }
  where decl = modCtx ^. moduleDecls . funcSymbol funcSymb

-- | Create an override that takes the place of a given defined or even
-- declared/external function, and instead of executing that function, applies
-- its specification as described in the documentation for 'Spec.applySpecs'.
createSpecOverride ::
  forall m arch sym bak fs va mft args argTypes personality.
  IsSymBackend sym bak =>
  HasLLVMAnn sym =>
  ArchOk arch =>
  (?lc :: TypeContext) =>
  (?memOpts :: MemOptions) =>
  (fs ~ 'FS.FuncSig va mft args) =>
  ModuleContext m arch ->
  bak ->
  -- | Origins of created values
  IORef (ExprTracker m sym argTypes) ->
  -- | Function to be overridden
  FuncSymbol m ->
  -- | Type of function to be overridden
  FS.FuncSigRepr m fs ->
  -- | Constraints on the return value, clobbered pointer values such as
  -- arguments or global variables
  Spec.Specs m fs ->
  PolymorphicLLVMOverride arch (personality sym) sym
createSpecOverride modCtx bak tracker funcSymb fsRep specs =
  mkOverride modCtx (Just bak) funcSymb fsRep $
    \mvar args ->
      Spec.applySpecs bak modCtx tracker funcSymb specs fsRep mvar args