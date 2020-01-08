Name: spdtest.sh
Version: 1.1.0
Usage: Script with UI for testing internet speed reability.
Description:
Internet speeds are tested against random servers from speedtest.net with 'speedtest' at an interval (defined by user).
If slow speed (defined by user) is detected, then runs a number of download and upload test with 'speedtest' and (optional)
route tests to servers with detected packet loss with 'mtr' and writes to a logfile.
Contact: jakob@qvantnet.com

Dependencies:
bash v4.4 or later : Script functionality might brake with earlier versions

speedtest: https://www.speedtest.net/apps/cli : Official speedtest client from Ookla, needs to be in path or defined below

Python 2.7-3.x: https://www.python.org/downloads : needed for speedtest-cli and grc

jq : https://stedolan.github.io/jq/ : needed for json parsing

less : http://www.greenwoodsoftware.com/less/ : for logfile viewing

Optionals:
mtr : https://github.com/traviscross/mtr : needed if you want to check routes to slow servers

Included:
speedtest-cli : https://github.com/sivel/speedtest-cli : should not be installed globally since name conflicts with official client,
version 2.1.2 included : used to get serverlist since official client is limited to 10 servers

Included but optional:
getIdle : source and linux x86_64 binary included : needs to be in script directory for idle reset functionality
compile with 'gcc -o getIdle src/getIdle.c -lXss -lX11'
needs X11/extensions/scrnsaver.h from libXss, install libxss (libxss-dev on debian based systems)

grc : https://github.com/garabik/grc : for making text output in the UI pretty, can be disabled
slighty modified grcat from grc version 1.11.3 included
