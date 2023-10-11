#!/bin/sh

# This script prepares the test environment as follows:
#     - A solc binary path is queried from the user to use for compilation
#     - A settings.cfg.sh file is created that can be source'd by the
# framework scripts to obtain the environment variables $SOLC_BINARY_PATH
# and an updated $PATH including fast-solc-js 
#
# Arguments:
#    --use-defaults        - use default values instead of interactive questions
#    --solc-path=<path>    - path to solc binary 
#    --nodejs-path=<path>  - path to directory containing npm/node to use
#
# If ./builddeps exists, dependencies will be used from it if available:
#    ./builddeps/go.tgz       - go installation package
#    ./builddeps/go-ethereum  - cloned geth repository
#    ./builddeps/solc         - solc binary

GENERATED_SETTINGS_FILE="settings.cfg.sh"

# Cleanup in case of reinstallation
# rm -rf go-ethereum
rm -rf test-env-truffle/node_modules

verify_solc_path() {
	if ! test -x "$SELECTED_COMPILER"; then
		return 1
	else
		return 0
	fi
}

verify_nodejs_path() {
	NODE_BIN_FILE_PATH_NODE=`realpath "$SELECTED_NODE_DIR/node"`	
	NODE_BIN_FILE_PATH_NPM=`realpath "$SELECTED_NODE_DIR/npm"`	
	if ! test -x "$NODE_BIN_FILE_PATH_NODE" || ! test -x "$NODE_BIN_FILE_PATH_NPM"; then
		return 1
	else
		return 0
	fi
}

while test "$#" != 0; do
	arg_part_one=`echo $1 | awk -F'=' '{print $1}'`
	arg_part_two=`echo $1 | awk -F'=' '{print $2}'`
	if test "$arg_part_one" = --use-defaults; then
		USE_DEFAULTS=yes
	elif test "$arg_part_one" = --solc-path; then
		SELECTED_COMPILER="$arg_part_two"
		if ! verify_solc_path "$SELECTED_COMPILER"; then
			echo "Error: $SELECTED_COMPILER does not appear to be an executable binary file"
			exit 1
		fi
	elif test "$arg_part_one" = --nodejs-path; then
		SELECTED_NODE_DIR="$arg_part_two"
		echo SELECTED_NODE_DIr = "$SELECTED_NODE_DIR"
		if ! verify_nodejs_path; then
			echo Error: "$SELECTED_NODE_DIR" does not contain executable node and npm binaries
			exit 1
		fi
	else
		echo Invalid argument. Available arguments:
		echo "    --use-defaults        - use default values instead of interactive questions"
		echo "    --solc-path=<path>    - path to solc binary"
		echo "    --nodejs-path=<path>  - path to directory containing npm/node to use (must be >v10)"
		exit 1
	fi
	shift
done

echo Starting test framework setup ...

echo Building soltix...
CURDIR=`pwd`

LOGDIR="$PWD/_setup-logs"
if ! test -d "$LOGDIR"; then
	mkdir "$LOGDIR"
fi
BUILDLOG="$LOGDIR"/build.log

if ! cd soltix || ! mvn install >"$BUILDLOG" 2>&1; then
	cat "$BUILDLOG"
	echo
        echo "Error: Could not build soltix. This could indicate that one of the following is missing:"
        echo "      General build tools    -   sudo apt-get install build-essential"
        echo "      Java SDK 8+            -   sudo apt-get install openjdk-8-jdk"
        echo "      Maven                  -   sudo apt-get install maven"
	echo "See also Dockerfile for dependencies installation."
        echo "See also log output in $BUILDLOG or above"
        exit 1
fi
cd "$CURDIR"

echo Building tools...
cd tools/coordinator
if ! mvn install >/dev/null 2>&1; then
	echo Error: cannot build coordination tools for cloud processing
	echo Proceeding anyway...
fi
cd "$CURDIR"

#echo Building helper tools...
#MAKELOG="$LOGDIR"/tools.log
#cd soltix/bin
#if ! make >"$MAKELOG" 2>&1; then
#	echo Build error - see log "$MAKELOG"
#	exit 1
#fi
#cd "$CURDIR" 

BUILDDEPS="$PWD/builddeps"

INSTALLED_SOLC=`whereis solc | awk '{print $2}'`

