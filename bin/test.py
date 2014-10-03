from time import *
import time
import sys
import collections
import datetime
from Adafruit_CharLCD import Adafruit_CharLCD
from datetime import datetime
from subprocess import *
import RPi.GPIO as GPIO



# # Define GPIO inputs and outputs
# MODE
E_PULSE = 0.00005
E_DELAY = 0.00005
wait = 0.1

# BUTTONS
UP = 13
OK = 27
DN = 26

tag = 0
val = 0
p = 0
try:
   def main():
      # Main program block
      print "test"
      
      tag = 0
      val = 0
      p = 0
   
      GPIO.setmode(GPIO.BCM)
   
      GPIO.setup(OK, GPIO.IN, pull_up_down=GPIO.PUD_UP)
      GPIO.setup(DN, GPIO.IN, pull_up_down=GPIO.PUD_UP)
      GPIO.setup(UP, GPIO.IN, pull_up_down=GPIO.PUD_UP)
      
      ok = GPIO.input(OK)
      dn = GPIO.input(DN)
      up = GPIO.input(UP)
   
      p   = 0
      tag = 0
      val = 0

      while True:
          ok = GPIO.input(OK)
          dn = GPIO.input(DN)
          up = GPIO.input(UP)
	  if ok == False:
            	p = "ok"
          if dn == False:
                p = "dn"
          if up == False:
        	p = "up"
          if p != 0:
	    result = message(tag, val, p)
            val = result['val']
            tag = result['tag']
            p = 0
          sleep(wait)

   def message(tag, val, button):
	# setup lcd
	lcd = Adafruit_CharLCD()

	# clear screen
	lcd.begin(16, 1)
	lcd.clear()
      	lcd.message("you pressed " + button)
      	if button == "ok":
        	tag = tag + 10
	if button == "dn":
        	val = val - 1
      	if button == "up":
         	val = val + 1
	lcd.message("\nval " + str(val) + " tag " + str(tag))
      
      	return{'tag':tag, 'val':val}  


   GPIO.cleanup()
   
   if __name__ == '__main__':
      main()
   
   GPIO.cleanup()
except Exception,e: 
   GPIO.cleanup()
   print str(e)

