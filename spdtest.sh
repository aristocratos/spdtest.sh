#!/usr/bin/env bash
# shellcheck disable=SC1090  #can't follow non constant source
# shellcheck disable=SC2034  #unused variables

#? @note TODOs

# TODO Fixa argument parsing och felmeddelanden
# TODO mer test i fulltest?
# TODO route test till test servrar?
# TODO Bättre kommentering på rörig kod
# TODO Hämta routes från servrar i fulltest?
# TODO Ändra slowtest till flera servrar och jämför resultat, mer färgning till grc, möjligen <>
# TODO getcspeed innan slowtest, använd slowspeed eller egen variabel
# TODO fixa fel keypress i inputwait, typ esc koder
# TODO makefile till getIdle och bättre dep lista
# TODO extern config och spara till config?
# TODO getservers() getcspeed inann, error check och wait animation
# TODO ssh controlmaster, server, client
# TODO grc funtion i bash?

#?> Start variables ------------------------------------------------------------------------------------------------------------------> @note Start variables
net_device="auto"		#* Network interface to get current speed from, set to "auto" to get default interface from "ip route" command
unit="mbit"  			#* Valid values are "mbit" and "mbyte"
slowspeed=30 			#* Download speed in unit defined above that triggers more tests, recommended set to 10%-40% of your max speed
numservers=30 			#* How many of the closest servers to get from "speedtest-cli --list", used as random pool of servers to test against
slowretry=1				#* When speed is below slowspeed, how many retries of random servers before running full tests
numslowservers=10		#* How many of the closest servers from list to test if slow speed has been detected, tests all if not set
precheck="true"         #* Check current bandwidth usage before slowcheck, blocks if speed is higher then values set below
precheck_samplet="5"    #* Time in seconds to sample bandwidth usage, defaults to 5 if not set
precheck_down="50"      #* Download speed in unit defined above that blocks slowcheck
precheck_up="50"        #* Upload speed in unit defined above that blocks slowcheck
waittime="00:20:00" 	#* Default wait timer between slow checks, format: "HH:MM:SS"
slowwait="00:10:00" 	#* Time between tests when slow speed has been detected, uses wait timer if unset, format: "HH:MM:SS"
idle="false" 			#* If "true", resets timer if keyboard or mouse activity is detected in X Server, needs getIdle to work
# idletimer="00:30:00"  #* If set and idle="true", the script uses this timer until first test, then uses standard wait time,
						#* any X Server activity resets back to idle timer, format: "HH:MM:SS"
displaypause="false"	#* If "true" automatically pauses timer when display is on, unpauses when off, overrides idle="true" if set, needs xset to work
loglevel=2				#* 0 : No logging
						#* 1 : Log only when slow speed has been detected
						#* 2 : Also log slow speed check
						#* 3 : Also log server updates
						#* 4 : Log all including forced tests
quiet_start="false"     #* If "true", don't print serverlist and routelist at startup
maxlogsize=100			#* Max logsize (in kilobytes) before log is rotated
# logcompress="gzip"	#* Command for compressing rotated logs, uncomment to enable
# logname=""            #* Custom logfile (full path), if a custom logname is set, log rotation is disabled
mtr="true"				#* Set "false" to disable route testing with mtr, automatically set to "false" if mtr is not found in PATH
						#* Needs route.cfg.sh to be populated with hosts to test against
mtrcount=10 			#* Number of pings sent with mtr
grc="true" 				#* If "true", enables output coloring with grc
paused="false" 			#* If "true", the timer is paused at startup, ignored if displaypause="true"
startuptest="false"		#* If "true" and paused="false", tests speed at startup before timer starts
testonly="false" 		#* If "true", never enter UI mode, always run full tests and quit
testnum=1				#* Number of times to loop full tests in testonly mode
use_shm="true"			#* Use /dev/shm shared memory for temp files, defaults to /tmp if /dev/shm isn't present

ookla_speedtest="speedtest"                        #* Command or full path to official speedtest client 
speedtest_cli="speedtest-cli/speedtest.py"         #* Path to unofficial speedtest-cli

