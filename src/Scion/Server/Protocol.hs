{-# LANGUAGE ExistentialQuantification, TypeSynonymInstances #-}
-- |
-- Module      : Scion.Server.Protocol
-- Copyright   : (c) Thomas Schilling 2008
-- License     : BSD-style
--
-- Maintainer  : nominolo@gmail.com
-- Stability   : experimental
-- Portability : portable
--
-- Server message types and methods for serialising and deserialising them to
-- strings.
--
-- TODO: Document protocol + message format.
--
module Scion.Server.Protocol where

import Scion.Types

import Data.Char ( isDigit, isSpace )
import Numeric   ( showInt )
import Text.ParserCombinators.ReadP
import qualified Data.Map as M

------------------------------------------------------------------------------

scionVersion :: Int
scionVersion = 1

class Sexp a where toSexp :: a -> ShowS
instance Sexp String where toSexp s = showString (show s)
instance Sexp Int where toSexp i = showInt i
instance Sexp Integer where toSexp i = showInt i

newtype Keyword = K String deriving (Eq, Ord, Show)
instance Sexp Keyword where
  toSexp (K s) = showChar ':' . showString s

-- if you need to cheat
newtype ExactSexp = ExactSexp ShowS
instance Sexp ExactSexp where
  toSexp (ExactSexp s) = s

instance (Sexp a, Sexp b) => Sexp (M.Map a b) where
  toSexp m = parens (go (M.assocs m))
    where go ((k,v):r) = toSexp k <+> toSexp v <+> go r
          go [] = id

data Request
  = Rex (ScionM String) Int -- Remote EXecute
  | RQuit

instance Show Request where
  show (Rex _ i) = "Rex <cmd> " ++ show i
  show RQuit = "RQuit"

data Response
  = RReturn String Int
  | RReaderError String String
  deriving Show

data Command = Command {
    getCommand :: ReadP (ScionM String)
  }

------------------------------------------------------------------------------

-- * Parsing Requests

parseRequest :: [Command] -> String -> Maybe Request
parseRequest cmds msg =
    let rs = readP_to_S (messageParser cmds) msg in
    case [ r | (r, "") <- rs ] of
      [m] -> Just m
      []  -> Nothing
      _   -> error "Ambiguous grammar for message.  This is a bug."

-- | At the moment messages are in a very simple Lisp-style format.  This
--   should also be easy to parse (and generate) for non-lisp clients.
messageParser :: [Command] -> ReadP Request
messageParser cmds = do
  r <- inParens $ choice
         [ string ":quit" >> return RQuit
         , do string ":emacs-rex"
              sp
              c <- inParens (choice (map getCommand cmds))
              sp
              i <- getInt
              return (Rex c i)
         ]    
  skipSpaces
  return r

inParens :: ReadP a -> ReadP a
inParens = between (char '(') (char ')')

getString :: ReadP String
getString = decodeEscapes `fmap` (char '"' >> munchmunch False)
  where
    munchmunch had_backspace = do
      c <- get
      if c == '"' && not had_backspace 
        then return []
        else do
          (c:) `fmap` munchmunch (c == '\\')

getInt :: ReadP Int
getInt = munch1 isDigit >>= return . read

decodeEscapes :: String -> String
decodeEscapes = id -- XXX

-- | One or more spaces.
sp :: ReadP ()
sp = skipMany1 (satisfy isSpace)


------------------------------------------------------------------------------

-- * Writing Responses

showResponse :: Response -> String
showResponse r = shows' r "\n"
  where
    shows' (RReturn f i) = 
       parens (showString ":return" <+> 
               parens (showString ":ok" <+> showString f)
               <+> showInt i)
    shows' (RReaderError s t) = 
        parens (showString ":reader-error" <+>
                showString (show s) <+>
                showString (show t))
parens :: ShowS -> ShowS
parens p = showChar '(' . p . showChar ')'

putString :: String -> ShowS
putString s = showString (show s)

infixr 1 <+>
(<+>) :: ShowS -> ShowS -> ShowS
l <+> r = l . showChar ' ' . r