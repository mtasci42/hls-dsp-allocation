# =============================================================================
# bind_experiment.tcl  --  Group A: HLS binding experiment (defensive rewrite)
#
# 5 configs x 3 binding modes (default / dsp / fabric), csynth only.
# Project dir : <cfg>/bind_<mode>      Solution: sol1
# RTL         : <cfg>/bind_<mode>/sol1/syn/verilog   (read by bind_synth.tcl)
#
# Usage (from the HLS root; each <config>/ must hold cnn.cpp, cnn.h, weights.h,
# and HLS/directives.tcl must exist):
#   vitis_hls -f binding/bind_experiment.tcl                         ;# all 15 runs
#   vitis_hls -f binding/bind_experiment.tcl -tclargs W_int4_A8      ;# one config, 3 modes
#   vitis_hls -f binding/bind_experiment.tcl -tclargs W_int4_A8 default  ;# one run
#   vitis_hls -f binding/bind_experiment.tcl -tclargs B_W*            ;# Group B sweep dirs
#   (set BIND_CSV=name.csv to write to another CSV instead of bind_experiment.csv)
#
# Every run is wrapped in catch; a missing report or table writes NA and the
# loop continues. Each CSV row is flushed immediately.
# =============================================================================

set ROOT   [file normalize [pwd]]
set PART   xc7z020clg400-1
set PERIOD 20

set ALL_CFGS  {W_int8_A8 W_int4_A8 A_int8_A4 A_int4_A4 W_ternary_A8}
set ALL_MODES {default dsp fabric}

# ---- optional restriction via -tclargs ---------------------------------------
# Vitis HLS puts its own command line (-f script.tcl ...) into argv, so only
# tokens that are known config / mode names are taken. Env vars BIND_CFG /
# BIND_MODE work as a fallback if -tclargs is not passed through.
set CFGS  {}
set MODES {}
set toks {}
if {[info exists argv]} { set toks $argv }
if {[info exists ::env(BIND_CFG)]}  { lappend toks $::env(BIND_CFG) }
if {[info exists ::env(BIND_MODE)]} { lappend toks $::env(BIND_MODE) }
# a token is a config if it is a known name, an existing <dir>/cnn.cpp under ROOT,
# or a glob (e.g. B_W*) matching such directories
proc is_cfg_dir {root d} { expr {[file isfile [file join $root $d cnn.cpp]] && [file isfile [file join $root $d weights.h]]} }
foreach t $toks {
    if {[lsearch -exact $ALL_MODES $t] >= 0} {
        if {[lsearch -exact $MODES $t] < 0} { lappend MODES $t }
        continue
    }
    if {[string first * $t] >= 0} {
        foreach d [lsort [glob -nocomplain -tails -directory $ROOT -type d $t]] {
            if {[is_cfg_dir $ROOT $d] && [lsearch -exact $CFGS $d] < 0} { lappend CFGS $d }
        }
    } elseif {([lsearch -exact $ALL_CFGS $t] >= 0 || [is_cfg_dir $ROOT $t]) && [lsearch -exact $CFGS $t] < 0} {
        lappend CFGS $t
    }
}
if {[llength $CFGS]  == 0} { set CFGS  $ALL_CFGS }
if {[llength $MODES] == 0} { set MODES $ALL_MODES }
puts "argv = [expr {[info exists argv] ? $argv : {}}]"
puts "Runs: configs = $CFGS ; modes = $MODES"

set CSVNAME bind_experiment.csv
if {[info exists ::env(BIND_CSV)]} { set CSVNAME $::env(BIND_CSV) }
set CSV  [file join $ROOT $CSVNAME]
set DUMP [file join $ROOT bind_dump]
file mkdir $DUMP

# First 10 columns keep the old order so bind_synth.tcl is unaffected;
# new columns are appended after rtl_dir.
set HEADER [join {config bind DSP_hls LUT_hls FF_hls conv2_DSP_hls mul_total \
    mul_dsp_slice mul_auto rtl_dir status top mul_fabric mul_other \
    conv2_rpt conv2_mul_total conv2_mul_dsp_slice conv2_mul_auto \
    rtl_files rtl_use_dsp_hits rtl_dsp48_hits \
    mul_dsp conv2_mul_dsp conv2_mul_fabric conv2_mul_other conv2_operands note} ,]

# =============================================================================
# Helpers (each one returns NA / empty instead of throwing)
# =============================================================================
proc slurp {path} {
    if {![file exists $path]} { return "" }
    if {[catch {set fh [open $path r]; set s [read $fh]; close $fh} err]} { return "" }
    return $s
}

proc na {v} { if {$v eq ""} { return NA } ; return $v }

proc csv_safe {v} {
    set v [string map {"\n" " " "\r" " " "," ";"} $v]
    return $v
}

