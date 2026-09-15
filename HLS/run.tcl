# kullanim:  vitis_hls -f run.tcl -tclargs <UNROLL_C2>
# ya da:     UNROLL=4 vitis_hls -f run.tcl
set U 1
if {[info exists ::env(UNROLL)]} { set U $::env(UNROLL) }
foreach a $argv { if {[string is integer -strict $a]} { set U $a } }
puts "== UNROLL_C2 = $U =="
set FL "-I. -DUNROLL_C2=$U"

open_project -reset proj_U$U
set_top cnn_top
add_files cnn.cpp -cflags $FL
add_files -tb tb.cpp -cflags $FL
open_solution -reset sol1 -flow_target vivado
set_part {xc7z020clg400-1}
create_clock -period 20 -name default

set_directive_pipeline -II 1 "load_in/LD"
set_directive_array_partition -type cyclic -factor 8 -dim 1 "cnn_top" buf

set_directive_dataflow "cnn_top"

set_directive_pipeline -II 1 "conv1/C1_MAIN"
set_directive_unroll             "conv1/C1_K_L"

set_directive_pipeline -II 1 "conv2/C2_MAIN"
set_directive_unroll             "conv2/C2_K_L"
set_directive_unroll             "conv2/C2_CIN"
set_directive_unroll             "conv2/C2_U"

set_directive_pipeline -II 1 "gap/G_L"
set_directive_unroll             "gap/G_CH"
set_directive_pipeline -II 1 "dense_argmax/D_IN"

set_directive_array_partition -type complete -dim 0 "conv1"       W1
set_directive_array_partition -type complete -dim 1 "conv2"       W2
set_directive_array_partition -type complete -dim 2 "conv2"       W2
set_directive_array_partition -type complete -dim 2 "cnn_top"     a1
set_directive_array_partition -type complete -dim 2 "cnn_top"     a2
set_directive_array_partition -type complete -dim 1 "gap"         s

csim_design
csynth_design
close_project
exit
