# Tcl on Windows has unfortunate defaults:
#   - cp1252 encoding, which will mangle utf-8 source code
#   - crlf linebreaks instead of unix-style lf
# Let's be consistent cross-platform to avoid surprises:
encoding system "utf-8"
foreach p {stdin stdout stderr} {
    fconfigure $p -encoding "utf-8"
    fconfigure $p -translation lf
}

package require Tk

wm title . "KWTekken Overlay"
tk appname "KWTekken Overlay"

# Proper Windows theme doesn't allow setting fieldbackground on text inputs,
# so let's settle with `clam` instead.
ttk::style theme use clam

wm protocol . WM_DELETE_WINDOW {
    exit 0
}
wm minsize . 480 160

# Data that we send to the actual web-based overlay:
array set scoreboard {
    description ""
    subtitle ""
    p1name ""
    p1country ""
    p1score 0
    p1team ""
    p2name ""
    p2country ""
    p2score 0
    p2team ""
    font "Bahnschrift"
}

# $applied_scoreboard represents data that has actually been applied
# to the overlay. This is used to display diff in the UI, and to restore data
# when user clicks "Discard".
foreach key [array names scoreboard] {
    set applied_scoreboard($key) scoreboard($key)
}

array set var_to_widget {
    description .n.m.description.entry
    p1name .n.m.players.p1name
    p1score .n.m.players.p1score
    p2name .n.m.players.p2name
    p2score .n.m.players.p2score
}

array set startgg {
    token ""
    slug ""
    msg ""
}

# GUI has a top Settings menu and one main panel.

menu .menubar
. configure -menu .menubar
menu .menubar.settings -tearoff 0
menu .menubar.settings.font -tearoff 0
.menubar add cascade -label "Settings" -menu .menubar.settings
.menubar.settings add cascade -label "Font" -menu .menubar.settings.font
foreach font {"Bahnschrift" "Segoe UI" "Arial" "Trebuchet MS" "Tahoma" "Verdana" "Jura"} {
    .menubar.settings.font add radiobutton -label $font -variable scoreboard(font) -value $font \
        -command mark_settings_changed
}
.menubar.settings add separator
.menubar.settings add command -label "start.gg..." -command openstartggsettings

ttk::frame .n
ttk::frame .n.m -padding 5
grid .n -column 0 -row 0 -sticky NESW
grid .n.m -column 0 -row 0 -sticky NESW
grid columnconfigure . 0 -weight 1
grid rowconfigure . 0 -weight 1
grid columnconfigure .n 0 -weight 1
grid rowconfigure .n 0 -weight 1

# Main panel:

ttk::frame .n.m.description
ttk::label .n.m.description.lbl -text "Title"
ttk::entry .n.m.description.entry -textvariable scoreboard(description)
ttk::frame .n.m.players
ttk::label .n.m.players.p1lbl -text "Player 1"
ttk::combobox .n.m.players.p1name -textvariable scoreboard(p1name) -width 35
ttk::spinbox .n.m.players.p1score -textvariable scoreboard(p1score) -from 0 -to 999 -width 4
ttk::button .n.m.players.p1win -text "▲ Win" -width 6 -command {increment_score p1score}
ttk::separator .n.m.players.separator -orient horizontal
ttk::label .n.m.players.p2lbl -text "Player 2"
ttk::combobox .n.m.players.p2name -textvariable scoreboard(p2name) -width 35
ttk::spinbox .n.m.players.p2score -textvariable scoreboard(p2score) -from 0 -to 999 -width 4
ttk::button .n.m.players.p2win -text "▲ Win" -width 6 -command {increment_score p2score}
ttk::frame .n.m.buttons
ttk::button .n.m.buttons.apply -text "▶ Apply" -command applyscoreboard
ttk::button .n.m.buttons.discard -text "✖ Discard" -command discardscoreboard
ttk::button .n.m.buttons.reset -text "↶ Reset scores" -command {
    set scoreboard(p1score) 0
    set scoreboard(p2score) 0
}
ttk::button .n.m.buttons.swap -text "⇄ Swap players" -command {
    foreach key {name score} {
        set tmp $scoreboard(p1$key)
        set scoreboard(p1$key) $scoreboard(p2$key)
        set scoreboard(p2$key) $tmp
    }
}
ttk::label .n.m.status -textvariable mainstatus
grid .n.m.description -row 0 -column 0 -sticky NESW -pady {0 5}
grid .n.m.description.lbl -row 0 -column 0 -padx {0 5}
grid .n.m.description.entry -row 0 -column 1 -sticky EW
grid columnconfigure .n.m.description 1 -weight 1
grid .n.m.players -row 1 -column 0 -sticky EW
grid .n.m.players.p1lbl -row 0 -column 0
grid .n.m.players.p1name -row 0 -column 1 -sticky EW
grid .n.m.players.p1score -row 0 -column 2
grid .n.m.players.p1win -row 0 -column 3 -padx {5 0} -sticky NS
grid .n.m.players.separator -row 1 -column 0 -columnspan 4 -pady 10 -sticky EW
grid .n.m.players.p2lbl -row 2 -column 0
grid .n.m.players.p2name -row 2 -column 1 -sticky EW
grid .n.m.players.p2score -row 2 -column 2
grid .n.m.players.p2win -row 2 -column 3 -padx {5 0} -sticky NS
grid .n.m.buttons -row 2 -column 0 -sticky W -pady {10 0}
grid .n.m.buttons.apply -row 0 -column 0
grid .n.m.buttons.discard -row 0 -column 1
grid .n.m.buttons.reset -row 0 -column 2
grid .n.m.buttons.swap -row 0 -column 3
grid .n.m.status -row 3 -column 0 -columnspan 4 -pady {10 0} -sticky EW
grid columnconfigure .n.m 0 -weight 1
grid rowconfigure .n.m 1 -weight 1
grid columnconfigure .n.m.players 1 -weight 1
grid columnconfigure .n.m.players 2 -pad 5
grid columnconfigure .n.m.buttons 1 -pad 15
grid columnconfigure .n.m.buttons 3 -pad 15

