#!/bin/bash
# this script automates installing DefectDojo using settings from config-vars
# there are some assumptions being made:
#   - you will overwrite the defaults from in config-vars to give your instance unique secrets
#   - the machine image that Defect Dojo will run on already has most dependencies installed
#   - the database should be on a separate server and should not be deleted


function ubuntu_wkhtml_install() {
	# Install wkhtmltopdf for report generation
    echo "=============================================================================="
    echo "  Installing wkhtml for PDF report generation "
    echo "=============================================================================="
    echo ""
	cd /tmp

	# case statement on Ubuntu version built against 18.04 or 16.04
	case $INSTALL_OS_VER in
	    "18.04")
        wget https://downloads.wkhtmltopdf.org/0.12/0.12.5/wkhtmltox_0.12.5-1.bionic_amd64.deb
        apt install -y ./wkhtmltox_0.12.5-1.bionic_amd64.deb
        echo ""
	    ;;
	    "16.04")
	    wget https://downloads.wkhtmltopdf.org/0.12/0.12.5/wkhtmltox_0.12.5-1.xenial_amd64.deb
	    apt install -y ./wkhtmltox_0.12.5-1.xenial_amd64.deb
        echo ""
	    ;;
	    *)
        echo "=============================================================================="
        echo "  Error: Unsupported OS version for wkthml - $INSTALL_OS_VER"
        echo "=============================================================================="
        echo ""
		echo "    Error: Unsupported OS version - $INSTALL_OS_VER"
		exit 1
		;;
	esac

	# Clean up
	cd "$DOJO_SOURCE"
    rm /tmp/wkhtmlto*
}

function urlenc() {
    # URL encode values used in the DB URL to keep certain chars from breaking things
	local STRING="${1}"
    # Run correct python version for URL encoding
    if [ "$PY" = python3 ]; then
        echo `python3 -c "import urllib.parse as ul; print(ul.quote_plus('$STRING'))"` 
    else
	    echo `python -c "import sys, urllib as ul; print ul.quote_plus('$STRING')"`
    fi
}

function test_database_access() {
        # Just try and run quit in the remote DB - verifies connectivity and creds provided work
    if mysql -fs -h "$DB_HOST" -P "$DB_PORT" -u"$DB_USER" -p"$DB_PASS" -e "quit" > /dev/null 2>&1; then
        echo "=============================================================================="
        echo "  Remote $DB_TYPE server connectivity confirmed"
        echo "=============================================================================="
        echo ""
    else
        echo "##############################################################################"
        echo "#  ERROR: Remote $DB_TYPE server connectivity failed - exiting               #"
        echo "##############################################################################"
        echo ""
        exit 1
    fi
}


function create_dojo_settings() {
	echo "=============================================================================="
    echo "  Creating dojo/settings/settings.py and .env file"
    echo "=============================================================================="
    echo ""

    # Copy settings file & env files to final location
    cp "$SOURCE_SETTINGS_FILE" "$TARGET_SETTINGS_FILE"
    cp "$ENV_SETTINGS_FILE" "$ENV_TARGET_FILE"

    # Construct DD_DATABASE_URL based on DB type - see https://github.com/kennethreitz/dj-database-url
    case $DB_TYPE in
        "SQLite")
        # sqlite:///PATH
        DD_DATABASE_URL="sqlite:///defectdojo.db"
        ;;
        "MySQL")
        # mysql://USER:PASSWORD@HOST:PORT/NAME
        SAFE_URL=$(urlenc "$DB_USER")":"$(urlenc "$DB_PASS")"@"$(urlenc "$DB_HOST")":"$(urlenc "$DB_PORT")"/"$(urlenc "$DB_NAME")
        DD_DATABASE_URL="mysql://$SAFE_URL"
        ;;
        "PostgreSQL")
        # postgres://USER:PASSWORD@HOST:PORT/NAME
        SAFE_URL=$(urlenc "$DB_USER")":"$(urlenc "$DB_PASS")"@"$(urlenc "$DB_HOST")":"$(urlenc "$DB_PORT")"/"$(urlenc "$DB_NAME")
        DD_DATABASE_URL="postgres://$SAFE_URL"
        ;;
        *)
        echo "    Error: Unsupported DB type - $DB_TYPE"
		exit 1
		;;
	esac

    # Substitute install vars for settings.py values
    sed -i -e 's%#DD_DEBUG#%'$DD_DEBUG'%' "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_DJANGO_ADMIN_ENABLED#%'$DD_DJANGO_ADMIN_ENABLED'%' "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_SECRET_KEY#%'$DD_SECRET_KEY'%' "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_CREDENTIAL_AES_256_KEY#%'$DD_CREDENTIAL_AES_256_KEY'%' "$ENV_TARGET_FILE"
    sed -i -e "s^#DD_DATABASE_URL#^$DD_DATABASE_URL^" "$ENV_TARGET_FILE"
    sed -i -e "s%#DD_ALLOWED_HOSTS#%$DD_ALLOWED_HOSTS%" "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_WHITENOISE#%'$DD_WHITENOISE'%' "$ENV_TARGET_FILE"
    # Additional Settings / Override defaults in settings.py
    sed -i -e 's%#DD_TIME_ZONE#%'$DD_TIME_ZONE'%' "$ENV_TARGET_FILE"
    sed -i -e "s%#DD_TRACK_MIGRATIONS#%$DD_TRACK_MIGRATIONS%" "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_SESSION_COOKIE_HTTPONLY#%'$DD_SESSION_COOKIE_HTTPONLY'%' "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_CSRF_COOKIE_HTTPONLY#%'$DD_CSRF_COOKIE_HTTPONLY'%' "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_SECURE_SSL_REDIRECT#%'$DD_SECURE_SSL_REDIRECT'%' "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_CSRF_COOKIE_SECURE#%'$DD_CSRF_COOKIE_SECURE'%' "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_SECURE_BROWSER_XSS_FILTER#%'$DD_SECURE_BROWSER_XSS_FILTER'%' "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_LANG#%'$DD_LANG'%' "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_WKHTMLTOPDF#%'$DD_WKHTMLTOPDF'%' "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_TEAM_NAME#%'$DD_TEAM_NAME'%' "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_ADMINS#%'$DD_ADMINS'%' "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_PORT_SCAN_CONTACT_EMAIL#%'$DD_PORT_SCAN_CONTACT_EMAIL'%' "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_PORT_SCAN_RESULT_EMAIL_FROM#%'$DD_PORT_SCAN_RESULT_EMAIL_FROM'%' "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_PORT_SCAN_EXTERNAL_UNIT_EMAIL_LIST#%'$DD_PORT_SCAN_EXTERNAL_UNIT_EMAIL_LIST'%' "$ENV_TARGET_FILE"
    sed -i -e 's%#DD_PORT_SCAN_SOURCE_IP#%'$DD_PORT_SCAN_SOURCE_IP'%' "$ENV_TARGET_FILE"
}

