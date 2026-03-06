ARG BASE_IMAGE=elog-base-debian12
FROM ${BASE_IMAGE}

# No extra dependencies needed for elog_lib tests (base image has coreutils)

COPY files/ /opt/files/
COPY tests/ /opt/tests/

WORKDIR /opt/tests
CMD ["bats", "--formatter", "tap", "/opt/tests/"]
