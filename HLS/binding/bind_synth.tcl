# bind_synth.tcl
#   (from HLS/) vivado -mode batch -source binding/bind_synth.tcl -nojournal -nolog   (all)
#   ... -tclargs W_int4_A8
#   ... -tclargs W_int4_A8 dsp
#   Tcl Console:  set argv {B_W*} ; set BIND_SYNTH_CSV bind_synth_B.csv ; source binding/bind_synth.tcl
#
# Out-of-context logic synthesis of the RTL produced by bind_experiment.tcl,
# so we can see what Vivado actually builds under each binding mode.
# Columns 1-6 are unchanged from the previous version; the per-core DSP
# split is appended. Every DSP48E1 cell name is dumped to
# bind_dump/dspcells_<cfg>_<mode>.txt so the name-pattern split can be checked.

# run from the HLS root (the folder holding the <config>/ directories)
set ROOT  [file normalize [pwd]]
set ALL_CFGS  {W_int8_A8 W_int4_A8 A_int8_A4 A_int4_A4 W_ternary_A8}
set ALL_MODES {default dsp fabric}

set CFGS {} ; set MODES {}
proc is_rtl_cfg {root d} { expr {[file isdirectory [file join $root $d]] && [llength [glob -nocomplain -directory [file join $root $d] -type d bind_*]]} }
if {[info exists argv]} {
  foreach t $argv {
    if {[lsearch -exact $ALL_MODES $t] >= 0} { if {[lsearch -exact $MODES $t] < 0} { lappend MODES $t } ; continue }
    if {[string first * $t] >= 0} {
      foreach d [lsort [glob -nocomplain -tails -directory $ROOT -type d $t]] {
        if {[is_rtl_cfg $ROOT $d] && [lsearch -exact $CFGS $d] < 0} { lappend CFGS $d }
      }
    } elseif {([lsearch -exact $ALL_CFGS $t] >= 0 || [is_rtl_cfg $ROOT $t]) && [lsearch -exact $CFGS $t] < 0} {
      lappend CFGS $t
    }
  }
}
if {![llength $CFGS]}  { set CFGS  $ALL_CFGS }
if {![llength $MODES]} { set MODES $ALL_MODES }
puts "Runs: configs = $CFGS ; modes = $MODES"

set DUMP [file join $ROOT bind_dump]
file mkdir $DUMP
set CSVNAME bind_synth.csv
if {[info exists ::env(BIND_SYNTH_CSV)]} { set CSVNAME $::env(BIND_SYNTH_CSV) }
if {[info exists BIND_SYNTH_CSV]} { set CSVNAME $BIND_SYNTH_CSV }
set OUT [open [file join $ROOT $CSVNAME] w]
puts $OUT "config,bind,DSP_built,LUT_built,FF_built,WNS,DSP_cells,DSP_conv2,DSP_conv2_macmuladd,DSP_conv2_mul,DSP_conv2_otherdsp,status,note"
flush $OUT

foreach cfg $CFGS {
  foreach mode $MODES {
    set dsp NA; set lut NA; set ff NA; set wns NA
    set ncell NA; set nc2 NA; set nmac NA; set nmul NA; set noth NA
    set status OK; set note ""

    set vdir ""
    foreach sub [list [file join $cfg bind_$mode sol1 syn verilog] \
                      [file join $cfg bind_$mode sol1 impl verilog]] {
      set p [file join $ROOT $sub]
      if {[file isdirectory $p] && [llength [glob -nocomplain "$p/*.v"]]} { set vdir $p; break }
    }
    if {$vdir eq ""} {
      puts "RTL not found: $cfg/$mode"
      puts $OUT "$cfg,$mode,NA,NA,NA,NA,NA,NA,NA,NA,NA,NO_RTL,"
      flush $OUT
      continue
    }

    if {[catch {
      create_project -in_memory -part xc7z020clg400-1
      read_verilog [glob "$vdir/*.v"]
      set vhd [glob -nocomplain "$vdir/*.vhd"]
      if {[llength $vhd]} { read_vhdl $vhd }

      set top ""
      foreach f [glob "$vdir/*.v"] {
        set b [file rootname [file tail $f]]
        if {$b eq "cnn_core" || $b eq "cnn_top"} { set top $b }
      }
      if {$top eq ""} { error "top not found in $vdir" }

      # clock constraint kept outside the RTL directory
      set xdc [file join $DUMP _clk_${cfg}_${mode}.xdc]
      set fh [open $xdc w]
      puts $fh "create_clock -period 20.0 -name ap_clk \[get_ports ap_clk\]"
      close $fh
      read_xdc $xdc

      synth_design -top $top -part xc7z020clg400-1 -mode out_of_context

      set u [report_utilization -return_string]
      foreach ln [split $u "\n"] {
        if {[regexp {\|\s*Slice LUTs\*?\s*\|\s*(\d+)}   $ln -> v]} { set lut $v }
        if {[regexp {\|\s*Slice Registers\s*\|\s*(\d+)} $ln -> v]} { set ff  $v }
        if {[regexp {\|\s*DSPs\s*\|\s*(\d+)}            $ln -> v]} { set dsp $v }
      }
      catch { set wns [get_property SLACK [lindex [get_timing_paths -delay_type max] 0]] }

      # per-core split of DSP48E1 cells (name patterns: see dump file)
      set cells [get_cells -hier -quiet -filter {REF_NAME == DSP48E1}]
      set ncell [llength $cells]
      set nc2 0; set nmac 0; set nmul 0; set noth 0
      set dfh [open [file join $DUMP dspcells_${cfg}_${mode}.txt] w]
      foreach c $cells {
        set n [get_property NAME $c]
        puts $dfh $n
        if {![string match -nocase "*conv2*" $n]} continue
        incr nc2
        if {[string match -nocase "*mac_muladd*" $n] || [string match -nocase "*ama_addmuladd*" $n]} {
          incr nmac
        } elseif {[string match -nocase "*/mul_*" $n]} {
          incr nmul
        } else {
          incr noth
        }
      }
      close $dfh
      if {$dsp ne "NA" && $ncell != $dsp} { append note " DSP_cells!=utilization" }
    } err]} {
      set status FAIL
      set note "[string map {"\n" " " "," ";"} $err]"
      puts "FAILED $cfg/$mode: $err"
    }
    catch { close_project }
    cd $ROOT

    puts $OUT "$cfg,$mode,$dsp,$lut,$ff,$wns,$ncell,$nc2,$nmac,$nmul,$noth,$status,[string trim $note]"
    flush $OUT
    puts ">>> $cfg/$mode : $status DSP=$dsp conv2=$nc2 (macmuladd=$nmac mul=$nmul other=$noth)"
  }
}
close $OUT
puts "\n>>> written: [file join $ROOT $CSVNAME]"