# 1. Select compiler binary - using the current solc static binary as initial suggestion
# TODO use truffle external compiler function to reference the selected binary as well
SOLC_VERSION_8="0.8.21"

USER_INPUT=""

echo The test framework needs a solc compiler binary at least for code parsing.
echo To compile and run a program, the same solc binary or solc-js can be used.
echo
echo settings.cfg will be generated. It can be used to configure the choice between
echo a solc binary and solcjs, optimization settings, and other things.
echo
echo Generated code currently always complies with 0.5 language rules and does not use
echo 0.4 language-specific constructs anymore.
echo
while test "$USER_INPUT" != y && test "$USER_INPUT" != n; do
	printf "Download static solc binary version ${SOLC_VERSION_8} now? [y]: "
	if test "$USE_DEFAULTS" != yes; then
		read USER_INPUT
	fi
	if test "$USER_INPUT" = ""; then
		USER_INPUT=y
	fi
done

if test "$USER_INPUT" = y; then
	if test -f "$BUILDDEPS"/solc; then
		echo Using solc from builddeps dir
		INSTALLED_SOLC="$BUILDDEPS"/solc
	else	
		echo Downloading default solc compiler binary $SOLC_VERSION_8 ...
		# if ! wget https://github.com/ethereum/solidity/releases/download/v${SOLC_VERSION_8}/solc-static-linux -O solc-${SOLC_VERSION_8} >/dev/null 2>&1; then
		#	  echo Error: could not download solc compiler binary
		# else
		INSTALLED_SOLC=$PWD/solc-${SOLC_VERSION_8}
		# fi
	fi
	chmod +x "$INSTALLED_SOLC"
fi

if ! test -x "$INSTALLED_SOLC"; then
	INSTALLED_SOLC=""
	echo Could not locate any installed solc binary
else
	echo Located installed solc binary at $INSTALLED_SOLC
fi

while test "$SELECTED_COMPILER" = ""; do
	printf "Please select the solc compiler binary path to use [$INSTALLED_SOLC]: "
	if test "$USE_DEFAULTS" != yes; then
		read USER_INPUT
	else
		USER_INPUT=""
	fi
	if test "$USER_INPUT" = ""; then
		if test "$INSTALLED_SOLC" = ""; then
			echo Error: You selected the default compiler, but no installed compiler has been found
			if test "$USE_DEFAULTS" = yes; then
				echo Aborting installation
				exit 1
			fi
		else
			SELECTED_COMPILER="$INSTALLED_SOLC"
		fi
	else 
		if ! verify_solc_path; then
			echo Error: "$SELECTED_COMPILER" does not appear to be an executable binary file
		else
			SELECTED_COMPILER=`realpath "$USER_INPUT"`
		fi
	fi
done


# 2. Select a node version. Try to find a default option first 
# SELECTED_NODE_DIR=/usr/local/bin
SELECTED_NODE_DIR=/home/lum7na/.nvm/versions/node/v18.18.0/bin/
if ! verify_nodejs_path; then
	SELECTED_NODE_DIR=/usr/bin
	if verify_nodejs_path; then
		DEFAULT_NODE_DIR="$SELECTED_NODE_DIR"
	fi
else
	DEFAULT_NODE_DIR="$SELECTED_NODE_DIR"
fi

SELECTED_NODE_DIR=""
while test "$SELECTED_NODE_DIR" = ""; do
	printf "Please enter the directory path containing the node and npm binaries to use [$DEFAULT_NODE_DIR]: "
	if test "$USE_DEFAULTS" != yes; then
		read USER_INPUT
	fi

	if test "$USER_INPUT" = ""; then
		# Default choice
		SELECTED_NODE_DIR="$DEFAULT_NODE_DIR"
		break
	fi

	SELECTED_NODE_DIR=`realpath "$USER_INPUT"`
	if ! verify_nodejs_path; then
		echo Error: "$USER_INPUT" does not contain executable node and npm binaries
	fi
	NODE_VERSION=`"$SELECTED_NODE_DIR"/node -v | awk -F. '{print $1}' | awk -Fv '{print $2}'`
	if test "$NODE_VERSION" -lt 10; then
		echo Error: node version too old, must be at least v10
		SELECTED_NODE_DIR=""
	fi