# Top-level resources from csynth.xml (<AreaEstimates><Resources>)
proc xml_resources {xmlpath} {
    set r [dict create DSP NA LUT NA FF NA]
    set s [slurp $xmlpath]
    if {$s eq ""} { return $r }
    if {![regexp {<AreaEstimates>.*?<Resources>(.*?)</Resources>} $s -> blk]} { return $r }
    foreach tag {DSP DSP48E DSP48E1} {
        if {[regexp "<$tag>\\s*(\[0-9\]+)\\s*</$tag>" $blk -> v]} { dict set r DSP $v ; break }
    }
    if {[regexp {<LUT>\s*([0-9]+)\s*</LUT>} $blk -> v]} { dict set r LUT $v }
    if {[regexp {<FF>\s*([0-9]+)\s*</FF>}   $blk -> v]} { dict set r FF  $v }
    return $r
}

# Parse the hierarchical "Bind Op Report" in the top-level csynth.rpt
# (Vitis HLS 2024.1: the table exists only there, not in per-module reports).
# Module rows look like "|  + conv2 | 47 | ...", indentation gives nesting.
# Returns dict: module -> {dsp_slice N auto N fabric N other N}, plus key
# "__ALL__" for the whole design and "__FOUND__" 0/1.
# Every counted "mul" row is written to dumpfh with its module path.
proc bindop_table {rptpath dumpfh} {
    set res [dict create __FOUND__ 0 __LABELS__ {}]
    set s [slurp $rptpath]
    if {$s eq ""} { return $res }
    set in 0 ; set iOp -1 ; set iImpl -1 ; set stack {} ; set ops [dict create]
    foreach line [split $s "\n"] {
        if {!$in} {
            if {[string match -nocase "== Bind Op Report*" [string trim $line]]} {
                set in 1 ; dict set res __FOUND__ 1
            }
            continue
        }
        if {[regexp {^== } $line]} break           ;# next section
        if {![regexp {^\|} $line]} continue         ;# ==== and +---- lines
        set raw  [lrange [split $line |] 1 end-1]
        set cols {}
        foreach x $raw { lappend cols [string trim $x] }
        if {$iOp < 0} {
            set iOp   [lsearch -exact -nocase $cols Op]
            set iImpl [lsearch -exact -nocase $cols Impl]
            continue
        }
        set name [lindex $cols 0]
        if {[regexp {^\+\s*(\S+)} $name -> mod]} {
            set ind [expr {[string length [lindex $raw 0]] - [string length [string trimleft [lindex $raw 0]]]}]
            while {[llength $stack] && [lindex $stack end 0] >= $ind} { set stack [lrange $stack 0 end-1] }
            lappend stack [list $ind $mod]
            continue
        }
        if {$iImpl < 0 || $iImpl >= [llength $cols]} continue
        if {[string tolower [lindex $cols $iOp]] ne "mul"} continue
        set impl [string tolower [lindex $cols $iImpl]]
        if {$impl ni {dsp_slice dsp auto fabric}} {
            if {[lsearch -exact [dict get $res __LABELS__] $impl] < 0} { dict lappend res __LABELS__ $impl }
            set impl other
        }
        set path {}
        foreach e $stack { lappend path [lindex $e 1] }
        foreach m [concat [list __ALL__] $path] {
            if {![dict exists $res $m]} { dict set res $m [dict create dsp_slice 0 dsp 0 auto 0 fabric 0 other 0] }
            dict set res $m $impl [expr {[dict get $res $m $impl] + 1}]
        }
        if {[lsearch -exact $path conv2] >= 0 &&
            [regexp {^(?:mac_muladd|ama_addmuladd|am_addmul|mul)_([0-9]+n?s)_([0-9]+n?s)} $name -> wa wb]} {
            dict incr ops "${wa}*${wb}"
        }
        if {$dumpfh ne ""} { puts $dumpfh "[join $path /] | $name | $impl" }
    }
    set ol {}
    foreach k [lsort [dict keys $ops]] { lappend ol "$k=[dict get $ops $k]" }
    dict set res __OPS__ [join $ol ";"]
    return $res
}

proc sumc {d} { expr {[dict get $d dsp_slice]+[dict get $d dsp]+[dict get $d auto]+[dict get $d fabric]+[dict get $d other]} }

proc rtl_scan {rtldir} {
    set r [dict create files 0 use_dsp 0 dsp48 0]
    if {![file isdirectory $rtldir]} { return $r }
    set fl [glob -nocomplain -directory $rtldir *.v *.sv]
    dict set r files [llength $fl]
    foreach f $fl {
        foreach line [split [slurp $f] "\n"] {
            if {[string match -nocase "*use_dsp*" $line]} { dict incr r use_dsp }
            if {[string match -nocase "*DSP48*"   $line]} { dict incr r dsp48 }
        }
    }
    return $r
}

