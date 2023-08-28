#!/bin/bash

# # # # # # # # # # # # # # # # # # # # # # #
#  _____    __    __                     _  #
#  FLOUT —— FLuka OUtput processing scripT  #
#  ‾‾‾‾‾    ‾‾    ‾‾                     ‾  #
#  version 0.9.5                            #
#                                           #
# # # # # # # # # # # # # # # # # # # # # # #

if (( "${BASH_VERSINFO[0]}" < 4 )); then
	echo "Error: FLOUT requires 'bash' version >= 4" >&2
	exit 1
fi
set -f	# disable filename expansion (globbing)

function PrintHelp(){
	echo "
    Usage:
    flout [mode] [file]
    flout [mode] [file] [parameter 1]...[parameter n]
    flout [mode] [file] -d [directory]
    flout [mode] [file] -d [directory] [parameter 1]...[parameter n]

    Modes:
    auto       	flout -a fluka_input.inp
    interactive	flout -i fluka_input.inp
    manual     	flout -m user_input.txt
    scan       	flout -s fluka_input.inp

    Copy or move results to directory:
    flout [mode] [file] -d /path/to/directory

    Optional parameters:
    --log  		save output from fluka readout programs
    --clean		move (rather than copy) results to /path/to/directory
    --dat  		convert USRBIN binary to plain text
    --reuse		reprocessing of already processed binary files
    --old  		use readout programs from old (INFN) FLUKA package
"
}

function ReadUserInput(){
	local IFS=$'\n'
	FILENAME="$(sed -n 1p "$1")"
	FILENAME="$(echo -n "$FILENAME" | sed 's/[[:space:]]//g')"
	if [[ "$FILENAME" == "" ]]; then
		echo "Error: empty name in user input '$1'" >&2
		exit 1
	fi
	local string=""
	local found=""
	local unit=""
	local scorer=""
	local key=""
	for string in $(sed -n '2,$ p' "$1"); do
		found="false"
		unit="$(echo -n "$string" | cut -d " " -f1)"
		scorer="$(echo -n "$string" | cut -d " " -f2)"
		if (( "$unit" > 0 )) && (( "$unit" < 1000 )); then
			for key in "${!SCORECARDS[@]}"; do
				if [[ "$key" == "$scorer" ]]; then
					found="true"
					UNITS["$unit"]="$scorer"
					break
				fi
			done
			if [[ "$found" == "false" ]]; then
				echo "Error: illegal scorer in entry 'string' in user input '$1'" >&2
				exit 1
			fi
		else
			echo "Error: illegal unit in entry 'string' in user input '$1'" >&2
			exit 1
		fi
	done
}

