{-# LANGUAGE OverloadedStrings #-}

module Kitten.Resolve
  ( Resolved(..)
  , Value(..)
  , resolveFragment
  ) where

import Control.Applicative
import Control.Monad.Trans.Class
import Control.Monad.Trans.State
import Data.List
import Data.Monoid
import Data.Text (Text)
import Data.Vector (Vector)

import qualified Data.Text as Text
import qualified Data.Vector as Vector

import Kitten.Builtin (Builtin)
import Kitten.Def
import Kitten.Error
import Kitten.Name
import Kitten.Fragment
import Kitten.Term (Term)
import Kitten.Util

import qualified Kitten.Term as Term

data Resolved
  = Value !Value
  | Builtin !Builtin
  | Scoped !Resolved
  | Local !Name
  | Compose !Resolved !Resolved
  | Empty

data Value
  = Word !Name
  | Int !Int
  | Bool !Bool
  | Text !Text
  | Vec !(Vector Value)
  | Fun !Resolved

instance Show Value where
  show (Word (Name name)) = '@' : show name
  show (Int value) = show value
  show (Bool value) = if value then "true" else "false"
  show (Text value) = show value
  show (Vec values) = Text.unpack
    $ "[" <> Text.unwords (map textShow $ Vector.toList values) <> "]"
  show (Fun _) = "{...}"

data Env = Env
  { envPrelude :: Vector (Def Resolved)
  , envDefs :: Vector (Def Term)
  , envScope :: [Text]
  }

enter :: Text -> Env -> Env
enter name env = env { envScope = name : envScope env }

leave :: Env -> Env
leave env = env { envScope = tail $ envScope env }

type Resolution = StateT Env (Either CompileError)

resolveFragment
  :: Vector (Def Resolved)
  -> Fragment Term
  -> Either CompileError (Fragment Resolved)
resolveFragment prelude (Fragment defs term) = flip evalStateT env0
  $ Fragment <$> resolveDefs defs <*> resolveTerm term
  where env0 = Env prelude defs []

resolveDefs :: Vector (Def Term) -> Resolution (Vector (Def Resolved))
resolveDefs defs = (<>) <$> gets envPrelude <*> Vector.mapM resolveDef defs
  where resolveDef (Def name body) = Def name <$> resolveTerm body

resolveTerm :: Term -> Resolution Resolved
resolveTerm unresolved = case unresolved of
  Term.Value value -> resolveValue value
  Term.Builtin name -> return $ Builtin name
  Term.Compose down top -> Compose <$> resolveTerm down <*> resolveTerm top
  Term.Lambda name term -> do
    modify $ enter name
    resolved <- resolveTerm term
    modify leave
    return $ Scoped resolved
  Term.Empty -> return Empty

fromValue :: Resolved -> Value
fromValue (Value value) = value
fromValue _ = error "Resolve.fromValue: not a value"

resolveValue :: Term.Value -> Resolution Resolved
resolveValue unresolved = case unresolved of
  Term.Word name -> do
    mLocalIndex <- gets $ localIndex name
    case mLocalIndex of
      Just index -> return . Local $ Name index
      Nothing -> do
        mDefIndex <- gets $ defIndex name
        case mDefIndex of
          Just index -> return . Value . Word $ Name index
          Nothing -> lift . Left . CompileError $ Text.concat
            ["Unable to resolve word '", name, "'"]
  Term.Fun term -> Value . Fun <$> resolveTerm term
  Term.Vec terms -> Value . Vec
    <$> Vector.mapM (fmap fromValue . resolveValue) terms
  Term.Int value -> return . Value $ Int value
  Term.Bool value -> return . Value $ Bool value
  Term.Text value -> return . Value $ Text value

localIndex :: Text -> Env -> Maybe Int
localIndex name = elemIndex name . envScope

defIndex :: Text -> Env -> Maybe Int
defIndex expected Env{..} = findExpected envPrelude
  <|> ((+ Vector.length envPrelude) <$> findExpected envDefs)
  where
  defName (Def name _) = name
  findExpected = Vector.findIndex $ (== expected) . defName
