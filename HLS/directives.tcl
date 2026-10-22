# directives.tcl -- the directive set shared by every configuration and binding mode.
# Sourced by binding/bind_experiment.tcl at global scope after set_top; $TOP is the
# kernel top function (cnn_core). Identical to the directives of hw.tcl.
set_directive_dataflow                                   $TOP
set_directive_pipeline -II 1                             "load_in/LD"
set_directive_pipeline -II 1                             "conv1/C1_MAIN"
set_directive_unroll                                     "conv1/C1_K_L"
set_directive_unroll                                     "conv1/C1_U"
set_directive_pipeline -II 1                             "conv2/C2_MAIN"
set_directive_unroll                                     "conv2/C2_K_L"
set_directive_unroll                                     "conv2/C2_CIN"
set_directive_unroll                                     "conv2/C2_U"
set_directive_pipeline -II 1                             "gap/G_L"
set_directive_pipeline -II 1                             "dense_argmax/D_IN"
set_directive_array_partition -type complete -dim 0      "conv1" W1
set_directive_array_partition -type complete -dim 1      "conv2" W2
set_directive_array_partition -type complete -dim 2      "conv2" W2
set_directive_array_partition -type cyclic -factor 8 -dim 1 $TOP buf
set_directive_array_partition -type complete -dim 2      $TOP a1
set_directive_array_partition -type complete -dim 2      $TOP a2
set_directive_array_partition -type complete -dim 1      "gap" s