################# BEGIN SCRIPT

# Set the python version for the installer
PY="python3"
PIP="pip3"

# Make sure aws-standalone.bash is run from the same directory it is located in
cd ${0%/*}  # same as `cd "$(dirname "$0")"` without relying on dirname
SETUP_BASE=`pwd`
REPO_BASE=${SETUP_BASE%/*}

# Set install config values and load the 'libraries' needed for install
LIB_PATH="$SETUP_BASE/scripts/common"
. "$LIB_PATH/config-vars.sh"     # Set install configuration default values
. "$LIB_PATH/cmd-args.sh"        # Get command-line args and set config values as needed
. "$LIB_PATH/prompt.sh"          # Prompt for config values if install is interactive
. "$LIB_PATH/common-os.sh"       # Determine what OS the installer is running on
# . "$LIB_PATH/install-dojo.sh"    # Complete an install of Dojo based on previously run code

read_cmd_args

# Prompt for config values if install is interactive - the default
if [ "$PROMPT" = true ] ; then
    prompt_for_config_vals
else
    init_install_creds
fi

test_database_access

# Check for OS installer is running on and that python version is correct
# Funcions below in ./scripts/common/common-os.sh
check_install_os
check_python_version

# Remove cmdtest to prevent name collisions - see https://github.com/yarnpkg/yarn/issues/2821
apt-get remove cmdtest --yes

# Install yarn and verify GPG signature
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt update && sudo apt install yarn --yes

# TODO: consider installing wkhtml on the AMI instead? apt-get install -y wkhtmltopdf ??
ubuntu_wkhtml_install

# Install DefectDojo
echo "=============================================================================="
echo "  Installing DefectDojo Django application "
echo "=============================================================================="
echo ""

create_dojo_settings

cd $DOJO_SOURCE
$PIP install -r requirements.txt

# Install deps from package.json using yarn
yarn install

# Before running nginx, you have to collect all Django static files in the static folder
$PY manage.py collectstatic --noinput

echo "=============================================================================="
echo "  Running database migrations "
echo "=============================================================================="
echo ""

$PY manage.py makemigrations --merge --noinput
$PY manage.py makemigrations dojo
$PY manage.py migrate

echo "=============================================================================="
echo "  Creating SuperUsers "
echo "=============================================================================="
echo ""

$PY manage.py createsuperuser --noinput --username="$ADMIN_USER" --email="$ADMIN_EMAIL"
# Run the add Django superuser script based on python version
if [ "$PY" = python3 ]; then
    $SETUP_BASE/scripts/common/setup-superuser.expect "$ADMIN_USER" "$ADMIN_PASS"
else
    $SETUP_BASE/scripts/common/setup-superuser-2.expect "$ADMIN_USER" "$ADMIN_PASS"
fi