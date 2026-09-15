#include "cnn.h"

static a1_t rq1(acc1_t acc, int co) {
  r1_t t = (r1_t)acc * (r1_t)M01[co] + (r1_t)B1[co] + ((r1_t)1 << (SH1-1));
  r1_t y = t >> SH1;
  const r1_t hi = ((r1_t)1 << A1_BITS) - 1;
  if (y < 0) y = 0; else if (y > hi) y = hi;
  return (a1_t)y;
}

static a2_t rq2(acc2_t acc, int co) {
  r2_t t = (r2_t)acc * (r2_t)M02[co] + (r2_t)B2[co] + ((r2_t)1 << (SH2-1));
  r2_t y = t >> SH2;
  const r2_t hi = ((r2_t)1 << A2_BITS) - 1;
  if (y < 0) y = 0; else if (y > hi) y = hi;
  return (a2_t)y;
}

static void load_in(const i8_t in[IN_LEN], i8_t buf[IN_LEN]) {
  LD: for (int i = 0; i < IN_LEN; i++) buf[i] = in[i];
}

static void conv1(const i8_t buf[IN_LEN], a1_t a1[L1][C1_COUT]) {
  o1_t o = 0; ap_uint<5> co = 0;
  C1_MAIN: for (int i = 0; i < L1*C1_COUT; i++) {
    acc1_t acc = 0;
    C1_K_L: for (int k = 0; k < C1_K; k++) {
      sidx_t t = (sidx_t)(o << 1) + (sidx_t)k - (sidx_t)PAD1;
      i8_t x = (t < 0 || t >= (sidx_t)IN_LEN) ? (i8_t)0 : buf[t];
      acc += (acc1_t)(x * W1[k][0][co]);
    }
    a1[o][co] = rq1(acc, co);
    if (co == C1_COUT-1) { co = 0; o++; } else { co++; }
  }
}

static void conv2(const a1_t a1[L1][C1_COUT], a2_t a2[L2_LEN][C2_COUT]) {
  const int NB = C2_COUT / UNROLL_C2;
  o2_t o = 0; ap_uint<6> cb = 0;
  C2_MAIN: for (int i = 0; i < L2_LEN*NB; i++) {
    acc2_t acc[UNROLL_C2];
    C2_Z: for (int u = 0; u < UNROLL_C2; u++) acc[u] = 0;
    C2_K_L: for (int k = 0; k < C2_K; k++) {
      sidx_t t = (sidx_t)(o << 1) + (sidx_t)k - (sidx_t)PAD2;
      bool ok = (t >= 0 && t < (sidx_t)L1);
      o1_t ta = ok ? (o1_t)t : (o1_t)0;
      C2_CIN: for (int ci = 0; ci < C1_COUT; ci++) {
        a1_t x = ok ? a1[ta][ci] : (a1_t)0;
        C2_U: for (int u = 0; u < UNROLL_C2; u++) {
          int co = cb*UNROLL_C2 + u;
#if MODE_C2 == 1
          int8_t w = W2[k][ci][co];
          if      (w > 0) acc[u] += (acc2_t)x;
          else if (w < 0) acc[u] -= (acc2_t)x;
#else
          acc[u] += (acc2_t)(x * W2[k][ci][co]);
#endif
        }
      }
    }
    C2_W: for (int u = 0; u < UNROLL_C2; u++) {
      int co = cb*UNROLL_C2 + u;
      a2[o][co] = rq2(acc[u], co);
    }
    if (cb == NB-1) { cb = 0; o++; } else { cb++; }
  }
}

static void gap(const a2_t a2[L2_LEN][C2_COUT], gap_t g[C2_COUT]) {
  gap_t s[C2_COUT];
  G_Z: for (int c = 0; c < C2_COUT; c++) s[c] = 0;
  G_L: for (int t = 0; t < L2_LEN; t++) {
    G_CH: for (int c = 0; c < C2_COUT; c++) s[c] += a2[t][c];
  }
  G_O: for (int c = 0; c < C2_COUT; c++) g[c] = s[c];
}

static void dense_argmax(const gap_t g[C2_COUT], int *cls, ap_int<64> logit_out[N_CLASS]) {
  ap_int<64> best = -(((ap_int<64>)1) << 62); int bk = 0;
  D_K: for (int k = 0; k < N_CLASS; k++) {
    dacc_t a = 0;
    D_IN: for (int j = 0; j < C2_COUT; j++) {
      a += (dacc_t)((int)g[j] * (int)WD[j][k]);
    }
    dmul_t t = (dmul_t)a * (dmul_t)M0D[k] + (dmul_t)BD[k] + ((dmul_t)1 << (SHD-1));
    ap_int<64> l = (ap_int<64>)(t >> SHD);
    logit_out[k] = l;
    if (l > best) { best = l; bk = k; }
  }
  *cls = bk;
}

void cnn_core(const i8_t in[IN_LEN], int *cls, ap_int<64> logit_out[N_CLASS]) {
  i8_t  buf[IN_LEN];
  a1_t  a1[L1][C1_COUT];
  a2_t  a2[L2_LEN][C2_COUT];
  gap_t g[C2_COUT];
  load_in(in, buf);
  conv1(buf, a1);
  conv2(a1, a2);
  gap(a2, g);
  dense_argmax(g, cls, logit_out);
}