#! Variables below are for internal function, don't change unless you know what you are doing
if [[ $use_shm == true && -d /dev/shm ]]; then temp="/dev/shm"; else temp="/tmp"; fi
secfile="$temp/spdtest-sec.$$"
speedfile="$temp/spdtest-speed.$$"
routefile="$temp/spdtest-route.$$"
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
charx=0
animx=1
animout=""
precheck_status=""
precheck_samplet=${precheck_samplet:-5}
declare -A routelista
declare -a testlista
declare -a rndbkp
declare -a errorlist
cd "$(dirname "$(readlink -f "$0")")" || { echo "Failed to set working directory"; exit 1; }
if [[ -e server.cfg.sh ]]; then servercfg="server.cfg.sh"; else servercfg="/dev/null"; fi
#? End variables -------------------------------------------------------------------------------------------------------------------->

command -v $ookla_speedtest >/dev/null 2>&1 || { echo "Error official speedtest client not found"; exit 1; }
command -v $speedtest_cli >/dev/null 2>&1 || { echo "Error speedtest-cli not found"; exit 1; }

#? Start argument parsing ------------------------------------------------------------------------------------------------------------------>
# TODO Fixa kontroller och mer felargument
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
		-g|--grc-off)
			grc="false"
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
			echo -e "\t-g, --grc-off               Disables terminal output coloring with grc"
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
if [[ $net_status != "up" ]]; then echo "Interface $net_device is down!"; exit 1; fi

#? End argument parsing ------------------------------------------------------------------------------------------------------------------>

#? Start functions ------------------------------------------------------------------------------------------------------------------>

