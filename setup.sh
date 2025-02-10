#!/bin/bash

# Check if the script is being run as root and exit if it is
# Needed to get the current user
if [ "$EUID" -eq 0 ]
  then echo "Do not run this script as root"
  exit
fi


case $1 in
        -u) echo "Updading Mac-like-automatic-brightness..."
          echo "Stopping AB service..."
          sudo systemctl kill AB
          echo "Updating AutomaticBrightness.sh..."
          echo "Cloning AutomaticBrighness.sh..."
          sudo cp AutomaticBrightness.sh /usr/local/bin/AutomaticBrightness.sh
          echo "Updating AB.service for systemD..."
          echo "Cloning AB.service for systemD..."
          sudo cp AB.service /etc/systemd/system/AB.service
          echo "Restarting AB service..."
          systemctl daemon-reload
          sudo systemctl start AB
          exit;;
esac

echo "Setting up AutomaticBrightness.sh as a service..."

echo "Calibrating Light Sensor Scale..."

LightSensorPath=$(find -L /sys/bus/iio/devices -maxdepth 2  -name "in_illuminance_raw" 2>/dev/null | grep "in_illuminance_raw")

echo "Put your sensor in a bright light (outside works best)"
read -p "Press Enter to continue..."

LightSensorMax=$(cat $LightSensorPath)

echo "Saving Light Sensor Max: $LightSensorMax"

echo "Put your sensor in a dark light (cover the sensor with hand works best)"
read -p "Press Enter to continue..."

LightSensorMin=$(cat $LightSensorPath)

CurrentUser=$(whoami)

echo "Saving Light Sensor Min: $LightSensorMin"

awk -v new_phrase="LightSensorMax=$LightSensorMax" '/LightSensorMax=/{ print new_phrase; next } 1' AutomaticBrightness.sh  > temp && mv temp AutomaticBrightness.sh
awk -v new_phrase="LightSensorMin=$LightSensorMin" '/LightSensorMin=/{ print new_phrase; next } 1' AutomaticBrightness.sh  > temp && mv temp AutomaticBrightness.sh
awk -v new_phrase="User=$CurrentUser" '/User=/{ print new_phrase; next } 1' AutomaticBrightness.sh  > temp && mv temp AutomaticBrightness.sh

echo "Stopping AB service..."
sudo systemctl kill AB


echo "Cloning AutomaticBrighness.sh..."
sudo cp AutomaticBrightness.sh /usr/local/bin/AutomaticBrightness.sh
sudo chmod u+x /usr/local/bin/AutomaticBrightness.sh

echo "Cloning AB.service for systemD..."
sudo cp AB.service /etc/systemd/system/AB.service


echo "Startin Service..."
sudo systemctl daemon-reload
sudo systemctl enable AB
sudo systemctl start AB
