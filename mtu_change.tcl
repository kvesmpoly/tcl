::cisco::eem::event_register_none maxrun 120
#
# Politica EEM (TCL) para IOS XR - cambio de MTU de UNA interfaz, ejecutada por el
# EEM del router (no depende de la sesion SSH). Pensada para XR 32-bit 6.x (ASR9k);
# en prueba tambien en XR 64-bit (8201).
#
#   event manager run mtu_change.tcl Bundle-Ether16 9114
#
# Flujo (las validaciones PRE/POST las hace el orquestador):
#   1. configure / interface <if> / shutdown / mtu <mtu> / commit / end
#   2. esperar 10 segundos
#   3. configure / interface <if> / no shutdown / commit / end  (aunque falle el paso 1)
# Resultado en syslog: show logging | include MTU_POC
#
namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

proc run {fd cmds} {
    foreach c $cmds {
        set r [cli_exec $fd $c]
        if {[regexp {% Invalid|% Incomplete|% Ambiguous|% Failed|% Error} $r]} {
            error "$c -> [string trim $r]"
        }
    }
}

array set info [event_reqinfo]
# Sin argumentos no se toca nada; se deja en el log lo que llego para diagnosticar.
if {![info exists info(arg1)] || ![info exists info(arg2)]} {
    action_syslog priority err msg "MTU_POC RESULT=FAILED INTF=? MTU=? MSG=no llegaron los argumentos: [array get info]"
    exit 1
}
set intf $info(arg1)
set mtu $info(arg2)
set errores {}

if {[catch {cli_open} r]} {
    action_syslog priority err msg "MTU_POC RESULT=FAILED INTF=$intf MTU=$mtu MSG=cli_open: $r"
    exit 1
}
array set cli $r

if {[catch {
    run $cli(fd) [list "configure" "interface $intf" "shutdown" "mtu $mtu" "commit" "end"]
    after 10000
} e]} {
    lappend errores "paso 1: $e"
    # Si el paso 1 fallo dentro de configure, descartar lo pendiente antes del paso 3.
    catch {cli_exec $cli(fd) "abort"}
}

if {[catch {
    run $cli(fd) [list "configure" "interface $intf" "no shutdown" "commit" "end"]
} e]} {
    lappend errores "paso 3: $e"
}

catch {cli_close $cli(fd) $cli(tty_id)}

if {[llength $errores]} {
    action_syslog priority err msg "MTU_POC RESULT=FAILED INTF=$intf MTU=$mtu MSG=[join $errores { | }]"
} else {
    action_syslog priority info msg "MTU_POC RESULT=SUCCESS INTF=$intf MTU=$mtu MSG=ok"
}
