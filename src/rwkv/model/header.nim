## rwkv/model/header.nim — Low-level model header parsing.
##
## Reads the 24-byte rwkv.cpp file header straight off disk (no library load).
## This module has NO dependency on rwkv.nim to avoid circular imports.

type
  ModelHeader* = object
    magic*: uint32
    version*: uint32
    nVocab*: uint32
    nEmbed*: uint32
    nLayer*: uint32
    dataType*: uint32

const
  ModelMagic* = 0x67676d66'u32  # 24-byte header: 6 x LE u32

# rwkv.cpp data_type indexes (see rwkv_file_format.inc TYPE_*)
const
  DtypeFP32* = 0
  DtypeFP16* = 1
  DtypeQ4_0* = 2
  DtypeQ4_1* = 3
  DtypeQ5_0* = 4
  DtypeQ5_1* = 5
  DtypeQ8_0* = 6
  DtypeIQ4_NL* = 10
  DtypeIQ4_XS* = 11
  DtypeQ4_K* = 12
  DtypeQ5_K* = 13
  DtypeQ6_K* = 14
  DtypeQ8_K* = 15
  FirstQuantType* = 2           # Q4_0 onwards are all quantized

# Bytes per parameter by data type
const
  BytesPerParamFP32* = 4
  BytesPerParamFP16* = 2
  BytesPerParamQ4* = 0.5      # 4-bit quantization
  BytesPerParamQ5* = 0.625    # 5-bit quantization
  BytesPerParamQ6* = 0.75     # 6-bit quantization
  BytesPerParamQ8* = 1.0      # 8-bit quantization

proc readModelHeader*(path: string): ModelHeader =
  ## Reads the 24-byte rwkv.cpp file header straight off disk (no library load).
  result.dataType = uint32.high
  var f: File
  if not f.open(path, fmRead):
    return
  defer: f.close()
  var b: array[24, uint8]
  if f.readBytes(b, 0, 24) != 24:
    return
  template u32le(off: int): uint32 =
    uint32(b[off]) or (uint32(b[off + 1]) shl 8) or
    (uint32(b[off + 2]) shl 16) or (uint32(b[off + 3]) shl 24)
  result.magic = u32le(0)
  result.version = u32le(4)
  result.nVocab = u32le(8)
  result.nEmbed = u32le(12)
  result.nLayer = u32le(16)
  result.dataType = u32le(20)

proc isValidHeader*(h: ModelHeader): bool = h.magic == ModelMagic
proc isRawModel*(h: ModelHeader): bool = isValidHeader(h) and h.dataType < FirstQuantType
proc isQuantized*(h: ModelHeader): bool = isValidHeader(h) and h.dataType >= FirstQuantType

proc bytesPerParam*(dataType: uint32): float =
  ## Returns bytes per parameter for the given data type.
  case dataType
  of DtypeFP32: return BytesPerParamFP32.float
  of DtypeFP16: return BytesPerParamFP16.float
  of DtypeQ4_0, DtypeQ4_1, DtypeIQ4_NL, DtypeQ4_K: return BytesPerParamQ4
  of DtypeQ5_0, DtypeQ5_1, DtypeQ5_K: return BytesPerParamQ5.float
  of DtypeQ6_K: return BytesPerParamQ6.float
  of DtypeQ8_0, DtypeQ8_K:
    if dataType == DtypeQ8_K:
      # Q8_K is a special format, use Q8_0 as approximation
      return BytesPerParamQ8.float
    else:
      return BytesPerParamQ8.float
  else: return BytesPerParamFP16.float  # fallback

proc modelSizeBytes*(h: ModelHeader): int64 =
  ## Calculates the model size in bytes from the header.
  ## Formula: nEmbed^2 * nLayer * 3 + nEmbed * nVocab (approximate for RWKV)
  let embed = int64(h.nEmbed)
  let layer = int64(h.nLayer)
  let vocab = int64(h.nVocab)
  let bpp = bytesPerParam(h.dataType)
  # RWKV model size approximation: (3 * n_layer + 1) * n_embed^2 + n_embed * n_vocab
  let paramCount = int64(float32(3 * layer + 1) * float32(embed * embed) + float32(embed * vocab))
  result = int64(float32(paramCount) * bpp)

proc modelSizeMiB*(h: ModelHeader): int =
  ## Returns model size in MiB.
  int(modelSizeBytes(h) div (1024 * 1024))
