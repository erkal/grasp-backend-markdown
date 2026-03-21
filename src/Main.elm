port module Main exposing (main)

import Browser
import Dict exposing (Dict)
import FsServer
import Html exposing (..)
import Html.Attributes as Attr
import Html.Events as Events
import Json.Decode as Decode
import Json.Encode as Encode
import Markdown
import Markdown.Block as Block exposing (Block(..), BlockContent(..), ParseResult)
import Markdown.Inline as Inline exposing (Inline(..), InlineContent(..))
import Markdown.Wikilink exposing (WikilinkData)
import WebSocketManager as WS


type alias Region =
    ( ( Int, Int ), ( Int, Int ) )


port wsOut : WS.CommandPort msg


port wsIn : WS.EventPort msg


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }



-- MODEL


type alias Flags =
    { wsUrl : String
    , projectDir : String
    }


type alias Model =
    { source : String
    , parseResult : ParseResult () ()
    , files : List String
    , currentFile : Maybe String
    , hoveredRegion : Maybe Region
    , scrollToRegion : Maybe ( Region, Int )
    , error : Maybe String
    , wsConfig : WS.Config
    , wsConnected : Bool
    , projectDir : String
    }


emptyParseResult : ParseResult () ()
emptyParseResult =
    { blocks = []
    , blockIds = Dict.empty
    , wikilinks = Dict.empty
    }



-- INIT


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        wsConfig : WS.Config
        wsConfig =
            WS.init flags.wsUrl

        ws : WS.WebSocket Msg
        ws =
            WS.bind wsConfig wsOut GotWsEvent
    in
    ( { source = ""
      , parseResult = emptyParseResult
      , files = []
      , currentFile = Nothing
      , hoveredRegion = Nothing
      , scrollToRegion = Nothing
      , error = Nothing
      , wsConfig = wsConfig
      , wsConnected = False
      , projectDir = flags.projectDir
      }
    , ws.open
    )



-- MSG


type Msg
    = SourceChanged String
    | SaveRequested String
    | SelectedFile String
    | GotWsEvent (Result Decode.Error WS.Event)
    | HoveredAstNode (Maybe Region)
    | ClickedAstNode Region



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    WS.onEvent wsIn [ ( model.wsConfig, GotWsEvent ) ] (GotWsEvent << Err)



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
                    ( model, wsSendJsonValue model (FsServer.encodeSaveFile file content) )

                Nothing ->
                    ( { model | error = Just "No file selected" }, Cmd.none )

        SelectedFile file ->
            ( { model | currentFile = Just file, error = Nothing }
            , sendReadContent model file
            )

        GotWsEvent (Ok event) ->
            handleWsEvent event model

        GotWsEvent (Err decodeError) ->
            ( { model | error = Just ("WS decode error: " ++ Decode.errorToString decodeError) }
            , Cmd.none
            )

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



-- WEBSOCKET COMMUNICATION


wsSendJsonValue : Model -> Encode.Value -> Cmd Msg
wsSendJsonValue model jsonValue =
    let
        ws : WS.WebSocket Msg
        ws =
            WS.bind model.wsConfig wsOut GotWsEvent
    in
    ws.sendText (Encode.encode 0 jsonValue)


sendScanDirectory : Model -> Cmd Msg
sendScanDirectory model =
    wsSendJsonValue model (FsServer.encodeScanDirectory model.projectDir Nothing)


sendReadContent : Model -> String -> Cmd Msg
sendReadContent model filePath =
    wsSendJsonValue model (FsServer.encodeReadContent filePath)



-- WEBSOCKET EVENT HANDLING


handleWsEvent : WS.Event -> Model -> ( Model, Cmd Msg )
handleWsEvent event model =
    case event of
        WS.Opened ->
            ( { model | wsConnected = True }
            , sendScanDirectory model
            )

        WS.MessageReceived message ->
            handleServerMessage message model

        WS.Closed _ ->
            ( { model | wsConnected = False }, Cmd.none )

        _ ->
            ( model, Cmd.none )


