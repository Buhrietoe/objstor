#!/bin/bash
# Written by: Jason Gardner
# https://github.com/Buhrietoe/objstor
# License: MIT
# Bash Command line utility for using swift object storage
# This was written with portability/minimal dependencies in mind and to keep it as simple as possible

# Print usage information
usage() {
  # Using my own tab var because 8 characters is too much
  local TAB='  '
  echo "Usage: $(basename $SCRIPTNAME) [options] <action> [path] [path2...]"
  echo "Options:"
  echo "$TAB -u Username"
  echo "$TAB -k Key"
  echo "$TAB -a Auth URL"
  echo "$TAB -o Overwrite existing file/object"
  echo
  echo "Actions:"
  echo "$TAB stats - Get information about your Object Storage account."
  echo
  echo "$TAB save - Save authentication details specified with -u -k and -a to ~/.objstor"
  echo "$TAB$TAB so they do not need to be specified in later calls of the program."
  echo "$TAB$TAB The ~/.objstor file is a simple bash file that is sourced."
  echo
  echo "$TAB list - List the contents of the container specified. This will return the"
  echo "$TAB$TAB containers if none specified. If an object is specified, it's details"
  echo "$TAB$TAB are retrieved."
  echo
  echo "$TAB get - Download the object specified to the current directory. If the"
  echo "$TAB$TAB filename already exists in the current directory, an error is"
  echo "$TAB$TAB returned. Specifying -o will overwrite the existing file."
  echo
  echo "$TAB put - Upload file to object storage. The container is specified as the"
  echo "$TAB$TAB first argument and the list of files following that. If an object"
  echo "$TAB$TAB already exists, it will not be overwritten unless -o option is used."
  echo
  echo "$TAB delete - Delete file(s) in object storage. The path must include the container"
  echo "$TAB$TAB first. Multiple files may be specified for deletion."
  echo
  echo "Other Notes:"
  echo "$TAB Authentication information specified with the -u -k and -a options takes precedence over the configured ~/.objstor credentials."
  echo
  echo "Examples:"
  echo "$TAB Save:"
  echo "$TAB$TAB$(basename $SCRIPTNAME) save -u myusername -k mykey -a 'https://swift.server.url/auth'"
  echo
  echo "$TAB List:"
  echo "$TAB$TAB$(basename $SCRIPTNAME) list"
  echo "$TAB$TAB$(basename $SCRIPTNAME) list mycontainer"
  echo "$TAB$TAB$(basename $SCRIPTNAME) list mycontainer/myobject"
  echo
  echo "$TAB Get:"
  echo "$TAB$TAB$(basename $SCRIPTNAME) get mycontainer/myobject"
  echo
  echo "$TAB Put:"
  echo "$TAB$TAB$(basename $SCRIPTNAME) put mycontainer mylocalfile myotherlocalfile"
  echo
  echo "$TAB Delete:"
  echo "$TAB$TAB$(basename $SCRIPTNAME) delete mycontainer/myobject mycontainer/myotherobject"
}

# Print errors to stderr
printError() {
  echo $1 >&2
}

# Check dependencies
# Check to ensure that our basic utilities are present. If not then error and quit.
checkDependencies() {
  CMDCURL=$(which curl 2>/dev/null)
  if [ -z "$CMDCURL" ]; then
    printError "curl binary not found in path. It is required."
    exit 1
  fi

  CMDMD5SUM=$(which md5sum 2>/dev/null)
  if [ -z "$CMDMD5SUM" ]; then
    printError "md5sum binary not found in path. It is required."
    exit 1
  fi

  CMDDD=$(which dd 2>/dev/null)
  if [ -z "$CMDDD" ]; then
    printError "dd binary not found in path. It is required."
    exit 1
  fi

  CMDFILE=$(which file 2>/dev/null)
  if [ -z "$CMDFILE" ]; then
    printError "file binary not found in path. It is required."
    exit 1
  fi

  CMDGREP=$(which grep 2>/dev/null)
  if [ -z "$CMDFILE" ]; then
    printError "grep binary not found in path. It is required."
    exit 1
  fi

  CMDAWK=$(which awk 2>/dev/null)
  if [ -z "$CMDFILE" ]; then
    printError "awk binary not found in path. It is required."
    exit 1
  fi

  CMDTR=$(which tr 2>/dev/null)
  if [ -z "$CMDFILE" ]; then
    printError "tr binary not found in path. It is required."
    exit 1
  fi
}

