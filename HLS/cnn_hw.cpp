#include "cnn.h"
#include <string.h>

// cnn.cpp icindeki asamalar
void cnn_core(const i8_t in[IN_LEN], int *cls, ap_int<64> logit_out[N_CLASS]);

extern "C" void cnn_hw(const int8_t *x_in, int32_t *y_out, int n_win) {
#pragma HLS INTERFACE m_axi     port=x_in  offset=slave bundle=gmem depth=2048
#pragma HLS INTERFACE m_axi     port=y_out offset=slave bundle=gmem depth=11
#pragma HLS INTERFACE s_axilite port=x_in  bundle=control
#pragma HLS INTERFACE s_axilite port=y_out bundle=control
#pragma HLS INTERFACE s_axilite port=n_win bundle=control
#pragma HLS INTERFACE s_axilite port=return bundle=control

  WIN_LOOP: for (int w = 0; w < n_win; w++) {
    i8_t local[IN_LEN];
    CP_IN: for (int i = 0; i < IN_LEN; i++) {
#pragma HLS PIPELINE II=1
      local[i] = (i8_t)x_in[(long)w*IN_LEN + i];
    }
    int cls; ap_int<64> lo[N_CLASS];
    cnn_core(local, &cls, lo);
    y_out[(long)w*(N_CLASS+1)] = (int32_t)cls;
    CP_OUT: for (int k = 0; k < N_CLASS; k++) {
#pragma HLS PIPELINE II=1
      y_out[(long)w*(N_CLASS+1) + 1 + k] = (int32_t)lo[k];
    }
  }
}
