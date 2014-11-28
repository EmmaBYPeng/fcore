{-# OPTIONS -XRankNTypes -XFlexibleInstances -XFlexibleContexts -XTypeOperators -XMultiParamTypeClasses -XKindSignatures -XConstraintKinds -XScopedTypeVariables #-}

module ApplyTransCFJava where

import qualified Data.Set as Set
import qualified Language.Java.Syntax as J

import           BaseTransCFJava
import           ClosureF
import           Inheritance
import           JavaEDSL
import           MonadLib
import           StringPrefixes

data ApplyOptTranslate m = NT {toT :: Translate m}

instance (:<) (ApplyOptTranslate m) (Translate m) where
   up              = up . toT

instance (:<) (ApplyOptTranslate m) (ApplyOptTranslate m) where
   up              = id

isMutiBinder :: EScope Int (Var, Type Int) -> Bool
isMutiBinder (Type _ _) = True
isMutiBinder (Kind f)   = isMutiBinder (f 0)
isMutiBinder (Body _)   = False

-- main translation function
transApply :: (MonadState Int m,
               MonadState (Set.Set J.Name) m,
               MonadReader InitVars m,
               selfType :< ApplyOptTranslate m,
               selfType :< Translate m)
              => Mixin selfType (Translate m) (ApplyOptTranslate m)
transApply this super = NT {toT = super {
  translateScopeTyp = \currentId nextId initVars nextInClosure m closureClass ->
    case isMutiBinder nextInClosure of
         False -> do (initVars' :: InitVars) <- ask
                     translateScopeTyp super currentId nextId (initVars ++ initVars') nextInClosure (local (\(_ :: InitVars) -> []) m) closureClass
         True -> do (s,je,t1) <- local (initVars ++) m
                    let refactored = modifiedScopeTyp (unwrap je) s currentId nextId closureClass
                    return (refactored,t1),

  genApply = \f t x y z -> do applyGen <- genApply super f t x y z
                              return [bStmt $ J.IfThen (fieldAccess f "hasApply")
                                      (J.StmtBlock (block applyGen)) ],

  genClosureVar = \t j1 typ -> do
    (usedCl :: Set.Set J.Name) <- get
    maybeCloned <- case t of
                    Body _ ->
                      return (J.ExpName j1)
                    _ ->
                      if (Set.member j1 usedCl) then
                        return $ J.MethodInv (J.PrimaryMethodCall (J.ExpName j1) [] (J.Ident "clone") [])
                      else do
                        put (Set.insert j1 usedCl)
                        return (J.ExpName j1)
    f <- getNewVarName (up this)
    case maybeCloned of
     J.MethodInv _ -> return ([localVar typ (varDecl f maybeCloned)], (name [f]))
     _ -> return ([], j1),


  genClone = return True
}}

modifiedScopeTyp :: J.Exp -> [J.BlockStmt] -> Int -> Int -> String -> [J.BlockStmt]
modifiedScopeTyp oexpr ostmts currentId nextId closureClass = completeClosure
  where closureType' = classTy closureClass
        currentInitialDeclaration = memberDecl $ fieldDecl closureType' (varDecl (localvarstr ++ show currentId) J.This)
        setApplyFlag = assignField (fieldAccExp (left $ var (localvarstr ++ show currentId)) "hasApply") (J.Lit (J.Boolean False))
        completeClosure = [(localClassDecl ("Fun" ++ show nextId) closureClass
                            (closureBodyGen
                             [currentInitialDeclaration, J.InitDecl False (block $ (setApplyFlag : ostmts ++ [assign (name [closureOutput]) oexpr]))]
                             []
                             nextId
                             True
                             closureType'))
                          ,localVar closureType' (varDecl (localvarstr ++ show nextId) (funInstCreate nextId))]


-- Alternate version of transApply that works with Stack translation
transAS :: (MonadState Int m, MonadState (Set.Set J.Name) m, MonadReader InitVars m, selfType :< ApplyOptTranslate m, selfType :< Translate m) => Mixin selfType (Translate m) (ApplyOptTranslate m)
transAS this super = NT {toT = (up (transApply this super)) {

  genApply = \f t tempOut outType z ->
    do applyGen <- genApply super f t tempOut outType z
       let tempDecl = localVar outType
                      (varDecl tempOut (case outType of
                                         J.PrimType J.IntT -> J.Lit (J.Int 0)
                                         _ -> (J.Lit J.Null)))
       let elseDecl = assign (name [tempOut]) (cast outType (J.FieldAccess (fieldAccExp (cast z f) closureOutput)))

       if length applyGen == 2
         then return applyGen
         else return [tempDecl, bStmt $ J.IfThenElse (fieldAccess f "hasApply")
                                (J.StmtBlock (block applyGen))
                                (J.StmtBlock (block [elseDecl]))]
  }}
