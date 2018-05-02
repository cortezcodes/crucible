module Goal where

import Control.Lens((^.))
import Control.Monad(foldM)
import qualified Data.Foldable as Fold

import Lang.Crucible.Solver.Interface
        (IsExprBuilder, Pred, notPred, impliesPred)
import Lang.Crucible.Solver.BoolInterface
        ( Assertion, assertPred, assertMsg, assertLoc )
import Lang.Crucible.Solver.Adapter(SolverAdapter(..))
import Lang.Crucible.Solver.AssumptionStack(ProofGoal(..))
import Lang.Crucible.Solver.SatResult(SatResult(..))
import Lang.Crucible.Solver.SimpleBuilder (SimpleBuilder)
import Lang.Crucible.Solver.SimpleBackend.Z3(z3Adapter)
-- import Lang.Crucible.Solver.SimpleBackend.Yices(yicesAdapter)

import Lang.Crucible.Simulator.SimError(SimErrorReason(..))
import Lang.Crucible.Simulator.ExecutionTree
        (ctxSymInterface, cruciblePersonality)


import Error
import Types
import Model


prover :: SolverAdapter s
prover = z3Adapter
--prover = yicesAdapter

data Goal sym = Goal
  { gAssumes :: [Pred sym]
  , gShows   :: Assertion (Pred sym) SimErrorReason
  }

-- Check assertions before other things
goalPriority :: Goal sym -> Int
goalPriority g =
  case assertMsg (gShows g) of
    AssertFailureSimError {} -> 0
    _ -> 1

mkGoal :: ProofGoal (Pred sym) SimErrorReason -> Goal sym
mkGoal (ProofGoal as p) = Goal { gAssumes = (Fold.toList as), gShows = p }

obligGoal :: IsExprBuilder sym => sym -> Goal sym -> IO (Pred sym)
obligGoal sym g = foldM imp (gShows g ^. assertPred) (gAssumes g)
  where
  imp p a = impliesPred sym a p

proveGoal ::
  SimCtxt (SimpleBuilder s t) arch ->
  Goal (SimpleBuilder s t) ->
  IO (Maybe Error)
proveGoal ctxt g =
  do let sym = ctxt ^. ctxSymInterface
     g1 <- obligGoal sym g
     p <- notPred sym g1

     let say _n _x = return () -- putStrLn ("[" ++ show _n ++ "] " ++ _x)
     solver_adapter_check_sat prover sym say p $ \res ->
        case res of
          Unsat -> return Nothing
          Sat (evalFn,_mbRng) ->
            do let model = ctxt ^. cruciblePersonality
               str <- ppModel evalFn model
               return (Just (e (Just str)))
          _  -> return (Just (e Nothing))

  where
  a = gShows g
  e mb = FailedToProve (assertLoc a) (assertMsg a) mb


