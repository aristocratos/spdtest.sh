#!/usr/bin/env bash
# shellcheck disable=SC1090  #can't follow non constant source
# shellcheck disable=SC2034  #unused variables

#? @note TODOs

# TODO Fix argument parsing and error messages
# TODO Change slowtest to multiple servers and compare results
# TODO fix wrong keypress in inputwait, esc codes etc
# TODO makefile to getIdle
# TODO fix up README.md
# TODO extern config and save to config?
# TODO ssh controlmaster, server, client
# TODO grc funtion in bash function?
# TODO plot speedgraphs overtime in UI
# TODO translate remaining swedish...
# TODO options menu, window box function
# TODO grc, grc.conf, speedtest and speedtest-cli to /dev/shm ?
# TODO fix buffer reset on buffer add or on any keypress in loop, "if scrolled -gt 0"
# TODO buffer optional save between sessions


#?> Start variables ------------------------------------------------------------------------------------------------------------------> @note Start variables
net_device="auto"		#* Network interface to get current speed from, set to "auto" to get default interface from "ip route" command
unit="mbit"				#* Valid values are "mbit" and "mbyte"
slowspeed="30"			#* Download speed in unit defined above that triggers more tests, recommended set to 10%-40% of your max speed
numservers="30"			#* How many of the closest servers to get from "speedtest-cli --list", used as random pool of servers to test against
slowretry="1"			#* When speed is below slowspeed, how many retries of random servers before running full tests
numslowservers="8"		#* How many of the closest servers from list to test if slow speed has been detected, tests all if not set
precheck="true"			#* Check current bandwidth usage before slowcheck, blocks if speed is higher then values set below
precheck_samplet="5"	#* Time in seconds to sample bandwidth usage, defaults to 5 if not set
precheck_down="50"		#* Download speed in unit defined above that blocks slowcheck
precheck_up="50"		#* Upload speed in unit defined above that blocks slowcheck
waittime="00:15:00"		#* Default wait timer between slow checks, format: "HH:MM:SS"
slowwait="00:05:00"		#* Time between tests when slow speed has been detected, uses wait timer if unset, format: "HH:MM:SS"
idle="false"			#* If "true", resets timer if keyboard or mouse activity is detected in X Server, needs getIdle to work
# idletimer="00:30:00"	#* If set and idle="true", the script uses this timer until first test, then uses standard wait time,
						#* any X Server activity resets back to idletimer, format: "HH:MM:SS"
displaypause="false"	#* If "true" automatically pauses timer when display is on, unpauses when off, overrides idle="true" if set, needs xset to work
loglevel=2				#* 0 : No logging
						#* 1 : Log only when slow speed has been detected
						#* 2 : Also log slow speed check
						#* 3 : Also log server updates
						#* 4 : Log all including forced tests
quiet_start="true"		#* If "true", don't print serverlist and routelist at startup
maxlogsize="100"		#* Max logsize (in kilobytes) before log is rotated
# logcompress="gzip"	#* Command for compressing rotated logs, uncomment to enable
# logname=""			#* Custom logfile (full path), if a custom logname is set, log rotation is disabled
max_buffer="1000"		#* Max number of lines to buffer in internal scroll buffer, set to 0 to disable, disabled if use_shm="false"
buffer_save="true"		#* Save buffer to disk on exit and restore on start
mtr="true"				#* Set "false" to disable route testing with mtr, automatically set to "false" if mtr is not found in PATH
mtr_internal="true"		#* Use hosts from full test in mtr test
mtr_internal_ok="false"	#* Use hosts from full test with speeds above $slowspeed, set to false to only test hosts with speed below $slowspeed
# mtr_internal_max=""	#* Set max hosts to add from internal list
mtr_external="false"	#* Use hosts from route.cfg.sh, see route.cfg.sh.sample for formatting
mtrpings="25"			#* Number of pings sent with mtr
paused="false"			#* If "true", the timer is paused at startup, ignored if displaypause="true"
startuptest="false"		#* If "true" and paused="false", tests speed at startup before timer starts
testonly="false" 		#* If "true", never enter UI mode, always run full tests and quit
testnum=1				#* Number of times to loop full tests in testonly mode
use_shm="true"			#* Use /dev/shm shared memory for temp files, defaults to /tmp if /dev/shm isn't present

ookla_speedtest="speedtest"						#* Command or full path to official speedtest client 
speedtest_cli="speedtest-cli/speedtest.py"		#* Path to unofficial speedtest-cli

#! Variables below are for internal function, don't change unless you know what you are doing
if [[ $use_shm == true && -d /dev/shm ]]; then temp="/dev/shm"; else temp="/tmp"; max_buffer=0; fi
secfile="$temp/spdtest-sec.$$"
speedfile="$temp/spdtest-speed.$$"
routefile="$temp/spdtest-route.$$"
tmpout="$temp/spdtest-tmpout.$$"
bufferfile="$temp/spdtest-buffer.$$"
funcname=$(basename "$0")
startup=1
forcetest=0
detects=0
slowgoing=0
startupdetect=0
idledone=0
idlebreak=0
broken=0
updateservers=0
monitorOvr=0
pausetoggled=0
slowerror=0
stype=""
speedstring=""
chars="/-\|"
escape_char=$(printf "\u1b")
charx=0
animx=1
animout=""
bufflen=0
scrolled=0
buffsize=0
buffpos=0
precheck_status=""
precheck_samplet=${precheck_samplet:-5}
mtr_internal_max=${mtr_internal_max:-$numslowservers}
declare -a routelista; declare -a routelistadesc; declare -a routelistaport
declare -a routelistb; declare -a routelistbdesc; declare -a routelistbport
declare -a routelistc; declare -a routelistcdesc; declare -a routelistcport
declare -a testlista
declare -a rndbkp
declare -a errorlist
cd "$(dirname "$(readlink -f "$0")")" || { echo "Failed to set working directory"; exit 1; }
if [[ -e server.cfg.sh ]]; then servercfg="server.cfg.sh"; else servercfg="/dev/null"; fi
if [[ $use_shm != "true" && $max_buffer -ne 0 ]]; then max_buffer=0; fi

#? Colors
reset="\e[0m"
bold="\e[1m"
underline="\e[4m"
blink="\e[5m"
reverse="\e[7m"
dark="\e[2m"
italic="\e[3m"

black="\e[30m"
red="\e[31m"
green="\e[32m"
yellow="\e[33m"
blue="\e[34m"
magenta="\e[35m"
cyan="\e[36m"
white="\e[37m"

#? End variables -------------------------------------------------------------------------------------------------------------------->

command -v $ookla_speedtest >/dev/null 2>&1 || { echo "Error Ookla speedtest client not found"; exit 1; }
command -v $speedtest_cli >/dev/null 2>&1 || { echo "Error speedtest-cli missing"; exit 1; }
command -v grc/grcat >/dev/null 2>&1 || { echo "Error grc/grcat missing"; exit 1; }

#? Start argument parsing ------------------------------------------------------------------------------------------------------------------>
argumenterror() { #* Handles argument errors
	echo "Error:"
	case $1 in
		general) echo -e "$2 tnot a valid option" ;;
		server-config) echo "Can't find server config, use with flag -gs to create a new file" ;;
		missing) echo -e "$2 missing argument" ;;
		wrong) echo -e "$3 not a valid modifier for $2" ;;
	esac
	echo -e "$funcname -h, --help \tShows help information"
	exit 0
}