proc initialize {} {
    loadicon
    loadstartgg
    loadwebmsg
    loadscoreboard
    loadplayernames

    setupdiffcheck
    setupplayersuggestion


    # By default this window is not focused and not even brought to
    # foreground on Windows. I suspect it's because tcl is exec'ed from Go.
    # The old "iconify, deiconify" trick no longer seems to work, so this time
    # I'm passing it to Go to call the winapi's SetForegroundWindow directly.
    if {$::tcl_platform(platform) == "windows"} {
        windows_forcefocus
    }
}

# Very simple line-based IPC system where Tcl client talks to Go server
# via stdin/stdout
proc ipc_write {method args} {
    puts "$method [llength $args]"
    foreach a $args {
        puts "$a"
    }
}
proc ipc_read {} {
    set results {}
    set numlines [gets stdin]
    for {set i 0} {$i < $numlines} {incr i} {
        lappend results [gets stdin]
    }
    return $results
}
proc ipc {method args} {
    ipc_write $method {*}$args
    return [ipc_read]
}

proc windows_forcefocus {} {
    # First call winapi's SetForegroundWindow()
    set handle [winfo id .]
    ipc "forcefocus" $handle
    # Then call force focus on tcl side
    focus -force .
    # We must do both in order to properly focus on main tk window.
    # Don't ask me why - that's just how it works.
    #
    # Alternatively we can try making Tcl our entrypoint instead of exec-ing
    # Tcl from Go. Maybe some other time.
}

proc loadicon {} {
    set iconblob [image create photo -file kwtekken-icon.png]
    wm iconphoto . -default $iconblob
}

proc loadstartgg {} {
    set resp [ipc "getstartgg"]
    set ::startgg(token) [lindex $resp 0]
    set ::startgg(slug) [lindex $resp 1]
}

proc loadwebmsg {} {
    set resp [ipc "getwebport"]
    set webport [lindex $resp 0]
    set ::mainstatus "Point your OBS browser source to http://localhost:${webport}"
}

proc mark_settings_changed {} {
    set ::mainstatus "Settings changed. Click Apply to update OBS overlay."
}

proc openstartggsettings {} {
    if {[winfo exists .startgg]} {
        raise .startgg
        focus .startgg.body.token
        return
    }

    toplevel .startgg
    wm title .startgg "start.gg Settings"
    wm transient .startgg .
    wm minsize .startgg 420 140
    ttk::frame .startgg.body -padding 10
    ttk::label .startgg.body.tokenlbl -text "Personal token"
    ttk::entry .startgg.body.token -show * -textvariable startgg(token)
    ttk::label .startgg.body.tournamentlbl -text "Tournament slug"
    ttk::entry .startgg.body.tournamentslug -textvariable startgg(slug)
    ttk::frame .startgg.body.buttons
    ttk::button .startgg.body.buttons.fetch -text "↓ Fetch players" -command fetchplayers
    ttk::button .startgg.body.buttons.clear -text "✘ Clear" -command clearstartgg
    ttk::button .startgg.body.buttons.close -text "Close" -command {destroy .startgg}
    ttk::label .startgg.body.msg -textvariable startgg(msg)

    grid .startgg.body -row 0 -column 0 -sticky NESW
    grid .startgg.body.tokenlbl -row 0 -column 0 -sticky W -padx {0 8}
    grid .startgg.body.token -row 0 -column 1 -sticky EW
    grid .startgg.body.tournamentlbl -row 1 -column 0 -sticky W -padx {0 8}
    grid .startgg.body.tournamentslug -row 1 -column 1 -sticky EW
    grid .startgg.body.buttons -row 2 -column 1 -sticky W
    grid .startgg.body.buttons.fetch -row 0 -column 0 -sticky W
    grid .startgg.body.buttons.clear -row 0 -column 1 -sticky W -padx 5
    grid .startgg.body.buttons.close -row 0 -column 2 -sticky W
    grid .startgg.body.msg -row 3 -column 1 -sticky W
    grid columnconfigure .startgg.body 1 -weight 1
    grid rowconfigure .startgg.body 1 -pad 5
    grid rowconfigure .startgg.body 2 -pad 5
    grid columnconfigure .startgg 0 -weight 1
    grid rowconfigure .startgg 0 -weight 1
    focus .startgg.body.token
}

