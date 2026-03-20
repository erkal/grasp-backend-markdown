module Markdown.Wikilink exposing
    ( parseContent, parseDimensions -- Parsing
    , defaultDisplay -- Query
    , isImageEmbed, isVideoEmbed -- Embed type checks
    , isAudioEmbed, isPdfEmbed
    , WikilinkData, Fragment(..) -- Types
    )


type alias WikilinkData =
    { target : String
    , fragment : Maybe Fragment
    , display : Maybe String
    , isEmbed : Bool
    }


type Fragment
    = HeadingFragment (List String)
    | BlockFragment String
    | HeadingSearch String
    | BlockSearch String
    | PdfPage Int
    | PdfHeight Int



-- PARSING


parseContent : Bool -> String -> WikilinkData
parseContent isEmbed raw =
    let
        splitResult : ( String, Maybe String )
        splitResult =
            splitOnPipe raw

        targetPart : String
        targetPart =
            Tuple.first splitResult

        displayPart : Maybe String
        displayPart =
            Tuple.second splitResult

        parseResult : ( String, Maybe Fragment )
        parseResult =
            parseFragment targetPart

        target : String
        target =
            Tuple.first parseResult

        fragment : Maybe Fragment
        fragment =
            Tuple.second parseResult
    in
    { target = String.trim target
    , fragment = fragment
    , display = Maybe.map String.trim displayPart
    , isEmbed = isEmbed
    }


splitOnPipe : String -> ( String, Maybe String )
splitOnPipe raw =
    splitOnPipeHelp 0 False raw


splitOnPipeHelp : Int -> Bool -> String -> ( String, Maybe String )
splitOnPipeHelp idx escaped raw =
    if idx >= String.length raw then
        ( raw, Nothing )

    else
        let
            char : String
            char =
                String.slice idx (idx + 1) raw
        in
        if escaped then
            splitOnPipeHelp (idx + 1) False raw

        else if char == "\\" then
            splitOnPipeHelp (idx + 1) True raw

        else if char == "|" then
            ( String.left idx raw
            , Just (String.dropLeft (idx + 1) raw)
            )

        else
            splitOnPipeHelp (idx + 1) False raw


parseFragment : String -> ( String, Maybe Fragment )
parseFragment str =
    if String.startsWith "##" str then
        ( ""
        , Just (HeadingSearch (String.dropLeft 2 str |> String.trim))
        )

    else if String.startsWith "^^" str then
        ( ""
        , Just (BlockSearch (String.dropLeft 2 str |> String.trim))
        )

    else
        case splitOnFirstHash str of
            ( target, Nothing ) ->
                ( target, Nothing )

            ( target, Just fragmentStr ) ->
                ( target, Just (classifyFragment fragmentStr) )


splitOnFirstHash : String -> ( String, Maybe String )
splitOnFirstHash str =
    case String.indices "#" str of
        [] ->
            ( str, Nothing )

        firstIdx :: _ ->
            ( String.left firstIdx str
            , Just (String.dropLeft (firstIdx + 1) str)
            )


classifyFragment : String -> Fragment
classifyFragment frag =
    if String.startsWith "^" frag then
        BlockFragment (String.dropLeft 1 frag)

    else if String.startsWith "page=" frag then
        frag
            |> String.dropLeft 5
            |> String.toInt
            |> Maybe.map PdfPage
            |> Maybe.withDefault (HeadingFragment [ frag ])

    else if String.startsWith "height=" frag then
        frag
            |> String.dropLeft 7
            |> String.toInt
            |> Maybe.map PdfHeight
            |> Maybe.withDefault (HeadingFragment [ frag ])

    else
        HeadingFragment (String.split "#" frag)



-- HELPERS


defaultDisplay : WikilinkData -> String
defaultDisplay data =
    let
        base : String
        base =
            data.target
                |> String.split "/"
                |> List.reverse
                |> List.head
                |> Maybe.withDefault data.target
    in
    stripExtension base


stripExtension : String -> String
stripExtension name =
    case String.indices "." name of
        [] ->
            name

        _ ->
            name
                |> String.split "."
                |> List.reverse
                |> List.drop 1
                |> List.reverse
                |> String.join "."
                |> (\s ->
                        if String.isEmpty s then
                            name

                        else
                            s
                   )


isImageEmbed : String -> Bool
isImageEmbed target =
    let
        lower : String
        lower =
            String.toLower target
    in
    [ ".avif", ".bmp", ".gif", ".jpeg", ".jpg", ".png", ".svg", ".webp" ]
        |> List.any (\ext -> String.endsWith ext lower)


isVideoEmbed : String -> Bool
isVideoEmbed target =
    let
        lower : String
        lower =
            String.toLower target
    in
    [ ".mkv", ".mov", ".mp4", ".ogv", ".webm" ]
        |> List.any (\ext -> String.endsWith ext lower)


isAudioEmbed : String -> Bool
isAudioEmbed target =
    let
        lower : String
        lower =
            String.toLower target
    in
    [ ".flac", ".m4a", ".mp3", ".ogg", ".wav", ".3gp" ]
        |> List.any (\ext -> String.endsWith ext lower)


isPdfEmbed : String -> Bool
isPdfEmbed target =
    String.toLower target |> String.endsWith ".pdf"


parseDimensions : Maybe String -> ( Maybe Int, Maybe Int )
parseDimensions maybeDisplay =
    case maybeDisplay of
        Nothing ->
            ( Nothing, Nothing )

        Just display ->
            if String.contains "x" display then
                case String.split "x" display of
                    [ wStr, hStr ] ->
                        ( String.toInt (String.trim wStr)
                        , String.toInt (String.trim hStr)
                        )

                    _ ->
                        ( Nothing, Nothing )

            else
                ( String.toInt (String.trim display), Nothing )