handleServerMessage : String -> Model -> ( Model, Cmd Msg )
handleServerMessage message model =
    case Decode.decodeString FsServer.serverMessageDecoder message of
        Ok (FsServer.DirectoryListing { entries }) ->
            let
                fileNames : List String
                fileNames =
                    entries
                        |> List.filterMap
                            (\e ->
                                if not e.isDirectory && String.endsWith ".md" e.name then
                                    Just e.path
                                else
                                    Nothing
                            )

                firstFile : Maybe String
                firstFile =
                    fileNames |> List.head
            in
            ( { model | files = fileNames, currentFile = firstFile, error = Nothing }
            , firstFile
                |> Maybe.map (sendReadContent model)
                |> Maybe.withDefault Cmd.none
            )

        Ok (FsServer.FileContent { content }) ->
            case content of
                Just c ->
                    ( { model
                        | source = c
                        , parseResult = Markdown.parse Nothing c
                        , error = Nothing
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        Ok (FsServer.FileTreeDelta delta) ->
            let
                isMdFile : { a | name : String, isDirectory : Bool } -> Bool
                isMdFile e =
                    not e.isDirectory && String.endsWith ".md" e.name

                addedFiles : List String
                addedFiles =
                    delta.added
                        |> List.filterMap
                            (\e ->
                                if isMdFile e then
                                    Just e.path
                                else
                                    Nothing
                            )

                renamedOldPaths : List String
                renamedOldPaths =
                    delta.renamed |> List.map .oldPath

                renamedNewFiles : List String
                renamedNewFiles =
                    delta.renamed
                        |> List.filterMap
                            (\e ->
                                if isMdFile e then
                                    Just e.newPath
                                else
                                    Nothing
                            )

                removedFiles : List String
                removedFiles =
                    delta.removed ++ renamedOldPaths

                updatedFiles : List String
                updatedFiles =
                    model.files
                        |> List.filter (\f -> not (List.member f removedFiles))
                        |> (\existing -> existing ++ addedFiles ++ renamedNewFiles)
                        |> List.sort

                needsReload : Bool
                needsReload =
                    delta.changed
                        |> List.any (\c -> model.currentFile == Just c.path)

                renamedPath : Maybe String
                renamedPath =
                    delta.renamed
                        |> List.filter (\r -> r.oldPath == Maybe.withDefault "" model.currentFile)
                        |> List.head
                        |> Maybe.map .newPath

                updatedCurrentFile : Maybe String
                updatedCurrentFile =
                    case model.currentFile of
                        Just cur ->
                            case renamedPath of
                                Just newPath ->
                                    Just newPath

                                Nothing ->
                                    if List.member cur removedFiles then
                                        Nothing

                                    else
                                        Just cur

                        Nothing ->
                            Nothing
            in
            ( { model | files = updatedFiles, currentFile = updatedCurrentFile }
            , if needsReload then
                updatedCurrentFile
                    |> Maybe.map (sendReadContent model)
                    |> Maybe.withDefault Cmd.none

              else
                Cmd.none
            )

        Ok (FsServer.SaveResult _) ->
            ( model, Cmd.none )

        Ok (FsServer.Error err) ->
            ( { model | error = Just ("Server error: " ++ err.message) }, Cmd.none )

        Err decodeError ->
            ( { model | error = Just ("Decode error: " ++ Decode.errorToString decodeError) }, Cmd.none )



-- REGION → OFFSET CONVERSION


regionToOffsets : String -> Region -> Maybe ( Int, Int )
regionToOffsets source (( ( startRow, startCol ), ( endRow, endCol ) ) as region) =
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
            lineStartOffset startRow + (startCol - 1)

        toOffset : Int
        toOffset =
            lineStartOffset endRow + (endCol - 1)

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
        , case model.error of
            Just errorMsg ->
                span [ Attr.class "topbar-error" ] [ text errorMsg ]

            Nothing ->
                text ""
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
        , Attr.attribute "language" "markdown"
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


viewWikilinksSummary : Dict Region WikilinkData -> Html Msg
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
                        (\( region, data ) ->
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
viewRegionBadge ( ( startRow, startCol ), ( endRow, endCol ) ) =
    span [ Attr.class "ast-region" ]
        [ text
            (String.fromInt startRow
                ++ ":"
                ++ String.fromInt startCol
                ++ " \u{2192} "
                ++ String.fromInt endRow
                ++ ":"
                ++ String.fromInt endCol
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
