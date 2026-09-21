FROM docker.io/ubuntu:24.04@sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3
ARG GEONODE_VERSION=4.3.1
# geonode-importer is installed with --no-deps like GeoNode itself: it declares
# gdal<=3.4.3, whose Python bindings no longer compile against the libgdal-dev that
# the apt repositories ship (3.13 dropped the ABS() macro they use). Its two runtime
# dependencies (pdok-geopackage-validator, geonode-django-dynamic-model) are pinned in
# requirements.txt; the GDAL bindings are installed first, matching the system library
# exactly, so that no requirement pulls another gdal from PyPI.
# (1.1.x imports geonode.assets, which only exists from GeoNode 4.4 on.)
ARG IMPORTER_VERSION=1.0.10
# CVE-2023-42439: fixed in GeoNode 4.1.3.post1 (GHSA); the PYSEC-2023-176 record still lists 4.3.1 — see README, disposition table.
ARG IMAGE_VERSION=testing
LABEL Name="Customized geonode-base for the Inteligeo project."
LABEL Version="$IMAGE_VERSION"

# Add postgresql repository (not using the legacy trusted.gpg keyring).
# Add ubuntugis repository because of https://data.safetycli.com/v/74054/97c/
#  against GDAL<3.9.3. Ubuntu 24.04 ships with GDAL 3.8.4, which is vulnerable.
# Update the os and install the necessary packages
# Create a virtual environment
RUN apt-get update -qq\
 && apt-get install -y -qq curl gnupg2 unzip vim wget\
 && curl -sS "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x2ec86b48e6a9f326623cd22fff0e7bbec491c6a1" | gpg --dearmor -o /usr/share/keyrings/ubuntugis-unstable.gpg\
 && echo "deb [signed-by=/usr/share/keyrings/ubuntugis-unstable.gpg] https://ppa.launchpadcontent.net/ubuntugis/ubuntugis-unstable/ubuntu noble main" > /etc/apt/sources.list.d/ubuntugis.list\
 && curl -sS 'https://www.postgresql.org/media/keys/ACCC4CF8.asc' | gpg --dearmor > /usr/share/keyrings/pgdg.gpg\
 && echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt/ noble-pgdg main" > /etc/apt/sources.list.d/pgdg.list\
 && apt-get update -qq\
 && apt-get dist-upgrade -y -qq\
 && apt-get install -y -qq\
  build-essential debhelper devscripts\
  libffi-dev libgdal-dev libjpeg-dev\
  libldap2-dev libmemcached-dev libpq-dev\
  libsasl2-dev libxml2 libxml2-dev\
  libxslt1-dev memcached pkg-kde-tools\
  sharutils zlib1g-dev tini\
 && apt-get install -y -qq --no-install-recommends\
  cron gcc gdal-bin geoip-bin gettext\
  postgresql-client-16\
  python-is-python3 python3-all-dev python3-dev python3-pip python3-venv\
 && apt-get autoremove --purge -y -qq\
 && apt-get clean -qq\
 && rm -r /var/lib/apt/*\
 && python3 -m venv /usr/src/venv

#Removed python3-gdbm from above, which has no pip package equivalent. If any issues arise, add it back.

# activates the python virtual environment:
ENV PATH="/usr/src/venv/bin:$PATH"
ENV PS1="(venv) \\[\\e]0;\\u@\\h: \\w\\a\\]\${debian_chroot:+(\$debian_chroot)}\\u@\\h:\\w\\\$ "
ENV VIRTUAL_ENV="/usr/src/venv"
ENV VIRTUAL_ENV_PROMPT="(venv) "

# Copy the pip requirements file.
COPY requirements.txt /requirements.txt

# Install the geonode_ldap app from "geonode-contribs"
# TODO: remove this part as soon as we don't need LDAP anymore.
# Commit 68bf8bfb36678011a09ac5acd530a06f35bb6aee is "HEAD" as of 2025-12-15,
# we use that specific point in time to avoid surprise changes: it fixes
# remove_user_memberships() deleting groups.
WORKDIR /usr/src
RUN git clone https://github.com/GeoNode/geonode-contribs.git -b master
WORKDIR /usr/src/geonode-contribs/ldap
RUN git -c advice.detachedHead=false checkout 68bf8bfb36678011a09ac5acd530a06f35bb6aee && pip install -q --upgrade -e .
WORKDIR /

# Install the GDAL bindings that match the installed library (before anything that
# could pull another gdal from PyPI)
# Install GeoNode and geonode-importer without dependencies - they are installed from
# requirements.txt
# Install required packages
# Cleanup pip cache and other files left behind by pip
# Check that the GDAL bindings match the library. Make this build fail if there is a version mismatch.
#  && pip install -q django-geonode-mapstore-client=="$GEONODE_VERSION"\
RUN pip install --upgrade pip\
 && apt purge python3-cryptography python3-setuptools python3-setuptools-whl -y -qq\
 && pip install -q GDAL==$(gdal-config --version).*\
 && pip install --no-deps -q GeoNode=="$GEONODE_VERSION" geonode-importer=="$IMPORTER_VERSION"\
 && pip install -q -r /requirements.txt --upgrade\
 && pip cache purge && rm -rf /root/.cache/pip/http*\
 && python -c "from osgeo import gdal; print(gdal.__version__)" | grep $(gdal-config --version)

# Security fixes that have no released version for Django 4.2 (series ended on
# 2026-04-07 with 4.2.30; there will be no 4.2.31) and GeoNode 4.3.1. One .patch per
# CVE, applied against the installed packages: paths in the patches are "django/..."
# and "geonode/...", hence -p1 from
# site-packages. --fuzz=0 because with the default tolerance `patch` silently
# accepts hunks whose context changed. Files are numbered because 02- depends on 01-.
# Each patch header states its origin, the side-by-side reading and the test run.
# See README, "Known vulnerabilities and disposition".
COPY patches /patches
WORKDIR /usr/src/venv/lib/python3.12/site-packages
RUN for p in /patches/django/*.patch /patches/geonode/*.patch; do\
      echo "== $p" && patch -p1 --fuzz=0 --no-backup-if-mismatch < "$p" || exit 1;\
    done\
 && sh /patches/django/evidence.sh .
WORKDIR /

# This image does not provide a command or entrypoint.
# It is supposed to be used to build other images.