proc set_startgg_controls_state {state} {
    if {![winfo exists .startgg]} {
        return
    }
    .startgg.body.buttons.fetch configure -state $state
    .startgg.body.buttons.clear configure -state $state
    .startgg.body.buttons.close configure -state $state
    .startgg.body.token configure -state $state
    .startgg.body.tournamentslug configure -state $state
}

proc loadscoreboard {} {
    set sb [ipc "getscoreboard"]
    set ::scoreboard(description) [lindex $sb 0]
    set ::scoreboard(subtitle) ""
    set ::scoreboard(p1name) [lindex $sb 2]
    set ::scoreboard(p1country) ""
    set ::scoreboard(p1score) [lindex $sb 4]
    set ::scoreboard(p1team) ""
    set ::scoreboard(p2name) [lindex $sb 6]
    set ::scoreboard(p2country) ""
    set ::scoreboard(p2score) [lindex $sb 8]
    set ::scoreboard(p2team) ""
    set ::scoreboard(font) [lindex $sb 10]
    if {$::scoreboard(font) == ""} {
        set ::scoreboard(font) "Bahnschrift"
    }
    update_applied_scoreboard
}

proc applyscoreboard {} {
    set sb [ \
        ipc "applyscoreboard" \
        $::scoreboard(description) \
        "" \
        $::scoreboard(p1name) \
        "" \
        $::scoreboard(p1score) \
        "" \
        $::scoreboard(p2name) \
        "" \
        $::scoreboard(p2score) \
        "" \
        $::scoreboard(font) \
    ]
    update_applied_scoreboard
    loadwebmsg
}

proc increment_score {key} {
    if {![string is integer -strict $::scoreboard($key)]} {
        set ::scoreboard($key) 0
    }
    incr ::scoreboard($key)
}

proc loadplayernames {} {
    set playernames [ipc "searchplayers" ""]
    .n.m.players.p1name configure -values $playernames
    .n.m.players.p2name configure -values $playernames
}

proc setupplayersuggestion {} {
    proc update_suggestions {_ key _} {
        if {!($key == "p1name" || $key == "p2name")} {
            return
        }
        set newvalue $::scoreboard($key)
        set widget .n.m.players.$key
        set matches [ipc "searchplayers" $newvalue]
        $widget configure -values $matches
    }
    trace add variable ::scoreboard write update_suggestions
}

proc fetchplayers {} {
    if {$::startgg(token) == "" || $::startgg(slug) == ""} {
        set ::startgg(msg) "Please enter token & slug first."
        return
    }
    set_startgg_controls_state disabled
    set ::startgg(msg) "Fetching..."
    ipc_write "fetchplayers" $::startgg(token) $::startgg(slug)
}

proc fetchplayers__resp {} {
    set resp [ipc_read]
    set status [lindex $resp 0]
    set msg [lindex $resp 1]

    set ::startgg(msg) $msg

    if {$status == "ok"} {
        loadplayernames
    }

    set_startgg_controls_state normal
}

proc clearstartgg {} {
    set ::startgg(token) ""
    set ::startgg(slug) ""
    set ::startgg(msg) ""
    ipc_write "clearstartgg"
}

proc discardscoreboard {} {
    foreach key [array names ::scoreboard] {
        set ::scoreboard($key) $::applied_scoreboard($key)
    }
}

proc update_applied_scoreboard {} {
    foreach key [array names ::scoreboard] {
        set ::applied_scoreboard($key) $::scoreboard($key)
    }
}

proc setupdiffcheck {} {
    # Define styling for "dirty"
    foreach x {TEntry TCombobox TSpinbox} {
        ttk::style configure "Dirty.$x" -fieldbackground #dffcde
    }

    trace add variable ::scoreboard write ::checkdiff
    trace add variable ::applied_scoreboard write ::checkdiff
}

proc checkdiff {_ key _} {
    if {![info exists ::var_to_widget($key)]} {
        return
    }
    set widget $::var_to_widget($key)
    if {$::scoreboard($key) == $::applied_scoreboard($key)} {
        $widget configure -style [winfo class $widget]
    } else {
        $widget configure -style "Dirty.[winfo class $widget]"
    }
}
