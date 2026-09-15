set PROJS {
  {W_int8_A8    C:/Users/Administrator.LAB/rulman_v2/rulman_v2.xpr}
  {W_int4_A8    C:/Users/Administrator.LAB/W_int4_A8/W_int4_A8.xpr}
  {A_int8_A4    C:/Users/Administrator.LAB/A_int8_A4/A_int8_A4.xpr}
  {A_int4_A4    C:/Users/Administrator.LAB/A_int4_A4/A_int4_A4.xpr}
  {W_ternary_A8 C:/Users/Administrator.LAB/W_ternary_A8/W_ternary_A8.xpr}
}
puts "\nconfig,WNS,WHS,TNS,THS,LUT,FF,DSP,BRAM"
foreach p $PROJS {
  lassign $p name xpr
  if {![file exists $xpr]} { puts "$name,PROJE_YOK"; continue }
  open_project $xpr
  open_run impl_1
  set wns [get_property STATS.WNS [get_runs impl_1]]
  set whs [get_property STATS.WHS [get_runs impl_1]]
  set tns [get_property STATS.TNS [get_runs impl_1]]
  set ths [get_property STATS.THS [get_runs impl_1]]
  set u [report_utilization -return_string]
  set lut ""; set ff ""; set dsp ""; set bram ""
  foreach ln [split $u "\n"] {
    if {[regexp {\|\s*Slice LUTs\s*\|\s*(\d+)}    $ln -> v]} { set lut $v }
    if {[regexp {\|\s*Slice Registers\s*\|\s*(\d+)} $ln -> v]} { set ff  $v }
    if {[regexp {\|\s*DSPs\s*\|\s*(\d+)}          $ln -> v]} { set dsp $v }
    if {[regexp {\|\s*Block RAM Tile\s*\|\s*([\d.]+)} $ln -> v]} { set bram $v }
  }
  puts "$name,$wns,$whs,$tns,$ths,$lut,$ff,$dsp,$bram"
  close_project
}