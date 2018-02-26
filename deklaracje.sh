#!/bin/bash
# Instalacja e-deklaracji i e-pitów na Linuksie
# Wersja 0.8 09.02.2018
# Na podstawie rozwiązania http://nocnypingwin.pl/e-deklaracje-pod-linuxem-2017/
# Z wykorzystaniem https://aur.archlinux.org/cgit/aur.git/snapshot/adobe-air.tar.gz
# Skrypt nie pobiera tej paczki, tylko tworzy plik adobe-air, pozostawiłem opis autora Spider.007 / Sjon
# Zlepił w całość i pokolorował :) gunter
# Nie wszystkie funkcje adminemające, czy folder/plik istnieje, są dodane. Bo i po co.
# ---
# 2018.02.24 Dość znaczka przeróbka (by rysson)

VER='0.9'


##tymczasowy
tmppath='/tmp/tmpdek'
test -e "$tmppath" && rm -R "$tmppath"
mkdir "$tmppath"
cd "$tmppath"
admin_script="$tmppath/admin.sh"
user_script="$tmppath/user.sh"

# True if at file exists (pattern version, ?*[a-z],{a,b}...)
# fexists [-v] [TEST_FLAG] FILE_PAT [FILE_PAT]...
# where TEST_FLAG one of test or [ exist flag [bcdefgGhkLOprsSuwx], default -e (just exists),
#       another usefull: -f (regular file) -d (dir), -s (exists and size > 0), see: man test
exists()
{
	local f
	local verb='n'
	local op='-e'
	while [[ $# > 0 ]]; do
		case "$1" in
			-v) verb='y';;
			-[bcdefgGhkLOprsSuwx]) op="$1";;
			*) break;;
		esac
		shift
	done
	for f in "$@"; do
		if [ $op "$f" ]; then
			[[ $verb = y ]] && echo $f
			EXISTS="$f"
			return 0
		fi
	done
	return 1
}

# Find if element in array
# array_cointains ITEM ARRAY_ELEMS...
# E.g. array_cointains value "${table[@]}"
# See: https://stackoverflow.com/a/8574392
array_cointains()
{
	local e match="$1"
	shift
	for e; do [[ "$e" == "$match" ]] && return 0; done
	return 1
}

# Add uninque item(s). Add to array if not contains
# array_add_unique ARRAY_NAME ITEM [ITEM]...
array_add_unique()
{
	local e name="$1"
	shift
	for e; do
		eval "array_cointains \"\$e\" \"\${$name[@]}\" || $name+=(\"\$e\")"
	done
}

# Echo array (arguments) with separator
# join_by SEP ITEM [ITEM]...
# See: https://stackoverflow.com/a/17841619
join_by()
{
	local d=$1
	shift
	echo -n "$1"
	shift
	printf "%s" "${@/#/$d}"
}

# check if command exists
iscmd()
{
	command -v "$1" >/dev/null
}

# True if is dry run
isdry()
{
	[[ -n "$dry" ]]
}

# Download from Internet
# download [-o OUT_FILE] URL [URL]...
download()
{
	local outfile
	case "$1::$2" in
		-o::?*) outfile="$2"; shift 2;;
		-o?*) outfile="${1#-?}"; shift ;;
		*)
			outfile="${1%%#*}"
			outfile="${outfile%%\?*}"
			outfile="${outfile##*/}"
			[[ -z "$outfile" ]] && outfile='out'
			;;
	esac
	if iscmd wget; then
		$dry wget -O "$outfile" "$@"
	else
		$dry curl -o "$outfile" "$@"
	fi
}

##sudo/su
if iscmd sudo; then adminem='sudo sh' ; else adminem='su' ; fi
dry=

# Error & exit
error()
{
	tput setaf 1
	tput bold
	echo "$@"
	tput sgr0
	exit 1
}

# Title
title()
{
	tput sgr0
	tput bold
	echo "-------   $@   -------"
	tput sgr0
}