ctrl_c() { #* Catch ctrl-c and general exit function, abort if currently testing otherwise cleanup and exit
	if [[ $testing == 1 ]]; then
		kill "$speedpid" >/dev/null 2>&1
		kill "$routepid" >/dev/null 2>&1
		broken=1
		return
	else
		tput clear
		tput cvvis
		stty echo
		tput rmcup
		kill "$secpid" >/dev/null 2>&1
		kill "$speedpid" >/dev/null 2>&1
		kill "$routepid" >/dev/null 2>&1
		rm $secfile >/dev/null 2>&1
		rm $speedfile >/dev/null 2>&1
		rm $routefile >/dev/null 2>&1
		if [[ -n $2 ]]; then echo -e "$2"; fi
		exit "${1:-0}"
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

waiting() { #* Show animation and speed or text while waiting for background job, arguments: <pid> <speed/"text"> <[down/up/both]>
			local text=$2
			local tdir=$3
			local spaces=""
			if [[ $3 == "both" ]]; then tdir="down"; spaces="    "; fi
			if [[ $text == "speed" ]]; then text="Testing"; c2="\e[0;1m"; etext=" $unit"; fi
			local skip=1
			local sndval sndval2 stext stext2

			while kill -0 "$1" >/dev/null 2>&1; do
				for (( i=0; i<${#chars}; i++ )); do
					if [[ $2 == "speed" && $skip == 1 ]]; then
						sndval="$(getcspeed "$tdir" 0.5 "get")"
						if [[ $3 == "both" ]]; then sndval2="$(getcspeed "up" 0.5 "get")"; fi
					elif [[ $2 == "speed" && $skip == 5 ]]; then
						cspd="$(getcspeed "$tdir" 2 "$sndval")"
						if [[ $3 == "both" && $cspd -lt $((cspdbkp/2)) ]]; then cspd=$cspdbkp; else cspdbkp=$cspd; fi
						stext="$spaces""$cspd""$spaces"
						if [[ $3 == "both" ]]; then stext2="      \e[1;37m$(getcspeed "up" 2 "$sndval2")"; etext="\t  "; fi
						if [[ $stext -le $slowspeed && $3 != "both" ]]; then c1="\e[1;31m"; elif [[ $3 != "both" ]]; then c1="\e[1;32m"; else c1="\e[1;37m"; fi
						text="$c1$stext$stext2$c2$etext"
						skip=0
					fi
					sleep 0.5
					if [[ $broken == 1 ]]; then return; fi
					echo -en "\e[1;32m$text \e[1;31m${chars:$i:1} \e[0m" "\r"
					skip=$((skip+1))
				done
			done

}

redraw() { #* Redraw menu if window is resized
	width=$(tput cols)
	if [[ $width -lt 106 ]]; then menuypos=2; else menuypos=1; fi
	titleypos=$((menuypos+1))
	#height=$(tput lines)
	tput sc; tput cup $((titleypos+1)) 0; tput el; tput rc
	drawm
}

myip() { #* Get public IP
	dig @resolver1.opendns.com ANY myip.opendns.com +short
	}

getcspeed() { #* Get current $net_device bandwith usage, arguments: <down/up/both> <sleep> <["get"][value from previous get]>
	local sdir=${1:-down}
	local slp=${2:-3}
	local uvalue=0
	LINE=$(grep "$net_device" /proc/net/dev | sed "s/.*://");
	if [[ $sdir == "down" ]]; then svalue=$(echo "$LINE" | awk '{print $1}')
	elif [[ $sdir == "up" ]]; then svalue=$(echo "$LINE" | awk '{print $9}')
	elif [[ $sdir == "both" ]]; then dvalue=$(echo "$LINE" | awk '{print $1}'); uvalue=$(echo "$LINE" | awk '{print $9}'); svalue=$((dvalue+uvalue)); fi
	if [[ -n $3 && $3 != "get" ]]; then SPEED=$(echo "($svalue - $3) / ($slp - ($slp * 0.028))" | bc); echo $(((SPEED*unitop)>>20)); return; fi
	total=$((svalue))
	if [[ $3 == "get" ]]; then echo $total; return; fi
	sleep "$slp"
	LINE=$(grep "$net_device" /proc/net/dev | sed "s/.*://");
	if [[ $sdir == "down" ]]; then svalue=$(echo "$LINE" | awk '{print $1}')
	elif [[ $sdir == "up" ]]; then svalue=$(echo "$LINE" | awk '{print $9}')
	elif [[ $sdir == "both" ]]; then dvalue=$(echo "$LINE" | awk '{print $1}'); uvalue=$(echo "$LINE" | awk '{print $9}'); svalue=$((dvalue+uvalue)); fi
	#SPEED=$(((svalue-total)/slp))
	SPEED=$(echo "($svalue - $total) / ($slp - ($slp * 0.028))" | bc)
	echo $(((SPEED*unitop)>>20))
}

testspeed_cli() { #* Get data from speedtest-cli and write to shared memory, meant to be run in background, arguments: <server> [<flags>]
	# shellcheck disable=SC2086
	speed=$($speedtest_cli --server $1 $2 --json 2>&1)
	echo "$speed" > "$speedfile"
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
	if [[ -n $3 ]]; then cs="\e[$3m"; ce="\e[$4m"; else cs=""; ce=""; fi
	if [[ ${#text} -gt 10 ]]; then text=${text::10}; fi
	echo -n "["
	if [[ ! $((${#text}%2)) -eq 0 ]]; then if [[ $percent -ge 10 ]]; then echo -n "="; else echo -n " "; fi; xp=$((xp+1)); fi
	for((x=1;x<=2;x++)); do
		for((i=0;i<((10-${#text})/2);i++)); do xp=$((xp+1)); if [[ $xp -le $((percent/10)) ]]; then echo -n "="; else echo -n " "; fi; done
		if [[ $x -eq 1 ]]; then echo -en "$cs$text$ce"; xp=$((xp+${#text})); fi
	done
	echo -n "]"
}

precheck_speed() { #* Check current bandwidth usage before slowcheck
	local sndvald sndvalu i skip=1
	local dspeed=0
	local uspeed=0
	local ib=10
	local t=$((precheck_samplet*10))
	drawm "Checking bandwidth usage" 33
	echo -en "Checking bandwidth usage: \e[1m$(progress 0)\e[0m\r"
	sndvald="$(getcspeed "down" 0 "get")"
	sndvalu="$(getcspeed "up" 0 "get")"
	for((i=1;i<=t;i++)); do
		prc=$(echo "scale=2; $i / $t * 100" | bc | cut -d . -f 1)
		if [[ $i -eq $ib ]]; then ib=$((ib+10)); dspeed=$(getcspeed "down" $((i/10)) "$sndvald"); uspeed=$(getcspeed "up" $((i/10)) "$sndvalu"); fi
		#dspeed=$(getcspeed "down" "$(echo "scale=1; $i / 10" | bc)" "$sndvald"); uspeed=$(getcspeed "up" "$(echo "scale=1; $i / 10" | bc)" "$sndvalu")
		echo -en "Checking bandwidth usage: \e[1m$(progress "$prc") \e[1;32mDOWN=\e[0;1m$dspeed $unit \e[1;31mUP=\e[0;1m$uspeed $unit\e[0m         \r"
		sleep 0.1
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
		writelog 2 "WARNING: Testing blocked, current bandwidth usage: DOWN=$dspeed $unit UP=$uspeed $unit $(date +%H:%M\ \(%y-%m-%d))"
	fi
	drawm
}

testspeed() { #* V2.0 Using official Ookla speedtest client
	local mode=${1:-down}
	local max_tests cs ce cb
	local tests=0
	local err_retry=0
	local xl=1
	local warnings
	unset 'errorlist[@]'
	RANDOM=$$$(date +%s)
	testing=1

	if [[ $precheck == "true" && $mode == "down" && $slowgoing == 0 ]]; then
		precheck_speed
		if [[ $precheck_status = "fail" ]]; then testing=0; return; fi
	fi

	if [[ $mode == "full" && $numslowservers -ge ${#testlista[@]} ]]; then max_tests=$((${#testlista[@]}-1))
	elif [[ $mode == "full" && $numslowservers -lt ${#testlista[@]} ]]; then max_tests=$((numslowservers-1))
	elif [[ $mode == "down" ]]; then

		# TODO getcspeed check! if slowgoing == 0

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
			writelog 1 "\n<---------------------------------------Slow speed detected!---------------------------------------->"; slowgoing=1; fi
			if [[ $tests == 0 ]]; then
				writelog 1 "Speedtest start: ($(date +%Y-%m-%d\ %T)), IP: $(myip)"
				printf "%-12s%-12s%-10s%-14s%-10s%-10s\n" "Down $unit" "Up $unit" "Ping" "Progress" "Time /s" "Server" | writelog 1
			fi
			printf "%-58s%s" "" "${testlistdesc[$tests]}" | writelog 9
			tput cuu1; drawm "Running full test" 31
			tl=${testlista[$tests]}
		elif [[ $mode == "down" ]]; then
			if [[ $tests -ge 1 ]]; then numstat="<-- Attempt $((tests+1))"; else numstat=""; fi
			printf "\r%5s%-4s%14s\t%s" "$down_speed " "$unit" "$(progress 0 "Init")" " ${testlistdesc[$rnum]} $numstat"| writelog 9
			#writelog 9 "\e[1mStarting\e[0m     \t  ${testlistdesc[$rnum]} $numstat"
			tput cuu1; drawm "Testing speed" 32
		fi

		stype=""; speedstring=""; echo "" > "$speedfile"

		$ookla_speedtest -s "$tl" -p yes -f json -I "$net_device" &>"$speedfile" &         #? <---------------- @note speedtest start
		speedpid="$!"

		x=1
		while [[ $stype == ""  || $stype == "null" || $stype == "testStart" ]]; do
			test_type_checker
			if [[ $x -eq 10 ]]; then
				anim 1
				if [[ $mode == "full" ]]; then printf "\r\e[1m%-12s\e[0m%-12s%-8s\e[1m%16s\e[0m" "     " "" "  " "$(progress 0 "Init $animout")    "
				#echo -en "\r\e[1mStarting $animout \e[0m"
				elif [[ $mode == "down" ]]; then printf "\r\e[1m%5s%-4s%14s\t\e[0m" "$down_speed " "$unit" "$(progress 0 "Init $animout")"
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
				printf "\r\e[1m%-12s\e[0m%-12s%-8s\e[1m%16s%-5s\e[0m" "   $down_speed  " "" " $server_ping " "$(progress "$down_progress")    " " $elapsed  "
			else
				# printf "\r\e[1m%-5s%-4s%-8s" "$down_speed" "$unit" "$down_progress%"
				# echo -en "\r\e[1m$down_speed $unit   "
				# echo -en "\r\t  $down_progress%  \e[0m"
				printf "\r\e[1m%5s%-4s%14s\t\e[0m" "$down_speed " "$unit" "$(progress "$down_progress")"
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
			if [[ $up_progress -eq 100 ]]; then anim 1; up_progresst=" $animout "; cs="1;32"; ce="0;1"; cb=""; else up_progresst=""; cs=""; ce=""; cb="\e[1m"; fi
			printf "\r%-12s$cb%-12s\e[0m%-8s\e[1m%-16s\e[0m$cb%-5s\e[0m" "   $down_speed  " "  $up_speed" " $server_ping " "$(progress "$up_progress" "$up_progresst" "$cs" "$ce")    " " $elapsedt  "
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
			if [[ $down_speed -le $slowspeed ]]; then downst="FAIL!"; else downst="OK!"; fi
			if [[ $packetloss != "null" && $packetloss != 0 ]]; then warnings="WARNING: ${packetloss%.*}% packet loss!"; fi

		# TODO Packet loss detected: Lägg till mtr lista ifrån jq '.server.host' , .server.name , .server.location , .server.country , .server.ip

			printf "\r"; printf "%-12s%-12s%-8s%-16s%-10s%s%s" "   $down_speed  " "  $up_speed" " $server_ping " "$(progress "$up_progress" "$downst")    " " $elapsedt  " "${testlistdesc[$tests]}" "  $warnings" | writelog 1
			drawm "Running full test" 31
			tests=$((tests+1))
		
		elif [[ $mode == "full" && $slowerror == 1 ]]; then
			warnings="ERROR: Couldn't test server!"
			printf "\r"; printf "%-12s%-12s%-8s%-16s%-10s%s%s" "   $down_speed  " "  $up_speed" " $server_ping " "$(progress "$up_progress" "FAIL!")    " " $elapsedt  " "${testlistdesc[$tests]}" "  $warnings" | writelog 1
			drawm "Running full test" 31
			tests=$((tests+1))
		elif [[ $mode == "down" && $slowerror == 0 ]]; then
			if [[ $slowgoing == 0 ]]; then rndbkp[$xl]="$rnum"; xl=$((xl+1)); fi
			if [[ $down_speed -le $slowspeed ]]; then downst="FAIL!"; else downst="OK!"; fi
			if [[ $tdate != $(date +%d) ]]; then tdate="$(date +%d)"; timestamp="$(date +%H:%M\ \(%y-%m-%d))"; else timestamp="$(date +%H:%M)"; fi
			#writelog 2 "\r\e[1m$down_speed $unit\t\e[0m  $downst\t  ${testlistdesc[$rnum]} <Ping: $server_ping> $timestamp $numstat"
			printf "\r"; tput el; printf "%5s%-4s%14s\t%s" "$down_speed " "$unit" "$(progress $down_progress "$downst")" " ${testlistdesc[$rnum]} <Ping: $server_ping> $timestamp $numstat"| writelog 2
			lastspeed=$down_speed
			drawm "Testing speed" 32
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
			drawm "Testing speed" 32
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
	if [[ $broken == 1 && $mode == "full" ]]; then writelog 1 "\nTests aborted\n"; 
	elif [[ $broken == 1 && $mode == "down" ]]; then writelog 2 "\nTests aborted\n"; 
	elif [[ $mode == "full" ]]; then writelog 1 " "; fi
	testing=0
}

oldslowtest() { #* Test random server from server list for slow speed, if detected check x other random servers
	unset 'errorlist[@]'
	RANDOM=$$$(date +%s)
	testing=1
	err_retry=0
	x=0
	xl=1
	if [[ ${#testlista[@]} -gt 1 && $slowgoing == 0 ]]; then
		rnum="$RANDOM % ${#testlista[@]}"
		tl=${testlista[$rnum]}
	elif [[ ${#testlista[@]} -gt 1 && $slowgoing == 1 ]]; then
		rnum=${rndbkp[$xl]}
		tl=${testlista[$rnum]}
	else
		tl=${testlista[1]}
		rnum=1
	fi
	while [[ $x -le $slowretry ]]; do
		testspeed_cli"$tl" --no-upload &
		speedpid="$!"
		if [[ $x -ge 1 ]]; then numstat="<-- Attempt $((x+1))"; else numstat=""; fi
		writelog 9 "\e[1;32mTesting\e[0m     \t  ${testlistdesc[$rnum]} $numstat"
		tput cuu1; drawm "Testing..." 32
		waiting $speedpid "speed" "down"
		if [[ $broken == 1 ]]; then slowerror=1; testing=0; return; fi
		speed=$(<$speedfile)
		if [[ ${speed::25} == "ERROR: No matched servers" ]]; then
			err_retry=$((err_retry+1))
			errorlist+=("$tl")
			writelog 2 "          ERROR\t  ${testlistdesc[$rnum]}   ERROR: Couldn't test server!"
			if [[ ${#testlista[@]} -gt 1 && $err_retry -lt ${#testlista[@]} ]]; then
				tl2=$tl
				while [[ $(contains "${errorlist[@]}" "$tl2") ]]; do
					rnum="$RANDOM % ${#testlista[@]}"
					tl2=${testlista[$rnum]}
				done
				tl=$tl2
			else
				writelog 2 "ERROR Couldn't get current speed from servers"
				slowerror=1
				testing=0
				return
			fi
		elif [[ ${speed::5} == "ERROR" ]]; then
			writelog 1 "Fatal error in speedtest"
			writelog 1 "$speed"
			testing=0
			ctrl_c 1 "Fatal error in speedtest\n$speed"
		else
			down=$(echo "$speed" | jq '.download' | cut -d "." -f 1)
			down=$((down >> 20))
			if [[ $slowgoing == 0 ]]; then rndbkp[$xl]="$rnum"; xl=$((xl+1)); fi
			if [[ $down -le $slowspeed ]]; then downst="FAIL!"; else downst="OK!"; fi
			if [[ $tdate != $(date +%d) ]]; then tdate="$(date +%d)"; timestamp="($(date +%H:%M\)\ \(%y-%m-%d))"; else timestamp="($(date +%H:%M))"; fi
			writelog 2 "$down Mbit/s $downst\t  ${testlistdesc[$rnum]} $timestamp $numstat"
			drawm "Testing..." 32
			if [[ $down -le $slowspeed && ${#testlista[@]} -gt 1 && $x -lt $slowretry && $slowgoing == 0 ]]; then
				tl2=$tl
				while [[ $tl2 == "$tl" ]]; do
					rnum="$RANDOM % ${#testlista[@]}"
					tl2=${testlista[$rnum]}
				done
				tl=$tl2
				x=$((x+1))
			elif [[ $down -le $slowspeed && ${#testlista[@]} -gt 1 && $x -lt $slowretry && $slowgoing == 1 ]]; then
				xl=$((xl+1))
				rnum=${rndbkp[$xl]}
				tl=${testlista[$rnum]}
				x=$((x+1))
			else
				x=$((slowretry+1))
			fi
		fi
	done

	lastspeed="$down"
	testing=0
}

oldfulltest() { #* Tests to run when download speed is slow
	testing=1
	if [[ $slowgoing == 0 && $forcetest == 0 ]]; then
	writelog 1 "\n<---------------------------------------Slow speed detected!--------------------------------------->"
	fi
	writelog 1 "Speedtest start: ($(date +%Y-%m-%d\ %T)), IP: $(myip)"
	printf "%-12s %-12s %-10s %-10s\n" "Down Mbit/s" "Up Mbit/s" "Ping" "Server" | writelog 1
	drawm "Running full test..." 32
	x=0
	for tl in "${testlista[@]}"; do
		testspeed_cli "$tl" &
		speedpid="$!"
		printf "%-12s %-12s %-10s %-10s" "      " "     " "   " "${testlistdesc[$x]}" | writelog 9
		tput cuu1; drawm "Running full test..." 32
		waiting $speedpid "speed" "both"
		if [[ $broken == 1 ]]; then break; fi
		speed=$(<$speedfile)
		down=$(echo "$speed" | jq '.download' | cut -d "." -f 1)
		down=$((down >> 20))
		ping=$(echo "$speed" | jq '.ping' | cut -d "." -f 1)
		upl=$(echo "$speed" | jq '.upload' | cut -d "." -f 1)
		upl=$((upl >> 20))
		printf "%-12s %-12s %-10s %-10s\n" "    $down" "   $upl" " $ping" "${testlistdesc[$x]}" | writelog 1
		drawm "Running full test..." 32
		x=$((x+1))
		if [[ $x -ge $numslowservers ]]; then break; fi
	done
	# writelog 1 "\n"
	testing=0
}

routetest() { #* Test routes with mtr
	if [[ $mtr == "false" ]] || [[ $broken == 1 ]]; then return; fi
	testing=1
	if [[ -e route.cfg.sh ]]; then
		for rl in "${!routelista[@]}"; do
			writelog 1 "Routetest ($rl) ${routelista[$rl]}"
			drawm "Running route test..." 32
			mtr -wbc "$mtrcount" -I "$net_device" "${routelista[$rl]}" > "$routefile" &
			routepid="$!"
			waiting $routepid "Testing"
			if [[ $broken == 1 ]]; then break; fi
			writelog 1 "$(<$routefile)\n"
			drawm
		done
		writelog 1 " "
	fi
	if [[ $broken == 1 ]]; then writelog 1 "Tests aborted\n"; fi
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
	if [[ $grc == "true" ]]; then
		echo -en "$input\n" | tee -a "$file" | grc/grcat grc.conf
	elif [[ $grc == "false" ]]; then
		echo -en "$input\n" | tee -a "$file"
	fi
}

drawm() { #* Draw menu and title, arguments: <"title text"> <bracket color 30-37> <sleep time>
	if [[ $testonly == "true" ]]; then return; fi
	tput sc
	tput cup 0 0; tput el
	echo -e "[\e[1;4;31mQ\e[0;1muit] [H\e[1;4;33me\e[0;1mlp] [$funcname]\c"
	if [[ -n $lastspeed ]]; then
		echo -e " [Last: $lastspeed $unit]\c"
	fi
	if [[ $detects -ge 1 && $width -ge 100 ]]; then
		echo -e " [Slow detects: $detects]\c"
	fi
	logt="[Log:][\e[1;4;35mV\e[0;1miew][${logfile##log/}]"
	logtl=$(echo -e "$logt" | sed "s,\x1B\[[0-9;]*[a-zA-Z],,g")
	tput cup 0 $((width-${#logtl}))
	echo -e "$logt"
	if [[ $paused == "true" ]]; then ovs="\e[1;32mOn\e[0;1m"; else ovs="\e[1;31mOff\e[0;1m"; fi
	if [[ $idle == "true" ]]; then idl="\e[1;32mOn\e[0;1m"; else idl="\e[1;31mOff\e[0;1m"; fi
	tput cup 1 0; tput el
	echo -en "[Timer:][\e[1;4;32mHMS\e[0;1m+][\e[1;4;31mhms\e[0;1m-][S\e[1;4;33ma\e[0;1mve][\e[1;4;34mR\e[0;1meset][\e[1;4;35mI\e[0;1mdle $idl][\e[1;4;33mP\e[0;1mause $ovs] [\e[1;4;32mT\e[0;1mest] [\e[1;4;36mF\e[0;1morce test] "
	if [[ $menuypos == 2 ]]; then tput cup 2 0; tput el; fi
	echo -en "[\e[1;4;35mU\e[0;1mpdate servers] [\e[1;4;33mC\e[0;1mlear screen]"
	tput cup $titleypos 0
	printf "%0$(tput cols)d" 0 | tr '0' '='
	if [[ -n $1 ]]; then tput cup "$titleypos" $(((width / 2)-(${#1} / 2)))
	echo -e "\e[1;${2:-37}m[\e[0;1m$1\e[1;${2:-37}m]\e[0m"
	sleep "${3:-0}"
	fi
	tput rc
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
	local IFS=$'\n'

	if [[ $quiet_start = "true" && $loglevel -ge 3 ]]; then bkploglevel=$loglevel; loglevel=103
	elif [[ $quiet_start = "true" && $loglevel -lt 3 ]]; then bkploglevel=$loglevel; loglevel=1000; fi

	if [[ -e $servercfg && $servercfg != "/dev/null" && $updateservers = 0 ]]; then
		source "$servercfg"
		writelog 3 "\nUsing servers from $servercfg"
		local num=1
		#servlst="$(cat $servercfg | sed 1d)"
		#for line in $servlst; do
		#	servlen=$((${#line} - 24))
		#	servdesc=${line:(-servlen)}
		#	servdesc=${servdesc# }
		#	echo "$num. $servdesc"
		#	num=$((num+1))
		#done
		for tl in "${testlistdesc[@]}"; do
			writelog 3 "$num. $tl"
			num=$((num+1))
		done
	else
		echo "#!/bin/bash" > "$servercfg"
		echo "#? Automatically generated server list, servers won't be refreshed at start if this file exists" >> "$servercfg"
		writelog 3 "\nUsing servers:"
		speedlist=$($speedtest_cli --list | head -$((numservers+1)) | sed 1d)
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
	if [[ -e route.cfg.sh && $startup == 1 && $genservers != "true" && $mtr == "true" ]]; then
		# shellcheck disable=SC1091
		source route.cfg.sh
		writelog 3 "Hosts in route.cfg.sh"
		for rl in "${!routelista[@]}"; do
			writelog 3 "$rl: ${routelista[$rl]}"
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
			printf "\e[1m[%02d:%02d:\e[1;31m%02d\e[0;1m]\e[0m" $((secs/3600)) $(((secs/60)%60)) $((secs%60))
		else
			printf "\e[1m[%02d:%02d:%02d]\e[0m" $((secs/3600)) $(((secs/60)%60)) $((secs%60))
		fi
		tput rc
		
		read -srd '' -t 0.01 -n 10000
		# shellcheck disable=SC2162
		read -srn 1 -t 0.99 keyp
		case "$keyp" in
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
				drawm "Timer saved!" 32 2; drawm
				;;
			r|R) unset waitsaved ; secs=$stsecs; updatesec=1 ;;
			f|F) forcetest=1; break ;;
			v|V)
				if [[ $grc == "true" && -s $logfile ]]; then echo "$(<"$logfile")" | grc/grcat ./grc.conf | less -rFX~x1
				elif [[ -s $logfile ]]; then echo "$(<"$logfile")" | less -rFX~x1
				else drawm "Log empty!" 31 2; drawm
				fi
				drawm
				;;
			e|E) printhelp; drawm; sleep 1 ;;
			c|C) tput clear; tput cup 3 0; drawm ;;
			u|U) drawm "Getting servers..." 33; updateservers=1; getservers; drawm ;;
			ö) echo "displaypause=$displaypause monitor=$(monitor) paused=$paused monitorOvr=$monitorOvr pausetoggled=$pausetoggled" ;;
			# ö) echo "$(<spdtest.sh)" | grcat ./grc.conf | less -rFX~; drawm ;;
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
	if [[ -n $idletimer && $idle == "true" && $slowgoing == 0 && $idlebreak == 0 ]]; then idledone=1; fi
	if kill -0 "$secpid" >/dev/null 2>&1; then kill $secpid >/dev/null 2>&1; fi
}

debug1() { #! Remove
	loglevel=0
	quiet_start="true"
	getservers
	while true; do
		drawm "Debug Mode" 35
		echo -en "\r \e[1mT = Test \t F = Full test \t P = Precheck \t G = grctest \t Q = Quit\e[0m\r"
		read -rsn 1 key
		tput el
		case "$key" in
		q|Q) break ;;
		t|T) testspeed "down" ;;
		f|F) testspeed "full" ;;
		p|P) precheck_speed; echo "" ;;
		g|G) echo "$(<log/spdtest.log)" | grc/grcat
		esac
	done
		broken=0
		testing=0
	ctrl_c
}

#?> End functions --------------------------------------------------------------------------------------------------------------------> @audit Pre Main

command -v grc/grcat >/dev/null 2>&1 || grc="false"
command -v mtr >/dev/null 2>&1 || mtr="false"

trap ctrl_c INT

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

touch $secfile; chmod 600 $secfile
tput smcup; tput clear; tput civis; tput cup 3 0; stty -echo

redraw
trap redraw WINCH

if [[ $debug == "true" ]]; then debug1; fi #! Remove

drawm "Getting servers..." 32
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




#? Start infinite loop ------------------------------------------------------------------------------------------------------------------> @audit Main loop start

while true; do
	if [[ -n $idletimer && $idle == "true" && $slowgoing == 0 && $idledone == 0 && $startupdetect == 0 ]]; then
		inputwait "$idletimer"
	elif [[ $startupdetect == 0 ]]; then
		inputwait "$waittime"
	fi

	net_status="$(</sys/class/net/"$net_device"/operstate)"

	if [[ $idlebreak == 0 && $net_status == "up" ]]; then
		logrotate

		if [[ $forcetest != 1 && $startupdetect == 0 ]]; then
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
			drawm "Slow detected!" 31 2; drawm
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

		broken=0
		startupdetect=0
		slowerror=0
		precheck_status=""

	fi

	if [[ $net_status != "up" ]]; then writelog 1 "Interface $net_device is down! ($(date +%H:%M))"; fi

	idlebreak=0
done

#? End infinite loop --------------------------------------------------------------------------------------------------------------------> @audit Main loop end
