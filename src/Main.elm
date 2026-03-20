module Main exposing (main)

import Browser
import Dict exposing (Dict)
import Html exposing (..)
import Html.Attributes as Attr
import Html.Events as Events
import Http
import Json.Decode as Decode
import Json.Encode as Encode
import Markdown
import Markdown.Block as Block exposing (Block(..), BlockContent(..), ParseResult)
import Markdown.Inline as Inline exposing (Inline(..), InlineContent(..))
import Markdown.Wikilink exposing (WikilinkData)
import SourceLocation exposing (ComparableRegion, Region)


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }



-- MODEL


type alias Model =
    { source : String
    , parseResult : ParseResult () ()
    , files : List String
    , currentFile : Maybe String
    , hoveredRegion : Maybe Region
    , scrollToRegion : Maybe ( Region, Int )
    }


emptyParseResult : ParseResult () ()
emptyParseResult =
    { blocks = []
    , blockIds = Dict.empty
    , wikilinks = Dict.empty
    }



-- INIT


init : () -> ( Model, Cmd Msg )
init () =
    ( { source = ""
      , parseResult = emptyParseResult
      , files = []
      , currentFile = Nothing
      , hoveredRegion = Nothing
      , scrollToRegion = Nothing
      }
    , fetchFileList
    )



-- MSG


type Msg
    = SourceChanged String
    | SaveRequested String
    | SelectedFile String
    | GotFileList (Result Http.Error (List String))
    | GotFileContent (Result Http.Error String)
    | SavedFile (Result Http.Error ())
    | HoveredAstNode (Maybe Region)
    | ClickedAstNode Region



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SourceChanged newSource ->
            ( { model
                | source = newSource
                , parseResult = Markdown.parse Nothing newSource
              }
            , Cmd.none
            )

        SaveRequested content ->
            case model.currentFile of
                Just file ->
                    ( model, saveFile file content )

                Nothing ->
                    ( model, Cmd.none )

        SelectedFile file ->
            ( { model | currentFile = Just file }
            , fetchFileContent file
            )

        GotFileList (Ok files) ->
            let
                firstFile : Maybe String
                firstFile =
                    files |> List.head
            in
            ( { model | files = files, currentFile = firstFile }
            , firstFile
                |> Maybe.map fetchFileContent
                |> Maybe.withDefault Cmd.none
            )

        GotFileList (Err _) ->
            ( model, Cmd.none )

        GotFileContent (Ok content) ->
            ( { model
                | source = content
                , parseResult = Markdown.parse Nothing content
              }
            , Cmd.none
            )

        GotFileContent (Err _) ->
            ( model, Cmd.none )

        SavedFile _ ->
            ( model, Cmd.none )

        HoveredAstNode maybeRegion ->
            ( { model | hoveredRegion = maybeRegion }, Cmd.none )

        ClickedAstNode region ->
            let
                nextSeq : Int
                nextSeq =
                    model.scrollToRegion
                        |> Maybe.map (\( _, seq ) -> seq + 1)
                        |> Maybe.withDefault 0
            in
            ( { model | scrollToRegion = Just ( region, nextSeq ) }
            , Cmd.none
            )



-- HTTP


fetchFileList : Cmd Msg
fetchFileList =
    Http.get
        { url = "/files"
        , expect = Http.expectJson GotFileList (Decode.list Decode.string)
        }


fetchFileContent : String -> Cmd Msg
fetchFileContent file =
    Http.get
        { url = "/files/" ++ file
        , expect = Http.expectString GotFileContent
        }


saveFile : String -> String -> Cmd Msg
saveFile path content =
    Http.post
        { url = "/save"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "path", Encode.string path )
                    , ( "content", Encode.string content )
                    ]
                )
        , expect = Http.expectWhatever SavedFile
        }



-- REGION → OFFSET CONVERSION


regionToOffsets : String -> Region -> Maybe ( Int, Int )
regionToOffsets source region =
    let
        lines : List String
        lines =
            source |> String.split "\n"

        lineStartOffset : Int -> Int
        lineStartOffset row =
            lines
                |> List.take (row - 1)
                |> List.foldl (\line acc -> acc + String.length line + 1) 0

        fromOffset : Int
        fromOffset =
            lineStartOffset region.start.row + (region.start.col - 1)

        toOffset : Int
        toOffset =
            lineStartOffset region.end.row + (region.end.col - 1)

        docLength : Int
        docLength =
            String.length source
    in
    if fromOffset >= 0 && toOffset >= fromOffset && toOffset <= docLength then
        Just ( fromOffset, toOffset )

    else if fromOffset >= 0 && fromOffset <= docLength then
        Just ( fromOffset, min toOffset docLength )

    else
        Nothing



-- VIEW


view : Model -> Html Msg
view model =
    div [ Attr.class "app" ]
        [ viewTopBar model
        , div [ Attr.class "panels" ]
            [ viewEditor model
            , viewAstPanel model
            ]
        ]