# Select target place
# select_target <local|system|home>
select_target()
{
	target_bin_script=
	case "$1" in
		system)
			target="/usr"
			air_sdk_path="/opt/adobe-air-sdk"
			bin_path="$target/bin"
			target_apps="$target/share/applications"
			target_script="$admin_script"
			;;
		local)
			target="/usr/local"
			air_sdk_path="$target/share/adobe-air-sdk"
			bin_path="$target/bin"
			target_apps="$target/share/applications"
			target_script="$admin_script"
			;;
		''|home)  # --- default ---
			target="$HOME/.local"
			air_sdk_path="$target/share/adobe-air-sdk"
			[[ -d "$HOME/bin" ]] && bin_path="$HOME/bin" || { bin_path="/usr/local/bin"; target_bin_script="$admin_script"; }
			target_apps="$target/share/applications"
			target_script="$user_script"
			;;
		gunter)
			target="$HOME/adobe-air-sdk"
			air_sdk_path="$HOME/adobe-air-sdk"
			bin_path="/usr/bin"
			target_apps="$HOME/.local/share/applications"
			target_script="$user_script"
			;;
		*)
			error "Unknow target"
			;;
	esac
	[[ -z "$target_bin_script" ]] && target_bin_script="$target_script"
}

# Install AIR dependences (as i386 architecture, libs, etc...)
instlal_air_deps_apt()
{
	# If no i386 architecture, add it
	{ (dpkg --print-architecture; dpkg --print-foreign-architectures) | grep -qsw 'i386'; } || echo "dpkg --add-architecture i386; apt-get update" >> "$admin_script"

	# Update packages (32-bit libs mostly) if not installed
	local packs=(libgtk2.0-0:i386 libstdc++6:i386 libxml2:i386 libxslt1.1:i386 libcanberra-gtk-module:i386)
	packs+=(gtk2-engines-murrine:i386 libqt4-qt3support:i386 libgnome-keyring0:i386 libnss-mdns:i386)
	packs+=(libnss3:i386)
	if dpkg -l "${packs[@]}" 2>&1 | sed '/^Desired=/,/^+++/d' | grep -sqv '^i'; then
		# Found at least one non-installed package, add install step
		echo "apt-get install -y ${packs[@]}" >> "$admin_script"
	fi
	for lib in libgnome-keyring.so.0 libgnome-keyring.so.0.2.0; do
		[[ -e /usr/lib/$lib ]] || echo "ln -s /usr/lib/i386-linux-gnu/$lib /usr/lib/" >> "$admin_script"
	done
}

# Install AIR dependences (as i386 architecture, libs, etc...)
instlal_air_deps_fedora()
{
	echo dnf upgrade nss libgnome-keyring libxslt -y >> "$admin_script"
	echo dnf install libgnome-keyring.i686 nss.i686 rpm-build libxslt.i686 -y >> "$admin_script"
}

# Install AIR dependences (as i386 architecture, libs, etc...)
instlal_air_deps_suse()
{
	local packs=(libxslt1-32bit libgnome-keyring0-32bit mozilla-nss-32bit libstdc++6-32bit)
	packs+=(libgtk-2_0-0-32bit libgthread-2_0-0-32bit)
	echo zypper -n install ${packs[@]} >> "$admin_script"
}

# Install AIR dependences (as i386 architecture, libs, etc...)
instlal_air_deps()
{
	case "$dist" in
		fedora:*)  instlal_air_deps_fedora ;;
		suse:*)    instlal_air_deps_suse ;;
		*:apt)     instlal_air_deps_apt ;;
	esac
}

# Install AdobeReader
install_adobre_reader()
{
	case "$dist" in
		*:apt)
		download ftp.adobe.com/pub/adobe/reader/unix/9.x/9.5.5/enu/AdbeRdr9.5.5-1_i386linux_enu.deb
			echo dpkg -i AdbeRdr9.5.5-1_i386linux_enu.deb >> "$admin_script"
			echo apt-get install -f -y >> "$admin_script"
			;;

		fedora:rpm:dnf)
			download ftp.adobe.com/pub/adobe/reader/unix/9.x/9.5.5/enu/AdbeRdr9.5.5-1_i486linux_enu.rpm
			echo dnf install -y AdbeRdr9.5.5-1_i486linux_enu.rpm >> "$admin_script"
			echo dnf install -y libcanberra-gtk2.i686 adwaita-gtk2-theme.i686 PackageKit-gtk3-module.i686 >> "$admin_script"
			;;

		*:rpm:*)
			download ftp.adobe.com/pub/adobe/reader/unix/9.x/9.5.5/enu/AdbeRdr9.5.5-1_i486linux_enu.rpm
			echo dnf upgrade nss libgnome-keyring libxslt -y >> "$admin_script"
			echo dnf install  AdbeRdr9.5.5-1_i486linux_enu.rpm -y >> "$admin_script"
			echo dnf install libgnome-keyring.i686 nss.i686 rpm-build libxslt.i686 -y >> "$admin_script"
			;;
	esac
}

