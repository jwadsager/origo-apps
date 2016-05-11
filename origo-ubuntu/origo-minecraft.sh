# description "start and stop the minecraft-server"

start on runlevel [2345]
stop on runlevel [^2345]

console log
chdir /minecraft
echo "eula=true" > eula.txt
setuid minecraft
setgid minecraft

respawn
respawn limit 20 5

memory=`awk '/MemTotal/ {printf( "%.2d\n", $2 / 1024 )}' /proc/meminfo`

exec /usr/bin/java -Xmx${memory}M -Xms${memory}M -jar minecraft_server.jar nogui