# re='^[0-9]+$'
while [[ $# -gt 0 ]]; do #* @note Parse arguments
	case $1 in
		-t|--test)
			testonly="true"
			if [[ -n $2 && ${2::1} != "-" ]]; then testnum="$2"; shift; fi
			testnum=${testnum:-1}
		;;
		-u|--unit)
			if [[ $2 == "mbyte" || $2 == "mbit" ]]; then unit="$2"; shift
			else argumenterror "wrong" "$1" "$2"; fi	
		;;
		-s|--slow-speed)
			if [[ -n $2 && ${2::1} != "-" ]]; then slowspeed="$2"; shift
			else argumenterror "missing" "$1"; fi
		;;
		-l|--loglevel)
			if [[ -n $2 && ${2::1} != "-" ]]; then loglevel="$2"; shift
			else argumenterror "missing" "$1"; fi
		;;
		-lf|--log-file)
			if [[ -n $2 && ${2::1} != "-" ]]; then logname="$2"; shift
			else argumenterror "missing" "$1"; fi
		;;
		-i|--interface)
			if [[ -n $2 && ${2::1} != "-" ]]; then net_device="$2"; shift
			else argumenterror "missing" "$1"; fi
		;;
		-p|--paused)
			paused="true"
		;;
		-n|--num-servers)
			if [[ -n $2 && ${2::1} != "-" ]]; then numservers="$2"; shift
			else argumenterror "missing" "$1"; fi
		;;
		-gs|--gen-server-cfg)
			updateservers=3
			genservers="true"
			servercfg=server.cfg.sh
			shift
		;;
		-sc|--server-config)
			if [[ -e $2 ]] || [[ $updateservers == 3 ]]; then servercfg="$2"; shift
			else argumenterror "server-config"; fi
		;;
		-wt|--wait-time)
			waittime="$2"
			shift
		;;
		-st|--slow-time)
			slowwait="$2"
			shift
		;;
		-x|--x-reset)
			idle="true"
			if [[ -n $2 && ${2::1} != "-" ]]; then idletimer="$2"; shift; fi
		;;
		-d|--display-pause)
			displaypause="true"
		;;
		--debug)
			debug=true
		;;
		-h|--help)
			echo -e "USAGE: $funcname [OPTIONS]"
			echo ""
			echo -e "OPTIONS:"
			echo -e "\t-t, --test num              Runs full test 1 or <x> number of times and quits"
			echo -e "\t-u, --unit mbit/mbyte       Which unit to show speed in, valid units are mbit or mbyte [default: mbit]"
			echo -e "\t-s, --slow-speed speed      Defines what speed in defined unit that will trigger more tests"
			echo -e "\t-n, --num-servers num       How many of the closest servers to get from speedtest.net"
			echo -e "\t-i, --interface name        Network interface being used [default: auto]"
			echo -e "\t-l, --loglevel 0-3          0 No logging"
			echo -e "\t                            1 Log only when slow speed has been detected"
			echo -e "\t                            2 Also log slow speed check and server update"
			echo -e "\t                            3 Log all including forced tests"
			echo -e "\t-lf, --log-file file        Full path to custom logfile, no log rotation is done on custom logfiles"
			echo -e "\t-p, --paused                Sets timer to paused state at startup"
			echo -e "\t-wt, --wait-time HH:MM:SS   Time between tests when NO slowdown is detected [default: 00:10:00]"
			echo -e "\t-st, --slow-time HH:MM:SS   Time between tests when slowdown has been detected, uses wait timer if unset"
			echo -e "\t-x, --x-reset [HH:MM:SS]    Reset timer if keyboard or mouse activity is detected in X Server"
			echo -e "\t                            If HH:MM:SS is included, the script uses this timer until first test, then uses"
			echo -e "\t                            standard wait time, any activity resets to idle timer [default: unset]"
			echo -e "\t-d, --display-pause         Automatically pauses timer when display is on, unpauses when off"
			echo -e "\t-gs, --gen-server-cfg num   Writes <x> number of the closest servers to \"server.cfg.sh\" and quits"
			echo -e "\t                            Servers aren't updated automatically at start if \"server.cfg.sh\" exists"
			echo -e "\t-sc, --server-config file   Reads server config from <file> [default: server.cfg.sh]"
			echo -e "\t                            If used in combination with -gs a new file is created"
			echo -e "\t-h, --help                  Shows help information"
			echo -e "CONFIG:"
			echo -e "\t                            Note: All config files should be stored in same folder as main script"
			echo -e "\tspdtest.sh                  Options can be permanently set in the Variables section of main script"
			echo -e "\t[server.cfg.sh]             Stores server id's to use with speedtest, delete to refresh servers on start"
			echo -e "\t[route.cfg.sh]              Additional hosts to test with mtr"
			echo -e "LOG:"
			echo -e "\t                            Logs are named spdtest<date>.log and saved in ./log folder of main script"
			exit 0
		;;
		*)
			argumenterror "general" "$1"
		;;
	esac
	shift
done

if [[ $loglevel -gt 4 ]]; then loglevel=4; fi
if [[ $unit = "mbyte" ]]; then unit="MB/s"; unitop="1"; else unit="Mbps"; unitop="8"; fi
if [[ $displaypause == "true" ]]; then idle="false"; fi
if [[ $net_device == "auto" ]]; then
	net_device=$(ip route | grep default | sed -e "s/^.*dev.//" -e "s/.proto.*//")
else
	# shellcheck disable=SC2013
	for good_device in $(grep ":" /proc/net/dev | awk '{print $1}' | sed "s/:.*//"); do
        if [[ "$net_device" = "$good_device" ]]; then
                is_good=1
                break
        fi
	done
	if [[ $is_good -eq 0 ]]; then
			echo "Net device \"$net_device\" not found. Should be one of these:"
			grep ":" /proc/net/dev | awk '{print $1}' | sed "s/:.*//"
			exit 1
	fi
fi

net_status="$(</sys/class/net/"$net_device"/operstate)"

#? End argument parsing ------------------------------------------------------------------------------------------------------------------>

#? Start functions ------------------------------------------------------------------------------------------------------------------>

ctrl_c() { #* Catch ctrl-c and general exit function, abort if currently testing otherwise cleanup and exit
	if [[ $testing == 1 ]]; then
		if kill -0 "$speedpid" >/dev/null 2>&1; then kill "$speedpid" >/dev/null 2>&1; fi
		if kill -0 "$routepid" >/dev/null 2>&1; then kill "$routepid" >/dev/null 2>&1; fi
		broken=1
		return
	else
		#writelog 1 "\nINFO: Script ended! ($(date +%Y-%m-%d\ %T))"
		if kill -0 "$secpid" >/dev/null 2>&1; then kill "$secpid" >/dev/null 2>&1; fi
		if kill -0 "$routepid" >/dev/null 2>&1; then kill "$routepid" >/dev/null 2>&1; fi
		if kill -0 "$speedpid" >/dev/null 2>&1; then kill "$speedpid" >/dev/null 2>&1; fi
		if kill -0 "$routepid" >/dev/null 2>&1; then kill "$routepid" >/dev/null 2>&1; fi
		rm $secfile >/dev/null 2>&1
		rm $speedfile >/dev/null 2>&1
		rm $routefile >/dev/null 2>&1
		rm $tmpout >/dev/null 2>&1
		if [[ $buffer_save == "true" && -e "$bufferfile" ]]; then cp -f "$bufferfile" .buffer >/dev/null 2>&1; fi
		rm $bufferfile >/dev/null 2>&1
		tput clear
		tput cvvis
		stty echo
		tput rmcup
		exit 0
		#if [[ -n $2 ]]; then echo -e "$2"; fi
		#exit "${1:-0}"
	fi
}