# Create AIR luncher
create_air_luncher()
{
	download http://airdownload.adobe.com/air/lin/download/2.6/AdobeAIRSDK.tbz2
	echo "mkdir -p ${air_sdk_path}/adobe-air && tar xjf AdobeAIRSDK.tbz2 -C ${air_sdk_path}" >> "$target_script"
	echo "cp adobe-air.sh ${air_sdk_path}/adobe-air/adobe-air" >> "$target_script"

	cat > adobe-air.sh << EOF
#!/bin/bash
# Simple Adobe Air SDK wrapper script to use it as a simple AIR application launcher
# By Spider.007 / Sjon

if [[ -z "\$1" ]]; then
	echo "Please supply an .air application as first argument"
	exit 1
fi

tmpdir=\$(mktemp -d /tmp/adobeair.XXXXXXXXXX)

echo "adobe-air: Extracting application to directory: \$tmpdir"
mkdir -p \$tmpdir
unzip -q \$1 -d \$tmpdir || exit 1

echo "adobe-air: Attempting to start application"
${air_sdk_path}/bin/adl -nodebug \$tmpdir/META-INF/AIR/application.xml \$tmpdir

echo "adobe-air: Cleaning up temporary directory"
rm -Rf \$tmpdir && echo "adobe-air: Done"
EOF
	chmod +x adobe-air.sh
}

# Create luncher
# create_luncher_script NAME URL ICON [TITLE]
install_luncher_script()
{
	local name="$1"
	local url="$2"
	local pack="${url##*/}"
	local icon="$3"
	local air_script="$2"
	local title="${4:-$name}"

	download -o "$pack" "$url"  || $dry rm -f "$pack"
	isdry \
		&& $dry unzip -p "$pack" "$icon" \> "${name}.png" \
		|| $dry unzip -p "$pack" "$icon" > "${name}.png"

	cat > "$name" <<EOF
#!/bin/sh
# Launching $title
${air_sdk_path}/adobe-air/adobe-air  ${air_sdk_path}/$name/$pack
EOF
	chmod +x "$name"

	cat > "$name.desktop" << EOF
[Desktop Entry]
Name=$title
Comment=$title
Type=Application
Terminal=false
Categories=Office
Exec=${air_sdk_path}/adobe-air/adobe-air  ${air_sdk_path}/$name/$pack
Icon=${air_sdk_path}/$name/$name.png
EOF

	echo "mkdir -p ${air_sdk_path}/${name} && cp $pack ${air_sdk_path}/$name/$pack" >> "$target_script"
	echo "cp $name.png ${air_sdk_path}/${name}/${name}.png"
	echo "mkdir -p $bin_path && cp $name $bin_path/" >> "$target_bin_script"
	echo "mkdir -p $target_apps && cp $name.desktop $target_apps/" >> "$target_script"
}

# install e-pity stuff
install_epity()
{
	install_luncher_script e-pity \
		http://download.e-pity.pl/down/setup_e-pity2017Linux.air \
		Assets/icons/pity_128_256.png
}

# install e-deklaracje stuff
install_edeklaracje()
{
	install_luncher_script e-deklaracje \
		http://www.finanse.mf.gov.pl/documents/766655/1196444/e-DeklaracjeDesktop.air \
		assets/icons/icon128.png
}

# Install base tills like wget, unzip...
install_base_tools()
{
	local packs=()
	iscmd unzip || packs+=(unzip)
	iscmd wget || iscmd curl || packs+=(wget)
	if [[ "${#packs[@]}" > 0 ]]; then
		title "Instaluję niezbędne narzędzia"
		local d p tool
		IFS=: read d p tool <<< $dist
		case "$dist" in
			*) $dry $adminem -c "$tool install -y ${packs[@]}";;
		esac
	fi
}

