module Markdown exposing (parse)

{-| A pure Elm package for markdown parsing.

@docs parse

-}

import Markdown.Block as Block exposing (Block, ParseResult)
import Markdown.Config exposing (Options)


{-| Parse a markdown string into a ParseResult.

If `Maybe Options` is `Nothing`, `Config.defaultOptions` will be used.

-}
parse : Maybe Options -> String -> ParseResult () ()
parse =
    Block.parse
