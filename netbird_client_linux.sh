#!/bin/bash
install=
requiredVersion="0.28.5"
minimalVersion="0.28.0"
netbird_domain="remote.qwilt.com"
netbird_ip="35.246.201.207"
netbird_device_port="33073"
netbird_web_port="443"
random_port=$((20000 + RANDOM % 10001))
logged_in_user=$(w | grep -E 'tty|gdm' | awk '{print $1}' | sort --uniq)
display=$(w | grep -E 'tty|gdm' | awk '{print $3}' | sort --uniq)
homefolder=$(grep "^$logged_in_user:" /etc/passwd | cut -d: -f6)

sed -i "/$netbird_domain/d" /etc/hosts
echo "$netbird_ip  $netbird_domain"  | sudo tee -a /etc/hosts > /dev/null

CONFIG_FILE=$homefolder/.ssh/config
if [[ ! -d "$homefolder/.ssh" ]]; then su -c "ssh-keygen -t rsa -N '' -f $homefolder/.ssh/id_rsa" $logged_in_user;fi

if [[ -z "$CONFIG_FILE" ]]
    then 
    # Check if "Host *" exists
    if ! grep -q '^Host \*' "$CONFIG_FILE"; then
        # If "Host *" does not exist, add it with the desired settings
        echo -e "Host *\n  ServerAliveInterval 120\n  ServerAliveCountMax 15" >> "$CONFIG_FILE"
    else
        # If "Host *" exists, check if the settings are present
        if ! grep -q 'ServerAliveInterval 120' "$CONFIG_FILE"; then
            sed -i '/^Host \*/a\ \ ServerAliveInterval 120\n\ \ ServerAliveCountMax 15' "$CONFIG_FILE"
        fi
    fi
    chown $logged_in_user:$logged_in_user $homefolder/.ssh/config
else
    echo 'Host *' > "$CONFIG_FILE"
    echo '  ServerAliveInterval 120' >> "$CONFIG_FILE"
    echo '   ServerAliveCountMax 15' >> "$CONFIG_FILE"
    chown $logged_in_user:$logged_in_user $homefolder/.ssh/config
fi

# Define a function to update config.json and create a cloudfront script
update_config () { 
  # Update config.json with the new domain and port values
  sed -i "s|api.netbird.io:443|$netbird_domain:$netbird_device_port|g" /etc/netbird/config.json
  sed -i "s|app.netbird.io:443|$netbird_domain:$netbird_web_port|g" /etc/netbird/config.json
  sed -i "s|\"WgPort\".*,|\"WgPort\": $random_port,|g" /etc/netbird/config.json
  sed -i '/NetworkMonitor/d' /etc/netbird/config.json
  sed -i '/IFaceBlackList/i\    "NetworkMonitor": true,' /etc/netbird/config.json
  
}