# Install all we need
install()
{
	# empty list -> install all
	[[ $# = 0 ]] && { install all; return; }

	# prepare tasks to do
	local packs=()
	local pack
	for pack do
		case "$pack" in
			all)           install e-deklaracje e-pity; return;;
			e-deklaracje)  array_add_unique packs instlal_air_deps create_air_luncher install_adobre_reader install_edeklaracje;;
			e-pity)        array_add_unique packs instlal_air_deps create_air_luncher install_epity;;
			*)             error 'Nieznany program do instalacji';;
		esac
	done

	install_base_tools

	# execute packages, prepare tasks to do
	local pack
	for pack in "${packs[@]}"; do
		$pack
	done

	# If there are any commands for admin execute it
	if [[ -s "$admin_script" ]]; then
		chmod +x "$admin_script"
		$dry $adminem "$admin_script"
		isdry && tput dim && sed 's/^/  /' "$admin_script" && tput sgr0
	fi

	# If there are any commands for user execute it
	if [[ -s "$user_script" ]]; then
		chmod +x "$user_script"
		$dry sh -c "$user_script"
		isdry && tput dim && sed 's/^/  /' "$user_script" && tput sgr0
	fi
}

# # Find installed packages in given target
# find_installed_packs()
# {
# 	local packs
# 	[[ -d "$air_sdk_path/e-pity" ]] && packs+=(e-pity)
# 	[[ -d "$air_sdk_path/e-deklaracje" ]] && packs+=(e-deklaracje)
# 	[[ -d '/opt/Adobe/Reader9' ]] && packs+=(adobe-reader)
# 	[[ -e "$air_sdk_path/AIR SDK Readme.txt" && -d "$air_sdk_path/adobe-air" ]] && packs+=(adobe-air)
# 	echo "${packs[@]}"
# }

# Find installed packages in given target (only main and dependences)
find_installed_packs()
{
	local packs
	declare -A packs
	[[ -d "$air_sdk_path/e-pity" ]] && { let packs[e-pity]+=1; let packs[adobe-air]+=1; }
	[[ -d "$air_sdk_path/e-deklaracje" ]] && { let packs[e-deklaracje]+=1; let packs[adobe-reader]+=1; let packs[adobe-air]+=1; }
	declare -p packs
	#[[ -d "$air_sdk_path/e-deklaracje" ]] && packs+=(e-deklaracje adobe-reader adobe-air)
	#echo "${packs[@]}"
}

# Uninstall Adobe Air
uninstall_adobre_reader()
{
	case "$dist" in
		*:apt)
			(dpkg -l adobereader-enu | grep -qs '^ii.*adobereader-enu') && \
				echo apt remove -y adobereader-enu >> "$admin_script"
			;;

		*:dnf)
			echo dnf remove -y AdobeReader_enu >> "$admin_script"
			;;

		*:rpm:*)
			echo yum remove -y AdobeReader_enu >> "$admin_script"
			;;
	esac
}

# Uninstall
uninstall()
{
	# empty list -> install all
	[[ $# = 0 ]] && { uninstall all; return; }
	array_cointains all "$@" && { uninstall e-pity e-deklaracje; return; }

	#	target="/usr"
	#	air_sdk_path="/opt/adobe-air-sdk"
	#	bin_path="$target/bin"
	#	target_apps="$target/share/applications"
	#	target_script="$admin_script"
	#error 'Deinstalacja jeszcze nie jest obsługiwana'  # XXX

	# get installed apps (with dependences)
	local packs
	eval $(find_installed_packs)
	echo -n 'Insalled: '; declare -p packs

	# uninstall dependences
	local pack
	for pack do
		if [[ ${packs[$pack]} > 0 ]]; then
			case "$pack" in
				e-deklaracje)  let packs[adobe-reader]-=1 ; let packs[adobe-air]-=1 ;;
				e-pity)        let packs[adobe-air]-=1 ;;
				*)             error 'Nieznany program do odinstalownia';;
			esac
			let packs[$pack]-=1
		fi
	done

	for pack in e-pity e-deklaracje adobe-reader adobe-air; do
		echo "Should '$pack' be kept: '${packs[$pack]}'"
		if [[ -n "${packs[$pack]}" && ${packs[$pack]} < 1 ]]; then  # should be removed
			echo "Removing '$pack'"
			case "$pack" in
				e-pity|e-deklaracje)
					echo "rm -f $bin_path/$pack" >> "$target_bin_script"
					echo "rm -r $air_sdk_path/$pack" >> "$target_script"
					;;
				adobe-reader)
					uninstall_adobre_reader
					;;
				adobe-air)
					echo "rm -r $air_sdk_path/" >> "$target_script"
					;;
			esac
		fi
	done

	# If there are any commands for admin execute it
	if [[ -s "$admin_script" ]]; then
		chmod +x "$admin_script"
		$dry $adminem "$admin_script"
		isdry && tput dim && sed 's/^/  /' "$admin_script" && tput sgr0
	fi

	# If there are any commands for user execute it
	if [[ -s "$user_script" ]]; then
		chmod +x "$user_script"
		$dry sh -c "$user_script"
		isdry && tput dim && sed 's/^/  /' "$user_script" && tput sgr0
	fi
}

