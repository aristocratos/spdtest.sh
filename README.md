# spdtest.sh

**Version:** 0.2.0  
**Usage:** Script with UI for testing internet speed reability

## Description

Internet speeds are tested against random servers from speedtest.net with 'speedtest' at an interval (defined by user).  
If slow speed (defined by user) is detected, then runs a number of download and upload test with 'speedtest' and optional route tests to servers with 'mtr' and writes to a logfile.

## Dependencies

**bash** (v4.4 or later). Script functionality might brake with earlier versions  

**[Python 3](https://www.python.org/downloads)** Needed for speedtest-cli, grc and getIdle.  

**[speedtest](https://www.speedtest.net/apps/cli)** Official speedtest client from Ookla, needs to be in path or defined in config

**[jq](https://stedolan.github.io/jq/)** Needed for json parsing  

**[less](http://www.greenwoodsoftware.com/less/)** For logfile viewing  

## Included

**[speedtest-cli](https://github.com/sivel/speedtest-cli)** Used to get serverlist, since official client is limited to 10 servers.  
Should not be installed globally since name conflicts with official client, version 2.1.2 included.  

**[grc](https://github.com/garabik/grc)** For making text output in the UI pretty.  
Modified version of grcat included in the script.

**getIdle** Python code included in script.

## Optionals

**[mtr](https://github.com/traviscross/mtr)** Needed if you want to check routes to slow servers  
