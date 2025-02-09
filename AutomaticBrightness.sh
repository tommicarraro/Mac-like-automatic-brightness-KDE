#!/bin/bash
## Thanks to steel99xl (https://github.com/steel99xl/Mac-like-automatic-brightness) for the base script and idea

###### VARIABLES ######
###### EDIT HERE ######
# User that will be used to change the brightness
User=""

# Desktop Environment
DesktopEnvironment="KDE"

# Enable Keyboard Backlight Control
KeyboardBacklightControl="true"

#How much light change must be seen by the sensor before it will act
LightSensorThresholdChange=10

#How often should the sensor be checked (in seconds)
SensorDelay=5
# Minimum Brightness 
LightSensorMin=1

# Maximum Brightness
LightSensorMax=169

# Speed of the screen refresh rate in Hz
Frequency=60

# These variables are automatically calculated based on the Frequency of your screen
# Feel to change them if you know what you are doing

# How many steps should be taken to reach the new brightness. DEFAULT: the frequency of your screen
LevelSteps=$Frequency
# How long should each step take. DEFAULT: 1 / LevelSteps
AnimationDelay=$(echo "scale=4; 1 / $Frequency" | bc)

###### END EDIT ######

# Set the priority of the current script
priority=19 # Priority level , 0 = regular app , 19 = very much background app

# Set the priority of the current script
renice "$priority" "$$"

# Get screen max brightness value
MaxScreenBrightness=$(find -L /sys/class/backlight -maxdepth 2 -name "max_brightness" 2>/dev/null | grep "max_brightness" | xargs cat)

# Get screen min brightness value
MinScreenBrightness=1

# Set path to current luminance sensor
LightSensorPath=$(find -L /sys/bus/iio/devices -maxdepth 2  -name "in_illuminance_raw" 2>/dev/null | grep "in_illuminance_raw")

# Set path to current screen brightness
ScreenBrightnessPath=$(find -L /sys/class/backlight -maxdepth 2 -name "brightness" 2>/dev/null | grep "brightness")

# Set path to current keyboard brightness
#TODO: KeyboardBrightnessPath=

#Set the current light value so we have something to compare to
LightSensorOld=$(cat $LightSensorPath)

# Variables needed by functions
LightSensorCurrent=$(cat $LightSensorPath)
Changer_toggle=0
CurrentScreenBrightness=0
ScreenBrightnessStep=0

# Function to check if is time to change the brightness
light_sensor_check() {
    LightSensorCurrent=$(cat $LightSensorPath)
    # Calculate at what the Light Sensor should trigger
    LightThresholdTriggerMin=$(($LightSensorOld - $LightSensorThresholdChange))
    LightThresholdTriggerMax=$(($LightSensorOld + $LightSensorThresholdChange))

    # Check if the current light value is outside the trigger range and execute the change of the brightness
    if [[ $LightSensorCurrent -gt $LightThresholdTriggerMax ]] || [[ $LightSensorCurrent -lt $LightThresholdTriggerMin ]]
    then
        return 0
    else
        return 1
    fi
}

# Function to change the brightness of the screen
# Arguments: $1 = Percentage of the brightness to set
screen_brightness_animation() {
    # Do a loop and change the brigchtness in steps
    for i in $(eval echo {1..$LevelSteps} )
    do
        # Calculate the new brightness value, increasing or decreasing from the current value taking the sign of the LightIncrease, and multiply by 100 to get the percentage
        ScreenBrightnessSet=$(LC_NUMERIC=C printf "%.0f" $(echo "scale=2; $CurrentScreenBrightness + ( $ScreenBrightnessStep * $i )" | bc ))
        # Check if the new brightness value is within the bounds of the screen brightness
        if [[ $ScreenBrightnessSet -gt $MaxScreenBrightness ]]
        then
            # Set the new brightness value using sysfs which is faster than qdbus-qt5
            echo $ScreenBrightnessSet > $MaxScreenBrightness
            exit 0
        elif [[ $ScreenBrightnessSet -lt $MinScreenBrightness ]]
        then
            # Set the new brightness value using sysfs which is faster than qdbus-qt5
            echo $ScreenBrightnessSet > $MinScreenBrightness
            exit 0
        fi
        # Set the new brightness value using sysfs which is faster than qdbus-qt5
        echo $ScreenBrightnessSet > $ScreenBrightnessPath
        
        # Sleep for the screen Hz time so he effect is visible
        sleep $AnimationDelay
    done
}

