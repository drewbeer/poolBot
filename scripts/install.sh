#!/bin/bash

wget http://raspberry.znix.com/hipifiles/hipi-install
perl hipi-install
cpanm Mojolicious::Lite LWP::Simple Log::Log4perl Date::Calc Schedule::Cron
