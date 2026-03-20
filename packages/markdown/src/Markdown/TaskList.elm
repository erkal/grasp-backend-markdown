module Markdown.TaskList exposing
    ( TaskStatus(..)
    , detect
    )

{-| Task list checkbox detection in list items.
-}

import Markdown.Inline exposing (Inline(..), InlineContent(..))


type TaskStatus
    = NotATask
    | IncompleteTask
    | CompletedTask


{-| Detect whether the leading inlines represent a task item
(`[ ]` or `[x]`/`[X]`). Returns the status and the inlines with
the checkbox prefix stripped.
-}
detect : List (Inline i) -> ( TaskStatus, List (Inline i) )
detect inlines =
    case inlines of
        (Inline inline) :: rest ->
            case inline.content of
                Text str ->
                    if String.startsWith "[ ] " str then
                        ( IncompleteTask
                        , Inline { inline | content = Text (String.dropLeft 4 str) } :: rest
                        )

                    else if String.startsWith "[x] " str || String.startsWith "[X] " str then
                        ( CompletedTask
                        , Inline { inline | content = Text (String.dropLeft 4 str) } :: rest
                        )

                    else
                        ( NotATask, inlines )

                _ ->
                    ( NotATask, inlines )

        _ ->
            ( NotATask, inlines )
