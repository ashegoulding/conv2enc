#!/bin/bash
__PROG_NAME="conv2utf8_bom.sh"
__TMP_DIR="/tmp/conv2utf8_bom"
__CMDS=("iconv" "uuidgen" "chardetect" "bc" "stat" "chmod" "chown")
__CONF_RATE="0.8"

if [ "$#" -lt 1 ]; then
	cat >&2 << EOT
Usage: $__PROG_NAME [A file to convert [file2 [file3 ...]]]
This script won't touch the original file if:
	- chardetect confidence rate less is than $__CONF_RATE
	- Conversion fails without //IGNORE or //TRANSLIT option.
This script will try to preserve the file's mode and owner.

사용법: $__PROG_NAME [변환할 파일 [파일2 [파일3 ...]]]
이 스크립트는 다음 상황에서 원본 파일을 건들이지 않습니다:
	- chardetect의 confidence가 $__CONF_RATE 이하일 때.
	- //IGNORE나 //TRANSLIT 옵션없이 변환을 할 수 없을 때.
이 스크립트는 원본 파일의 모드와 소유자 정보를 유지할 것입니다.

tmp directory: $__TMP_DIR
Author: david@danusys.com
Rev: 0

EOT
fi
# Check if the commands we need are present.
declare -a missingCmds
j=0
for i in ${__CMDS[@]}; do
	"$i" 2> /dev/null 1> /dev/null < /dev/null
	if [ "$?" -eq 127 ]; then
		missingCmds[$j]="$i"
		let j++
	fi
done
if [ "${#missingCmds[@]}" -gt 0 ]; then
	echo -n "**Fatal: Command missing: " >&2
	for i in ${missingCmds[@]}; do
		echo -n ${missingCmds[$i]} >&2
	done
	echo "" >&2
	exit 1
fi
if [ "$#" -lt 1 ]; then
	exit 1
fi

mkdir -p "$__TMP_DIR"
if [ $? -ne 0 ]; then
	echo "**Fatal: temp directory not usable($__TMP_DIR)." >&2
	exit 2
fi

for THE_FILE in "$@"
do
	if [ ! -f "$THE_FILE" ]; then
		echo "$THE_FILE: Where is the file?" >&2
		continue
	fi
	out=`chardetect "$THE_FILE"`
	if [ "$?" -ne 0 ]; then
		echo "$THE_FILE: Sorry! Couldn't detect the encoding." >&2
		continue
	fi

	chop=`expr length "$THE_FILE: "`
	out=${out:$chop}
	arr=(${out// / })
	encoding=${arr[0]}
	encoding="${encoding,,}" #Lower the string
	rate=${arr[3]}
	# Check the 'confidence' rate.
	if (( $(echo "$rate < $__CONF_RATE" | bc) )); then
		echo "$out (No go for conversion.)" >&2
		continue
	fi
	head -c3 "$THE_FILE" | hexdump -C | grep -i 'ef bb bf' > /dev/null 2> /dev/null
	if [ $? -eq 0 ]; then
		echo "$THE_FILE: Starts with BOM. Skipping."
		continue
	fi
	if [ "$encoding" == "utf-8" ] || [ "$encoding" == "utf8" ] || [ "$(head -c3 "$THE_FILE")" == '\xef\xbb\xbf' ]; then
		echo "$THE_FILE: Already UTF-8. Skipping." >&2
		continue
	fi

	tmpfile="$__TMP_DIR/$$_`uuidgen -r`" # Salt the shell's PID to avoid conflict when using concurrently
	# Convert!
	echo -ne '\xEF\xBB\xBF' > "$tmpfile" # Marking BOM
	iconv -f "$encoding" -t "utf-8" < "$THE_FILE" >> "$tmpfile"
	if [ "$?" -ne 0 ]; then
		echo "$THE_FILE: Non-zero exit code from iconv($?)" >&2
		continue
	fi
	# Preserve the owner and mode of the file.
	mode=`stat -c "%a" "$THE_FILE"`
	owner=`stat -c "%u:%g" "$THE_FILE"`

	mv "$tmpfile" "$THE_FILE"

	chmod "$mode" "$THE_FILE"
	chown "$owner" "$THE_FILE"
done

exit 0

