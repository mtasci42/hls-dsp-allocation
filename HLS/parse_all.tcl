# vitis_hls -f parse_all.tcl     (hls/ kökünde; sentez KOŞMAZ)
set ROOT [file normalize [file dirname [info script]]]
set CONFIGS {W_int8_A8 W_int4_A8 W_ternary_A8 A_int8_A4 A_int4_A4}
set UNROLLS {1}

proc num {s} { if {[regexp {(-?\d+)} $s -> v]} { return $v } ; return "" }

proc row {txt name} {
  foreach ln [split $txt "\n"] {
    set ln [string trim $ln]
    if {![string match "|*" $ln]} continue
    set f [split $ln "|"]
    if {[llength $f] < 14} continue
    set nm [string trim [lindex $f 1]]
    regsub {^[+o*]\s*} $nm "" nm
    set nm [string trimright [string trim $nm] "*"]
    if {$nm eq $name} { return $f }
  }
  return {}
}

set fh [open [file join $ROOT results.csv] w]
puts $fh "config,unroll,csim_argmax,csim_logit,latency,II_top,DSP,LUT,FF,BRAM,conv2_DSP,conv2_LUT,C2_II,conv1_DSP,C1_II"
foreach cfg $CONFIGS {
  foreach U $UNROLLS {
    set d [file join $ROOT $cfg]
    set p proj_U$U
    set ma ""; set ml ""
    foreach cand [list [file join $d $p sol1 csim report cnn_top_csim.log] \
                       [file join $d $p sol1 csim build csim.log]] {
      if {[file exists $cand]} {
        set t [read [set f [open $cand]]]; close $f
        regexp {argmax mismatch:\s*(\d+)} $t -> ma
        regexp {logit\s+mismatch:\s*(\d+)} $t -> ml
        break
      }
    }
    set rp [file join $d $p sol1 syn report csynth.rpt]
    foreach v {lat ii dsp lut ff bram c2d c2l c2ii c1d c1ii} { set $v "" }
    if {[file exists $rp]} {
      set t [read [set f [open $rp]]]; close $f
      set r [row $t "cnn_top"]
      if {[llength $r]} {
        set lat [num [lindex $r 4]];  set ii   [num [lindex $r 7]]
        set bram [num [lindex $r 10]]; set dsp [num [lindex $r 11]]
        set ff  [num [lindex $r 12]]; set lut  [num [lindex $r 13]]
      }
      set r [row $t "conv2"]
      if {[llength $r]} { set c2d [num [lindex $r 11]]; set c2l [num [lindex $r 13]] }
      set r [row $t "conv1"]   ; if {[llength $r]} { set c1d  [num [lindex $r 11]] }
      set r [row $t "C2_MAIN"] ; if {[llength $r]} { set c2ii [num [lindex $r 7]] }
      set r [row $t "C1_MAIN"] ; if {[llength $r]} { set c1ii [num [lindex $r 7]] }
    } else { puts "YOK: $rp" }
    puts $fh "$cfg,$U,$ma,$ml,$lat,$ii,$dsp,$lut,$ff,$bram,$c2d,$c2l,$c2ii,$c1d,$c1ii"
  }
}
close $fh
puts ">>> yazildi: [file join $ROOT results.csv]"
exit
