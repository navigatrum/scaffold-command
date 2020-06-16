#!/bin/sh

# `Sh` compatible, revisited version of `install-wp-tests.sh`

if [ $# -lt 3 ] && [ -n "$DB_NAME" ] || [ -n "$DB_USER" ] || [ -n "$DB_PASSWORD" ]; then
    echo "usage: $0 <db-name> <db-user> <db-pass> [db-host] [wp-version] [skip-database-creation] [skip-reinstall]"
    exit 1
fi

DB_NAME=${1-$DB_NAME}
DB_USER=${2-$DB_USER}
DB_PASS=${3-$DB_PASSWORD}
DB_HOST=${4-${DB_HOST-localhost}}
WP_VERSION=${5-${WP_VERSION-latest}}
SKIP_DB_CREATE=${6-false}
SKIP_REINSTALL=${7-true}

echo $DB_HOST;
exit 1;

if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ] || [ -z "$DB_HOST" ] || [ -z "$WP_VERSION" ]; then
    echo "usage: $0 <db-name> <db-user> <db-pass> [db-host] [wp-version] [skip-database-creation]"
    exit 1
fi;
exit 1

TMPDIR=${TMPDIR-/tmp}
TMPDIR=$(echo $TMPDIR | sed -e "s/\/$//")
WP_CORE_DIR=${WP_CORE_DIR-$TMPDIR/wordpress/}
WP_TESTS_DIR=${WP_TESTS_DIR-$TMPDIR/wordpress-tests-lib}

download() {
    if [ `which curl` ]; then
        curl --max-time 900 -s "$1" > "$2";
    elif [ `which wget` ]; then
        wget --timeout=900 -nv -O "$2" "$1"
    fi
}