# =============================================================================
# One run: build project, csynth, parse. Throws only to the outer catch.
# =============================================================================
proc one_run {root cfg mode part period dumpdir} {
    set cdir [file join $root $cfg]
    set src  [file join $cdir cnn.cpp]
    if {![file exists $src]} { error "missing $src" }

    set top cnn_top
    if {[regexp {void\s+cnn_core\s*\(} [slurp $src]]} { set top cnn_core }

    cd $cdir
    catch {close_project}
    open_project -reset bind_$mode
    set_top $top
    add_files $src -cflags "-I$cdir"
    open_solution -reset sol1 -flow_target vivado
    set_part $part
    create_clock -period $period -name default

    # directives.tcl uses $TOP; source it at global level so it sees ::TOP
    # (a plain 'source' inside a proc runs in the proc's local scope).
    set ::TOP $top
    set TOP   $top
    uplevel #0 [list source [file join $root directives.tcl]]

    switch -- $mode {
        default { }
        dsp     { config_op mul -impl dsp }
        fabric  { config_op mul -impl fabric }
        default { error "unknown mode $mode" }
    }

    csynth_design
    close_project
    cd $root
    return $top
}

# =============================================================================
# Main loop
# =============================================================================
set out [open $CSV w]
puts $out $HEADER
flush $out

foreach cfg $CFGS {
    foreach mode $MODES {
        puts "\n######## $cfg / $mode ########"
        set status OK ; set note "" ; set top NA
        if {[catch {set top [one_run $ROOT $cfg $mode $PART $PERIOD $DUMP]} err]} {
            set status FAIL_CSYNTH
            set note $err
            catch {close_project}
        }
        cd $ROOT

        set sol    [file join $ROOT $cfg bind_$mode sol1]
        set repdir [file join $sol syn report]
        set rtldir [file join $sol syn verilog]

        set res  [dict create DSP NA LUT NA FF NA]
        set all  [dict create total NA dsp_slice NA dsp NA auto NA fabric NA other NA]
        set c2   [dict create total NA dsp_slice NA dsp NA auto NA fabric NA other NA]
        set c2dsp NA ; set c2rpt NA ; set c2ops NA
        set rtl  [dict create files NA use_dsp NA dsp48 NA]

        if {[catch {
            set res [xml_resources [file join $repdir csynth.xml]]
            if {[dict get $res DSP] eq "NA"} { append note " csynth.xml_missing_or_unparsed" }

            set dfh [open [file join $DUMP bindop_${cfg}_${mode}.txt] w]
            set bt [bindop_table [file join $repdir csynth.rpt] $dfh]
            close $dfh
            if {[dict get $bt __FOUND__] && [dict exists $bt __ALL__]} {
                set d [dict get $bt __ALL__]
                set all [dict merge $d [dict create total [sumc $d]]]
                if {[llength [dict get $bt __LABELS__]]} { append note " other_impl=[join [dict get $bt __LABELS__] /]" }
            } else {
                append note " no_bind_op_table_in_csynth.rpt"
            }
            if {[dict exists $bt __OPS__] && [dict get $bt __OPS__] ne ""} { set c2ops [dict get $bt __OPS__] }
            if {[dict exists $bt conv2]} {
                set d [dict get $bt conv2]
                set c2 [dict merge $d [dict create total [sumc $d]]]
                set c2rpt csynth.rpt
            } else {
                append note " no_conv2_in_bind_op_table"
            }
            # conv2 DSP estimate from per-module xml
            set x [xml_resources [file join $repdir conv2_csynth.xml]]
            set c2dsp [dict get $x DSP]

            set rtl [rtl_scan $rtldir]
        } perr]} {
            if {$status eq "OK"} { set status FAIL_PARSE }
            append note " parse:$perr"
        }

        set row [list $cfg $mode \
            [na [dict get $res DSP]] [na [dict get $res LUT]] [na [dict get $res FF]] \
            [na $c2dsp] \
            [na [dict get $all total]] [na [dict get $all dsp_slice]] [na [dict get $all auto]] \
            $rtldir $status $top \
            [na [dict get $all fabric]] [na [dict get $all other]] \
            $c2rpt [na [dict get $c2 total]] [na [dict get $c2 dsp_slice]] [na [dict get $c2 auto]] \
            [na [dict get $rtl files]] [na [dict get $rtl use_dsp]] [na [dict get $rtl dsp48]] \
            [na [dict get $all dsp]] [na [dict get $c2 dsp]] [na [dict get $c2 fabric]] [na [dict get $c2 other]] $c2ops \
            [string trim $note]]
        set clean {}
        foreach v $row { lappend clean [csv_safe $v] }
        puts $out [join $clean ,]
        flush $out
        puts ">>> $cfg/$mode : $status  DSP_hls=[dict get $res DSP]  note=[string trim $note]"
    }
}
close $out
puts "\nDone. CSV: $CSV   raw bind-op rows: $DUMP"
exit
