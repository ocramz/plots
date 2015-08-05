{-# LANGUAGE CPP                       #-}
{-# LANGUAGE DeriveDataTypeable        #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE FunctionalDependencies    #-}
{-# LANGUAGE MultiParamTypeClasses     #-}
{-# LANGUAGE RankNTypes                #-}
{-# LANGUAGE RecordWildCards           #-}
{-# LANGUAGE TypeFamilies              #-}

module Plots.Types.Smooth
  (

-- * GSmoothPlot plot
     GSmoothPlot
  , _SmoothPlot

  , SmoothPlot
  , mkSmoothPlotOf
  , mkSmoothPlot

  , drawTrail
  , testXY

  ) where

import           Control.Lens                    hiding (lmap, none, transform,
                                                  ( # ))
import qualified Data.Foldable                   as F
import           Data.Typeable
import           Data.List
import           Data.Function

import           Diagrams.Prelude
import           Diagrams.Trail

import           Diagrams.Coordinates.Isomorphic

import           Plots.Themes
import           Plots.Types

data GSmoothPlot v n a = forall s. GSmoothPlot
  { sData :: s
  , sFold :: Fold s a
  , sPos  :: a -> Point v n
  , sMeth :: [P2 n] -> (Located (Trail' Loop V2 n) ,Located (Trail' Line V2 n))
  , sLine :: Bool
-- change P2 n to Point v n 
-- Look at Histogram.hs for more details
-- Extend Bool
  } deriving Typeable

type instance V (GSmoothPlot v n a) = v
type instance N (GSmoothPlot v n a) = n

instance (Metric v, OrderedField n) => Enveloped (GSmoothPlot v n a) where
  getEnvelope GSmoothPlot {..} = foldMapOf (sFold . to sPos) getEnvelope sData

instance (Typeable a, Typeable b, TypeableFloat n, Renderable (Path V2 n) b)
    => Plotable (GSmoothPlot V2 n a) b where
  renderPlotable s GSmoothPlot {..} pp = 
               lp # stroke
                  # lw none
                  # applyBarStyle pp
                  # opacity 0.7
                  # transform t
            <> if sLine 
                then ln # transform t # stroke
--                        # applyLineStyle pp -- dont know why doesnt work 
--                        add easy options for linesize colour dashing opacity; same for fill
                else mempty
          where
            ps             = toListOf (sFold . to sPos . to (logPoint ls)) sData
            (lp, ln)       = sMeth ps
            t              = s ^. specTrans
            ls             = s ^. specScale

  defLegendPic GSmoothPlot {..} pp
      = square 5 # applyBarStyle pp

------------------------------------------------------------------------
-- Simple Smooth Plot
------------------------------------------------------------------------

type SmoothPlot v n = GSmoothPlot v n (Point v n)

mkSmoothPlot :: (PointLike v n p, F.Foldable f, Ord n, Floating n, Enum n, Num n)
              => f p -> SmoothPlot v n
mkSmoothPlot = mkSmoothPlotOf folded


mkSmoothPlotOf :: (PointLike v n p, Ord n, Floating n, Enum n, Num n)
                => Fold s p -> s -> SmoothPlot v n
mkSmoothPlotOf f a = GSmoothPlot
  { sData = a
  , sFold = f . unpointLike
  , sPos  = id
  , sMeth = testXY
  , sLine = True 
  }
  
_SmoothPlot :: (Plotable (SmoothPlot v n) b, Typeable b)
                   => Prism' (Plot b v n) (SmoothPlot v n)
_SmoothPlot = _Plot

---------- add more of this function - one for mean other for sum --
-- lm ---

testXY :: (Ord n, Floating n, Enum n) => [P2 n] -> (Located (Trail' Loop V2 n) ,Located (Trail' Line V2 n))
testXY ps = (lp, ln) 
            where 
            xpts = map fst (map unp2 ps)
            ypts = map snd (map unp2 ps)
            xmean = mean xpts
            ymean = mean ypts
            xmin = minimum xpts
            ymin = minimum ypts
            xmax = maximum xpts
            ymax = maximum ypts
            h    = 0.3 * (ymax - ymean)
            (m, b) = simpleLinear (map unp2 ps)
            y1   = predict xmin (m, b)
            y2   = predict xmax (m, b)
            lp   = (fromVertices (map p2 [(xmin, y1-h),(xmax, y2-h),(xmax, y2+h),(xmin, y1+h)])) #mapLoc closeLine
            ln   = fromVertices (map p2 [(xmin, y1),(xmax, y2)])
                                      
                                                                                
mean :: (Fractional a) => [a] -> a                                              
mean xs = sum(xs) / fromIntegral (length xs)                                    
                                                                                
meanOfPoints :: (Fractional a) => [(a, a)] -> (a, a)                            
meanOfPoints x = let (a, b) = unzip x                                           
                 in (mean a, mean b)                                            
                                                                                
correlation :: (Floating a) => [(a, a)] -> a                                    
correlation xs = xy / sqrt (xx * yy)                                            
                 where xy = sum $ map (\x -> fst x * snd x) xs                  
                       xx = sum $ map (\x -> fst x ^ 2) xs                      
                       yy = sum $ map (\x -> snd x ^ 2) xs                      
                                                                                
stdDev :: Floating a => [a] -> a                                                
stdDev xs = sqrt $ sum (xMinusMean xs) / lengthList                             
            where mu = mean xs                                                  
                  xMinusMean = map (\x -> (x - mu) ^ 2)                         
                  lengthList = fromIntegral (length xs)                         
                                                                                
stdDevOfPoints :: (Floating a) => [(a, a)] -> (a, a)                            
stdDevOfPoints x = let (a, b) = unzip x                                         
                   in (stdDev a, stdDev b)                                      
                                                                                
simpleLinear :: (Ord n, Floating n, Enum n) => [(n , n)] -> (n, n)                            
simpleLinear xs = (m, b)                                                      
                  where r = correlation xs                                      
                        (sx, sy) = stdDevOfPoints xs                            
                        (mx, my) = meanOfPoints xs                              
                        m = r * sy / sx                                         
                        b = my - m * mx                                         
                                                                                
predict :: (Ord n, Floating n, Enum n) => n -> (n, n) -> n                                   
predict x (m, b) = b + m * x  

----------------------------------------------------------------------------
-- Smooth Lenses
----------------------------------------------------------------------------

class HasSmooth a v n d | a -> v n, a -> d where
  smooth :: Lens' a (GSmoothPlot v n d)

  drawTrail :: Lens' a Bool
  drawTrail =  smooth . lens sLine (\s b -> (s {sLine = b}))

instance HasSmooth (GSmoothPlot v n d) v n d where
  smooth = id

instance HasSmooth (PropertiedPlot (GSmoothPlot v n d) b) v n d where
  smooth = _pp
