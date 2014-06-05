#!/bin/bash
source include.sh
export OPTIONS="$COMMON_OPTIONS $RELEASE_OPTIONS $@"
dmd $OPTIONS $SOURCES -I$ALLEGRO5_PATH_WINDOWS -of$OUTPUT_NAME $LINKER_FLAGS

echo "#!/bin/bash" > run.sh
echo "source include.sh" >> run.sh
echo "export PATH=\$PATH:\$ALLEGRO5_PATH_LINUX" >> run.sh
#echo "start binary/\$NAME.exe >log.txt" >> run.sh
echo "binary/\$NAME.exe \$@" >> run.sh