# Check for and load credentials
# Exits script with error if any credentials are missing
checkCredentials() {
  if [[ "$1" == 1 ]]; then
    if [[ -n "$APIUSER" && -n "$APIKEY" && -n "$APIURL" ]]; then
      echo 'yes'
      return
    else
      echo 'no'
      return
    fi
  else
    if [[ -z "$APIUSER" || -z "$APIKEY" || -z "$APIURL" ]]; then
      if [ -f $CREDENTIALFILE ]; then
        source $CREDENTIALFILE
        local RETURNRESULT=$(checkCredentials 1)
        if [ "$RETURNRESULT" == 'yes' ]; then
          true
        else
          printError "ERROR: All credential information not supplied!" && echo && exit 1
        fi
      else
        printError "ERROR: Credentials not supplied, and could not read credential file!" && echo && exit 1
      fi
    fi
  fi
  doAuth
}

# Perform Authentication
# APIUSER, APIKEY, and APIURL must already be set
# Variables set if successful:
# # OSCODE - HTTP return code
# # OSTOKEN - Auth token
# # OSURL - Storage URL for access
doAuth() {
  AUTHRESULT="$($CMDCURL -s -i -H "X-Auth-User: $APIUSER" -H "X-Auth-Key: $APIKEY" $APIURL)"
  OSCODE=$(parseCode "$AUTHRESULT")

  if [ "$OSCODE" != "200" ]; then
    printError "Authentication Failed!" && echo "$AUTHRESULT" && exit 1
  fi

  OSURL=$(echo "$AUTHRESULT" | $CMDGREP 'X-Storage-Url' | $CMDTR -d '\r' | $CMDAWK '{print $2}')
  OSTOKEN=$(echo "$AUTHRESULT" | $CMDGREP 'X-Storage-Token' | $CMDTR -d '\r' | $CMDAWK '{print $2}') 
}

# Check if an object exists
# Parameters: path
# Returns yes or no if the object exists
checkExist() {
  local OBJECTINFO=$(getInfo $1)
  local OBJECTCODE=$(parseCode "$OBJECTINFO")
  if [ "$OBJECTCODE" == "200" ]; then
    echo yes
  else
    echo no
  fi
}

# Parses the HTTP code from response header data and returns it
# Parameter: response header blob (getInfo)
# Returns: HTTP Code
parseCode() {
  local RETURNCODE=$(echo "$1" | $CMDGREP 'HTTP' | $CMDTR -d '\r' | $CMDAWK '{print $2}')
  echo "$RETURNCODE"
}

# Parses the objects md5 sum from response header data
# Parameter: response header blob (getInfo)
# Return: md5sum of object
parseMd5() {
  local MD5SUM=$(echo "$1" | $CMDGREP 'Etag' | $CMDTR -d '\r' | $CMDAWK '{print $2}')
  echo "$MD5SUM"
}

# Fetches md5sum of local copy and copy on object storage and compares them
# Parameters: local file path, object storage path
# Return: yes if match, no if files differ
matchMd5() {
  local OSOBJECTINFO=$(getInfo "$2")
  local OSMD5SUM=$(parseMd5 "$OSOBJECTINFO")
  local LOCALMD5SUM=$($CMDMD5SUM $1 | $CMDTR -d '\r' | $CMDAWK '{print $1}')
  if [ "$OSMD5SUM" == "$LOCALMD5SUM" ]; then
    echo yes
  else
    echo no
  fi
}

# Display information about your account usage
# Parameters: none
# Returns: Response headers with information about account
getStats() {
  local ACCTSTATS=$($CMDCURL -s -H "X-Auth-Token: $OSTOKEN" $OSURL -I)
  echo "$ACCTSTATS" | $CMDGREP 'X-Account' | $CMDTR -d '\r'
}

# Check and display a listing of the specified path.
# Parameter: path or object
# Returns: list of containers or object in a container, depending on the path given
getList() {
  $CMDCURL -s -H "X-Auth-Token: $OSTOKEN" $OSURL"$1"
}

# Retrieve information about an object
# Parameters: path or object
# Returns: RAW response headers from object located at path given
getInfo() {
  $CMDCURL -s -H "X-Auth-Token: $OSTOKEN" $OSURL"$1" -I
}

# Downloads an object from object storage to disk
# Parameters: path to object, local storage path
getObject() {
  $CMDCURL -H "X-Auth-Token: $OSTOKEN" $OSURL"$1" -o "$2"
}

# Upload an file
# Parameters: object storage container/path/object, location of local file
putObject() {
  $CMDCURL -H "X-Auth-Token: $OSTOKEN" $OSURL"$1" -T "$2" -X PUT -o /dev/null
}

# Create a directory object
# Parameters: object storage container/path
putDirectory() {
  $CMDCURL -s -H "X-Auth-Token: $OSTOKEN" -H "Content-Length: 0" -H "Content-Type: application/directory" $OSURL"$1" -X PUT
}

# Delete a file from object storage
# Parameters: path to object
deleteObject() {
  $CMDCURL -s -H "X-Auth-Token: $OSTOKEN" $OSURL"$1" -X DELETE
}

