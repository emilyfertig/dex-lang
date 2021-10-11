-- Copyright 2021 Google LLC
--
-- Use of this source code is governed by a BSD-style
-- license that can be found in the LICENSE file or at
-- https://developers.google.com/open-source/licenses/bsd

module SaferNames.CheapReduction
  (cheapReduceBlockToAtom, cheapReduce, CheaplyReducible (..)) where

import LabeledItems
import SaferNames.Name
import SaferNames.Syntax

cheapReduceBlockToAtom :: BindingsReader m => Block n -> m n (Maybe (Atom n))
cheapReduceBlockToAtom block = fromAtomicBlock <$> cheapReduce block

fromAtomicBlock :: Block n -> Maybe (Atom n)
fromAtomicBlock (Block _ Empty expr) = fromAtomicExpr expr
fromAtomicBlock _ = Nothing

fromAtomicExpr :: Expr n -> Maybe (Atom n)
fromAtomicExpr (Atom atom) = Just atom
fromAtomicExpr _ = Nothing

cheapReduce :: (CheaplyReducible e, BindingsReader m) => e n -> m n (e n)
cheapReduce x = runEnvReaderT idEnv $ cheapReduceE x

class CheaplyReducible (e::E) where
  cheapReduceE :: (EnvReader Name m, BindingsReader2 m) => e i -> m i o (e o)

instance CheaplyReducible Atom where
  cheapReduceE = \case
    Var v -> do
      v' <- substM v
      lookupBindings v' >>= \case
        -- TODO: worry about effects!
        AtomNameBinding (LetBound (DeclBinding PlainLet _ expr)) -> do
          expr' <- dropSubst $ cheapReduceE expr
          case fromAtomicExpr expr' of
              Nothing -> return $ Var v'
              Just x' -> return x'
        _ -> return $ Var v'
    TC con -> TC <$> mapM cheapReduceE con
    -- TODO: pi type case?
    TypeCon (name, def) params -> do
      namedDef' <- (,) <$> substM name <*> substM def
      TypeCon namedDef' <$> mapM cheapReduceE params
    RecordTy (Ext tys ext) ->
      RecordTy <$> (Ext <$> mapM cheapReduceE tys <*> mapM substM ext)
    VariantTy (Ext tys ext) ->
      VariantTy <$> (Ext <$> mapM cheapReduceE tys <*> mapM substM ext)
    x -> substM x

instance CheaplyReducible Expr where
  cheapReduceE (Atom atom) = Atom <$> cheapReduceE atom

instance CheaplyReducible Block where
  cheapReduceE (Block ty Empty result) = do
    ty' <- substM ty
    result' <- cheapReduceE result
    return $ Block ty' Empty result'
