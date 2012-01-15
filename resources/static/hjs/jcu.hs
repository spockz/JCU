{-# LANGUAGE EmptyDataDecls #-}
module JCU where

import Control.Monad (liftM, foldM)

import Data.List
import Data.Tree as T



import Language.UHC.JScript.Types -- (JS, toJS, fromJS, FromJS)
import Language.UHC.JScript.Primitives
import Language.UHC.JScript.JQuery.JQuery
import Language.UHC.JScript.W3C.HTML5 as HTML5

import Language.UHC.JScript.ECMA.Bool
import Language.UHC.JScript.ECMA.String as JSString


import Language.UHC.JScript.Assorted (alert , _alert)

import Language.UHC.JScript.JQuery.Ajax as Ajax
import qualified Language.UHC.JScript.JQuery.AjaxQueue as AQ
import Language.UHC.JScript.JQuery.Draggable
import Language.UHC.JScript.JQuery.Droppable

import Language.Prolog.NanoProlog.NanoProlog
import Language.Prolog.NanoProlog.ParserUUTC

----
--  App
----

import Prolog

-- import Language.UHC.JScript.ECMA.Array

import Array

import Templates
import Models

foreign import jscript "typeof(%1)"
  typeof :: a -> JSString

-- | Would like fun dep here
class FromJS a b => FromJSPlus a b where
  jsType :: a -> b -> String
  check :: a -> b -> Bool
  check a b = jsType a b == fromJS (typeof a)
  fromJSP :: a -> Maybe b
  fromJSP a = let (v::b) = fromJS a
               in if check a v then
                    Just v
                  else
                    Nothing


ajaxQ :: (JS r, JS v) => AjaxRequestType -> String -> v -> AjaxCallback r -> AjaxCallback r -> IO ()
ajaxQ rt url vals onSuccess onFail = do
  AQ.ajaxQ "jcu_app"
           (AjaxOptions { ao_url         = url,
                          ao_requestType = rt,
                          ao_contentType = "application/json",
                          ao_dataType    = "json"
                        })
           vals
           onSuccess
           onFail

registerEvents :: [(String, JEventType, EventHandler)] -> IO ()
registerEvents = mapM_ (\ (e, event, eh) -> do elem <- jQuery e
                                               jeh  <- mkJEventHandler eh
                                               bind elem
                                                    event 
                                                    jeh)

main :: IO ()
main = do init <- ioWrap initialize
          onDocumentReady init

initialize :: IO ()
initialize = do -- Rendering
                bd <- jQuery "#bd"
                setHTML bd Templates.home
                wrapInner bd "<div id=\"home-view\"/>"
                -- Proof tree
                
                -- Rules list
                obj <- mkAnonObj
                ajaxQ GET "/rules/stored" obj addRules noop
                
                addRuleTree
                
                registerEvents $ [("#btnCheck"  , "click"   , noevent)
                                 ,("#btnAddRule", "click"   , addRuleEvent)
                                 ,("#btnReset"  , "click"   , noevent)
                                 ,("#txtAddRule", "keypress", noevent)
                                 ,("#txtAddRule", "blur"    , noevent)
                                 ,("#btnSubst"  , "click"   , noevent)
                                 ]
  where noop :: AjaxCallback (JSPtr a)
        noop = (\x y z -> return ())
        noevent :: EventHandler
        noevent x = return False

addRuleTree :: IO ()
addRuleTree = do
  ruleTreeDiv <- jQuery "#proof-tree-div"
  ruleTreeUL  <- buildRuleUl $ T.Node (Var "") []
  append ruleTreeDiv ruleTreeUL
  
buildRuleUl :: Proof -> IO JQuery
buildRuleUl node =
  do topUL <- jQuery "<ul id=\"proof-tree-view\" class=\"tree\"/>"
     restUL <- build' node node False
     append topUL restUL
     return topUL
  where
    f :: Proof -> JQuery -> Proof -> IO JQuery
    f wp jq node = do li' <- build' wp node True
                      append jq li'
                      return jq
    dropje :: Proof -> Proof -> UIThisEventHandler
    dropje wp node this _ _  = do
      elemVal <- findSelector this "input[type='text']:first" >>= valString

      if length elemVal == 0 then
          alert "There needs to be a term in the text field!" 
        else
          if not $ hasValidTermSyntax (fromJS elemVal) then
              alert "You cannot possibly think I could unify this invalid term!"
            else
              case tryParseRule "" of
                Nothing  -> alert "This should not happen. Dropping an invalid rule here."
                (Just t) -> case dropUnify wp [] t of
                              (DropRes False _) -> alert "I could not unify this."
                              (DropRes True  p) -> do
                                oldUL <- jQuery "ul#proof-tree-view.tree"
                                newUL <- buildRuleUl p
                                replaceWith oldUL newUL
      
      return True

    
    build' :: Proof -> Proof -> Bool -> IO JQuery
    build' wp n@(T.Node term childTerms) disabled =
      do li <- jQuery "<li/>"
         appendString li  $ proof_tree_item (show term) "" disabled

         dropzones <- findSelector li ".dropzone"
         
         drop'   <- mkJUIThisEventHandler (dropje wp n) 
         drop''  <- wrappedJQueryUIEvent drop'
         droppable dropzones $ Droppable (toJS "dropHover") drop''
         
         
         startUl <- jQuery "<ul/>"
         res <- foldM (f wp) startUl childTerms
         append li res
         return li


addRules :: AjaxCallback (JSArray JSRule)
addRules obj str obj2 = do
  -- slet rules  = (Data.List.map fromJS . elems . jsArrayToArray) obj
  f <- mkEachIterator (\idx e -> do
    rule' <- jsRule2Rule e
    let rt = rules_list_item ((fromJS . rule) rule')
    rules_list_div <- jQuery "#rules-list-div"
    rules_list_ul  <- jQuery "<ul id=\"rules-list-view\"/>"
    append rules_list_div rules_list_ul
    appendString rules_list_ul ("<li>" ++ rt ++ "</li>")    
    return ())
  each' obj f
  
  onStart <- mkJUIEventHandler (\x y -> do focus <- jQuery ":focus"
                                           doBlur focus
                                           return False)
  
  draggables <- jQuery ".draggable"
  draggable draggables $ Draggable (toJS True) (toJS "document") (toJS True) 100 50 onStart
  
  return ()

--   
-- instance JS () where
  
addRuleEvent :: EventHandler
addRuleEvent event = do
  rule  <- jQuery "#txtAddRule" >>= valString
  alert (fromJS rule)
  let str = JSString.concat (toJS "{\"rule\":\"") $ JSString.concat rule (toJS "\"}")
  ajaxQ POST "/rules/stored" str (onSuccess (fromJS rule)) onFail
  return True
  where onSuccess :: String -> AjaxCallback JSString
        onSuccess r _ _ _ = do ul <- jQuery "ul#rules-list-view"
                               appendString ul $ "<li>" ++ rules_list_item r ++ "</li>"
        onFail _ _ _ = alert "faal"
        
createRule :: String -> IO JQuery
createRule rule = do item <- jQuery $ "<li>" ++ rules_list_item rule ++ "</li>"
                     
                     return item
        
foreign import jscript "jQuery.noop()"
  noop :: IO (JSFunPtr (JSPtr a -> String -> JSPtr b -> IO()))
  
foreign import jscript "wrapper"
  eventWrap :: (JQuery -> IO Bool)-> IO (JSFunPtr (JQuery -> IO Bool))

foreign import jscript "wrapper"
  ioWrap :: IO () -> IO (JSFunPtr (IO ()))



alertType :: a -> IO ()
alertType = _alert . typeof