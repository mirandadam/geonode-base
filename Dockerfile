#FROM docker.io/geonode/geonode-base:latest-ubuntu-22.04@sha256:872fccedf55a0047241b27e03cc885fdb2f2674b45c6426c94f4377d4762e99f
FROM docker.io/ubuntu:24.04@sha256:d35dfc2fe3ef66bcc085ca00d3152b482e6cafb23cdda1864154caf3b19094ba
LABEL Name="Customized geonode-base for the Inteligeo project."
LABEL Version="5.4.0"

# Add postgresql repository (not using the legacy trusted.gpg keyring).
# Update the os and install the necessary packages
# Create a virtual environment
RUN apt-get update -qq\
 && apt-get install -y -qq curl gnupg2 unzip vim wget\
 && echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt/ noble-pgdg main" > /etc/apt/sources.list.d/pgdg.list\
 && curl -s -S 'https://www.postgresql.org/media/keys/ACCC4CF8.asc' | gpg --dearmor > /usr/share/keyrings/pgdg.gpg\
 && apt-get update -qq\
 && apt-get dist-upgrade -y -qq\
 && apt-get install -y -qq\
  build-essential debhelper devscripts\
  libffi-dev libgdal-dev libjpeg-dev\
  libldap2-dev libmemcached-dev libpq-dev\
  libsasl2-dev libxml2 libxml2-dev\
  libxslt1-dev memcached pkg-kde-tools\
  sharutils zlib1g-dev\
 && apt-get install -y -qq --no-install-recommends\
  cron gcc gdal-bin geoip-bin gettext\
  postgresql-client-15\
  python-is-python3 python3-all-dev python3-dev python3-pip python3-venv\
 && apt-get autoremove --purge -y -qq\
 && apt-get clean -qq\
 && rm -r /var/lib/apt/*\
 && python3 -m venv /usr/src/venv

#Removed python3-gdbm from above, which has no pip package equivalent. If any issues arise, add it back.

# activates the environment:
ENV PATH="/usr/src/venv/bin:$PATH"
ENV PS1="(venv) \\[\\e]0;\\u@\\h: \\w\\a\\]\${debian_chroot:+(\$debian_chroot)}\\u@\\h:\\w\\\$ "
ENV VIRTUAL_ENV="/usr/src/venv"
ENV VIRTUAL_ENV_PROMPT="(venv) "

# Copy the pip requirements file.
COPY requirements.txt /requirements.txt

# Install the geonode_ldap app from "geonode-contribs"
# TODO: remove this part as soon as we don't need LDAP anymore.
# commit 5da1051debdd88c319f3e4fce046c25e0956beb7 is "HEAD" as of 2024-10-28
WORKDIR /usr/src
RUN git clone https://github.com/GeoNode/geonode-contribs.git -b master
WORKDIR /usr/src/geonode-contribs/ldap
RUN git -c advice.detachedHead=false checkout 5da1051debdd88c319f3e4fce046c25e0956beb7 && pip install -q --upgrade -e .
WORKDIR /

# Install GeoNode without dependencies
# Install required packages
# Install specific required pygdal version to match the installed binaries
# Cleanup pip cache and other files left behind by pip
# Install geonode package with no dependencies - they will be installed manually 
RUN pip install --upgrade pip\
 && apt purge python3-cryptography python3-setuptools python3-setuptools-whl -y -qq\
 && pip install -q django-geonode-mapstore-client==4.3.1\
 && pip install --no-deps -q GeoNode==4.3.1\
 && pip install -q -r /requirements.txt --upgrade\
 && pip install -q GDAL==$(gdal-config --version).*\
 && pip cache purge && rm -rf /root/.cache/pip/http*

# Check if pygdal/GDAL is correctly installed. Make this build fail if there is a version mismatch.
RUN python -c "from osgeo import gdal; print(gdal.__version__)" | grep $(gdal-config --version)

# This image does not provide a command or entrypoint.
# It is supposed to be used to build other images.