function ReadFlukaInput(){
	local IFS=$'\n'
	COMM="false"	# comment line
	TITLE="false"	# title card
	FIXED="true"	# input file format
	GEO="false"		# geometry description
	CONT="false"	# continuation card
	HASDET="false"	# input file has DETECT card
	NUMBER=""		# variable for passing result from GetFixedWHAT and GetFreeWHAT functions
	UNIT=""			# variable for passing result from GetUnit function
	CODEWD=""
	declare -A DEFS	# preprocessor definitions
	declare -A LEVELS
	declare -A PROC
	PREPRO="true"
	LEVEL=0
	LEVELS["$LEVEL"]="true"
	PROC["$LEVEL"]="true"
	local promptuser="true"
	local found=""
	local answer=""
	local string=""
	local unit=""
	local scorer=""
	local key=""
	#### 1st pass of the file ####
	GetGlobalFormat "$1"
	#### cleanup ####
	for key in "${!DEFS[@]}"; do
		unset DEFS["$key"]
	done
	for key in "${!LEVELS[@]}"; do
		unset LEVELS["$key"]
	done
	for key in "${!PROC[@]}"; do
		unset PROC["$key"]
	done
	PREPRO="true"
	LEVEL=0
	LEVELS["$LEVEL"]="true"
	PROC["$LEVEL"]="true"
	#### 2nd pass of the file ####
	for string in $(sed -n '1,$ p' "$1"); do
		#### Skip comment ####
		CheckComment "$string"
		if [[ "$COMM" == "true" ]]; then
			continue
		fi
		#### Strip comment ####
		string="$(echo -n "$string" | sed 's/![[:print:]]*$//')"
		if [[ "$string" == "" ]]; then
			continue
		fi
		#### Preprocessor ####
		CheckPrepro "$string"
		if [[ "$PREPRO" == "false" ]]; then
			continue
		fi
		#### Card name ####
		CODEWD=""
		GetCODEWD "$string"
		#### Set format ####
		if [[ "$CODEWD" == "GLOBAL" ]]; then
			continue
		elif [[ "$CODEWD" == "FIXED" ]]; then
			FIXED="true"
			continue
		elif [[ "$CODEWD" == "FREE" ]]; then
			FIXED="false"
			continue
		fi
		#### Skip Title ####
		if [[ "$CODEWD" == "TITLE" ]]; then
			TITLE="true"
			continue
		fi
		if [[ "$TITLE" == "true" ]]; then
			TITLE="false"
			continue
		fi
		#### Skip geometry ####
		if [[ "$CODEWD" == "GEOBEGIN" ]]; then
			GEO="true"
			continue
		fi
		if [[ "$GEO" == "true" ]]; then
			if [[ "$CODEWD" == "GEOEND" ]]; then
				GEO="false"
			fi
			continue
		fi
		#### Skip already found DETECT card ####
		if [[ "$CODEWD" == "DETECT" ]] && [[ "$HASDET" == "true" ]]; then
			continue
		fi
		#### Save scoring card ####
		for scorer in "${!SCORECARDS[@]}"; do
			if [[ "$CODEWD" == "$scorer" ]]; then
				#### Check continuation ####
				CheckContinuation "$string"
				if [[ "$CONT" == "true" ]]; then
					CONT="false"
					break
				fi
				#### Logical unit for scorer ####
				GetUnit "$string"
				if [[ "$UNIT" == "0" ]]; then
					break
				fi
				#### Check for duplicates in skipped units ####
				found="false"
				for key in "${UNITS_SKIPPED[@]}"; do
					if [[ "$key" == "$UNIT" ]]; then
						found="true"
						break
					fi
				done
				if [[ "$found" == "true" ]]; then
					break
				fi
				#### Check for duplicates in units for processing ####
				found="false"
				for key in "${!UNITS[@]}"; do
					if [[ "$key" == "$UNIT" ]]; then
						found="true"
						break
					fi
				done
				if [[ "$found" == "true" ]]; then
					break
				fi
				#### Interactive mode ####
				if [[ "$INTERACTIVE" == "true" ]]; then
					if [[ "$promptuser" == "true" ]]; then
						promptuser="false"
						echo ""
						echo "Press 'y' to process or any other key to skip:"
					fi
					echo -ne "[ ] unit $UNIT $scorer\r"
					read -r -n 1 -s answer
					if [[ "$answer" == "y" ]] || [[ "$answer" == "Y" ]]; then
						echo -n "[+] unit $UNIT $scorer"
						sleep 0.2
						echo ""
					else
						UNITS_SKIPPED+=("$UNIT")
						echo -n "[ ] unit $UNIT $scorer"
						sleep 0.2
						echo ""
					fi
				fi
				UNITS["$UNIT"]="$scorer"
				break
			fi
		done
	done
}