# Find old installs
find_installed_targets()
{
	local installed=()
	local p
	for p in home local system gunter; do
		select_target $p
		[[ -e "$air_sdk_path/AIR SDK Readme.txt" && -d "$air_sdk_path/adobe-air" ]] && installed+=($p)
	done
	echo "${installed[@]}"
}

# detect package system
find_packagesystem()
{
	local tool tools="${@}"
	[[ ${#tools[@]} = 0 ]] && tools=(apt dnf yum zypper emerge)
	for tool in tools; do
		if iscmd $tool; then
			echo -n "$tool"
			return 0
		fi
	done
	return 1
}

# detect Linux distro
find_distro()
{
	if [[ -s /etc/os-release ]]; then
		. /etc/os-release
		dist="$ID::"
	elif [[ -s /etc/lsb-release ]]; then
		. /etc/lsb-release
		dist="$(tr A-Z a-z<<<$DISTRIB_ID)::"
	elif [[ -s /etc/debian_release ]]; then
		dist="debian:deb:apt"
	elif fexist -s /etc/{fedora,SuSE,slackware,mandrake,yellowdog}-release ]]; then
		dist="$(sed 's+^.*/\([^/]*\)-release$+\1+'<<<$EXISTS|tr A-Z a-z):rpm:"
	elif [[ -s /etc/gentoo-release ]]; then
		dist="gentoo:portage:emerge"
	else
		:
	fi
	# tuning by distro
	case "$dist" in
		debian::|ubuntu::)  dist="${dist%:}"deb:apt ;;
		fedora::|suse::|slackware::|mandrake::|yellowdog::)  dist="${dist%:}"rpm: ;;
		gentoo::)  dist="${dist%:}"portage:emerge ;;
	esac
	# tuning by package system
	case "$dist" in
		*::)         dist+=$(find_packagesystem) ;;
		*:deb:)      dist+=$(find_packagesystem apt) ;;
		*:rpm:)      dist+=$(find_packagesystem dnf zypper yum) ;;
		*:portage:)  dist+=$(find_packagesystem emerge) ;;
	esac
	# recover pakage system by found tool
	case "$dist" in
		*::apt)  dist="${dist/::/:deb:}" ;;
		*::yum|*::dnf|*::zypper)  dist="${dist/::/:rpm:}" ;;
		*::emerge)  dist="${dist/::/:portage:}" ;;
	esac
}

