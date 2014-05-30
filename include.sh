#!/bin/bash
export NAME=solve
export ALLEGRO5_PATH_WINDOWS="C:\\programs\\git\\DAllegro5"
export ALLEGRO5_PATH_LINUX="/c/programs/git/DAllegro5"
export LINKER_FLAGS="-L/STACK:268435456"
export OUTPUT_NAME="binary\\$NAME.exe"
export SOURCES=`ls source/*.d`
#echo $SOURCES
export ARCHITECTURE_OPTIONS="-m32"
#export ARCHITECTURE_OPTIONS="-m64"
export DEBUG_OPTIONS="-debug -unittest"
export RELEASE_OPTIONS="-O -release -inline -noboundscheck"
export COMMON_OPTIONS="$ARCHITECTURE_OPTIONS -O -inline -wi -odobject"
#-L/SUBSYSTEM:CONSOLE:4.0
#-L/SUBSYSTEM:WINDOWS:4.0
