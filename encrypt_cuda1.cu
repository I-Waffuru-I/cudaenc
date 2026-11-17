#include "parameters.h"
#include <__clang_cuda_builtin_vars.h>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cuda.h>
#include <iostream>
#include <stdint.h>
#include <sys/types.h>
#include <vector>

__global__ void someKernel(uint8_t *src, uint8_t *keys) {
  __shared__ uint8_t s[1024];
  uint8_t *chunk = src + blockIdx.x * 1024;
  uint8_t *keychunk = keys + blockIdx.x * 1024;

  // thread t kopieert bytes t + blockDim.x*k
  // met 64 threads zal elke thread 1024/64 bytes kopieren
  // TODO CHECKEN: ik denk geen overlap?
  for (int i = threadIdx.x; i < 1024; i += blockDim.x)
    s[i] = chunk[i];

  __syncthreads();

  uint8_t *output = &s[0];
  uint8_t *tmp = &s[512];

  // have each thread xor one thing? 
  for (int i = threadIdx.x; i < 512; i += blockDim.x)
    tmp[i] = chunk[i] ^ keychunk[i];

  // output, tmp are arrays of 512 bytes
  // tmp = input XOR key
  // for i in 0 ... 511:
  //         tmp[i] = substitutionTable[tmp[i]] # substitution
  // for i in 0 ... 511:
  //         j = permutationTable[i] # permutation
  //         output[j] = tmp[i]
  // return output;
}

std::vector<uint8_t> encrypt_cuda(std::vector<uint8_t> plaintext,
                                  std::vector<std::vector<uint8_t>> roundkeys,
                                  bool decrypt = false) {
  // TODO check assignment
  auto output = std::vector<uint8_t>(plaintext.size());

  size_t startKey, stopKey;
  if (decrypt) {
    startKey = 0;
    stopKey = roundkeys.size() - 1;
  } else {
    stopKey = 0;
    startKey = roundkeys.size() - 1;
  }

  size_t keysnum = roundkeys.size();
  size_t keysize = roundkeys[0].size();
  for (auto k : roundkeys)
    if (k.size() != keysize) {
      printf("Keys don't have matching length");
      exit(1);
    }
  std::vector<uint8_t> flatkeys(keysnum * keysize);
  for (size_t r = 0; r < keysnum; r++) {
    // reverse order als decrypt
    size_t src = decrypt ? keysnum - 1 - r : r;
    std::copy(roundkeys[src].begin(), roundkeys[src].end(),
              flatkeys.begin() + r * keysize);
  }

  uint8_t *src_ptr, *keys_ptr;
  size_t numparts = plaintext.size() / 1024;
  cudaMalloc(&src_ptr, sizeof(uint8_t) * plaintext.size());
  cudaMalloc(&keys_ptr, sizeof(uint8_t) * flatkeys.size());

  cudaMemcpy(src_ptr, plaintext.data(), plaintext.size() * sizeof(uint8_t),
             cudaMemcpyHostToDevice);
  cudaMemcpy(keys_ptr, flatkeys.data(), flatkeys.size() * sizeof(uint8_t),
             cudaMemcpyHostToDevice);

  for (size_t part = 0; part < numparts; part++) {
    // firstPart = copy 512 bytes from plaintext[b*1024 + 0]
    // secondPart = copy 512 bytes from plaintext[b*1024 + 512]
    // for k in startKey ... stopKey:
    //         key = roundkeys[k]
    //         tmp = runF(secondPart, key)
    //         firstPart = firstPart XOR tmp;
    //         if k != stopKey: # don't swap last time
    //                 swap firstPart and secondPart
    // copy firstPart to output[b*1024 + 0]
    // copy secondPart to output[b*1024 + 512]
  }

  return output;
}

/*
output = array of same length as plaintext
if not decrypt:
        startKey = 0
        stopKey = len(roundkeys)-1
else:
        startKey = len(roundkeys)-1
        stopKey = 0
# Each 1024-byte part will be encrypted/decrypted independently
partsToEncrypt = plaintext/1024
for b in 0 ... (partsToEncrypt-1):
        firstPart = copy 512 bytes from plaintext[b*1024 + 0]
        secondPart = copy 512 bytes from plaintext[b*1024 + 512]
        for k in startKey ... stopKey:
                key = roundkeys[k]
                tmp = runF(secondPart, key)
                firstPart = firstPart XOR tmp;
                if k != stopKey: # don't swap last time
                        swap firstPart and secondPart
        copy firstPart to output[b*1024 + 0]
        copy secondPart to output[b*1024 + 512]


def runF(input, key): # both arrays of 512 bytes
        output, tmp are arrays of 512 bytes
        tmp = input XOR key
        for i in 0 ... 511:
                tmp[i] = substitutionTable[tmp[i]] # substitution
        for i in 0 ... 511:
                j = permutationTable[i] # permutation
                output[j] = tmp[i]
        return output;



*/
