poolBot
======

Raspberry PI powered pool automation project

this is basically broken into a bunch of different systems.

- deviceUI.py this is responsible for the physical aspect of the system
- poolBot.pl this is the api wrapper that is sort of the center of everything

the one that really matters is the poolBot.pl. this is a perl web server that is bascially a api to the different systems. so it talks to the nodejs pool controler, rachio, and the gpio ports that are wired in.

## requirements
this project relies on a few other great projects, especially because that means i don't have to reinvent anything. first and foremost you're going to need
to have nodejs-poolController installed and running. its whats responsible for talking to either your pool controller, pump, salt, or whatever it can control.
also if you have a rachio, and you've replaced the valve to a zone, then you can also control the pool fill.


