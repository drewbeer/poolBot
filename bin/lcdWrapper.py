#!/usr/bin/python

import sys
from Adafruit_CharLCD import Adafruit_CharLCD
from subprocess import *
from time import sleep, strftime
from datetime import datetime

lcd = Adafruit_CharLCD()

inMessage = sys.argv[1:]

lcd.begin(16, 1)
lcd.clear()
lcd.message(inMessage)
