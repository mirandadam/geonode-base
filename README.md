# geonode-base

Files for building a personal version of geonode/geonode-base.

Docker Hub: [mirandadam/geonode-base](https://hub.docker.com/r/mirandadam/geonode-base).

Original repositories for the geonode dockerfiles are [here](https://github.com/GeoNode/geonode-docker), but the specific dockerfile for geonode-base is [here](https://github.com/GeoNode/geonode/tree/master/scripts/docker/base/ubuntu).

Upstream Docker Hub registry is [geonode/geonode-base](https://hub.docker.com/r/geonode/geonode-base).

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

### Troubleshooting

If you have the following error message with `....` replaced by some garbled garbage:

```text
Error: crun: realpath `....` failed: No such file or directory: OCI runtime attempted to invoke a command that was not found
```

This means that you probably installed the latest podman from the Kubic repositories as per [podman official instructions for Ubntu](https://podman.io/docs/installation#ubuntu) around december 2023. See <https://github.com/containers/podman/issues/21024> for a discussion on a conmon regression that caused this.

Stopgap solution:

```bash
#https://packages.ubuntu.com/noble/amd64/conmon/download
wget http://mirrors.kernel.org/ubuntu/pool/universe/c/conmon/conmon_2.1.6+ds1-1_amd64.deb
sudo dpkg -i conmon_2.1.6+ds1-1_amd64.deb
```

The specific defective package I encountrered shows on `apt show podman -a` as:

```text
Package: conmon
Version: 2:2.1.9-0ubuntu22.04+obs17.1
Priority: optional
Maintainer: Podman Debbuild Maintainers <https://github.com/orgs/containers/teams/podman-debbuild-maintainers>
Installed-Size: 795 kB
Depends: libglib2.0-0,libseccomp2,libsystemd0,libc6,libpcre3,liblzma5,libzstd1,liblz4-1,libcap2,libgcrypt20,libgpg-error0
Homepage: https://github.com/containers/conmon
Download-Size: 121 kB
APT-Manual-Installed: no
APT-Sources: https://download.opensuse.org/repositories/devel:kubic:libcontainers:unstable/xUbuntu_22.04  Packages
Description: OCI container runtime monitor
 OCI container runtime monitor.
```

### Todo

- implement provenance/sboms as in <https://docs.docker.com/build/ci/github-actions/attestations/#add-sbom-and-provenance-attestations-with-github-actions>, but for docker. RedHat also has [documentation](https://next.redhat.com/2022/10/27/establishing-a-secure-pipeline/) on creating a secure workflow with provenance and SBOM.