# Main function for the list action
actionList() {
  checkCredentials
  local NUMPATHS=${#ARGPATHS[@]}

  if [[ $NUMPATHS == 0 ]]; then
    local GETRESULT=$(getList)
    echo "$GETRESULT"
  else
    for i in ${ARGPATHS[@]}; do
      if [[ ${i:0:1} != "/" ]]; then
        i=/$i
      fi
      REQUESTINFO=$(getInfo $i)
      REQUESTCODE=$(parseCode "$REQUESTINFO")
      if [[ $REQUESTCODE == "200" ]]; then
        echo File: $i
        echo "$REQUESTINFO"
      elif [[ $REQUESTCODE == "204" ]]; then
        getList $i
      elif [[ $REQUESTCODE == "404" ]]; then
        echo File $i does not exist!
      else
        echo Unhandled response code: $REQUESTCODE
        echo "$REQUESTINFO"
      fi
    done
  fi
}

# Main function for the stats action
actionStats() {
  checkCredentials
  getStats
}

# Main function for the get action
actionGet() {
  checkCredentials
  getObject "${ARGPATHS[0]}" "${ARGPATHS[1]}"
}

# Main function for the put action
actionPut() {
  local NUMPATHS=${#ARGPATHS[@]}

  if [[ $NUMPATHS < 2 ]]; then
    printError "ERROR: You must specify a target container path and file or directory to upload!" && echo && exit 1
  fi

  checkCredentials
  if [[ ${ARGPATHS[0]:0:1} != "/" ]]; then
    local CONTLOC="/${ARGPATHS[0]}"
  else
    local CONTLOC="${ARGPATHS[0]}"
  fi
  if [[ ${ARGPATHS[0]:${#ARGPATHS[0]}-1:1} != "/" ]]; then
    local CONTLOC="$CONTLOC/"
  fi

  ARGPATHS=(${ARGPATHS[@]:1})
  for i in ${ARGPATHS[@]}; do
    # need to check local file here and start recursion loop
    local OSLOC="$CONTLOC""$i"
    local ONOS=$(checkExist "$OSLOC")
    if [[ "$ONOS" == 'no' ]]; then
      putObject "$OSLOC" "$i"
      echo "$i": UPLOADED : Average Speed "$OSSPEED" bytes/sec
    elif [[ "$ONOS" == 'yes' && "$OVERWRITEMODE" == 1 ]]; then
      local SUMMATCH=$(matchMd5 "$i" "$OSLOC")
      if [[ "$SUMMATCH" == "yes" ]]; then
        echo "$i": SKIPPING : md5 sums match, no re-upload necessary
      else
          putObject "$OSLOC" "$i"
          echo "$i": UPLOADED : Average Speed "$OSSPEED" bytes/sec
      fi
    else
      local SUMMATCH=$(matchMd5 "$i" "$OSLOC")
      if [[ "$SUMMATCH" == "yes" ]]; then
        echo "$i": SKIPPING : refusing to overwrite. Files are identical.
      else
        echo "$i": SKIPPING : refusing to overwrite without overwrite flag. Files differ.
      fi
    fi
  done
}

# Main function for the delete action
actionDelete() {
  checkCredentials
  echo "${ARGPATHS[0]}"
  deleteObject "${ARGPATHS[0]}"
}

# Main function for the save action
actionSave() {
  if [[ -z "$APIUSER" || -z "$APIKEY" || -z "$APIURL" ]]; then
    printError "ERROR: Missing all credential parameters!" && echo && exit 1
  fi

  echo "APIUSER='$APIUSER'" > $CREDENTIALFILE
  echo "APIKEY='$APIKEY'" >> $CREDENTIALFILE
  echo "APIURL='$APIURL'" >> $CREDENTIALFILE
}

# This is the main control flow function
main() {
  checkDependencies

  # Perform the action specified
  case $ARGACTION in
    "stats" ) actionStats;;
    "list" ) actionList;;
    "get" ) actionGet;;
    "put" ) actionPut;;
    "delete" ) actionDelete;;
    "save" ) actionSave;;
    * ) echo "Invalid Action!" && usage && exit 1
  esac
}

# Set defaults
OVERWRITEMODE="0"
SPLITSIZETHRESHOLD="5000000000"
SPLITSIZE="2000000000"
SCRIPTNAME=$0
ARGCOPY="$@"
CREDENTIALFILE=~/.objstor

# If no arguments given, display usage
if [ -z "$ARGCOPY" ]; then
  usage
  exit
fi

# Parse options on command line
OPTERR=0
while getopts "u:k:a:o" OPTION; do
  case $OPTION in
    u ) APIUSER="$OPTARG";;
    k ) APIKEY="$OPTARG";;
    a ) APIURL="$OPTARG";;
    o ) OVERWRITEMODE="1";;
    * ) echo "Invalid option!" && usage && exit 1;;
  esac
done
shift $(($OPTIND - 1))

# Grab the action specified on command line, then shift it off
ARGACTION=$1
shift 1

# Create array of paths specified
declare -a ARGPATHS=("$@")

main