# Main loop
while true
do
    # Do a loop while the light_sensor_check function returns 1
    while light_sensor_check
    do
        Changer_toggle=1
        # Calculate the increase in percentage of the current light sensor value from the old one, remembering the LightSensorMax and LightSensorMin values
        LightIncrease=$(LC_NUMERIC=C printf "%.2f" $(echo "scale=2; ( ( $LightSensorCurrent - $LightSensorOld ) / ( $LightSensorMax - $LightSensorMin ) ) * 100" | bc ))

        # Calculate the new brightness in percetage, increasing or decreasing from the current value
        CurrentScreenBrightness=$(cat $ScreenBrightnessPath)
        NewScreenBrightness=$(LC_NUMERIC=C printf "%.0f" $(echo "scale=2; $CurrentScreenBrightness + ( $LightIncrease * ( $MaxScreenBrightness - $MinScreenBrightness ) / 100 )" | bc ))

        # Calculate the step size for the brightness change
        ScreenBrightnessStep=$(LC_NUMERIC=C printf "%.0f" $(echo "scale=2; ( $NewScreenBrightness - $CurrentScreenBrightness ) / $LevelSteps" | bc ))

        screen_brightness_animation $1

        # Store new light as old light for next comparison
        LightSensorOld=$LightSensorCurrent
    done

    # Set the new brightness value using qdbus-qt5 for KDE
    if [[ $Changer_toggle -eq 1 ]] && [[ $DesktopEnvironment == "KDE" ]]
    then
        Changer_toggle=0
         # Calculate for KDE the new screen brightness value in percentage from what the sensor value is, to be sent to KDE's brightness control
        ScreenBrightnessSet=$(LC_NUMERIC=C printf "%.0f" $(echo "scale=2; (( $ScreenBrightnessSet - $MinScreenBrightness ) * 100 / ( $MaxScreenBrightness - $MinScreenBrightness )) *100" | bc ))
        sudo -u "$User" env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$User")/bus" qdbus-qt5 local.org_kde_powerdevil /org/kde/Solid/PowerManagement/Actions/BrightnessControl setBrightness $ScreenBrightnessSet
    fi

    # Calculate for the Keyboard Backlight the new screen brightness value in percentage from what the sensor value is, to be sent to the Keyboard Backlight control
    if [[ $Changer_toggle -eq 1 ]] && [[ $KeyboardBacklightControl == "true" ]]
    then
        CurrentKeyboardBrightness=$(sudo dbus-send --system --print-reply --dest="org.freedesktop.UPower" "/org/freedesktop/UPower/KbdBacklight" "org.freedesktop.UPower.KbdBacklight.GetBrightness" | awk '{print $2}')
        # Change the Keyboard Brightness knowing that the Keyboard Brightness is a value between 0 and 100
        KeyboardBrightnessSet=$(LC_NUMERIC=C printf "%.0f" $(echo "scale=2; ($CurrentKeyboardBrightness + $LightIncrease)" | bc ))
        # Check if the new brightness value is within the bounds of the keyboard brightness
        if [[ $KeyboardBrightnessSet -gt 100 ]]
        then
            KeyboardBrightnessSet=100
        elif [[ $KeyboardBrightnessSet -lt 0 ]]
        then
            KeyboardBrightnessSet=0
        fi
        sudo dbus-send --system --type=method_call  --dest="org.freedesktop.UPower" "/org/freedesktop/UPower/KbdBacklight" "org.freedesktop.UPower.KbdBacklight.SetBrightness" int32:$KeyboardBrightnessSet
    fi
    
    # Sleep for the sensor delay time     
	sleep $SensorDelay
done