{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ImplicitParams #-}
{-# LANGUAGE RankNTypes #-}

module Mir.Pass (
    Pass,
    rewriteCollection
) where


import Control.Lens hiding (op,(|>))
import qualified Data.Map.Strict as Map

import GHC.Stack

import Mir.Mir
import Mir.DefId
import Mir.PP(fmt)

import Mir.Pass.AllocateEnum ( passAllocateEnum )

import Debug.Trace

type Pass = (?debug::Int, ?mirLib::Collection, HasCallStack) => Collection -> Collection

--------------------------------------------------------------------------------------
infixl 0 |>
(|>) :: a -> (a -> b) -> b
x |> f = f x
--------------------------------------------------------------------------------------

rewriteCollection :: Pass
rewriteCollection col =
  col
    |> passAllocateEnum

--------------------------------------------------------------------------------------

passId :: Pass
passId = id

--------------------------------------------------------------------------------------

passTrace :: String -> Pass
passTrace str col =
  if (?debug > 5) then
      ((trace $ "*********MIR collection " ++ str ++ "*******\n"
                ++ fmt col ++ "\n****************************")
       col)
  else col

--------------------------------------------------------------------------------------

toCollectionPass :: ([Fn] -> [Fn]) -> Pass
toCollectionPass f col = col { _functions = (fromList (f (Map.elems (col^.functions)))) } where
    fromList :: [Fn] -> Map.Map DefId Fn
    fromList = foldr (\fn m -> Map.insert (fn^.fname) fn m) Map.empty

--------------------------------------------------------------------------------------


