module Main (main) where

import BVH
import Camera
import Control.Concurrent.ParallelIO.Global (parallel)
import Data.List (genericLength, intercalate)
import GHC.Records (HasField (getField))
import Hitable
import Material
import Math
import Ray
import Vec3
import Worlds qualified

initialTRange :: (Float, Float)
initialTRange = (0.001, 1000000)

skyColor :: Vec3 -> Vec3
skyColor direction =
  let unitDirection = direction.normalize
      t = 0.5 * unitDirection.y + 1
   in lerp Worlds.white Worlds.blueSky t

rayColor :: Hitable a => Ray -> a -> IO Vec3
rayColor ray hitable =
  getColor ray hitable 0
  where
    getColor ray@(Ray {direction}) hitable depth =
      case hit ray initialTRange hitable of
        Just (HitRecord {u, v, point, normal, material}) -> do
          maybeRec <- material.scatter ray point normal
          let emitted = material.emit u v point
          case maybeRec of
            Just (ScatterRecord {scattered, attenuation})
              | depth < 50 -> do
                  c <- getColor scattered hitable (depth + 1)
                  return $ emitted + c * attenuation
            _ -> return $ emitted
        Nothing ->
          return $ skyColor direction

average :: Fractional a => [a] -> a
average xs = (sum xs) / genericLength xs

gammaCorrection :: Vec3 -> Vec3
gammaCorrection = sqrt

colorForPixel :: Hitable a => Float -> Float -> Float -> Float -> Camera -> a -> IO Vec3
colorForPixel width height x y camera world =
  fmap (gammaCorrection . average) . parallel $ do
    subPixelX <- subPixelXs
    subPixelY <- subPixelYs
    let u = (x + subPixelX) / width
        v = (y + subPixelY) / height
    return $ do
      ray <- camera.getRay u v
      rayColor ray world

vecToColorStr :: Vec3 -> String
vecToColorStr (Vec3 r g b) =
  intercalate " " $
    show <$> clamp 0 255 <$> floor <$> (* 255.99) <$> [r, g, b]

{-
This is an interesting use case for the extra modularity lazy
languages brings. It looks like pixels computation are all defined
here as a List of IO string, but actually since Lists are lazy,
only the "iterable" procedure is created here, and pixels will
be evaluated as we iterate over the list. We don't need to deal
with this complexity in our code to make our program a stream
of IOs which only has a single pixel in memory at the time.
-}
pixels :: Hitable a => Float -> Float -> Camera -> a -> [IO String]
pixels width height camera world = do
  y <- reverse [0 .. height]
  x <- [0 .. (width - 1)]
  return $ vecToColorStr <$> colorForPixel width height x y camera world

writeImage :: Hitable a => Float -> Float -> Camera -> [a] -> IO ()
writeImage width height camera world = do
  putStrLn $ "P3\n" ++ show (floor width) ++ " " ++ show (floor height) ++ "\n255"
  tree <- createTree initialTRange world
  -- We use sequence_ because it discards the list values and the
  -- can be garbage collected after each pixel has been written to
  -- the disk.
  sequence_
    . fmap (>>= putStrLn)
    $ pixels width height camera tree

subPixelXs :: [Float]
subPixelXs = [0, 0.1 .. 1]

subPixelYs :: [Float]
subPixelYs = [0, 0.2 .. 1]

main :: IO ()
main = do
  let width = 150
      height = 100
      camera = Worlds.triangleCamera width height
  world <- Worlds.triangleWorld
  writeImage width height camera world
