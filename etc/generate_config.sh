#!/bin/sh
# $Id$

# Script to generate specific config files for different languages
# from one global config file 'global.cfg'. This way all configuration
# data which is shared between different languages used in the system
# has to be changed in only one place: the global config file.
#
# Usage: generate_config.sh <extension>
#
# <extension> may be a complete filename (including path), but only
# the extension (after the last dot) is taken. A configuration file
# is then generated from 'config.template.<extension>' and 'global.cfg'
# into 'config.<extension>'.
#
#
# See 'global.cfg' for the syntax of that file.
#
# Syntax of the language specific templates:
#
# In these files different tags are used to specify parts of the files
# which are replaced by automatically generated content. Tags must
# exactly appear once with a 'START' and after that an 'END' suffix
# and different tags may not overlap. The next tags are defined:
#
# 'GLOBAL CONFIG INCLUDE'
#	Within these tags the content generated from the global config
#	file is placed. All previous content is removed.
#
# 'AUTOGENERATE HEADER'
#	Within these tags some information on the automatic generation of
#	the config file is placed. All previous content is removed.
#
# Content in the configuration templates outside of any tags is copied
# as is to the config file. Here language specific configuration data
# can be placed and other things you like...
#
# Part of the DOMjudge Programming Contest Jury System and licenced
# under the GNU GPL. See README and COPYING for details.

# Exit on any error:
set -e

GLOBALCONF=global.cfg
LANGCONF=config
LANGTEMPLATE=config.template

CONFHEADTAG="AUTOGENERATE HEADER"
CONFMAINTAG="GLOBAL CONFIG INCLUDE"

# Maximum number of lines in config files
MAXLINES=1000

if [ -z "$1" ]; then
	echo "Usage: $0 <filename> | <extension>"
	exit 1
fi

EXT=${1##*.}
TEMPLATE="$LANGTEMPLATE.$EXT"
CONFIG="$LANGCONF.$EXT"

case $EXT in
	h)	COMMENT='//';;
	sh)	COMMENT='#';;
	php)	COMMENT='//';;
	tex)	COMMENT='%';;
	*)	echo "Filetype '$EXT' is not supported."; exit 1;;
esac

if [ ! -r "$TEMPLATE" ]; then
	echo "Template '$TEMPLATE' does not exist."
	exit 1
fi

if [ ! -r "$GLOBALCONF" ]; then
	echo "Global config '$GLOBALCONF' does not exist."
	exit 1
fi

# Store config generated from global config here
TMPMAIN=main.$EXT.new
TMPHEAD=head.$EXT.new

# Clean any previous tempfiles left:
rm -f $TMPHEAD $TMPMAIN

COMMANDLINE="$0 $@"


# Generate language specific config from global config
exec 3<$GLOBALCONF

OLDIFS=$IFS

LINENR=0
while IFS='='; read VARDEF VALUE <&3; do
	IFS=$OLDIFS
	LINENR=$(($LINENR+1))
	
	# Ignore comments and whitespace only lines
	if echo "$VARDEF" | egrep '^([[:space:]]*$|#)' >/dev/null ; then
		continue
	fi

	ATTR_STRING=0
	ATTR_EVAL=0
	# Check for attributes
	if [ "$VARDEF" != "${VARDEF%\[*}" ]; then
		VARATTR=${VARDEF#*\[}
		if ! echo "$VARATTR" | egrep '^[a-z]+(,[a-z]+)*]$' >/dev/null ; then
			echo "Parse error on line $LINENR!"
			exit 1
		fi
		VARATTR=${VARATTR%\]}
		IFS="$IFS,"
		for ATTR in $VARATTR; do
			case "$ATTR" in
			string)	ATTR_STRING=1;;
			eval)	ATTR_EVAL=1;;
			*)	echo "Unknown variable attribute '$ATTR' on line $LINENR!"
				exit 1;;
			esac
		done
		IFS=$OLDIFS
	fi
	VARNAME=${VARDEF%%\[*}
	if ! echo "$VARNAME" | egrep '^[A-Za-z][A-Za-z0-9_]*$' >/dev/null ; then
		echo "Invalid variable name '$VARNAME' on line $LINENR!"
		exit 1
	fi

	# Escape quoting characters ' and ":
	VALUE=$(echo "$VALUE" | sed "s!'!\\'!;"'s!"!\\"!' )

	if [ $ATTR_EVAL -ne 0 ]; then
		eval VALUE="\"$VALUE\""
	fi

	if [ $ATTR_STRING -ne 0 ]; then
		case $EXT in
		h)    echo "#define $VARNAME \"$VALUE\""   >>$TMPMAIN;;
		sh)   echo "$VARNAME=\"$VALUE\""           >>$TMPMAIN;;
		php)  echo "define('$VARNAME', '$VALUE');" >>$TMPMAIN;;
		tex)  echo "\\def\\$VARNAME{$VALUE}"       >>$TMPMAIN;;
		esac
	else
		case $EXT in
		h)    echo "#define $VARNAME $VALUE"       >>$TMPMAIN;;
		sh)   echo "$VARNAME=$VALUE"               >>$TMPMAIN;;
		php)  echo "define('$VARNAME', $VALUE);"   >>$TMPMAIN;;
		tex)  echo "\\def\\$VARNAME{$VALUE}"       >>$TMPMAIN;;
		esac
	fi

	if set | grep ^${VARNAME}= >/dev/null ; then
		echo "Variable '$VARNAME' already in use on line $LINENR!"
		exit 1
	fi

	eval $VARNAME="\"$VALUE\""
done

exec 3<&-

# Generate header tags include
cat >>$TMPHEAD <<EOF
$COMMENT
$COMMENT This configuration file was automatically generated
$COMMENT with command '$COMMANDLINE'
$COMMENT on `date` on host '`hostname`'.
$COMMENT
$COMMENT Do not edit this file by hand! Instead, edit parts of this
$COMMENT file which are outside the '$CONFHEADTAG' and
$COMMENT '$CONFMAINTAG' tags in the templates '$LANGTEMPLATE.*'.
$COMMENT
$COMMENT Configuration options inside '$CONFMAINTAG' tags
$COMMENT should be edited in the main configuration file '$GLOBALCONF'
$COMMENT and then be included here by running 'make config' in the root
$COMMENT of the system directory.
$COMMENT
EOF

config_include ()
{
	TAG=$1
	CFGFILE=$2
	TAGFILE=$3

	TMPFILE=$CFGFILE.new

	NSTART=`grep "$TAG START" $CFGFILE | wc -l`
	NEND=`  grep "$TAG END"   $CFGFILE | wc -l`
	if [ $NSTART -ne 1 -o $NEND -ne 1 ]; then
		echo "Incorrect number of '$TAG' START and/or END tags in $CFGFILE!"
		exit 1
	fi
	if [ `grep -A $MAXLINES "$TAG START" $CFGFILE | grep "$TAG END" | wc -l` -ne 1 ]; then
		echo "'$TAG' END tag does not close START tag in $CFGFILE!"
		exit 1
	fi

	grep -B $MAXLINES "$TAG START" $CFGFILE >$TMPFILE
	cat $TAGFILE >>$TMPFILE
	grep -A $MAXLINES "$TAG END"   $CFGFILE >>$TMPFILE
	mv $TMPFILE $CFGFILE
}

cp -p $TEMPLATE $CONFIG

config_include "$CONFHEADTAG" $CONFIG $TMPHEAD
config_include "$CONFMAINTAG" $CONFIG $TMPMAIN

rm -f $TMPHEAD $TMPMAIN

exit 0