function ProcessFlukaOutput(){
	local unit="$1"
	local name_pattern=""
	local dummy=""
	local merged_name=""
	local merged_file=""
	local readout=""
	local ext=""
	#### Search for files ####
	if [[ "${SETTINGS[reuse]}" == "false" ]]; then
		name_pattern="^${FILENAME}[[:print:]]*fort.${unit}$" # e.g. "example...fort.47" for "example_01001_fort.47"
		dummy="$(ls -1 | grep "$name_pattern")"
		if [[ "$dummy" == "" ]]; then
			name_pattern="^${FILENAME}[[:print:]]*ftn.${unit}$" # e.g. "example...ftn.47" for "example_01001_ftn.47"
			dummy="$(ls -1 | grep "$name_pattern")"
		fi
	else
		if [[ "${UNITS[$unit]}" == "USRYIELD" ]]; then
			echo "Warning: could not reuse unit $unit USRYIELD data" >&2	# SIGFPE usysuw.f:924 and usysuw.f:1410
			return
		fi
		name_pattern="^${FILENAME}[[:print:]]*$unit${SCORECARDS[${UNITS[$unit]}]}" # e.g. "example...47.bnx" for "example_47.bnx"
		dummy="$(ls -1 | grep "$name_pattern")"
	fi
	if [[ "$dummy" == "" ]]; then
		echo "Warning: unit $unit ${UNITS[$unit]} files not found" >&2
		return
	fi
	#### Input ####
	{
		echo ""
		echo "##########"
		echo "Processing [$FILECOUNT/$FILETOTAL] unit $unit ${UNITS[$unit]}"
		echo "##########"
	} >> "$LOGFILE"
	ls -1 | grep "$name_pattern" > "$TXTFILE"
	echo "" >> "$TXTFILE"
	if [[ "${unit}" == "17" ]]; then # DETECT output is always on unit 17
		merged_name="${FILENAME}_${unit}.dtc"
	else
		merged_name="${FILENAME}_${unit}"
	fi
	echo "$merged_name" >> "$TXTFILE"
	#### Processing ####
	echo -ne "[ ] [$FILECOUNT/$FILETOTAL] unit $unit ${UNITS[$unit]}\r"
	readout="${READOUTS[${UNITS[$unit]}]}"
	cat "$TXTFILE" | "$readout" >> "$LOGFILE"
	if [[ "${UNITS[$unit]}" == "USRBIN" ]] && [[ "${SETTINGS[dat]}" == "true" ]]; then # convert USRBIN binary output to plain text
		echo "${merged_name}.bnn" > "$TXTFILE"
		echo "${merged_name}.dat" >> "$TXTFILE"
		readout="${READOUTS[BIN2DAT]}"
		cat "$TXTFILE" | "$readout" >> "$LOGFILE"
	fi
	echo  "[+] [$FILECOUNT/$FILETOTAL] unit $unit ${UNITS[$unit]}"
	#### Add files for further copy/move operations ####
	if [[ "$DESTDIR" != "" ]]; then
		for ext in "${SCORECARDS[${UNITS[$unit]}]}" "_sum.lis" "_tab.lis"; do
			merged_file="${FILENAME}_${unit}${ext}"
			if [[ -f "$merged_file" ]]; then
				FILELIST+=("$merged_file")
			fi
		done
		if [[ "${UNITS[$unit]}" == "USRBIN" ]] && [[ "${SETTINGS[dat]}" == "true" ]]; then
			merged_file="${merged_name}.dat"
			if [[ -f "$merged_file" ]]; then
				FILELIST+=("$merged_file")
			fi
		fi
	fi
}

function CopyFiles(){
	local file=""
	local count=0
	local total="${#FILELIST[@]}"
	echo ""
	if [[ "$total" == "0" ]]; then
		echo "Warning: no files to copy to the specified directory" >&2
		return
	fi
	#### Copy files ####
	if [[ "${SETTINGS[clean]}" == "true" ]]; then
		echo "Moving files:"
	else
		echo "Copying files:"
	fi
	for file in "${FILELIST[@]}"; do
		(( ++count ))
		echo -ne "[ ] [$count/$total] $file\r"
		if [[ "${SETTINGS[clean]}" == "true" ]]; then
			mv "$file" "$DESTDIR"
		else
			cp "$file" "$DESTDIR"/"$file"
		fi
		echo "[+] [$count/$total] $file"
	done
	#### Copy log ####
	if [[ "${SETTINGS[log]}" == "true" ]]; then
		if [[ "${SETTINGS[clean]}" == "true" ]]; then
			mv "$LOGFILE" "$DESTDIR"
		else
			cp "$LOGFILE" "$DESTDIR"/"$LOGFILE"
		fi
	fi
	#### Print path to destination directory ####
	if [[ "${SETTINGS[clean]}" == "true" ]]; then
		echo "Files moved to $DESTDIR"
	else
		echo "Files copied to $DESTDIR"
	fi
}

function GetGlobalFormat(){
	local string=""
	local codewd=""
	local what4=""
	for string in $( sed -n '1,$ p' "$1"); do
		#### Skip comment ####
		CheckComment "$string"
		if [[ "$COMM" == "true" ]]; then
			continue
		fi
		#### Strip comment ####
		string="$(echo -n "$string" | sed 's/![[:print:]]*$//')"
		if [[ "$string" == "" ]]; then
			continue
		fi
		#### Preprocessor ####
		CheckPrepro "$string"
		if [[ "$PREPRO" == "false" ]]; then
			continue
		fi
		#### Global format ####
		codewd="$(echo -n "$string" | cut -c 1-10 | sed 's/[[:space:]]*$//')"
		if [[ "$codewd" == "GLOBAL" ]]; then
			GetFixedWHAT "$string" "4"
			what4="$NUMBER"
			if [[ "$what4" == "" ]] || (( "$what4" < 0 )) ; then
				what4=1
			fi
			if [[ "$what4" == "2" ]] || [[ "$what4" == "3" ]]; then
				FIXED="false"
			else
				FIXED="true"
			fi
			break
		fi
	done
}