viewTopBar : Model -> Html Msg
viewTopBar model =
    div [ Attr.class "topbar" ]
        [ span [ Attr.class "topbar-title" ] [ text "grasp-backend-markdown" ]
        , viewFileSelector model
        ]


viewFileSelector : Model -> Html Msg
viewFileSelector model =
    select
        [ Events.onInput SelectedFile
        , Attr.class "file-selector"
        ]
        (model.files
            |> List.map
                (\file ->
                    option
                        [ Attr.value file
                        , Attr.selected (model.currentFile == Just file)
                        ]
                        [ text file ]
                )
        )


viewEditor : Model -> Html Msg
viewEditor model =
    Html.node "codemirror-element"
        [ Attr.attribute "value" model.source
        , Events.on "value-changed"
            (Decode.at [ "detail", "value" ] Decode.string
                |> Decode.map SourceChanged
            )
        , Events.on "save-requested"
            (Decode.at [ "detail", "value" ] Decode.string
                |> Decode.map SaveRequested
            )
        , Attr.property "decorations" (encodeDecorations model)
        , Attr.property "scrollTo" (encodeScrollTo model)
        , Attr.class "editor-panel"
        ]
        []


encodeDecorations : Model -> Encode.Value
encodeDecorations model =
    case model.hoveredRegion of
        Nothing ->
            Encode.list identity []

        Just region ->
            case regionToOffsets model.source region of
                Nothing ->
                    Encode.list identity []

                Just ( from, to ) ->
                    Encode.list identity
                        [ Encode.object
                            [ ( "from", Encode.int from )
                            , ( "to", Encode.int to )
                            , ( "class", Encode.string "cm-highlight-region" )
                            ]
                        ]


encodeScrollTo : Model -> Encode.Value
encodeScrollTo model =
    case model.scrollToRegion of
        Nothing ->
            Encode.null

        Just ( region, seq ) ->
            case regionToOffsets model.source region of
                Nothing ->
                    Encode.null

                Just ( from, _ ) ->
                    Encode.object
                        [ ( "offset", Encode.int from )
                        , ( "seq", Encode.int seq )
                        ]



-- AST PANEL


viewAstPanel : Model -> Html Msg
viewAstPanel model =
    div [ Attr.class "ast-panel" ]
        [ div [ Attr.class "ast-header" ] [ text "AST" ]
        , div [ Attr.class "ast-tree" ]
            [ viewBlockIdsSummary model.parseResult.blockIds
            , viewWikilinksSummary model.parseResult.wikilinks
            , div [] (model.parseResult.blocks |> List.map (viewBlock 0))
            ]
        ]


viewBlockIdsSummary : Dict String Region -> Html Msg
viewBlockIdsSummary blockIds =
    if Dict.isEmpty blockIds then
        text ""

    else
        div [ Attr.class "ast-section" ]
            [ div [ Attr.class "ast-section-header" ]
                [ text ("Block IDs (" ++ String.fromInt (Dict.size blockIds) ++ ")") ]
            , div [ Attr.class "ast-section-body" ]
                (blockIds
                    |> Dict.toList
                    |> List.map
                        (\( id, region ) ->
                            div
                                [ Attr.class "ast-block-id"
                                , Events.onMouseEnter (HoveredAstNode (Just region))
                                , Events.onMouseLeave (HoveredAstNode Nothing)
                                , onClickStop (ClickedAstNode region)
                                ]
                                [ span [ Attr.class "ast-id-name" ] [ text ("^" ++ id) ]
                                , viewRegionBadge region
                                ]
                        )
                )
            ]


viewWikilinksSummary : Dict ComparableRegion WikilinkData -> Html Msg
viewWikilinksSummary wikilinks =
    if Dict.isEmpty wikilinks then
        text ""

    else
        div [ Attr.class "ast-section" ]
            [ div [ Attr.class "ast-section-header" ]
                [ text ("Wikilinks (" ++ String.fromInt (Dict.size wikilinks) ++ ")") ]
            , div [ Attr.class "ast-section-body" ]
                (wikilinks
                    |> Dict.toList
                    |> List.map
                        (\( comparableRegion, data ) ->
                            let
                                region : Region
                                region =
                                    SourceLocation.fromComparableRegion comparableRegion
                            in
                            div
                                [ Attr.class "ast-wikilink"
                                , Events.onMouseEnter (HoveredAstNode (Just region))
                                , Events.onMouseLeave (HoveredAstNode Nothing)
                                , onClickStop (ClickedAstNode region)
                                ]
                                [ span [ Attr.class "ast-wikilink-target" ] [ text data.target ]
                                , viewRegionBadge region
                                ]
                        )
                )
            ]



-- AST NODES


