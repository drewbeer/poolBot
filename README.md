poolBot
======

documented mostly at https://drew.beer/blog/blog/project-poolbot

Raspberry PI powered pool automation project

this is basically broken into a bunch of different systems.

- deviceUI.py this is responsible for the physical aspect of the system (unfinished, and not in use right now)
- poolBot.pl this is the api wrapper that is sort of the center of everything

the one that really matters is the poolBot.pl. this is a perl web server that is bascially a api to the different systems. so it talks to the nodejs pool controler, rachio, and the gpio ports that are wired in.

## requirements
this project relies on a few other great projects, especially because that means i don't have to reinvent anything. first and foremost you're going to need
to have nodejs-poolController installed and running. its whats responsible for talking to either your pool controller, pump, salt, or whatever it can control.
also if you have a rachio, and you've replaced the valve to a zone, then you can also control the pool fill.

### updates - 2021-01
you no longer need nodered to handle scheduling, thats now built into the new poolBot code, also it pushes to influx itself instead of using nodered to scrape.

there is still an api to start and stop things, and get status of the system and relays. will be adding mqtt soon.

### updates - 2021-6
node-red is pretty much gone, and is not needed any longer. poolbot pushes to both mqtt, and to influx v3. new modes which can be called via api, and by scheduler
settings has been updated to reflect that, and also how to handle safety measures.
