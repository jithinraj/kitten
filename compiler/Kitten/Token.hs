module Kitten.Token
  ( Located(..)
  , Token(..)
  , tokenize
  ) where

import Control.Applicative
import Control.Monad.Identity
import Data.Text (Text)
import Text.Parsec ((<?>))

import qualified Data.Text as Text
import qualified Text.Parsec as P

import Kitten.Builtin (Builtin)
import Kitten.Util

import qualified Kitten.Builtin as Builtin

type Parser a = P.ParsecT String P.Column Identity a

data Token
  = Word !Text
  | Builtin !Builtin
  | Int !Int
  | Bool !Bool
  | Text !Text
  | Def
  | Lambda
  | VecBegin
  | VecEnd
  | FunBegin
  | FunEnd
  | Layout
  deriving (Eq)

instance Show Token where
  show (Word word) = show word
  show (Builtin name) = show name
  show (Int value) = show value
  show (Bool value) = if value then "true" else "false"
  show (Text value) = show value
  show Def = "def"
  show Lambda = "\\"
  show VecBegin = "["
  show VecEnd = "]"
  show FunBegin = "{"
  show FunEnd = "}"
  show Layout = ":"

data Located = Located
  { locatedLocation :: P.SourcePos
  , locatedIndent :: P.Column
  , locatedToken :: Token
  }

instance Show Located where
  show Located{..} = show locatedToken

tokenize :: String -> String -> Either P.ParseError [Located]
tokenize = P.runParser file 0

located
  :: Parser Token
  -> Parser Located
located parser = do
  indent <- P.getState
  position <- P.getPosition
  result <- parser
  return $ Located position indent result

file :: Parser [Located]
file = silence *> tokens <* P.eof

tokens :: Parser [Located]
tokens = token `P.sepEndBy` silence

token :: Parser Located
token = (<?> "token") . located $ P.choice
  [ lambda
  , vecBegin
  , vecEnd
  , funBegin
  , funEnd
  , layout
  , P.try int
  , text
  , word
  ]

  where
  lambda = Lambda <$ P.char '\\'

  vecBegin = VecBegin <$ P.char '['
  vecEnd = VecEnd <$ P.char ']'

  funBegin = FunBegin <$ P.char '{'
  layout = Layout <$ P.char ':'
  funEnd = FunEnd <$ P.char '}'

  int = do
    sign <- P.optionMaybe $ P.oneOf "+-"
    value <- read <$> P.many1 P.digit
    return . Int $ if sign == Just '-' then negate value else value

  text = Text . Text.pack <$> (P.char '"' *> textContents <* P.char '"')
  textContents = P.many (P.noneOf "\\\"" <|> textEscape)
  textEscape = P.char '\\' *> P.oneOf "\\\""

  word = (alphanumeric <|> symbolic) <$$> \ name -> case name of
    "def" -> Def
    "true" -> Bool True
    "false" -> Bool False
    _ -> case Builtin.fromText nameText of
      Just builtin -> Builtin builtin
      _ -> Word nameText
      where nameText = Text.pack name
    where
    alphanumeric = (:)
      <$> (P.letter <|> P.char '_')
      <*> P.many (P.letter <|> P.digit <|> P.char '_')
    symbolic = P.many1 $ P.oneOf "!#$%&*+,-./;<=>?@^|~"

silence :: Parser ()
silence = P.skipMany $ comment <|> whitespace
  where
  whitespace = P.skipMany1 $ P.choice [newline, nonNewline]
  newline = do
    void $ P.char '\n' *> many nonNewline
    pos <- P.getPosition
    P.putState $ P.sourceColumn pos
  nonNewline = void $ P.satisfy (`elem` "\t\v\f\r ")
  comment = single <|> multi
  single = P.try (P.string "--")
    *> (P.anyChar `skipManyTill` (void (P.char '\n') <|> P.eof))
  multi = void $ start *> contents <* end
    where
    contents = characters *> optional multi <* characters
    characters = P.skipMany $ P.notFollowedBy (start <|> end) *> P.anyChar
    start = P.try $ P.string "{-"
    end = P.string "-}"

skipManyTill
  :: Parser a
  -> Parser b
  -> Parser ()
a `skipManyTill` b = void (P.try b) <|> a *> (a `skipManyTill` b)
