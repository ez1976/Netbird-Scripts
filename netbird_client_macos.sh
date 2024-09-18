#!/bin/bash
install=
requiredVersion="0.29.2"
minimalVersion="0.29.1"
netbird_domain="remote.qwilt.com"
netbird_ip="35.246.201.207"
netbird_device_port="33073"
netbird_web_port="443"
random_port=$((20000 + RANDOM % 10001))


# Define a function to update config.json 
update_config () { 
  # Update config.json with the new domain and port values
  sed -i '' "s|api.netbird.io:443|$netbird_domain:$netbird_device_port|g" /etc/netbird/config.json
  sed -i '' "s|connect.qwilt.com|$netbird_domain|g" /etc/netbird/config.json
  sed -i '' "s|app.netbird.io:443|$netbird_domain:$netbird_web_port|g" /etc/netbird/config.json
  sed -i '' "s|\"WgPort\".*,|\"WgPort\": $random_port,|g" /etc/netbird/config.json
#add netbird domain to host file
sed -i ' ' "/$netbird_domain/d" /etc/hosts
echo "$netbird_ip  $netbird_domain"  | sudo tee -a /etc/hosts > /dev/null

# Get the currently logged-in user 
logged_in_user=$(stat -f "%Su" /dev/console)

# change ssh config to reduce disconnections
CONFIG_FILE=/Users/$logged_in_user/.ssh/config

# Check if the config file exists, if not, create it
# Check if the config file exists, if not, create it
if [ ! -f "$CONFIG_FILE" ]; then
    touch "$CONFIG_FILE"
    echo "Host *" >> "$CONFIG_FILE"
    echo "  ServerAliveInterval 120" >> "$CONFIG_FILE"
    echo "  ServerAliveCountMax 15" >> "$CONFIG_FILE"
    echo "$CONFIG_FILE file created and settings added."
else
    # Check if "Host *" exists
    if ! grep -q '^Host \*' "$CONFIG_FILE"; then
        # If "Host *" does not exist, add it with the desired settings
        echo "Host *" >> "$CONFIG_FILE"
        echo "  ServerAliveInterval 120" >> "$CONFIG_FILE"
        echo "  ServerAliveCountMax 15" >> "$CONFIG_FILE"
        echo "settings added to $CONFIG_FILE."
    else
        # If "Host *" exists, check if the settings are present
        if ! grep -q 'ServerAliveInterval 120' "$CONFIG_FILE"; then
            sed -i '/^Host \*/a\ \ ServerAliveInterval 120\n\ \ ServerAliveCountMax 15' "$CONFIG_FILE"
            echo "settings added to $CONFIG_FILE."
        fi
    fi
fi
echo "Host file:"
cat /etc/hosts | grep remote
echo "config.json Host:"
sudo cat /etc/netbird/config.json | grep \"Host\":
echo "SSH Config file:"
cat $CONFIG_FILE | grep ServerAlive

}

