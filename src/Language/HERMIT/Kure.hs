{-# LANGUAGE CPP, MultiParamTypeClasses, FlexibleInstances, FlexibleContexts, UndecidableInstances, TupleSections, LambdaCase, InstanceSigs, ScopedTypeVariables #-}

module Language.HERMIT.Kure
       (
       -- * KURE

       -- | All the required functionality of KURE is exported here, so other modules do not need to import KURE directly.
         module Language.KURE
       , module Language.KURE.BiTranslate
       , module Language.KURE.Lens
       -- * Sub-Modules
       , module Language.HERMIT.Kure.SumTypes
       -- * Synonyms
       , TranslateH
       , RewriteH
       , BiRewriteH
       , LensH
       , PathH

       -- * Congruence combinators
       -- ** Modguts
       , modGutsT, modGutsR
       -- ** Program
       , progNilT
       , progConsT, progConsAllR, progConsAnyR, progConsOneR
       -- ** Binding Groups
       , nonRecT, nonRecAllR, nonRecAnyR, nonRecOneR
       , recT, recAllR, recAnyR, recOneR
       -- ** Recursive Definitions
       , defT, defAllR, defAnyR, defOneR
       -- ** Case Alternatives
       , altT, altAllR, altAnyR, altOneR
       -- ** Expressions
       , varT, varR
       , litT, litR
       , appT, appAllR, appAnyR, appOneR
       , lamT, lamAllR, lamAnyR, lamOneR
       , letT, letAllR, letAnyR, letOneR
       , caseT, caseAllR, caseAnyR, caseOneR
       , castT, castAllR, castAnyR, castOneR
       , tickT, tickAllR, tickAnyR, tickOneR
       , typeT, typeR
       , coercionT, coercionR
       -- ** Composite Congruence Combinators
       , recDefT, recDefAllR, recDefAnyR, recDefOneR
       , letNonRecT, letNonRecAllR, letNonRecAnyR, letNonRecOneR
       , letRecT, letRecAllR, letRecAnyR, letRecOneR
       , letRecDefT, letRecDefAllR, letRecDefAnyR, letRecDefOneR
       , consNonRecT, consNonRecAllR, consNonRecAnyR, consNonRecOneR
       , consRecT, consRecAllR, consRecAnyR, consRecOneR
       , consRecDefT, consRecDefAllR, consRecDefAnyR, consRecDefOneR
       , caseAltT, caseAltAllR, caseAltAnyR, caseAltOneR
       -- ** Types
       , tyVarT, tyVarR
       , litTyT, litTyR
       , appTyT, appTyAllR, appTyAnyR, appTyOneR
       , funTyT, funTyAllR, funTyAnyR, funTyOneR
       , forAllTyT, forAllTyAllR, forAllTyAnyR, forAllTyOneR
       , tyConAppT, tyConAppAllR, tyConAppAnyR, tyConAppOneR
       -- ** Coercions
       , reflT, reflR
       , tyConAppCoT, tyConAppCoAllR, tyConAppCoAnyR, tyConAppCoOneR
       , appCoT, appCoAllR, appCoAnyR, appCoOneR
       , forAllCoT, forAllCoAllR, forAllCoAnyR, forAllCoOneR
       , coVarCoT, coVarCoR
       , axiomInstCoT, axiomInstCoAllR, axiomInstCoAnyR, axiomInstCoOneR
       , unsafeCoT, unsafeCoAllR, unsafeCoAnyR, unsafeCoOneR
       , symCoT, symCoR
       , transCoT, transCoAllR, transCoAnyR, transCoOneR
       , nthCoT, nthCoAllR, nthCoAnyR, nthCoOneR
       , instCoT, instCoAllR, instCoAnyR, instCoOneR
       -- * Promotion Combinators
       -- ** Rewrite Promotions
       , promoteModGutsR
       , promoteProgR
       , promoteBindR
       , promoteDefR
       , promoteExprR
       , promoteAltR
       -- ** BiRewrite Promotions
       , promoteExprBiR
       -- ** Translate Promotions
       , promoteModGutsT
       , promoteProgT
       , promoteBindT
       , promoteDefT
       , promoteExprT
       , promoteAltT

       -- * Conversion to deprecated Int representation
       , deprecatedIntToCrumbT
       , deprecatedIntToPathT
       )
where

import GhcPlugins hiding (empty)

import Language.KURE
import Language.KURE.BiTranslate
import Language.KURE.Lens

import Language.HERMIT.Context
import Language.HERMIT.Core
import Language.HERMIT.GHC
import Language.HERMIT.Monad
import Language.HERMIT.Kure.SumTypes

import Control.Monad

---------------------------------------------------------------------

type TranslateH a b = Translate HermitC HermitM a b
type RewriteH a     = Rewrite   HermitC HermitM a
type BiRewriteH a   = BiRewrite HermitC HermitM a
type LensH a b      = Lens      HermitC HermitM a b
type PathH          = Path Crumb

-- I find it annoying that Applicative is not a superclass of Monad.
(<$>) :: Monad m => (a -> b) -> m a -> m b
(<$>) = liftM
{-# INLINE (<$>) #-}

(<*>) :: Monad m => m (a -> b) -> m a -> m b
(<*>) = ap
{-# INLINE (<*>) #-}

---------------------------------------------------------------------

-- | Walking over modules, programs, binding groups, definitions, expressions and case alternatives.
instance (ExtendPath c Crumb, AddBindings c) => Walker c Core where

  allR :: forall m. MonadCatch m => Rewrite c m Core -> Rewrite c m Core
  allR r = prefixFailMsg "allR failed: " $
           rewrite $ \ c -> \case
             GutsCore guts  -> inject <$> apply allRmodguts c guts
             ProgCore p     -> inject <$> apply allRprog c p
             BindCore bn    -> inject <$> apply allRbind c bn
             DefCore def    -> inject <$> apply allRdef c def
             AltCore alt    -> inject <$> apply allRalt c alt
             ExprCore e     -> inject <$> apply allRexpr c e
    where
      allRmodguts :: MonadCatch m => Rewrite c m ModGuts
      allRmodguts = modGutsR (extractR r)
      {-# INLINE allRmodguts #-}

      allRprog :: MonadCatch m => Rewrite c m CoreProg
      allRprog = readerT $ \case
                              ProgCons{}  -> progConsAllR (extractR r) (extractR r)
                              _           -> idR
      {-# INLINE allRprog #-}

      allRbind :: MonadCatch m => Rewrite c m CoreBind
      allRbind = readerT $ \case
                              NonRec{}  -> nonRecAllR idR (extractR r) -- we don't descend into the Var
                              Rec _     -> recAllR (const $ extractR r)
      {-# INLINE allRbind #-}

      allRdef :: MonadCatch m => Rewrite c m CoreDef
      allRdef = defAllR idR (extractR r) -- we don't descend into the Id
      {-# INLINE allRdef #-}

      allRalt :: MonadCatch m => Rewrite c m CoreAlt
      allRalt = altAllR idR (const idR) (extractR r) -- we don't descend into the AltCon or Vars
      {-# INLINE allRalt #-}

      allRexpr :: MonadCatch m => Rewrite c m CoreExpr
      allRexpr = readerT $ \case
                              App{}   -> appAllR (extractR r) (extractR r)
                              Lam{}   -> lamAllR idR (extractR r) -- we don't descend into the Var
                              Let{}   -> letAllR (extractR r) (extractR r)
                              Case{}  -> caseAllR (extractR r) idR idR (const $ extractR r) -- we don't descend into the case binder or Type
                              Cast{}  -> castAllR (extractR r) idR -- we don't descend into the Coercion
                              Tick{}  -> tickAllR idR (extractR r) -- we don't descend into the Tickish
                              _       -> idR
      {-# INLINE allRexpr #-}

-- NOTE: I tried telling GHC to inline allR and compilation hit the (default) simplifier tick limit.
-- TODO: Investigate whether that was achieving useful optimisations.

---------------------------------------------------------------------

-- | Walking over types (only).
instance (ExtendPath c Crumb, AddBindings c) => Walker c Type where

  allR :: MonadCatch m => Rewrite c m Type -> Rewrite c m Type
  allR r = prefixFailMsg "allR failed: " $
           readerT $ \case
                        AppTy{}     -> appTyAllR r r
                        FunTy{}     -> funTyAllR r r
                        ForAllTy{}  -> forAllTyAllR idR r
                        TyConApp{}  -> tyConAppAllR idR (const r)
                        _           -> idR

---------------------------------------------------------------------

-- | Walking over coercions (only).
instance (ExtendPath c Crumb, AddBindings c) => Walker c Coercion where

  allR :: MonadCatch m => Rewrite c m Coercion -> Rewrite c m Coercion
  allR r = prefixFailMsg "allR failed: " $
           readerT $ \case
                        TyConAppCo{}  -> tyConAppCoAllR idR (const r)
                        AppCo{}       -> appCoAllR r r
                        ForAllCo{}    -> forAllCoAllR idR r
                        AxiomInstCo{} -> axiomInstCoAllR idR (const r)
                        SymCo{}       -> symCoR r
                        TransCo{}     -> transCoAllR r r
                        NthCo{}       -> nthCoAllR idR r
                        InstCo{}      -> instCoAllR r idR
                        _             -> idR

---------------------------------------------------------------------

-- | Walking over types and coercions.
instance (ExtendPath c Crumb, AddBindings c) => Walker c TyCo where

  allR :: forall m. MonadCatch m => Rewrite c m TyCo -> Rewrite c m TyCo
  allR r = prefixFailMsg "allR failed: " $
           rewrite $ \ c -> \case
             TypeCore ty     -> inject <$> apply (allR $ extractR r) c ty -- exploiting the fact that types do not contain coercions
             CoercionCore co -> inject <$> apply allRcoercion c co
    where
      allRcoercion :: MonadCatch m => Rewrite c m Coercion
      allRcoercion = readerT $ \case
                              Refl{}        -> reflR (extractR r)
                              TyConAppCo{}  -> tyConAppCoAllR idR (const $ extractR r) -- we don't descend into the TyCon
                              AppCo{}       -> appCoAllR (extractR r) (extractR r)
                              ForAllCo{}    -> forAllCoAllR idR (extractR r) -- we don't descend into the TyVar
                              AxiomInstCo{} -> axiomInstCoAllR idR (const $ extractR r) -- we don't descend into the axiom
                              UnsafeCo{}    -> unsafeCoAllR (extractR r) (extractR r)
                              SymCo{}       -> symCoR (extractR r)
                              TransCo{}     -> transCoAllR (extractR r) (extractR r)
                              InstCo{}      -> instCoAllR (extractR r) (extractR r)
                              NthCo{}       -> nthCoAllR idR (extractR r) -- we don't descend into the Int
                              _             -> idR
      {-# INLINE allRcoercion #-}

---------------------------------------------------------------------

-- | Walking over modules, programs, binding groups, definitions, expressions and case alternatives.
instance (ExtendPath c Crumb, AddBindings c) => Walker c CoreTC where

  allR :: forall m. MonadCatch m => Rewrite c m CoreTC -> Rewrite c m CoreTC
  allR r = prefixFailMsg "allR failed: " $
           rewrite $ \ c -> \case
             Core (GutsCore guts)  -> inject <$> apply allRmodguts c guts
             Core (ProgCore p)     -> inject <$> apply allRprog c p
             Core (BindCore bn)    -> inject <$> apply allRbind c bn
             Core (DefCore def)    -> inject <$> apply allRdef c def
             Core (AltCore alt)    -> inject <$> apply allRalt c alt
             Core (ExprCore e)     -> inject <$> apply allRexpr c e
             TyCo tyCo             -> inject <$> apply (allR $ extractR r) c tyCo -- exploiting the fact that only types and coercions appear within types and coercions
    where
      allRmodguts :: MonadCatch m => Rewrite c m ModGuts
      allRmodguts = modGutsR (extractR r)
      {-# INLINE allRmodguts #-}

      allRprog :: MonadCatch m => Rewrite c m CoreProg
      allRprog = readerT $ \case
                              ProgCons{}  -> progConsAllR (extractR r) (extractR r)
                              _           -> idR
      {-# INLINE allRprog #-}

      allRbind :: MonadCatch m => Rewrite c m CoreBind
      allRbind = readerT $ \case
                              NonRec{}  -> nonRecAllR idR (extractR r) -- we don't descend into the Var
                              Rec _     -> recAllR (const $ extractR r)
      {-# INLINE allRbind #-}

      allRdef :: MonadCatch m => Rewrite c m CoreDef
      allRdef = defAllR idR (extractR r) -- we don't descend into the Id
      {-# INLINE allRdef #-}

      allRalt :: MonadCatch m => Rewrite c m CoreAlt
      allRalt = altAllR idR (const idR) (extractR r) -- we don't descend into the AltCon or Vars
      {-# INLINE allRalt #-}

      allRexpr :: MonadCatch m => Rewrite c m CoreExpr
      allRexpr = readerT $ \case
                              App{}      -> appAllR (extractR r) (extractR r)
                              Lam{}      -> lamAllR idR (extractR r) -- we don't descend into the Var
                              Let{}      -> letAllR (extractR r) (extractR r)
                              Case{}     -> caseAllR (extractR r) idR (extractR r) (const $ extractR r) -- we don't descend into the case binder
                              Cast{}     -> castAllR (extractR r) (extractR r)
                              Tick{}     -> tickAllR idR (extractR r) -- we don't descend into the Tickish
                              Type{}     -> typeR (extractR r)
                              Coercion{} -> coercionR (extractR r)
                              _          -> idR
      {-# INLINE allRexpr #-}

---------------------------------------------------------------------

-- | Translate a module.
--   Slightly different to the other congruence combinators: it passes in /all/ of the original to the reconstruction function.
modGutsT :: (ExtendPath c Crumb, Monad m) => Translate c m CoreProg a -> (ModGuts -> a -> b) -> Translate c m ModGuts b
modGutsT t f = translate $ \ c guts -> f guts <$> apply t (c @@ ModGuts_Prog) (bindsToProg $ mg_binds guts)
{-# INLINE modGutsT #-}

-- | Rewrite the 'CoreProg' child of a module.
modGutsR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoreProg -> Rewrite c m ModGuts
modGutsR r = modGutsT r (\ guts p -> guts {mg_binds = progToBinds p})
{-# INLINE modGutsR #-}

---------------------------------------------------------------------

-- | Translate an empty list.
progNilT :: Monad m => b -> Translate c m CoreProg b
progNilT b = contextfreeT $ \case
                               ProgNil       -> return b
                               ProgCons _ _  -> fail "not an empty program."
{-# INLINE progNilT #-}

-- | Translate a program of the form: ('CoreBind' @:@ 'CoreProg')
progConsT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m CoreBind a1 -> Translate c m CoreProg a2 -> (a1 -> a2 -> b) -> Translate c m CoreProg b
progConsT t1 t2 f = translate $ \ c -> \case
                                          ProgCons bd p -> f <$> apply t1 (c @@ ProgCons_Head) bd <*> apply t2 (addBindingGroup bd c @@ ProgCons_Tail) p
                                          _             -> fail "not a non-empty program."
{-# INLINE progConsT #-}

-- | Rewrite all children of a program of the form: ('CoreBind' @:@ 'CoreProg')
progConsAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m CoreBind -> Rewrite c m CoreProg -> Rewrite c m CoreProg
progConsAllR r1 r2 = progConsT r1 r2 ProgCons
{-# INLINE progConsAllR #-}

-- | Rewrite any children of a program of the form: ('CoreBind' @:@ 'CoreProg')
progConsAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m CoreBind -> Rewrite c m CoreProg -> Rewrite c m CoreProg
progConsAnyR r1 r2 = unwrapAnyR $ progConsAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE progConsAnyR #-}

-- | Rewrite one child of a program of the form: ('CoreBind' @:@ 'CoreProg')
progConsOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m CoreBind -> Rewrite c m CoreProg -> Rewrite c m CoreProg
progConsOneR r1 r2 = unwrapOneR $  progConsAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE progConsOneR #-}

---------------------------------------------------------------------

-- | Translate a binding group of the form: @NonRec@ 'Var' 'CoreExpr'
nonRecT :: (ExtendPath c Crumb, Monad m) => Translate c m Var a1 -> Translate c m CoreExpr a2 -> (a1 -> a2 -> b) -> Translate c m CoreBind b
nonRecT t1 t2 f = translate $ \ c -> \case
                                        NonRec v e -> f <$> apply t1 (c @@ NonRec_Var) v <*> apply t2 (c @@ NonRec_RHS) e
                                        _          -> fail "not a non-recursive binding group."
{-# INLINE nonRecT #-}

-- | Rewrite all children of a binding group of the form: @NonRec@ 'Var' 'CoreExpr'
nonRecAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreBind
nonRecAllR r1 r2 = nonRecT r1 r2 NonRec
{-# INLINE nonRecAllR #-}

-- | Rewrite any children of a binding group of the form: @NonRec@ 'Var' 'CoreExpr'
nonRecAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreBind
nonRecAnyR r1 r2 = unwrapAnyR (nonRecAllR (wrapAnyR r1) (wrapAnyR r2))
{-# INLINE nonRecAnyR #-}

-- | Rewrite one child of a binding group of the form: @NonRec@ 'Var' 'CoreExpr'
nonRecOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreBind
nonRecOneR r1 r2 = unwrapOneR (nonRecAllR (wrapOneR r1) (wrapOneR r2))
{-# INLINE nonRecOneR #-}


-- | Translate a binding group of the form: @Rec@ ['CoreDef']
recT :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> Translate c m CoreDef a) -> ([a] -> b) -> Translate c m CoreBind b
recT t f = translate $ \ c -> \case
         Rec bds -> -- Notice how we add the scoping bindings here *before* descending into each individual definition.
                    let c' = addBindingGroup (Rec bds) c
                     in f <$> sequence [ apply (t n) (c' @@ Rec_Def n) (Def v e) -- here we convert from (Id,CoreExpr) to CoreDef
                                       | ((v,e),n) <- zip bds [0..]
                                       ]
         _       -> fail "not a recursive binding group."
{-# INLINE recT #-}

-- | Rewrite all children of a binding group of the form: @Rec@ ['CoreDef']
recAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreBind
recAllR rs = recT rs defsToRecBind
{-# INLINE recAllR #-}

-- | Rewrite any children of a binding group of the form: @Rec@ ['CoreDef']
recAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreBind
recAnyR rs = unwrapAnyR $ recAllR (wrapAnyR . rs)
{-# INLINE recAnyR #-}

-- | Rewrite one child of a binding group of the form: @Rec@ ['CoreDef']
recOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreBind
recOneR rs = unwrapOneR $ recAllR (wrapOneR . rs)
{-# INLINE recOneR #-}

---------------------------------------------------------------------

-- | Translate a recursive definition of the form: @Def@ 'Id' 'CoreExpr'
defT :: (ExtendPath c Crumb, Monad m) => Translate c m Id a1 -> Translate c m CoreExpr a2 -> (a1 -> a2 -> b) -> Translate c m CoreDef b
defT t1 t2 f = translate $ \ c (Def v e) -> f <$> apply t1 (c @@ Def_Id) v <*> apply t2 (c @@ Def_RHS) e
{-# INLINE defT #-}

-- | Rewrite all children of a recursive definition of the form: @Def@ 'Id' 'CoreExpr'
defAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Id -> Rewrite c m CoreExpr -> Rewrite c m CoreDef
defAllR r1 r2 = defT r1 r2 Def
{-# INLINE defAllR #-}

-- | Rewrite any children of a recursive definition of the form: @Def@ 'Id' 'CoreExpr'
defAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Id -> Rewrite c m CoreExpr -> Rewrite c m CoreDef
defAnyR r1 r2 = unwrapAnyR (defAllR (wrapAnyR r1) (wrapAnyR r2))
{-# INLINE defAnyR #-}

-- | Rewrite one child of a recursive definition of the form: @Def@ 'Id' 'CoreExpr'
defOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Id -> Rewrite c m CoreExpr -> Rewrite c m CoreDef
defOneR r1 r2 = unwrapOneR (defAllR (wrapOneR r1) (wrapOneR r2))
{-# INLINE defOneR #-}

---------------------------------------------------------------------

-- | Translate a case alternative of the form: ('AltCon', ['Var'], 'CoreExpr')
altT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m AltCon a1 -> (Int -> Translate c m Var a2) -> Translate c m CoreExpr a3 -> (a1 -> [a2] -> a3 -> b) -> Translate c m CoreAlt b
altT t1 ts t2 f = translate $ \ c (con,vs,e) -> f <$> apply t1 (c @@ Alt_Con) con
                                                  <*> sequence [ apply (ts n) (c @@ Alt_Var n) v | (v,n) <- zip vs [1..] ]
                                                  <*> apply t2 (addAltBindings vs c @@ Alt_RHS) e
{-# INLINE altT #-}

-- | Rewrite all children of a case alternative of the form: ('AltCon', 'Id', 'CoreExpr')
altAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m AltCon -> (Int -> Rewrite c m Var) -> Rewrite c m CoreExpr -> Rewrite c m CoreAlt
altAllR r1 rs r2 = altT r1 rs r2 (,,)
{-# INLINE altAllR #-}

-- | Rewrite any children of a case alternative of the form: ('AltCon', 'Id', 'CoreExpr')
altAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m AltCon -> (Int -> Rewrite c m Var) -> Rewrite c m CoreExpr -> Rewrite c m CoreAlt
altAnyR r1 rs r2 = unwrapAnyR (altAllR (wrapAnyR r1) (wrapAnyR . rs) (wrapAnyR r2))
{-# INLINE altAnyR #-}

-- | Rewrite one child of a case alternative of the form: ('AltCon', 'Id', 'CoreExpr')
altOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m AltCon -> (Int -> Rewrite c m Var) -> Rewrite c m CoreExpr -> Rewrite c m CoreAlt
altOneR r1 rs r2 = unwrapOneR (altAllR (wrapOneR r1) (wrapOneR . rs) (wrapOneR r2))
{-# INLINE altOneR #-}

---------------------------------------------------------------------

-- | Translate an expression of the form: @Var@ 'Id'
varT :: (ExtendPath c Crumb, Monad m) => Translate c m Id b -> Translate c m CoreExpr b
varT t = translate $ \ c -> \case
                               Var v -> apply t (c @@ Var_Id) v
                               _     -> fail "not a variable."
{-# INLINE varT #-}

-- | Rewrite the 'Id' child in an expression of the form: @Var@ 'Id'
varR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Id -> Rewrite c m CoreExpr
varR r = varT (Var <$> r)
{-# INLINE varR #-}


-- | Translate an expression of the form: @Lit@ 'Literal'
litT :: (ExtendPath c Crumb, Monad m) => Translate c m Literal b -> Translate c m CoreExpr b
litT t = translate $ \ c -> \case
                               Lit x -> apply t (c @@ Lit_Lit) x
                               _     -> fail "not a literal."
{-# INLINE litT #-}

-- | Rewrite the 'Literal' child in an expression of the form: @Lit@ 'Literal'
litR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Literal -> Rewrite c m CoreExpr
litR r = litT (Lit <$> r)
{-# INLINE litR #-}


-- | Translate an expression of the form: @App@ 'CoreExpr' 'CoreExpr'
appT :: (ExtendPath c Crumb, Monad m) => Translate c m CoreExpr a1 -> Translate c m CoreExpr a2 -> (a1 -> a2 -> b) -> Translate c m CoreExpr b
appT t1 t2 f = translate $ \ c -> \case
                                     App e1 e2 -> f <$> apply t1 (c @@ App_Fun) e1 <*> apply t2 (c @@ App_Arg) e2
                                     _         -> fail "not an application."
{-# INLINE appT #-}

-- | Rewrite all children of an expression of the form: @App@ 'CoreExpr' 'CoreExpr'
appAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoreExpr -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
appAllR r1 r2 = appT r1 r2 App
{-# INLINE appAllR #-}

-- | Rewrite any children of an expression of the form: @App@ 'CoreExpr' 'CoreExpr'
appAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m CoreExpr -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
appAnyR r1 r2 = unwrapAnyR $ appAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE appAnyR #-}

-- | Rewrite one child of an expression of the form: @App@ 'CoreExpr' 'CoreExpr'
appOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m CoreExpr -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
appOneR r1 r2 = unwrapOneR $ appAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE appOneR #-}


-- | Translate an expression of the form: @Lam@ 'Var' 'CoreExpr'
lamT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m Var a1 -> Translate c m CoreExpr a2 -> (a1 -> a2 -> b) -> Translate c m CoreExpr b
lamT t1 t2 f = translate $ \ c -> \case
                                     Lam v e -> f <$> apply t1 (c @@ Lam_Var) v <*> apply t2 (addLambdaBinding v c @@ Lam_Body) e
                                     _       -> fail "not a lambda."
{-# INLINE lamT #-}

-- | Rewrite all children of an expression of the form: @Lam@ 'Var' 'CoreExpr'
lamAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
lamAllR r1 r2 = lamT r1 r2 Lam
{-# INLINE lamAllR #-}

-- | Rewrite any children of an expression of the form: @Lam@ 'Var' 'CoreExpr'
lamAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
lamAnyR r1 r2 = unwrapAnyR $ lamAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE lamAnyR #-}

-- | Rewrite one child of an expression of the form: @Lam@ 'Var' 'CoreExpr'
lamOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
lamOneR r1 r2 = unwrapOneR $ lamAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE lamOneR #-}


-- | Translate an expression of the form: @Let@ 'CoreBind' 'CoreExpr'
letT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m CoreBind a1 -> Translate c m CoreExpr a2 -> (a1 -> a2 -> b) -> Translate c m CoreExpr b
letT t1 t2 f = translate $ \ c -> \case
        Let bds e -> -- Note we use the *original* context for the binding group.
                     -- If the bindings are recursive, they will be added to the context by recT.
                     f <$> apply t1 (c @@ Let_Bind) bds <*> apply t2 (addBindingGroup bds c @@ Let_Body) e
        _         -> fail "not a let node."
{-# INLINE letT #-}

-- | Rewrite all children of an expression of the form: @Let@ 'CoreBind' 'CoreExpr'
letAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m CoreBind -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letAllR r1 r2 = letT r1 r2 Let
{-# INLINE letAllR #-}

-- | Rewrite any children of an expression of the form: @Let@ 'CoreBind' 'CoreExpr'
letAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m CoreBind -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letAnyR r1 r2 = unwrapAnyR $ letAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE letAnyR #-}

-- | Rewrite one child of an expression of the form: @Let@ 'CoreBind' 'CoreExpr'
letOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m CoreBind -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letOneR r1 r2 = unwrapOneR $ letAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE letOneR #-}


-- | Translate an expression of the form: @Case@ 'CoreExpr' 'Id' 'Type' ['CoreAlt']
caseT :: (ExtendPath c Crumb, AddBindings c, Monad m)
      => Translate c m CoreExpr e
      -> Translate c m Id w
      -> Translate c m Type ty
      -> (Int -> Translate c m CoreAlt alt)
      -> (e -> w -> ty -> [alt] -> b)
      -> Translate c m CoreExpr b
caseT te tw tty talts f = translate $ \ c -> \case
         Case e w ty alts -> f <$> apply te (c @@ Case_Scrutinee) e
                               <*> apply tw (c @@ Case_Binder) w
                               <*> apply tty (c @@ Case_Type) ty
                               <*> sequence [ apply (talts n) (addCaseWildBinding (w,e,alt) c @@ Case_Alt n) alt
                                            | (alt,n) <- zip alts [0..]
                                            ]
         _                -> fail "not a case."
{-# INLINE caseT #-}

-- | Rewrite all children of an expression of the form: @Case@ 'CoreExpr' 'Id' 'Type' ['CoreAlt']
caseAllR :: (ExtendPath c Crumb, AddBindings c, Monad m)
         => Rewrite c m CoreExpr
         -> Rewrite c m Id
         -> Rewrite c m Type
         -> (Int -> Rewrite c m CoreAlt)
         -> Rewrite c m CoreExpr
caseAllR re rw rty ralts = caseT re rw rty ralts Case
{-# INLINE caseAllR #-}

-- | Rewrite any children of an expression of the form: @Case@ 'CoreExpr' 'Id' 'Type' ['CoreAlt']
caseAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m)
         => Rewrite c m CoreExpr
         -> Rewrite c m Id
         -> Rewrite c m Type
         -> (Int -> Rewrite c m CoreAlt)
         -> Rewrite c m CoreExpr
caseAnyR re rw rty ralts = unwrapAnyR $ caseAllR (wrapAnyR re) (wrapAnyR rw) (wrapAnyR rty) (wrapAnyR . ralts)
{-# INLINE caseAnyR #-}

-- | Rewrite one child of an expression of the form: @Case@ 'CoreExpr' 'Id' 'Type' ['CoreAlt']
caseOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m)
         => Rewrite c m CoreExpr
         -> Rewrite c m Id
         -> Rewrite c m Type
         -> (Int -> Rewrite c m CoreAlt)
         -> Rewrite c m CoreExpr
caseOneR re rw rty ralts = unwrapOneR $ caseAllR (wrapOneR re) (wrapOneR rw) (wrapOneR rty) (wrapOneR . ralts)
{-# INLINE caseOneR #-}


-- | Translate an expression of the form: @Cast@ 'CoreExpr' 'Coercion'
castT :: (ExtendPath c Crumb, Monad m) => Translate c m CoreExpr a1 -> Translate c m Coercion a2 -> (a1 -> a2 -> b) -> Translate c m CoreExpr b
castT t1 t2 f = translate $ \ c -> \case
                                      Cast e co -> f <$> apply t1 (c @@ Cast_Expr) e <*> apply t2 (c @@ Cast_Co) co
                                      _         -> fail "not a cast."
{-# INLINE castT #-}

-- | Rewrite all children of an expression of the form: @Cast@ 'CoreExpr' 'Coercion'
castAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoreExpr -> Rewrite c m Coercion -> Rewrite c m CoreExpr
castAllR r1 r2 = castT r1 r2 Cast
{-# INLINE castAllR #-}

-- | Rewrite any children of an expression of the form: @Cast@ 'CoreExpr' 'Coercion'
castAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m CoreExpr -> Rewrite c m Coercion -> Rewrite c m CoreExpr
castAnyR r1 r2 = unwrapAnyR $ castAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE castAnyR #-}

-- | Rewrite one child of an expression of the form: @Cast@ 'CoreExpr' 'Coercion'
castOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m CoreExpr -> Rewrite c m Coercion -> Rewrite c m CoreExpr
castOneR r1 r2 = unwrapOneR $ castAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE castOneR #-}


-- | Translate an expression of the form: @Tick@ 'CoreTickish' 'CoreExpr'
tickT :: (ExtendPath c Crumb, Monad m) => Translate c m CoreTickish a1 -> Translate c m CoreExpr a2 -> (a1 -> a2 -> b) -> Translate c m CoreExpr b
tickT t1 t2 f = translate $ \ c -> \case
                                      Tick tk e -> f <$> apply t1 (c @@ Tick_Tick) tk <*> apply t2 (c @@ Tick_Expr) e
                                      _         -> fail "not a tick."
{-# INLINE tickT #-}

-- | Rewrite all children of an expression of the form: @Tick@ 'CoreTickish' 'CoreExpr'
tickAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoreTickish -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
tickAllR r1 r2 = tickT r1 r2 Tick
{-# INLINE tickAllR #-}

-- | Rewrite any children of an expression of the form: @Tick@ 'CoreTickish' 'CoreExpr'
tickAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m CoreTickish -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
tickAnyR r1 r2 = unwrapAnyR $ tickAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE tickAnyR #-}

-- | Rewrite any children of an expression of the form: @Tick@ 'CoreTickish' 'CoreExpr'
tickOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m CoreTickish -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
tickOneR r1 r2 = unwrapOneR $ tickAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE tickOneR #-}


-- | Translate an expression of the form: @Type@ 'Type'
typeT :: Monad m => Translate c m Type b -> Translate c m CoreExpr b
typeT t = translate $ \ c -> \case
                                Type ty -> apply t c ty
                                _       -> fail "not a type."
{-# INLINE typeT #-}

-- | Rewrite the 'Type' child in an expression of the form: @Type@ 'Type'
typeR :: Monad m => Rewrite c m Type -> Rewrite c m CoreExpr
typeR r = typeT (Type <$> r)
{-# INLINE typeR #-}


-- | Translate an expression of the form: @Coercion@ 'Coercion'
coercionT :: Monad m => Translate c m Coercion b -> Translate c m CoreExpr b
coercionT t = translate $ \ c -> \case
                                    Coercion co -> apply t c co
                                    _           -> fail "not a coercion."
{-# INLINE coercionT #-}

-- | Rewrite the 'Coercion' child in an expression of the form: @Coercion@ 'Coercion'
coercionR :: Monad m => Rewrite c m Coercion -> Rewrite c m CoreExpr
coercionR r = coercionT (Coercion <$> r)
{-# INLINE coercionR #-}

---------------------------------------------------------------------

-- Some composite congruence combinators to export.

-- | Translate a binding group of the form: @Rec@ [('Id', 'CoreExpr')]
recDefT :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> (Translate c m Id a1, Translate c m CoreExpr a2)) -> ([(a1,a2)] -> b) -> Translate c m CoreBind b
recDefT ts = recT (\ n -> uncurry defT (ts n) (,))
{-# INLINE recDefT #-}

-- | Rewrite all children of a binding group of the form: @Rec@ [('Id', 'CoreExpr')]
recDefAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreBind
recDefAllR rs = recAllR (\ n -> uncurry defAllR (rs n))
{-# INLINE recDefAllR #-}

-- | Rewrite any children of a binding group of the form: @Rec@ [('Id', 'CoreExpr')]
recDefAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreBind
recDefAnyR rs = recAnyR (\ n -> uncurry defAnyR (rs n))
{-# INLINE recDefAnyR #-}

-- | Rewrite one child of a binding group of the form: @Rec@ [('Id', 'CoreExpr')]
recDefOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreBind
recDefOneR rs = recOneR (\ n -> uncurry defOneR (rs n))
{-# INLINE recDefOneR #-}


-- | Translate a program of the form: (@NonRec@ 'Var' 'CoreExpr') @:@ 'CoreProg'
consNonRecT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m Var a1 -> Translate c m CoreExpr a2 -> Translate c m CoreProg a3 -> (a1 -> a2 -> a3 -> b) -> Translate c m CoreProg b
consNonRecT t1 t2 t3 f = progConsT (nonRecT t1 t2 (,)) t3 (uncurry f)
{-# INLINE consNonRecT #-}

-- | Rewrite all children of an expression of the form: (@NonRec@ 'Var' 'CoreExpr') @:@ 'CoreProg'
consNonRecAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consNonRecAllR r1 r2 r3 = progConsAllR (nonRecAllR r1 r2) r3
{-# INLINE consNonRecAllR #-}

-- | Rewrite any children of an expression of the form: (@NonRec@ 'Var' 'CoreExpr') @:@ 'CoreProg'
consNonRecAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consNonRecAnyR r1 r2 r3 = progConsAllR (nonRecAnyR r1 r2) r3
{-# INLINE consNonRecAnyR #-}

-- | Rewrite one child of an expression of the form: (@NonRec@ 'Var' 'CoreExpr') @:@ 'CoreProg'
consNonRecOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consNonRecOneR r1 r2 r3 = progConsAllR (nonRecOneR r1 r2) r3
{-# INLINE consNonRecOneR #-}


-- | Translate an expression of the form: (@Rec@ ['CoreDef']) @:@ 'CoreProg'
consRecT :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> Translate c m CoreDef a1) -> Translate c m CoreProg a2 -> ([a1] -> a2 -> b) -> Translate c m CoreProg b
consRecT ts t = progConsT (recT ts id) t
{-# INLINE consRecT #-}

-- | Rewrite all children of an expression of the form: (@Rec@ ['CoreDef']) @:@ 'CoreProg'
consRecAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consRecAllR rs r = progConsAllR (recAllR rs) r
{-# INLINE consRecAllR #-}

-- | Rewrite any children of an expression of the form: (@Rec@ ['CoreDef']) @:@ 'CoreProg'
consRecAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consRecAnyR rs r = progConsAnyR (recAnyR rs) r
{-# INLINE consRecAnyR #-}

-- | Rewrite one child of an expression of the form: (@Rec@ ['CoreDef']) @:@ 'CoreProg'
consRecOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consRecOneR rs r = progConsOneR (recOneR rs) r
{-# INLINE consRecOneR #-}


-- | Translate an expression of the form: (@Rec@ [('Id', 'CoreExpr')]) @:@ 'CoreProg'
consRecDefT :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> (Translate c m Id a1, Translate c m CoreExpr a2)) -> Translate c m CoreProg a3 -> ([(a1,a2)] -> a3 -> b) -> Translate c m CoreProg b
consRecDefT ts t = consRecT (\ n -> uncurry defT (ts n) (,)) t
{-# INLINE consRecDefT #-}

-- | Rewrite all children of an expression of the form: (@Rec@ [('Id', 'CoreExpr')]) @:@ 'CoreProg'
consRecDefAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consRecDefAllR rs r = consRecAllR (\ n -> uncurry defAllR (rs n)) r
{-# INLINE consRecDefAllR #-}

-- | Rewrite any children of an expression of the form: (@Rec@ [('Id', 'CoreExpr')]) @:@ 'CoreProg'
consRecDefAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consRecDefAnyR rs r = consRecAnyR (\ n -> uncurry defAnyR (rs n)) r
{-# INLINE consRecDefAnyR #-}

-- | Rewrite one child of an expression of the form: (@Rec@ [('Id', 'CoreExpr')]) @:@ 'CoreProg'
consRecDefOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreProg -> Rewrite c m CoreProg
consRecDefOneR rs r = consRecOneR (\ n -> uncurry defOneR (rs n)) r
{-# INLINE consRecDefOneR #-}


-- | Translate an expression of the form: @Let@ (@NonRec@ 'Var' 'CoreExpr') 'CoreExpr'
letNonRecT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m Var a1 -> Translate c m CoreExpr a2 -> Translate c m CoreExpr a3 -> (a1 -> a2 -> a3 -> b) -> Translate c m CoreExpr b
letNonRecT t1 t2 t3 f = letT (nonRecT t1 t2 (,)) t3 (uncurry f)
{-# INLINE letNonRecT #-}

-- | Rewrite all children of an expression of the form: @Let@ (@NonRec@ 'Var' 'CoreExpr') 'CoreExpr'
letNonRecAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letNonRecAllR r1 r2 r3 = letAllR (nonRecAllR r1 r2) r3
{-# INLINE letNonRecAllR #-}

-- | Rewrite any children of an expression of the form: @Let@ (@NonRec@ 'Var' 'CoreExpr') 'CoreExpr'
letNonRecAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letNonRecAnyR r1 r2 r3 = letAnyR (nonRecAnyR r1 r2) r3
{-# INLINE letNonRecAnyR #-}

-- | Rewrite one child of an expression of the form: @Let@ (@NonRec@ 'Var' 'CoreExpr') 'CoreExpr'
letNonRecOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letNonRecOneR r1 r2 r3 = letOneR (nonRecOneR r1 r2) r3
{-# INLINE letNonRecOneR #-}


-- | Translate an expression of the form: @Let@ (@Rec@ ['CoreDef']) 'CoreExpr'
letRecT :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> Translate c m CoreDef a1) -> Translate c m CoreExpr a2 -> ([a1] -> a2 -> b) -> Translate c m CoreExpr b
letRecT ts t = letT (recT ts id) t
{-# INLINE letRecT #-}

-- | Rewrite all children of an expression of the form: @Let@ (@Rec@ ['CoreDef']) 'CoreExpr'
letRecAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letRecAllR rs r = letAllR (recAllR rs) r
{-# INLINE letRecAllR #-}

-- | Rewrite any children of an expression of the form: @Let@ (@Rec@ ['CoreDef']) 'CoreExpr'
letRecAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letRecAnyR rs r = letAnyR (recAnyR rs) r
{-# INLINE letRecAnyR #-}

-- | Rewrite one child of an expression of the form: @Let@ (@Rec@ ['CoreDef']) 'CoreExpr'
letRecOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> Rewrite c m CoreDef) -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letRecOneR rs r = letOneR (recOneR rs) r
{-# INLINE letRecOneR #-}


-- | Translate an expression of the form: @Let@ (@Rec@ [('Id', 'CoreExpr')]) 'CoreExpr'
letRecDefT :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> (Translate c m Id a1, Translate c m CoreExpr a2)) -> Translate c m CoreExpr a3 -> ([(a1,a2)] -> a3 -> b) -> Translate c m CoreExpr b
letRecDefT ts t = letRecT (\ n -> uncurry defT (ts n) (,)) t
{-# INLINE letRecDefT #-}

-- | Rewrite all children of an expression of the form: @Let@ (@Rec@ [('Id', 'CoreExpr')]) 'CoreExpr'
letRecDefAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letRecDefAllR rs r = letRecAllR (\ n -> uncurry defAllR (rs n)) r
{-# INLINE letRecDefAllR #-}

-- | Rewrite any children of an expression of the form: @Let@ (@Rec@ [('Id', 'CoreExpr')]) 'CoreExpr'
letRecDefAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letRecDefAnyR rs r = letRecAnyR (\ n -> uncurry defAnyR (rs n)) r
{-# INLINE letRecDefAnyR #-}

-- | Rewrite one child of an expression of the form: @Let@ (@Rec@ [('Id', 'CoreExpr')]) 'CoreExpr'
letRecDefOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => (Int -> (Rewrite c m Id, Rewrite c m CoreExpr)) -> Rewrite c m CoreExpr -> Rewrite c m CoreExpr
letRecDefOneR rs r = letRecOneR (\ n -> uncurry defOneR (rs n)) r
{-# INLINE letRecDefOneR #-}


-- | Translate an expression of the form: @Case@ 'CoreExpr' 'Id' 'Type' [('AltCon', ['Var'], 'CoreExpr')]
caseAltT :: (ExtendPath c Crumb, AddBindings c, Monad m)
         => Translate c m CoreExpr sc
         -> Translate c m Id w
         -> Translate c m Type ty
         -> (Int -> (Translate c m AltCon con, (Int -> Translate c m Var v), Translate c m CoreExpr rhs)) -> (sc -> w -> ty -> [(con,[v],rhs)] -> b)
         -> Translate c m CoreExpr b
caseAltT tsc tw tty talts = caseT tsc tw tty (\ n -> let (tcon,tvs,te) = talts n in altT tcon tvs te (,,))
{-# INLINE caseAltT #-}

-- | Rewrite all children of an expression of the form: @Case@ 'CoreExpr' 'Id' 'Type' [('AltCon', ['Var'], 'CoreExpr')]
caseAltAllR :: (ExtendPath c Crumb, AddBindings c, Monad m)
            => Rewrite c m CoreExpr
            -> Rewrite c m Id
            -> Rewrite c m Type
            -> (Int -> (Rewrite c m AltCon, (Int -> Rewrite c m Var), Rewrite c m CoreExpr))
            -> Rewrite c m CoreExpr
caseAltAllR rsc rw rty ralts = caseAllR rsc rw rty (\ n -> let (rcon,rvs,re) = ralts n in altAllR rcon rvs re)
{-# INLINE caseAltAllR #-}

-- | Rewrite any children of an expression of the form: @Case@ 'CoreExpr' 'Id' 'Type' [('AltCon', ['Var'], 'CoreExpr')]
caseAltAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m)
            => Rewrite c m CoreExpr
            -> Rewrite c m Id
            -> Rewrite c m Type
            -> (Int -> (Rewrite c m AltCon, (Int -> Rewrite c m Var), Rewrite c m CoreExpr))
            -> Rewrite c m CoreExpr
caseAltAnyR rsc rw rty ralts = caseAnyR rsc rw rty (\ n -> let (rcon,rvs,re) = ralts n in altAnyR rcon rvs re)
{-# INLINE caseAltAnyR #-}

-- | Rewrite one child of an expression of the form: @Case@ 'CoreExpr' 'Id' 'Type' [('AltCon', ['Var'], 'CoreExpr')]
caseAltOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m)
            => Rewrite c m CoreExpr
            -> Rewrite c m Id
            -> Rewrite c m Type
            -> (Int -> (Rewrite c m AltCon, (Int -> Rewrite c m Var), Rewrite c m CoreExpr))
            -> Rewrite c m CoreExpr
caseAltOneR rsc rw rty ralts = caseOneR rsc rw rty (\ n -> let (rcon,rvs,re) = ralts n in altOneR rcon rvs re)
{-# INLINE caseAltOneR #-}

---------------------------------------------------------------------

-- | Promote a rewrite on 'ModGuts' to a rewrite on 'Core'.
promoteModGutsR :: (ExtendPath c Crumb, Monad m) => Rewrite c m ModGuts -> Rewrite c m Core
promoteModGutsR = promoteWithFailMsgR "This rewrite can only succeed at the module level."
{-# INLINE promoteModGutsR #-}

-- | Promote a rewrite on 'CoreProg' to a rewrite on 'Core'.
promoteProgR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoreProg -> Rewrite c m Core
promoteProgR = promoteWithFailMsgR "This rewrite can only succeed at program nodes (the top-level)."
{-# INLINE promoteProgR #-}

-- | Promote a rewrite on 'CoreBind' to a rewrite on 'Core'.
promoteBindR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoreBind -> Rewrite c m Core
promoteBindR = promoteWithFailMsgR "This rewrite can only succeed at binding group nodes."
{-# INLINE promoteBindR #-}

-- | Promote a rewrite on 'CoreDef' to a rewrite on 'Core'.
promoteDefR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoreDef -> Rewrite c m Core
promoteDefR = promoteWithFailMsgR "This rewrite can only succeed at recursive definition nodes."
{-# INLINE promoteDefR #-}

-- | Promote a rewrite on 'CoreAlt' to a rewrite on 'Core'.
promoteAltR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoreAlt -> Rewrite c m Core
promoteAltR = promoteWithFailMsgR "This rewrite can only succeed at case alternative nodes."
{-# INLINE promoteAltR #-}

-- | Promote a rewrite on 'CoreExpr' to a rewrite on 'Core'.
promoteExprR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoreExpr -> Rewrite c m Core
promoteExprR = promoteWithFailMsgR "This rewrite can only succeed at expression nodes."
{-# INLINE promoteExprR #-}

---------------------------------------------------------------------

-- | Promote a bidirectional rewrite on 'CoreExpr' to a bidirectional rewrite on 'Core'.
promoteExprBiR :: (ExtendPath c Crumb, Monad m) => BiRewrite c m CoreExpr -> BiRewrite c m Core
promoteExprBiR b = bidirectional (promoteExprR $ forewardT b) (promoteExprR $ backwardT b)
{-# INLINE promoteExprBiR #-}

---------------------------------------------------------------------

-- | Promote a translate on 'ModGuts' to a translate on 'Core'.
promoteModGutsT :: (ExtendPath c Crumb, Monad m) => Translate c m ModGuts b -> Translate c m Core b
promoteModGutsT = promoteWithFailMsgT "This translate can only succeed at the module level."
{-# INLINE promoteModGutsT #-}

-- | Promote a translate on 'CoreProg' to a translate on 'Core'.
promoteProgT :: (ExtendPath c Crumb, Monad m) => Translate c m CoreProg b -> Translate c m Core b
promoteProgT = promoteWithFailMsgT "This translate can only succeed at program nodes (the top-level)."
{-# INLINE promoteProgT #-}

-- | Promote a translate on 'CoreBind' to a translate on 'Core'.
promoteBindT :: (ExtendPath c Crumb, Monad m) => Translate c m CoreBind b -> Translate c m Core b
promoteBindT = promoteWithFailMsgT "This translate can only succeed at binding group nodes."
{-# INLINE promoteBindT #-}

-- | Promote a translate on 'CoreDef' to a translate on 'Core'.
promoteDefT :: (ExtendPath c Crumb, Monad m) => Translate c m CoreDef b -> Translate c m Core b
promoteDefT = promoteWithFailMsgT "This translate can only succeed at recursive definition nodes."
{-# INLINE promoteDefT #-}

-- | Promote a translate on 'CoreAlt' to a translate on 'Core'.
promoteAltT :: (ExtendPath c Crumb, Monad m) => Translate c m CoreAlt b -> Translate c m Core b
promoteAltT = promoteWithFailMsgT "This translate can only succeed at case alternative nodes."
{-# INLINE promoteAltT #-}

-- | Promote a translate on 'CoreExpr' to a translate on 'Core'.
promoteExprT :: (ExtendPath c Crumb, Monad m) => Translate c m CoreExpr b -> Translate c m Core b
promoteExprT = promoteWithFailMsgT "This translate can only succeed at expression nodes."
{-# INLINE promoteExprT #-}


---------------------------------------------------------------------
---------------------------------------------------------------------

-- Types

-- | Translate a type of the form: @TyVarTy@ 'TyVar'
tyVarT :: (ExtendPath c Crumb, Monad m) => Translate c m TyVar b -> Translate c m Type b
tyVarT t = translate $ \ c -> \case
                                 TyVarTy v -> apply t (c @@ TyVarTy_TyVar) v
                                 _         -> fail "not a type variable."
{-# INLINE tyVarT #-}

-- | Rewrite the 'TyVar' child of a type of the form: @TyVarTy@ 'TyVar'
tyVarR :: (ExtendPath c Crumb, Monad m) => Rewrite c m TyVar -> Rewrite c m Type
tyVarR r = tyVarT (TyVarTy <$> r)
{-# INLINE tyVarR #-}


-- | Translate a type of the form: @LitTy@ 'TyLit'
litTyT :: (ExtendPath c Crumb, Monad m) => Translate c m TyLit b -> Translate c m Type b
litTyT t = translate $ \ c -> \case
                                 LitTy x -> apply t (c @@ LitTy_TyLit) x
                                 _       -> fail "not a type literal."
{-# INLINE litTyT #-}

-- | Rewrite the 'TyLit' child of a type of the form: @LitTy@ 'TyLit'
litTyR :: (ExtendPath c Crumb, Monad m) => Rewrite c m TyLit -> Rewrite c m Type
litTyR r = litTyT (LitTy <$> r)
{-# INLINE litTyR #-}


-- | Translate a type of the form: @AppTy@ 'Type' 'Type'
appTyT :: (ExtendPath c Crumb, Monad m) => Translate c m Type a1 -> Translate c m Type a2 -> (a1 -> a2 -> b) -> Translate c m Type b
appTyT t1 t2 f = translate $ \ c -> \case
                                     AppTy ty1 ty2 -> f <$> apply t1 (c @@ AppTy_Fun) ty1 <*> apply t2 (c @@ AppTy_Arg) ty2
                                     _             -> fail "not a type application."
{-# INLINE appTyT #-}

-- | Rewrite all children of a type of the form: @AppTy@ 'Type' 'Type'
appTyAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Type
appTyAllR r1 r2 = appTyT r1 r2 AppTy
{-# INLINE appTyAllR #-}

-- | Rewrite any children of a type of the form: @AppTy@ 'Type' 'Type'
appTyAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Type
appTyAnyR r1 r2 = unwrapAnyR $ appTyAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE appTyAnyR #-}

-- | Rewrite one child of a type of the form: @AppTy@ 'Type' 'Type'
appTyOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Type
appTyOneR r1 r2 = unwrapOneR $ appTyAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE appTyOneR #-}


-- | Translate a type of the form: @FunTy@ 'Type' 'Type'
funTyT :: (ExtendPath c Crumb, Monad m) => Translate c m Type a1 -> Translate c m Type a2 -> (a1 -> a2 -> b) -> Translate c m Type b
funTyT t1 t2 f = translate $ \ c -> \case
                                     FunTy ty1 ty2 -> f <$> apply t1 (c @@ FunTy_Dom) ty1 <*> apply t2 (c @@ FunTy_CoDom) ty2
                                     _             -> fail "not a function type."
{-# INLINE funTyT #-}

-- | Rewrite all children of a type of the form: @FunTy@ 'Type' 'Type'
funTyAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Type
funTyAllR r1 r2 = funTyT r1 r2 FunTy
{-# INLINE funTyAllR #-}

-- | Rewrite any children of a type of the form: @FunTy@ 'Type' 'Type'
funTyAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Type
funTyAnyR r1 r2 = unwrapAnyR $ funTyAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE funTyAnyR #-}

-- | Rewrite one child of a type of the form: @FunTy@ 'Type' 'Type'
funTyOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Type
funTyOneR r1 r2 = unwrapOneR $ funTyAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE funTyOneR #-}


-- | Translate a type of the form: @ForAllTy@ 'Var' 'Type'
forAllTyT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m Var a1 -> Translate c m Type a2 -> (a1 -> a2 -> b) -> Translate c m Type b
forAllTyT t1 t2 f = translate $ \ c -> \case
                                          ForAllTy v ty -> f <$> apply t1 (c @@ ForAllTy_Var) v <*> apply t2 (addForallBinding v c @@ ForAllTy_Body) ty
                                          _             -> fail "not a forall type."
{-# INLINE forAllTyT #-}

-- | Rewrite all children of a type of the form: @ForAllTy@ 'Var' 'Type'
forAllTyAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m Var -> Rewrite c m Type -> Rewrite c m Type
forAllTyAllR r1 r2 = forAllTyT r1 r2 ForAllTy
{-# INLINE forAllTyAllR #-}

-- | Rewrite any children of a type of the form: @ForAllTy@ 'Var' 'Type'
forAllTyAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m Type -> Rewrite c m Type
forAllTyAnyR r1 r2 = unwrapAnyR $ forAllTyAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE forAllTyAnyR #-}

-- | Rewrite one child of a type of the form: @ForAllTy@ 'Var' 'Type'
forAllTyOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m Var -> Rewrite c m Type -> Rewrite c m Type
forAllTyOneR r1 r2 = unwrapOneR $ forAllTyAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE forAllTyOneR #-}


-- | Translate a type of the form: @TyConApp@ 'TyCon' ['KindOrType']
tyConAppT :: (ExtendPath c Crumb, Monad m) => Translate c m TyCon a1 -> (Int -> Translate c m KindOrType a2) -> (a1 -> [a2] -> b) -> Translate c m Type b
tyConAppT t ts f = translate $ \ c -> \case
                                         TyConApp con tys -> f <$> apply t (c @@ TyConApp_TyCon) con <*> sequence [ apply (ts n) (c @@ TyConApp_Arg n) ty | (ty,n) <- zip tys [0..] ]
                                         _                -> fail "not a type-constructor application."
{-# INLINE tyConAppT #-}

-- | Rewrite all children of a type of the form: @TyConApp@ 'TyCon' ['KindOrType']
tyConAppAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m TyCon -> (Int -> Rewrite c m KindOrType) -> Rewrite c m Type
tyConAppAllR r rs = tyConAppT r rs TyConApp
{-# INLINE tyConAppAllR #-}

-- | Rewrite any children of a type of the form: @TyConApp@ 'TyCon' ['KindOrType']
tyConAppAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m TyCon -> (Int -> Rewrite c m KindOrType) -> Rewrite c m Type
tyConAppAnyR r rs = unwrapAnyR $ tyConAppAllR (wrapAnyR r) (wrapAnyR . rs)
{-# INLINE tyConAppAnyR #-}

-- | Rewrite one child of a type of the form: @TyConApp@ 'TyCon' ['KindOrType']
tyConAppOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m TyCon -> (Int -> Rewrite c m KindOrType) -> Rewrite c m Type
tyConAppOneR r rs = unwrapOneR $ tyConAppAllR (wrapOneR r) (wrapOneR . rs)
{-# INLINE tyConAppOneR #-}

---------------------------------------------------------------------
---------------------------------------------------------------------

-- Coercions

-- | Translate a coercion of the form: @Refl@ 'Type'
reflT :: (ExtendPath c Crumb, Monad m) => Translate c m Type b -> Translate c m Coercion b
reflT t = translate $ \ c -> \case
                                 Refl ty -> apply t (c @@ Refl_Type) ty
                                 _       -> fail "not a reflexive coercion."
{-# INLINE reflT #-}

-- | Rewrite the 'Type' child of a coercion of the form: @Refl@ 'Type'
reflR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Type -> Rewrite c m Coercion
reflR r = reflT (Refl <$> r)
{-# INLINE reflR #-}


-- | Translate a coercion of the form: @TyConAppCo@ 'TyCon' ['Coercion']
tyConAppCoT :: (ExtendPath c Crumb, Monad m) => Translate c m TyCon a1 -> (Int -> Translate c m Coercion a2) -> (a1 -> [a2] -> b) -> Translate c m Coercion b
tyConAppCoT t ts f = translate $ \ c -> \case
                                           TyConAppCo con coes -> f <$> apply t (c @@ TyConAppCo_TyCon) con <*> sequence [ apply (ts n) (c @@ TyConAppCo_Arg n) co | (co,n) <- zip coes [0..] ]
                                           _                   -> fail "not a type-constructor coercion."
{-# INLINE tyConAppCoT #-}

-- | Rewrite all children of a coercion of the form: @TyConAppCo@ 'TyCon' ['Coercion']
tyConAppCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m TyCon -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
tyConAppCoAllR r rs = tyConAppCoT r rs TyConAppCo
{-# INLINE tyConAppCoAllR #-}

-- | Rewrite any children of a coercion of the form: @TyConAppCo@ 'TyCon' ['Coercion']
tyConAppCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m TyCon -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
tyConAppCoAnyR r rs = unwrapAnyR $ tyConAppCoAllR (wrapAnyR r) (wrapAnyR . rs)
{-# INLINE tyConAppCoAnyR #-}

-- | Rewrite one child of a coercion of the form: @TyConAppCo@ 'TyCon' ['Coercion']
tyConAppCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m TyCon -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
tyConAppCoOneR r rs = unwrapOneR $ tyConAppCoAllR (wrapOneR r) (wrapOneR . rs)
{-# INLINE tyConAppCoOneR #-}


-- | Translate a coercion of the form: @AppCo@ 'Coercion' 'Coercion'
appCoT :: (ExtendPath c Crumb, Monad m) => Translate c m Coercion a1 -> Translate c m Coercion a2 -> (a1 -> a2 -> b) -> Translate c m Coercion b
appCoT t1 t2 f = translate $ \ c -> \case
                                     AppCo co1 co2 -> f <$> apply t1 (c @@ AppCo_Fun) co1 <*> apply t2 (c @@ AppCo_Arg) co2
                                     _             -> fail "not a coercion application."
{-# INLINE appCoT #-}

-- | Rewrite all children of a coercion of the form: @AppCo@ 'Coercion' 'Coercion'
appCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Coercion -> Rewrite c m Coercion -> Rewrite c m Coercion
appCoAllR r1 r2 = appCoT r1 r2 AppCo
{-# INLINE appCoAllR #-}

-- | Rewrite any children of a coercion of the form: @AppCo@ 'Coercion' 'Coercion'
appCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Coercion -> Rewrite c m Coercion -> Rewrite c m Coercion
appCoAnyR r1 r2 = unwrapAnyR $ appCoAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE appCoAnyR #-}

-- | Rewrite one child of a coercion of the form: @AppCo@ 'Coercion' 'Coercion'
appCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Coercion -> Rewrite c m Coercion -> Rewrite c m Coercion
appCoOneR r1 r2 = unwrapOneR $ appCoAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE appCoOneR #-}


-- | Translate a coercion of the form: @ForAllCo@ 'TyVar' 'Coercion'
forAllCoT :: (ExtendPath c Crumb, AddBindings c, Monad m) => Translate c m TyVar a1 -> Translate c m Coercion a2 -> (a1 -> a2 -> b) -> Translate c m Coercion b
forAllCoT t1 t2 f = translate $ \ c -> \case
                                          ForAllCo v co -> f <$> apply t1 (c @@ ForAllCo_TyVar) v <*> apply t2 (addForallBinding v c @@ ForAllCo_Body) co
                                          _             -> fail "not a forall coercion."
{-# INLINE forAllCoT #-}

-- | Rewrite all children of a coercion of the form: @ForAllCo@ 'TyVar' 'Coercion'
forAllCoAllR :: (ExtendPath c Crumb, AddBindings c, Monad m) => Rewrite c m TyVar -> Rewrite c m Coercion -> Rewrite c m Coercion
forAllCoAllR r1 r2 = forAllCoT r1 r2 ForAllCo
{-# INLINE forAllCoAllR #-}

-- | Rewrite any children of a coercion of the form: @ForAllCo@ 'TyVar' 'Coercion'
forAllCoAnyR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m TyVar -> Rewrite c m Coercion -> Rewrite c m Coercion
forAllCoAnyR r1 r2 = unwrapAnyR $ forAllCoAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE forAllCoAnyR #-}

-- | Rewrite one child of a coercion of the form: @ForAllCo@ 'TyVar' 'Coercion'
forAllCoOneR :: (ExtendPath c Crumb, AddBindings c, MonadCatch m) => Rewrite c m TyVar -> Rewrite c m Coercion -> Rewrite c m Coercion
forAllCoOneR r1 r2 = unwrapOneR $ forAllCoAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE forAllCoOneR #-}


-- | Translate a coercion of the form: @CoVarCo@ 'CoVar'
coVarCoT :: (ExtendPath c Crumb, Monad m) => Translate c m CoVar b -> Translate c m Coercion b
coVarCoT t = translate $ \ c -> \case
                                   CoVarCo v -> apply t (c @@ CoVarCo_CoVar) v
                                   _         -> fail "not a coercion variable."
{-# INLINE coVarCoT #-}

-- | Rewrite the 'CoVar' child of a coercion of the form: @CoVarCo@ 'CoVar'
coVarCoR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoVar -> Rewrite c m Coercion
coVarCoR r = coVarCoT (CoVarCo <$> r)
{-# INLINE coVarCoR #-}

-- | Translate a coercion of the form: @AxiomInstCo@ 'CoAxiom' ['Coercion']
#if __GLASGOW_HASKELL__ > 706
axiomInstCoT :: (ExtendPath c Crumb, Monad m) => Translate c m (CoAxiom Branched) a1 -> (Int -> Translate c m Coercion a2) -> (a1 -> BranchIndex -> [a2] -> b) -> Translate c m Coercion b
axiomInstCoT t ts f = translate $ \ c -> \case
                                            AxiomInstCo ax idx coes -> f <$> apply t (c @@ AxiomInstCo_Axiom) ax <*> return idx <*> sequence [ apply (ts n) (c @@ AxiomInstCo_Arg n) co | (co,n) <- zip coes [0..] ]
                                            _                   -> fail "not a coercion axiom instantiation."
#else
axiomInstCoT :: (ExtendPath c Crumb, Monad m) => Translate c m CoAxiom a1 -> (Int -> Translate c m Coercion a2) -> (a1 -> [a2] -> b) -> Translate c m Coercion b
axiomInstCoT t ts f = translate $ \ c -> \case
                                            AxiomInstCo ax coes -> f <$> apply t (c @@ AxiomInstCo_Axiom) ax <*> sequence [ apply (ts n) (c @@ AxiomInstCo_Arg n) co | (co,n) <- zip coes [0..] ]
                                            _                   -> fail "not a coercion axiom instantiation."
#endif
{-# INLINE axiomInstCoT #-}

-- | Rewrite all children of a coercion of the form: @AxiomInstCo@ 'CoAxiom' ['Coercion']
#if __GLASGOW_HASKELL__ > 706
axiomInstCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m (CoAxiom Branched) -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
#else
axiomInstCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m CoAxiom -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
#endif
axiomInstCoAllR r rs = axiomInstCoT r rs AxiomInstCo
{-# INLINE axiomInstCoAllR #-}

-- | Rewrite any children of a coercion of the form: @AxiomInstCo@ 'CoAxiom' ['Coercion']
#if __GLASGOW_HASKELL__ > 706
axiomInstCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m (CoAxiom Branched) -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
#else
axiomInstCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m CoAxiom -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
#endif
axiomInstCoAnyR r rs = unwrapAnyR $ axiomInstCoAllR (wrapAnyR r) (wrapAnyR . rs)
{-# INLINE axiomInstCoAnyR #-}

-- | Rewrite one child of a coercion of the form: @AxiomInstCo@ 'CoAxiom' ['Coercion']
#if __GLASGOW_HASKELL__ > 706
axiomInstCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m (CoAxiom Branched) -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
#else
axiomInstCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m CoAxiom -> (Int -> Rewrite c m Coercion) -> Rewrite c m Coercion
#endif
axiomInstCoOneR r rs = unwrapOneR $ axiomInstCoAllR (wrapOneR r) (wrapOneR . rs)
{-# INLINE axiomInstCoOneR #-}

-- | Translate a coercion of the form: @UnsafeCo@ 'Type' 'Type'
unsafeCoT :: (ExtendPath c Crumb, Monad m) => Translate c m Type a1 -> Translate c m Type a2 -> (a1 -> a2 -> b) -> Translate c m Coercion b
unsafeCoT t1 t2 f = translate $ \ c -> \case
                                          UnsafeCo ty1 ty2 -> f <$> apply t1 (c @@ UnsafeCo_Left) ty1 <*> apply t2 (c @@ UnsafeCo_Right) ty2
                                          _                -> fail "not an unsafe coercion."
{-# INLINE unsafeCoT #-}

-- | Rewrite all children of a coercion of the form: @UnsafeCo@ 'Type' 'Type'
unsafeCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Coercion
unsafeCoAllR r1 r2 = unsafeCoT r1 r2 UnsafeCo
{-# INLINE unsafeCoAllR #-}

-- | Rewrite any children of a coercion of the form: @UnsafeCo@ 'Type' 'Type'
unsafeCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Coercion
unsafeCoAnyR r1 r2 = unwrapAnyR $ unsafeCoAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE unsafeCoAnyR #-}

-- | Rewrite one child of a coercion of the form: @UnsafeCo@ 'Type' 'Type'
unsafeCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Type -> Rewrite c m Type -> Rewrite c m Coercion
unsafeCoOneR r1 r2 = unwrapOneR $ unsafeCoAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE unsafeCoOneR #-}


-- | Translate a coercion of the form: @SymCo@ 'Coercion'
symCoT :: (ExtendPath c Crumb, Monad m) => Translate c m Coercion b -> Translate c m Coercion b
symCoT t = translate $ \ c -> \case
                                   SymCo co -> apply t (c @@ SymCo_Co) co
                                   _        -> fail "not a symmetric coercion."
{-# INLINE symCoT #-}

-- | Rewrite the 'Coercion' child of a coercion of the form: @SymCo@ 'Coercion'
symCoR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Coercion -> Rewrite c m Coercion
symCoR r = symCoT (SymCo <$> r)
{-# INLINE symCoR #-}


-- | Translate a coercion of the form: @TransCo@ 'Coercion' 'Coercion'
transCoT :: (ExtendPath c Crumb, Monad m) => Translate c m Coercion a1 -> Translate c m Coercion a2 -> (a1 -> a2 -> b) -> Translate c m Coercion b
transCoT t1 t2 f = translate $ \ c -> \case
                                          TransCo co1 co2 -> f <$> apply t1 (c @@ TransCo_Left) co1 <*> apply t2 (c @@ TransCo_Right) co2
                                          _               -> fail "not a transitive coercion."
{-# INLINE transCoT #-}

-- | Rewrite all children of a coercion of the form: @TransCo@ 'Coercion' 'Coercion'
transCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Coercion -> Rewrite c m Coercion -> Rewrite c m Coercion
transCoAllR r1 r2 = transCoT r1 r2 TransCo
{-# INLINE transCoAllR #-}

-- | Rewrite any children of a coercion of the form: @TransCo@ 'Coercion' 'Coercion'
transCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Coercion -> Rewrite c m Coercion -> Rewrite c m Coercion
transCoAnyR r1 r2 = unwrapAnyR $ transCoAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE transCoAnyR #-}

-- | Rewrite one child of a coercion of the form: @TransCo@ 'Coercion' 'Coercion'
transCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Coercion -> Rewrite c m Coercion -> Rewrite c m Coercion
transCoOneR r1 r2 = unwrapOneR $ transCoAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE transCoOneR #-}


-- | Translate a coercion of the form: @NthCo@ 'Int' 'Coercion'
nthCoT :: (ExtendPath c Crumb, Monad m) => Translate c m Int a1 -> Translate c m Coercion a2 -> (a1 -> a2 -> b) -> Translate c m Coercion b
nthCoT t1 t2 f = translate $ \ c -> \case
                                          NthCo n co -> f <$> apply t1 (c @@ NthCo_Int) n <*> apply t2 (c @@ NthCo_Co) co
                                          _          -> fail "not an Nth coercion."
{-# INLINE nthCoT #-}

-- | Rewrite all children of a coercion of the form: @NthCo@ 'Int' 'Coercion'
nthCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Int -> Rewrite c m Coercion -> Rewrite c m Coercion
nthCoAllR r1 r2 = nthCoT r1 r2 NthCo
{-# INLINE nthCoAllR #-}

-- | Rewrite any children of a coercion of the form: @NthCo@ 'Int' 'Coercion'
nthCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Int -> Rewrite c m Coercion -> Rewrite c m Coercion
nthCoAnyR r1 r2 = unwrapAnyR $ nthCoAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE nthCoAnyR #-}

-- | Rewrite one child of a coercion of the form: @NthCo@ 'Int' 'Coercion'
nthCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Int -> Rewrite c m Coercion -> Rewrite c m Coercion
nthCoOneR r1 r2 = unwrapOneR $ nthCoAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE nthCoOneR #-}


-- | Translate a coercion of the form: @InstCo@ 'Coercion' 'Type'
instCoT :: (ExtendPath c Crumb, Monad m) => Translate c m Coercion a1 -> Translate c m Type a2 -> (a1 -> a2 -> b) -> Translate c m Coercion b
instCoT t1 t2 f = translate $ \ c -> \case
                                          InstCo co ty -> f <$> apply t1 (c @@ InstCo_Co) co <*> apply t2 (c @@ InstCo_Type) ty
                                          _            -> fail "not a coercion instantiation."
{-# INLINE instCoT #-}

-- | Rewrite all children of a coercion of the form: @InstCo@ 'Coercion' 'Type'
instCoAllR :: (ExtendPath c Crumb, Monad m) => Rewrite c m Coercion -> Rewrite c m Type -> Rewrite c m Coercion
instCoAllR r1 r2 = instCoT r1 r2 InstCo
{-# INLINE instCoAllR #-}

-- | Rewrite any children of a coercion of the form: @InstCo@ 'Coercion' 'Type'
instCoAnyR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Coercion -> Rewrite c m Type -> Rewrite c m Coercion
instCoAnyR r1 r2 = unwrapAnyR $ instCoAllR (wrapAnyR r1) (wrapAnyR r2)
{-# INLINE instCoAnyR #-}

-- | Rewrite one child of a coercion of the form: @InstCo@ 'Coercion' 'Type'
instCoOneR :: (ExtendPath c Crumb, MonadCatch m) => Rewrite c m Coercion -> Rewrite c m Type -> Rewrite c m Coercion
instCoOneR r1 r2 = unwrapOneR $ instCoAllR (wrapOneR r1) (wrapOneR r2)
{-# INLINE instCoOneR #-}

---------------------------------------------------------------------
---------------------------------------------------------------------

-- | Earlier versions of HERMIT used 'Int' as the crumb type.
--   This translation maps an 'Int' to the corresponding 'Crumb', for backwards compatibility purposes.
deprecatedIntToCrumbT :: Monad m => Int -> Translate c m Core Crumb
deprecatedIntToCrumbT n = contextfreeT $ \case
                                            GutsCore _                 | n == 0                        -> return ModGuts_Prog
                                            AltCore _                  | n == 0                        -> return Alt_RHS
                                            DefCore _                  | n == 0                        -> return Def_RHS
                                            ProgCore (ProgCons _ _)    | n == 0                        -> return ProgCons_Head
                                                                       | n == 1                        -> return ProgCons_Tail
                                            BindCore (NonRec _ _)      | n == 0                        -> return NonRec_RHS
                                            BindCore (Rec bds)         | (n >= 0) && (n < length bds)  -> return (Rec_Def n)
                                            ExprCore (App _ _)         | n == 0                        -> return App_Fun
                                                                       | n == 1                        -> return App_Arg
                                            ExprCore (Lam _ _)         | n == 0                        -> return Lam_Body
                                            ExprCore (Let _ _)         | n == 0                        -> return Let_Bind
                                                                       | n == 1                        -> return Let_Body
                                            ExprCore (Case _ _ _ alts) | n == 0                        -> return Case_Scrutinee
                                                                       | (n > 0) && (n <= length alts) -> return (Case_Alt (n-1))
                                            ExprCore (Cast _ _)        | n == 0                        -> return Cast_Expr
                                            ExprCore (Tick _ _)        | n == 0                        -> return Tick_Expr
                                            _                                                          -> fail ("Child " ++ show n ++ " does not exist.")
{-# INLINE deprecatedIntToCrumbT #-}

-- | Builds a path to the first child, based on the old numbering system.
deprecatedIntToPathT :: Monad m => Int -> Translate c m Core PathH
deprecatedIntToPathT =  liftM return . deprecatedIntToCrumbT
{-# INLINE deprecatedIntToPathT #-}

---------------------------------------------------------------------
---------------------------------------------------------------------
