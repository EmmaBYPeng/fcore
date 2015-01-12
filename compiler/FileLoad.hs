{-# LANGUAGE TemplateHaskell #-}
module Main where

import System.IO
import System.Process
import System.Directory			(doesFileExist, getDirectoryContents)
import System.FilePath			(takeFileName)
import System.TimeIt			(timeIt)

import Data.Time			(getCurrentTime, diffUTCTime)

import Translations
import FileIO
import JavaUtils
import StringPrefixes			(namespace)
import qualified Data.ByteString as B
import Data.FileEmbed (embedFile)
import System.Directory (getTemporaryDirectory)
import System.FilePath ((</>))

runtimeBytes :: B.ByteString
runtimeBytes = $(embedFile "runtime/runtime.jar")

writeRuntimeToTemp :: IO ()
writeRuntimeToTemp =
  do tempdir <- getTemporaryDirectory
     let tempFile = tempdir </> "runtime.jar"
     B.writeFile tempFile runtimeBytes

testCasesPath = "testsuite/tests/run-pass/"

initReplEnv ::[String] -> IO ()
initReplEnv xs =  do
     cp <- getClassPath
     let p = (proc "java" ["-cp", cp, (namespace ++ "FileServer"), cp])
                  {std_in = CreatePipe, std_out = CreatePipe}
     (Just inP, Just outP, _, proch) <- createProcess p
     hSetBuffering inP NoBuffering
     hSetBuffering outP NoBuffering
     loadFile inP outP [Naive] compileN xs
     loadFile inP outP [Naive, Apply] compileAO xs
     loadFile inP outP [Naive, Stack] compileSN xs
     terminateProcess proch

loadFile :: Handle -> Handle -> [TransMethod] -> Compilation -> [String] -> IO ()
loadFile inP outP method opt xs = do
    putStrLn "-------------------------------------"
    putStrLn ("Compileation Option: " ++ show (method))
    loadAll inP outP method opt xs
   
loadAll ::  Handle -> Handle -> [TransMethod] -> Compilation -> [String] -> IO ()
loadAll _ _ _ _ [] = return () 
loadAll inP outP method opt (x:xs) = do
    putStrLn ("Running " ++ (takeFileName x))
    send inP (0, opt, method) False x
    receiveMsg outP
    loadAll inP outP method opt xs 
  
fileExist :: String -> IO ()
fileExist name = do
	exist <- doesFileExist name
	if (exist) 
	  then return ()
	  else fileExist name
	
addFilePath :: [FilePath] -> [FilePath]
addFilePath [] = []
addFilePath (x:xs) = (testCasesPath ++ x) : (addFilePath xs)

main :: IO ()
main = do
  writeRuntimeToTemp
  start <- getCurrentTime
  xs <- getDirectoryContents testCasesPath
  let (x:y:ys) = xs 
  let zs = addFilePath ys
  putStrLn ""
  putStrLn ("Running test from " ++ testCasesPath)
  putStrLn "-------------------------------------"
  timeIt(initReplEnv zs)
  putStrLn "-------------------------------------"
  putStrLn "Finished!"
  end <- getCurrentTime
  putStrLn ("Running Time " ++ show (diffUTCTime end start))

 
