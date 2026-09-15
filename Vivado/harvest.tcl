# harvest.tcl  ->  vivado -mode batch -source harvest.tcl -nojournal -nolog
# Mevcut projelerden post-synth + post-impl + hiyerarsik DSP dokumu cikarir.
# HICBIR SEY YENIDEN KOSMAZ.

set PROJS {
  {W8A8   C:/Users/Administrator.LAB/rulman_v2/rulman_v2.xpr}
  {W4A8   C:/Users/Administrator.LAB/W_int4_A8/W_int4_A8.xpr}
  {W8A4   C:/Users/Administrator.LAB/A_int8_A4/A_int8_A4.xpr}
  {W4A4   C:/Users/Administrator.LAB/A_int4_A4/A_int4_A4.xpr}
  {TerA8  C:/Users/Administrator.LAB/W_ternary_A8/W_ternary_A8.xpr}
}
set OUT [open "harvest.csv" w]
puts $OUT "config,stage,DSP,LUT,FF,BRAM"
set OUT2 [open "dsp_hier.csv" w]
puts $OUT2 "config,stage,submodule,DSP"

proc util {} {
  set u [report_utilization -return_string]
  set r [dict create LUT "" FF "" DSP "" BRAM ""]
  foreach ln [split $u "\n"] {
    if {[regexp {\|\s*Slice LUTs\*?\s*\|\s*(\d+)}       $ln -> v]} { dict set r LUT  $v }
    if {[regexp {\|\s*Slice Registers\s*\|\s*(\d+)}     $ln -> v]} { dict set r FF   $v }
    if {[regexp {\|\s*DSPs\s*\|\s*(\d+)}                $ln -> v]} { dict set r DSP  $v }
    if {[regexp {\|\s*Block RAM Tile\s*\|\s*([\d.]+)}   $ln -> v]} { dict set r BRAM $v }
  }
  return $r
}

proc dsp_by_submodule {} {
  # DSP48 hucrelerini ust seviye alt modullerine gore say
  set tally [dict create]
  foreach c [get_cells -quiet -hier -filter {REF_NAME =~ DSP48*}] {
    set path [get_property NAME $c]
    set parts [split $path "/"]
    # cnn_hw sarmalayicisinin altindaki ilk anlamli seviyeyi al
    set key "other"
    foreach p $parts {
      if {[regexp {(conv1|conv2|gap|dense|grp_|cnn_core|cnn_hw)} $p]} { set key $p }
    }
    dict incr tally $key
  }
  return $tally
}

foreach p $PROJS {
  lassign $p name xpr
  if {![file exists $xpr]} { puts "ATLA $name"; continue }
  open_project $xpr
  foreach stage {synth_1 impl_1} {
    if {[llength [get_runs -quiet $stage]] == 0} { puts "$name: $stage yok"; continue }
    if {[get_property PROGRESS [get_runs $stage]] ne "100%"} {
      puts "$name: $stage tamamlanmamis, atlaniyor"; continue
    }
    open_run $stage -name ${name}_${stage}
    set r [util]
    puts $OUT "$name,$stage,[dict get $r DSP],[dict get $r LUT],[dict get $r FF],[dict get $r BRAM]"
    dict for {k v} [dsp_by_submodule] { puts $OUT2 "$name,$stage,$k,$v" }
    flush $OUT; flush $OUT2
    close_design
  }
  close_project
}
close $OUT; close $OUT2
puts "\n>>> harvest.csv ve dsp_hier.csv yazildi"