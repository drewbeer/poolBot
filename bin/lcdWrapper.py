#!/usr/bin/python

import sys
from Adafruit_CharLCD import Adafruit_CharLCD
from subprocess import *
from time import sleep, strftime
from datetime import datetime

# LCD settings
DISPLAY_ROWS = 2
DISPLAY_COLS = 16
lcd = Adafruit_CharLCD()
lcd.begin(DISPLAY_COLS, DISPLAY_ROWS)

inMessage = sys.argv[1].decode("string_escape")
lcd.clear()
lcd.message(str(inMessage))

