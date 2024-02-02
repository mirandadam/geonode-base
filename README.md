# geonode-base

Files for building a personal version of geonode/geonode-base.

Docker Hub: [mirandadam/geonode-base](https://hub.docker.com/r/mirandadam/geonode-base).

References:

* [GeoNode dockerfiles](https://github.com/GeoNode/geonode-docker)
* Specific [dockerfile for geonode-base](https://github.com/GeoNode/geonode/tree/master/scripts/docker/base/ubuntu).
* Specific [dockerfile for geonode-project](https://github.com/GeoNode/geonode-project/blob/master/Dockerfile)
* Upstream [geonode/geonode-base](https://hub.docker.com/r/geonode/geonode-base).

## How to build

Remove any images with the same name:

```bash
podman rmi -i mirandadam/geonode-base:tagname
```

Build an image from scratch in the local foldel (.), discarding local caches (--no-cache), taging it as mirandadam/geonode-base:tagname, and squashes all the new layers to reduce size (--squash):

```bash
podman build --no-cache --squash -t mirandadam/geonode-base:tagname .
```

Make sure you have not introduced a python environment with active CVEs. If you find any CVEs with either pip-audit or safety, fix the Dockerfile to address them and rebuild the image.

```bash
# Get a shell into the image:
podman run -it --rm --entrypoint "bash" localhost/mirandadam/geonode-base:tagname
# Inside the image, install and run pip-audit:
pip install pip-audit
pip-audit
# Also install and run safety:
pip install safety
safety check
```

You can also use the [grype tool](https://github.com/anchore/grype) to test for vulnerabilities, but the messages produced are a bit overwhelming, seem to have false positives and don't ultimately provide a path to fixing most of the problems since, in the case of this image, they are related to the undelying OS. To install and run it:

```bash
# installing on ~/bin
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b ~/bin

grype mirandadam/geonode-base:tagname
```

Make sure that the recent layers were squashed. Check the two last lines of the following output to make sure that this image needs only one layer (the last one) and that the one above it is the upstream geonode/geonode-base:

```bash
podman image tree localhost/mirandadam/geonode-base:tagname
```

## How to push to Docker Hub

Pushes the image to the Docker Hub registry with credentials "user:password".

```bash
podman push --creds "user:password" mirandadam/geonode-base:tagname
```

## Repository history

After pushing the image to Docker Hub, tag the commit with the same tag as the image. Add a comment with the specific date of the build.

Example:

```bash
git tag -a "5.2.0-v1" -m "Used to build 5.2.0-v1 in 2023-02-02"
git push origin "5.2.0-v1"
```

### Todo

* implement provenance/sboms as in <https://docs.docker.com/build/ci/github-actions/attestations/#add-sbom-and-provenance-attestations-with-github-actions>, but for docker. RedHat also has [documentation](https://next.redhat.com/2022/10/27/establishing-a-secure-pipeline/) on creating a secure workflow with provenance and SBOM.
