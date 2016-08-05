{-# language ForeignFunctionInterface #-}
{-# language BangPatterns #-}
{-# language ViewPatterns #-}
{-# language FlexibleInstances #-}
module CodeGen.X86.FFI where

import Control.Monad
import Control.Exception (evaluate)
import Foreign
import Foreign.C.Types
import Foreign.ForeignPtr
import Foreign.ForeignPtr.Unsafe
import System.IO.Unsafe

import CodeGen.X86.Asm
import CodeGen.X86.CodeGen

-------------------------------------------------------

foreign import ccall "dynamic" callWord64           :: FunPtr Word64                -> Word64
foreign import ccall "dynamic" callWord32           :: FunPtr Word32                -> Word32
foreign import ccall "dynamic" callWord16           :: FunPtr Word16                -> Word16
foreign import ccall "dynamic" callWord8            :: FunPtr Word8                 -> Word8
foreign import ccall "dynamic" callBool             :: FunPtr Bool                  -> Bool
foreign import ccall "dynamic" callIOUnit           :: FunPtr (IO ())               -> IO ()
foreign import ccall "dynamic" callWord64_Word64    :: FunPtr (Word64 -> Word64)    -> Word64 -> Word64
foreign import ccall "dynamic" callPtr_Word64       :: FunPtr (Ptr a -> Word64)     -> Ptr a -> Word64

unsafeCallForeignPtr0 call p = unsafePerformIO $ evaluate (call (castPtrToFunPtr $ unsafeForeignPtrToPtr p)) <* touchForeignPtr p

unsafeCallForeignPtr1 call p a = unsafePerformIO $ evaluate (call (castPtrToFunPtr $ unsafeForeignPtrToPtr p) a) <* touchForeignPtr p

unsafeCallForeignPtrIO0 call p = call (castPtrToFunPtr $ unsafeForeignPtrToPtr p) <* touchForeignPtr p


class Callable a where unsafeCallForeignPtr :: ForeignPtr a -> a

instance Callable Word64                where unsafeCallForeignPtr = unsafeCallForeignPtr0 callWord64
instance Callable Word32                where unsafeCallForeignPtr = unsafeCallForeignPtr0 callWord32
instance Callable Word16                where unsafeCallForeignPtr = unsafeCallForeignPtr0 callWord16
instance Callable Word8                 where unsafeCallForeignPtr = unsafeCallForeignPtr0 callWord8
instance Callable Bool                  where unsafeCallForeignPtr = unsafeCallForeignPtr0 callBool
instance Callable (IO ())               where unsafeCallForeignPtr = unsafeCallForeignPtrIO0 callIOUnit
instance Callable (Word64 -> Word64)    where unsafeCallForeignPtr = unsafeCallForeignPtr1 callWord64_Word64
instance Callable (Ptr a -> Word64)     where unsafeCallForeignPtr = unsafeCallForeignPtr1 callPtr_Word64

-------------------------------------------------------

foreign import ccall "static stdlib.h memalign"   memalign :: CUInt -> CUInt -> IO (Ptr a)
foreign import ccall "static stdlib.h &free"      stdfree  :: FunPtr (Ptr a -> IO ())
foreign import ccall "static sys/mman.h mprotect" mprotect :: Ptr a -> CUInt -> Int -> IO Int

{-# NOINLINE compile #-}
compile :: Callable a => Code -> a
compile x = unsafeCallForeignPtr $ unsafePerformIO $ do
    let (bytes, fromIntegral -> size) = buildTheCode x
    arr <- memalign 0x1000 size
    _ <- mprotect arr size 0x7 -- READ, WRITE, EXEC
    forM_ [p | Right p <- bytes] $ uncurry $ pokeByteOff arr
    newForeignPtr stdfree arr

-------------------------------------------------------

foreign import ccall "wrapper" createPtrWord64_Word64 :: (Word64 -> Word64) -> IO (FunPtr (Word64 -> Word64))

class CallableHs a where createHsPtr :: a -> IO (FunPtr a)

instance CallableHs (Word64 -> Word64) where createHsPtr = createPtrWord64_Word64

hsPtr :: CallableHs a => a -> FunPtr a
hsPtr x = unsafePerformIO $ createHsPtr x


