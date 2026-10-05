# A manylinux image with the V compiler and vcraft already present.
#
# Derived from the official PyPA image, so the interpreters, auditwheel and the
# toolchain come from there rather than being assembled here. What this adds is
# exactly two things: V, built from source, and vcraft, compiled from the
# repository this file lives in.
#
# V is built from source rather than taken from its release for one reason: the
# release binary links a newer glibc than this image provides, so it does not run
# here at all. A V compiled on this image links this image's glibc, which is also
# what makes the extensions it compiles genuinely manylinux-compatible rather than
# merely tagged so.
#
# Built and pushed by `.github/workflows/release-images.yml`. Locally:
#
#   docker build -f docker/manylinux.Dockerfile -t vcraft-manylinux:local .
#   docker run --rm -v "$PWD:/work" -w /work vcraft-manylinux:local \
#     vcraft build --target linux-x86_64-gnu --manylinux 2_28
#
# The base defaults to x86_64. For aarch64 pass
# `--build-arg BASE=quay.io/pypa/manylinux_2_28_aarch64` on an aarch64 host, or
# build with `docker buildx` for the other architecture.
ARG BASE=quay.io/pypa/manylinux_2_28_x86_64
FROM ${BASE}

# V is pinned to a commit, not to a tag: the release tag predates the V this
# repository was developed against, and a tag's V does not understand the flags the
# build scripts pass. When the host's V moves, move both commits to ones from just
# before its date -- the `vc` bootstrap one in particular, which has to stay
# contemporary with V itself.
ARG V_COMMIT=0137eb5d8ebc5d183259309ed08ea06ba9bc27d6
# The `vc` bootstrap snapshot. A newer bootstrap enforces checker rules the V sources
# predate, and the build fails on the compiler's own sources with errors about the
# wrong strictness.
ARG VC_COMMIT=8af812feb76c678abd86a8e682fd9ab2790e519c

# git and make for the V source build; the C toolchain is already in the base image.
RUN yum install -y git make 2>/dev/null || microdnf install -y git make

# A shallow fetch by SHA rather than a branch: the commit is what matters, and no
# branch points at it. GitHub serves a fetch by SHA for any reachable commit.
RUN git init -q /opt/v-src \
    && cd /opt/v-src && git remote add origin https://github.com/vlang/v.git \
    && git fetch -q --depth 1 origin "${V_COMMIT}" && git checkout -q FETCH_HEAD \
    && git clone https://github.com/vlang/vc.git /opt/v-src/vc \
    && cd /opt/v-src/vc && git checkout -q "${VC_COMMIT}"

# tcc and Boehm, built from source with the system compiler. The prebuilt tcc bundle
# is not used at all: its compiler binary does not run on an older glibc, and its
# `libgc.a` then fails to link with an `undefined reference to sigsetjmp` and nothing
# naming the bundle. Building natively makes both match this image's libc.
#
# tinycc first, because V prefers it as its fast compiler and a missing one turns
# every build log into a fallback warning. Then Boehm's amalgamation, which V ships as
# C source, archived exactly where V looks for it. The defines mirror the ones V
# itself passes when it compiles the amalgamation: thread-local allocation needs
# GC_THREADS, and the prebuilt archives this replaces were built with thread-local
# allocation.
RUN git clone https://repo.or.cz/tinycc.git /opt/tinycc \
    && cd /opt/tinycc \
    && ./configure \
        --prefix=/opt/v-src/thirdparty/tcc \
        --bindir=/opt/v-src/thirdparty/tcc \
        --crtprefix=/opt/v-src/thirdparty/tcc/lib:/usr/lib/x86_64-linux-gnu:/usr/lib64:/usr/lib:/lib/x86_64-linux-gnu:/lib:/lib64 \
        --libpaths=/opt/v-src/thirdparty/tcc/lib/tcc:/opt/v-src/thirdparty/tcc/lib:/usr/lib/x86_64-linux-gnu:/usr/lib64:/usr/lib:/lib/x86_64-linux-gnu:/lib:/lib64:/usr/local/lib/x86_64-linux-gnu:/usr/local/lib \
        --cc=gcc --extra-cflags=-O2 --config-bcheck=yes --config-backtrace=yes \
    && make -j2 && make install \
    && mkdir -p /opt/v-src/thirdparty/tcc/lib \
    && gcc -O2 -fPIC -DGC_THREADS=1 -DTHREAD_LOCAL_ALLOC=1 -DALL_INTERIOR_POINTERS=1 \
        -DGC_BUILTIN_ATOMIC=1 -I/opt/v-src/thirdparty/libgc/include \
        -c /opt/v-src/thirdparty/libgc/gc.c -o /opt/v-src/thirdparty/tcc/lib/libgc.o \
    && ar rcs /opt/v-src/thirdparty/tcc/lib/libgc.a /opt/v-src/thirdparty/tcc/lib/libgc.o \
    && rm /opt/v-src/thirdparty/tcc/lib/libgc.o
RUN cd /opt/v-src && make local=1 -j2 \
    && ln -s /opt/v-src/v /usr/local/bin/v \
    && v version

# vcraft, compiled from the repository. The build context is the repo root, so a
# release builds the image from the tag it is releasing and a local build tests
# whatever is checked out.
#
# VCRAFT_REF is the git revision being built, passed as `--build-arg`. A different
# revision always rebuilds vcraft without rebuilding V, so a stale binary can never
# ship with fresh sources.
ARG VCRAFT_REF=unknown
RUN test -n "$VCRAFT_REF"
COPY . /src/vcraft
RUN cd /src/vcraft && ./scripts/build-vcraft.sh && bin/vcraft version

ENV PATH="/src/vcraft/bin:${PATH}"
WORKDIR /work
