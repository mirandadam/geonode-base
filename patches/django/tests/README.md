# Origin regression tests for the transposed Django patches

The four `.patch` files in the parent folder carry Django 5.2.x security fixes
transposed to Django 4.2.30 (the 4.2 series ended on 2026-04-07; there is no
4.2.31). Each origin commit also changed Django's own test suite; those parts
are kept here, one `CVE-*-tests.patch` per CVE, re-diffed against the `tests/`
tree of the `django-4.2.30` sdist. They are not applied in the image build:
they exist so that the transposition can be proved by the tests the Django
security team wrote for it.

| CVE | Django patch | Test patch | Test modules |
|---|---|---|---|
| CVE-2026-15307 | `01-CVE-2026-15307.patch` | `CVE-2026-15307-tests.patch` | `gis_tests` |
| CVE-2026-15830 | `02-CVE-2026-15830.patch` | `CVE-2026-15830-tests.patch` | `gis_tests` |
| CVE-2026-15337 | `03-CVE-2026-15337.patch` | `CVE-2026-15337-tests.patch` | `i18n` |
| CVE-2026-7666  | `04-CVE-2026-7666.patch`  | `CVE-2026-7666-tests.patch`  | `mail` |

The test patches must be applied in this order (15830 edits files that 15307
already touched). Two of them needed adapting to 4.2 (import lists; and the
geoadmin test uses `admin_site._registry[City]` because
`AdminSite.get_model_admin()` only exists from Django 5.0); the header of each
file says what changed.

## Why inside the image

`mail` and `i18n` run anywhere, but `gis_tests` exercises GEOS and GDAL, and
CVE-2026-15830 is precisely a limit that keeps input away from a GEOS crash:
the GEOS build on a developer machine is not the one the image ships, so the
run that counts is the one inside the built image. `gis_tests` also needs a
spatial database; the sdist only ships `test_sqlite.py`, so `test_postgis.py`
here points the suite at the PostGIS of the `instancia_r` pod
(`127.0.0.1:5432`, user `postgres` -- the `geonode` role cannot create databases
or the `postgis` extension). The suite creates and drops its own
`test_django_origin_tests*` databases and touches nothing else.

