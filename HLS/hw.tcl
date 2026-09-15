# vitis_hls -f hw.tcl      (config klasorunde; IP uretir)
set U 1
foreach a $argv { if {[string is integer -strict $a]} { set U $a } }
set FL "-I. -DUNROLL_C2=$U -DUNROLL_C1=1"

open_project -reset hw_U$U
set_top cnn_hw
add_files cnn.cpp   -cflags $FL
add_files cnn_hw.cpp -cflags $FL
add_files -tb tb_hw.cpp -cflags $FL
open_solution -reset sol1 -flow_target vivado
set_part {xc7z020clg400-1}
create_clock -period 20 -name default

set_directive_dataflow "cnn_core"
set_directive_pipeline -II 1 "load_in/LD"
set_directive_pipeline -II 1 "conv1/C1_MAIN"
set_directive_unroll             "conv1/C1_K_L"
set_directive_unroll             "conv1/C1_U"
set_directive_pipeline -II 1 "conv2/C2_MAIN"
set_directive_unroll             "conv2/C2_K_L"
set_directive_unroll             "conv2/C2_CIN"
set_directive_unroll             "conv2/C2_U"
set_directive_pipeline -II 1 "gap/G_L"
set_directive_pipeline -II 1 "dense_argmax/D_IN"
set_directive_array_partition -type complete -dim 0 "conv1" W1
set_directive_array_partition -type complete -dim 1 "conv2" W2
set_directive_array_partition -type complete -dim 2 "conv2" W2
set_directive_array_partition -type cyclic -factor 8 -dim 1 "cnn_core" buf
set_directive_array_partition -type complete -dim 2 "cnn_core" a1
set_directive_array_partition -type complete -dim 2 "cnn_core" a2
set_directive_array_partition -type complete -dim 1 "gap" s

csim_design
csynth_design
export_design -format ip_catalog -rtl verilog
close_project
exit
