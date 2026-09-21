# geonode-base

Files for building a customized version of geonode/geonode-base for use with Inteligeo.

Docker Hub: [mirandadam/geonode-base](https://hub.docker.com/r/mirandadam/geonode-base).

The image is Ubuntu 24.04 (pinned by digest in the `Dockerfile`) with a Python 3.12
virtual environment in `/usr/src/venv` holding GeoNode 4.3.1, Django 4.2.30, every
package of `requirements.txt` at an exact version, `geonode-importer` 1.0.10 (installed
without its declared dependencies, see *How to update the requirements*), the
`geonode_ldap` app from `geonode-contribs` (editable install, pinned to a commit) and the
GDAL Python bindings matching the `libgdal` that the apt repositories of the `Dockerfile`
serve (3.13.2 from pgdg on 2026-09-21). It provides no entrypoint:
`inteligeo-geonode` builds on top of it. Since 5.5.4 the build also applies security
patches to the installed Django and GeoNode (`patches/`), because both have security
fixes that no release usable here carries; see *Known vulnerabilities and disposition*.

References:

* [GeoNode dockerfiles](https://github.com/GeoNode/geonode-docker)
* Specific [dockerfile for geonode-base](https://github.com/GeoNode/geonode/tree/master/scripts/docker/base/ubuntu).
* Specific [dockerfile for geonode-project](https://github.com/GeoNode/geonode-project/blob/master/Dockerfile)
* Upstream [geonode/geonode-base](https://hub.docker.com/r/geonode/geonode-base).

## How to build

Define a TAG to identify the image version. Replace `testing` with the chosen tag:

```bash
export tagname=testing
```

Remove any images with the same name:

```bash
#replace mirandadam with your own repository
podman rmi -i mirandadam/geonode-base:$tagname
```

Build an image from scratch in the local folder (.), discarding local caches (--no-cache), taging it as mirandadam/geonode-base:tagname, and squashing all the layers to reduce size (--squash):

```bash
#replace mirandadam with your own repository
podman build --no-cache --squash --build-arg=IMAGE_VERSION=$tagname -t mirandadam/geonode-base:$tagname .
```

The build fails if the GDAL bindings do not match the system library, if any hunk of a
patch in `patches/` does not apply exactly (`--fuzz=0`), or if `patches/django/evidence.sh`
finds a call into one of the unpatched Django CVEs (see *Security patches applied at build
time*). Read the output of that last step: it prints one line per patch and one per CVE.

Make sure you have not introduced a python environment with active CVEs. Run `pip-audit`
inside the image with the ignore list from *Known vulnerabilities and disposition* (every
ignored id has a row there saying why); anything it still reports is new and has to be
fixed in `requirements.txt`, patched, or added to the table with its reason:

```bash
#replace mirandadam with your own repository
# Get a shell into the image:
podman run -it --rm --entrypoint "bash" localhost/mirandadam/geonode-base:$tagname
# Inside the image, install and run pip-audit (--skip-editable: geonode_ldap is an
# editable install; the ignore list is in the disposition section below):
pip install pip-audit
pip-audit --skip-editable --ignore-vuln CVE-... --ignore-vuln CVE-...
```

You can also use the [grype tool](https://github.com/anchore/grype) to test for vulnerabilities, but the messages produced are a bit overwhelming, seem to have false positives and don't ultimately provide a path to fixing most of the problems since, in the case of this image, they are related to the undelying OS. To install and run it:

```bash
# installing on ~/bin
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b ~/bin

#replace mirandadam with your own repository
grype mirandadam/geonode-base:tagname
```

Make sure that the recent layers were squashed. Check the two last lines of the following output to make sure that this image needs only one layer (the last one) and that the one above it is an upstream image:

```bash
#replace mirandadam with your own repository
podman image tree localhost/mirandadam/geonode-base:$tagname
```

## How to push to Docker Hub

Pushes the image to the Docker Hub registry with credentials "user:password".

```bash
#replace mirandadam with your own repository
podman push --creds "user:password" mirandadam/geonode-base:$tagname
```

## Repository history

After pushing the image to Docker Hub, tag the commit with the same tag as the image. Add a comment with the specific date of the build.

Example:

```bash
git tag -a "5.5.4" -m "Used to build the image for Inteligeo 5.5.4 in 2026-09-21"
git push origin "5.5.4"
```

## How to update the requirements

Download the .whl file of GeoNode and look into its metadata (see <https://pypi.org/pypi/Geonode/json> for the link), all the required packages will be listed there. You can use that to check whether there are any new packages to include or packages that were included before and are no longer necessary.

The rule for every pin is: the latest release whose metadata accepts Django 4.2 and
Python 3.12. GeoNode 4.3.1 requires Django 4.2, whose last release is 4.2.30 (the series
ended on 2026-04-07), so `pur` is told to keep Django's major and minor version; three
packages are excluded from the bump because their pins are deliberate (see below):

```bash
$ pip install pur
$ pur --minor Django --skip httpx,django-tinymce,django-allauth -r requirements.txt
```

`pur` reads only the version numbers, so it will also raise the eight pins that are held
back on purpose, each with its reason on its own line: `django-autocomplete-light`,
`django-filter`, `django-modeltranslation`, `django-treebeard` (the next releases require
Django 5.1 or 5.2), `djangorestframework` (`dynamic-rest 2.3.0`, its last release,
refuses 3.16 and later; 3.18 also requires Django 5.2), `django-polymorphic` (4.6.0
breaks `get_real_instance()` with GeoNode's non-polymorphic manager), `pycsw` (2.6.2 caps
OWSLib below what GeoNode pins) and `setuptools` (82.0.0 removed `pkg_resources`, which
pycsw imports at startup). After running
`pur`, revert those lines unless the reason on the line has stopped being true, and check
the "special cases" block at the bottom of `requirements.txt`: Django (the maximum
supported version), `django-tinymce` (see *TinyMCE* below), `httpx` (0.28 and later break
the Inteligeo data-loading scripts), plus `flower` and `defusedxml`, which GeoNode needs
but does not declare.

`geonode-importer` is not in `requirements.txt` any more: the `Dockerfile` installs it
with `--no-deps` on the same line as GeoNode (`ARG IMPORTER_VERSION=1.0.10`), because it
declares `gdal<=3.4.3` and pip would try to build those old bindings from source against
the current `libgdal-dev` headers, which no longer compile (3.13 dropped the `ABS()` macro
they use); the bindings that match the system library are installed first, before
GeoNode and `requirements.txt`, so that no requirement (`pdok-geopackage-validator`
declares `gdal>=3.0.4`) pulls another gdal from PyPI. 1.0.10 is the last release for
GeoNode 4.3.1 (1.1.x imports `geonode.assets`, which only exists from GeoNode 4.4 on).
Because of `--no-deps`, what the importer needs besides GDAL comes from
`requirements.txt`: its metadata on PyPI (`requires_dist`) lists `setuptools>=59`,
`gdal<=3.4.3`, `pdok-geopackage-validator==0.8.5` and
`geonode-django-dynamic-model==0.4.0`, and the importer imports the last two at runtime
(`importer/handlers/common/vector.py`, `importer/handlers/gpkg/handler.py`), so both are
pinned in `requirements.txt` at exactly those versions; check that list again when
changing either file.

Then install the file into a throwaway container based on the previous image and run
`pip check`: every line it prints must start with `geonode 4.3.1` or
`geonode-importer 1.0.10` (their own `==` declarations of Django, Pillow, DRF, allauth,
tinymce and `gdal<=3.4.3`; 95 lines on 2026-09-21). Any other line is a real conflict.
Packages that changed major version should have their changelog read against the GeoNode
4.3.1 code that uses them before the image is built.

## Security patches applied at build time

The `Dockerfile` copies `patches/` into the image and, after the last `pip install`,
applies every `patches/django/*.patch` and `patches/geonode/*.patch` from
`site-packages` with `patch -p1 --fuzz=0 --no-backup-if-mismatch`. `--fuzz=0` is
deliberate: with the default tolerance `patch` accepts hunks whose context has changed,
which is how a transposed fix silently lands in the wrong place. The Django patches are
numbered because `02-` edits code that `01-` introduces.

Each patch file starts with a header stating the CVE, the severity, the origin commit or
release, what was rewritten for the target version and why it is valid there, and the
test run. That header is the reference; this README only points to it.

- `patches/django/`: four Django 5.2.x security fixes transposed to 4.2.30
  (CVE-2026-15307, CVE-2026-15830, CVE-2026-15337, CVE-2026-7666). The parts of the origin
  commits that change Django's own test suite are kept in `patches/django/tests/`, not
  applied in the image, so that the transposition can be proved by the tests the Django
  security team wrote for it: `patches/django/tests/README.md` explains how to run them
  inside the built image against a PostGIS server (`run-origin-tests.sh`).
- `patches/django/evidence.sh`: the other eleven Django CVEs fixed only in 5.2.x are not
  patched because nothing in the image reaches them, or because the vulnerable code does
  not exist in 4.2. Instead of a sentence, the build re-measures that claim: the script
  greps the whole `site-packages` for the entry point of each CVE and fails the build the
  day one appears. Its header explains each row and its exclusions, and how to run it by
  hand on the image, on the `geonode_ldap` editable install and on the Inteligeo code
  (which is not in this image).
- `patches/geonode/`: the two GeoNode SSRF fixes (CVE-2026-39922, CVE-2026-39921),
  transposed from GeoNode 5.0.3 to 4.3.1 with one deliberate change of policy, stated in
  the header: private networks are allowed, because Inteligeo runs inside them and the
  WMS servers of the intranet are the use case of remote services.

To redo the work for another Django or GeoNode release: re-diff the patches against the
new tree (the build fails on the first hunk that no longer applies), run the origin tests
again, and revisit the disposition table -- rows 10 and 11 of `evidence.sh` exist to trip
when Django reaches a series that contains the code those CVEs are about.

## Known vulnerabilities and disposition (5.5.4)

This is the only place where the disposition of each advisory is written; the
`Dockerfile`, `requirements.txt`, the patch headers and `evidence.sh` point here.
Advisory data is from OSV/PyPI as of 2026-09-21. Status vocabulary: **fixed by version**
(the installed release carries the upstream fix), **mitigated by patch** (transposed in
`patches/`), **not affected** (the reason and its evidence follow), **open** (nothing done;
the reason follows). "Evidence" names what was measured, not what was assumed.

### Django 4.2.30

Django 4.2 ended on 2026-04-07 with 4.2.30, and GeoNode 4.3.1 requires 4.2. Of the CVEs
published against 4.2.22 (the pin of the previous image, 5.4.0b, which Inteligeo used up
to 5.5.3), twenty are fixed by 4.2.30 and pip-audit no longer reports them. Fifteen more
were fixed only in 5.2.14--5.2.17 (May--August 2026); the vulnerability databases list
some of them against 4.2.30 and some not, but all fifteen are disposed here. Severity is
Django's own, from the release notes.

| CVE | Severity | Status | Evidence |
|---|---|---|---|
| CVE-2026-15307 | high | mitigated by patch `01-CVE-2026-15307.patch` (spatial lookups: `str`/`dict` values reaching `GDALRaster`; reachable through the admin filter of any model with a spatial field, and `ResourceBase.bbox_polygon` is one) | side-by-side reading in the header (after the patch `gis/db/models/fields.py` is byte-identical to 5.2.x); origin `gis_tests` run inside the built image on 2026-09-21 against the `instancia_r` PostGIS (`patches/django/tests/run-origin-tests.sh … both`): 977 tests before the test patches, 1005 after, the 28 new tests all passing and the same 7 pre-existing failures (GEOS 3.14 / GDAL 3.13 / PostGIS 3.5 / root) in both runs; on unpatched 4.2.30 the new tests fail or do not import -- detail in `patches/django/tests/README.md` |
| CVE-2026-15830 | moderate | mitigated by patch `02-CVE-2026-15830.patch` (nested `GEOMETRYCOLLECTION` crashing GEOS; `security/views.py` does `GEOSGeometry(request.body)`) | four hunks re-placed by hand for 4.2 context only, inserted lines identical to the origin (header); same run (its 20 new tests pass; on unpatched 4.2.30 the run aborts at app import because the test models use the new `max_geom_collections` keyword) |
| CVE-2026-15337 | low | mitigated by patch `03-CVE-2026-15337.patch` (`check_for_language()` DoS; the `^i18n/` route is active) | host run of 2026-09-21, Django 4.2.30 sdist, `runtests.py mail i18n`: 417 tests OK unpatched, 419 OK patched (the two new tests), and the new test does not even import on unpatched 4.2.30; confirmed inside the image on 2026-09-21 in the same run as the rows above (`i18n` in the 1005) |
| CVE-2026-7666 | low | mitigated by patch `04-CVE-2026-7666.patch` (failed STARTTLS leaving SMTP unencrypted; `EMAIL_USE_TLS` is an instance setting) | same host run: with the patched tests on unpatched 4.2.30 the three changed `mail` tests fail, with the patch all pass; confirmed inside the image on 2026-09-21 in the same run as the rows above (`mail` in the 1005) |
| CVE-2026-8404 | low | not affected: `UpdateCacheMiddleware` and `cache_page()` are not used anywhere in the image | `evidence.sh` rows 1--5, 0 hits in `site-packages` (2026-09-21) and in `inteligeo-geonode/src` and `plugins` (2026-09-21) |
| CVE-2026-35193 | low | not affected: same (page cache) | same rows |
| CVE-2026-48587 | low | not affected: `has_vary_header()` is only consulted by the cache middlewares (grep over the whole `site-packages`) | same rows |
| CVE-2026-48588 | low | not affected: same (page cache) | same rows |
| CVE-2026-6907 | low | not affected: same (page cache) | same rows |
| CVE-2026-6873 | low | not affected: nothing calls `get_signed_cookie()`/`set_signed_cookie()` | `evidence.sh` row 6, 0 hits (same dates and folders) |
| CVE-2026-53877 | low | not affected: no code builds a `GDALRaster` from bytes (the admin-filter path into it is CVE-2026-15307, patched) | `evidence.sh` row 7, 0 hits |
| CVE-2026-35192 | low | not affected: `SESSION_SAVE_EVERY_REQUEST` is never set (default `False`) and there is no page cache | `evidence.sh` row 8, 0 hits |
| CVE-2026-5766 | low | not affected: GeoNode is served through WSGI by uWSGI (`inteligeo-geonode/src/uwsgi.ini`, line 7: `module = inteligeo5.wsgi:application`); no ASGI server is installed | `evidence.sh` row 9 (handler, server package and server configuration files), 0 hits |
| CVE-2026-53878 | low | not affected: `DomainNameValidator` does not exist in Django 4.2 (added in 5.1), although the databases list 4.2 as affected | `evidence.sh` row 10 greps `django/core/validators.py`, 0 hits; trips on the day Django reaches 5.1 |
| CVE-2026-15920 | moderate | not affected: Django 4.2 renders `URLField` as plain text in the admin (links since 5.2), although the databases list 4.2 as affected | `evidence.sh` row 11 greps `django/contrib/admin/utils.py`, 0 hits; trips on 5.2 |

### GeoNode 4.3.1

| Advisory | Severity | Status | Evidence |
|---|---|---|---|
| CVE-2026-39922 (GHSA-hw9r-6m78-w6h3, PYSEC-2026-61): SSRF in the remote service form and `/proxy/` | moderate (GHSA) | mitigated by patch `CVE-2026-39922-is-safe-url.patch`: `is_safe_url()` of GeoNode 5.0.3 in `utils.py`, `services/forms.py`, `proxy/views.py` and `geoserver/views.py`, refusing loopback, link-local, multicast, reserved and unspecified addresses and **allowing private networks** (Inteligeo runs in 10.x; the WMS servers of the intranet are the use case). The advisory's "fixed in 4.4.5 / 5.0.2" does not match the tagged trees: the code appears in 5.0.3 | 22 URL cases in the header (loopback, 169.254.169.254, 0.0.0.0, `::1`, `::ffff:127.0.0.1`, `//127.0.0.1:8080/x` refused; 10.x, 192.168.x, 172.16.x, gov.br accepted); `CreateServiceForm` refuses those URLs before any probe, measured inside the image on 2026-09-21 |
| CVE-2026-39921 (PYSEC-2026-2159): SSRF through `doc_url` when building the thumbnail of a remote document | moderate (CVSS 3.1 6.3) | mitigated by patch `CVE-2026-39921-remote-thumbnail.patch`: neither the upload view nor the Celery task `create_document_thumbnail` (which the REST API and the metadata form also run) fetch `doc_url`. Visible consequence: **a document registered by link has no thumbnail**, at upload and at every regeneration (the origin, GeoNode 5.0.2, only skips it at upload) | applied on a clean copy of the installed package, 0 FAILED, `py_compile` clean (2026-09-21); acceptance in the Inteligeo pod: a document with `doc_url` on a loopback address is created without thumbnail and without a request in the GeoNode log |
| CVE-2023-42439 (GHSA-pxg5-h34r-7q8p, PYSEC-2023-176): SSRF bypass in the proxy | high (GHSA) | not affected: fixed in GeoNode 4.1.3.post1 (the GHSA range is `>= 3.2.0, < 4.1.3.post1`); the PYSEC record has no fixed version and enumerates every later release, including 4.3.1, which is why pip-audit still reports it | GHSA affected range, read on 2026-09-21 |

### Python packages

Every pinned package that had an advisory at the version of the previous image (5.4.0b,
used by Inteligeo up to 5.5.3) was raised to a release that carries the fix (checked pin
by pin against OSV on 2026-09-21; the advisories are those of the pinned version, so a
package the deployment container used to downgrade is listed under the version it
actually ran):

| Package | 5.4.0b | 5.5.4 | Advisories at the old version, all **fixed by version** |
|---|---|---|---|
| Django | 4.2.22 | 4.2.30 | 20 CVEs fixed between 4.2.24 and 4.2.30 (CVE-2025-57833, -59681, -59682, -64458, -64459, -64460, -13372, -13473, -14550, CVE-2026-1207, -1285, -1287, -1312, -25673, -25674, -33033, -33034, -3902, -4277, -4292) |
| aiohttp | 3.10.11 | 3.14.3 | 33 CVEs (CVE-2025-53643, -69223..-69230, CVE-2026-22815, -34513..-34520, -34525, -34993, -47265, -50269, -54273..-54280, -59881, -69243, -69244); last fixed in 3.14.3 |
| black | 24.8.0 | 26.5.1 | CVE-2026-31900, CVE-2026-32274 (26.3.1) |
| Brotli | 1.1.0 | 1.2.0 | CVE-2025-6176 (1.2.0) |
| cryptography | 45.0.4 | 50.0.1 | CVE-2026-26007, -34073, -39892, -69247, -69248, -69249, GHSA-537c-gmf6-5ccf (50.0.0) |
| django-allauth | 65.9.0 pinned, **0.63.6 installed** | 65.19.4 | CVE-2025-65430, CVE-2025-65431 (65.13.0), CVE-2026-27982 (65.14.1). Until 5.5.3 the two Inteligeo authentication plugins (`autenticacao-sinesp`, `autenticacao-govbr`) required `django-allauth ~= 0.47` and downgraded the container to 0.63.6, so the pin here was never what ran; since 5.5.4 they accept `>= 65, < 66` and every symbol they and GeoNode 4.3.1 use was read in the 65.19.4 source (same signatures, no new migration) |
| django-tinymce | 3.7.1 | 5.0.0 | CVE-2024-38356, CVE-2024-38357 (4.1.0); the editor itself is under *TinyMCE* below |
| httplib2 | 0.22.0 | 0.32.0 | CVE-2026-59939 (0.32.0) |
| idna | 3.10 pinned, **2.10 installed** | 3.20 | CVE-2024-3651 / PYSEC-2024-60 (3.7) and CVE-2026-45409 (3.15). The MapStore client fork of Inteligeo required `idna < 2.11` and downgraded the container to 2.10; since 5.5.4 it requires `>= 3.7` |
| jwcrypto | 1.5.6 | 1.6.1 | CVE-2026-39373 (1.5.7) |
| lxml | 5.3.0 | 6.1.3 | CVE-2026-41066 (6.1.0) |
| Mako | 1.3.5 | 1.4.1 | CVE-2026-41205, CVE-2026-44307 (1.3.12) |
| Markdown | 3.7 | 3.10.3 | CVE-2025-69534 (3.8.1) |
| mistune | 3.0.2 | 3.3.4 | 16 CVEs (CVE-2026-33079, -44708, -44896..-44899, -49851, -59922..-59930); last fixed in 3.3.0 |
| paramiko | 3.5.1 | 5.0.0 | CVE-2026-44405 (SHA-1 in `rsakey.py`; last affected 4.0.0, no longer listed at 5.0.0) |
| pillow | 10.4.0 | 12.3.0 | 17 CVEs (CVE-2026-25990, -40192, -42308, -42310, -42311, -54058, -54059, -54060, -55379, -55380, -55798, -59197..-59200, -59204, -59205); last fixed in 12.3.0. GeoNode 4.3.1 declares 10.3; thumbnails are an acceptance item of the Inteligeo release |
| protobuf | 5.28.2 | 7.36.2 | CVE-2025-4565, CVE-2026-0994 (6.33.5) |
| PyJWT | 2.10.1 | 2.14.0 | CVE-2026-32597, -48522..-48526 (2.13.0); CVE-2025-45768 (disputed, last affected 2.10.1) |
| pyOpenSSL | 25.1.0 | 26.4.0 | CVE-2026-27448, CVE-2026-27459 (26.0.0) |
| pytest | 8.3.3 | 9.1.1 | CVE-2025-71176 (9.0.3) |
| requests | 2.32.4 | 2.34.2 | CVE-2026-25645 (2.33.0) |
| sqlparse | 0.5.1 | 0.6.0 | CVE-2026-54284, -59893, -59894, -71491, -84305, GHSA-27jp-wm6q-gp25 (0.6.0) |
| Twisted | 24.7.0 | 26.4.0 | CVE-2026-42304 (26.4.0) |
| urllib3 | 2.2.3 | 2.8.0 | CVE-2025-50181, -50182, -66418, -66471, CVE-2026-21441, -44431 (2.7.0) |

Two of the eight pins held back for compatibility (see *How to update the requirements*)
carry advisories of their own:

| Package | Advisory | Severity | Status | Evidence |
|---|---|---|---|---|
| djangorestframework 3.15.2 | CVE-2026-73229 (GHSA-g47c-3xmw-q6m2): `AdminRenderer` discloses GET-protected data on a 400 response | moderate (GHSA) | not affected: `AdminRenderer` is not used; GeoNode's renderers are `JSONRenderer` and `DynamicBrowsableAPIRenderer` (`geonode/settings.py`, `REST_FRAMEWORK`) and no view sets `renderer_classes` to it | grep for `AdminRenderer` in `geonode/`, `dynamic_rest/`, `drf_spectacular/`, `rest_framework_gis/` and in the Inteligeo code, 0 hits (2026-09-21) |
| djangorestframework 3.15.2 | CVE-2026-73228 (GHSA-2m8g-3cmr-wg3w): `request.data` bypasses `DATA_UPLOAD_MAX_MEMORY_SIZE` for JSON and form bodies (availability) | moderate (GHSA) | **open**: fixed in 3.17.2, which accepts Django 4.2 but is refused by `dynamic-rest 2.3.0` (its last release, `djangorestframework < 3.16`), which GeoNode 4.3.1 uses for its REST API. The request body is bounded only by the reverse proxy in front of GeoNode (`client_max_body_size 1G` in the Inteligeo Nginx template, the limit dataset uploads need) | read on 2026-09-21; nothing measured |
| setuptools 81.0.0 | CVE-2026-59890 (GHSA-h35f-9h28-mq5c): `MANIFEST.in` exclusions bypassed by Unicode normalization when building an sdist on macOS | moderate (GHSA) | not affected: the flaw is in building source distributions (`sdist`) on APFS/HFS+; in this image setuptools only builds wheels of the pinned packages at build time, on Linux, and no sdist is produced or published. Held at 81.0.0 because 82.0.0 removed `pkg_resources`, which `pycsw 2.6.1` imports when the URLconf loads | reading of the advisory; the pin's reason is on its line in `requirements.txt` |

Packages that `requirements.txt` does not pin (transitive dependencies such as `anyio`,
`bleach`, `click`, `filelock`, `pyasn1`, `Pygments`, `PyNaCl`, `python-dotenv`,
`python-ldap`, `soupsieve`, `tornado`) are installed at their current release on each
`--no-cache` build, and nothing in the pinned set caps any of them below the releases that
fix the advisories listed against them on 2026-09-21 (reverse dependencies read in the
installed metadata). A container that upgrades an older image in place keeps the old
copies, and pip-audit reports them: rebuild instead.

### GDAL

The image installs `libgdal-dev` from the apt repositories the `Dockerfile` adds
(ubuntugis-unstable and pgdg; apt takes the highest version, 3.13.2 from pgdg on
2026-09-21, whereas ubuntugis-unstable served 3.11.4 and the 5.4.0b image had 3.10.3)
and the matching Python bindings (`pip install GDAL==$(gdal-config --version).*`). The
version is therefore whatever those repositories serve on the day of the build; the build
prints it and fails if the bindings do not match.

| Advisory | Severity | Status | Evidence |
|---|---|---|---|
| CVE-2026-49014 (GHSA-wphc-7cm7-8mf7, PYSEC-2026-193): code execution via stack overflow in the netCDF driver | high (GHSA) | fixed by version: GDAL 3.13.1 (image built on 2026-09-21 has 3.13.2 from pgdg) | OSV record; `gdal-config --version` in the built image |
| CVE-2026-8084, CVE-2026-8086, CVE-2026-8087, CVE-2026-8088, CVE-2026-8212, CVE-2026-8213 (PYSEC-2026-2153..2157, PYSEC-2026-4): memory errors in the HDF4/HDF-EOS driver | low (GHSA) to CVSS 7.8, local vector | fixed by version: GDAL 3.13.0 (same image, 3.13.2) | same |

If a later build lands on a `libgdal` below 3.13.1 (the repositories decide), these seven
rows become **open** again and their ids go back into the ignore list below.

### TinyMCE

Ten XSS advisories are published against the TinyMCE 5.10.x that `django-tinymce 3.7.1`
embedded in the previous image: CVE-2023-45818, CVE-2023-45819 (fixed 5.10.8), CVE-2023-48219
(5.10.9), CVE-2024-38356, CVE-2024-38357 (5.11.0), CVE-2024-29203 (6.8.1), CVE-2024-29881
(7.0.0), CVE-2026-47759, CVE-2026-47761, CVE-2026-47762 (7.9.3 / 8.5.1); all moderate
(GHSA) except the last three, high. All ten are **fixed by version**: the editor that
runs in Inteligeo 5.5.4 is TinyMCE 8.9.1, vendored in
`inteligeo-geonode/src/inteligeo5/static/tinymce/` (GPL-2.0), which `collectstatic`
serves in place of the 7.8.0 that `django-tinymce 5.0.0` ships inside this image
(`FileSystemFinder` runs before `AppDirectoriesFinder`). The image alone, without that
override, would serve 7.8.0, which is affected by the last three (fixed in 7.9.3).

Why the pin was held at 3.7.1 for so long, and what the real cause is (the comment in
`requirements.txt` says the same): only the Python widget of `django-tinymce` is used;
the editor JS is vendored in `inteligeo-geonode`. GeoNode's `assets.min.js`, loaded at
the end of every page, embeds its own TinyMCE 5.10.3, and every TinyMCE bundle ends with
an unconditional `window.tinymce = ...`, so the last script loaded wins: GeoNode's
`metadata_base.html` loads the `django-tinymce` script *before* `assets.min.js`, and the
editor ran the 5.10.3 core with the theme of whatever the package shipped -- any
`django-tinymce` whose JS is of another series broke the forms. The fix lives in
`inteligeo-geonode`, not here: its `templates/metadata_base.html` and
`templates/admin/base_site.html` override GeoNode's and load the vendored editor *after*
`assets.min.js`. The 5.10.3 copies that remain inside `assets.min.js` and the old
`grappelli/tinymce/` files are not instantiated by any page after that override; removing
them means recompiling GeoNode's bundle and is out of scope.

### pip-audit ignore list

pip-audit matches `--ignore-vuln` against the record id and its aliases, so the stable CVE
id is used. Each id below has a row above; ids of rows marked "fixed by version" are not
listed because pip-audit does not report them. The eight Django CVEs whose records do not
(yet) list 4.2.30 as affected are included anyway so that a database update does not turn
a disposed row into a new finding.

```bash
pip-audit --skip-editable \
  --ignore-vuln CVE-2026-15307 --ignore-vuln CVE-2026-15830 --ignore-vuln CVE-2026-15337 \
  --ignore-vuln CVE-2026-7666  --ignore-vuln CVE-2026-8404  --ignore-vuln CVE-2026-35193 \
  --ignore-vuln CVE-2026-48587 --ignore-vuln CVE-2026-48588 --ignore-vuln CVE-2026-6907 \
  --ignore-vuln CVE-2026-6873  --ignore-vuln CVE-2026-53877 --ignore-vuln CVE-2026-35192 \
  --ignore-vuln CVE-2026-5766  --ignore-vuln CVE-2026-53878 --ignore-vuln CVE-2026-15920 \
  --ignore-vuln CVE-2026-39922 --ignore-vuln CVE-2026-39921 --ignore-vuln CVE-2023-42439 \
  --ignore-vuln CVE-2026-73228 --ignore-vuln CVE-2026-73229 --ignore-vuln CVE-2026-59890
```

| Ids | Row |
|---|---|
| CVE-2026-15307, -15830, -15337, -7666 | Django, mitigated by patch |
| CVE-2026-8404, -35193, -48587, -48588, -6907, -6873, -53877, -35192, -5766, -53878, -15920 | Django, not affected (`evidence.sh`) |
| CVE-2026-39922, CVE-2026-39921 | GeoNode, mitigated by patch |
| CVE-2023-42439 | GeoNode, not affected (fixed in 4.1.3.post1) |
| CVE-2026-73229 | djangorestframework, not affected |
| CVE-2026-73228 | djangorestframework, open |
| CVE-2026-59890 | setuptools, not affected |

Measured on 2026-09-21 on a throwaway container with the final `requirements.txt`
installed over the deployment container of Inteligeo 5.5.3 (`container-common`, itself
built on the 5.4.0b base; `localhost/reqcompat:round2`, pip-audit 2.10.1): 60 findings in 15 packages; with the list above plus the seven GDAL ids (that
container still had GDAL 3.10.3), 25 ignored and the 35 left are all in the unpinned
transitive packages that the in-place upgrade did not touch (see *Python packages*).
On the built `mirandadam/geonode-base:5.5.4` image (2026-09-21, `--no-cache` build,
pip-audit 2.10.1 installed in a throwaway container -- `pip freeze` before and after that
install differs only by pip-audit's own packages -- and, as a cross-check, run from outside
on the image's `pip freeze` with `-r --no-deps --disable-pip`): without the list, 15
findings in 4 packages (django 7, geonode 4, djangorestframework 2, setuptools 2), every
one of them a row above; with the list, **zero findings, 15 ignored**. The unpinned
transitive packages no longer appear. That image contains only what this repository
installs, whereas the container of a deployment also carries `inteligeo-geonode`'s own
packages (the two authentication plugins, the MapStore client, `dependencies_fix`), which
are not disposed here.

### Todo

* implement provenance/sboms as in <https://docs.docker.com/build/ci/github-actions/attestations/#add-sbom-and-provenance-attestations-with-github-actions>, but for docker. RedHat also has [documentation](https://next.redhat.com/2022/10/27/establishing-a-secure-pipeline/) on creating a secure workflow with provenance and SBOM.
