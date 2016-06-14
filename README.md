objstor
=====

OpenStack Swift Object Storage front end written in bash with minimal dependencies and simplicity in mind.


Dependencies
=====

* curl
* file
* grep
* awk
* md5sum
* dd
* tr


Usage
=====

```
Usage: objstor.sh [options] <action> [path] [path2...]
Options:
   -u Username
   -k Key
   -a Auth URL
   -o Overwrite existing file/object

Actions:
   stats - Get information about your Object Storage account.

   save - Save authentication details specified with -u -k and -a to ~/.objstor
     so they do not need to be specified in later calls of the program.
     The ~/.objstor file is a simple bash file that is sourced.

   ls - List the contents of the container specified. This will return the
     containers if none specified. If an object is specified, it's details
     are retrieved.

   get - Download the object specified to the current directory. If the
     filename already exists in the current directory, an error is
     returned. Specifying -o will overwrite the existing file.

   put - Upload file to object storage. The container is specified as the
     first argument and the list of files following that. If an object
     already exists, it will not be overwritten unless -o option is used.

   del - Delete file(s) in object storage. The path must include the container
     first. Multiple files may be specified for deletion.

Other Notes:
   Authentication information specified with the -u -k and -a options takes precedence over the configured ~/.objstor credentials.

Examples:
   Save:
    objstor.sh save -u myusername -k mykey -a 'https://swift.server.url/auth'

   List:
    objstor.sh ls
    objstor.sh ls mycontainer
    objstor.sh ls mycontainer/myobject

   Get:
    objstor.sh get mycontainer/myobject

   Put:
    objstor.sh put mycontainer mylocalfile myotherlocalfile

   Delete:
    objstor.sh del mycontainer/myobject mycontainer/myotherobject

Return Codes:
   0 - Success!
   1 - Undefined error
   2 - Missing dependency
   3 - Incorrect arguments passed
   4 - Missing credentials
   5 - Failed authentication
```