# Interactive menu
menu()
{
	tput setaf 3
	echo
	echo "      Instalacja e-deklaracji i e-pitów       "
	echo "     Na systemy Debian, Ubuntu, Linuxmint     "
	echo "    I wszystkie pozostałe pochodne Debiana    "
	while :; do
		local name pack tool
		IFS=: read name pack tool <<< $dist
		[[ -z "$name" ]] && case "$pack" in
			deb) name="debiano podobny" ;;
			rpm) name="redhato podobny" ;;
			*)   name="nieznany" ;;
		esac
		tput sgr0
		echo
		echo "---  Znaleziono system $(tput bold)$name$(tput sgr0), Twój wybór:  ---"
		echo
		echo " 1. Zainstaluj e-deklaracje"
		echo " 2. Zainstaluj e-pity"
		echo " 3. Wszystkie programy"
		tput dim
		echo " 4. Zmień miejsce instalacji (teraz: $(tput sgr0; echo -n $target; tput dim))"
		echo " 5. Uruchom na sucho (teraz: $(tput sgr0; isdry && echo -n "TAK" || echo -n nie; tput dim))"
		tput sgr0
		echo " 0. Jednak nie instaluję nic"
		tput sgr0
		echo
		read -p "Wpisz numer instalacji i naciśnij enter [1-5,0] " wybor
		tput sgr0
		echo

		tput setaf 2
		case "$wybor" in
			0) echo "Anulacja" ;                        break ;;
			1) echo "Instaluję e-deklaracje" ;          tput sgr0; install e-deklaracje; break ;;
			2) echo "Instaluję e-pity" ;                tput sgr0; install e-pity; break ;;
			3) echo "Instaluję e-deklaracje i e-pity" ; tput sgr0; install all break ;;
			4)
				tput sgr0;
				echo -e " 1. Katalog domowy\n 2. Lokalnie w systemie (/usr/local)\n 3. System (/usr,/opt)"
				echo " 4. Gunter (stary skrypt czyli katalog domowy jawnie, skrypty w /usr/bin)"
				read -p "Wybierz miejsce [1-4,0]: " wybor
				echo
				tput setaf 2
				case "$wybor" in
					1) select_target home ;   echo "Wybrano $target" ;;
					2) select_target local ;  echo "Wybrano $target" ;;
					3) select_target system ; echo "Wybrano $target" ;;
					4) select_target gunter ; echo "Wybrano $target" ;;
					*) echo "Nie zmieniono miejsca" ;;
				esac ;;
			5) isdry && { dry=; echo "Instalacja prawdziwa"; } || { dry='echo'; echo "Przebieg na sucho"; } ;;
			*) echo; tput setaf 1; tput bold; echo "źle wybrałeś" ; tput sgr0 ; tput rc ;;
		esac
	done
	tput sgr0
}

# Print usage nad exit
usage()
{
	cat << EOF
${0##*/} [OPTIONS] COMMAND [PROG]...

Gdzie COMMAND:
  menu        - interaktuwne menu (domyślnie)
  install     - instalacja programów PROG...
  uninstall   - instalacja programów PROG...

Gdzoe PROG:
  e-deklaracje
  e-pity

Gdzie OPTIONS:
  --dry-run            - sychy przebieg (bez instalacji)
  --help               - ten komunikat pomocy
  -t, --target=TARGET  - miejsce instalacji (TARGET: home, local, system, gunter)

EOF
	exit 0
}

# Default options
target=''
debug=''
todo='menu'

# Parse arguments
parseoptions='y'
while [[ $# > 0 ]]; do
	opt="$1"
	arg=
	optarg=
	if [[ "$parseoptions" == y ]]; then
		case "$1" in
			--)     parseoptions=;;
			--*=*)  opt="${1%%=*}"; arg="${1#*=}"; optarg="$arg";;
			--*)    opt="${1}"; arg="${2}";;
			-??*)   opt="${1:0:2}"; arg="${1#-?}"; optarg="$arg";;
			-*)     opt="${1}"; arg="${2}";;
		esac
	fi
	echo "ARGS: []='$1' opt='$opt', arg='$arg', optarg='$optarg'"
	case "$opt" in
		-t|--target)      target="$arg"; shift ;;
		--debug)          debug="${optarg:-1}" ;;
		--dry-run)        dry='echo';;
		--help)           usage;;
		--version|--ver)  echo "$VER"; exit 0;;
		-*)  echo "Uknown option '$opt'"; exit 1;;
		menu|install|uninstall|list)  todo="$1"; shift; break;;
		*) error "Nieznane polecenie";;
	esac
	shift
done

if [[ -n "$debug" ]]; then
	set -x
fi

find_distro
installed=($(find_installed_targets))
print_targets()
{
	[[ ${#installed[@]} > 0 ]] && { local IFS=','; echo "Wykryto intalację w" $(join_by ', ' "${installed[@]}"); }
	[[ ${#installed[@]} = 1 && -z "$taget" ]] && target="${installed[0]}" && echo "Miejsce instalacji $target"
}
print_targets
select_target "$target"

case "$todo" in
	menu)       menu;;
	install)    install "$@";;
	uninstall)  uninstall "$@";;
	list)       echo -e 'Progrmay:\n  e-deklaracje\n  e-pity';;
esac

##clear
cd /tmp
rm -R "$tmppath"