if [[ ! -z $(/usr/local/bin/netbird) ]]
then
    if  [[ "$(/usr/local/bin/netbird status 2>&1 | grep "deadline")" ]] || [[ ! "$(cat /etc/netbird/config.json | grep remote.qwilt.com)" ]]
    then 
        echo "Netbird Service is shutdown or config.json is corrupted - regenerating"
        /usr/local/bin/netbird service stop  > /dev/null 2>&1
        rm -f /etc/netbird/config.json  > /dev/null 2>&1
        /usr/local/bin/netbird service start  > /dev/null 2>&1
        sleep 2
        /usr/local/bin/netbirdd service stop  > /dev/null 2>&1
        sleep 3
        update_config
        /usr/local/bin/netbird service restart
    fi

    installedVersion=$(/usr/local/bin/netbird version)
    if [[ "$(printf '%s\n' "$minimalVersion" "$installedVersion" | sort -V | head -n1)" == "$minimalVersion" && "$installedVersion" != "$minimalVersion" ]]; then
        echo "The installed version ($installedVersion) is at least $minimalVersion."
        if [[ $(/usr/local/bin/netbird status | grep Management | grep -c Connected) -ge 1 ]]
        then 
            echo "Netbird connected at the moment - Aborting"
            update_config # execute function
            sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
        else
            if [[ "$(/usr/local/bin/netbird version)" == "$requiredVersion" ]]
            then 
                echo "Netbird is already at $requiredVersion - ignoring"
                update_config # execute function
                exit 0
            else
                echo "Current version is: $(/usr/local/bin/netbird version)"
                echo "Netbird is not at version $requiredVersion - Will Upgrade/Downgrade"
                sudo -u "$logged_in_user" osascript -e "display dialog \"Netbird is not at version $requiredVersion - Will Upgrade/Downgrade\" buttons {\"OK\"} default button \"OK\""
                sudo -u "$logged_in_user" osascript -e 'Netbird is not at version $requiredVersion - Will Upgrade/Downgrade"'
                killall -9 netbird-ui   > /dev/null 2>&1
                /usr/local/bin/netbird down   > /dev/null 2>&1
                /usr/local/bin/netbird service stop   > /dev/null 2>&1
                install=install
            fi
        fi
    else
        echo "The installed version ($installedVersion) is less than $minimalVersion."
        echo "Forcing Netbird Upgrade"
        sudo -u "$logged_in_user" osascript -e "display dialog \"The installed version ($installedVersion) is less than $minimalVersion - Forcing Netbird Upgrade\" buttons {\"OK\"} default button \"OK\""

        /usr/local/bin/netbird down   > /dev/null 2>&1
        /usr/local/bin/netbird service stop   > /dev/null 2>&1
        install=install
    fi
else
    install=install
    app=install
fi

if [[ "$install" == "install" ]]
then
    if [[ "$app" == "install" ]]
    then
        cd /tmp
        rm -rf /tmp/netbird*   > /dev/null 2>&1
        echo getting netbird Application from S3 bucket
        curl --silent -o /tmp/netbird.zip https://storage.googleapis.com/qwilt-installs/netbird_app.zip
        cd /tmp
        unzip -o netbird.zip -d /
    else
        # Check CPU type
        cpu_type=$(uname -m)
        echo "CPU Type: $cpu_type"
        if [[ "$cpu_type" == "x86_64" ]]; then
            echo "CPU type is Intel"
            pkg_url=$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/netbirdio/netbird/releases/download/v$requiredVersion/netbird_${requiredVersion}_darwin_amd64.pkg)
            curl --silent -o /tmp/netbird.pkg "$pkg_url"

            # Add your x86_64 specific commands here
        elif [[ "$cpu_type" == "arm64" ]]; then
            echo "CPU type is M1/M2/M3"
            # Add your arm64 specific commands here
            pkg_url=$(curl -sIL -o /dev/null -w '%{url_effective}' https://github.com/netbirdio/netbird/releases/download/v$requiredVersion/netbird_${requiredVersion}_darwin_arm64.pkg)
            curl --silent -o /tmp/netbird.pkg "$pkg_url"
        else
            echo "Unsupported CPU type: $cpu_type"
            exit 1
        fi
    fi
    echo installing pkg
    killall -9 netbird-ui  > /dev/null 2>&1
    installer -pkg "/tmp/netbird.pkg" -target /

    /usr/local/bin/netbird service stop   > /dev/null 2>&1
    sleep 3
    /usr/local/bin/netbird service start   > /dev/null 2>&1
    sudo -u "$logged_in_user" open -g "/Applications/NetBird.app"
    sleep 3
    echo updating config file and restarting
    /usr/local/bin/netbird service stop  > /dev/null 2>&1
    killall -9 netbird-ui  > /dev/null 2>&1
    killall -9 netbird  > /dev/null 2>&1
    sleep 5
    update_config # execute function
    /usr/local/bin/netbird service start
    sleep 5
    sudo -u "$logged_in_user" open -g "/Applications/NetBird.app"
    sleep 15
fi
echo "Host file:"
cat /etc/hosts | grep $netbird_domain
echo "config.json Host:"
sudo cat /etc/netbird/config.json | grep \"Host\":
echo "SSH Config file:"
cat $CONFIG_FILE | grep ServerAlive
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
