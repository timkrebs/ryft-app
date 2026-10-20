#!/bin/sh
# The one build number formula, for `make archive` and CI alike (docs/CI.md →
# Versions and build numbers): UTC date, a dot, UTC time to the second, e.g.
# 20261020.094512. It only goes up, wherever the build is made, with no counter
# to share. Two parts keep each integer small for App Store Connect's
# component-wise comparison.
date -u +%Y%m%d.%H%M%S
