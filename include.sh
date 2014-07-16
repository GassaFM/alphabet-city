#!/bin/bash
export NAME=solve
export ALLEGRO5_PATH_WINDOWS="C:\\programs\\git\\DAllegro5"
export ALLEGRO5_PATH_LINUX="/c/programs/git/DAllegro5"
export LINKER_FLAGS="-L/STACK:268435456"
export OUTPUT_NAME="binary\\$NAME.exe"
export SOURCES=`ls source/{,search/}*.d`
export DC=dmd
#export DC=C:\\Tools\\ldc2\\bin\\ldmd2
#export DC='bash C:\\Tools\\gdc\\bin\\gdmd.sh'
#echo $SOURCES
#export ARCHITECTURE_OPTIONS="-m32"
export ARCHITECTURE_OPTIONS="-m64"
export DEBUG_OPTIONS="-g -debug -unittest"
export RELEASE_OPTIONS="-O -release -inline -noboundscheck"
export COMMON_OPTIONS="$ARCHITECTURE_OPTIONS -O -wi -odobject"
#-L/SUBSYSTEM:CONSOLE:4.0
#-L/SUBSYSTEM:WINDOWS:4.0
