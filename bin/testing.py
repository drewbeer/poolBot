#!/usr/bin/python

import subprocess
import RPi.GPIO as GPIO
GPIO.setmode(GPIO.BCM)

from Adafruit_CharLCD import Adafruit_CharLCD
from subprocess import *
from time import sleep, strftime
from datetime import datetime

lcd = Adafruit_CharLCD()

#cmd = "/usr/bin/tmux-mem-cpu-load | awk '{print $2, $3, $4}'"
cmd = "uptime | awk '{print $2, $3, $4, $9, $10}'"

lcd.begin(16, 1)


def run_cmd(cmd):
    p = Popen(cmd, shell=True, stdout=PIPE)
    output = p.communicate()[0]
    return output

GPIO.setup(26, GPIO.IN, pull_up_down=GPIO.PUD_UP)

lcd.clear()
lcd.message('Are you sure?\nPress Sel for Y')
while 1:
        if GPIO.wait_for_edge(26, GPIO.FALLING)
            lcd.clear()
            commands.getoutput("sudo wall test")
            quit()
        sleep(0.25)

GPIO.cleanup()
