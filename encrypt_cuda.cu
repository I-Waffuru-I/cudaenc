#include "parameters.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <vector>

/* swaps */
__device__ void
runF(const uint8_t *right,   // shared, 512 bytes (current right half)
     const uint8_t *rk,      // global, 512 bytes (this round's key)
     uint8_t *out,           // shared, 512 bytes (output)
     const uint8_t *s_sbox,  // shared, 256 bytes
     const uint16_t *perm) { // global, 512 entries
  size_t i = threadIdx.x;
  size_t randIndex = perm[i];
  uint8_t xo = right[i] ^ rk[i];
  // sb[r ^ rk] != sb[r] ^ sb[rk], betere random encryptie denk ik?
  uint8_t tmp = s_sbox[xo];
  out[randIndex] = tmp;
  __syncthreads();
}

__global__ void
encryptKernel(const uint8_t *__restrict__ in, // device, plaintext.size() bytes
              uint8_t *__restrict__ out,      // device, plaintext.size() bytes
              const uint8_t *__restrict__ keys,  // device, rounds * 512 bytes
              const uint8_t *__restrict__ sbox,  // device, 256 bytes
              const uint16_t *__restrict__ perm, // device, 512 entries
              int rounds) {
  __shared__ uint8_t s[3 * 512 + 256];
  uint8_t *bufA = &s[0];
  uint8_t *bufB = &s[512];
  uint8_t *scratch = &s[1024];
  uint8_t *sbx = &s[1536];

  // prep
  uint8_t *L = bufA;
  uint8_t *R = bufB;
  size_t part = blockIdx.x;
  size_t i = threadIdx.x;
  size_t randIndex = perm[i];

  for (size_t j = i; j < 256; j += blockDim.x) {
    sbx[j] = sbox[j];
  }
  L[i] = in[part * 1024 + i];
  R[i] = in[part * 1024 + 512 + i];
  __syncthreads();

  // moesten de laatste skippen vgm?
  for (size_t r = 0; r < rounds; r++) {
    const uint8_t *roundkey = keys + r * 512;
    uint8_t xo = R[i] ^ roundkey[i];
    // sb[r ^ rk] != sb[r] ^ sb[rk], betere random
    uint8_t tmp = sbx[xo];
    scratch[randIndex] = tmp;
    // sync writing
    __syncthreads();

    L[i] ^= scratch[i];
    // finished mixing in scratch
    __syncthreads();
    if (r != rounds - 1) {
      uint8_t *t = L;
      L = R;
      R = t;
    }
  }
  out[part * 1024 + i] = L[i];
  out[part * 1024 + 512 + i] = R[i];
}

std::vector<uint8_t> encrypt_cuda(std::vector<uint8_t> plaintext,
                                  std::vector<std::vector<uint8_t>> roundkeys,
                                  bool decrypt = false) {

  auto output = std::vector<uint8_t>(plaintext.size());

  size_t startKey = decrypt ? 0 : roundkeys.size() - 1;
  size_t stopKey = decrypt ? roundkeys.size() - 1 : 0;

  size_t keysnum = roundkeys.size();
  size_t keysize = roundkeys[0].size();
  for (auto k : roundkeys) {
    if (k.size() != keysize) {
      printf("Keys don't have matching length");
      exit(1);
    }
  }

  std::vector<uint8_t> flatkeys(keysnum * keysize);
  for (size_t r = 0; r < keysnum; r++) {
    // reverse order als decrypt
    size_t src = decrypt ? keysnum - 1 - r : r;
    std::copy(roundkeys[src].begin(), roundkeys[src].end(),
              flatkeys.begin() + r * keysize);
  }

  uint8_t *din, *dout, *dkeys, *dsbox;
  uint16_t *dperm;
  // ja duh, das waar ge alles in/uit leest
  cudaMalloc(&din, plaintext.size() * sizeof(uint8_t));
  cudaMalloc(&dout, plaintext.size() * sizeof(uint8_t));
  // 512 per key
  cudaMalloc(&dkeys, flatkeys.size() * sizeof(uint8_t) * 512);
  cudaMalloc(&dsbox, 256 * sizeof(uint8_t));
  cudaMalloc(&dperm, 512 * sizeof(uint16_t));

  cudaMemcpy(din, plaintext.data(), plaintext.size() * sizeof(uint8_t),
             cudaMemcpyHostToDevice);
  cudaMemcpy(dkeys, flatkeys.data(), flatkeys.size() * sizeof(uint8_t),
             cudaMemcpyHostToDevice);
  cudaMemcpy(dsbox, substitutionTable, 256 * sizeof(uint8_t),
             cudaMemcpyHostToDevice);
  cudaMemcpy(dperm, permutationTable, 512 * sizeof(uint16_t),
             cudaMemcpyHostToDevice);

  //
  size_t numParts = plaintext.size() / 1024;
  encryptKernel<<<numParts, 512, 3 * 512 + 256>>>(din, dout, dkeys, dsbox,
                                                  dperm, roundkeys.size());
  cudaDeviceSynchronize();
  cudaError_t err = cudaGetLastError();
  if (err != cudaSuccess) {
    std::cout << cudaGetErrorString(err) << std::endl;
  }

  cudaMemcpy(output.data(), dout, plaintext.size() * sizeof(uint8_t),
             cudaMemcpyDeviceToHost);

  cudaFree(din);
  cudaFree(dout);
  cudaFree(dkeys);
  cudaFree(dsbox);
  cudaFree(dperm);

  return output;
}
