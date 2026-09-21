# Django test-suite settings for running the origin regression tests of the
# transposed CVE patches against a PostGIS server, from inside the built image.
# The sdist only ships test_sqlite.py, and the gis_tests module needs a
# spatial database; this mirrors test_sqlite.py (two aliases, fast hasher,
# USE_TZ=False) with the PostGIS engine. Copy it next to tests/runtests.py and
# pass --settings=test_postgis. See README.md in this folder.
#
# Connection: the instancia_r PostGIS, published on 127.0.0.1:5432, as the
# superuser `postgres` (the `geonode` role cannot create databases or the
# postgis extension). The password is never written to a file: it is read from
# the POSTGRES_PASSWORD environment variable, whose value comes from the
# `env_postgis` block of inteligeo-deploy/instancia_r/pod.yaml.
import os

_PASSWORD = os.environ["POSTGRES_PASSWORD"]  # KeyError on purpose if unset.
_HOST = os.environ.get("POSTGRES_HOST", "127.0.0.1")
_PORT = os.environ.get("POSTGRES_PORT", "5432")
_USER = os.environ.get("POSTGRES_USER", "postgres")

DATABASES = {
    "default": {
        "ENGINE": "django.contrib.gis.db.backends.postgis",
        "NAME": "django_origin_tests",  # test DB becomes test_django_origin_tests
        "USER": _USER,
        "PASSWORD": _PASSWORD,
        "HOST": _HOST,
        "PORT": _PORT,
    },
    "other": {
        "ENGINE": "django.contrib.gis.db.backends.postgis",
        "NAME": "django_origin_tests_other",
        "USER": _USER,
        "PASSWORD": _PASSWORD,
        "HOST": _HOST,
        "PORT": _PORT,
    },
}

SECRET_KEY = "django_tests_secret_key"

# Use a fast hasher to speed up tests.
PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.MD5PasswordHasher",
]

DEFAULT_AUTO_FIELD = "django.db.models.AutoField"

USE_TZ = False
