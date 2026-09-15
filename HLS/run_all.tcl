# vitis_hls -f run_all.tcl     (hls/ kökünde çalıştır)
set ROOT [file normalize [file dirname [info script]]]
set CONFIGS {W_int8_A8 W_int4_A8 W_ternary_A8 A_int8_A4 A_int4_A4}
set UNROLLS {1}
set CSV [file join $ROOT results.csv]

proc num {s} {
  if {[regexp {(-?\d+)} $s -> v]} { return $v }
  return ""
}
proc row {txt name} {
  foreach ln [split $txt "\n"] {
    set ln [string trim $ln]
    if {![string match "|*" $ln]} continue
    set f [split $ln "|"]
    if {[llength $f] < 14} continue
    set nm [string trim [string map {+ "" o "" * ""} [lindex $f 1]]]
    if {$nm eq $name} { return $f }
  }
  return {}
}

set fh [open $CSV w]
puts $fh "config,unroll,csim_argmax,csim_logit,latency,II_top,DSP,LUT,FF,BRAM,conv2_DSP,conv2_LUT,C2_II,conv1_DSP,C1_II"
foreach cfg $CONFIGS {
  foreach U $UNROLLS {
    set d [file join $ROOT $cfg]
    if {![file isdirectory $d]} { puts "ATLA: $d yok"; continue }
    cd $d
    puts "=== $cfg  U=$U ==="
    set FL "-I. -DUNROLL_C2=$U"
    set p proj_U$U
    open_project -reset $p
    set_top cnn_top
    add_files cnn.cpp -cflags $FL
    add_files -tb tb.cpp -cflags $FL
    open_solution -reset sol1 -flow_target vivado
    set_part {xc7z020clg400-1}
    create_clock -period 20 -name default

    set_directive_dataflow "cnn_top"
    set_directive_pipeline -II 1 "load_in/LD"
    set_directive_pipeline -II 1 "conv1/C1_MAIN"
    set_directive_unroll             "conv1/C1_K_L"
    set_directive_pipeline -II 1 "conv2/C2_MAIN"
    set_directive_unroll             "conv2/C2_K_L"
    set_directive_unroll             "conv2/C2_CIN"
    set_directive_unroll             "conv2/C2_U"
    set_directive_pipeline -II 1 "gap/G_L"
    set_directive_pipeline -II 1 "dense_argmax/D_IN"
    set_directive_array_partition -type complete -dim 0 "conv1" W1
    set_directive_array_partition -type complete -dim 1 "conv2" W2
    set_directive_array_partition -type complete -dim 2 "conv2" W2
    set_directive_array_partition -type cyclic -factor 8 -dim 1 "cnn_top" buf
    set_directive_array_partition -type complete -dim 2 "cnn_top" a1
    set_directive_array_partition -type complete -dim 2 "cnn_top" a2
    set_directive_array_partition -type complete -dim 1 "gap" s

    csim_design
    csynth_design
    close_project

    # --- ayrıştır ---
    set ma ""; set ml ""
    set lg [file join $d $p sol1 csim report cnn_top_csim.log]
    if {[file exists $lg]} {
      set t [read [set f [open $lg]]]; close $f
      regexp {argmax mismatch:\s*(\d+)} $t -> ma
      regexp {logit\s+mismatch:\s*(\d+)} $t -> ml
    }
    set rp [file join $d $p sol1 syn report csynth.rpt]
    set lat ""; set ii ""; set dsp ""; set lut ""; set ff ""; set bram ""
    set c2d ""; set c2l ""; set c2ii ""; set c1d ""; set c1ii ""
    if {[file exists $rp]} {
      set t [read [set f [open $rp]]]; close $f
      set r [row $t "cnn_top"]
      if {[llength $r]} {
        set lat  [num [lindex $r 4]];  set ii   [num [lindex $r 7]]
        set bram [num [lindex $r 10]]; set dsp  [num [lindex $r 11]]
        set ff   [num [lindex $r 12]]; set lut  [num [lindex $r 13]]
      }
      set r [row $t "conv2"]
      if {[llength $r]} { set c2d [num [lindex $r 11]]; set c2l [num [lindex $r 13]] }
      set r [row $t "C2_MAIN"];  if {[llength $r]} { set c2ii [num [lindex $r 7]] }
      set r [row $t "conv1"];    if {[llength $r]} { set c1d  [num [lindex $r 11]] }
      set r [row $t "C1_MAIN"];  if {[llength $r]} { set c1ii [num [lindex $r 7]] }
    }
    puts $fh "$cfg,$U,$ma,$ml,$lat,$ii,$dsp,$lut,$ff,$bram,$c2d,$c2l,$c2ii,$c1d,$c1ii"
    flush $fh
    cd $ROOT
  }
}
close $fh
puts "\n>>> yazildi: $CSV"
exit
