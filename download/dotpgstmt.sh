#!/bin/bash

#####################################
# log
# error
#####################################
function log()
{
	if [ $# -ne 0 ]; then
		echo "[LOG]: $*"
	fi
}
function error()
{
	if [ $# -ne 0 ]; then
		echo "[ERROR]: $*"
	fi
	exit
}

##################
# stack
##################
MAXTOP=10
TOP=0
TEMP=
declare -a STACK

function stpush()
{
	# no arg, do nothing
	if [ $# -eq 0  ]; then
		return
	fi
	# push all args to stack
	while [ $# -gt 0 ]
	do
		if [ $TOP -eq $MAXTOP ]; then
			error "stack is full"
		fi
		let TOP++
		STACK[$TOP]=$1
		shift
	done
}

function stpop()
{
	TEMP=
	if [ $TOP -eq 0 ]; then
		error "stack is empty"
	fi
	TEMP=${STACK[$TOP]}
	unset STACK[$TOP]
	let TOP--
}

function printst()
{
	echo "@@ ----------STACK--------------"  
	for i in ${STACK[@]}  
	do  
		echo "@@ "$i  
	done  
	echo "@@ stack size = $TOP"  
	echo "@@ -----------------------------"  
	echo
}

function stlength()
{
	echo $TOP
}

function sttop()
{
	echo ${STACK[$TOP]}
}

function st2node()
{
	local len
	len=${#STACK[@]}
	local retstr=""
	if [ $len -eq 0 ]; then
		error "stack is empty"
	fi
	retstr="${STACK[$0]}"
	if [ $len -eq 1 ]; then
		echo $retstr
	fi

	for i in ${STACK[@]}
	do
		retstr=${retstr}:
	done
}


################################################################
# transform file format 
#
# file_trim:
#   1.Remove the blanks at both ends of the front and back
#   2.Replace : of the front to empty
#   3.Replace <> to empty
#             "  to '
#
# file_trim2format1:
#   xxx                  xxx
#      {AAA                 xxx{AAA
#         yyy     ===>         yyy
#         {BBB                 yyy{BBB
#         }                    }
#      }                    }
#
# file_format12format2: Eliminate parentheses 
#   xxx (                  xxx
#      {BBB                   xxx{BBB
#      }                      }
#      {CCC        ===>       xxx{CCC
#          {DDD                  {DDD
#          }                     }
#      }                      }
#   )                      )
#
########################################################
NODEPOINT=".nodepoint"
function file_check()
{
	if [ "x$1" = "x" ]; then
		return
	elif [ ! -f "$1" ]; then
		error "no such file: $1"
	fi

	local left
	local right
	left=`cat $1 | grep -o '{'`
	right=`cat $1 | grep -o '}'`
	if [ $left -ne $right ]; then
		error "{ and } are not mismatch"
	fi

	left=`cat $1 | grep -o '('`
	right=`cat $1 | grep -o ')'`
	if [ $left -ne $right ]; then
		error "( and ) are not mismatch"
	fi

	left=`cat $1 | grep -o '<'`
	right=`cat $1 | grep -o '>'`
	if [ $left -ne $right ]; then
		error "< and > are not mismatch"
	fi
}

function file_trim()
{
	if [ "x$1" = "x" ]; then
		return
	elif [ ! -f "$1" ]; then
		error "no such file: $1"
	fi

	local file="$1"
	local tmpfile="${file}.tmp"
	cp -f $file $tmpfile
	sed -e 's/<>//g' -e 's/''"''/'"'"'/g' -e 's/^\s*//g' -e 's/\s*$//g' -e 's/^://g' -e '/^$/d' $tmpfile > $file
	rm -f $tmpfile
}

function file_trim2format1()
{
	if [ "x$1" = "x" ]; then
		return
	elif [ ! -f "$1" ]; then
		error "no such file: $1"
	fi

	local file=$1
	local tmpfile="${file}.tmp"
	local pline
	local line
	rm -f $tmpfile && touch $tmpfile
	while read line
	do
		if [ ${line:0:1} = "{" ] && [ "x$pline" != "x" ] && [ ${pline:0-1} != "}" ] && [ ${pline:0-1} != "(" ]; then
			echo "${pline}${line}" >> $tmpfile
		else
			echo $line >> $tmpfile
		fi
		pline=$line
	done < $file

	mv $tmpfile $file
}

function file_format12format2()
{
	if [ "x$1" = "x" ]; then
		return
	elif [ ! -f "$1" ]; then
		error "no such file: $1"
	fi

	local file=$1
	local tmpfile="${file}.tmp"
	local pline
	local line
	rm -f $tmpfile && touch $tmpfile
	while read line
	do
		if [ ${line:0-1} = "(" ]; then
			stpush ${line%?}
			echo "${line%?}" >> $tmpfile
		elif [ ${line:0:1} = ")" ]; then
			stpop
		elif [ ${line:0:1} = '{' ] && [ "x$pline" != "x" ]; then
			if [ `stlength` -eq 0 ]; then
				error "$line is not in ()"
			else
				echo `sttop`"$line" >> $tmpfile
			fi
		else
			echo $line >> $tmpfile
		fi
		pline=$line
	done < $file

	mv $tmpfile $file
}

function file_format22node()
{
	if [ "x$1" = "x" ]; then
		return
	elif [ ! -f "$1" ]; then
		error "no such file: $1"
	fi

	local file="$1"
	local seg1
	local seg2
	local nodename
	local nodep=$NODEPOINT
	while read line
	do
		if [ ${line:0:1} = '{' ]; then
			nodename=${line:1}
			stpush $nodename
			echo $nodename >> $nodename
		elif [[ $line =~ "{" ]]; then
			seg1=`echo $line | cut -d '{' -f 1`
			seg2=`echo $line | cut -d '{' -f 2`
			nodename=`sttop`"_${seg1}_${seg2}"
			local i=0
			while true
			do
				if [ -f $nodename ]; then
					let i++
				else
					nodename="${nodename}_${i}"
					echo $seg2 >> $nodename
					break
				fi
			done
			echo `sttop`":${seg1}->${nodename}:${seg2}" >> $nodep 
			stpush $nodename
		elif [ ${line:0:1} = '}' ]; then
			stpop
			nodename=`sttop`
		else
			if [ "x$nodename" = "x" ]; then
				error "node is empty now"
			else
				echo $line >> $nodename
			fi
		fi
	done < $file
}


###########################################################################
# wirte node dot file
# node1,node2,node3,...,.nodepoint
###########################################################################
function file2node()
{
	if [ "x$1" = "x" ]; then
		return
	fi
	if [ ! -f $1 ]; then
		error "no sudh file: $1"
	fi

	local nodename="$1"
	local first=1
	local ret
	local llabel
	while read line
	do
		if [[ $line =~ '(' ]]; then
			llabel=''
		else
			llabel=$line
		fi

		if [ $first -eq 1 ]; then
			ret="${nodename} [label=\"<${llabel}>${line}"
			first=0
		else
			ret="${ret}|<${llabel}>${line}"
		fi
	done < $nodename
	ret="${ret}\"]"
	echo $ret
}

################################################
# dot file:
# digraph xxx {
#    ...
# }
################################################
function file_node2dot()
{
	if [ "x$1" = "x" ]; then
		return
	fi
	if [ ! -d "$1" ]; then
		error "no such directory: $1"
	fi
	if [ ! -f "${1}/$NODEPOINT" ]; then
		error "no such file: ${1}/$NODEPOINT"
	fi

	local CHROOT="$1"
	local OLDROOT=`pwd`
	local DOTFILE="${OLDROOT}/${FILE}.dot"

	rm -f $DOTFILE
	echo "digraph ${OFILE} {" >> $DOTFILE
	echo "	node [shape=record];" >> $DOTFILE
	echo "	rankdir=LR;" >> $DOTFILE

	cd $CHROOT
	local file
	for file in `ls $PREDIR`
	do
		echo "	"`file2node ${file}`";" >> ${DOTFILE}
	done
	cd $OLDROOT

	local line
	while read line
	do
		echo "	""$line"";" >> ${DOTFILE}
	done < "${CHROOT}/${NODEPOINT}"

	echo "}" >> ${DOTFILE}
}


############
# options
############
if [ "x$1" = "x" ]; then
	echo "<Usage>"
	echo "    $0 <file>"
	exit
fi

ROOT=`pwd`
TMPDIR=`pwd`/.tmp
rm -rf $TMPDIR > /dev/null 2>&1
mkdir -p $TMPDIR > /dev/null 2>&1
cp -f $1 "${TMPDIR}/.$1"
FILE="$1"
TMPFILE=".$1"

cd $TMPDIR

file_check $TMPFILE
file_trim $TMPFILE
file_trim2format1 $TMPFILE
file_format12format2 $TMPFILE
file_format22node $TMPFILE

cd $ROOT

file_node2dot $TMPDIR

which dot > /dev/null 2>&1
if [ $? -ne 0 ]; then
	error "no dot command"
fi
dot -Tpng -o "${FILE}.png" "${FILE}.dot"

