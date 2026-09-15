# sweep_synth.tcl  ->  vivado -mode batch -source sweep_synth.tcl -nojournal -nolog
set ROOT "C:/Users/Administrator.LAB/Desktop/rulman_v2/hls"
set CFGS {W_int8_A8 W_int4_A8 A_int8_A4 A_int4_A4 W_ternary_A8}
set PERIODS {20.0 10.0}
set OUT [open "$ROOT/sweep_synth.csv" w]
puts $OUT "config,period_ns,DSP,LUT,FF,BRAM,WNS"

proc rtldir {root cfg} {
  foreach sub {impl/verilog syn/verilog impl/ip/hdl/verilog} {
    set d "$root/$cfg/hw_U1/sol1/$sub"
    if {[file isdirectory $d] && [llength [glob -nocomplain "$d/*.v"]]} { return $d }
  }
  return ""
}

foreach cfg $CFGS {
  set vdir [rtldir $ROOT $cfg]
  if {$vdir eq ""} { puts "RTL bulunamadi: $cfg"; continue }
  foreach T $PERIODS {
    cd $vdir
    create_project -in_memory -part xc7z020clg400-1
    read_verilog [glob "$vdir/*.v"]
    set vhd [glob -nocomplain "$vdir/*.vhd"]
    if {[llength $vhd]} { read_vhdl $vhd }

    # saat kisiti XDC ile verilir; synth_design'dan ONCE acik tasarim yok
    set xdc "$vdir/_clk.xdc"
    set fh [open $xdc w]
    puts $fh "create_clock -period $T -name ap_clk \[get_ports ap_clk\]"
    close $fh
    read_xdc $xdc

    if {[catch {synth_design -top cnn_hw -part xc7z020clg400-1 -mode out_of_context} err]} {
      puts "SYNTH HATASI $cfg @ $T ns: $err"
      close_project
      continue
    }

    set u [report_utilization -return_string]
    set lut ""; set ff ""; set dsp ""; set bram ""
    foreach ln [split $u "\n"] {
      if {[regexp {\|\s*Slice LUTs\*?\s*\|\s*(\d+)}     $ln -> v]} { set lut $v }
      if {[regexp {\|\s*Slice Registers\s*\|\s*(\d+)}   $ln -> v]} { set ff  $v }
      if {[regexp {\|\s*DSPs\s*\|\s*(\d+)}              $ln -> v]} { set dsp $v }
      if {[regexp {\|\s*Block RAM Tile\s*\|\s*([\d.]+)} $ln -> v]} { set bram $v }
    }
    set wns ""
    catch { set wns [get_property SLACK [lindex [get_timing_paths -delay_type max] 0]] }
    puts $OUT "$cfg,$T,$dsp,$lut,$ff,$bram,$wns"
    flush $OUT
    close_project
  }
}
close $OUT
puts ">>> sweep_synth.csv yazildi"