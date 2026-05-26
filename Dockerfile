FROM stagex/pallet-gcc-gnu-gnu:sx2026.05.0@sha256:c06b4e5e490d7fdc77951510b5256f889a8bd51c6fa9d6c41c7f6c4cea88f35c AS builder
COPY --from=stagex/core-curl:sx2026.05.0@sha256:7a95abfe88eea0a7afd614d219e0b0f11fd77ce257046489baa0fbbf2fc6c088 . /
COPY --from=stagex/core-openssl:sx2026.05.0@sha256:9a8cac9cacc5fdcbd09f0cf36b1895f71c02fb92fc9806fae824de1d18f60bb0 . /
COPY --from=stagex/core-ca-certificates:sx2026.05.0@sha256:7773dae6630aa3bdcc82cfec6c9265c0c501aaf0af67cc73631b09e1cff1b094 . /
COPY --from=stagex/user-patch:sx2026.05.0@sha256:1d4428893f0ea9abfabc1fb5e365c5593fe10c6ed8ffc592d6528157a4299942 . /
COPY --from=stagex/core-cmake:sx2026.05.0@sha256:ac023f4f1dfb1f7fb649c63de4f54f072ca206f43311807b1e1fd21edecaf8fe . /
COPY --from=stagex/core-ncurses:sx2026.05.0@sha256:90cc5d029c5073405f9db39c88b9509b8959bbd8f19d8cd02c20e9350cc40254 . /

# builder stage
FROM ubuntu:26.04 AS builder

RUN set -ex && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get --no-install-recommends --yes install \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        git \
        python3 \
        make \
        libtool \
        pkg-config \
        gperf \
        libusb-1.0-0-dev \
        libhidapi-dev \
        libprotobuf-dev \
        protobuf-compiler \
        libssl-dev \
        libunbound-dev \
        libboost-all-dev \
        libsodium-dev \
        libzmq3-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .

ARG NPROC
RUN set -ex && \
    git submodule init && \
    git submodule update && \
    echo "Submodules initialized and updated" && \
    rm -rf build && \
    mkdir build && \
    cd build && \
    cmake .. -DARCH="default" -DBUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release && \
    echo "CMake configuration completed" && \
    if [ -z "$NPROC" ] ; then make -j$(nproc) ; else make -j$NPROC ; fi && \
    echo "Build completed"

RUN make -C contrib/depends -j$(nproc) HOST="${TARGET}" NO_WALLET=1 NO_READLINE=1

RUN cmake --toolchain "contrib/depends/${TARGET}/share/toolchain.cmake" -S . -B build \
        -DSTACK_TRACE=OFF \
        -DBUILD_WALLET=OFF \
        -DUSE_READLINE=OFF \
        -DUSE_DEVICE_TREZOR=OFF \
        -DSTATIC_FLAGS="-static-pie" && \
    cmake --build build --target daemon --parallel $(nproc)

RUN set -ex && \
    apt-get update && \
    apt-get --no-install-recommends --yes install ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/build /usr/local/bin/

# Create monero user
RUN adduser --system --group --disabled-password monero && \
    mkdir -p /wallet /home/monero/.bitmonero && \
    chown -R monero:monero /home/monero/.bitmonero && \
    chown -R monero:monero /wallet

# Contains the blockchain
VOLUME /home/monero/.bitmonero

# Generate your wallet via accessing the container and run:
# cd /wallet
# monero-wallet-cli
VOLUME /wallet

EXPOSE 18080
EXPOSE 18081

# switch to user monero
USER monero

ENTRYPOINT ["monerod"]
CMD ["--p2p-bind-ip=0.0.0.0", "--p2p-bind-port=18080", "--rpc-bind-ip=0.0.0.0", "--rpc-bind-port=18081", "--non-interactive", "--confirm-external-bind"]