done

echo Installing node packages...
cd test-env-truffle 


NPMLOG="$LOGDIR"/npm-install.log
if ! "$SELECTED_NODE_DIR"/npm install >"$NPMLOG" 2>&1; then
	echo Warning: $SELECTED_NODE_DIR/npm install in ./test-env-truffle returned an error, see "$NPMLOG" for log output.
	echo          If the framework works regardless, this may be ignorable
fi

# Patch truffle for external compiler invocation
# if ! ../tools/patch-truffle.sh ./node_modules/.bin/truffle; then
# 	echo Error: Cannot patch truffle - aborting setup
# 	exit 1
# fi


# 3. Obtain geth blockchain client if desired
USER_INPUT=""
while test "$USER_INPUT" != y && test "$USER_INPUT" != n; do
	printf "Download and compile geth blockchain backend now (takes a while and requires recent golang)? [y]: " 
	if test "$USE_DEFAULTS" != yes; then
		read USER_INPUT
	fi
	if test "$USER_INPUT" = ""; then
		USER_INPUT=y
	fi
done
if test "$USER_INPUT" = y; then
	cd "$CURDIR"

	# First check local go version.
	# TODO version check?
	if test -f "$BUILDDEPS"/go.tgz; then
		GOLANG_DIR="./go"
		if ! test -d "$GOLANG_DIR"; then
			mkdir "$GOLANG_DIR"
		fi
		tar -C "$GOLANG_DIR" -xzf "$BUILDDEPS"/go.tgz 
		export PATH="`realpath $GOLANG_DIR/go/bin`:$PATH"
	elif ! which go; then
		# Only advise on installation
		echo 'Error: cannot find go binary. Binary installation in ./go on Linux'
		echo '(see also https://golang.org/doc/install#install):'
		echo 'Run ./tools/golang-setup.sh and then rerun this setup.'
		if test `uname -s` = Linux && test `uname -m` = x86_64; then # TODO macOS? 
			USER_INPUT=""
			GOLANG_DIR="./go"
			while test "$USER_INPUT" != y && test "$USER_INPUT" != n; do
				printf "Download and extract golang to '$GOLANG_DIR' directory now? [y]: "
				if test "$USE_DEFAULTS" != yes; then
					read USER_INPUT
				fi
				if test "$USER_INPUT" = ""; then
					USER_INPUT=y
				fi
			done
			if ./tools/golang-setup.sh "$GOLANG_DIR"; then
				export PATH="`realpath $GOLANG_DIR/go/bin`:$PATH"
			fi
		fi
	fi

	if ! which go; then
		echo 'Aborting geth setup due to lack of go installation'
	elif ! test -d "$BUILDDEPS"/go-ethereum && git clone https://github.com/ethereum/go-ethereum.git; then
		echo Error: Cannot git clone go-ethereum.git - aborting geth setup
	else
		if test -d "$BUILDDEPS"/go-ethereum; then
			echo Using go-ethereum from builddeps dir
			## rm -rf go-ethereum
			## cp -R "$BUILDDEPS"/go-ethereum go-ethereum
		fi

		cd go-ethereum
		# if ! ../tools/patch-geth.sh; then
		# 	echo Error: Cannot patch geth code - aborting geth setup
		# else
		go env -w  GOPROXY=https://goproxy.cn,direct
    if ! make all; then
      echo Error: make all failed - aborting geth setup
    else
      cd ..
      GETH_PATH=`realpath ./go-ethereum/build/bin/geth`
		fi
	fi
fi


cd "$CURDIR"


