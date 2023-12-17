FROM docker.io/geonode/geonode-base:latest-ubuntu-22.04
LABEL Name="Update geonode-base for the Inteligeo project."
LABEL Version="0.0.1"

# update the OS
RUN apt-get update && apt-get upgrade -y && apt-get clean

# Install "geonode-contribs" apps.
# TODO: remove this part as soon as we don't need LDAP anymore.
WORKDIR /usr/src
RUN git clone --depth=1 https://github.com/GeoNode/geonode-contribs.git -b master
WORKDIR /usr/src/geonode-contribs/ldap
RUN pip install --upgrade -e .

# install geonode package and requirements
RUN pip install GeoNode==4.1.3.post1

#check if pygdal is correctly installed. Break compilation if it is not.
RUN python -c "from osgeo import gdal; print(gdal.__version__)" | grep $(gdal-config --version)
#alternative installation in case above does not work.
#RUN pip install pygdal==$(gdal-config --version)

#clearing stuff left behind by pip:
RUN pip cache purge && rm -rf /root/.cache/pip/http*

# This image does not provide a command or entrypoint.
# It is supposed to be used to build other images.
