FROM docker.io/geonode/geonode-base:latest-ubuntu-22.04
LABEL Name="Update geonode-base for the Inteligeo project."
LABEL Version="0.0.1"

# update the OS
RUN apt-get update && apt-get upgrade -y && apt-get clean

# Install "geonode-contribs" apps.
# TODO: remove this part as soon as we don't need LDAP anymore.
WORKDIR /usr/src
RUN git clone https://github.com/GeoNode/geonode-contribs.git -b master
WORKDIR /usr/src/geonode-contribs/ldap
RUN pip install --upgrade  -e .

# install geonode requirements
RUN pip install pip --upgrade \
    && pip install pygdal==$(gdal-config --version).*\
    && pip install flower==0.9.4 \
    && pip install pylibmc \
    && pip install sherlock \
    && pip install GeoNode==4.1.3.post1

# This image does not provide a command or entrypoint.
# It is supposed to be used to build other images.
