#ifndef CNN_H
#define CNN_H
#include <ap_int.h>
#include "weights.h"

#define L1     ((IN_LEN + STRIDE - 1)/STRIDE)
#define L2_LEN ((L1 + STRIDE - 1)/STRIDE)
#define PAD1   (((L1-1)*STRIDE + C1_K - IN_LEN)/2)
#define PAD2   (((L2_LEN-1)*STRIDE + C2_K - L1)/2)

#ifndef UNROLL_C2
#define UNROLL_C2 1
#endif

#if (C2_COUT % UNROLL_C2) != 0
#error "UNROLL_C2 must divide C2_COUT"
#endif

typedef ap_int<8>           i8_t;
typedef ap_uint<A1_BITS>    a1_t;
typedef ap_uint<A2_BITS>    a2_t;
typedef ap_int<ACC1_W>      acc1_t;
typedef ap_int<ACC2_W>      acc2_t;
typedef ap_int<ACC1_W+20>   r1_t;
typedef ap_int<ACC2_W+20>   r2_t;
typedef ap_uint<GAP_W>      gap_t;
typedef ap_int<DACC_W>      dacc_t;
typedef ap_int<DMUL_W+8>    dmul_t;
typedef ap_uint<12>  o1_t;
typedef ap_uint<11>  o2_t;
typedef ap_int<14>   sidx_t;

void cnn_core(const i8_t in[IN_LEN], int *cls, ap_int<64> logit_out[N_CLASS]);
#endif
