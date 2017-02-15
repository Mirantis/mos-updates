#!/usr/bin/env python


import os

from setuptools import setup

dist = "/roos/mos-updates"
data_files = []
for r, ds, fs in os.walk('./'):
    if '.git' not in r:
        data_files.append((
            os.path.join(dist,r.strip('./')),
            [os.path.join(r, f) for f in fs]
        ))

setup(
    name='mos-updates',
    version='1.0.0',
    author='Mirantis',
    author_email='mos-maintenance@mirantis.com',
    license='Apache2',
    data_files=data_files,
    include_package_data=True
)

