#!/usr/bin/python
#
# basicaly created by DrewBeer, and licensed as Free as in Beer.
# this is the first time i have ever written python 10-3-2014
#
# code used from Alan Aufderheide - https://github.com/aufder/RaspberryPiLcdMenu
#
import commands
import os
import curses
import threading
import RPi.GPIO as GPIO
from string import split
from time import sleep, strftime, localtime
from xml.dom.minidom import *
from Adafruit_CharLCD import Adafruit_CharLCD
from subprocess import *
from ListSelector import ListSelector


# nav tree
configfile = 'lcdmenu.xml'

# set DEBUG=1 for print debug statements
DEBUG = 1
stdscr.nodelay(1)

# LCD settings
DISPLAY_ROWS = 2
DISPLAY_COLS = 16
lcd = Adafruit_CharLCD()
lcd.begin(DISPLAY_COLS, DISPLAY_ROWS)

# GPIO SETTINGS
# # Define GPIO inputs and outputs
E_PULSE = 0.00005
E_DELAY = 0.00005
wait = 0.1

GPIO.setmode(GPIO.BCM)

# BUTTONS
UP = 13
OK = 27
DN = 26

GPIO.setup(OK, GPIO.IN, pull_up_down=GPIO.PUD_UP)
GPIO.setup(DN, GPIO.IN, pull_up_down=GPIO.PUD_UP)
GPIO.setup(UP, GPIO.IN, pull_up_down=GPIO.PUD_UP)

# RELAYS
SpaRelay = 16
SaltRelay = 18
HeaterRelay = 19
LightRelay = 20

GPIO.setup(SpaRelay, GPIO.OUT, initial=GPIO.HIGH)
GPIO.setup(SaltRelay, GPIO.OUT, initial=GPIO.HIGH)
GPIO.setup(HeaterRelay, GPIO.OUT, initial=GPIO.HIGH)
GPIO.setup(LightRelay, GPIO.OUT, initial=GPIO.HIGH)


# functions
def uInput(key):

	gpioData = GPIO.input(key)
	keyboard = stdscr.getch()

	if key = "UP"
		if gpioData or keyboard = 259
			return True

	if key = "DN"
		if gpioData or keyboard = 258
			return True

	if key = "OK"
		if gpioData or keyboard = 261
			return True

	return gpioData

# commands
def DoQuit():
		lcd.clear()
		lcd.message('Are you sure?\nPress Sel for Y')
		sleep(0.25)
		while 1:
				if not (uInput(UP)):
						break
				if not (uInput(OK)):
						lcd.clear()
						lcd.message('goodbye dave')
						quit()
				sleep(0.25)


def DoShutdown():
		lcd.clear()
		lcd.message('Are you sure?\nPress Sel for Y')
		sleep(0.25)
		while 1:
				if not (uInput(UP)):
						break
				if not (uInput(OK)):
						lcd.clear()
						lcd.message('shutting down')
						commands.getoutput("shutdown -h now")
						quit()
				sleep(0.25)

def DoReboot():
		lcd.clear()
		lcd.message('Are you sure?\nPress Sel for Y')
		sleep(0.25)
		while 1:
				if not (uInput(UP)):
						break
				if not (uInput(OK)):
						lcd.clear()
						lcd.message('rebooting')
						commands.getoutput("reboot")
						quit()
				sleep(0.25)

def ShowDateTime():
		if DEBUG:
				stdscr.addstr('in ShowDateTime')
		lcd.clear()
		sleep(0.25)
		while not (uInput(OK)):
				sleep(0.25)
				lcd.home()
				lcd.message(strftime('%a %b %d %Y\n%I:%M:%S %p', localtime()))