install_wp() {
    echo "Downloading WordPress for Test Suite: "

    if [ -d $WP_CORE_DIR ]; then
        if  [ "$KIP_REINSTALL" = "true" ]; then
            rm -rd $WP_CORE_DIR
        else
            echo "skipping"
            return;
        fi
    fi

    mkdir -p $WP_CORE_DIR

    echo "in $WP_CORE_DIR..."

    if [ "$WP_VERSION" = 'nightly' ] || [ "$WP_VERSION" = 'trunk' ]; then
        mkdir -p $TMPDIR/wordpress-nightly
        echo "Downloading WP $WP_VERSION from nightly builds..."
        download https://wordpress.org/nightly-builds/wordpress-latest.zip  $TMPDIR/wordpress-nightly/wordpress-nightly.zip
        unzip -q $TMPDIR/wordpress-nightly/wordpress-nightly.zip -d $TMPDIR/wordpress-nightly/
        mv $TMPDIR/wordpress-nightly/wordpress/* $WP_CORE_DIR
    else
        if [ "$WP_VERSION" = 'latest' ]; then
            ARCHIVE_NAME='latest'
        elif echo "$WP_VERSION" | grep -Eq '[0-9]+\.[0-9]+'; then
            # https serves multiple offers, whereas http serves single.
            if [ echo "$WP_VERSION" | grep -Eq '[0-9]+\.[0-9]+\.[0]' ]; then
                # version x.x.0 means the first release of the major version, so strip off the .0 and download version x.x
                LATEST_VERSION=${WP_VERSION%??}
            else
                download https://api.wordpress.org/core/version-check/1.7/ $TMPDIR/wp-latest.json
                # otherwise, scan the releases and get the most up to date minor version of the major release
                VERSION_ESCAPED=`echo $WP_VERSION | sed 's/\./\\\\./g'`
                LATEST_VERSION=$(grep -o '"version":"'$VERSION_ESCAPED'[^"]*' $TMPDIR/wp-latest.json | sed 's/"version":"//' | head -1)
            fi
            if [ -z "$LATEST_VERSION" ]; then
                local ARCHIVE_NAME="wordpress-$WP_VERSION"
            else
                local ARCHIVE_NAME="wordpress-$LATEST_VERSION"
            fi
        else
            local ARCHIVE_NAME="wordpress-$WP_VERSION"
        fi
        download https://wordpress.org/${ARCHIVE_NAME}.tar.gz  $TMPDIR/wordpress.tar.gz
        tar --strip-components=1 -zxmf $TMPDIR/wordpress.tar.gz -C $WP_CORE_DIR
    fi

    download https://raw.github.com/markoheijnen/wp-mysqli/master/db.php $WP_CORE_DIR/wp-content/db.php
}

install_test_suite() {
        echo "Installing Wordpress Test Suite: ";

    if [ -d $WP_TESTS_DIR ] && [ "$SKIP_REINSTALL" = true ]; then
          rm -rd $WP_TESTS_DIR;
    fi

    if [ -d $WP_TESTS_DIR ] && [ -f wp-tests-config.php ]; then
        echo "skipping."
        return;
    fi

    # findout WP_TESTS_TAG to build the download url
    if echo "$WP_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\-(beta|RC)[0-9]+$'; then
        WP_BRANCH=${WP_VERSION%\-*}
        WP_TESTS_TAG="branches/$WP_BRANCH"
    elif echo "$WP_VERSION" | grep -Eq '^[0-9]+\.[0-9]+$'; then
        WP_TESTS_TAG="branches/$WP_VERSION"
    elif echo "$WP_VERSION" | grep -Eq '[0-9]+\.[0-9]+\.[0-9]+'; then
        if echo "$WP_VERSION" | grep -Eq '[0-9]+\.[0-9]+\.[0]'; then
            # version x.x.0 means the first release of the major version, so strip off the .0 and download version x.x
            WP_TESTS_TAG="tags/${WP_VERSION%??}"
        else
            WP_TESTS_TAG="tags/$WP_VERSION"
        fi
    elif [ "$WP_VERSION" = 'nightly' ] || [ "$WP_VERSION" = 'trunk' ]; then
        WP_TESTS_TAG="trunk"
    elif [ "$WP_VERSION" = 'latest' ]; then
        wget -nv -O $TMPDIR/wp-latest.json http://api.wordpress.org/core/version-check/1.7/
        grep '[0-9]+\.[0-9]+(\.[0-9]+)?' /$TMPDIR/wp-latest.json
        LATEST_VERSION=$(grep -o '"version":"[^"]*' /$TMPDIR/wp-latest.json | sed 's/"version":"//')
        if [ -z "$LATEST_VERSION" ]; then
            echo "Latest WordPress version could not be found"
            exit 1
        fi
        WP_TESTS_TAG="tags/$LATEST_VERSION"
    else
        echo "Invalid Wordpress version name."
        exit 1
    fi

    echo "v. $WP_TESTS_TAG.";

    # set up testing suite if it doesn't yet exist
    if [ ! -d $WP_TESTS_DIR ]; then

        # set up testing suite
        echo "Downloading WP Testsuite in $WP_TESTS_DIR..."
        mkdir -p $WP_TESTS_DIR
        svn co --quiet --trust-server-cert --non-interactive https://develop.svn.wordpress.org/${WP_TESTS_TAG}/tests/phpunit/includes/ $WP_TESTS_DIR/includes
        svn co --quiet --trust-server-cert --non-interactive https://develop.svn.wordpress.org/${WP_TESTS_TAG}/tests/phpunit/data/ $WP_TESTS_DIR/data
    fi

    if [ ! -f wp-tests-config.php ]; then

        echo "Setting up config file...";
        WP_TESTS_TAG=${WP_TESTS_TAG-wp_tests_tag}
        download https://develop.svn.wordpress.org/${WP_TESTS_TAG}/wp-tests-config-sample.php "$WP_TESTS_DIR"/wp-tests-config.php 
        # remove all forward slashes in the end
        WP_CORE_DIR=$(echo $WP_CORE_DIR | sed "s:/\+$::")

        # portable in-place argument for both GNU sed and Mac OSX sed
        if [[ $(uname -s) == 'Darwin' ]]; then
            local ioption='-i.bak'
        else
            local ioption='-i'
        fi

        sed $ioption "s:dirname( __FILE__ ) . '/src/':'$WP_CORE_DIR/':" "$WP_TESTS_DIR"/wp-tests-config.php
        sed $ioption "s/youremptytestdbnamehere/$DB_NAME/" "$WP_TESTS_DIR"/wp-tests-config.php
        sed $ioption "s/yourusernamehere/$DB_USER/" "$WP_TESTS_DIR"/wp-tests-config.php
        sed $ioption "s/yourpasswordhere/$DB_PASS/" "$WP_TESTS_DIR"/wp-tests-config.php
        sed $ioption "s|localhost|${DB_HOST}|" "$WP_TESTS_DIR"/wp-tests-config.php
    fi

}

install_test_suite
install_wp