echo "# use solcjs in truffle (otherwise: invoke external solc binary)?"                                        >"$GENERATED_SETTINGS_FILE"
echo "export USE_SOLCJS=no"                                                                                    >>"$GENERATED_SETTINGS_FILE"
# solcjs version - auto-installed
echo "# if USE_SOLCJS=yes - solcjs version to use (auto-installed, see https://www.npmjs.com/package/solc)"    >>"$GENERATED_SETTINGS_FILE"
echo "export SOLCJS_VERSION=\"0.5.7\""                                                                         >>"$GENERATED_SETTINGS_FILE"
# solc binary - needs manual download
echo "# if USE_SOLCJS=no - absolute path of solc binary to use (see https://github.com/ethereum/solidity/releases for static Linux release binaries)" >>"$GENERATED_SETTINGS_FILE"
echo "export SOLC_BINARY_PATH=\"$SELECTED_COMPILER\""                                                          >>"$GENERATED_SETTINGS_FILE"
echo "# blockchain backend to use - ganache or geth?"                                                          >>"$GENERATED_SETTINGS_FILE"
echo "export BLOCKCHAIN_BACKEND=geth"                                                                          >>"$GENERATED_SETTINGS_FILE"
echo "# geth binary path to use if BLOCKCHAIN_BACKEND=geth"                                                    >>"$GENERATED_SETTINGS_FILE"
echo "export GETH_PATH=\"$GETH_PATH\""                                                                         >>"$GENERATED_SETTINGS_FILE"
echo "# enable optimization?  will update truffle's  'optimizer { enabled:'  setting   "                       >>"$GENERATED_SETTINGS_FILE"
echo "export USE_SOLC_OPTIMIZATION=yes"                                                                        >>"$GENERATED_SETTINGS_FILE"
echo "# if optimizing - how many runs? will update truffle's  'optimizer { runs:'  setting   "                 >>"$GENERATED_SETTINGS_FILE"
echo "export SOLC_OPTIMIZATION_RUNS=200"                                                                       >>"$GENERATED_SETTINGS_FILE"
echo "# if optimizing - use experimental new yul optimizer?"                                                   >>"$GENERATED_SETTINGS_FILE"
echo "export SOLC_USE_YUL_OPTIMIZER=no"                                                                        >>"$GENERATED_SETTINGS_FILE"
echo "# avoid generating exponentiation (**) code - workaround for ganache-cli crashes and old solc versions"  >>"$GENERATED_SETTINGS_FILE"
echo "export CODEGEN_AVOID_EXP_OPERATOR=yes"                                                                   >>"$GENERATED_SETTINGS_FILE"                                           
echo "# avoid generating shift (<<, >>) code - workaround for ganache-cli crashes"                             >>"$GENERATED_SETTINGS_FILE"
echo "export CODEGEN_AVOID_SHIFT_OPERATORS=yes"                                                                >>"$GENERATED_SETTINGS_FILE"                                           
echo "# use experimental version 2 ABI encoder? Needed for constructs like structure arguments, but 20x slower">>"$GENERATED_SETTINGS_FILE"
echo "export CODEGEN_USE_ABI_ENCODER_V2=no"                                                                    >>"$GENERATED_SETTINGS_FILE"
echo "# generate function arguments of struct type? Requires CODEGEN_USE_ABI_ENCODER_V2=yes which may be undesirable due to performance" >>"$GENERATED_SETTINGS_FILE"
echo "export CODEGEN_ALLOW_STRUCTS_IN_FUNCTION_ABI=no"                                                        >>"$GENERATED_SETTINGS_FILE"
echo                                                                                                           >>"$GENERATED_SETTINGS_FILE"
echo "export NODEDIR=\"${SELECTED_NODE_DIR}\""                                                                 >>"$GENERATED_SETTINGS_FILE"
echo "export PATH=\"${PWD}/soltix/bin:${PWD}/test-env-truffle/bin:${PWD}/test-env-truffle/tools:${PWD}/test-env-truffle/tools/external-solc:${PWD}/tools:${PWD}/tools/coordinator/bin:$PATH\""         >>"$GENERATED_SETTINGS_FILE"


. ./settings.cfg.sh  # "$GENERATED_SETTINGS_FILE"

echo Testing whether the framework works...
# Run one test contract
TESTLOG="$LOGDIR"/test.log
if ! cd test-env-truffle || ! echo 'contract c { uint x = 123; function f() public { return ; } }' >x.sol || ! run-one-test.sh x.sol 1 >"$TESTLOG" 2>&1; then
	echo - Error: Framework does not appear to work correctly, see log "$TESTLOG"
	exit 1
else
	echo - Test OK - see log "$TESTLOG"
fi

cd "$CURDIR"


echo "All done - settings (accessible in node via process.env.<name>):"
echo
cat "$GENERATED_SETTINGS_FILE"
echo

echo "You can change these in settings.cfg.sh"

exit 0