def SetLocation():
		if DEBUG:
				stdscr.addstr('in SetLocation')
		global lcd
		list = []
		# coordinates usable by ephem library, lat, lon, elevation (m)
		list.append(['New York', '40.7143528', '-74.0059731', 9.775694])
		list.append(['Paris', '48.8566667', '2.3509871', 35.917042])
		selector = ListSelector(list, lcd)
		item = selector.Pick()
		# do something useful
		if (item >= 0):
				chosen = list[item]

### main stuff

## dashboard
def ShowDashboard():

		if DEBUG:
				stdscr.addstr('in ShowDashbaord')
		lcd.clear()
		while 1:
				sleep(0.25)
				lcd.message('mode:auto pump:on\ntemp:78 salt:00')

				if not uInput(UP) or not uInput(DN) or not uInput(OK):
					break

## Spa controls
# toggle pump
def PumpSpaToggle():
	sleep(0.25)
	while 1:
		spaJetStatus = uInput(SpaRelay)
		# if the jets are off
		if spaJetStatus:
			if DEBUG:
				stdscr.addstr('jets off')
			spaJetsMsg = "off"
			spaToggleVal = 0
			spaToggleMsg = "on"
		# if the jets are already on
		if not spaJetStatus:
			if DEBUG:
				stdscr.addstr('jets on')
			spaJetsMsg = "on"
		 	spaToggleVal = 1
		 	spaToggleMsg = "off"

		lcd.clear()
		lcd.message('Spa Booster\nStatus: %s ' % spaJetsMsg)
		if not uInput(UP) or not uInput(DN):
			break
		if not uInput(OK):
			lcd.clear()
			lcd.message('Turning jets %s' % spaToggleMsg)
			GPIO.output(SpaRelay, spaToggleVal)
			sleep(1.5)
		sleep(0.25)

# pump timer
# Spa controls
def PumpSpaTimer():
	if DEBUG:
			stdscr.addstr('in PumpSpaTimer')


def goBack():
		if DEBUG:
				stdscr.addstr('in goBack')
		display.update('l')
		display.display()

class CommandToRun:
		def __init__(self, myName, theCommand):
				self.text = myName
				self.commandToRun = theCommand
		def Run(self):
				self.clist = split(commands.getoutput(self.commandToRun), '\n')
				if len(self.clist) > 0:
						lcd.clear()
						lcd.message(self.clist[0])
						for i in range(1, len(self.clist)):
								while 1:
										if lcd.buttonPressed(lcd.DOWN):
												break
										sleep(0.25)
								lcd.clear()
								lcd.message(self.clist[i-1]+'\n'+self.clist[i])
								sleep(0.5)
				while 1:
						if lcd.buttonPressed(lcd.LEFT):
								break

class Widget:
		def __init__(self, myName, myFunction):
				self.text = myName
				self.function = myFunction

class Folder:
		def __init__(self, myName, myParent):
				self.text = myName
				self.items = []
				self.parent = myParent

def ProcessNode(currentNode, currentItem):
		children = currentNode.childNodes

		for child in children:
				if isinstance(child, xml.dom.minidom.Element):
						if child.tagName == 'folder':
								thisFolder = Folder(child.getAttribute('text'), currentItem)
								currentItem.items.append(thisFolder)
								ProcessNode(child, thisFolder)
						elif child.tagName == 'widget':
								thisWidget = Widget(child.getAttribute('text'), child.getAttribute('function'))
								currentItem.items.append(thisWidget)
						elif child.tagName == 'run':
								thisCommand = CommandToRun(child.getAttribute('text'), child.firstChild.data)
								currentItem.items.append(thisCommand)

