# A musllinux image with a musl toolchain, CPython headers, V and vcraft.
#
# Alpine is musl natively, so there is no cross-compilation involved: the compiler,
# the headers and the interpreter all agree with each other, which is the property a
# musllinux wheel needs. What the base image lacks is a toolchain, a V compiler and
# vcraft, and those are the three things this adds.
#
# V is built from source, for the same reason as in manylinux.Dockerfile and one more:
# the V release binary links glibc and does not run on musl at all.
#
# Built and pushed by `.github/workflows/release-images.yml`. Locally:
#
#   docker build -f docker/musllinux.Dockerfile -t vcraft-musllinux:local .
#   docker run --rm -v "$PWD:/work" -w /work vcraft-musllinux:local \
#     vcraft build --target linux-x86_64-musl --musllinux 1_2
#
# For aarch64 the same file builds on an aarch64 host; there is no emulation involved
# anywhere, because emulating a compiler is how a build becomes unreproducible.
FROM alpine:3.23

# Same pins as manylinux.Dockerfile; see there for why they are commits and not tags.
ARG V_COMMIT=36be92642c49a8fe9213ea4b96c6bf56b67b668c
ARG VC_COMMIT=6851aaf3f9e696b30b26e406f16095b0002acaab

# A C toolchain, CPython with its headers, and the libraries V links against.
# `gc-dev` is Boehm, which V links by default; without it every V build fails at the
# link step with a missing `-lgc` and nothing naming the package that provides it.
RUN apk add --no-cache \
        python3 python3-dev py3-pip \
        gcc musl-dev linux-headers \
        gc-dev libffi-dev openssl-dev \
        curl bash git make

# A shallow fetch by SHA rather than a branch: the commit is what matters, and no
# branch points at it.
RUN git init -q /opt/v-src \
    && cd /opt/v-src && git remote add origin https://github.com/vlang/v.git \
    && git fetch -q --depth 1 origin "${V_COMMIT}" && git checkout -q FETCH_HEAD \
    && git clone https://github.com/vlang/vc.git /opt/v-src/vc \
    && cd /opt/v-src/vc && git checkout -q "${VC_COMMIT}"

# No tcc and no bundled Boehm here, unlike manylinux: on a musl host V infers the
# libc itself and links the system's Boehm (`gc-dev` above) instead of the bundled
# archive, so there is nothing native to build. V falls back from the missing tcc to
# the system compiler with a warning, which is noise in a build log but not an error.
RUN cd /opt/v-src && make local=1 -j"$(nproc)" \
    && ln -s /opt/v-src/v /usr/local/bin/v \
    && v version

# vcraft, compiled from the repository. Pass the revision as `--build-arg
# VCRAFT_REF=$(git rev-parse HEAD)`: a stale binary with fresh sources is silent and
# catastrophic here, so a different revision always rebuilds this layer.
ARG VCRAFT_REF=unknown
RUN test -n "$VCRAFT_REF"
COPY . /src/vcraft
RUN cd /src/vcraft && ./scripts/build-vcraft.sh && bin/vcraft version

ENV PATH="/src/vcraft/bin:${PATH}"
WORKDIR /work
