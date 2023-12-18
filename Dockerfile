FROM docker.io/geonode/geonode-base:latest-ubuntu-22.04
LABEL Name="Update geonode-base for the Inteligeo project."
LABEL Version="0.0.1"

# update the OS
RUN apt-get update -qq && apt-get upgrade -y -qq && apt-get clean -qq

# Install "geonode-contribs" apps.
# TODO: remove this part as soon as we don't need LDAP anymore.
WORKDIR /usr/src
RUN git clone --depth=1 https://github.com/GeoNode/geonode-contribs.git -b master
WORKDIR /usr/src/geonode-contribs/ldap
RUN pip install -q --upgrade -e .
WORKDIR /usr/src

# install geonode package and requirements
RUN pip install -q GeoNode==4.1.3.post1

# Update GDAL (3.4.1 has two CVEs as of 2023-12-17)
# Adding deb entry to /etc/apt/sources.list.d/ubuntugis-unstable.list
RUN echo "deb [signed-by=/usr/share/keyrings/ubuntugis.gpg] https://ppa.launchpadcontent.net/ubuntugis/ubuntugis-unstable/ubuntu/ jammy main" > /etc/apt/sources.list.d/ubuntugis-unstable.list
# Adding key to /usr/share/keyrings/ubuntugis.gpg with fingerprint 6B827C12C2D425E227EDCA75089EBE08314DF160
RUN curl 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x6B827C12C2D425E227EDCA75089EBE08314DF160' | gpg --dearmor > /usr/share/keyrings/ubuntugis.gpg
# Update the OS and add missing memcached package.
RUN apt update -qq\
 && apt upgrade -y\
 && apt-get install -y -qq memcached\
 && apt autoremove --purge -y -qq\
 && apt clean -qq

# Patch the python environment to fix open CVEs:
RUN pip install -q --upgrade pip
RUN pip install -q cryptography==41.0.6\
 django==3.2.23\
 flower==1.2.0\
 pillow==10.1.0\
 python-ldap==3.4.0\
 twisted==23.10.0rc1\
 urllib3==1.26.18\
 uwsgi==2.0.22\
 wheel==0.38.1\
 pyopenssl==23.3.0\
 GDAL==$(gdal-config --version)

# Patch geonode's version of avatar to use LANCZOS instead of ANTIALIAS, which does not exist for Pillow 10.0 onwards.
RUN sed -i 's/RESIZE_METHOD = Image.ANTIALIAS/RESIZE_METHOD = Image.LANCZOS/g' /usr/local/lib/python3.10/dist-packages/avatar/conf.py

#check if pygdal is correctly installed. Break compilation if it is not.
RUN python -c "from osgeo import gdal; print(gdal.__version__)" | grep $(gdal-config --version)

#clearing stuff left behind by pip:
RUN pip cache purge && rm -rf /root/.cache/pip/http*

# This image does not provide a command or entrypoint.
# It is supposed to be used to build other images.
