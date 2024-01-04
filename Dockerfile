FROM docker.io/geonode/geonode-base:latest-ubuntu-22.04
LABEL Name="Update geonode-base for the Inteligeo project."
LABEL Version="0.0.1"

# Copy the pip package constraints file.
COPY requirements.txt /requirements.txt

# update the OS
RUN apt-get update -qq && apt-get upgrade -y -qq && apt-get clean -qq

# Update GDAL (3.4.1 has two CVEs as of 2023-12-17)
# Adding deb entry to /etc/apt/sources.list.d/ubuntugis-unstable.list
RUN echo "deb [signed-by=/usr/share/keyrings/ubuntugis.gpg] https://ppa.launchpadcontent.net/ubuntugis/ubuntugis-unstable/ubuntu/ jammy main" > /etc/apt/sources.list.d/ubuntugis-unstable.list
# Adding key to /usr/share/keyrings/ubuntugis.gpg with fingerprint 6B827C12C2D425E227EDCA75089EBE08314DF160
RUN curl -s -S 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x6B827C12C2D425E227EDCA75089EBE08314DF160' | gpg --dearmor > /usr/share/keyrings/ubuntugis.gpg
# Update the OS and add missing memcached package.
RUN apt-get update -qq\
 && apt-get upgrade -y -qq\
 && apt-get install -y -qq memcached\
 && apt-get autoremove --purge -y -qq\
 && apt-get clean -qq

# install geonode package

RUN pip install -q --root-user-action=ignore GeoNode==4.1.3.post1

# Add GDAL python dependency to the constraints file
RUN echo GDAL==$(gdal-config --version) >> /requirements.txt
# update pip
# install required packages
# specific updates are described in the constraints file
# cleanup pip cache and other files left behind by pip
# cleanup all __pycache__ directories
RUN pip install -q --root-user-action=ignore --upgrade pip==23.3.2\
 && pip install -q --root-user-action=ignore -r /requirements.txt\
 && pip cache purge && rm -rf /root/.cache/pip/http*

# Install "geonode-contribs" apps.
# TODO: remove this part as soon as we don't need LDAP anymore.
WORKDIR /usr/src
RUN git clone --depth=1 https://github.com/GeoNode/geonode-contribs.git -b master
WORKDIR /usr/src/geonode-contribs/ldap
RUN pip install -q --root-user-action=ignore -r /requirements.txt --upgrade -e .

WORKDIR /

# Patch geonode's version of avatar to use LANCZOS instead of ANTIALIAS, which does not exist for Pillow 10.0 onwards.
RUN sed -i 's/RESIZE_METHOD = Image.ANTIALIAS/RESIZE_METHOD = Image.LANCZOS/g' /usr/local/lib/python3.10/dist-packages/avatar/conf.py

#Check if pygdal is correctly installed. Make this build fail if there is a version mismatch.
RUN python -c "from osgeo import gdal; print(gdal.__version__)" | grep $(gdal-config --version)

# This image does not provide a command or entrypoint.
# It is supposed to be used to build other images.
