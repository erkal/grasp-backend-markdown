module Markdown.Inline
    exposing
        ( Inline(..)
        , InlineContent(..)
        , extractText
        )

{-| Inline types and helpers.


# Model

@docs Inline, InlineContent


# Helpers

@docs extractText

-}

import Markdown.Helpers exposing (Attribute)
import Markdown.Wikilink as Wikilink exposing (WikilinkData)


type alias Region =
    ( ( Int, Int ), ( Int, Int ) )


{-| An inline element with its source region.
-}
type Inline i
    = Inline
        { content : InlineContent i
        , region : Region
        }


{-| The inline content type.

  - **Text** | _Text_
  - **HardLineBreak**
  - **CodeInline** | _Code_
  - **Link** | _Url_ | _Maybe Title_ | _Inlines_
  - **Image** | _Source_ | _Maybe Title_ | _Inlines_
  - **HtmlInline** | _Tag_ | _List Attribute_ | _Inlines_
  - **Emphasis** | _Delimiter Length_ | _Inlines_
  - **Custom** | _Custom type_ | _Inlines_
  - **Wikilink** | _WikilinkData_

-}
type InlineContent i
    = Text String
    | HardLineBreak
    | CodeInline String
    | Link String (Maybe String) (List (Inline i))
    | Image String (Maybe String) (List (Inline i))
    | HtmlInline String (List ( String, Maybe String )) (List (Inline i))
    | Emphasis Int (List (Inline i))
    | Custom i (List (Inline i))
    | Wikilink WikilinkData


{-| Extract the text from a list of inlines.
-}
extractText : List (Inline i) -> String
extractText inlines =
    List.foldl extractTextHelp "" inlines


extractTextHelp : Inline i -> String -> String
extractTextHelp (Inline { content }) text =
    case content of
        Text str ->
            text ++ str

        HardLineBreak ->
            text ++ " "

        CodeInline str ->
            text ++ str

        Link _ _ inlines ->
            text ++ extractText inlines

        Image _ _ inlines ->
            text ++ extractText inlines

        HtmlInline _ _ inlines ->
            text ++ extractText inlines

        Emphasis _ inlines ->
            text ++ extractText inlines

        Custom _ inlines ->
            text ++ extractText inlines

        Wikilink data ->
            text
                ++ (data.display
                        |> Maybe.withDefault (Wikilink.defaultDisplay data)
                   )
