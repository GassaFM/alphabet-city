#!/bin/bash
export NAME=solve
export ALLEGRO5_PATH_WINDOWS="C:\\programs\\git\\DAllegro5"
export ALLEGRO5_PATH_LINUX="/c/programs/git/DAllegro5"
export LINKER_FLAGS="-L/STACK:268435456"
export OUTPUT_NAME="binary\\$NAME.exe"
export SOURCES=`ls source/*.d`
#echo $SOURCES
export DEBUG_OPTIONS="-debug -unittest"
export RELEASE_OPTIONS="-O -release -inline -noboundscheck"
export COMMON_OPTIONS="-O -inline -wi -odobject"
#-L/SUBSYSTEM:WINDOWS
