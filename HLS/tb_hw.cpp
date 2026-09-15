#include <cstdio>
#include <cstdlib>
#include "cnn.h"
#include "test_data.h"
extern "C" void cnn_hw(const int8_t*, int32_t*, int);
int main() {
  int8_t  *x = (int8_t*) malloc((size_t)N_TEST*IN_LEN);
  int32_t *y = (int32_t*)malloc((size_t)N_TEST*(N_CLASS+1)*sizeof(int32_t));
  for (int n = 0; n < N_TEST; n++)
    for (int i = 0; i < IN_LEN; i++) x[(size_t)n*IN_LEN+i] = (int8_t)TEST_X[n][i];
  cnn_hw(x, y, N_TEST);
  int mc = 0, ml = 0;
  for (int n = 0; n < N_TEST; n++) {
    if (y[(size_t)n*(N_CLASS+1)] != GOLD_CLS[n]) mc++;
    for (int k = 0; k < N_CLASS; k++)
      if ((int64_t)y[(size_t)n*(N_CLASS+1)+1+k] != GOLD_LOGIT[n][k]) ml++;
  }
  printf("HW argmax mismatch: %d / %d\n", mc, N_TEST);
  printf("HW logit  mismatch: %d / %d\n", ml, N_TEST*N_CLASS);
  free(x); free(y);
  return (mc || ml) ? 1 : 0;
}
