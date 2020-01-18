#? List of routes to test with mtr
#? Format:
#? routelista+=("host")
#? routelistdesc["host"]=("Name")
#? routelistport["host"]=("port")  'Set port to "auto" if you don't want to set a custom port!'

routelista+=("google.com")
routelistdesc["google.com"]="Google"
routelistport["google.com"]="auto"

routelista+=("reddit.com")
routelistdesc["reddit.com"]="Reddit"
routelistport["reddit.com"]="auto"

routelista+=("twitch.tv")
routelistdesc["twitch.tv"]="Twitch"
routelistport["twitch.tv"]="auto"

routelista+=("amazon.com")
routelistdesc["amazon.com"]="Amazon"
routelistport["amazon.com"]="auto"