contains() { #* Function for checking if a value is contained in an array, arguments: <"${array[@]}"> <"value">
    local n=$#
    local value=${!n}
    for ((i=1;i < $#;i++)) {
        if [[ "${!i}" == "${value}" ]]; then
            return 0
        fi
    }
    return 1
}

waiting() { #* Show animation and text while waiting for background job, arguments: <pid> <"text">
			local text=$2
			local tdir=$3
			local i spaces=""
			while kill -0 "$1" >/dev/null 2>&1; do
				for (( i=0; i<${#chars}; i++ )); do
					sleep 0.2
					if [[ $broken == 1 ]]; then return; fi
					echo -en "${bold}${white}$text ${red}${chars:$i:1} ${reset}" "\r"
				done
			done

}

redraw() { #* Redraw menu if window is resized
	width=$(tput cols)
	if [[ $width -lt 106 ]]; then menuypos=2; else menuypos=1; fi
	titleypos=$((menuypos+1))
	buffpos=$((titleypos+1))
	height=$(tput lines)
	buffsize=$((height-buffpos-1))
	if [[ $startup -eq 1 ]]; then return; fi
	if [[ $max_buffer -eq 0 ]]; then tput sc; tput cup $buffpos 0; tput el; tput rc
	else buffer "redraw"; fi
	drawm
}

myip() { #* Get public IP
	dig @resolver1.opendns.com ANY myip.opendns.com +short
	}

getcspeed() { #* Get current $net_device bandwith usage, arguments: <down/up> <sleep> <["get"][value from previous get]>
	local line svalue speed total awkline slp=${2:-3} sdir=${1:-down}
	# shellcheck disable=SC2016
	if [[ $sdir == "down" ]]; then awkline='{print $1}'
	elif [[ $sdir == "up" ]]; then awkline='{print $9}'
	else return; fi
	line=$(grep "$net_device" /proc/net/dev | sed "s/.*://")
	svalue=$(echo "$line" | awk "$awkline")
	if [[ $3 == "get" ]]; then echo "$svalue"; return; fi
	if [[ -n $3 && $3 != "get" ]]; then speed=$(echo "($svalue - $3) / ($slp - ($slp * 0.028))" | bc); echo $(((speed*unitop)>>20)); return; fi
	total=$((svalue))
	sleep "$slp"
	line=$(grep "$net_device" /proc/net/dev | sed "s/.*://")
	svalue=$(echo "$line" | awk "$awkline")
	speed=$(echo "($svalue - $total) / ($slp - ($slp * 0.028))" | bc)
	echo $(((speed*unitop)>>20))
}

test_type_checker() { #* Check current type of test being run by speedtest
		speedstring=$(tail -n1 < $speedfile)
		stype=$(echo "$speedstring" | jq -r '.type')
		if [[ $broken == 1 ]]; then stype="broken"; fi
		if [[ $stype == "log" ]]; then slowerror=1; return; fi
		if ! kill -0 "$speedpid" >/dev/null 2>&1; then stype="ended"; fi
}

anim() { #* Gives a character for printing loading animation, arguments: <num>  Only print every num number of times
			if [[ $animx -eq $1 ]]; then
				if [[ $charx -ge ${#chars} ]]; then charx=0; fi
				animout="${chars:$charx:1}"; charx=$((charx+1)); animx=0
			fi
			animx=$((animx+1))
}

progress() { #* Print progress bar, arguments: <percent> [<"text">] [<text color>] [<reset color>]
	local text cs ce x i xp=0
	local percent=${1:-0}
	local text=${2:-$percent}
	if [[ -n $3 ]]; then cs="$3"; ce="${4:-$white}"; else cs=""; ce=""; fi
	if [[ ${#text} -gt 10 ]]; then text=${text::10}; fi
	echo -n "["
	if [[ ! $((${#text}%2)) -eq 0 ]]; then if [[ $percent -ge 10 ]]; then echo -n "="; else echo -n " "; fi; xp=$((xp+1)); fi
	for((x=1;x<=2;x++)); do
		for((i=0;i<((10-${#text})/2);i++)); do xp=$((xp+1)); if [[ $xp -le $((percent/10)) ]]; then echo -n "="; else echo -n " "; fi; done
		if [[ $x -eq 1 ]]; then echo -en "${cs}${text}${ce}"; xp=$((xp+${#text})); fi
	done
	echo -n "]"
}

precheck_speed() { #* Check current bandwidth usage before slowcheck
	testing=1
	local sndvald sndvalu i skip=1
	local dspeed=0
	local uspeed=0
	local ib=10
	local t=$((precheck_samplet*10))
	drawm "Checking bandwidth usage" "$yellow"
	echo -en "Checking bandwidth usage: ${bold}$(progress 0)${reset}\r"
	sndvald="$(getcspeed "down" 0 "get")"
	sndvalu="$(getcspeed "up" 0 "get")"
	for((i=1;i<=t;i++)); do
		prc=$(echo "scale=2; $i / $t * 100" | bc | cut -d . -f 1)
		if [[ $i -eq $ib ]]; then ib=$((ib+10)); dspeed=$(getcspeed "down" $((i/10)) "$sndvald"); uspeed=$(getcspeed "up" $((i/10)) "$sndvalu"); fi
		#dspeed=$(getcspeed "down" "$(echo "scale=1; $i / 10" | bc)" "$sndvald"); uspeed=$(getcspeed "up" "$(echo "scale=1; $i / 10" | bc)" "$sndvalu")
		echo -en "Checking bandwidth usage: ${bold}$(progress "$prc") ${green}DOWN=${white}$dspeed $unit ${red}UP=${white}$uspeed $unit${reset}         \r"
		sleep 0.1
		if [[ $broken == 1 ]]; then precheck_status="fail"; testing=0; tput el; tput el1; writelog 2 "\nWARNING: Precheck aborted!\n"; return; fi
	done
	tput el
	dspeed="$(getcspeed "down" $precheck_samplet "$sndvald")"
	uspeed="$(getcspeed "up" $precheck_samplet "$sndvalu")"
	if [[ $dspeed -lt $precheck_down && $uspeed -lt $precheck_up ]]; then
		precheck_status="ok"
		writelog 9 "Checking bandwidth usage: $(progress 100 "OK!") DOWN=$dspeed $unit UP=$uspeed $unit\r"; sleep 2; tput cuu1; tput el
	else
		precheck_status="fail"
		writelog 9 "Checking bandwidth usage: $(progress 100 "FAIL!") DOWN=$dspeed $unit UP=$uspeed $unit\r"; sleep 2; tput cuu1
		writelog 2 "WARNING: Testing blocked, current bandwidth usage: DOWN=$dspeed $unit UP=$uspeed $unit ($(date +%Y-%m-%d\ %T))"
	fi
	testing=0
	drawm
}

testspeed() { #* Using official Ookla speedtest client
	local mode=${1:-down}
	local max_tests cs ce cb warnings
	local tests=0
	local err_retry=0
	local xl=1
	local routetemp routeadd
	unset 'errorlist[@]'
	unset 'routelistb[@]'
	unset 'routelistbdesc[@]'
	RANDOM=$$$(date +%s)
	testing=1

	if [[ $mode == "full" && $numslowservers -ge ${#testlista[@]} ]]; then max_tests=$((${#testlista[@]}-1))
	elif [[ $mode == "full" && $numslowservers -lt ${#testlista[@]} ]]; then max_tests=$((numslowservers-1))
	elif [[ $mode == "down" ]]; then

		max_tests=$slowretry
		if [[ ${#testlista[@]} -gt 1 && $slowgoing == 0 ]]; then
			rnum="$RANDOM % ${#testlista[@]}"
			tl=${testlista[$rnum]}
		elif [[ ${#testlista[@]} -gt 1 && $slowgoing == 1 ]]; then
			rnum=${rndbkp[$xl]}
			tl=${testlista[$rnum]}
		else
			tl=${testlista[0]}
			rnum=0
		fi
	fi

	while [[ $tests -le $max_tests ]]; do #? Test loop start ------------------------------------------------------------------------------------>
		if [[ $mode == "full" ]]; then
			if [[ $slowgoing == 0 && $forcetest == 0 ]]; then
				writelog 1 "\n<---------------------------------------Slow speed detected!---------------------------------------->"
				slowgoing=1
			fi
			if [[ $tests == 0 ]]; then
				writelog 1 "Speedtest start: ($(date +%Y-%m-%d\ %T)), IP: $(myip)"
				printf "%-12s%-12s%-10s%-14s%-10s%-10s\n" "Down $unit" "Up $unit" "Ping" "Progress" "Time /s" "Server" | writelog 1
			fi
			printf "%-58s%s" "" "${testlistdesc[$tests]}" | writelog 9
			tput cuu1; drawm "Running full test" "$red"
			tl=${testlista[$tests]}
			routetemp=""
			routeadd=0
		elif [[ $mode == "down" ]]; then
			if [[ $tests -ge 1 ]]; then numstat="<-- Attempt $((tests+1))"; else numstat=""; fi
			printf "\r%5s%-4s%14s\t%s" "$down_speed " "$unit" "$(progress 0 "Init")" " ${testlistdesc[$rnum]} $numstat"| writelog 9
			#writelog 9 "${bold}Starting${reset}     \t  ${testlistdesc[$rnum]} $numstat"
			tput cuu1; drawm "Testing speed" "$green"
		fi

		stype=""; speedstring=""; echo "" > "$speedfile"

		$ookla_speedtest -s "$tl" -p yes -f json -I "$net_device" &>"$speedfile" &         #? <---------------- @note speedtest start
		speedpid="$!"

		x=1
		while [[ $stype == ""  || $stype == "null" || $stype == "testStart" ]]; do
			test_type_checker
			if [[ $x -eq 10 ]]; then
				anim 1
				if [[ $mode == "full" ]]; then printf "\r${bold}%-12s${reset}%-12s%-8s${bold}%16s${reset}" "     " "" "  " "$(progress 0 "Init $animout")    "
				#echo -en "\r${bold}Starting $animout ${reset}"
				elif [[ $mode == "down" ]]; then printf "\r${bold}%5s%-4s%14s\t${reset}" "$down_speed " "$unit" "$(progress 0 "Init $animout")"
				fi
				x=0
			fi
			sleep 0.01
			x=$((x+1))
		done

		while [[ $stype == "ping" ]]; do
			server_ping=$(echo "$speedstring" | jq '.ping.latency'); server_ping=${server_ping%.*}
			test_type_checker
			sleep 0.01
		done

		while [[ $stype == "download" ]]; do
			down_speed=$(echo "$speedstring" | jq '.download.bandwidth'); down_speed=$(((down_speed*unitop)>>20))
			down_progress=$(echo "$speedstring" | jq '.download.progress'); down_progress=$(echo "$down_progress*100" | bc -l 2> /dev/null)
			down_progress=${down_progress%.*}
			if [[ $mode == "full" ]]; then
				down_progress=$((down_progress/2))
				elapsed=$(echo "$speedstring" | jq '.download.elapsed'); elapsed=$(echo "scale=2; $elapsed / 1000" | bc 2> /dev/null)
				printf "\r${bold}%-12s${reset}%-12s%-8s${bold}%16s%-5s${reset}" "   $down_speed  " "" " $server_ping " "$(progress "$down_progress")    " " $elapsed  "
			else
				# printf "\r${bold}%-5s%-4s%-8s" "$down_speed" "$unit" "$down_progress%"
				# echo -en "\r${bold}$down_speed $unit   "
				# echo -en "\r\t  $down_progress%  ${reset}"
				printf "\r${bold}%5s%-4s%14s\t${reset}" "$down_speed " "$unit" "$(progress "$down_progress")"
			fi
			sleep 0.1
			test_type_checker
		done
		
		if [[ $mode == "down" ]]; then kill "$speedpid" >/dev/null 2>&1; fi
		
		while [[ $stype == "upload" && $mode != "down" ]]; do
			up_speed=$(echo "$speedstring" | jq '.upload.bandwidth'); up_speed=$(((up_speed*unitop)>>20))
			elapsed2=$(echo "$speedstring" | jq '.upload.elapsed'); elapsed2=$(echo "scale=2; $elapsed2 / 1000" | bc 2> /dev/null)
			elapsedt=$(echo "scale=2; $elapsed + $elapsed2" | bc 2> /dev/null)
			up_progress=$(echo "$speedstring" | jq '.upload.progress'); up_progress=$(echo "$up_progress*100" | bc -l 2> /dev/null)
			up_progress=${up_progress%.*}; up_progress=$(((up_progress/2)+50))
			#echo -en "\r   $down_speed  \t  $up_speed   \t$server_ping   \t    $(((up_progress/2)+50))%  \t  $elapsedt    "
			if [[ $up_progress -eq 100 ]]; then anim 1; up_progresst=" $animout "; cs="${bold}${green}"; ce="${white}"; cb=""; else up_progresst=""; cs=""; ce=""; cb="${bold}"; fi
			printf "\r%-12s$cb%-12s${reset}%-8s${bold}%-16s${reset}$cb%-5s${reset}" "   $down_speed  " "  $up_speed" " $server_ping " "$(progress "$up_progress" "$up_progresst" "$cs" "$ce")    " " $elapsedt  "
			sleep 0.1
			test_type_checker
		done
		
		#? ------------------------------------Checks--------------------------------------------------------------
		if [[ $broken == 1 ]]; then break; fi
		wait $speedpid

		if [[ $mode == "full" && $slowerror == 0 ]]; then
			sleep 0.1
			speedstring=$(jq -c 'select(.type=="result")' $speedfile)
			down_speed=$(echo "$speedstring" | jq '.download.bandwidth')
			down_speed=$(((down_speed*unitop)>>20))
			up_speed=$(echo "$speedstring" | jq '.upload.bandwidth')
			up_speed=$(((up_speed*unitop)>>20))
			server_ping=$(echo "$speedstring" | jq '.ping.latency'); server_ping=${server_ping%.*}
			packetloss=$(echo "$speedstring" | jq '.packetLoss')
			routetemp="$(echo "$speedstring" | jq -r '.server.host')"
			if [[ $down_speed -le $slowspeed ]]; then
				downst="FAIL!"
				if [[ $mtr_internal == "true" && ${#routelistb[@]} -lt $mtr_internal_max && -n $routetemp ]]; then routeadd=1; fi
			else 
				downst="OK!"
				if [[ $mtr_internal_ok == "true" && ${#routelistb[@]} -lt $mtr_internal_max && -n $routetemp ]]; then routeadd=1; fi
			fi

			if [[ $routeadd -eq 1 ]]; then
				routelistb+=("$routetemp")
				routelistbdesc+=("$(echo "$speedstring" | jq -r '.server.name') ($(echo "$speedstring" | jq -r '.server.location'), $(echo "$speedstring" | jq -r '.server.country'))")
				routelistbport+=("$(echo "$speedstring" | jq '.server.port')")
			fi
			
			if [[ -n $packetloss && $packetloss != "null" && $packetloss != 0 ]]; then warnings="WARNING: ${packetloss}% packet loss!"; fi

			printf "\r"; printf "%-12s%-12s%-8s%-16s%-10s%s%s" "   $down_speed  " "  $up_speed" " $server_ping " "$(progress "$up_progress" "$downst")    " " $elapsedt  " "${testlistdesc[$tests]}" "  $warnings" | writelog 1
			drawm "Running full test" "$red"
			tests=$((tests+1))
		
		elif [[ $mode == "full" && $slowerror == 1 ]]; then
			warnings="ERROR: Couldn't test server!"
			printf "\r"; printf "%-12s%-12s%-8s%-16s%-10s%s%s" "   $down_speed  " "  $up_speed" " $server_ping " "$(progress "$up_progress" "FAIL!")    " " $elapsedt  " "${testlistdesc[$tests]}" "  $warnings" | writelog 1
			drawm "Running full test" "$red"
			tests=$((tests+1))
		elif [[ $mode == "down" && $slowerror == 0 ]]; then
			if [[ $slowgoing == 0 ]]; then rndbkp[$xl]="$rnum"; xl=$((xl+1)); fi
			if [[ $down_speed -le $slowspeed ]]; then downst="FAIL!"; else downst="OK!"; fi
			if [[ $tdate != $(date +%d) ]]; then tdate="$(date +%d)"; timestamp="$(date +%H:%M\ \(%y-%m-%d))"; else timestamp="$(date +%H:%M)"; fi
			#writelog 2 "\r${bold}$down_speed $unit\t${reset}  $downst\t  ${testlistdesc[$rnum]} <Ping: $server_ping> $timestamp $numstat"
			printf "\r"; tput el; printf "%5s%-4s%14s\t%s" "$down_speed " "$unit" "$(progress $down_progress "$downst")" " ${testlistdesc[$rnum]} <Ping: $server_ping> $timestamp $numstat"| writelog 2
			lastspeed=$down_speed
			drawm "Testing speed" "$green"
			if [[ $down_speed -le $slowspeed && ${#testlista[@]} -gt 1 && $tests -lt $max_tests && $slowgoing == 0 ]]; then
				tl2=$tl
				while [[ $tl2 == "$tl" ]]; do
					rnum="$RANDOM % ${#testlista[@]}"
					tl2=${testlista[$rnum]}
				done
				tl=$tl2
				tests=$((tests+1))
			elif [[ $down_speed -le $slowspeed && ${#testlista[@]} -gt 1 && $tests -lt $max_tests && $slowgoing == 1 ]]; then
				xl=$((xl+1))
				rnum=${rndbkp[$xl]}
				tl=${testlista[$rnum]}
				tests=$((tests+1))
			else
				tests=$((max_tests+1))
			fi
		elif [[ $mode == "down" && $slowerror == 1 ]]; then
			err_retry=$((err_retry+1))
			errorlist+=("$tl")
			timestamp="$(date +%H:%M\ \(%y-%m-%d))"
			#tput el; writelog 2 "\r        \t\  FAIL! \t  ${testlistdesc[$rnum]} $timestamp  ERROR: Couldn't test server!"
			printf "\r"; tput el; printf "%5s%-4s%14s\t%s" "$down_speed " "$unit" "$(progress $down_progress "FAIL!")" " ${testlistdesc[$rnum]} $timestamp  ERROR: Couldn't test server!" | writelog 2
			drawm "Testing speed" "$green"
			if [[ ${#testlista[@]} -gt 1 && $err_retry -lt ${#testlista[@]} ]]; then
				tl2=$tl
				while [[ $(contains "${errorlist[@]}" "$tl2") ]]; do
					rnum="$RANDOM % ${#testlista[@]}"
					tl2=${testlista[$rnum]}
				done
				tl=$tl2
			else
				writelog 2 "\nERROR Couldn't get current speed from servers"
				testing=0
				return
			fi
		fi

		warnings=""
	done #? Test loop end ----------------------------------------------------------------------------------------------------------------------->
	if kill -0 "$speedpid" >/dev/null 2>&1; then kill "$speedpid" >/dev/null 2>&1; fi
	if [[ $broken == 1 && $mode == "full" ]]; then tput el; tput el1; writelog 1 "\nWARNING: Full test aborted!\n"; 
	elif [[ $broken == 1 && $mode == "down" ]]; then tput el; tput el1; writelog 2 "\nWARNING: Slow test aborted!\n"; 
	elif [[ $mode == "full" ]]; then writelog 1 " "; fi
	testing=0
}



routetest() { #* Test routes with mtr
	unset 'routelistc[@]'
	unset 'routelistcdesc[@]'
	unset 'routelistcport[@]'

	local i ttime tcount pcount prc secs dtext port
	
	if [[ $mtr == "false" ]] || [[ $broken == 1 ]]; then return; fi
	testing=1

	if [[ -n ${routelistb[0]} ]]; then	
		routelistc+=("${routelistb[@]}")
		routelistcdesc+=("${routelistbdesc[@]}")
		routelistcport+=("${routelistbport[@]}")
	fi

	if [[ -n ${routelista[0]} ]]; then
		routelistc+=("${routelista[@]}")
		routelistcdesc+=("${routelistadesc[@]}")
		routelistcport+=("${routelistaport[@]}")
	fi
		
	if [[ -z ${routelistc[0]} ]]; then testing=0; return; fi

	for((i=0;i<${#routelistc[@]};i++)); do
		if ping -qc1 -w5 "${routelistc[$i]}" > /dev/null 2>&1; then
			echo "Routetest: ${routelistcdesc[$i]} ${routelistc[$i]} ($(date +%T))" | writelog 1
			drawm "Running route test..." "$green"
			
			if [[ ${routelistcport[$i]} == "auto" || ${routelistcport[$i]} == "null" || -z ${routelistcport[$i]} ]]; then port=""
			else port="-P ${routelistcport[$i]}"; fi
			# shellcheck disable=SC2086
			mtr -wbc "$mtrpings" -I "$net_device" $port "${routelistc[$i]}" > "$routefile" &
			routepid="$!"
			
			ttime=$((mtrpings+5))
			tcount=1; pcount=1; dtext=""
			
			printf "\r%s${bold}%s${reset}%s" "Running mtr  " "$(progress "$prc" "$dtext" "${green}")" "  Time left: "
			printf "${bold}${yellow}<%02d:%02d>${reset}" $(((ttime/60)%60)) $((ttime%60))
			while kill -0 "$routepid" >/dev/null 2>&1; do
				prc=$(echo "scale=2; $pcount / ($ttime * 5) * 100" | bc | cut -d . -f 1)
				if [[ $pcount -gt $((ttime*5)) ]]; then anim 1; prc=100; dtext=" $animout "; tcount=$((tcount-1)); fi
				printf "\r%s${bold}%s${reset}%s" "Running mtr  " "$(progress "$prc" "$dtext" "${green}")" "  Time left: "
				if [[ $tcount -eq 5 ]]; then
					secs=$((ttime-(pcount/5)))
					printf "${bold}${yellow}<%02d:%02d>${reset}" $((((ttime-(pcount/5))/60)%60)) $(((ttime-(pcount/5))%60))
					tcount=0
				fi
				sleep 0.2
				tcount=$((tcount+1)); pcount=$((pcount+1))
			done

			echo -en "\r"; tput el

			if [[ $broken == 1 ]]; then break; fi
			writelog 1 "$(tail -n+2 <$routefile)\n"

			drawm
		else
			echo "Routetest: ${routelistcdesc[$i]} ${routelistc[$i]} ($(date +%T))" | writelog 1
			echo "ERROR: Host not reachable!" | writelog 1
			drawm
		fi
		done
		writelog 1 " "
	if [[ $broken == 1 ]]; then tput el; tput el1; writelog 1 "\nWARNING: Route tests aborted!\n"; fi
	testing=0
}

monitor() { #* Check if display is on with xset
		xset q | grep -q "Monitor is On" && echo on || echo off
}

logrotate() { #* Rename logfile, compress and create new if size is over $logsize
	if [[ -n $logname ]]; then
		logfile="$logname"
	else
		logfile="log/spdtest.log"
		if [[ $loglevel == 0 ]]; then return; fi
		if [[ ! -d log ]]; then mkdir log; fi
		touch $logfile
		logsize=$(du $logfile | tr -s '\t' ' ' | cut -d' ' -f1)
		if [[ $logsize -gt $maxlogsize ]]; then
			ts=$(date +%y-%m-%d-T:%H:%M)
			mv $logfile "log/spdtest.$ts.log"
			touch $logfile
			# shellcheck disable=SC2154
			if [[ -n $logcompress ]]; then $logcompress "log/spdtest.$ts.log"; fi
		fi
	fi
}

writelog() { #* Write to logfile and colorise terminal output with grc
	if [[ $loglevel -eq 1000 ]]; then return; fi
	declare input=${2:-$(</dev/stdin)};

	if [[ $1 -le $loglevel || $loglevel -eq 103  ]]; then file="$logfile"; else file="/dev/null"; fi
	if [[ $loglevel -eq 103 ]]; then echo -en "$input\n" > "$file"; return; fi

	echo -en "$input\n" | tee -a "$file" | cut -c -"$width" | grc/grcat

	if [[ $1 -le 8 && $testonly != "true" && $loglevel -ne 103 ]]; then buffer add "$input"; fi
  
}

buffline() { #* Get current buffer from scroll position and window height, cut off text wider than window width
	echo -e "$(<$bufferfile)" | tail -n$((buffsize+scrolled)) | head -n "$buffsize" | cut -c -"$((width-1))" | grc/grcat
}


buffer() { #* Buffer control, arguments: add/up/down/pageup/pagedown/redraw/clear ["text to add to buffer"]
	if [[ $max_buffer -eq 0 ]]; then return; fi	
	local buffout scrtext y x
	bufflen=$(wc -l <"$bufferfile")

	if [[ $1 == "add" && -n $2 ]]; then
		local addlen addline buffer
		scrolled=0
		addline="$2"
		addlen=$(echo -en "$addline" | wc -l)
		if [[ $addlen -ge $max_buffer ]]; then echo "$addline" | tail -n"$max_buffer" > "$bufferfile"
		elif [[ $((bufflen+addlen)) -gt $max_buffer ]]; then buffer="$(tail -n+$(((bufflen+addlen)-max_buffer)) <"$bufferfile")$addline"; echo "$buffer" > "$bufferfile"
		else echo -e "${buffer}${addline}" >> "$bufferfile"
		fi
		bufflen=$(wc -l <"$bufferfile")
		drawscroll
		return

	elif [[ $1 == "up" && $bufflen -gt $buffsize && $scrolled -lt $((bufflen-(buffsize+2))) ]]; then
	scrolled=$((scrolled+1))
	tput cup $buffpos 0
	buffout=$(buffline)
	tput ed; echo -e "$buffout"

	elif [[ $1 == "down" && $scrolled -ne 0  ]]; then
	scrolled=$((scrolled-1))
	buffout=$(buffline)
	tput cup $buffpos 0; tput ed; tput ll
	echo -e "$buffout"
	
	elif [[ $1 == "pageup" && $bufflen -gt $buffsize && $scrolled -lt $((bufflen-(buffsize+2))) ]]; then
	scrolled=$((scrolled+buffsize))
	if [[ $scrolled -gt $((bufflen-(buffsize+2))) ]]; then scrolled=$((bufflen-(buffsize+2))); fi
	tput cup $buffpos 0
	buffout=$(buffline)
	tput ed; echo -e "$buffout"
	
	elif [[ $1 == "pagedown" && $scrolled -ne 0 ]]; then
	scrolled=$((scrolled-buffsize))
	if [[ $scrolled -lt 0 ]]; then scrolled=0; fi
	buffout=$(buffline)
	tput cup $buffpos 0; tput ed
	echo -e "$buffout"

	elif [[ $1 == "redraw" ]]; then
		scrolled=0
		buffout=$(buffline)
		tput cup $buffpos 0; tput ed
		echo -e "$buffout"
		if [[ $testing -eq 1 ]]; then echo; fi

	elif [[ $1 == "clear" ]]; then
		true > "$bufferfile"
		scrolled=0
		tput cup $buffpos 0; tput ed
	fi

	# tput sc
	# scrtxt="[Bfr: $(((bufflen-buffsize)-scrolled))=>$((bufflen-scrolled))]"
	# tput cup $((titleypos+1)) $((width-20)); echo -en "${bold}[Bfr: $((((bufflen-2)-buffsize)-scrolled))=>$(((bufflen-2)-scrolled))]${reset}"
	# tput rc
	drawscroll

	sleep 0.001
}

drawscroll() {
	tput sc
	if [[ $scrolled -gt 0 && $scrolled -lt $((bufflen-(buffsize+2))) ]]; then
		tput cup $titleypos $((width-4)); echo -en "[↕]"
	elif [[ $scrolled -gt 0 && $scrolled -ge $((bufflen-(buffsize+2))) ]]; then
		tput cup $titleypos $((width-4)); echo -en "[↓]"
	elif [[ $scrolled -eq 0 && $bufflen -gt $buffsize ]]; then
		tput cup $titleypos $((width-4)); echo -en "[↑]"
	fi

	if [[ $scrolled -gt 0 && $scrolled -le $((bufflen-(buffsize+2))) ]]; then 
		y=$(echo "scale=2; $scrolled / ($bufflen-($buffsize+2)) * ($buffsize+2)" | bc); y=${y%.*}; y=$(((buffsize-y)+(buffpos+2)))
		tput cup "$y" $((width-1)); echo -en "${reverse}░${reset}"
	fi
	tput rc
}

drawm() { #* Draw menu and title, arguments: <"title text"> <bracket color 30-37> <sleep time>
	if [[ $testonly == "true" ]]; then return; fi
	tput sc
	tput cup 0 0; tput el
	echo -e "[${bold}${underline}${red}Q${reset}${bold}uit] [H${underline}${yellow}e${reset}${bold}lp] [$funcname]\c"
	if [[ -n $lastspeed ]]; then
		echo -e " [Last: $lastspeed $unit]\c"
	fi
	if [[ $detects -ge 1 && $width -ge 100 ]]; then
		echo -e " [Slow detects: $detects]\c"
	fi
	logt="[Log:][${underline}${magenta}V${reset}${bold}iew][${logfile##log/}]"
	logtl=$(echo -e "$logt" | sed "s,\x1B\[[0-9;]*[a-zA-Z],,g")
	tput cup 0 $((width-${#logtl}))
	echo -e "$logt"
	if [[ $paused == "true" ]]; then ovs="${green}On${white}"; else ovs="${red}Off${white}"; fi
	if [[ $idle == "true" ]]; then idl="${green}On${white}"; else idl="${red}Off${white}"; fi
	tput cup 1 0; tput el
	echo -en "[Timer:][${underline}${green}HMS${reset}${bold}+][${underline}${red}hms${reset}${bold}-][S${underline}${yellow}a${reset}${bold}ve][${underline}${blue}R${reset}${bold}eset][${underline}${magenta}I${reset}${bold}dle $idl][${underline}${yellow}P${reset}${bold}ause $ovs] [${underline}${green}T${reset}${bold}est] [${underline}${cyan}F${reset}${bold}orce test] "
	if [[ $menuypos == 2 ]]; then tput cup 2 0; tput el; fi
	echo -en "[${underline}${magenta}U${reset}${bold}pdate servers] [${underline}${yellow}C${reset}${bold}lear screen]"
	tput cup $titleypos 0
	printf "${bold}%0$(tput cols)d${reset}" 0 | tr '0' '='
	if [[ -n $1 ]]; then tput cup "$titleypos" $(((width / 2)-(${#1} / 2)))
	echo -en "${bold}${2:-$white}[${white}$1${2:-$white}]${reset}"
	sleep "${3:-0}"
	fi
	tput rc
	drawscroll
}

tcount() { #* Run timer count in background and write to shared memory
	lsec="$1"
	echo "$lsec" > "$secfile"
	secbkp=$((lsec + 1))
	while [[ $lsec -gt 0 ]]; do
		if [[ $idle == "true" ]] && [[ $(./getIdle) -lt 1 ]]; then
		lsec=$secbkp
		fi
		sleep 1
		lsec=$((lsec - 1))
		echo "$lsec" > "$secfile"
	done
}

printhelp() { #* Prints help information in UI
	echo ""
	echo -e "Key:              Descripton:                           Key:              Description:"
	echo -e "q                 Quit                                  e                 Show help information"
	echo -e "c                 Clear screen                          v                 View current logfile with less"
	echo -e "H                 Add 1 hour to timer                   h                 Remove 1 hour from timer"
	echo -e "M                 Add 1 minute to timer                 m                 Remove 1 minute from timer"
	echo -e "S                 Add 1 second to timer                 s                 Remove 1 second from timer"
	echo -e "a                 Save wait timer                       r                 Reset wait timer"
	echo -e "i                 Reset timer on X Server activity      p                 Pause timer"
	echo -e "t                 Test if speed is slow                 f                 Run full tests without slow check"
	echo -e "u                 Update serverlist\n"
	}

getservers() { #* Gets servers from speedtest-cli and optionally saves to file
	unset 'testlista[@]'
	unset 'testlistdesc[@]'
	unset 'routelista[@]'
	unset 'routelistadesc[@]'
	local IFS=$'\n'

	if [[ $quiet_start = "true" && $loglevel -ge 3 ]]; then bkploglevel=$loglevel; loglevel=103
	elif [[ $quiet_start = "true" && $loglevel -lt 3 ]]; then bkploglevel=$loglevel; loglevel=1000; fi

	if [[ -e $servercfg && $servercfg != "/dev/null" && $updateservers = 0 ]]; then
		source "$servercfg"
		writelog 3 "\nUsing servers from $servercfg"
		local num=1
		for tl in "${testlistdesc[@]}"; do
			writelog 3 "$num. $tl"
			num=$((num+1))
		done
	else
		echo "#? Automatically generated server list, servers won't be refreshed at start if this file exists" >> "$servercfg"
		$speedtest_cli --list  > $tmpout &
		waiting $! "Fetching servers"; tput el
		speedlist=$(head -$((numservers+1)) "$tmpout" | sed 1d)
		writelog 3 "Using servers:         "
		local num=1
		for line in $speedlist; do
			servnum=${line:0:5}
			servnum=${servnum%)}
			servnum=${servnum# }
			testlista+=("$servnum")
			servlen=$((${#line} - 6))
			servdesc=${line:(-servlen)}
			servdesc=${servdesc# }
			testlistdesc+=("$servdesc")
			echo -e "testlista+=(\"$servnum\");\t\ttestlistdesc+=(\"$servdesc\")" >> "$servercfg"
			writelog 3 "$num. $servdesc"
			num=$((num+1))
		done
	fi
	if [[ $numslowservers -ge $num ]]; then numslowservers=$((num-1)); fi
	numslowservers=${numslowservers:-$((num-1))}
	writelog 3 "\n"
	if [[ -e route.cfg.sh && $startup == 1 && $genservers != "true" && $mtr == "true" && $mtr_external == "true" ]]; then
		# shellcheck disable=SC1091
		source route.cfg.sh
		writelog 3 "Hosts in route.cfg.sh:"
		for((i=0;i<${#routelista[@]};i++)); do
			writelog 3 "(${routelistadesc[$i]}): ${routelista[$i]}"
		done
		writelog 3 "\n"
	fi

	if [[ $quiet_start = "true" ]]; then loglevel=$bkploglevel; fi
}

inputwait() { #* Timer and input loop
	drawm

	local IFS=:
	# shellcheck disable=SC2048
	# shellcheck disable=SC2086
	set -- $*
	if [[ -n $waitsaved && $idle != "true" ]]; then
		secs=$waitsaved
	elif [[ -n $idlesaved && $idle == "true" ]]; then
		secs=$idlesaved
	else
		secs=$(( ${1#0} * 3600 + ${2#0} * 60 + ${3#0} ))
	fi
	stsecs=$secs
	if [[ $paused = "false" ]]; then
		tcount $secs &
		secpid="$!"
	fi
	unset IFS


	while [[ $secs -gt 0 ]]; do
		tput sc; tput cup $titleypos $(((width / 2)-4))
		if [[ $secs -le 10 ]]; then
			printf "${bold}[%02d:%02d:${red}%02d${reset}" $((secs/3600)) $(((secs/60)%60)) $((secs%60))
		else
			printf "${bold}[%02d:%02d:%02d]${reset}" $((secs/3600)) $(((secs/60)%60)) $((secs%60))
			#printf "${bold}[%02d:%02d:%02d]${reset}%s" $((secs/3600)) $(((secs/60)%60)) $((secs%60)) " $scrolled  $(wc -l <"$bufferfile")  $buffsize"
		fi
		tput rc
		
		read -srd '' -t 0.0001 -n 10000
		# shellcheck disable=SC2162
		read -srn 1 -t 0.9999 keyp
		if [[ $keyp == "$escape_char" ]]; then read -rsn3 -t 0.0001 keyp ; fi
		case "$keyp" in
			'[A') buffer "up" ;;
			'[B') buffer "down" ;;
			'[5~') buffer "pageup" ;;
			'[6~') buffer "pagedown" ;;
			p|P)
				if [[ $displaypause == "true" && $paused == "true" ]]; then monitorOvr=1
				elif [[ $displaypause == "true" && $paused == "false" ]] ; then monitorOvr=0; fi
				pausetoggled=1
				;;
			t|T) break ;;
			i|I)
				if [[ $idle == "true" && -n $idletimer ]]; then idlebreak=1; idledone=0; idle="false"; break
				elif [[ $idle == "false" && -n $idletimer ]]; then idlebreak=1; idledone=0; idle="true"; break
				fi
				if [[ $idle == "true" ]]; then idle="false"; else idle="true"; fi
				secs=$stsecs; updatesec=1; drawm
				;;
			H) secs=$(( secs + 3600 )); updatesec=1;;
			h) if [[ $secs -gt 3600 ]]; then secs=$(( secs - 3600 )) ; updatesec=1; fi ;;
			M) secs=$(( secs + 60 )); updatesec=1 ;;
			m) if [[ $secs -gt 60 ]]; then secs=$(( secs - 60 )); updatesec=1 ; fi ;;
			S) secs=$(( secs + 1 )); updatesec=1 ;;
			s) if [[ $secs -gt 1 ]]; then secs=$(( secs - 1 )); updatesec=1 ; fi ;;
			a|A)
				if [[ -n $idletimer ]] && [[ $idle == "true" ]]; then idlesaved=$secs
				else waitsaved=$secs; fi
				updatesec=1
				drawm "Timer saved!" "$green" 2; drawm
				;;
			r|R) unset waitsaved ; secs=$stsecs; updatesec=1 ;;
			f|F) forcetest=1; break ;;
			v|V)
				 if [[ -s $logfile ]]; then tput clear; printf "%s\t\t%s\t\t%s\n%s" "Viewing ${logfile}" "q = Quit" "h = Help" "$(<"$logfile")" | grc/grcat | less -rXx1; redraw
				 else drawm "Log empty!" "$red" 2; drawm
				 fi
				;;
			e|E) printhelp; drawm; sleep 1 ;;
			c|C) if [[ $max_buffer -eq 0 ]]; then tput clear; tput cup 3 0; drawm
				 else buffer "clear"
				 fi ;;
			u|U) drawm "Getting servers..." "$yellow"; updateservers=1; getservers; drawm ;;
			ö) echo "displaypause=$displaypause monitor=$(monitor) paused=$paused monitorOvr=$monitorOvr pausetoggled=$pausetoggled" ;;
			q) ctrl_c ;;
		esac
		if [[ $displaypause == "true" &&  $(monitor) == "on" && $paused == "false" && $monitorOvr == 0 ]] || [[ $paused == "false" && $pausetoggled == 1 ]] ; then
			paused="true"
			pausetoggled=0
			kill "$secpid" >/dev/null 2>&1
			drawm
		elif [[ $displaypause == "true" && $(monitor) == "off" && $paused == "true" ]] || [[ $paused == "true" && $pausetoggled == 1 ]]; then
			paused="false"
			if [[ $pausetoggled == 0 ]]; then monitorOvr=0; fi
			pausetoggled=0
			tcount $secs &
			secpid="$!"
			drawm
		fi
		if [[ $updatesec == 1 && $idledone == 0 && $paused == "true" ]]; then
			updatesec=0;
		elif [[ $updatesec == 1 && $idledone == 0 && $paused == "false" ]]; then
			kill "$secpid" >/dev/null 2>&1
			tcount $secs &
			secpid="$!"
			updatesec=0
		elif [[ $paused == "false" ]]; then
			oldsecs=$secs
			secs=$(<"$secfile")
		fi
		if [[ $secs -gt $oldsecs && -n $idletimer && $idle == "true" && $idledone == 1 && $idlebreak == 0 && $paused == "false" ]]; then idlebreak=1; idledone=0; break; fi
	done
	if [[ $scrolled -gt 0 ]]; then buffer "redraw"; fi
	if [[ -n $idletimer && $idle == "true" && $slowgoing == 0 && $idlebreak == 0 ]]; then idledone=1; fi
	if kill -0 "$secpid" >/dev/null 2>&1; then kill $secpid >/dev/null 2>&1; fi
}

debug1() { #! Remove
	drawm
	startup=0
	loglevel=0
	#quiet_start="true"
	numservers="30"
	numslowservers="5"
	slowspeed="30"
	mtrpings="10"
	max_buffer="1000"
	mtr_external="false"
	mtr_internal="true"
	mtr_internal_ok="true"
	# mtr_internal_max=""
	getservers
	while true; do
		key=""
		while [[ -z $key ]]; do
		#drawm "Debug Mode" "$magenta"
		tput sc; tput cup $menuypos 0
		echo -en "${bold} T = Test  F = Full test  P = Precheck  G = grctest  R = routetest  Q = Quit  A = Add line  C = Clear  Ö = Custom  V = Clear  B = Buffer:$scrolled"
		tput rc
		read -srd '' -t 0.0001 -n 10000
		read -rsn 1 -t 1 key
		done
		if [[ $key == "$escape_char" ]]; then read -rsn3 -t 0.0001 key ; fi
		tput el
		case "$key" in
		'[A') buffer "up" ;;
		'[B') buffer "down" ;;
		'[C') echo "right" ;;
		'[D') echo "left" ;;
		'[5~') buffer "pageup" ;;
		'[6~') buffer "pagedown" ;;
		q|Q) break ;;
		t|T) testspeed "down" ;;
		f|F) testspeed "full" ;;
		p|P) precheck_speed; echo "" ;;
		g|G) if [[ -s $logfile ]]; then writelog 8 "${logfile}:\n$(tail -n500 "$logfile")"; fi; drawm ;;
		b|B) echo -e "$(<$bufferfile)" | grc/grcat; drawm ;;
		r|R) routetest ;;
		a|A) echo "Korv" | writelog 5  ;;
		v|V) redraw ;;
		c|C) tput clear; tput cup 3 0; drawm; echo -n "" > "$bufferfile" ;;
		#ö|Ö) tput cup 4 0; echo Korv ;;
		*) echo "$key" ;;
		esac
		broken=0
		testing=0
		#drawm
		#if [[ $width -ne $((tput cols)) || $height -ne $((tput lines)) ]]; then redraw; fi
	done
		broken=0
		testing=0
	ctrl_c
}

#?> End functions --------------------------------------------------------------------------------------------------------------------> @audit Pre Main

command -v mtr >/dev/null 2>&1 || mtr="false"

if [[ $mtr == "false" ]]; then mtr_internal="false"; mtr_internal_ok="false"; fi

trap ctrl_c INT

touch $tmpout; chmod 600 $tmpout

if [[ $genservers == "true" ]]; then
	echo -e "\nCreating server.cfg.sh"
	loglevel=0
	getservers
	exit 0
fi

logrotate
if [[ ! -w $logfile && $loglevel != 0 ]]; then echo "ERROR: Couldn't write to logfile: $logfile"; exit 1; fi

touch $speedfile; chmod 600 $speedfile
touch $routefile; chmod 600 $routefile

if [[ $testonly == "true" ]]; then #* Run tests and quit if variable test="true" or arguments -t or --test was passed to script
	getservers
	writelog 2 "Logging to: $logfile\n"
	for i in $testnum; do
		testspeed "full"
		if [[ $broken == 1 ]]; then break; fi
		routetest
		if [[ $broken == 1 ]]; then break; fi
	done
	kill "$speedpid" >/dev/null 2>&1
	kill "$routepid" >/dev/null 2>&1
	rm $speedfile >/dev/null 2>&1
	rm $routefile >/dev/null 2>&1
	exit 0
fi

if [[ ! -x ./getIdle ]]; then idle="false"; fi

touch $bufferfile; chmod 600 $bufferfile
touch $secfile; chmod 600 $secfile
tput smcup; tput clear; tput civis; tput cup 3 0; stty -echo
redraw
trap redraw WINCH

if [[ $buffer_save == "true" && -s .buffer ]]; then cp -f .buffer "$bufferfile" >/dev/null 2>&1; buffer "redraw"; fi
if [[ $debug == "true" ]]; then debug1; fi #! Remove

#writelog 1 "\nINFO: Script started! ($(date +%Y-%m-%d\ %T))\n"

drawm "Getting servers..." "$green"
getservers
# debug1
if [[ $displaypause == "true" && $(monitor) == "on" ]]; then paused="true"
elif [[ $displaypause == "true" && $(monitor) == "off" ]]; then paused="false"
fi

if [[ $paused == "false" && $startuptest == "true" && $net_status == "up" ]]; then
	testspeed "down"
	if [[ $lastspeed -le $slowspeed && $slowerror == 0 ]]; then startupdetect=1; fi
fi

drawm
startup=0




#? Start infinite loop ------------------------------------------------------------------------------------------------------------------>
main_loop() {
	if [[ -n $idletimer && $idle == "true" && $slowgoing == 0 && $idledone == 0 && $startupdetect == 0 ]]; then
		inputwait "$idletimer"
	elif [[ $startupdetect == 0 ]]; then
		inputwait "$waittime"
	fi

	net_status="$(</sys/class/net/"$net_device"/operstate)"
	if [[ $net_status != "up" ]]; then writelog 1 "Interface $net_device is down! ($(date +%H:%M))"; return; fi	

	if [[ $idlebreak == 0 ]]; then
		logrotate

		if [[ $forcetest != 1 && $startupdetect == 0 ]]; then
			if [[ $precheck == "true" ]]; then
				precheck_speed
				if [[ $precheck_status = "fail" ]]; then return; fi
			fi
			testspeed "down"
			drawm
		fi

		if [[ $forcetest == 1 && $broken == 0 ]]; then
			if [[ $loglevel -lt 4 ]]; then bkploglevel=$loglevel; loglevel=0; fi
			testspeed "full"; drawm
			routetest; drawm
			if [[ -n $bkploglevel && $bkploglevel -lt 4 ]]; then loglevel=$bkploglevel; fi
			forcetest=0
		elif [[ $lastspeed -le $slowspeed && $broken == 0 && $slowerror == 0 ]]; then
			testspeed "full"; drawm
			routetest; drawm
			detects=$((detects + 1))
			if [[ -n $slowwait ]]; then waitbkp=$waittime; waittime=$slowwait; fi
		else
			if [[ $slowgoing == 1 && $broken == 0 ]]; then
				if [[ -n $slowwait ]]; then waittime=$waitbkp; fi
				if [[ $slowerror == 0 ]]; then
					slowgoing=0
					writelog 1 "<------------------------------------------Speeds normal!------------------------------------------>\n"
					drawm
				fi
			fi
		fi
	fi

	
}

while true; do
	main_loop
	idlebreak=0
	precheck_status=""
	broken=0
	startupdetect=0
	slowerror=0
done

#? End infinite loop --------------------------------------------------------------------------------------------------------------------> @audit Main loop end