function CheckComment(){
	if [[ "$(echo -n "$1" | cut -c 1)" == '*' ]]; then
		COMM="true"
	else
		COMM="false"
	fi
}

function CheckPrepro(){
	if [[ "$(echo -n "$1" | cut -c 1)" != '#' ]]; then
		return
	fi
	local id=""
	local def=""
	def="$(echo -n "$1" | cut -d " " -f1)"
	local idname=""
	idname="$(echo -n "$1" | cut -d " " -f2)"
	if [[ "$def" == "#define" ]]; then
		if [[ "$PREPRO" == "true" ]]; then
			DEFS["$idname"]=""
		fi
	elif [[ "$def" == "#undef" ]]; then
		if [[ "$PREPRO" == "true" ]]; then
			unset DEFS["$idname"]
		fi
	elif [[ "$def" == "#if" ]] || [[ "$def" == "#ifdef" ]]; then
		(( ++LEVEL ))
		for id in "${!DEFS[@]}"; do
			if [[ "$id" == "$idname" ]]; then
				LEVELS["$LEVEL"]="true"
				PROC["$LEVEL"]="true"
				ApplyPrepro
				return
			fi
		done
		LEVELS["$LEVEL"]="false"
		PROC["$LEVEL"]="false"
		ApplyPrepro
	elif [[ "$def" == "#ifndef" ]]; then
		(( ++LEVEL ))
		for id in "${!DEFS[@]}"; do
			if [[ "$id" == "$idname" ]]; then
				LEVELS["$LEVEL"]="false"
				PROC["$LEVEL"]="false"
				ApplyPrepro
				return
			fi
		done
		LEVELS["$LEVEL"]="true"
		PROC["$LEVEL"]="true"
		ApplyPrepro
	elif [[ "$def" == "#elif" ]]; then
		if [[ "${LEVELS[$LEVEL]}" == "true" ]]; then
			PROC["$LEVEL"]="false"
			ApplyPrepro
		else
			for id in "${!DEFS[@]}"; do
				if [[ "$id" == "$idname" ]]; then
					LEVELS["$LEVEL"]="true"
					PROC["$LEVEL"]="true"
					ApplyPrepro
					return
				fi
			done
			PROC["$LEVEL"]="false"
			ApplyPrepro
		fi
	elif [[ "$def" == "#else" ]]; then
		if [[ "${LEVELS[$LEVEL]}" == "true" ]]; then
			PROC["$LEVEL"]="false"
		else
			LEVELS["$LEVEL"]="true"
			PROC["$LEVEL"]="true"
		fi
		ApplyPrepro
	elif [[ "$def" == "#endif" ]]; then
		unset LEVELS["$LEVEL"]
		unset PROC["$LEVEL"]
		(( --LEVEL ))
		ApplyPrepro
	elif [[ "$def" == "#include" ]]; then
		echo "Warning: ignore '#include' directive" >&2
	else
		echo "Error: unknown preprocessor directive '$def'" >&2
		exit 1
	fi
}

function ApplyPrepro(){
	local found="false"
	local key=""
	for key in "${PROC[@]}"; do
		if [[ "$key" == "false" ]]; then
			found="true"
			break
		fi
	done
	if [[ "$found" == "true" ]]; then
		PREPRO="false"
	else
		PREPRO="true"
	fi
}

function GetCODEWD(){
	if [[ "$FIXED" == "true" ]] && [[ "$GEO" == "false" ]]; then
		CODEWD="$(echo -n "$1" | cut -c 1-10 | sed 's/[[:space:]]*$//')"
	else
		local str=""
		str="$(echo -n "$1" | sed 's/^[[:space:]]*//')"
		local IFS=' ,;:\'
		local tok=($str)
		CODEWD="${tok[0]}"
	fi
}

function CheckContinuation(){
	local str=""
	local len=""
	local tok=""
	if [[ "$FIXED" == "true" ]]; then
		str="$(echo -n "$1" | cut -c 71-78 | sed 's/[[:space:]]//g')"
		len="${#str}"
		for (( i=0; i<len; i++ ))
		{
			tok="${str:$i:1}"
			if [[ "$tok" == '&' ]];then
				CONT="true"
				break
			fi
		}
	else
		str="$1"
		len="${#str}"
		local last=$(( len - 1 ))
		tok="${str:$last:1}"
		if [[ "$tok" == '&' ]]; then
			CONT="true"
		fi
	fi
}

