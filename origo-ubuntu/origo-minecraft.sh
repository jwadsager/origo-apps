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

exec /usr/bin/java -Xmx4096M -Xms4096M -jar minecraft_server.jar nogui
