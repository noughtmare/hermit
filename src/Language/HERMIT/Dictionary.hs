{-# LANGUAGE ExistentialQuantification, DeriveDataTypeable, TypeFamilies, RankNTypes, GADTs #-}
-- The main namespace. Things tend to be untyped, because the API is accessed via (untyped) names.

module Language.HERMIT.Dictionary where

import GhcPlugins
import qualified Data.Map as Map
import Data.Map(Map)
import Data.Char
import Data.Monoid
import Data.Typeable
import Data.Dynamic
import qualified Language.Haskell.TH as TH

import Language.KURE

import Language.HERMIT.HermitKure
import qualified Language.HERMIT.Expr as Expr
import Language.HERMIT.Kernel
import Language.HERMIT.External

import qualified Language.HERMIT.Primitive.Case as Case
import qualified Language.HERMIT.Primitive.New as New
import qualified Language.HERMIT.Primitive.Inline as Inline
import qualified Language.HERMIT.Primitive.Consider as Consider
import qualified Language.HERMIT.Primitive.Local as Local

all_externals :: External
all_externals = mconcat $
        -- values defined elsewhere
        [ New.externals
        , Case.externals
        , Inline.externals
        , Consider.externals
        , Local.externals
        ] ++
        -- locally defined values
        [ external "allbu"   (allbuR :: RewriteH Core -> RewriteH Core)
            [ "promotes a rewrite to operate over an entire tree in bottom-up order, requiring success at each node"
            ]
        , external "alltd"    (alltdR :: RewriteH Core -> RewriteH Core)
            [ "promotes a rewrite to operate over an entire tree in top-down order, requiring success at each node"
            ]
        , external "anybu"   (anybuR :: RewriteH Core -> RewriteH Core)
            [ "promotes a rewrite to operate over an entire tree in bottom-up order, requiring success at at least one node"
            ]
        , external "anytd"    (anytdR :: RewriteH Core -> RewriteH Core)
            [ "promotes a rewrite to operate over an entire tree in top-down order, requiring success at at least one node"
            ]
        , external "try"        (tryR :: RewriteH Core -> RewriteH Core)
            [ "tries a rewrite, and performs an identity if this rewrite fails"
            ]
        , external "exit"       Exit
            [ "exits HERMIT"
            ]
        , external "pop"        PopFocus
            [ "pops one lens"
            ]
        , external "."          PopFocus
            [ "pops one lens"
            ]
        , external "superpop"   SuperPopFocus
            [ "pops all lenses"
            ]
        , external "help"       Help
            [ "lists commands"
            ]
        ]

dictionary :: Map String Dynamic
dictionary = toDictionary all_externals

help :: [String]
help = concat $ map snd $ Map.toList $ toHelp all_externals

------------------------------------------------------------------------------------

data KernelCommandBox = KernelCommandBox KernelCommand
        deriving (Typeable)

instance Extern KernelCommand where
    type Box KernelCommand = KernelCommandBox
    box i = KernelCommandBox i
    unbox (KernelCommandBox i) = i

------------------------------------------------------------------------------------

data Help = Help
        deriving (Typeable)

instance Extern Help where
    type Box Help = Help
    box i = i
    unbox i = i

------------------------------------------------------------------------------------
-- The union of all possible results from a "well-typed" commands, from this dictionary.

interpExpr :: Expr.Expr -> Either String KernelCommand
interpExpr expr =
        case interpExpr' expr of
          Left msg -> Left msg
          Right dyn -> runInterp dyn
             [ Interp $ \ (KernelCommandBox cmd)      -> Right $ cmd
             , Interp $ \ (RewriteCoreBox rr)         -> Right $ Apply rr
             , Interp $ \ (TranslateCoreStringBox tt) -> Right $ Query tt
             , Interp $ \ (LensCoreCoreBox lens)      -> Right $ PushFocus lens
             , Interp $ \ (IntBox i)                  -> Right $ PushFocus $ chooseL i
             , Interp $ \ Help                        -> Left $ unlines $ help
             ]
             (Left "interpExpr: bad type of expression")

data Interp :: * -> * where
   Interp :: (Typeable a) => (a -> b) -> Interp b

runInterp :: Dynamic -> [Interp b] -> b -> b
runInterp dyn []                bad = bad
runInterp dyn (Interp f : rest) bad = case fromDynamic dyn of
   Just v -> f v
   Nothing -> runInterp dyn rest bad

--------------------------------------------------------------------------

interpExpr' :: Expr.Expr -> Either String Dynamic -- (Either PartialCommand Command)
interpExpr' (Expr.Lit str)
        = Right $ toDyn $ NameBox $ TH.mkName str
interpExpr' (Expr.Var str)
        | all isDigit str
        = Right $ toDyn $ IntBox $ (read str)
interpExpr' (Expr.Var str)
        | Just dyn <- Map.lookup str dictionary
        = Right $ dyn
        | otherwise
        = Left $ "can not find : " ++ show str
interpExpr' (Expr.App e1 e2) = do
        r1 <- interpExpr' e1
        r2 <- interpExpr' e2
        case dynApply r1 r2 of
           Nothing -> Left "apply failed"
           Just res -> return res

--------------------------------------------------------------