viewBlock : Int -> Block () () -> Html Msg
viewBlock depth (Block { content, region }) =
    div
        [ Attr.class "ast-node"
        , Attr.style "padding-left" (String.fromInt (depth * 16) ++ "px")
        , Events.onMouseEnter (HoveredAstNode (Just region))
        , Events.onMouseLeave (HoveredAstNode Nothing)
        , onClickStop (ClickedAstNode region)
        ]
        [ div [ Attr.class "ast-node-header" ]
            [ span [ Attr.class "ast-node-type" ] [ text (blockContentLabel content) ]
            , viewRegionBadge region
            ]
        , div [ Attr.class "ast-node-children" ]
            (viewBlockContentChildren depth content)
        ]


blockContentLabel : BlockContent () () -> String
blockContentLabel content =
    case content of
        BlankLine _ ->
            "BlankLine"

        ThematicBreak ->
            "ThematicBreak"

        Heading _ level _ ->
            "Heading (h" ++ String.fromInt level ++ ")"

        CodeBlock _ _ ->
            "CodeBlock"

        Paragraph _ _ ->
            "Paragraph"

        BlockQuote _ ->
            "BlockQuote"

        List listBlock _ ->
            case listBlock.type_ of
                Block.Unordered ->
                    "UnorderedList"

                Block.Ordered start ->
                    "OrderedList (start=" ++ String.fromInt start ++ ")"

        PlainInlines _ ->
            "PlainInlines"

        Block.Custom _ _ ->
            "Custom"


viewBlockContentChildren : Int -> BlockContent () () -> List (Html Msg)
viewBlockContentChildren depth content =
    case content of
        Heading _ _ inlines ->
            inlines |> List.map (viewInline (depth + 1))

        Paragraph _ inlines ->
            inlines |> List.map (viewInline (depth + 1))

        BlockQuote blocks ->
            blocks |> List.map (viewBlock (depth + 1))

        List _ items ->
            items
                |> List.indexedMap
                    (\i blocks ->
                        div [ Attr.class "ast-list-item" ]
                            [ span [ Attr.class "ast-list-item-label" ]
                                [ text ("Item " ++ String.fromInt (i + 1)) ]
                            , div [] (blocks |> List.map (viewBlock (depth + 1)))
                            ]
                    )

        PlainInlines inlines ->
            inlines |> List.map (viewInline (depth + 1))

        Block.Custom _ blocks ->
            blocks |> List.map (viewBlock (depth + 1))

        _ ->
            []


viewInline : Int -> Inline () -> Html Msg
viewInline depth (Inline { content, region }) =
    div
        [ Attr.class "ast-node ast-inline"
        , Attr.style "padding-left" (String.fromInt (depth * 16) ++ "px")
        , Events.onMouseEnter (HoveredAstNode (Just region))
        , Events.onMouseLeave (HoveredAstNode Nothing)
        , onClickStop (ClickedAstNode region)
        ]
        [ div [ Attr.class "ast-node-header" ]
            [ span [ Attr.class "ast-node-type ast-inline-type" ] [ text (inlineContentLabel content) ]
            , viewRegionBadge region
            ]
        , div [ Attr.class "ast-node-children" ]
            (viewInlineChildren depth content)
        ]


inlineContentLabel : InlineContent () -> String
inlineContentLabel content =
    case content of
        Text str ->
            "Text \"" ++ truncate 30 str ++ "\""

        HardLineBreak ->
            "HardLineBreak"

        CodeInline str ->
            "CodeInline \"" ++ truncate 20 str ++ "\""

        Link url _ _ ->
            "Link \"" ++ url ++ "\""

        Image src _ _ ->
            "Image \"" ++ src ++ "\""

        HtmlInline tag _ _ ->
            "HtmlInline <" ++ tag ++ ">"

        Emphasis len _ ->
            "Emphasis (" ++ String.fromInt len ++ ")"

        Inline.Custom _ _ ->
            "Custom"

        Wikilink data ->
            "Wikilink [[" ++ data.target ++ "]]"


viewInlineChildren : Int -> InlineContent () -> List (Html Msg)
viewInlineChildren depth content =
    case content of
        Link _ _ inlines ->
            inlines |> List.map (viewInline (depth + 1))

        Image _ _ inlines ->
            inlines |> List.map (viewInline (depth + 1))

        HtmlInline _ _ inlines ->
            inlines |> List.map (viewInline (depth + 1))

        Emphasis _ inlines ->
            inlines |> List.map (viewInline (depth + 1))

        Inline.Custom _ inlines ->
            inlines |> List.map (viewInline (depth + 1))

        _ ->
            []



-- HELPERS


viewRegionBadge : Region -> Html Msg
viewRegionBadge region =
    span [ Attr.class "ast-region" ]
        [ text
            (String.fromInt region.start.row
                ++ ":"
                ++ String.fromInt region.start.col
                ++ " \u{2192} "
                ++ String.fromInt region.end.row
                ++ ":"
                ++ String.fromInt region.end.col
            )
        ]


onClickStop : Msg -> Html.Attribute Msg
onClickStop msg =
    Events.stopPropagationOn "click"
        (Decode.succeed ( msg, True ))


truncate : Int -> String -> String
truncate maxLen str =
    if String.length str > maxLen then
        String.left maxLen str ++ "..."

    else
        str