notify_users () {

user_list=($(who | grep -E "\(:[0-9](\.[0-9])*\)" | awk '{print $1 "@" $NF}' | sort -u))

for user in $user_list; do
    username=${user%@*}
    display=${user#*@}
    dbus=unix:path=/run/user/$(id -u $username)/bus

    sudo -u $username DISPLAY=${display:1:-1} \
                      DBUS_SESSION_BUS_ADDRESS=$dbus \
                      notify-send "Netbird Notice" "$@"
done
}
run_commands_on_users () {

user_list=($(who | grep -E "\(:[0-9](\.[0-9])*\)" | awk '{print $1 "@" $NF}' | sort -u))

for user in $user_list; do
    username=${user%@*}
    display=${user#*@}
    dbus=unix:path=/run/user/$(id -u $username)/bus

    sudo -u $username DISPLAY=${display:1:-1} \
                      DBUS_SESSION_BUS_ADDRESS=$dbus \
                      "$@" &
done
}


if [[ "$(which /usr/bin/netbird 2>/dev/null | grep -c netbird)" -eq 0 ]]
then 
    echo "Netbird is missing, installing it now"
    install=1
else
    if  [[ "$(/usr/bin/netbird status 2>&1 | grep "deadline")" ]]
    then 
        echo "Netbird Service is shutdown or config.json is corrupted - regenerating"
        /usr/bin/netbird service stop  > /dev/null 2>&1
        rm -f /etc/netbird/config.json  > /dev/null 2>&1
        /usr/bin/netbird service start  > /dev/null 2>&1
        sleep 3
        update_config
        /usr/bin/netbird service restart

    fi

    installedVersion=$(/usr/bin/netbird version)
    if [[ "$(printf '%s\n' "$minimalVersion" "$installedVersion" | sort -V | head -n1)" == "$minimalVersion" && "$installedVersion" != "$minimalVersion" ]]; then
        echo "The installed version ($installedVersion) is at least $minimalVersion."
        service netbird start
        if  [[ "$(/usr/bin/netbird status 2>/dev/null | grep Management | grep -oc Disconnected )" -ge 1 ]] || [[ "$( /usr/bin/netbird status 2>/dev/null | grep -c YOUR_MANAGEMENT_URL)" -ge 1 ]]
        then
            echo "Netbird is disconnected or not installed, checking if $requiredVersion is installed"
            if [[ "$(netbird version)" == "$requiredVersion" ]]
            then 
                echo "Netbird is already at $requiredVersion - ignoring"
                update_config
                /usr/bin/netbird service restart
            else
                echo "Current version is: $(/usr/bin/netbird version)"
                echo "Netbird version is not $requiredVersion - Upgrading/Downgrading"
                notify_users "Netbird version is not $requiredVersion - Upgrading/Downgrading"
                /usr/bin/netbird service stop  > /dev/null 2>&1
                killall -9 netbird-ui  > /dev/null 2>&1
                install=1
            fi #end of netbird version test
        else
            echo "Netbird client is connected at the moment, Ignoring"
            install=0
        fi # end of connection test
    else
        echo "The installed version ($installedVersion) is less than $minimalVersion."
        notify_users "Netbird installed version ($installedVersion) is less than $minimalVersion - Upgrading"
        echo "Forcing Netbird Upgrade"
             netbird down
            install=1
    fi

fi # end of install and version test

if [[ "$install" -eq 1 ]]
then
    echo "runnning install"
    notify_users "Netbird version $requiredVersion is being installed. please wait..."
    if [[ "$(cat /etc/os-release | grep -ociE 'Fedora|centos|rocky' | sort --uniq)" -ge 1 ]]
    then
        echo downloading the client
        pkg_url=$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/netbirdio/netbird/releases/download/v$requiredVersion/netbird_${requiredVersion}_linux_amd64.rpm)
        curl --silent -o /tmp/netbird.rpm "$pkg_url"
        rpm -Uvh  /tmp/netbird.rpm

        echo downloading the netbird-ui
        pkg_url=$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/netbirdio/netbird/releases/download/v$requiredVersion/netbird-ui_${requiredVersion}_linux_amd64.rpm)
        curl --silent -o /tmp/netbird-ui.rpm "$pkg_url"
        rpm -Uvh  /tmp/netbird-ui.rpm
    else
        apt install -y libnotify-bin
        pkg_url=$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/netbirdio/netbird/releases/download/v$requiredVersion/netbird_${requiredVersion}_linux_amd64.deb)
        # Download the package file
        curl --silent -o /tmp/netbird.deb "$pkg_url"
        pkg_url=$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/netbirdio/netbird/releases/download/v$requiredVersion/netbird-ui_${requiredVersion}_linux_amd64.deb)
        # Download the package file
        curl --silent -o /tmp/netbird-ui.deb "$pkg_url"
        dpkg -i /tmp/netbird.deb
        dpkg -i /tmp/netbird-ui.deb
        sudo apt-get install libnotify-bin -y

    fi # end of netbird client based on OS version

    /usr/bin/netbird service stop  > /dev/null 2>&1
    killall -9 netbird-ui  > /dev/null 2>&1
    update_config # calling function
    /usr/bin/netbird service install  > /dev/null 2>&1
    /usr/bin/netbird service start   > /dev/null 2>&1

fi # finished installing and configuring the client

run_commands_on_users netbird-ui

echo "Host file:"
cat /etc/hosts | grep $netbird_domain
echo "config.json Host:"
sudo cat /etc/netbird/config.json | grep \"Host\":
echo "SSH Config file:"
cat $CONFIG_FILE | grep ServerAlive