class Display:
		def __init__(self, folder):
				self.curFolder = folder
				self.curTopItem = 0
				self.curSelectedItem = 0
		def display(self):
				if self.curTopItem > len(self.curFolder.items) - DISPLAY_ROWS:
						self.curTopItem = len(self.curFolder.items) - DISPLAY_ROWS
				if self.curTopItem < 0:
						self.curTopItem = 0
				if DEBUG:
						stdscr.addstr('------------------')
				str = ''
				for row in range(self.curTopItem, self.curTopItem+DISPLAY_ROWS):
						if row > self.curTopItem:
								str += '\n'
						if row < len(self.curFolder.items):
								if row == self.curSelectedItem:
										cmd = '-'+self.curFolder.items[row].text
										if len(cmd) < 16:
												for row in range(len(cmd), 16):
														cmd += ' '
										if DEBUG:
												stdscr.addstr('|'+cmd+'|')
										str += cmd
								else:
										cmd = ' '+self.curFolder.items[row].text
										if len(cmd) < 16:
												for row in range(len(cmd), 16):
														cmd += ' '
										if DEBUG:
												stdscr.addstr('|'+cmd+'|')
										str += cmd
				if DEBUG:
						stdscr.addstr('------------------')
				lcd.home()
				lcd.message(str)

		def update(self, command):
				if DEBUG:
						stdscr.addstr('do',command)
				if command == 'u':
						self.up()
				elif command == 'l':
						self.left()
				elif command == 'd':
						self.down()
				elif command == 's':
						self.select()
		def up(self):
				if self.curSelectedItem == 0:
						return
				elif self.curSelectedItem > self.curTopItem:
						self.curSelectedItem -= 1
				else:
						self.curTopItem -= 1
						self.curSelectedItem -= 1
		def down(self):
				if self.curSelectedItem+1 == len(self.curFolder.items):
						return
				elif self.curSelectedItem < self.curTopItem+DISPLAY_ROWS-1:
						self.curSelectedItem += 1
				else:
						self.curTopItem += 1
						self.curSelectedItem += 1
		def left(self):
				if isinstance(self.curFolder.parent, Folder):
						# find the current in the parent
						itemno = 0
						index = 0
						for item in self.curFolder.parent.items:
								if self.curFolder == item:
										if DEBUG:
												stdscr.addstr('foundit')
										index = itemno
								else:
										itemno += 1
						if index < len(self.curFolder.parent.items):
								self.curFolder = self.curFolder.parent
								self.curTopItem = index
								self.curSelectedItem = index
						else:
								self.curFolder = self.curFolder.parent
								self.curTopItem = 0
								self.curSelectedItem = 0
		def select(self):
				if DEBUG:
						stdscr.addstr('check widget')
				if isinstance(self.curFolder.items[self.curSelectedItem], Folder):
						self.curFolder = self.curFolder.items[self.curSelectedItem]
						self.curTopItem = 0
						self.curSelectedItem = 0
				elif isinstance(self.curFolder.items[self.curSelectedItem], Widget):
						if DEBUG:
								stdscr.addstr('eval', self.curFolder.items[self.curSelectedItem].function)
						eval(self.curFolder.items[self.curSelectedItem].function+'()')
				elif isinstance(self.curFolder.items[self.curSelectedItem], CommandToRun):
						self.curFolder.items[self.curSelectedItem].Run()

def main(stdscr):
#### START OF MAIN LOOP ######

	ShowDashboard()

	# now start things up
	uiItems = Folder('root','')

	dom = parse(configfile) # parse an XML file by name

	top = dom.documentElement

	ProcessNode(top, uiItems)

	display = Display(uiItems)
	display.display()

	if DEBUG:
		stdscr.addstr('start while')

	timeout = 1000000
	dashTime = 0

	while True:

		# this creates a timeout so it reverts
		# to the dashboard after like a minute
		dashTime += 1
		if dashTime > timeout:
			ShowDashboard()
			dashTime = 0

		ok = uInput(OK)
		dn = uInput(DN)
		up = uInput(UP)

		if not up:
			display.update('u')
			display.display()
			dashTime = 0
			sleep(0.25)

		if not dn:
			display.update('d')
			display.display()
			dashTime = 0
			sleep(0.25)

		if not ok:
			display.update('s')
			display.display()
			dashTime = 0
			sleep(0.25)

if __name__ == '__main__':
		curses.wrapper(main)
