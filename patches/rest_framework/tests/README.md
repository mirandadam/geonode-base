# Origin regression tests for the transposed Django REST framework patch

`../CVE-2026-73228.patch` carries the fix of DRF 3.17.2 for CVE-2026-73228
(`request.data` bypassing `DATA_UPLOAD_MAX_MEMORY_SIZE` for JSON and urlencoded
bodies) transposed to the 3.15.2 the image installs (dynamic-rest 2.3.0, which
GeoNode 4.3.1 uses, refuses DRF 3.16+). The origin commit also changed DRF's own
`tests/test_request.py`; that part is `CVE-2026-73228-tests.patch`, re-diffed
against the `tests/` tree of the `djangorestframework-3.15.2` sdist. It is not
applied in the image build: it exists so that the transposition can be proved by
the tests the DRF maintainers wrote for it. One context line was adapted (the
header of the file says which); the added and removed test lines are the origin's.

## How to run

The suite needs only sqlite. On a host with Python 3.12 and network access:

```bash
W=/tmp/drf-origin-tests; mkdir -p $W && cd $W
python3 -m venv venv
venv/bin/pip download --no-deps --no-binary :all: djangorestframework==3.15.2
curl -sSL https://github.com/encode/django-rest-framework/archive/refs/tags/3.15.2.tar.gz | tar xz
venv/bin/pip install Django==4.2.30 djangorestframework==3.15.2 setuptools \
    -r django-rest-framework-3.15.2/requirements/requirements-testing.txt \
    -r django-rest-framework-3.15.2/requirements/requirements-optionals.txt
tar xzf djangorestframework-3.15.2.tar.gz
# tests/ and the pytest section of setup.cfg only: the sdist root also holds a
# rest_framework/ that would shadow the installed one
mkdir pristine patched && for d in pristine patched; do
    cp -r djangorestframework-3.15.2/tests djangorestframework-3.15.2/setup.cfg $d/; done
(cd patched && patch -p1 --fuzz=0 < <path to this folder>/CVE-2026-73228-tests.patch)
# a patched copy of the installed package, put first on PYTHONPATH for run (c)
mkdir drf && cp -r venv/lib/python3.12/site-packages/rest_framework drf/
(cd drf && patch -p1 --fuzz=0 < <path to this folder>/../CVE-2026-73228.patch)

(cd pristine && ../venv/bin/python -m pytest tests/test_request.py -q)                      # (a)
(cd patched  && ../venv/bin/python -m pytest tests/test_request.py -q)                      # (b)
(cd patched  && PYTHONPATH=$W/drf ../venv/bin/python -m pytest tests/test_request.py -q)    # (c)
```

Inside the built image the same three runs prove that the patch applies to the
installed tree: in a throwaway container
(`podman run --rm --network host -v <this folder>/..:/patch:ro -v $W:/work <image>`),
`cd /usr/src/venv/lib/python3.12/site-packages && patch -p1 --fuzz=0 < /patch/CVE-2026-73228.patch`
(the image already ships the patch once it is built with it; for the baseline
runs skip this step), `pip install -r requirements-testing.txt` **without the
`attrs==22.1.0` pin** (it breaks the image's anyio and jsonschema), then
`python -m pytest tests/test_request.py -q` in `/work/pristine` and `/work/patched`.

## Acceptance criterion

- (a) pristine DRF, pristine tests: all of `test_request.py` passes;
- (b) pristine DRF, patched tests: exactly the two `TestDataUploadMaxMemorySize`
  oversized-body tests and `test_duplicate_request_json_data_access` fail (the
  first two get a parsed body instead of `RequestDataTooBig`; the third gets
  `RawPostDataException`, because the unpatched code consumes the stream instead
  of caching the body); the other three new tests already pass on 3.15.2
  (multipart and custom parsers keep the streaming path, small bodies parse);
- (c) patched DRF, patched tests: everything passes, and the rest of the suite
  (`tests/`) has the same result as before the patch plus the five new tests.

## Result (2026-09-21)

Host: Python 3.12.3, Django 4.2.30, DRF 3.15.2, pytest 7.4.4, pytest-django
4.14.0, requirements-testing.txt and requirements-optionals.txt of the 3.15.2 tag.
Image: `localhost/mirandadam/geonode-base:5.5.4` built that day (before this
patch existed; the patch was applied inside the throwaway container), Python
3.12.3, Django 4.2.30, DRF 3.15.2, same pytest.

| Run | DRF | Tests | Host, `test_request.py` | Image, `test_request.py` |
|---|---|---|---|---|
| (a) | pristine | pristine | 26 passed | 26 passed |
| (b) | pristine | patched | 3 failed, 28 passed | 3 failed, 28 passed |
| (c) | patched | patched | 31 passed | 31 passed |

The three failures of (b) are the ones the criterion names. Whole suite
(`tests/`): host 1472 passed, 65 skipped before and 1477 passed, 65 skipped
after; image 1 failed, 1472 passed, 64 skipped before and 1 failed, 1477 passed,
64 skipped after -- the one failure is
`test_description.py::TestViewNamesAndDescriptions::test_markdown`, present
without the patch, from the image's newer Markdown/Pygments. Five new tests, all
passing with the patch.