function GetUnit(){
	if [[ "$CODEWD" == "DETECT" ]]; then
		HASDET="true"
		NUMBER=-17	# DETECT is always unformatted on unit 17
	elif [[ "$CODEWD" == "RESNUCLE" ]]; then
		GetWHAT "$1" "2"
	else
		GetWHAT "$1" "3"
	fi
	if [[ "$NUMBER" == "" ]]; then
		NUMBER=11 # standard output unit (formatted)
	fi
	if [[ "$(echo -n "$NUMBER" | cut -c 1)" == "-" ]]; then
		UNIT="$(echo -n "$NUMBER" | cut -c 2-)"
	else
		UNIT=0
	fi
}

function GetWHAT(){
	if [[ "$FIXED" == "true" ]]; then
		GetFixedWHAT "$1" "$2"
	else
		GetFreeWHAT "$1" "$2"
	fi
}

function GetFixedWHAT(){
	local pos1=$(( $2 * 10 + 1 ))
	local pos2=$(( $2 * 10 + 10 ))
	NUMBER="$(echo -n "$1" | cut -c $pos1-$pos2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$/0/;s/\.0*$//')"
}

function GetFreeWHAT(){
	local str=""
	str="$(echo -n "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
	local IFS=' ,;:\'
	local tok=($str)
	NUMBER="$(echo -n "${tok[$2]}" | sed 's/\.0*$//')"
}

#### Begin ####
if [[ ! -w $PWD ]]; then
	echo "Error: no write permission for current directory" >&2
	exit 1
fi

#### Globals ####
declare -A SETTINGS	# key=SETTING, val=VALUE
INTERACTIVE="false"		# -i option
MANUAL="false"			# -m option
SCAN="false"			# -s option
INPUTFILE=""
UIFILE=""
DESTDIR=""			# -d option
KEY=""
PAR=""				# -- optional arguments
FOUND=""
declare -A READOUTS	# key=SCORER, val=READOUT
THETIME=""
LOGFILE=""
TXTFILE=""
FILENAME=""
FILECOUNT=0
FILETOTAL=0
FILELIST=()			# contains names of output files from fluka readouts
UNITMIN=""
UNITS_SKIPPED=()
declare -A UNITS	# key=UNIT, val=SCORECARD
declare -A SCORECARDS	# key=SCORECARD, val=EXTENTION
SCORECARDS["DETECT"]=".dtc"
SCORECARDS["RESNUCLE"]=".rnc"
SCORECARDS["USRBDX"]=".bnx"
SCORECARDS["USRBIN"]=".bnn"
SCORECARDS["USRCOLL"]=".trk"
SCORECARDS["USRTRACK"]=".trk"
SCORECARDS["USRYIELD"]=".yie"

#### Settings ####
SETTINGS=( ["log"]="false" ["clean"]="false" ["dat"]="false" ["reuse"]="false" ["old"]="false" )	# default settings

#### Check command line arguments ####
case "$1" in
-a)	INTERACTIVE="false";;
-i)	INTERACTIVE="true";;
-m)	MANUAL="true";;
-s)	SCAN="true";;
-h) PrintHelp
	exit 1;;
*)	echo "Error: illegal mode '$1'" >&2
	echo "Use 'flout -h' to get help" >&2
	exit 1;;
esac

if [[ ! -f "$2" ]]; then
	echo "Error: input file '$2' not found" >&2
	exit 1
fi
INPUTFILE="$(readlink -f "$2")"

shift
shift

if [[ "$1" != "" ]]; then
	if [[ "$1" == "-d" ]]; then
		if [[ ! -d $2 ]]; then
			echo "Error: directory '$2' not found" >&2
			exit 1
		fi
		if [[ ! -w $2 ]]; then
			echo "Error: no write permission for destination directory" >&2
			exit 1
		fi
		DESTDIR="$(readlink -f "$2")"
		shift
		shift
	elif [[ "$(echo -n "$1" | cut -c 1-2)" != "--" ]]; then
		echo "Error: illegal parameter '$1'" >&2
		echo "Use 'flout -h' to get help" >&2
		exit 1
	fi
	for PAR in "$@"; do
		FOUND="false"
		for KEY in "${!SETTINGS[@]}"; do
			if [[ "$(echo -n "$PAR" | cut -c 3-)" == "$KEY" ]]; then
				FOUND="true"
				SETTINGS["$KEY"]="true"
				shift
				break
			fi
		done
		if [[ "$FOUND" == "false" ]]; then
			echo "Error: illegal parameter '$PAR'" >&2
			echo "Use 'flout -h' to get help" >&2
			exit 1
		fi
	done