The password is read from the environment variable `POSTGRES_PASSWORD` and is
never written to a file in this repository. Take it from the `env_postgis`
block of `inteligeo-deploy/instancia_r/pod.yaml` -- note that a key with the
same name appears earlier in that file, in `env_geonode`, with a different
value (the `geonode` role's).

## How to run

Everything is done by `run-origin-tests.sh`; the host needs only `podman`,
`tar` and `patch`:

```bash
# the env_postgis password, read from pod.yaml without echoing it
export POSTGRES_PASSWORD=$(awk '/name: env_postgis/{f=1} f&&/POSTGRES_PASSWORD:/{print $2; exit}' \
    ../../../../inteligeo-deploy/instancia_r/pod.yaml)

sh run-origin-tests.sh /tmp/django-origin-tests localhost/mirandadam/geonode-base:5.5.4 both
```

The script:

1. downloads `django-4.2.30.tar.gz` into the work folder with the image's own
   `pip` (`pip download --no-deps --no-binary :all: Django==4.2.30`);
2. unpacks its `tests/` tree three times -- pristine, with the four test
   patches applied with `patch -p1 --fuzz=0`, and with the CVE-2026-15307
   test patch alone (used by one baseline run, see below) -- and copies
   `test_postgis.py` next to `runtests.py`;
3. runs, in a throwaway container per run
   (`podman run --rm --network host -e POSTGRES_PASSWORD -v <tests>:/tests <image>`),
   `pip install -r tests/requirements/py3.txt` (minus `pylibmc` and
   `pywatchman`, which need system libraries the image lacks and are not used
   by these modules) and then
   `python /tests/runtests.py --settings=test_postgis --noinput -v 2 <modules>`
   (`mail i18n gis_tests`, or the narrower list of a baseline run, see below);
4. writes `results/<run>.txt` (full output) and `results/<run>.failures`
   (sorted list of failing tests) in the work folder.

Modes (third argument):

- `patched` (default): the image as built, patched tests.
- `baseline`: the image always ships the patches, so a baseline is made by
  running `pip install --force-reinstall --no-deps Django==4.2.30` inside the
  throwaway container before the tests (the image itself is untouched). Four
  runs: `baseline-pristine-tests` (pristine tests, all three modules), which
  gives the list of failures that pre-exist the patches, and three with the
  patched tests, in which every new test must fail. Three, because on
  unpatched Django the patched tests cannot run in one go: `runtests.py`
  installs every `gis_tests` app whenever a `gis_tests` label is given, and
  the CVE-2026-15830 test patch adds a model field with the new
  `max_geom_collections` keyword to `gis_tests/geoapp/models.py`, so a run
  that includes `gis_tests` aborts while importing the apps, before any test
  runs. Hence `baseline-patched-tests-mail-i18n` (`mail i18n`, no gis app
  installed), `baseline-patched-tests-gis-15307` (`gis_tests` with the
  CVE-2026-15307 test patch alone) and `baseline-patched-tests-gis-all`
  (`gis_tests` with all test patches: the abort, kept as the evidence that
  the CVE-2026-15830 tests need patch `02`).
- `both`: the five runs above.

Other modules can be chosen with `MODULES="mail i18n"` for the pristine and
`patched` runs (the three baseline runs with the patched tests have their
module lists fixed); a different PostGIS with `POSTGRES_HOST`,
`POSTGRES_PORT`, `POSTGRES_USER`.

## Acceptance criterion

Compare the `.failures` files:

- every test added or changed by the test patches fails in the
  `baseline-patched-tests-*` runs and passes in `patched`. Where the new
  tests import a name the Django patch creates, the whole test module fails
  to import (`i18n.tests` for CVE-2026-15337, `gis_tests.geoapp.tests` for
  CVE-2026-15307) or the run aborts at app import (CVE-2026-15830, see
  above); that counts as failing, and is the only baseline the origin tests
  allow for those cases;
- apart from those, `patched` has exactly the same failing tests as
  `baseline-pristine-tests`.

The run's command, counts and date go into the "Regression tests" paragraph of
each `.patch` header in the parent folder and into the disposition table of the
repository README.

Preliminary host run of 2026-09-21 (Python 3.12.3, `--settings=test_sqlite`,
modules `mail i18n` only): 417 tests OK before, 419 OK after (the two new
tests), and with the patched tests on unpatched Django the three changed
`mail` tests fail and `i18n` does not import. `gis_tests` was deliberately not
run on the host.

## Result of the run inside the image (2026-09-21)

`sh run-origin-tests.sh <workdir> localhost/mirandadam/geonode-base:5.5.4 both`
on the image built that day (Django 4.2.30 patched, GEOS 3.14.1, GDAL 3.13.2,
Python 3.12.3, container running as root) against the `instancia_r` PostGIS
(PostgreSQL 16.9, PostGIS 3.5.3, GEOS 3.13.1):

| Run | Django | Tests | Modules | Result |
|---|---|---|---|---|
| `baseline-pristine-tests` | unpatched | pristine | `mail i18n gis_tests` | Ran 977, FAILED (failures=4, errors=3, skipped=21) |
| `baseline-patched-tests-mail-i18n` | unpatched | patched | `mail i18n` | Ran 325, FAILED (failures=3, errors=2) |
| `baseline-patched-tests-gis-15307` | unpatched | 15307 patch only | `gis_tests` | Ran 531, FAILED (failures=3, errors=4, skipped=19) |
| `baseline-patched-tests-gis-all` | unpatched | patched | `gis_tests` | aborted at app import: `TypeError: Field.__init__() got an unexpected keyword argument 'max_geom_collections'` |
| `patched` | patched (the image) | patched | `mail i18n gis_tests` | Ran 1005, FAILED (failures=4, errors=3, skipped=21) |

The 28 tests the test patches add (1005 - 977) all pass in `patched`; on
unpatched Django they fail as follows:

- CVE-2026-7666 (`mail`): `test_reopen_replaces_partial_connection` (new)
  and `test_email_tls_attempts_starttls` fail (the connection is not `None`
  after a failed STARTTLS), `test_server_open` errors (no
  `_partial_connection` attribute).
- CVE-2026-15337 (`i18n`): `i18n.tests` fails to import
  (`translation_catalog_exists` does not exist before patch `03`), so
  `test_check_for_language_lang_code_max_length` cannot run.
- CVE-2026-15307 (`gis_tests`, 6 new tests): `test_raster_lookup_not_allowed`
  errors in both `geoadmin` classes (`ValueError` instead of
  `SuspiciousOperation`); `gis_tests.geoapp.tests` fails to import
  (`DisallowedRasterLookup` does not exist before patch `01`), so
  `test_lookup_rejects_writing_or_fetching_rasters`,
  `test_lookup_allows_writing_raster_from_bytes` and
  `test_lookup_allows_geos_geometry_string` cannot run; `test_raster_types`
  (`test_geoforms`) already passes on 4.2.30 (the form field rejected those
  values before the patch).
- CVE-2026-15830 (`gis_tests`, 20 new tests: 8 in `test_geos_limit.py`, 4 in
  `test_geoforms.py`, 4 in `geoapp/tests.py`, 3 in `test_fields.py`, 1 in
  `rasterapp`): the run aborts at app import, as in the table.

The 7 failures of `baseline-pristine-tests` are exactly the 7 of `patched`
(`diff` of the two `.failures` files is empty); none is touched by the
patches and each comes from the environment being newer than the one Django
4.2 was tested with, or from running as root:

- `gis_tests.geos_tests.test_io.GEOSIOTest.test02_wktwriter`,
  `test_wkt_writer_precision`, `test_wkt_writer_trim`: GEOS 3.12+ changed
  the `WKTWriter` defaults (trim on, precision), which Django only follows
  from 5.0;
- `gis_tests.gdal_tests.test_srs.SpatialRefTest.test_unicode`: `OGR failure`
  importing a WKT with a non-ASCII name on GDAL 3.13;
- `gis_tests.geoapp.tests.GeoModelTest.test_empty_geometries`: PostGIS 3.5
  refuses an empty geometry with a Z dimension in a 2D column;
- `gis_tests.geoapp.tests.GeoLookupTest.test_relate_lookup`: the `relate`
  mask no longer matches with GEOS 3.13 inside PostGIS;
- `i18n.test_compilation.PoFileTests.test_no_write_access`: the container
  runs as root, for whom a read-only `.po` file is still writable.
