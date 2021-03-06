{-# LANGUAGE FlexibleContexts       #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE RecordWildCards        #-}
{-# LANGUAGE TemplateHaskell        #-}
{-# LANGUAGE TypeFamilies           #-}
{-# LANGUAGE ViewPatterns           #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Plots.Axis.ColourBar
-- Copyright   :  (C) 2016 Christopher Chalmers
-- License     :  BSD-style (see the file LICENSE)
-- Maintainer  :  Christopher Chalmers
-- Stability   :  experimental
-- Portability :  non-portable
--
-- Options for rendering a colour bar, either attached to an axis or
-- rendered separately.
--
-- To change the colour map used for the colour bar see
-- 'Plots.Style.axisColourMap' from "Plots.Style".
--
----------------------------------------------------------------------------
module Plots.Axis.ColourBar
 ( -- * The colour bar
   ColourBar
 , HasColourBar (..)
 , defColourBar

   -- ** Rendering options
 , gradientColourBar
 , pathColourBar

   -- * Rendering colour bars
 , renderColourBar
 , addColourBar
 ) where

import           Data.Bool               (bool)
import qualified Data.Foldable           as F
import           Data.Typeable
import           Diagrams.Core.Transform (fromSymmetric)
import           Diagrams.Prelude        hiding (gap)
import           Diagrams.TwoD.Text
import           Plots.Axis.Grid
import           Plots.Axis.Labels
import           Plots.Axis.Ticks
import           Plots.Style
import           Plots.Types
import           Plots.Util

-- | Options for drawing a colour bar. Note that for an axis, the
--   'ColourMap' is stored in the 'AxisStyle'. These options are for
--   other aspects of the bar, not the colours used.
data ColourBar b n = ColourBar
  { cbPlacement  :: Placement
  , cbVisible    :: Bool
  , cbTicks      :: MajorTicks V2 n
  , cbGridLines  :: MajorGridLines V2 n
  , cbTickLabels :: TickLabels b V2 n
  , cbDraw       :: ColourMap -> QDiagram b V2 n Any
  , cbWidth      :: n
  , cbLengthFun  :: n -> n
  , cbGap        :: n
  , cbStyle      :: Style V2 n
  }

type instance V (ColourBar b n) = V2
type instance N (ColourBar b n) = n

-- | The default colour bar.
defColourBar :: (Renderable (Text n) b, Renderable (Path V2 n) b, TypeableFloat n)
             => ColourBar b n
defColourBar = ColourBar
  { cbPlacement   = rightMid
  , cbVisible     = False
  , cbTicks       = def
  , cbGridLines   = def
  , cbTickLabels  = def
  , cbDraw        = gradientColourBar
  , cbWidth       = 20
  , cbLengthFun   = id
  , cbGap         = 20
  , cbStyle       = mempty
  }

class HasColourBar a b | a -> b where
  -- | Lens onto the 'ColourBar'.
  colourBar :: Lens' a (ColourBar b (N a))

  -- | How to draw the colour bar. Expects a 1 by 1 box with the
  --   gradient going from left to right, without an outline with origin
  --   in the middle of the left side. See 'gradientColourBar' and
  --   'pathColourBar'.
  --
  --   The colour map this function recieves it given by
  --   'Plots.Style.axisColourMap' from "Plots.Style"
  --
  --   Default is 'gradientColourBar'.
  colourBarDraw :: Lens' a (ColourMap -> QDiagram b V2 (N a) Any)
  colourBarDraw = colourBar . lens cbDraw (\c a -> c {cbDraw = a})

  -- | The width (orthogonal to the colour bar direction) of the colour
  --   bar.
  --
  --   'Default' is @20@.
  colourBarWidth :: Lens' a (N a)
  colourBarWidth = colourBar . lens cbWidth (\c a -> c {cbWidth = a})

  -- | Set the length of the colour bar given the length of the axis the
  --   colour bar is aligned to.
  --
  --   'Default' is 'id'.
  colourBarLengthFunction :: Lens' a (N a -> N a)
  colourBarLengthFunction = colourBar . lens cbLengthFun (\c a -> c {cbLengthFun = a})

  -- | Gap between the axis and the colour bar (if rendered with an axis).
  --
  --   'Default' is @20@.
  colourBarGap :: Lens' a (N a)
  colourBarGap = colourBar . lens cbGap (\c a -> c {cbGap = a})

  -- | Style used for the outline of a colour bar.
  colourBarStyle :: Lens' a (Style V2 (N a))
  colourBarStyle = colourBar . lens cbStyle (\c a -> c {cbStyle = a})

instance HasColourBar (ColourBar b n) b where
  colourBar = id

instance HasGap (ColourBar b n) where
  gap = colourBarGap

instance HasPlacement (ColourBar b n) where
  placement = lens cbPlacement (\c p -> c {cbPlacement = p})

-- This is a kinda strange instance that I'm using as an experiment.
-- The Orientation depends on the 'Placement' of the colour bar.
--
-- \ N /
-- W * E
-- / S \
--
-- if it's on the east or west it's vertical, north or south it's
-- horizontal. If it's on a border it uses whatever way the gap
-- direction points. If the direction is parallel to the direction it's
-- on, we arbitrary choose pointing NE or SE to be vertical, NW and SW
-- to be horizontal (just for completeness, having such gap directions
-- doesn't make much sense).
--
-- When reversing the direction we map E <-> S and N <-> W. The gap
-- direction is rotated to match the new position and anchor has its x
-- and y flipped.
instance HasOrientation (ColourBar b n) where
  orientation = lens getter setter where

    getter p
      | north     || south = Horizontal
      | east      || west  = Vertical
      | northEast          = bool Horizontal Vertical (dx > dy)
      | southEast          = bool Horizontal Vertical (dx > -dy)
      | southWest          = bool Horizontal Vertical (dx < dy)
      | northWest          = bool Horizontal Vertical (dx < -dy)
      | otherwise          = error $ "internal error: get colourBar orientation: "
                                  ++ show (p ^. placement)
      where
        V2 x y   = p ^. placementAt
        V2 dx dy = p ^. gapDirection . _Dir
        north = x < y && x > (-y)
        east  = x > y && x > (-y)
        south = x > y && x < (-y)
        west  = x < y && x < (-y)
        northEast = x ==   y  && x > 0
        southEast = x == (-y) && x > 0
        southWest = x ==   y  && x < 0
        northWest = x == (-y) && x < 0

    setter p o
      | getter p == o = p
      | otherwise     = p & placementAt        %~ flipX_Y
                          & placementAnchor    %~ flipX_Y
                          & gapDirection ._Dir %~ flipX_Y

instance Typeable n => HasStyle (ColourBar b n) where
  applyStyle sty = colourBarStyle %~ applyStyle sty

instance Functor f => HasMajorTicks f (ColourBar b n) where
  majorTicks = lens cbTicks (\c a -> c {cbTicks = a})

instance Functor f => HasTickLabels f (ColourBar b n) b where
  tickLabel = lens cbTickLabels (\c a -> c {cbTickLabels = a})

instance HasVisibility (ColourBar b n) where
  visible = lens cbVisible (\c a -> c {cbVisible = a})

-- | Add a colour bar to an object, using the bounding box for the object.
addColourBar
  :: (TypeableFloat n, Renderable (Path V2 n) b)
  => BoundingBox V2 n -- ^ bounding box to place against
  -> ColourBar b n --
  -> ColourMap
  -> (n,n)
  -> QDiagram b V2 n Any
addColourBar bb cbo@ColourBar {..} cm bnds
  | cbVisible = placeAgainst bb cbPlacement cbGap cb
  | otherwise = mempty
  where
    cb       = renderColourBar cbo cm bnds l
    -- the length used for the rendered colour bar
    l = cbLengthFun bbl
    -- the length of the side of the bounding box the colour bar will be
    -- against
    bbl = orient cbo bx by
    V2 bx by = boxExtents bb

-- | Render a colour bar by it's self at a given width. Note this
--   ignores 'colourBarGap' and 'colourBarLengthFunction'.
renderColourBar
  :: (TypeableFloat n, Renderable (Path V2 n) b)
  => ColourBar b n -- ^ options for colour bar
  -> ColourMap     -- ^ map to use
  -> (n,n)         -- ^ bounds of the values on the colour bar
  -> n             -- ^ length of the colour bar
  -> QDiagram b V2 n Any
renderColourBar cb@ColourBar {..} cm bnds@(lb,ub) l
  | cbVisible = bar # xy id reflectY
                    # o id (reflectY . _reflectX_Y)

             <> tLbs
  | otherwise = mempty

  where
  -- These functions deal with the different cases for the position of
  -- the colour bar so that the ticks and labels are on the outside of
  -- the axis and the bar horizontal/vertical depending on which side
  -- the bar is on.
  o, xy :: a -> a -> a
  o      = orient cb
  xy a b = if let V2 x y = cb^.placementAt in x > y
             then a else b

  w   = cbWidth
  -- move a value on the colour bar such that
  --   f lb = -l/2
  --   f ub =  l/2
  -- so it ligns up with the colour bar
  f x = (x - (ub + lb)/2) / (ub - lb) * l
  inRange x = x >= lb && x <= ub

  bar = outline <> tks <> gLines <> colours

  -- the outline
  outline = rect l w # applyStyle (cbStyle & _fillTexture .~ _AC ## transparent)

  -- displaying the colour map
  colours = cbDraw cm # centerXY # scaleX l # scaleY w

  -- the ticks
  tickXs  = view majorTicksFunction cbTicks bnds
  tickXs' = filter inRange tickXs
  tks
    | cbTicks ^. hidden = mempty
    | otherwise = F.foldMap (\x -> aTick # translate (V2 (f x) (-w/2))) tickXs'
  aTick = someTick (cbTicks ^. majorTicksAlignment) (cbTicks ^. majorTicksLength)

  someTick tType d = case tType of
    TickSpec (fromRational -> aa) (fromRational -> bb)
             -> mkP2 0 (-d*bb) ~~ mkP2 0 (d*aa)
    AutoTick -> mkP2 0 (-d)    ~~ mkP2 0 d

  -- grid lines
  gridXs = filter inRange $ view majorGridLinesFunction cbGridLines tickXs bnds
  gLines
    | cbGridLines ^. hidden = mempty
    | otherwise             = F.foldMap mkGridLine gridXs
                                # strokePath
                                # applyStyle (cbGridLines ^. majorGridLinesStyle)
  mkGridLine x = mkP2 (f x) (-w/2) ~~ mkP2 (f x) (w/2)

  -- tick labels
  tickLabelXs = view tickLabelFunction cbTickLabels tickXs' bnds
  tLbs
    | cbTickLabels ^. hidden = mempty
    | otherwise              = F.foldMap drawTickLabel tickLabelXs
  drawTickLabel (x,label) =
    view tickLabelTextFunction cbTickLabels tAlign label
      # translate v
      # applyStyle (cbTickLabels ^. tickLabelStyle)
        where v = V2 (f x) (- w/2 - view tickLabelGap cbTickLabels)
                    # xy id (_y %~ negate)
                    # o id ((_y %~ negate) . flipX_Y)

  tAlign = o (xy (BoxAlignedText 0.5 1) (BoxAlignedText 0.5 0))
             (xy (BoxAlignedText 0 0.5) (BoxAlignedText 1 0.5))

-- > import Plots
-- > gradientColourBarExample = gradientColourBar viridis # scaleX 20
-- > pathColourBarExample = pathColourBar 10 viridis # scaleX 20

-- | The colour bar generated by a gradient texture. The final diagram
--   is 1 by 1, with origin at the middle of the left side. This can be
--   used as the 'colourBarDraw' function.
--
--   This may not be supported by all backends.
--
--   <<diagrams/src_Plots_Axis_ColourBar_gradientColourBarExample.svg#diagram=gradientColourBarExample&width=600>>
gradientColourBar :: (TypeableFloat n, Renderable (Path V2 n) b) => ColourMap -> QDiagram b V2 n Any
gradientColourBar cm =
  rect 1 1
    # fillTexture grad
    # lw none
  where
    stops = map (\(x,c) -> GradientStop (SomeColor c) (fromRational x)) (colourList cm)
    grad  = defaultLG & _LG . lGradStops .~ stops

-- | Construct a colour bar made up of @n@ solid square paths. The final
--   diagram is 1 by 1, with origin at the middle of the left side. This
--   can be used as the 'colourBarDraw' function.
--
--   <<diagrams/src_Plots_Axis_ColourBar_pathColourBarExample.svg#diagram=pathColourBarExample&width=600>>
pathColourBar :: (TypeableFloat n, Renderable (Path V2 n) b)
              => Int -> ColourMap -> QDiagram b V2 n Any
pathColourBar n cm = ifoldMap mkR xs
  where
    mkR i x = rect d' 1
                # alignR
                # fc (cm ^. ixColourR (x - 1/(2*fromIntegral n)))
                # translateX (fromRational x)
                # lw none
      where
        -- Some vector viewers don't render touching blocks of colour
        -- correctly. To solve this we overlap by half a bar length for
        -- all except the first bar (which is the one on top).
        d' | i == 0 = d
           | otherwise  = d*1.5

    xs = tail (enumFromToN 0 1 n)
    d  = 1 / fromIntegral n

flipX_Y :: Num n => V2 n -> V2 n
flipX_Y (V2 x y) = V2 (-y) (-x)

_reflectionX_Y :: (Additive v, R2 v, Num n) => Transformation v n
_reflectionX_Y = fromSymmetric $ (_xy %~ flipX_Y) <-> (_xy %~ flipX_Y)

_reflectX_Y :: (InSpace v n t, R2 v, Transformable t) => t -> t
_reflectX_Y = transform _reflectionX_Y

