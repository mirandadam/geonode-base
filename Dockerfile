#FROM docker.io/geonode/geonode-base:latest-ubuntu-22.04@sha256:872fccedf55a0047241b27e03cc885fdb2f2674b45c6426c94f4377d4762e99f
FROM docker.io/ubuntu:noble@sha256:d35dfc2fe3ef66bcc085ca00d3152b482e6cafb23cdda1864154caf3b19094ba
LABEL Name="Customized geonode-base for the Inteligeo project."
LABEL Version="testing"

# Add postgresql repository (not using the legacy trusted.gpg keyring).
# Update the os and install the necessary packages
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

# activates the environment:
ENV PATH="/usr/src/venv/bin:$PATH"
ENV PS1="(venv) \\[\\e]0;\\u@\\h: \\w\\a\\]\${debian_chroot:+(\$debian_chroot)}\\u@\\h:\\w\\\$ "
ENV VIRTUAL_ENV="/usr/src/venv"
ENV VIRTUAL_ENV_PROMPT="(venv) "



#python3-gdal python3-gdbm python3-ldap\
#python3-lxml python3-pil python3-pip\
#python3-psycopg2\

# Install geonode package. This has to be done before installing the requirements.txt packages
#RUN pip install -q GeoNode==4.3.1
RUN pip install --no-deps GeoNode==4.3.1

# Note: GDAL 3.4.1 from geonode/geonode-base has two CVEs as of 2024-08-23 https://security.snyk.io/package/pip/GDAL/3.4.1
# Add deb entry to /etc/apt/sources.list.d/ubuntugis-unstable.list
#RUN echo "deb [signed-by=/usr/share/keyrings/ubuntugis.gpg] https://ppa.launchpadcontent.net/ubuntugis/ubuntugis-unstable/ubuntu/ jammy main" > /etc/apt/sources.list.d/ubuntugis-unstable.list
#RUN echo "deb [signed-by=/usr/share/keyrings/ubuntugis.gpg] https://ppa.launchpadcontent.net/ubuntugis/ppa/ubuntu/ jammy main" > /etc/apt/sources.list.d/ubuntugis.list
# Add key to /usr/share/keyrings/ubuntugis.gpg with fingerprint 6B827C12C2D425E227EDCA75089EBE08314DF160
#RUN curl -s -S 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x6B827C12C2D425E227EDCA75089EBE08314DF160' | gpg --dearmor > /usr/share/keyrings/ubuntugis.gpg

# Copy the pip package constraints file.
#COPY requirements.txt /requirements.txt
COPY requirements_alt3.txt /requirements.txt

# Add GDAL python dependency to the constraints file
RUN echo GDAL==$(gdal-config --version) >> /requirements_gdal.txt
# update pip
# install required packages
# specific updates are described in the constraints file
# cleanup pip cache and other files left behind by pip
# cleanup all __pycache__ directories
#RUN pip install -q --upgrade pip==24\
RUN pip install -q -r /requirements.txt --upgrade\
 && pip install -q -r /requirements_gdal.txt\
 && pip cache purge && rm -rf /root/.cache/pip/http*

# Install "geonode-contribs" apps.
# TODO: remove this part as soon as we don't need LDAP anymore.
WORKDIR /usr/src
RUN git clone --depth=1 https://github.com/GeoNode/geonode-contribs.git -b master
WORKDIR /usr/src/geonode-contribs/ldap
RUN pip install -q -r /requirements.txt --upgrade -e .

WORKDIR /

# Check if pygdal is correctly installed. Make this build fail if there is a version mismatch.
#RUN python -c "from osgeo import gdal; print(gdal.__version__)" | grep $(gdal-config --version)

# This image does not provide a command or entrypoint.
# It is supposed to be used to build other images.
