module JCU.Prolog where

import            Data.List (permutations)
import            Data.Tree (Tree(..))
import            JCU.Types

lookUp :: Term -> Env -> Term
lookUp (Var x)  e   = case lookup x e of
                        Nothing   -> Var x
                        Just res  -> lookUp res e
lookUp t        _   = t

unify :: (Term, Term) -> Maybe Env -> Maybe Env
unify _       Nothing       = Nothing
unify (t, u)  env@(Just e)  = uni (lookUp t e) (lookUp u e)
  where  uni (Var x) y        = Just ((x, y): e)
         uni x (Var y)        = Just ((y, x): e)
         uni (Con x) (Con y)  = if x == y then env else Nothing
         uni (Fun x xs) (Fun y ys)
           | x == y && length xs == length ys  = foldr unify env (zip xs ys)
           | otherwise                         = Nothing
         uni _ _              =  Nothing

solve :: [Rule] -> Env -> Int -> [Term] -> [Env]
solve _     e _  []      = [e]
solve rules e n  (t:ts)  =
  [  sol
  |  (c :<-: cs)  <- map (tag n) rules
  ,  Just r       <- [unify (t, c) (Just e)]
  ,  sol          <- solve rules r (n+1) (cs ++ ts)
  ]

{-
 pa(alex,ama).
----------------
ouder(alex,ama).
-}

{-
                         pa(alex,ama). (6)
                         -------------
ma(bea,alex). (4)     ouder(alex,ama). (5)
-------------         ----------------
ouder(bea,alex), (2)  voor(alex,ama). (3)
-------------------------------------
         voor(bea,ama). (1)
-}

-- TODO Client-side:
-- A rule from the list can be dragged onto a textfield which already has
-- content. Then application then checks whether the dragged rule and the
-- text in the textfield can be unified. If so, n child text fields appear,
-- where n is the number of terms in the right-hand side of the rule.
-- If a fact is unified this way, it will spawn one text field, containing
-- the fact.

testSimpleRight :: PCheck
testSimpleRight  =  checkProof testStoredRules
                 $  Node (Fun "pa" [cnst "alex",  cnst "ama"]) []

testSimpleWrong :: PCheck
testSimpleWrong = checkProof testStoredRules $ Node (Fun "ma" [cnst "alex",  cnst "ama"]) []

testRight :: PCheck
testRight = checkProof testStoredRules voorBeaAmaProof
testWrong :: PCheck
testWrong = checkProof testStoredRules voorBeaAmaWrong

rhss :: Env -> [Rule] -> Term -> [([Term], Env)]
rhss env rls tm = [(cs, env')  |  (c :<-: cs)  <- rls
                               ,  Just env'    <- [unify (tm, c) (Just env)]]

check :: Env -> Int -> [Rule] -> Proof -> PCheck
check env n rls (Node tm []) = Node ((not . null) $ rhss env (tag n rls) tm) []
check env n rls (Node tm cs) = Node success nwChlds
  where  -- All possible right-hand sides of `tm`. Each of the child nodes
         -- _must_ unify with at least one of the right-hand side nodes.
         rhsss :: [([Term], Env)]
         rhsss = rhss env (tag n rls) tm

         success :: Bool
         success = (not . null) rhsss && (not . null) (concat matches)
           where  matches :: [Env]
                  matches = [m  |  (tms, env')  <- rhsss
                                ,  Just m       <- [match tms env']]

         nwChlds :: [PCheck]
         nwChlds | success    = map (check env (n+1) rls) cs -- TODO: Env to env'
                 | otherwise  = map (fmap (const False)) cs

         match :: [Term] -> Env -> Maybe Env
         match ts env' | null match'  = Nothing
                       | otherwise    = Just (head match')
           where match'  = [env''  |  perm        <- permutations (map rootLabel cs)
                                   ,  Just env''  <- [foldr unify (Just env') (zip perm ts)] ]

checkProof :: [Rule] -> Proof -> PCheck
checkProof = check [] 0

voorBeaAmaProof :: Proof
voorBeaAmaProof = Node (Fun "voor" [cnst "bea",  cnst "ama"])
                    [  Node (Fun "ouder" [cnst "bea",  cnst "alex"])
                         [  Node (Fun "ma" [cnst "bea",  cnst "alex"]) []
                         ,  Node (Fun "ouder" [cnst "alex", cnst "ama"])
                              [ Node (Fun "pa" [cnst "alex", cnst "ama"]) []]
                         ] 
                    ,  Node (Fun "voor"  [cnst "alex", cnst "ama"]) [] ]

voorBeaAmaWrong :: Proof
voorBeaAmaWrong = Node (Fun "voor" [cnst "bea",  cnst "ama"])
                    [ Node (Fun "ouder" [cnst "bea",  cnst "alex"])
                        [ Node (Fun "ma" [cnst "bea",  cnst "alex"]) []
                        , Node (Fun "fout!" [cnst "alex", cnst "ama"])
                            [ Node (Fun "pa" [cnst "alex", cnst "ama"]) []]
                        ]
                    , Node (Fun "voor"  [cnst "alex", cnst "ama"]) [] ]

cnst ::  Ident -> Term
cnst s = Fun s []

testStoredRules :: [Rule]
testStoredRules =  [ Fun "ma"    [cnst "mien", cnst "juul"] :<-: []
                   , Fun "ma"    [cnst "juul", cnst "bea"]  :<-: []
                   , Fun "ma"    [cnst "bea" , cnst "alex"] :<-: []
                   , Fun "ma"    [cnst "bea" , cnst "cons"] :<-: []
                   , Fun "ma"    [cnst "max" , cnst "ale"]  :<-: []
                   , Fun "ma"    [cnst "max" , cnst "ama"]  :<-: []
                   , Fun "ma"    [cnst "max" , cnst "ari"]  :<-: []
                   , Fun "oma"   [Var  "X"   ,  Var "Z"]    :<-: [ Fun "ma"    [Var "X", Var "Y"]
                                                                 , Fun "ouder" [Var "Y", Var "Z"] ]
                   , Fun "pa"    [cnst "alex", cnst "ale"]  :<-: []
                   , Fun "pa"    [cnst "alex", cnst "ama"]  :<-: []
                   , Fun "pa"    [cnst "alex", cnst "ari"]  :<-: []
                   , Fun "ouder" [Var "X",    Var "Y"]    :<-: [ Fun "pa"    [Var "X", Var "Y"] ]
                   , Fun "ouder" [Var "X",    Var "Y"]    :<-: [ Fun "ma"    [Var "X", Var "Y"] ]
                   , Fun "voor"  [Var "X",    Var "Y"]    :<-: [ Fun "ouder" [Var "X", Var "Y"] ]
                   , Fun "voor"  [Var "X",    Var "Y"]    :<-: [ Fun "ouder" [Var "X", Var "Z"]
                                                               , Fun "voor"  [Var "Z", Var "Y"] ] ]

testInUseRules :: [Rule]
testInUseRules = [ Fun "voor"  [cnst "bea",    cnst "ama"] :<-: []
                 , Fun "" []   :<-: [ Fun "pa" [Var "X", Var "Y"] ]
                 , Fun "pa"    [Var "X"    , cnst "ama"] :<-: []
                 , Fun "pa"    [cnst "alex", cnst "ama"] :<-: []
                 ]
