module SourceLocation exposing
    ( Position, Region
    , ComparableRegion, toComparableRegion, fromComparableRegion
    , placeholderRegion
    )

{-| 1-based source positions and regions for AST nodes.
-}


type alias Position =
    { row : Int
    , col : Int
    }


type alias Region =
    { start : Position
    , end : Position
    }


type alias ComparableRegion =
    ( ( Int, Int ), ( Int, Int ) )


toComparableRegion : Region -> ComparableRegion
toComparableRegion r =
    ( ( r.start.row, r.start.col ), ( r.end.row, r.end.col ) )


fromComparableRegion : ComparableRegion -> Region
fromComparableRegion ( ( sr, sc ), ( er, ec ) ) =
    { start = { row = sr, col = sc }
    , end = { row = er, col = ec }
    }


{-| Sentinel region (row 0, col 0) indicating position not yet computed.
Real regions start at row 1, col 1.
-}
placeholderRegion : Region
placeholderRegion =
    { start = { row = 0, col = 0 }
    , end = { row = 0, col = 0 }
    }
