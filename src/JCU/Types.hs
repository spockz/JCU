{-# LANGUAGE OverloadedStrings #-}

module JCU.Types where

import            Data.ByteString (ByteString)
import            Data.List (intercalate)
import            Data.Tree (Tree(..))
import            Snap.Auth (AuthUser)

data User     =  User  {  authUser     :: AuthUser
                       ,  storedRules  :: [ByteString] }
              deriving Show

data Term     =  Con Int
              |  Var Ident
              |  Fun Ident [Term]
              deriving (Eq, Ord)

data Rule     =  Term :<-: [Term]
              deriving Eq

data Status   =  Correct
              |  Incomplete
              |  Invalid
              deriving Show

data DropReq  = DropReq Term Rule
              deriving Show

type Ident    = String
type Env      = [(Ident, Term)]
type Proof    = Tree Term
type PCheck   = Tree Status
type DropRes  = (Bool, Int)

instance Show Term where
  show (Con  i)      = show i
  show (Var  i)      = i
  show (Fun  i [] )  = i
  show (Fun  i ts )  = i ++ "(" ++ showCommas ts ++ ")"

instance Show Rule where
  show (t :<-: [] ) = show t ++ "."
  show (t :<-: ts ) = show t ++ ":-" ++ showCommas ts ++ "."

showCommas :: Show a => [a] -> String
showCommas l = intercalate ", " (map show l)

class Taggable a where
  tag :: Int -> a -> a

instance Taggable Term where
  tag _  con@(Con _)  = con
  tag n  (Var  x)     = Var  (x ++ show n)
  tag n  (Fun  x xs)  = Fun  x (tag n xs)

instance Taggable Rule where
  tag n (c :<-: cs) = tag n c :<-: tag n cs

instance Taggable a => Taggable [a] where
  tag n = map (tag n)