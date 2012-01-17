{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleContexts #-}


module Application where

import            Control.Applicative
import            Control.Exception (SomeException)
import            Control.Monad
import            Control.Monad.CatchIO hiding (Handler)
import            Control.Monad.Reader
import            Control.Monad.State
import            Data.Aeson as AE
import            Data.ByteString.Char8 (ByteString)
import qualified  Data.ByteString.Char8 as BS
import            Data.Lens.Template
import            Data.ListLike (CharString(..))
import            Data.Map (Map)
import qualified  Data.Map as DM
import            Data.Maybe
import            Data.Pool
import            Data.String
import            Data.Text (Text)
import qualified  Data.Text as DT
import qualified  Data.Text.Encoding as DT
import qualified  Database.HDBC as HDBC
import            Database.HDBC.PostgreSQL
import            JCU.Prolog
import            JCU.Templates
import            JCU.Types
import            Language.Prolog.NanoProlog.NanoProlog
import            Language.Prolog.NanoProlog.Parser
import            Prelude hiding (catch)
import            Snap.Core
import            Snap.Snaplet
import            Snap.Snaplet.Auth
import            Snap.Snaplet.Auth.Backends.Hdbc
import            Snap.Snaplet.Hdbc
import            Snap.Snaplet.Session
import            Snap.Snaplet.Session.Backends.CookieSession
import            Snap.Util.FileServe
import            Text.Blaze
import qualified  Text.Blaze.Html5 as H
import            Text.Blaze.Renderer.Utf8 (renderHtml)
import            Text.Digestive
import            Text.Digestive.Blaze.Html5
import            Text.Digestive.Forms.Snap
import qualified  Text.Email.Validate as E

data App = App
  {  _authLens  :: Snaplet (AuthManager App)
  ,  _sessLens  :: Snaplet SessionManager
  ,  _dbLens    :: Snaplet (HdbcSnaplet Connection Pool)
  }

makeLens ''App

type AppHandler = Handler App App

instance HasHdbc (Handler b App) Connection Pool where
  getHdbcState = with dbLens get

jcu :: SnapletInit App App
jcu = makeSnaplet "jcu" "Prolog proof tree practice application" Nothing $ do
  addRoutes  [  ("/", ifTop siteIndexH)
             ,  ("/forbidden",  forbiddenH)
             ,  ("/login",   loginH)
             ,  ("/logout",  logoutH)
             ,  ("/signup",  signupH)
             ,  ("/rules/stored",  method GET   readStoredRulesH)
             ,  ("/rules/stored",  method POST  addStoredRuleH)
             ,  ("/rules/stored/:id",  method DELETE  deleteStoredRuleH)
             ,  ("/proof/check",   method POST  checkProofH)
             ,  ("/rules/unify",   method POST  unifyH)
             ,  ("/load-example",  method GET loadExampleH)
             ,  ("/check-syntax/:type",  method POST checkSyntaxH)
             ,  ("/subst/:sub/:for",     method POST substH)
             ,  ("", serveDirectory "resources/static")
             ]
  _sesslens'  <- nestSnaplet "session" sessLens $ initCookieSessionManager
                   "config/site_key.txt" "_session" Nothing
  let pgsql = connectPostgreSQL' =<< readFile "config/connection_string.conf"
  pool <- liftIO $ createPool pgsql HDBC.disconnect 1 500 1
  _dblens'    <- nestSnaplet "hdbc" dbLens $ hdbcInit pool
  _authlens'  <- nestSnaplet "auth" authLens $ initHdbcAuthManager
                   defAuthSettings sessLens pool defAuthTable defQueries
  return  $ App _authlens' _sesslens' _dblens'


------------------------------------------------------------------------------
-- | Handlers

restrict :: AppHandler b -> AppHandler b -> AppHandler b
restrict failH succH = do
  with sessLens touchSession
  authed <- with authLens isLoggedIn
  if authed
    then succH
    else failH

loginRedir :: AppHandler ()
loginRedir = redirect "/login"

forbiddenH :: AppHandler a
forbiddenH = do
  modifyResponse $ setResponseStatus 403 "Forbidden"
  writeBS "403 forbidden"
  finishWith =<< getResponse

siteIndexH :: AppHandler ()
siteIndexH = ifTop $ restrict loginRedir (blaze $ template index)

loginH :: AppHandler ()
loginH = withSession sessLens $ do
  loggedIn <- with authLens isLoggedIn
  when loggedIn $ redirect "/"
  res <- eitherSnapForm loginForm "login-form"
  case res of
    Left form' -> do
      didFail <- with sessLens $ do
        failed <- getFromSession "login-failed"
        deleteFromSession "login-failed"
        commitSession
        return failed
      blaze $ template $ loginHTML (isJust didFail) form'
    Right (FormUser e p r) -> do
      loginRes <- with authLens $
                    loginByUsername  (DT.encodeUtf8 e)
                                     (ClearText $ DT.encodeUtf8 p) r
      case loginRes of
        Left _   ->  do  with sessLens $ do
                           setInSession "login-failed" "1"
                           commitSession
                         redirect "/login"
        Right _  ->  redirect "/"

-- TODO: Also send an email after registration
signupH :: AppHandler ()
signupH = do
  loggedIn <- with authLens isLoggedIn
  when loggedIn $ redirect "/"
  res <- eitherSnapForm registrationForm "registration-form"
  case res of
    Left form' -> do
      exists <- with sessLens $ do
        failed <- getFromSession "username-exists"
        deleteFromSession "username-exists"
        commitSession
        return failed
      blaze $ template (signupHTML (isJust exists) form')
    Right (FormUser e p _) -> do
      _ <- with authLens (createUser e (DT.encodeUtf8 p)) `catch` hndlExcptn
      redirect "/"
  where  hndlExcptn :: SomeException -> AppHandler AuthUser
         hndlExcptn _ = do
           with sessLens $ do
             setInSession "username-exists" "1"
             commitSession
           redirect "/signup"

logoutH :: AppHandler ()
logoutH = do
  with authLens logout
  redirect "/"

readStoredRulesH :: AppHandler ()
readStoredRulesH = restrict forbiddenH $ do
  rules <- getStoredRules =<< getUserId
  modifyResponse $ setContentType "application/json"
  writeLBS $ encode rules

deleteStoredRuleH :: AppHandler ()
deleteStoredRuleH = restrict forbiddenH $ do
  mrid <- getParam "id"
  case mrid of
    Nothing  -> return ()
    Just x   -> do
      uid <- getUserId
      deleteRule uid x

addStoredRuleH :: AppHandler ()
addStoredRuleH = restrict forbiddenH $ do
  rqrl <- readRequestBody 4096
  case mkRule rqrl of
    Left   err  -> error500H err
    Right  rl   -> do
      uid  <- getUserId
      insRes <- insertRule uid rl
      case insRes of
        (Just newID) -> do modifyResponse $ setContentType "application/json"
                           writeLBS $ encode (AddRes newID)
        Nothing      -> error500H undefined

loadExampleH :: AppHandler ()
loadExampleH = restrict forbiddenH $ do
  uid <- getUserId
  deleteUserRules uid
  mapM_ (insertRule uid) exampleData
  redirect "/"

getUserId :: AppHandler UserId
getUserId = do
  cau <- with authLens currentUser
  case cau >>= userId of
    Nothing  -> redirect "/"
    Just x   -> return x

-- | Check the proof from the client. Since the checking could potentially
-- shoot into an inifinite recursion, a timeout is in place.
checkProofH :: AppHandler ()
checkProofH = restrict forbiddenH $ do
  setTimeout 15
  body <- readRequestBody 4096
  case mkProof body of
    Left   err    -> error500H err
    Right  proof  -> do
      rules <- getStoredRules =<< getUserId
      writeLBS $ encode (checkProof (map rule rules) proof)

unifyH :: AppHandler ()
unifyH = restrict forbiddenH $ do
  setTimeout 10
  body <- readRequestBody 4096
  case mkDropReq body of
    Left   err                   -> error500H err
    Right  (DropReq prf lvl rl)  -> writeLBS $ encode (dropUnify prf lvl rl)

error500H :: ByteString -> AppHandler a
error500H msg = do
  modifyResponse $ setResponseStatus 500 "Internal server error"
  writeBS $ BS.append (fromString "500 internal server error: ") msg
  finishWith =<< getResponse

checkSyntaxH :: AppHandler ()
checkSyntaxH = restrict forbiddenH $ do
  ptype  <- getParam "type"
  body   <- readRequestBody 4096
  writeLBS $ encode (parseCheck ptype body)

substH :: AppHandler ()
substH = restrict forbiddenH $ do
  body  <- readRequestBody 4096
  sub   <- getParam "sub"
  for   <- getParam "for"
  case mkProof body of
    Left   err    -> error500H err
    Right  proof  ->
      case (sub, for) of
        (Just sub', Just for')  ->
          let  env = Env $ DM.fromList [(BS.unpack for', Var $ BS.unpack sub')]
          in   writeLBS $ encode (subst env proof)
        _                       -> writeLBS $ encode proof


-------------------------------------------------------------------------------
-- View rendering

blaze :: Reader AuthState Html -> AppHandler ()
blaze htmlRdr = do
  modifyResponse $ addHeader "Content-Type" "text/html; charset=UTF-8"
  li   <- with authLens isLoggedIn
  eml  <- with authLens $ do
    cu <- currentUser
    return $ case cu of
      Nothing -> ""
      Just u  -> userLogin u
  let html = runReader htmlRdr (AuthState li eml)
  writeLBS $ renderHtml html

-------------------------------------------------------------------------------
-- Forms

data FormUser = FormUser
  {  email     :: Text
  ,  password  :: Text
  ,  remember  :: Bool }
  deriving Show

isEmail :: Monad m => Validator m Html Text
isEmail = check "Invalid email address" (E.isValid . DT.unpack)

longPwd :: Monad m => Validator m Html Text
longPwd  =  check "Password needs to be at least six characters long"
         $  \xs -> DT.length xs >= 6

isNonEmpty :: Monad m => Validator m Html Text
isNonEmpty = check "Field must not be empty" $ not . DT.null

identical :: Validator AppHandler Html (Text, Text)
identical = check "Field values must be identical" (uncurry (==))

loginForm :: Form AppHandler SnapInput Html BlazeFormHtml FormUser
loginForm = (\e p r _ -> FormUser e p r)
  <$>  mapViewHtml H.div (
       label  "Email address: "
       ++>    inputText Nothing `validate` isEmail
       <++    errors)
  <*>  mapViewHtml H.div (
       label  "Password: "
       ++>    inputPassword False `validate` longPwd
       <++    errors)
  <*>  mapViewHtml H.div (
       label  "Remember me?"
       ++>    inputCheckBox True)
  <*>  mapViewHtml H.div (
       submit "Login")

registrationForm :: Form AppHandler SnapInput Html BlazeFormHtml FormUser
registrationForm = (\ep pp _ -> FormUser (fst ep) (fst pp) False)
  <$>  ((,)
         <$>  mapViewHtml H.div (
              label  "Email address: "
              ++>    inputText Nothing `validate` isEmail
              <++    errors)
         <*>  mapViewHtml H.div (
              label  "Email address (confirmation): "
              ++>    inputText Nothing `validate` isEmail
              <++    errors))
       `validate`  identical
       <++         errors
  <*>  ((,)
         <$>  mapViewHtml H.div (
              label  "Password: "
              ++>    inputPassword False `validate` longPwd
              <++    errors)
         <*>  mapViewHtml H.div (
              label  "Password (confirmation): "
              ++>    inputPassword False `validate` longPwd
              <++    errors))
       `validate`  identical
       <++         errors
  <*>  mapViewHtml H.div (
       submit "Register")



-------------------------------------------------------------------------------
-- Database interaction

insertRule :: HasHdbc m c s => UserId -> Rule -> m (Maybe Int)
insertRule uid rl = let sqlVals = [toSql $ unUid uid, toSql $ show rl] in do
  query'  "INSERT INTO rules (uid, rule_order, rule) VALUES (?, 1, ?)" sqlVals
  rws <- query  "SELECT rid FROM rules WHERE uid = ? AND rule = ? ORDER BY rid DESC"
                sqlVals
  return $ case rws of
             []     -> Nothing
             (x:_)  -> Just $ fromSql $ x DM.! "rid"

deleteRule :: (Functor m, HasHdbc m c s) => UserId -> ByteString -> m ()
deleteRule uid rid = void $
  query' "DELETE FROM rules WHERE rid = ? AND uid = ?" [toSql rid, toSql uid]

getStoredRules :: HasHdbc m c s => UserId -> m [DBRule]
getStoredRules uid = do
  rws <- query "SELECT rid, rule_order, rule FROM rules WHERE uid = ?" [toSql uid]
  return $ map convRow rws
  where  convRow :: Map String HDBC.SqlValue -> DBRule
         convRow mp =
           let  rdSql k = fromSql $ mp DM.! k
           in   DBRule  (rdSql "rid")
                        (rdSql "rule_order")
                        (fst . startParse pRule $ CS (rdSql "rule"))

deleteUserRules :: (Functor m, HasHdbc m c s) => UserId -> m ()
deleteUserRules uid = void $ query' "DELETE FROM rules WHERE uid = ?" [toSql uid]
