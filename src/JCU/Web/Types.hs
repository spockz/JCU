{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings  #-}

module JCU.Web.Types where

import            Control.Applicative
import            Control.Monad
import            Data.Aeson
import            Data.ByteString (ByteString)
import            Snap.Auth (AuthUser)
import            JCU.Prolog.Types (Rule(..))
import            Text.ParserCombinators.UU.Core (parse)
import            JCU.Prolog.Parser


-- TODO: Get prolog field out of user? Though it can't hurt too much;
-- there's not a lot of data we want to store anyway.
data User = User  {  authUser     :: AuthUser
                  ,  storedRules  :: [ByteString]
                  ,  inuseRules   :: [ByteString] }

instance ToJSON Rule where
  toJSON t = let  txt = show t
             in   object  [  "rule"  .= txt
                          ,  "id"    .= txt]

data JSRule = JSRule String String
            deriving Show

instance FromJSON Rule where
  parseJSON (Object o)  = mkRule <$> o .: "id"
                                 <*> o .: "rule"
  parseJSON _           = mzero

mkRule :: ByteString -> ByteString -> Rule
mkRule _ r = a
  where (a, e) = parse pRule r

toText :: [JSRule] -> String
toText = concatMap (\(JSRule _ r) -> r ++ "\n")
