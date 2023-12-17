# geonode-base

Files for building a personal version of geonode/geonode-base. Docker Hub registry: [mirandadam/geonode-base](https://hub.docker.com/r/mirandadam/geonode-base).

Original repositories for the Dockerfiles are [here](https://github.com/GeoNode/geonode-docker), but the specific dockerfile for geonode-base is [here](https://github.com/GeoNode/geonode/tree/master/scripts/docker/base/ubuntu), original Docker Hub registry is [here](https://hub.docker.com/r/geonode/geonode-base).

## How to build

Builds an image from scratch, discarding local caches (--no-cache), tags it as mirandadam/geonode-base:5.2.x, and squashes all the new layers to reduce size (--squash):

```bash
podman rmi mirandadam/geonode-base:5.2.x
podman build --no-cache --squash -t mirandadam/geonode-base:5.2.x .
```

## How to push to Docker Hub

Pushes the image to the Docker Hub registry with credentials "user:password".

```bash
podman push --creds "user:password" mirandadam/geonode-base:tagname
```