fi

#### Fluka readout programs ####
if [[ "${SETTINGS[old]}" == "true" ]]; then
	READOUTS["DETECT"]="$(which "$FLUPRO"/flutil/detsuw)"
	READOUTS["RESNUCLE"]="$(which "$FLUPRO"/flutil/usrsuw)"
	READOUTS["USRBDX"]="$(which "$FLUPRO"/flutil/usxsuw)"
	READOUTS["USRBIN"]="$(which "$FLUPRO"/flutil/usbsuw)"
	READOUTS["USRTRACK"]="$(which "$FLUPRO"/flutil/ustsuw)"
	READOUTS["USRCOLL"]="$(which "$FLUPRO"/flutil/ustsuw)"
	READOUTS["USRYIELD"]="$(which "$FLUPRO"/flutil/usysuw)"
	READOUTS["BIN2DAT"]="$(which "$FLUPRO"/flutil/usbrea)"
else
	READOUTS["DETECT"]="$(which detsuw)"
	READOUTS["RESNUCLE"]="$(which usrsuw)"
	READOUTS["USRBDX"]="$(which usxsuw)"
	READOUTS["USRBIN"]="$(which usbsuw)"
	READOUTS["USRTRACK"]="$(which ustsuw)"
	READOUTS["USRCOLL"]="$(which ustsuw)"
	READOUTS["USRYIELD"]="$(which usysuw)"
	READOUTS["BIN2DAT"]="$(which usbrea)"
fi
for KEY in "${!READOUTS[@]}"; do
	if [[ "${READOUTS[$KEY]}" == "" ]]; then
		echo "Error: fluka '$KEY' readout program not found" >&2
		exit 1
	fi
done

#### Files ####
THETIME="$(date +"%F_%H-%M-%S")"
TXTFILE="flout_$THETIME.txt"
if [[ "${SETTINGS[log]}" == "true" ]]; then
	LOGFILE="flout_$THETIME.log"
else
	LOGFILE="/dev/null"
fi

#### Read input file ####
if [[ "$MANUAL" == "true" ]]; then
	ReadUserInput "$INPUTFILE"
else
	FILENAME="$(echo -n "$(basename "$INPUTFILE")" | sed 's/\.\(inp\|INP\)$//')"
	ReadFlukaInput "$INPUTFILE"
fi

#### Process fluka output files ####
FILETOTAL="${#UNITS[@]}"
if [[ "$FILETOTAL" == "0" ]]; then
	echo "Warning: no files to process" >&2
	exit 1
fi
echo ""
echo "Processing:"
UNITMIN=1000
if [[ "$SCAN" == "false" ]]; then
	touch "$TXTFILE"
	if [[ "${SETTINGS[log]}" == "true" ]]; then
		touch "$LOGFILE"
	fi
else
	UIFILE="${FILENAME}.txt"
	touch "$UIFILE"
	echo "$FILENAME" > "$UIFILE"
fi

while (( "${#UNITS[@]}" > 0 )); do
	for KEY in "${!UNITS[@]}"; do
		if (( "$KEY" < "$UNITMIN" )); then
			UNITMIN="$KEY"
		fi
	done
	(( ++FILECOUNT ))
	if [[ "$SCAN" == "false" ]]; then
		ProcessFlukaOutput "$UNITMIN"
	else
		echo "$UNITMIN ${UNITS[$UNITMIN]}" >> "$UIFILE"
	fi
	unset UNITS["$UNITMIN"]
	UNITMIN=1000
done

#### Copy or move processed files ####
if [[ "$SCAN" == "false" ]]; then
	rm "$TXTFILE"
	if [[ "$DESTDIR" != "" ]]; then
		CopyFiles
	fi
	if [[ "${SETTINGS[log]}" == "true" ]]; then
		echo "Log file: $LOGFILE"
	fi
else
	echo "User input file: $UIFILE"
fi

echo ""
#### End ####
