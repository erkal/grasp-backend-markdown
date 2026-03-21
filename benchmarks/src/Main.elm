port module Main exposing (main)

import Markdown
import Markdown.Block exposing (ParseResult)
import Platform


port parseThis : (String -> msg) -> Sub msg


port parseResult : { blocks : Int } -> Cmd msg


type alias Model =
    ()


type Msg
    = Parse String


main : Program () Model Msg
main =
    Platform.worker
        { init = \_ -> ( (), Cmd.none )
        , update = update
        , subscriptions = \_ -> parseThis Parse
        }


update : Msg -> Model -> ( Model, Cmd Msg )
update (Parse source) _ =
    let
        result : ParseResult () ()
        result =
            Markdown.parse Nothing source
    in
    ( ()
    , parseResult { blocks = List.length result.blocks }
    )
