{-# LANGUAGE CPP #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Database.Redis.Protocol (Reply(..), reply, renderRequest) where

import Prelude hiding (error, take)
#if __GLASGOW_HASKELL__ < 710
import Control.Applicative
#endif
import Control.DeepSeq
import Data.Attoparsec.ByteString (takeTill)
import Data.Attoparsec.ByteString.Char8 hiding (takeTill)
import Data.ByteString.Char8 (ByteString)
import GHC.Generics
import qualified Data.ByteString.Char8 as B

-- |Low-level representation of replies from the Redis server.
data Reply = SingleLine ByteString
           | Error ByteString
           | Integer Integer
           | Bulk (Maybe ByteString)
           | MultiBulk (Maybe [Reply])
         deriving (Eq, Show, Generic)

instance NFData Reply

------------------------------------------------------------------------------
-- Request
--
renderRequest :: [ByteString] -> ByteString
renderRequest req = B.concat (argCnt:args)
  where
    argCnt = B.concat ["*", showBS (length req), crlf]
    args   = map renderArg req

renderArg :: ByteString -> ByteString
renderArg arg = B.concat ["$",  argLen arg, crlf, arg, crlf]
  where
    argLen = showBS . B.length

showBS :: (Show a) => a -> ByteString
showBS = B.pack . show

crlf :: ByteString
crlf = "\r\n"

------------------------------------------------------------------------------
-- Reply parsers
--
reply :: Parser Reply
reply = do
  c <- anyChar
  case c of
    '+' -> singleLine
    '-' -> error
    ':' -> integer
    '$' -> bulk
    '*' -> multiBulk
    _ -> fail "Unknown reply type"

singleLine :: Parser Reply
singleLine = SingleLine <$> (takeTill isEndOfLine <* endOfLine)

error :: Parser Reply
error = Error <$> (takeTill isEndOfLine <* endOfLine)

integer :: Parser Reply
integer = Integer <$> (signed decimal <* endOfLine)

bulk :: Parser Reply
bulk = Bulk <$> do
    len <- signed decimal <* endOfLine
    if len < 0
        then return Nothing
        else Just <$> take len <* endOfLine

multiBulk :: Parser Reply
multiBulk = MultiBulk <$> do
    len <- signed decimal <* endOfLine
    if len < 0
        then return Nothing
        else Just <$> count len reply
