module Markdown.Alert exposing
    ( Alert
    , AlertType(..)
    , alertTypeToClass
    , alertTypeToIcon
    , alertTypeToLabel
    , tryParse
    )

{-| GitHub-style alert detection in blockquotes.

Detects `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`
markers inside blockquotes.

-}

import Markdown.Block exposing (Block(..), BlockContent(..))
import Regex exposing (Regex)


type AlertType
    = Note
    | Tip
    | Important
    | Warning
    | Caution


type alias Alert b i =
    { alertType : AlertType
    , contentBlocks : List (Block b i)
    }


tryParse : List (Block b i) -> Maybe (Alert b i)
tryParse blocks =
    case blocks of
        (Block blockRec) :: restBlocks ->
            case blockRec.content of
                Paragraph rawText _ ->
                    let
                        firstLine : String
                        firstLine =
                            rawText
                                |> String.lines
                                |> List.head
                                |> Maybe.withDefault ""
                                |> String.trim
                    in
                    case Regex.find alertMarkerRegex firstLine of
                        [ match ] ->
                            case match.submatches of
                                (Just typeName) :: _ ->
                                    case alertTypeFromString typeName of
                                        Just alertType ->
                                            let
                                                remainingText : String
                                                remainingText =
                                                    rawText
                                                        |> String.lines
                                                        |> List.drop 1
                                                        |> String.join "\n"
                                                        |> String.trim

                                                contentBlocks : List (Block b i)
                                                contentBlocks =
                                                    if String.isEmpty remainingText then
                                                        restBlocks

                                                    else
                                                        (Markdown.Block.parse Nothing remainingText).blocks
                                                            ++ restBlocks
                                            in
                                            Just
                                                { alertType = alertType
                                                , contentBlocks = contentBlocks
                                                }

                                        Nothing ->
                                            Nothing

                                _ ->
                                    Nothing

                        _ ->
                            Nothing

                _ ->
                    Nothing

        _ ->
            Nothing



-- HELPERS


alertMarkerRegex : Regex
alertMarkerRegex =
    Regex.fromString "^\\[!([A-Za-z]+)\\]\\s*$"
        |> Maybe.withDefault Regex.never


alertTypeFromString : String -> Maybe AlertType
alertTypeFromString str =
    case String.toUpper (String.trim str) of
        "NOTE" ->
            Just Note

        "TIP" ->
            Just Tip

        "IMPORTANT" ->
            Just Important

        "WARNING" ->
            Just Warning

        "CAUTION" ->
            Just Caution

        _ ->
            Nothing


alertTypeToClass : AlertType -> String
alertTypeToClass alertType =
    case alertType of
        Note ->
            "markdown-alert-note"

        Tip ->
            "markdown-alert-tip"

        Important ->
            "markdown-alert-important"

        Warning ->
            "markdown-alert-warning"

        Caution ->
            "markdown-alert-caution"


alertTypeToLabel : AlertType -> String
alertTypeToLabel alertType =
    case alertType of
        Note ->
            "Note"

        Tip ->
            "Tip"

        Important ->
            "Important"

        Warning ->
            "Warning"

        Caution ->
            "Caution"


alertTypeToIcon : AlertType -> String
alertTypeToIcon alertType =
    case alertType of
        Note ->
            "\u{2139}\u{FE0F}"

        Tip ->
            "\u{1F4A1}"

        Important ->
            "\u{2757}"

        Warning ->
            "\u{26A0}\u{FE0F}"

        Caution ->
            "\u{1F534}"
